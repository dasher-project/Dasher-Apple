import SwiftUI
import SwiftTTSWrapper

public struct SpeechSettingsView: View {
    @Bindable public var service: SpeechService

    public init(service: SpeechService) {
        self.service = service
    }

    public var body: some View {
        @Bindable var service = service
        VStack(alignment: .leading, spacing: 12) {
            enginePicker
            credentialsSection
            voiceSection
        }
        .buttonStyle(.borderless)
    }

    private var enginePicker: some View {
        Picker("TTS Engine", selection: $service.selectedEngine) {
            ForEach(allEngines, id: \.self) { engine in
                Text(engineName(engine)).tag(engine)
            }
        }
        .pickerStyle(.menu)
    }

    private var credentialsSection: some View {
        Group {
            if requiredKeys.isEmpty {
                Text("No credentials required")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(requiredKeys, id: \.self) { key in
                    HStack {
                        Text(keyLabel(key))
                            .frame(width: 120, alignment: .trailing)
                        if key.isSecret {
                            SecureField("Enter \(key)...", text: bindingForKey(key))
                                .textFieldStyle(.roundedBorder)
                        } else {
                            TextField("Enter \(key)...", text: bindingForKey(key))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
        }
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    service.loadVoices()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2")
                        Text("Load Voices")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(service.isLoadingVoices)

                if service.isLoadingVoices {
                    ProgressView().scaleEffect(0.6)
                }

                if !service.availableVoices.isEmpty {
                    Text("\(service.availableVoices.count) voices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    if service.isSpeaking {
                        service.stop()
                    } else {
                        service.speak("Hello, this is a preview of the selected voice.")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: service.isSpeaking ? "stop.fill" : "play.fill")
                        Text(service.isSpeaking ? "Stop" : "Preview")
                    }
                }
                .buttonStyle(.borderless)
            }

            if !service.availableVoices.isEmpty {
                Picker("Voice", selection: $service.selectedVoice) {
                    Text("Default").tag(nil as String?)
                    ForEach(service.availableVoices) { voice in
                        Text(voice.name).tag(voice.id as String?)
                    }
                }
                .onChange(of: service.selectedVoice) {
                    service.saveVoiceSelection()
                }
            }

            Picker("Rate", selection: $service.speechRate) {
                ForEach(SpeechRate.allCases, id: \.self) { rate in
                    Text(rateDisplayName(rate)).tag(rate)
                }
            }

            Picker("Pitch", selection: $service.speechPitch) {
                ForEach(SpeechPitch.allCases, id: \.self) { pitch in
                    Text(pitchDisplayName(pitch)).tag(pitch)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Volume")
                    Spacer()
                    Text("\(Int(service.speechVolume * 100))%")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $service.speechVolume, in: 0...1, step: 0.05)
            }
        }
    }

    private func rateDisplayName(_ rate: SpeechRate) -> String {
        switch rate {
        case .xSlow: return "Very Slow"
        case .slow: return "Slow"
        case .medium: return "Medium"
        case .fast: return "Fast"
        case .xFast: return "Very Fast"
        }
    }

    private func pitchDisplayName(_ pitch: SpeechPitch) -> String {
        switch pitch {
        case .xLow: return "Very Low"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xHigh: return "Very High"
        }
    }

    private var allEngines: [TTSEngine] {
        [.system, .sherpaonnx, .openai, .elevenlabs, .azure, .google, .cartesia, .playht, .deepgram, .fishaudio, .hume, .mistral, .murf, .polly, .resemble, .unrealspeech, .upliftai, .watson, .witai, .xai, .modelslab]
    }

    private func engineName(_ engine: TTSEngine) -> String {
        switch engine {
        case .system: return "System"
        case .openai: return "OpenAI"
        case .elevenlabs: return "ElevenLabs"
        case .azure: return "Azure"
        case .google: return "Google"
        case .cartesia: return "Cartesia"
        case .playht: return "PlayHT"
        case .deepgram: return "Deepgram"
        case .fishaudio: return "Fish Audio"
        case .hume: return "Hume AI"
        case .mistral: return "Mistral"
        case .murf: return "Murf"
        case .polly: return "Amazon Polly"
        case .resemble: return "Resemble AI"
        case .sherpaonnx: return "Sherpa-ONNX"
        case .unrealspeech: return "Unreal Speech"
        case .upliftai: return "UpliftAI"
        case .watson: return "IBM Watson"
        case .witai: return "Wit.ai"
        case .xai: return "xAI"
        case .modelslab: return "ModelsLab"
        }
    }

    private var requiredKeys: [CredentialKey] {
        switch service.selectedEngine {
        case .system, .sherpaonnx: return []
        case .openai, .google, .cartesia, .deepgram, .fishaudio, .hume, .mistral, .murf, .resemble, .unrealspeech, .upliftai, .xai, .modelslab, .elevenlabs:
            return [.init(key: "apiKey", label: "API Key", isSecret: true)]
        case .azure:
            return [.init(key: "subscriptionKey", label: "Subscription Key", isSecret: true), .init(key: "region", label: "Region", isSecret: false)]
        case .playht:
            return [.init(key: "apiKey", label: "API Key", isSecret: true), .init(key: "userId", label: "User ID", isSecret: false)]
        case .polly:
            return [.init(key: "accessKeyId", label: "Access Key ID", isSecret: false), .init(key: "secretAccessKey", label: "Secret Key", isSecret: true)]
        case .watson:
            return [.init(key: "apiKey", label: "API Key", isSecret: true), .init(key: "region", label: "Region", isSecret: false), .init(key: "instanceId", label: "Instance ID", isSecret: false)]
        case .witai:
            return [.init(key: "token", label: "Token", isSecret: true)]
        }
    }

    private func keyLabel(_ key: CredentialKey) -> String { key.label }

    private func bindingForKey(_ key: CredentialKey) -> Binding<String> {
        Binding(
            get: { service.credentials[key.key] ?? "" },
            set: { service.setCredential(key.key, value: $0) }
        )
    }
}

private struct CredentialKey: Hashable {
    let key: String
    let label: String
    let isSecret: Bool
}
