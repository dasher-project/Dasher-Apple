import Foundation
import AVFoundation
import SwiftTTSWrapper
#if os(macOS) || os(iOS)
import RustTtsWrapper
#endif

struct SpeechEngine: Identifiable {
    let id: String
    let name: String
    var fields: [Field] = []
    var requiredAny: [[String]] = []
    var supportsRate = true
    var supportsPitch = true
    var supportsVolume = true

    struct Field: Identifiable {
        enum Kind {
            case secret, text, choice, file
        }

        let id: String
        let label: String
        let kind: Kind
        var required = true
        var defaultValue: String?
        var placeholder: String?
        var choices: [String] = []
        var help: String?

        static func displayText(_ value: String?) -> String? {
            guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let schemaTypes = ["CredentialKey(", "CredentualKey(", "SetupField("]
            guard !schemaTypes.contains(where: text.localizedCaseInsensitiveContains) else { return nil }
            return text
        }

        var prompt: String? {
            Self.displayText(placeholder) ?? (kind == .secret ? nil : Self.displayText(defaultValue))
        }
    }

    static let system = SpeechEngine(id: "system", name: "System")
    static let sherpaID = "sherpaonnx"

    #if os(macOS) || os(iOS)
    static func available() throws -> [SpeechEngine] {
        let setups = try TtsClient.engineSetups()
        let engines = setups.filter { $0.capabilities.requiresInternet || $0.id == sherpaID }
        return [.system] + engines.map { setup in
            SpeechEngine(
                id: setup.id,
                name: setup.name,
                fields: setup.id == sherpaID ? [] : setup.fields.map { field in
                    let kind: Field.Kind
                    switch field.kind {
                    case .secret: kind = .secret
                    case .choice: kind = .choice
                    case .filePath, .directoryPath: kind = .file
                    default: kind = .text
                    }
                    return Field(
                        id: field.key, label: Field.displayText(field.label) ?? field.key, kind: kind,
                        required: field.required, defaultValue: field.defaultValue, placeholder: field.placeholder,
                        choices: field.choices, help: Field.displayText(field.helpText)
                    )
                },
                requiredAny: setup.requiredAny,
                supportsRate: setup.capabilities.supportsRate,
                supportsPitch: setup.capabilities.supportsPitch,
                supportsVolume: setup.capabilities.supportsVolume
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    #else
    static func available() throws -> [SpeechEngine] {
        [.system] + TTSEngine.allCases.compactMap { engine in
            let apiKey = Field(id: "apiKey", label: "API Key", kind: .secret)
            let region = Field(id: "region", label: "Region", kind: .text)
            let fields: [Field]
            switch engine {
            case .system: return nil
            case .sherpaonnx: fields = []
            case .azure: fields = [.init(id: "subscriptionKey", label: "Subscription Key", kind: .secret), region]
            case .playht: fields = [apiKey, .init(id: "userId", label: "User ID", kind: .text)]
            case .polly:
                fields = [.init(id: "accessKeyId", label: "Access Key ID", kind: .text),
                          .init(id: "secretAccessKey", label: "Secret Key", kind: .secret)]
            case .watson: fields = [apiKey, region, .init(id: "instanceId", label: "Instance ID", kind: .text)]
            case .witai: fields = [.init(id: "token", label: "Token", kind: .secret)]
            default: fields = [apiKey]
            }
            let names: [TTSEngine: String] = [
                .openai: "OpenAI", .elevenlabs: "ElevenLabs", .playht: "PlayHT", .deepgram: "Deepgram",
                .fishaudio: "Fish Audio", .hume: "Hume AI", .polly: "Amazon Polly", .unrealspeech: "Unreal Speech",
                .upliftai: "UpliftAI", .watson: "IBM Watson", .witai: "Wit.ai", .xai: "xAI", .modelslab: "ModelsLab",
                .sherpaonnx: "Sherpa-ONNX",
            ]
            return SpeechEngine(id: engine.rawValue, name: names[engine] ?? engine.rawValue.capitalized, fields: fields)
        }
    }
    #endif
}

struct SpeechVoice: Identifiable, Sendable {
    let id: String
    let name: String
    let metadata: VoiceMetadata

    init(id: String, name: String, metadata: VoiceMetadata) {
        self.id = id
        self.name = name.isEmpty ? id : name
        self.metadata = metadata
    }

    static func native(_ voices: [UnifiedVoice], engineID: String) -> [Self] {
        let systemVoices = engineID == SpeechEngine.system.id
            ? Dictionary(AVSpeechSynthesisVoice.speechVoices().map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
            : [:]
        return voices.map { voice in
            let native = systemVoices[voice.id]
            var type = providerVoiceType(engineID: engineID, id: voice.id)
            if let native {
                switch native.quality {
                case .default: type = String(localized: "Standard")
                case .enhanced: type = String(localized: "Enhanced")
                case .premium: type = String(localized: "Premium")
                @unknown default: break
                }
            }
            return Self(id: voice.id, name: voice.name, metadata: VoiceMetadata(
                languages: voice.languageCodes.map { VoiceLanguage($0.bcp47, name: $0.display) },
                gender: VoiceGender(voice.gender.rawValue),
                type: type
            ))
        }
    }

    static func providerVoiceType(engineID: String, id: String) -> String? {
        if engineID == "azure" || engineID == "edge" {
            if id.contains(":DragonHDOmni") { return String(localized: "Neural HD Omni") }
            if id.contains(":DragonHD") { return String(localized: "Neural HD") }
            if id.hasSuffix("MultilingualNeural") { return String(localized: "Multilingual Neural") }
            if id.hasSuffix("Neural") { return String(localized: "Neural") }
        }
        if engineID == "google" {
            return ["Chirp3-HD", "Studio", "Neural2", "WaveNet", "Standard"]
                .first { id.localizedCaseInsensitiveContains("-\($0)-") }
        }
        return nil
    }
}

#if os(macOS) || os(iOS)
actor RustSpeechBackend {
    private var client: TtsClient?
    private var engineID: String?
    private var previousVoice: String?
    private var credentials: [String: String] = [:]

    func voices(engineID: String, credentials: [String: String], modelMetadata: VoiceMetadata?) throws -> [SpeechVoice] {
        try Task.checkCancellation()
        return try configuredClient(engineID: engineID, credentials: credentials).getVoices().map { voice in
            let gender = VoiceGender(voice.gender)
            let languages = if let modelMetadata, !modelMetadata.languages.isEmpty {
                modelMetadata.languages
            } else {
                voice.language.isEmpty ? [] : [VoiceLanguage(wrapperLabel: voice.language)]
            }
            return SpeechVoice(id: voice.id, name: voice.name, metadata: VoiceMetadata(
                languages: languages,
                gender: gender == .unspecified ? modelMetadata?.gender ?? gender : gender,
                type: modelMetadata?.type ?? SpeechVoice.providerVoiceType(engineID: engineID, id: voice.id)
            ))
        }
    }

    func synthesize(
        _ text: String, engineID: String, credentials: [String: String],
        voice: String?, rate: Float, pitch: Float, volume: Float
    ) async throws -> Data {
        try Task.checkCancellation()
        if voice == nil, previousVoice != nil { client = nil }
        let client = try configuredClient(engineID: engineID, credentials: credentials)
        if let voice { client.setVoice(voice) }
        previousVoice = voice
        client.setRate(rate)
        client.setPitch(pitch)
        client.setVolume(volume)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try client.synthToWav(text)
        } onCancel: {
            client.stop()
        }
    }

    private func configuredClient(engineID: String, credentials: [String: String]) throws -> TtsClient {
        if let client, self.engineID == engineID, self.credentials == credentials {
            return client
        }
        let client = try TtsClient(engineId: engineID, credentials: credentials)
        self.client = client
        previousVoice = nil
        self.engineID = engineID
        self.credentials = credentials
        return client
    }
}
#endif
