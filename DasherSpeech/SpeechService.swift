import DasherShared
import Foundation
import SwiftTTSWrapper
#if os(macOS) || os(iOS)
import RustTtsWrapper
#endif

@MainActor
@Observable
public final class SpeechService {
    var selectedEngineID = SpeechEngine.system.id {
        didSet {
            guard oldValue != selectedEngineID else { return }
            defaults.set(selectedEngineID, forKey: "tts_engine")
            resetEngine()
        }
    }
    private(set) var availableEngines: [SpeechEngine] = [.system]
    private(set) var availableVoices: [SpeechVoice] = []
    public private(set) var isSpeaking = false
    private(set) var isLoadingVoices = false
    private(set) var isImporting = false
    private var installedModelID: String?
    private(set) var errorMessage: String?
    private(set) var engineListError: String?

    var selectedVoice: String? {
        get { voicesByEngine[selectedEngineID] }
        set {
            voicesByEngine[selectedEngineID] = newValue
            defaults.set(voicesByEngine, forKey: "tts_voices_by_engine")
        }
    }

    var speechRate: SpeechRate = .medium {
        didSet { defaults.set(speechRate.rawValue, forKey: "tts_rate") }
    }
    var speechPitch: SpeechPitch = .medium {
        didSet { defaults.set(speechPitch.rawValue, forKey: "tts_pitch") }
    }
    var speechVolume: Float = 1 {
        didSet { defaults.set(speechVolume, forKey: "tts_volume") }
    }

    /// Set by the view model when the active alphabet uses X-SAMPA.
    public var phonemeMode = false

    private var credentialsByEngine: [String: [String: String]] = [:]
    private var voicesByEngine: [String: String] = [:]
    private var nativeClient: TTSClient?
    private var speechTask: Task<Void, Never>?
    private var voiceTask: Task<Void, Never>?
    private var speechID = UUID()
    #if os(macOS) || os(iOS)
    private let rustBackend = RustSpeechBackend()
    private let audioPlayer = SpeechAudioPlayer()
    #endif

    public static let shared = SpeechService()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = SharedDefaults.fallback) {
        self.defaults = defaults
        do {
            availableEngines = try SpeechEngine.available()
        } catch {
            engineListError = String(localized: "Could not load the speech engines.")
        }
        loadSavedSettings()
    }

    var engine: SpeechEngine {
        availableEngines.first { $0.id == selectedEngineID } ?? .system
    }

    var isSherpa: Bool { usesRust && selectedEngineID == SpeechEngine.sherpaID }
    var modelID: String { credential("modelId") }

    func credential(_ key: String) -> String {
        credentialsByEngine[selectedEngineID]?[key] ?? ""
    }

    func setCredential(_ key: String, value: String) {
        var values = credentialsByEngine[selectedEngineID, default: [:]]
        guard values[key, default: ""] != value else { return }
        values[key] = value.isEmpty ? nil : value
        credentialsByEngine[selectedEngineID] = values
        defaults.set(credentialsByEngine, forKey: "tts_credentials_by_engine")
        resetEngine()
    }

    public func speak(_ text: String) {
        speak(text, phonemes: phonemeMode)
    }

    func preview() {
        speak(String(localized: "Hello, this is a preview of the selected voice."), phonemes: false)
    }

    public func stop() {
        speechID = UUID()
        speechTask?.cancel()
        speechTask = nil
        nativeClient?.stop()
        nativeClient = nil
        #if os(macOS) || os(iOS)
        audioPlayer.stop()
        #endif
        isSpeaking = false
    }

    func loadVoices() {
        voiceTask?.cancel()
        errorMessage = nil
        isLoadingVoices = true
        let engineID = selectedEngineID
        let credentialValues = credentialsByEngine[engineID, default: [:]]
        voiceTask = Task {
            defer {
                if !Task.isCancelled { isLoadingVoices = false }
            }
            do {
                let voices: [SpeechVoice]
                if usesRust {
                    #if os(macOS) || os(iOS)
                    let configuration = try rustCredentials(credentialValues, engineID: engineID)
                    voices = try await rustBackend.voices(engineID: engineID, credentials: configuration)
                    #else
                    voices = []
                    #endif
                } else {
                    voices = try await makeNativeClient(engineID: engineID, credentials: credentialValues).getVoices().map {
                        SpeechVoice(id: $0.id, name: $0.name)
                    }
                }
                try Task.checkCancellation()
                availableVoices = voices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if let selectedVoice, !availableVoices.contains(where: { $0.id == selectedVoice }) {
                    self.selectedVoice = nil
                }
            } catch {
                if !Task.isCancelled { showError(error) }
            }
        }
    }

    func showError(_ error: Error) {
        #if os(macOS) || os(iOS)
        if let ttsError = error as? TtsError {
            errorMessage = ttsError.displayMessage ?? ttsError.message
            return
        }
        #endif
        errorMessage = error.localizedDescription
    }

    private var usesRust: Bool {
        #if os(macOS) || os(iOS)
        selectedEngineID != SpeechEngine.system.id
        #else
        false
        #endif
    }

    private func speak(_ text: String, phonemes: Bool) {
        guard !text.isEmpty, !isImporting || !isSherpa else { return }
        stop()
        errorMessage = nil
        isSpeaking = true
        let requestID = speechID
        let engineID = selectedEngineID
        let voice = selectedVoice
        let credentialValues = credentialsByEngine[engineID, default: [:]]
        let options = SpeakOptions(rate: speechRate, pitch: speechPitch, volume: speechVolume, voice: voice)
        let payload = phonemes && !isSherpa
            ? text.split(separator: " ").map { "(\($0))[xsampa:\"\($0)\"]" }.joined(separator: " ")
            : text

        let complete: @MainActor (Error?) -> Void = { [weak self] error in
            self?.finish(requestID, error: error)
        }
        speechTask = Task {
            do {
                try Task.checkCancellation()
                if usesRust {
                    #if os(macOS) || os(iOS)
                    let configuration = try rustCredentials(credentialValues, engineID: engineID)
                    let data = try await rustBackend.synthesize(
                        payload, engineID: engineID, credentials: configuration, voice: voice,
                        rate: (options.rate ?? .medium).rateValue / SpeechRate.medium.rateValue,
                        pitch: (options.pitch ?? .medium).pitchValue, volume: options.volume ?? 1
                    )
                    try Task.checkCancellation()
                    try audioPlayer.play(data, completion: complete)
                    #endif
                } else {
                    let client = makeNativeClient(engineID: engineID, credentials: credentialValues)
                    nativeClient = client
                    client.onEnd = { Task { @MainActor in complete(nil) } }
                    client.onError = { error in Task { @MainActor in complete(error) } }
                    try await client.speak(payload, options: options)
                }
            } catch {
                if !Task.isCancelled { finish(requestID, error: error) }
            }
        }
    }

    private func finish(_ requestID: UUID, error: Error? = nil) {
        guard speechID == requestID else { return }
        isSpeaking = false
        speechTask = nil
        if let error { showError(error) }
    }

    private func makeNativeClient(engineID: String, credentials: [String: String]) -> TTSClient {
        TTSClientFactory.create(engine: TTSEngine(rawValue: engineID) ?? .system, credentials: credentials)
    }

    private func resetEngine() {
        stop()
        refreshModelStatus()
        voiceTask?.cancel()
        voiceTask = nil
        isLoadingVoices = false
        availableVoices = []
        errorMessage = nil
    }

    var hasSherpaModel: Bool { installedModelID == modelID }

    private func refreshModelStatus() {
        installedModelID = isSherpa && SpeechModelStorage.hasModel(modelID) ? modelID : nil
    }

    #if os(macOS) || os(iOS)
    func useEnglishModel() {
        isImporting = true
        errorMessage = nil
        Task {
            defer { isImporting = false }
            do {
                if !SpeechModelStorage.hasModel(SpeechModelStorage.englishModelID) {
                    try await SpeechModelStorage.downloadEnglishModel()
                }
                setCredential("modelId", value: SpeechModelStorage.englishModelID)
                refreshModelStatus()
            } catch {
                showError(error)
            }
        }
    }
    #endif

    func importSelection(_ source: URL, fieldID: String?) {
        let engineID = selectedEngineID
        let modelID = modelID
        stop()
        isImporting = true
        errorMessage = nil
        Task {
            defer { isImporting = false }
            do {
                if let fieldID {
                    let relativePath = try await Task.detached(priority: .utility) {
                        try SpeechModelStorage.importFile(from: source)
                    }.value
                    if selectedEngineID == engineID { setCredential(fieldID, value: relativePath) }
                } else {
                    try await Task.detached(priority: .utility) {
                        try SpeechModelStorage.installModel(from: source, as: modelID)
                    }.value
                    #if os(macOS) || os(iOS)
                    await rustBackend.reset()
                    #endif
                    if selectedEngineID == engineID { resetEngine() }
                }
            } catch {
                showError(error)
            }
        }
    }

    private func rustCredentials(_ values: [String: String], engineID: String) throws -> [String: String] {
        var configuration = values
        if engineID == SpeechEngine.sherpaID {
            guard SpeechModelStorage.isValidModelID(modelID) else { throw SpeechSetupError.invalidModelID }
            guard hasSherpaModel else { throw SpeechSetupError.modelNotInstalled }
            configuration["modelPath"] = SpeechModelStorage.models.path
        } else {
            for field in engine.fields where field.kind == .file {
                if let relative = values[field.id] {
                    configuration[field.id] = SpeechModelStorage.root.appending(path: relative).path
                }
            }
        }
        return configuration
    }

    private func loadSavedSettings() {
        credentialsByEngine = defaults.dictionary(forKey: "tts_credentials_by_engine") as? [String: [String: String]] ?? [:]
        voicesByEngine = defaults.dictionary(forKey: "tts_voices_by_engine") as? [String: String] ?? [:]
        let storedEngineID = defaults.string(forKey: "tts_engine") ?? SpeechEngine.system.id
        if defaults.object(forKey: "tts_credentials_by_engine") == nil,
           let engine = availableEngines.first(where: { $0.id == storedEngineID }),
           let data = defaults.data(forKey: "tts_credentials"),
           let oldCredentials = try? JSONDecoder().decode([String: String].self, from: data) {
            let keys = Set(engine.fields.filter { $0.kind != .file }.map(\.id))
            credentialsByEngine[storedEngineID] = oldCredentials.filter { keys.contains($0.key) }
            defaults.set(credentialsByEngine, forKey: "tts_credentials_by_engine")
        }
        if defaults.object(forKey: "tts_voices_by_engine") == nil, let voice = defaults.string(forKey: "tts_voice") {
            #if os(macOS) || os(iOS)
            if storedEngineID != SpeechEngine.sherpaID { voicesByEngine[storedEngineID] = voice }
            #else
            voicesByEngine[storedEngineID] = voice
            #endif
            defaults.set(voicesByEngine, forKey: "tts_voices_by_engine")
        }
        if availableEngines.contains(where: { $0.id == storedEngineID }) { selectedEngineID = storedEngineID }
        speechRate = defaults.string(forKey: "tts_rate").flatMap(SpeechRate.init(rawValue:)) ?? .medium
        speechPitch = defaults.string(forKey: "tts_pitch").flatMap(SpeechPitch.init(rawValue:)) ?? .medium
        if let volume = defaults.object(forKey: "tts_volume") as? Float, volume.isFinite {
            speechVolume = min(max(volume, 0), 1)
        }
    }
}
