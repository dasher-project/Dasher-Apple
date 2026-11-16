#if os(macOS) || os(iOS)
import SwiftUI

struct SherpaModelBrowser: View {
    let service: SpeechService
    private let entries: [Entry]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var filters = VoiceFilters()
    @State private var installedOnly = false

    private struct Entry: Identifiable {
        let model: SherpaModel
        let metadata: VoiceMetadata
        var id: String { model.id }
        var subtitle: String {
            [metadata.subtitle, model.variantLabel].compactMap { $0 }.joined(separator: " · ")
        }
    }

    init(service: SpeechService) {
        self.service = service
        entries = service.sherpaCatalog.map { Entry(model: $0, metadata: $0.voiceMetadata) }
    }

    private var results: [Entry] {
        entries.filter { entry in
            (!installedOnly || service.installedSherpaModels.contains(entry.id))
                && filters.matches(entry.metadata, search: search, terms: entry.model.searchTerms)
        }
    }

    var body: some View {
        let results = results
        NavigationStack {
            List {
                if let error = service.catalogError {
                    Text(error).foregroundStyle(.red)
                }
                Section {
                    Toggle("Installed Only", isOn: $installedOnly)
                }
                if results.isEmpty && service.catalogError == nil {
                    ContentUnavailableView("No matching voices", systemImage: "magnifyingglass")
                }
                ForEach(results) { entry in
                    NavigationLink(value: entry.id) {
                        let installed = service.installedSherpaModels.contains(entry.id)
                        HStack(spacing: 12) {
                            VoiceBrowserRow(title: entry.model.displayName, subtitle: entry.subtitle,
                                            selected: installed && entry.id == service.selectedSherpaModelID)
                            if installed && entry.id != service.selectedSherpaModelID {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Installed")
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search voices")
            .navigationTitle("Sherpa-ONNX Voices")
            .safeAreaInset(edge: .top, spacing: 0) {
                VoiceFilterBar(filters: $filters, metadata: entries.map(\.metadata), resultCount: results.count)
            }
            .navigationDestination(for: String.self) { id in
                if let model = service.sherpaCatalog.first(where: { $0.id == id }) {
                    details(for: model)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 480)
        #endif
    }

    private func details(for model: SherpaModel) -> some View {
        Form {
            Section {
                LabeledContent("Voice Type", value: model.voiceType)
                if !model.languages.isEmpty { LabeledContent("Languages", value: model.languages) }
                LabeledContent("Gender", value: model.voiceMetadata.gender.title)
                if let variant = model.variantLabel { LabeledContent("Variant", value: variant) }
                if let size = model.sizeLabel { LabeledContent("Download size", value: size) }
                if model.numSpeakers > 0 { LabeledContent("Speakers", value: "\(model.numSpeakers)") }
                if let license = model.licenseUrl, license.scheme == "https" {
                    Link(model.license, destination: license)
                } else {
                    LabeledContent("License", value: model.license)
                }
                if model.deprecated == true {
                    Text("This model is deprecated.").foregroundStyle(.secondary)
                }
            }
            Section {
                if service.downloadingSherpaModelID == model.id {
                    ProgressView("Downloading model…")
                    Button("Cancel Download", role: .cancel) { service.cancelSherpaModelDownload() }
                } else if service.installedSherpaModels.contains(model.id) {
                    if model.id == service.selectedSherpaModelID {
                        Label("Selected model", systemImage: "checkmark.circle")
                    } else {
                        Button("Use Model") { service.selectSherpaModel(model) }
                            .disabled(service.isImporting)
                    }
                } else if let reason = SpeechModelStorage.downloadUnavailableReason(for: model) {
                    Text(reason).foregroundStyle(.secondary)
                } else {
                    Button("Download Model") { service.downloadSherpaModel(model) }
                        .disabled(service.isImporting)
                }
                if let error = service.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(model.displayName)
    }
}
#endif
