#if os(macOS) || os(iOS)
import SwiftUI

struct SherpaModelBrowser: View {
    let service: SpeechService
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                if let error = service.catalogError {
                    Text(error).foregroundStyle(.red)
                }
                ForEach(service.sherpaCatalog.filter { $0.matches(search) }) { model in
                    NavigationLink(value: model.id) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.displayName)
                                if !model.languages.isEmpty {
                                    Text(model.languages).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if service.installedSherpaModels.contains(model.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityLabel("Installed")
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search models or languages")
            .navigationTitle("Sherpa-ONNX Models")
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
                if !model.languages.isEmpty { LabeledContent("Languages", value: model.languages) }
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
