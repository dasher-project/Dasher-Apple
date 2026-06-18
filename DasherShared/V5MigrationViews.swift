import SwiftUI

#if os(macOS)

/// First-launch v5 migration prompt (RFC 0005).
public struct V5MigrationPrompt: View {
    let scanResult: V5MigrationResult
    let onImport: () -> Void
    let onSkip: () -> Void

    public init(scanResult: V5MigrationResult, onImport: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.scanResult = scanResult
        self.onImport = onImport
        self.onSkip = onSkip
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                LucideIcon("arrow-down-to-line", size: 32, color: Color("DasherTeal"))

                Text("Import from Dasher 5")
                    .font(.title2.bold())
                    .foregroundColor(Color("DeepNavy"))

                Text("We found your Dasher 5 configuration on this Mac. Your alphabet, colours, speed settings, and custom files can be imported into Dasher 6.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.top, 32)
            .padding(.bottom, 20)

            if scanResult.hasData {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What was found")
                        .font(.subheadline.bold())
                        .foregroundColor(Color("DeepNavy"))

                    if scanResult.foundSettings {
                        HStack(spacing: 8) {
                            LucideIcon("settings", size: 14, color: .secondary)
                            Text("Settings (speed, colours, control mode, language model)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    ForEach(scanResult.foundCustomFiles, id: \.self) { file in
                        HStack(spacing: 8) {
                            LucideIcon("file-text", size: 14, color: .secondary)
                            Text(file)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    ForEach(scanResult.foundTrainingFiles, id: \.self) { file in
                        HStack(spacing: 8) {
                            LucideIcon("graduation-cap", size: 14, color: .secondary)
                            Text("Adaptive training: \(file)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    onImport()
                } label: {
                    Text("Import settings")
                        .font(.headline)
                        .foregroundColor(Color("DeepNavy"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color("DasherTeal"))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button {
                    onSkip()
                } label: {
                    Text("Start fresh")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                Text("You can import later in Settings > Privacy & Migration")
                    .font(.caption2)
                    .foregroundColor(Color("MutedText"))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
    }
}

/// Settings > Migration panel showing migration status and re-import option.
public struct V5MigrationSettingsSection: View {
    @State private var scanResult = V5MigrationResult()
    @State private var importResult: V5MigrationResult?
    @State private var hasImported = V5MigrationService.hasBeenCompleted

    public init() {}

    public var body: some View {
        Section {
            if !scanResult.hasData {
                Text("No Dasher 5 data found on this Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if hasImported {
                Text("Dasher 5 settings imported successfully.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let result = importResult ?? nil {
                    if !result.importedSettings.isEmpty {
                        Divider()
                        Text("Imported settings (\(result.importedSettings.count))")
                            .font(.caption.bold())
                        ForEach(result.importedSettings, id: \.name) { item in
                            Text("\(item.name): \(item.value)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    if !result.importedFiles.isEmpty {
                        Divider()
                        Text("Imported files (\(result.importedFiles.count))")
                            .font(.caption.bold())
                        ForEach(result.importedFiles, id: \.self) { file in
                            Text(file)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    if !result.skippedFiles.isEmpty {
                        Divider()
                        Text("Skipped files")
                            .font(.caption.bold())
                        ForEach(result.skippedFiles, id: \.name) { item in
                            Text("\(item.name): \(item.reason)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button("Re-import from Dasher 5") {
                    V5MigrationService.resetMigrationState()
                    hasImported = false
                }
                .foregroundColor(.accentColor)
            } else {
                Text("Dasher 5 data detected on this Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(scanResult.foundCustomFiles, id: \.self) { file in
                    Text("• \(file)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ForEach(scanResult.foundTrainingFiles, id: \.self) { file in
                    Text("• Training: \(file)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Import from Dasher 5") {
                    let result = V5MigrationService.importSettings(
                        bridge: MigrationBridgeHolder.shared.bridge!,
                        userDir: MigrationBridgeHolder.shared.userDir
                    )
                    if !result.deferredParameters.isEmpty {
                        V5MigrationService.applyDeferredParameters(
                            result.deferredParameters,
                            bridge: MigrationBridgeHolder.shared.bridge!
                        )
                    }
                    importResult = result
                    hasImported = true
                }
                .foregroundColor(.accentColor)
            }
        } header: {
            Text("Migration")
        }
        .onAppear {
            scanResult = V5MigrationService.scan()
        }
    }
}

/// Holder for bridge reference — set by the app delegate during launch.
public final class MigrationBridgeHolder {
    public static let shared = MigrationBridgeHolder()
    public var bridge: AccessSettingsBridge?
    public var userDir: String = ""
    private init() {}
}

#endif // os(macOS)
