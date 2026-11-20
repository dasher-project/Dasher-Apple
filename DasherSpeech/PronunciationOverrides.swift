import Foundation
#if os(macOS) || os(iOS)
import RustTtsWrapper
#endif

/// User pronunciation overrides (rust-tts-wrapper #125/#127, Swift surface
/// landed in 1.16.0 via #130/#135): a plain-text file teaching the wrapper
/// how words should sound —
///
///     # respell — works on every engine
///     botox = bow tocks
///     # phoneme override — precise IPA where the engine accepts it
///     nguyen = /wɪn/
///
/// The Rust wrapper applies this file automatically on every utterance for
/// engines it synthesizes (sherpa-onnx, cloud). This type owns the Dasher
/// copy of the file, points the Rust wrapper at it via
/// `TtsClient.setPronunciationsFile`, and re-applies the same respell
/// substitutions to the Apple system engine (AVSpeechSynthesizer), which
/// does not go through Rust.
public enum PronunciationOverrides {
    /// One parsed `word = value` line. `value` is a respell, or IPA when
    /// wrapped in forward slashes.
    struct Entry: Equatable, Identifiable {
        let word: String
        let respell: String?
        let ipa: String?

        var id: String { "\(word)|\(respell ?? ipa ?? "")" }

        /// The value as displayed: the respell, or the IPA between slashes.
        var displayValue: String {
            if let ipa { return "/\(ipa)/" }
            return respell ?? ""
        }
    }

    static let starterText = """
        # Pronunciation overrides — one entry per line, `word = pronunciation`.
        # Lines starting with # are comments. Edits apply on the next utterance.
        #
        # Respelling (works on every voice):
        #   botox = bow tocks
        # Exact phonemes, IPA between slashes (used where the voice supports it):
        #   nguyen = /w\u{026A}n/
        # Multi-word names are fine:
        #   san rafael = san rah fah el
        """

    // MARK: - File management

    /// Location of the overrides file inside the app's Application Support
    /// container (sandbox-safe on macOS and iOS).
    public static func fileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "Dasher", directoryHint: .isDirectory)
            .appending(path: "pronunciations.txt")
    }

    /// Make sure the file exists, writing the commented starter on first use.
    static func ensureFile() throws -> URL {
        let url = fileURL()
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            try starterText.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    /// Point the Rust wrapper at the Dasher-owned file (takes precedence
    /// over the default resolution; edits apply on the next utterance).
    public static func activate() {
        guard let url = try? ensureFile() else { return }
        #if os(macOS) || os(iOS)
        TtsClient.setPronunciationsFile(url.path)
        #endif
    }

    /// Whether the wrapper has the file loaded with at least one matching
    /// entry. False here means overrides aren't firing (bad path, or a
    /// bindings pin older than the feature).
    static var wrapperActive: Bool {
        #if os(macOS) || os(iOS)
        TtsClient.pronunciationsActive
        #else
        false
        #endif
    }

    /// The wrapper's own parse counts: entries loaded and malformed lines
    /// skipped — lets the editor flag `botox =` typos in place.
    static func wrapperStats() -> (entries: Int, skipped: Int)? {
        #if os(macOS) || os(iOS)
        let stats = TtsClient.pronunciationsStats()
        return (entries: stats.entries, skipped: stats.skipped)
        #else
        return nil
        #endif
    }

    /// Wrapper dry-run: the text after respell substitution — what a
    /// plain-text engine will speak. Used to confirm a new entry fires
    /// end-to-end without speaking.
    static func dryRun(_ text: String) -> String {
        #if os(macOS) || os(iOS)
        TtsClient.applyPronunciations(text)
        #else
        text
        #endif
    }

    static func loadText() -> String? {
        try? String(contentsOf: fileURL(), encoding: .utf8)
    }

    static func save(_ text: String) throws {
        let url = try ensureFile()
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The file line for an entry: `word = respell` or `word = /IPA/`.
    static func entryLine(_ entry: Entry) -> String {
        "\(entry.word) = \(entry.displayValue)"
    }

    /// Add (or replace, case-insensitively) an entry in the file text,
    /// preserving comments and the rest of the file.
    static func adding(_ entry: Entry, to text: String) -> String {
        var lines = removing(word: entry.word, from: text)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        lines.append(entryLine(entry))
        return lines.joined(separator: "\n") + "\n"
    }

    /// Remove every line for `entry`'s word (case-insensitive) from the file
    /// text, leaving comments and unrelated entries untouched.
    static func removing(_ entry: Entry, from text: String) -> String {
        removing(word: entry.word, from: text)
    }

    private static func removing(word: String, from text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { return true }
                let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
                return key.caseInsensitiveCompare(word) != .orderedSame
            }
            .joined(separator: "\n")
    }

    // MARK: - Parsing

    /// Parse `word = respell` / `word = /IPA/` lines; `#` lines are comments.
    /// Keys and values are single-space phrased, matching the wrapper's rules.
    static func entries(from text: String) -> [Entry] {
        var result: [Entry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }
            guard let separator = trimmed.firstIndex(of: "=") else { continue }
            let word = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty, !value.isEmpty else { continue }
            if value.count > 2, value.hasPrefix("/"), value.hasSuffix("/") {
                let ipa = String(value.dropFirst().dropLast())
                result.append(Entry(word: word, respell: nil, ipa: ipa))
            } else {
                result.append(Entry(word: word, respell: value, ipa: nil))
            }
        }
        return result
    }

    // MARK: - Substitution

    /// Apply respell substitutions: whole-word, case-insensitive, longest
    /// key first — mirroring the wrapper's matching rules. IPA-only entries
    /// are skipped (respell lines cover every engine).
    static func applyingRespells(to text: String, entries parsed: [Entry]? = nil) -> String {
        let parsed = parsed ?? entries(from: loadText() ?? "")
        let respells = parsed.filter { $0.respell != nil }
            .sorted { ($0.word.split(separator: " ").count, $0.word.count) > ($1.word.split(separator: " ").count, $1.word.count) }
        guard !respells.isEmpty else { return text }
        var result = text
        for entry in respells {
            guard let pattern = try? NSRegularExpression(
                pattern: "\\b\(NSRegularExpression.escapedPattern(for: entry.word))\\b",
                options: .caseInsensitive
            ) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            var rebuilt = ""
            var cursor = result.startIndex
            pattern.enumerateMatches(in: result, range: range) { match, _, _ in
                guard let match, let matchRange = Range(match.range, in: result) else { return }
                rebuilt += result[cursor..<matchRange.lowerBound]
                rebuilt += entry.respell ?? ""
                cursor = matchRange.upperBound
            }
            guard !rebuilt.isEmpty else { continue }
            rebuilt += result[cursor...]
            result = rebuilt
        }
        return result
    }
}
