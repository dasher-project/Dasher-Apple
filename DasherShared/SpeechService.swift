import Foundation
import SwiftTTSWrapper

@MainActor
@Observable
public final class SpeechService {
    public var selectedEngine: TTSEngine = .system {
        didSet { saveEngineSelection(); client = nil }
    }
    public var credentials: [String: String] = [:]
    public var selectedVoice: String?
    public var availableVoices: [UnifiedVoice] = []
    public var isSpeaking = false
    public var isLoadingVoices = false
    public var errorMessage: String?

    public var speechRate: SpeechRate = .medium {
        didSet { saveRateSelection() }
    }
    public var speechPitch: SpeechPitch = .medium {
        didSet { savePitchSelection() }
    }
    public var speechVolume: Float = 1.0 {
        didSet { saveVolumeSelection() }
    }

    private var client: TTSClient?

    public static let shared = SpeechService()

    private init() {
        loadSavedSettings()
    }

    public func speak(_ text: String) {
        guard !text.isEmpty else { return }
        ensureClient()
        client?.onStart = { [weak self] in
            Task { @MainActor in self?.isSpeaking = true; self?.errorMessage = nil }
        }
        client?.onEnd = { [weak self] in
            Task { @MainActor in self?.isSpeaking = false }
        }
        client?.onError = { [weak self] error in
            Task { @MainActor in self?.isSpeaking = false; self?.errorMessage = error.localizedDescription }
        }
        var options = SpeakOptions(useWordBoundary: true)
        if let selectedVoice {
            options.voice = selectedVoice
        }
        options.rate = speechRate
        options.pitch = speechPitch
        options.volume = speechVolume
        Task {
            do {
                try await client?.speak(text, options: options)
            } catch {
                errorMessage = error.localizedDescription
                isSpeaking = false
            }
        }
    }

    public func stop() {
        client?.stop()
        isSpeaking = false
    }

    public func loadVoices() {
        ensureClient()
        isLoadingVoices = true
        Task {
            do {
                availableVoices = try await client?.getVoices() ?? []
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoadingVoices = false
        }
    }

    public func setCredential(_ key: String, value: String) {
        credentials[key] = value
        client = nil
        saveCredentials()
    }

    private func ensureClient() {
        if client == nil {
            client = TTSClientFactory.create(engine: selectedEngine, credentials: credentials)
        }
    }

    private func loadSavedSettings() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "tts_engine"), let engine = TTSEngine(rawValue: raw) {
            selectedEngine = engine
        }
        if let data = defaults.data(forKey: "tts_credentials"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            credentials = dict
        }
        selectedVoice = defaults.string(forKey: "tts_voice")
        if let raw = defaults.string(forKey: "tts_rate"), let rate = SpeechRate(rawValue: raw) {
            speechRate = rate
        }
        if let raw = defaults.string(forKey: "tts_pitch"), let pitch = SpeechPitch(rawValue: raw) {
            speechPitch = pitch
        }
        speechVolume = defaults.float(forKey: "tts_volume").isNaN ? 1.0 : defaults.float(forKey: "tts_volume")
        if speechVolume <= 0 { speechVolume = 1.0 }
    }

    private func saveEngineSelection() {
        UserDefaults.standard.set(selectedEngine.rawValue, forKey: "tts_engine")
    }

    private func saveCredentials() {
        if let data = try? JSONEncoder().encode(credentials) {
            UserDefaults.standard.set(data, forKey: "tts_credentials")
        }
    }

    public func saveVoiceSelection() {
        UserDefaults.standard.set(selectedVoice, forKey: "tts_voice")
    }

    private func saveRateSelection() {
        UserDefaults.standard.set(speechRate.rawValue, forKey: "tts_rate")
    }

    private func savePitchSelection() {
        UserDefaults.standard.set(speechPitch.rawValue, forKey: "tts_pitch")
    }

    private func saveVolumeSelection() {
        UserDefaults.standard.set(speechVolume, forKey: "tts_volume")
    }
}
