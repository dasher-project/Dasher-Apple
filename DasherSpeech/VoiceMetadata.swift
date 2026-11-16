import Foundation

enum VoiceGender: String, CaseIterable {
    case female, male, neutral, unspecified

    init(_ value: String?) {
        self = VoiceGender(rawValue: value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")
            ?? .unspecified
    }

    var title: String {
        switch self {
        case .female: String(localized: "Female")
        case .male: String(localized: "Male")
        case .neutral: String(localized: "Neutral")
        case .unspecified: String(localized: "Gender not specified")
        }
    }
}

struct VoiceLanguage: Hashable {
    let code: String
    let name: String
    let filterName: String

    init(_ code: String, name: String? = nil) {
        self.code = code.replacingOccurrences(of: "_", with: "-")
        self.name = name.flatMap { $0.isEmpty ? nil : $0 }
            ?? Locale.current.localizedString(forIdentifier: self.code)
            ?? self.code
        let language = Locale.Language(identifier: self.code).languageCode
        filterName = language.flatMap { Locale.current.localizedString(forLanguageCode: $0.identifier) } ?? self.name
    }

    init(wrapperLabel: String) {
        // Rust's C API formats language as "Display name [BCP-47]".
        if wrapperLabel.hasSuffix("]"), let bracket = wrapperLabel.lastIndex(of: "[") {
            let code = String(wrapperLabel[wrapperLabel.index(after: bracket)..<wrapperLabel.index(before: wrapperLabel.endIndex)])
            let label = wrapperLabel[..<bracket].trimmingCharacters(in: .whitespaces)
            self.init(code, name: label == code ? nil : label)
        } else {
            self.init(wrapperLabel)
        }
    }
}

struct VoiceMetadata {
    var languages: [VoiceLanguage] = []
    var gender: VoiceGender = .unspecified
    var type: String?

    var subtitle: String {
        let languages = Set(languages.map(\.name)).sorted().joined(separator: ", ")
        return [type, languages.isEmpty ? nil : languages, gender.title].compactMap { $0 }.joined(separator: " · ")
    }
}

struct VoiceFilters {
    var language: String?
    var gender: VoiceGender?
    var type: String?

    var isActive: Bool { language != nil || gender != nil || type != nil }

    func matches(_ metadata: VoiceMetadata, search: String, terms: @autoclosure () -> [String]) -> Bool {
        if let language, !metadata.languages.contains(where: { $0.filterName == language }) { return false }
        if let gender, metadata.gender != gender { return false }
        if let type, metadata.type != type { return false }
        let searchTerms = search.split(whereSeparator: \.isWhitespace)
        guard !searchTerms.isEmpty else { return true }
        let fields = terms() + [metadata.type ?? ""]
            + metadata.languages.flatMap { [$0.code, $0.name, $0.filterName] }
        return searchTerms.allSatisfy { term in
            let word = String(term)
            if let gender = VoiceGender.allCases.first(where: { $0.title.localizedCaseInsensitiveCompare(word) == .orderedSame }) {
                return metadata.gender == gender
            }
            return fields.contains { $0.localizedStandardContains(word) }
        }
    }
}
