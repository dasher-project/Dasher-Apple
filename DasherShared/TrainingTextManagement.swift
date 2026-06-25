import SwiftUI
import UniformTypeIdentifiers

/// Reusable training text management section for Settings → Language.
/// Shows current training data size, with import / export / reset buttons.
/// Used by DasherApp (iOS), DasherMac, and DasherVision.
public struct TrainingTextManagementSection: View {
    let userTrainingFileSize: Int64
    let userTrainingSizeDescription: String
    let onImport: (String) -> Void
    let onExport: () -> String?
    let onReset: () -> Void

    @State private var showImportPicker = false
    @State private var showExportPicker = false
    @State private var showResetConfirm = false
    @State private var exportText: String?
    @State private var statusMessage: String?

    public init(
        userTrainingFileSize: Int64,
        userTrainingSizeDescription: String,
        onImport: @escaping (String) -> Void,
        onExport: @escaping () -> String?,
        onReset: @escaping () -> Void
    ) {
        self.userTrainingFileSize = userTrainingFileSize
        self.userTrainingSizeDescription = userTrainingSizeDescription
        self.onImport = onImport
        self.onExport = onExport
        self.onReset = onReset
    }

    public var body: some View {
        Section {
            HStack {
                Text("Training Data")
                Spacer()
                Text(userTrainingSizeDescription)
                    .foregroundColor(.secondary)
                    .font(.callout)
            }

            Button {
                showImportPicker = true
            } label: {
                Label("Import Training Text", systemImage: "square.and.arrow.down")
            }

            Button {
                if let text = onExport() {
                    exportText = text
                    showExportPicker = true
                } else {
                    statusMessage = "No training data to export yet."
                }
            } label: {
                Label("Export Training Text", systemImage: "square.and.arrow.up")
            }
            .disabled(userTrainingFileSize == 0)

            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Reset Training Data", systemImage: "arrow.counterclockwise")
            }
            .disabled(userTrainingFileSize == 0)
        } header: {
            Text("Training Data")
        } footer: {
            Text("Import adds text to the language model (appends to existing learning). Export saves your accumulated training data for backup or transfer. Reset deletes custom training data — the model returns to its built-in defaults on next launch.")
                .font(.caption)
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.plainText]
        ) { result in
            switch result {
            case .success(let url):
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let text = try? String(contentsOf: url, encoding: .utf8) {
                        onImport(text)
                        statusMessage = "Training text imported successfully."
                    } else {
                        statusMessage = "Could not read the selected file."
                    }
                }
            case .failure:
                statusMessage = "Could not open the selected file."
            }
        }
        .fileExporter(
            isPresented: $showExportPicker,
            document: ExportableTextDocument(text: exportText ?? ""),
            contentType: .plainText,
            defaultFilename: "dasher_training"
        ) { result in
            switch result {
            case .success:
                statusMessage = "Training text exported."
            case .failure:
                statusMessage = "Could not export training text."
            }
        }
        .alert("Reset Training Data?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                onReset()
                statusMessage = "Training data reset. Restart Dasher to apply."
            }
        } message: {
            Text("This deletes your accumulated training data. The language model will return to built-in defaults on next launch. This cannot be undone.")
        }
        .alert("Training", isPresented: Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )) {
            Button("OK") { statusMessage = nil }
        } message: {
            Text(statusMessage ?? "")
        }
    }
}

/// A minimal FileDocument wrapper for exporting plain text.
public struct ExportableTextDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.plainText] }
    public var text: String

    public init(text: String) { self.text = text }
    public init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(data: data, encoding: .utf8) ?? ""
    }
    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
