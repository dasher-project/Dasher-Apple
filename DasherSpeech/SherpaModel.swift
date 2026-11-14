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
    let g2pEnabled: Bool?

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
        return [developer.capitalized, name, quality, quantization == "fp32" ? nil : quantization]
            .compactMap { $0 }
            .filter { !$0.isEmpty && $0 != "unknown" }
            .joined(separator: " ")
    }

    var isEnglishOnly: Bool {
        language.count == 1 && language.first?.langCode == "en"
    }

    var usesG2PBundle: Bool {
        modelType == "vits" && g2pEnabled == true
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
        search.split(whereSeparator: \.isWhitespace).allSatisfy { term in
            [displayName, id, modelType, languages, language.map(\.langCode).joined(separator: " ")]
                .contains { $0.localizedStandardContains(String(term)) }
        }
    }
}
#endif
