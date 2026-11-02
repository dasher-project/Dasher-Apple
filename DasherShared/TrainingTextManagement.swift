import SwiftUI
import UniformTypeIdentifiers

/// Reusable training text management section for Settings → Language.
/// Shows current training data size, with import / export / reset buttons.
/// Used by DasherApp (iOS), DasherMac, and DasherVision.
public struct TrainingTextManagementSection: View {
    let userTrainingFileSize: Int64
    let userTrainingSizeDescription: String
    let sizeProvider: (() -> (Int64, String))?
    let onImport: (String, URL?) throws -> Void
    let onExport: () -> String?
    let onReset: () -> Void

    @State private var currentFileSize: Int64 = 0
    @State private var currentSizeDescription: String = ""
    @State private var showImportPicker = false
    @State private var showExportPicker = false
    @State private var showResetConfirm = false
    @State private var exportText: String?
    @State private var statusMessage: String?

    public init(
        userTrainingFileSize: Int64,
        userTrainingSizeDescription: String,
        sizeProvider: (() -> (Int64, String))? = nil,
        onImport: @escaping (String) -> Void,
        onExport: @escaping () -> String?,
        onReset: @escaping () -> Void
    ) {
        self.init(
            userTrainingFileSize: userTrainingFileSize,
            userTrainingSizeDescription: userTrainingSizeDescription,
            sizeProvider: sizeProvider,
            onImportFile: { text, _ in onImport(text) },
            onExport: onExport,
            onReset: onReset
        )
    }

    public init(
        userTrainingFileSize: Int64,
        userTrainingSizeDescription: String,
        sizeProvider: (() -> (Int64, String))? = nil,
        onImportFile: @escaping (String, URL?) throws -> Void,
        onExport: @escaping () -> String?,
        onReset: @escaping () -> Void
    ) {
        self.userTrainingFileSize = userTrainingFileSize
        self.userTrainingSizeDescription = userTrainingSizeDescription
        self.sizeProvider = sizeProvider
        self.onImport = onImportFile
        self.onExport = onExport
        self.onReset = onReset
        self._currentFileSize = State(initialValue: userTrainingFileSize)
        self._currentSizeDescription = State(initialValue: userTrainingSizeDescription)
    }

    private func refreshSize() {
        if let sizeProvider {
            let (bytes, desc) = sizeProvider()
            currentFileSize = bytes
            currentSizeDescription = desc
        } else {
            currentFileSize = userTrainingFileSize
            currentSizeDescription = userTrainingSizeDescription
        }
    }

    public var body: some View {
        Section {
            HStack {
                Text("Training Data")
                Spacer()
                Text(currentSizeDescription)
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
            .disabled(currentFileSize == 0)

            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Reset Training Data", systemImage: "arrow.counterclockwise")
            }
            .disabled(currentFileSize == 0)
        } header: {
            Text("Training Data")
        } footer: {
            Text("Import adds text to the language model (appends to existing learning). Export saves your accumulated training data for backup or transfer. Reset deletes custom training data — the model returns to its built-in defaults on next launch.")
                .font(.caption)
        }
        .onAppear {
            refreshSize()
        }
        .onChange(of: userTrainingFileSize) { _, _ in
            refreshSize()
        }
        .onChange(of: userTrainingSizeDescription) { _, _ in
            refreshSize()
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.plainText]
        ) { result in
            switch result {
            case .success(let url):
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }
                // Check the 10 MB size cap BEFORE reading the file on the UI thread.
                if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = values.fileSize,
                   fileSize > TrainingDataManager.maxImportBytes {
                    statusMessage = TrainingDataManager.ImportError.exceedsMaxSize(fileSize).localizedDescription
                    return
                }
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                    statusMessage = "Could not read the selected file."
                    return
                }
                guard data.count <= TrainingDataManager.maxImportBytes else {
                    statusMessage = TrainingDataManager.ImportError.exceedsMaxSize(data.count).localizedDescription
                    return
                }
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                    statusMessage = data.isEmpty
                        ? TrainingDataManager.ImportError.emptyText.localizedDescription
                        : "Could not read the selected file as UTF-8 text."
                    return
                }
                do {
                    try onImport(text, url)
                    refreshSize()
                    statusMessage = "Training text imported successfully."
                } catch {
                    statusMessage = error.localizedDescription
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
                currentFileSize = 0
                currentSizeDescription = TrainingDataManager.sizeDescription(bytes: 0)
                refreshSize()
                statusMessage = "Training data reset. Restart Dasher to apply."
            }
        } message: {
            Text("This deletes your accumulated training data files. Very recent typing from the current session may still influence predictions until Dasher is restarted. This cannot be undone.")
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
