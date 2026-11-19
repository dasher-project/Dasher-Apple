import Foundation

/// User pronunciation overrides (rust-tts-wrapper #125/#127, exposed in
/// aactools/rust-tts-wrapper#130 discussion): a plain-text file teaching the
/// wrapper how words should sound —
///
///     # respell — works on every engine
///     botox = bow tocks
///     # phoneme override — precise IPA where the engine accepts it
///     nguyen = /wɪn/
///
/// The Rust wrapper applies this file automatically on every utterance for
/// engines it synthesizes (sherpa-onnx, cloud). This type owns the Dasher
/// copy of the file, points the Rust wrapper at it via
/// `RUST_TTS_PRONUNCIATIONS`, and re-applies the same respell substitutions
/// to the Apple system engine (AVSpeechSynthesizer), which does not go
/// through Rust.
public enum PronunciationOverrides {
    static let envKey = "RUST_TTS_PRONUNCIATIONS"

    /// One parsed `word = value` line. `value` is a respell, or IPA when
    /// wrapped in forward slashes.
    struct Entry: Equatable {
        let word: String
        let respell: String?
        let ipa: String?
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

    /// Point the Rust wrapper at the Dasher-owned file. The wrapper resolves
    /// the path per utterance, so this only needs to happen once at startup.
    public static func activate() {
        guard let url = try? ensureFile() else { return }
        setenv(envKey, url.path, 1)
    }

    static func loadText() -> String? {
        try? String(contentsOf: fileURL(), encoding: .utf8)
    }

    static func save(_ text: String) throws {
        let url = try ensureFile()
        try text.write(to: url, atomically: true, encoding: .utf8)
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
