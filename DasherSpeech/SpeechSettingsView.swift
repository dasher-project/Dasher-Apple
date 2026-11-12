import SwiftTTSWrapper
import SwiftUI
import UniformTypeIdentifiers

public struct SpeechSettingsView: View {
    @Bindable public var service: SpeechService
    @State private var isChoosingFile = false
    @State private var importFieldID: String?

    public init(service: SpeechService) {
        self.service = service
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("TTS Engine", selection: $service.selectedEngineID) {
                ForEach(service.availableEngines) { engine in
                    Text(engine.name).tag(engine.id)
                }
            }
            .pickerStyle(.menu)
            .disabled(service.isImporting)

            if let error = service.engineListError {
                Text(error).foregroundStyle(.red)
            }
            if service.isSherpa {
                modelSection
            } else {
                credentialsSection
            }
            voiceSection
            if let error = service.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .buttonStyle(.borderless)
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: importFieldID == nil ? [.folder] : [.item]) {
            switch $0 {
            case .success(let url): service.importSelection(url, fieldID: importFieldID)
            case .failure(let error): service.showError(error)
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            #if os(macOS) || os(iOS)
            if !service.hasSherpaModel {
                Button("Set Up English Voice (27 MB)") { service.useEnglishModel() }
                    .disabled(service.isImporting)
            }
            #endif
            DisclosureGroup("Use Another Model") {
                customModelSection
            }
            if service.isImporting {
                ProgressView().controlSize(.small)
            } else if service.hasSherpaModel {
                Label("Model installed", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var customModelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Sherpa-ONNX model ID", text: binding(for: "modelId"), prompt: Text(verbatim: "inflect-en-nano-v2"))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .disabled(service.isImporting)
            Text("Enter the model ID from the registry, then import the extracted folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link("Sherpa-ONNX model registry", destination: URL(string: "https://github.com/AACTools/sherpa-onnx-tts-models")!)
            Button("Import Model Folder") { chooseFile(for: nil) }
                .disabled(service.isImporting || !SpeechModelStorage.isValidModelID(service.modelID))
        }
    }

    private var credentialsSection: some View {
        let alternativeKeys = Set(service.engine.requiredAny.flatMap { $0 })
        let essential = service.engine.fields.filter { $0.required || alternativeKeys.contains($0.id) }
        let optional = service.engine.fields.filter { !$0.required && !alternativeKeys.contains($0.id) }
        return VStack(alignment: .leading, spacing: 8) {
            if service.engine.fields.isEmpty {
                Text("No credentials required")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(essential) { credentialRow($0) }
            if !optional.isEmpty {
                DisclosureGroup("Advanced Settings") {
                    ForEach(optional) { credentialRow($0) }
                }
            }
        }
    }

    @ViewBuilder
    private func credentialRow(_ field: SpeechEngine.Field) -> some View {
        let value = binding(for: field.id)
        switch field.kind {
        case .secret:
            SecureField(field.label, text: value)
                .textFieldStyle(.roundedBorder)
        case .text:
            TextField(field.label, text: value, prompt: field.defaultValue.map { Text($0) })
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        case .choice:
            Picker(field.label, selection: value) {
                if !field.required { Text("Default").tag("") }
                else { Text("Select").tag("") }
                if !value.wrappedValue.isEmpty, !field.choices.contains(value.wrappedValue) {
                    Text(value.wrappedValue).tag(value.wrappedValue)
                }
                ForEach(field.choices, id: \.self) { Text($0).tag($0) }
            }
        case .file:
            HStack {
                Button { chooseFile(for: field.id) } label: {
                    Label(field.label, systemImage: "folder")
                }
                .disabled(service.isImporting)
                if !value.wrappedValue.isEmpty {
                    Text(URL(fileURLWithPath: value.wrappedValue).lastPathComponent)
                        .lineLimit(1)
                    Button("Clear") { value.wrappedValue = "" }
                }
            }
        }
        if let help = field.help {
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    service.loadVoices()
                } label: {
                    Label("Load Voices", systemImage: "speaker.wave.2")
                }
                .disabled(service.isLoadingVoices || service.isImporting || (service.isSherpa && !service.hasSherpaModel))

                if service.isLoadingVoices {
                    ProgressView().controlSize(.small)
                } else if !service.availableVoices.isEmpty {
                    Text("\(service.availableVoices.count) voices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    if service.isSpeaking { service.stop() } else { service.preview() }
                } label: {
                    if service.isSpeaking { Label("Stop", systemImage: "stop.fill") }
                    else { Label("Preview", systemImage: "play.fill") }
                }
                .disabled(service.isImporting || (service.isSherpa && !service.hasSherpaModel))
            }

            if !service.availableVoices.isEmpty {
                Picker("Voice", selection: $service.selectedVoice) {
                    Text("Default").tag(nil as String?)
                    ForEach(service.availableVoices) { voice in
                        Text(voice.name).tag(voice.id as String?)
                    }
                }
            }
            if service.engine.supportsRate {
                Picker("Rate", selection: $service.speechRate) {
                    Text("Very Slow").tag(SpeechRate.xSlow)
                    Text("Slow").tag(SpeechRate.slow)
                    Text("Medium").tag(SpeechRate.medium)
                    Text("Fast").tag(SpeechRate.fast)
                    Text("Very Fast").tag(SpeechRate.xFast)
                }
            }
            if service.engine.supportsPitch {
                Picker("Pitch", selection: $service.speechPitch) {
                    Text("Very Low").tag(SpeechPitch.xLow)
                    Text("Low").tag(SpeechPitch.low)
                    Text("Medium").tag(SpeechPitch.medium)
                    Text("High").tag(SpeechPitch.high)
                    Text("Very High").tag(SpeechPitch.xHigh)
                }
            }
            if service.engine.supportsVolume {
                Slider(value: $service.speechVolume, in: 0...1, step: 0.05) {
                    Text("Volume")
                } minimumValueLabel: {
                    Text("0%")
                } maximumValueLabel: {
                    Text("100%")
                }
            }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(get: { service.credential(key) }, set: { service.setCredential(key, value: $0) })
    }

    private func chooseFile(for fieldID: String?) {
        importFieldID = fieldID
        isChoosingFile = true
    }
}
