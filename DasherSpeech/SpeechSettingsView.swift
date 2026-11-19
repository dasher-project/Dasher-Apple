import SwiftTTSWrapper
import SwiftUI
import UniformTypeIdentifiers

public struct SpeechSettingsView: View {
    @Bindable public var service: SpeechService
    @State private var isChoosingFile = false
    @State private var showsVoiceBrowser = false
    @State private var showsPronunciationEditor = false
    @State private var importFieldID: String?
    #if os(macOS) || os(iOS)
    @State private var showsSherpaCatalog = false
    #endif

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
            pronunciationsSection
            if let error = service.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .buttonStyle(.borderless)
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.item]) {
            guard let importFieldID else { return }
            switch $0 {
            case .success(let url): service.importCredentialFile(url, fieldID: importFieldID)
            case .failure(let error): service.showError(error)
            }
        }
        .sheet(isPresented: $showsVoiceBrowser) {
            SpeechVoiceBrowser(service: service)
        }
        #if os(macOS) || os(iOS)
        .sheet(isPresented: $showsSherpaCatalog) {
            SherpaModelBrowser(service: service)
        }
        #endif
        .sheet(isPresented: $showsPronunciationEditor) {
            PronunciationEditor(service: service)
        }
    }

    private var pronunciationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    showsPronunciationEditor = true
                } label: {
                    Label("Pronunciations", systemImage: "character.book.closed")
                }
                Spacer()
            }
            Text("Teach voices how to say a name or word — respell it or give IPA. Applies to every engine.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            #if os(macOS) || os(iOS)
            if let model = service.selectedSherpaModel, service.hasSherpaModel {
                Label([model.displayName, model.variantLabel].compactMap { $0 }.joined(separator: " · "),
                      systemImage: "checkmark.circle")
            }
            Button("Browse Voices") {
                service.loadSherpaCatalog()
                showsSherpaCatalog = true
            }
            if let downloadID = service.downloadingSherpaModelID,
               let model = service.sherpaCatalog.first(where: { $0.id == downloadID }) {
                ProgressView {
                    Text("Downloading \(model.displayName)…")
                }
                .controlSize(.small)
            } else if !service.hasSherpaModel {
                Text("Download a voice to enable Preview.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            #endif
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
            LabeledContent {
                SecureField(field.label, text: value, prompt: Text(field.prompt ?? ""))
                    .textFieldStyle(.roundedBorder)
            } label: {
                Text(field.label)
            }
        case .text:
            LabeledContent {
                TextField(field.label, text: value, prompt: Text(field.prompt ?? ""))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            } label: {
                Text(field.label)
            }
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
                if canBrowseSpeakers {
                    Button {
                        showsVoiceBrowser = true
                        if service.availableVoices.isEmpty { service.loadVoices() }
                    } label: {
                        Label(service.isSherpa ? "Choose Speaker" : "Choose Voice", systemImage: "speaker.wave.2")
                    }
                    .disabled(service.isImporting)
                }

                Spacer()

                SpeechPreviewButton(service: service)
            }

            if canBrowseSpeakers, let voice = service.availableVoices.first(where: { $0.id == service.selectedVoice }) {
                Text(voice.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

    private var canBrowseSpeakers: Bool {
        #if os(macOS) || os(iOS)
        if service.isSherpa {
            return service.hasSherpaModel && (service.selectedSherpaModel?.numSpeakers ?? 0) > 1
        }
        #endif
        return true
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(get: { service.credential(key) }, set: { service.setCredential(key, value: $0) })
    }

    private func chooseFile(for fieldID: String) {
        importFieldID = fieldID
        isChoosingFile = true
    }
}

struct SpeechPreviewButton: View {
    let service: SpeechService

    var body: some View {
        Button {
            if service.isSpeaking {
                service.stop()
            } else {
                service.preview()
            }
        } label: {
            if service.isSpeaking {
                Label("Stop", systemImage: "stop.fill")
            } else {
                Label("Preview", systemImage: "play.fill")
            }
        }
        .disabled(service.isImporting || (service.isSherpa && !service.hasSherpaModel))
    }
}

struct PronunciationEditor: View {
    @Environment(\.dismiss) private var dismiss
    var service: SpeechService
    @State private var fileText = ""
    @State private var newWord = ""
    @State private var newSaying = ""
    @State private var errorMessage: String?

    private var entries: [PronunciationOverrides.Entry] {
        PronunciationOverrides.entries(from: fileText)
    }

    private var canAdd: Bool {
        !newWord.trimmingCharacters(in: .whitespaces).isEmpty
            && !newSaying.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Word or phrase", text: $newWord)
                    TextField("Say it like — bow tocks or /wɪn/", text: $newSaying)
                    HStack {
                        Button {
                            service.previewPronunciation(newSaying)
                        } label: {
                            Label("Preview", systemImage: "play.fill")
                        }
                        .disabled(!canAdd)
                        Spacer()
                        Button("Add", action: addEntry)
                            .disabled(!canAdd)
                    }
                } header: {
                    Text("Add a pronunciation")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else {
                        Text("Respelling for any voice, or IPA between slashes for voices that support phonemes.")
                    }
                }

                Section {
                    if entries.isEmpty {
                        Text("No pronunciation exceptions yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.word)
                                    Text("Says \(entry.displayValue)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    service.previewOverride(entry.word)
                                } label: {
                                    Image(systemName: "play.circle")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Preview \(entry.word)")
                                Button(role: .destructive) {
                                    removeEntry(entry)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(entry.word)")
                            }
                        }
                    }
                } header: {
                    Text("Your exceptions")
                } footer: {
                    Text("Changes apply on the next utterance.")
                }
            }
            .navigationTitle("Pronunciations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                fileText = PronunciationOverrides.loadText() ?? PronunciationOverrides.starterText
            }
        }
    }

    private func addEntry() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        let saying = newSaying.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !saying.isEmpty else { return }
        let entry: PronunciationOverrides.Entry
        if saying.count > 2, saying.hasPrefix("/"), saying.hasSuffix("/") {
            entry = PronunciationOverrides.Entry(word: word, respell: nil, ipa: String(saying.dropFirst().dropLast()))
        } else {
            entry = PronunciationOverrides.Entry(word: word, respell: saying, ipa: nil)
        }
        do {
            try PronunciationOverrides.save(PronunciationOverrides.adding(entry, to: fileText))
            fileText = PronunciationOverrides.loadText() ?? ""
            newWord = ""
            newSaying = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeEntry(_ entry: PronunciationOverrides.Entry) {
        do {
            try PronunciationOverrides.save(PronunciationOverrides.removing(entry, from: fileText))
            fileText = PronunciationOverrides.loadText() ?? ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
