#if os(macOS) || os(iOS)
import Foundation
import RustTtsWrapper

struct SherpaModel: Decodable, Identifiable, Sendable {
    struct Language: Decodable, Sendable {
        let langCode: String
        let languageName: String
        let country: String?
    }

    let id: String
    let modelType: String
    let engines: String?
    let developer: String
    let name: String
    let language: [Language]
    let quality: String?
    let quantization: String?
    let numSpeakers: Int
    let url: URL
    let filesizeMb: Double?
    let sha256: String?
    let license: String
    let licenseUrl: URL?
    let deprecated: Bool?
    let readiness: String?
    let gender: String?

    static func catalog(from json: String) throws -> [Self] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let models = try decoder.decode([String: Self].self, from: Data(json.utf8))
        return models.values.sorted { lhs, rhs in
            if lhs.id == SpeechModelStorage.englishModelID { return rhs.id != lhs.id }
            if rhs.id == SpeechModelStorage.englishModelID { return false }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    static func bundledCatalog() throws -> [Self] {
        try catalog(from: TtsClient.sherpaModelsJSON())
    }

    var displayName: String {
        if id == SpeechModelStorage.englishModelID { return "Inflect Nano v2" }
        let title = name.replacingOccurrences(of: "_", with: " ")
        if title.isEmpty || title == "unknown" { return voiceType }
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    var voiceType: String {
        switch developer.lowercased() {
        case "piper": "Piper"
        case "mms": "MMS"
        case "kokoro": "Kokoro"
        case "kitten": "Kitten"
        default:
            switch modelType {
            case "vits": developer.isEmpty || developer == "unknown" ? "VITS" : developer.capitalized
            default: modelType.capitalized
            }
        }
    }

    var voiceMetadata: VoiceMetadata {
        let languages = language.compactMap { item -> VoiceLanguage? in
            guard !item.langCode.isEmpty, item.langCode != "unknown" else { return nil }
            let country = item.country ?? ""
            let code = item.langCode.count == 2 && country.count == 2 ? "\(item.langCode)-\(country)" : item.langCode
            return VoiceLanguage(code, name: code == item.langCode ? item.languageName : nil)
        }
        var voiceGender = VoiceGender(gender)
        if voiceGender == .unspecified, developer == "piper", numSpeakers == 1 {
            // Alan uses the apope dataset, listed as MALE1 in Mimic 3's speech-dispatcher config.
            let nameParts = name.lowercased().split(separator: "_")
            if id.hasPrefix("piper-en_GB-alan-") || nameParts.contains("male") { voiceGender = .male }
            if nameParts.contains("female") { voiceGender = .female }
        }
        return VoiceMetadata(languages: languages, gender: voiceGender, type: voiceType)
    }

    var variantLabel: String? {
        let parts = [quality, quantization == "fp32" ? nil : quantization]
            .compactMap { $0 }
            .filter { !$0.isEmpty && $0 != "unknown" }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var isEnglishOnly: Bool {
        language.count == 1 && language.first?.langCode == "en"
    }

    var usesG2PBundle: Bool {
        readiness == "needs_bundle"
    }

    var languages: String {
        Set(language.map(\.languageName)).sorted().joined(separator: ", ")
    }

    var sizeLabel: String? {
        guard let filesizeMb, filesizeMb > 0 else { return nil }
        let bytes = Int64(filesizeMb * 1_048_576)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func matches(_ search: String) -> Bool {
        VoiceFilters().matches(voiceMetadata, search: search, terms: searchTerms)
    }

    var searchTerms: [String] { [displayName, id, modelType, developer, variantLabel ?? ""] }
}
#endif
