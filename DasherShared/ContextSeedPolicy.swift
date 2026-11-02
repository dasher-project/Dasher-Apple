import Foundation

/// RFC 0015 (Amended): Sentence-window trimming for Direct Mode target reads.
/// Mirrors `Dasher.Windows.Services.SentenceWindow`.
///
/// Target-field reads are trimmed to the sentence around the caret (up to
/// `maxLookback` UTF-16 code units back from the caret) before seeding the
/// language model so the shadow-compare stays in lockstep during typing and
/// re-seeds remain lightweight.
public enum SentenceWindow {

    /// Maximum lookback (in UTF-16 code units) from the caret for a sentence boundary.
    public static let maxLookback = 200

    /// UTF-16 code units that terminate a sentence (`.`, `!`, `?`, `\n`, `\r`, `;`, `:`).
    private static let boundaryUnits: Set<UInt16> = [
        0x002E, // '.'
        0x0021, // '!'
        0x003F, // '?'
        0x000A, // '\n'
        0x000D, // '\r'
        0x003B, // ';'
        0x003A, // ':'
    ]

    private static func isHighSurrogate(_ unit: UInt16) -> Bool {
        (0xD800...0xDBFF).contains(unit)
    }

    private static func isLowSurrogate(_ unit: UInt16) -> Bool {
        (0xDC00...0xDFFF).contains(unit)
    }

    private static func isUTF16Whitespace(_ unit: UInt16) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    /// Extract the sentence context ending at `caretUTF16`: from just after the
    /// last sentence boundary before the caret (or `maxLookback` UTF-16 units
    /// back, whichever is closer), skipping leading whitespace after the boundary
    /// and never splitting a UTF-16 surrogate pair at either end.
    public static func trim(_ text: String, caretUTF16: Int) -> (text: String, caretUTF16: Int) {
        let units = Array(text.utf16)
        let len = units.count
        guard len > 0 && caretUTF16 > 0 else {
            return ("", 0)
        }

        var caret = max(0, min(caretUTF16, len))
        let lookbackStart = max(0, caret - maxLookback)

        var start = lookbackStart
        for i in stride(from: caret - 1, through: lookbackStart, by: -1) {
            if boundaryUnits.contains(units[i]) {
                start = i + 1
                break
            }
        }

        // Skip leading whitespace after the boundary
        while start < caret && isUTF16Whitespace(units[start]) {
            start += 1
        }

        // Start-side surrogate guard: if the 200-unit lookback cap lands on the
        // low half of a surrogate pair, slide one UTF-16 unit forward.
        if start < caret && isLowSurrogate(units[start]) {
            start += 1
        }

        // End-side surrogate guard: if the caret splits a surrogate pair, step
        // back one UTF-16 unit so the window never ends with an orphan high surrogate.
        if caret > start && isHighSurrogate(units[caret - 1]) {
            caret -= 1
        }

        guard start < caret else {
            return ("", 0)
        }

        let slice = Array(units[start..<caret])
        let trimmed = String(decoding: slice, as: UTF16.self)
        return (trimmed, slice.count)
    }
}

/// What the caller should do after comparing the engine buffer with a target-field read.
public enum ContextSeedAction: Equatable, Sendable {
    case seed
    case skip
}

/// Result of `ContextSeedPolicy.decide`.
public struct ContextSeedDecision: Equatable, Sendable {
    public let action: ContextSeedAction
    public let reason: String
    public let text: String
    public let caretUTF16: Int

    public static func skip(_ reason: String) -> ContextSeedDecision {
        ContextSeedDecision(action: .skip, reason: reason, text: "", caretUTF16: 0)
    }

    public static func seed(_ text: String, caretUTF16: Int) -> ContextSeedDecision {
        ContextSeedDecision(action: .seed, reason: "", text: text, caretUTF16: caretUTF16)
    }
}

/// Direct-entry context-seed decision (RFC 0015): compares the engine's edit
/// buffer against a target-field AX read and decides whether to re-seed.
/// Mirrors `Dasher.Windows.Services.ContextSeedPolicy`.
public enum ContextSeedPolicy {

    /// Maximum full-text lag (UTF-16 code units, after normalisation) still
    /// attributed to a stale AX read.
    public static let maxLagChars = 32

    /// Minimum overlap (UTF-16 units) between the engine's head and the target
    /// read's tail for a "stale read" verdict.
    public static let minLagOverlapChars = 2

    public static func decide(
        engineFullText: String,
        targetFullText: String,
        targetCaretUTF16: Int
    ) -> ContextSeedDecision {
        let seedText = normalizeInvisible(SentenceWindow.trim(targetFullText, caretUTF16: targetCaretUTF16).text)
        let engineSentence = normalizeInvisible(SentenceWindow.trim(engineFullText, caretUTF16: engineFullText.utf16.count).text)

        let engineFull = normalizeInvisible(engineFullText).replacingOccurrences(of: "\r", with: "")
        let engineUnits = Array(engineFull.utf16)

        // Slice at the caret BEFORE normalising: normalisation removes characters
        // (\r, zero-width) and would shift the caret's UTF-16 index.
        // Snap off a low surrogate so mid-surrogate caret offsets do not decode into U+FFFD.
        let targetRawUnits = Array(targetFullText.utf16)
        var clampedCaret = max(0, min(targetCaretUTF16, targetRawUnits.count))
        if clampedCaret > 0 && clampedCaret < targetRawUnits.count &&
           (0xDC00...0xDFFF).contains(targetRawUnits[clampedCaret]) &&
           (0xD800...0xDBFF).contains(targetRawUnits[clampedCaret - 1]) {
            clampedCaret -= 1
        }
        let beforeRaw = String(decoding: Array(targetRawUnits[0..<clampedCaret]), as: UTF16.self)
        let afterRaw = String(decoding: Array(targetRawUnits[clampedCaret..<targetRawUnits.count]), as: UTF16.self)

        let targetToCaret = normalizeInvisible(beforeRaw).replacingOccurrences(of: "\r", with: "")
        let targetAfterCaret = normalizeInvisible(afterRaw).replacingOccurrences(of: "\r", with: "")
        let targetToCaretUnits = Array(targetToCaret.utf16)
        let targetAfterCaretUnits = Array(targetAfterCaret.utf16)

        // 1. Paragraph-mark mirror: a Dasher paragraph leaves the engine buffer
        // ending "\n", while the follow-up target read may sit before or at the
        // paragraph mark. Require engineUnits.count > 1 so a bare "\n" buffer
        // does not match an empty suffix on every unrelated field.
        if engineUnits.count > 1 && engineFull.hasSuffix("\n") {
            let mirrorUnits = Array(engineUnits.dropLast(1))
            if utf16EndsWith(targetToCaretUnits, suffix: mirrorUnits) {
                return .skip("paragraph-mark mirror — engine's newline is the target's; buffers in sync")
            }
        }

        // 2. Target-lag skip: when the engine buffer ends with "\n" and
        // targetToCaret already contains the whole engine buffer plus external
        // text past it, the engine is behind (user typed externally after our
        // paragraph), so disable the lag loop.
        let targetHasWholeEngine = engineFull.hasSuffix("\n") &&
            targetToCaretUnits.count > engineUnits.count &&
            targetToCaret.contains(engineFull)

        let maxLag = min(maxLagChars, engineUnits.count - minLagOverlapChars)
        if !targetHasWholeEngine && maxLag >= 1 {
            for lag in 1...maxLag {
                let prefixLen = engineUnits.count - lag
                let enginePrefix = Array(engineUnits[0..<prefixLen])
                let enginePending = Array(engineUnits[prefixLen..<engineUnits.count])
                if utf16EndsWith(targetToCaretUnits, suffix: enginePrefix) &&
                   !utf16StartsWith(targetAfterCaretUnits, prefix: enginePending) {
                    return .skip("target read lags engine output by \(lag) char(s) — waiting for it to reflect")
                }
            }
        }

        // 3. Sentence-equal skip: covers both mid-sentence and sentence-boundary
        // cases (both sides trim to "").
        if seedText == engineSentence {
            return .skip("sentence unchanged — engine already at a matching position (identical earlier sentence possible)")
        }

        // 4. Engine-ahead skip (sentence-level): the engine sentence starts with
        // the non-empty target sentence — our output is not reflected in AX yet.
        let seedUnits = Array(seedText.utf16)
        let engineSentenceUnits = Array(engineSentence.utf16)
        if !seedUnits.isEmpty &&
           engineSentenceUnits.count > seedUnits.count &&
           utf16StartsWith(engineSentenceUnits, prefix: seedUnits) {
            return .skip("engine ahead of target read (\(engineSentenceUnits.count) vs \(seedUnits.count) chars) — output not yet reflected")
        }

        // 5. Benign trailing-whitespace divergence
        if trimTrailingWhitespace(seedText) == trimTrailingWhitespace(engineSentence) {
            return .skip("sentence matches modulo trailing whitespace")
        }

        return .seed(seedText, caretUTF16: seedUnits.count)
    }

    /// Normalize invisible Unicode characters that rich-text editors insert into
    /// otherwise plain text: NBSP (`\u{00A0}`), narrow NBSP (`\u{202F}`), figure
    /// space (`\u{2007}`), thin space (`\u{2009}`) -> `' '`; zero-width space/joiners
    /// and BOM (`\u{200B}`, `\u{200C}`, `\u{200D}`, `\u{FEFF}`) -> stripped.
    public static func normalizeInvisible(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var out: [UInt16] = []
        out.reserveCapacity(s.utf16.count)
        for u in s.utf16 {
            switch u {
            case 0x00A0, 0x202F, 0x2007, 0x2009:
                out.append(0x0020) // ' '
            case 0x200B, 0x200C, 0x200D, 0xFEFF:
                break // strip
            default:
                out.append(u)
            }
        }
        return String(decoding: out, as: UTF16.self)
    }

    // MARK: - Helpers

    private static func utf16StartsWith(_ array: [UInt16], prefix: [UInt16]) -> Bool {
        guard array.count >= prefix.count else { return false }
        for i in 0..<prefix.count where array[i] != prefix[i] {
            return false
        }
        return true
    }

    private static func utf16EndsWith(_ array: [UInt16], suffix: [UInt16]) -> Bool {
        guard array.count >= suffix.count else { return false }
        let offset = array.count - suffix.count
        for i in 0..<suffix.count where array[offset + i] != suffix[i] {
            return false
        }
        return true
    }

    private static func trimTrailingWhitespace(_ s: String) -> String {
        var units = Array(s.utf16)
        while let last = units.last, let scalar = UnicodeScalar(last), CharacterSet.whitespacesAndNewlines.contains(scalar) {
            units.removeLast()
        }
        return String(decoding: units, as: UTF16.self)
    }
}
