import Foundation

/// Manages user training corpora at the engine-owned root layout (Fixes #53;
/// DasherCore #84/#85/#86, Dasher-Windows `dd41e39`, Dasher-GTK `b00c2c9` parity).
///
/// Key invariants:
/// 1. **Root `userDir` layout**: `DasherCore` (`dasher_capi_version() >= 1`) scans
///    and appends `<userDir>/training_<alphabet>.txt` at the **root** of `userDir`
///    (queried via `dasher_get_training_path(ctx)`), NOT `<userDir>/training/`.
/// 2. **Stranded file rescue**: Earlier v6 builds wrote imported and v5-migrated
///    corpora into `<userDir>/training/training_*.txt`. `migrateStrandedTrainingFiles(in:)`
///    moves/merges those files into `<userDir>` root before `dasher_create` runs.
/// 3. **Writable `userDir` fallback**: When the App Group container is unavailable
///    (e.g. unsigned local builds), `resolveUserDirectory` falls back to
///    `~/Library/Application Support/Dasher` instead of the read-only app bundle.
/// 4. **10 MB import cap & newline boundary**: Imports over 10 MB are rejected
///    before stalling the UI thread, and appending to a non-empty file that does
///    not end with `\n` inserts a newline separator first.
public enum TrainingDataManager {
    /// Maximum size of a single imported training file (10 MB).
    public static let maxImportBytes: Int = 10 * 1024 * 1024

    public enum ImportError: LocalizedError, Equatable {
        case emptyText
        case exceedsMaxSize(Int)
        case sameFileAsActiveTraining
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .emptyText:
                return "The selected training file is empty."
            case .exceedsMaxSize:
                return "Training file exceeds the 10 MB size limit."
            case .sameFileAsActiveTraining:
                return "Cannot import the active training file into itself."
            case .writeFailed(let detail):
                return "Could not save training text: \(detail)"
            }
        }
    }

    /// Resolves a writable user directory for settings and training files.
    /// Never returns the read-only bundle `fallbackDataDir` unless every writable
    /// location fails.
    public static func resolveUserDirectory(
        explicitUserDir: String? = nil,
        fallbackDataDir: String,
        applicationSupportOverride: URL? = nil
    ) -> String {
        let fm = FileManager.default

        if let explicit = explicitUserDir, !explicit.isEmpty, explicit != fallbackDataDir {
            try? fm.createDirectory(atPath: explicit, withIntermediateDirectories: true)
            return explicit
        }

        if applicationSupportOverride == nil,
           let sharedURL = fm.containerURL(forSecurityApplicationGroupIdentifier: SharedDefaults.groupIdentifier) {
            try? fm.createDirectory(at: sharedURL, withIntermediateDirectories: true)
            return sharedURL.path
        }

        let appSupportBase = applicationSupportOverride
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let appSupportBase {
            let dasherDir = appSupportBase.appendingPathComponent("Dasher", isDirectory: true)
            try? fm.createDirectory(at: dasherDir, withIntermediateDirectories: true)
            return dasherDir.path
        }

        return fallbackDataDir
    }

    /// Rescues any `training_*.txt` files stranded in `<userDir>/training/` by
    /// earlier v6 builds, moving or appending them into `<userDir>` root where
    /// `DasherCore` reads and writes user training data.
    public static func migrateStrandedTrainingFiles(in userDir: String) {
        guard !userDir.isEmpty else { return }
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: userDir, isDirectory: true)
        let legacyDirURL = rootURL.appendingPathComponent("training", isDirectory: true)

        // Guard against migrating bundled training files if userDir somehow
        // points at a bundle Data directory containing gamemode_* files.
        guard !fm.fileExists(atPath: legacyDirURL.appendingPathComponent("gamemode_english_GB.txt").path) else {
            return
        }

        guard let entries = try? fm.contentsOfDirectory(atPath: legacyDirURL.path) else {
            return
        }

        for entry in entries.sorted() where entry.hasPrefix("training_") && entry.hasSuffix(".txt") {
            let legacyFileURL = legacyDirURL.appendingPathComponent(entry)
            let rootFileURL = rootURL.appendingPathComponent(entry)

            if !fm.fileExists(atPath: rootFileURL.path) {
                try? fm.moveItem(at: legacyFileURL, to: rootFileURL)
            } else {
                do {
                    let legacyData = try Data(contentsOf: legacyFileURL)
                    if !legacyData.isEmpty {
                        try appendRawDataWithNewlineBoundary(legacyData, to: rootFileURL)
                    }
                    try fm.removeItem(at: legacyFileURL)
                } catch {
                    // Leave legacyFileURL untouched if reading or merging failed
                    // so user training data is never lost.
                    continue
                }
            }
        }

        // Remove the legacy `training/` directory if it is now empty.
        if let remaining = try? fm.contentsOfDirectory(atPath: legacyDirURL.path), remaining.isEmpty {
            try? fm.removeItem(at: legacyDirURL)
        }
    }

    /// Merges a Dasher v5 training file into a v6 root training file path.
    /// Handles identical source/destination paths (`v5UserDataDir == destDir`)
    /// and merges with a newline separator when v6 has already written adaptive
    /// training text to `destURL`.
    public static func migrateV5TrainingFile(from srcURL: URL, to destURL: URL) throws -> Bool {
        let fm = FileManager.default
        let canonicalSrc = srcURL.resolvingSymlinksInPath().standardizedFileURL.path
        let canonicalDest = destURL.resolvingSymlinksInPath().standardizedFileURL.path
        if !canonicalSrc.isEmpty && canonicalSrc == canonicalDest {
            return true
        }

        guard fm.fileExists(atPath: srcURL.path) else { return false }
        if !fm.fileExists(atPath: destURL.path) {
            try fm.copyItem(at: srcURL, to: destURL)
            return true
        }

        let srcData = try Data(contentsOf: srcURL)
        guard !srcData.isEmpty else { return false }

        if let existingData = try? Data(contentsOf: destURL),
           existingData.range(of: srcData) != nil {
            // Already merged previously.
            return false
        }

        try appendRawDataWithNewlineBoundary(srcData, to: destURL)
        return true
    }

    /// Resolves the active user training file URL.
    ///
    /// When `engineReportedPath` (`dasher_get_training_path(ctx)`) is non-empty,
    /// returns that exact URL so operations stay strictly scoped to the active
    /// alphabet. Only falls back to scanning `<userDir>` root when the engine
    /// has not yet reported a path (`engineReportedPath == nil` or empty).
    public static func resolveTrainingFileURL(
        engineReportedPath: String?,
        userDir: String,
        createDefaultIfMissing: Bool = false
    ) -> URL? {
        if let reported = engineReportedPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reported.isEmpty {
            return URL(fileURLWithPath: reported)
        }

        guard !userDir.isEmpty else { return nil }
        let rootURL = URL(fileURLWithPath: userDir, isDirectory: true)
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: rootURL.path) {
            let matches = files
                .filter { $0.hasPrefix("training_") && $0.hasSuffix(".txt") }
                .sorted()
            if let first = matches.first {
                return rootURL.appendingPathComponent(first)
            }
        }

        if createDefaultIfMissing {
            return rootURL.appendingPathComponent("training_english_GB.txt")
        }
        return nil
    }

    /// Size in bytes of the active alphabet's user training file.
    /// When `engineReportedPath` is provided, checks ONLY that file so another
    /// alphabet's corpus is never misattributed to the active alphabet.
    public static func fileSize(engineReportedPath: String?, userDir: String) -> Int64 {
        guard let url = resolveTrainingFileURL(engineReportedPath: engineReportedPath, userDir: userDir),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else {
            return 0
        }
        return max(0, size.int64Value)
    }

    /// Returns `true` if any `training_*.txt` file with size `> 0` exists in
    /// `<userDir>` root or legacy `<userDir>/training/` (used to enable Reset
    /// even when the currently selected alphabet has no training file yet).
    public static func hasAnyUserTrainingFiles(in userDir: String) -> Bool {
        guard !userDir.isEmpty else { return false }
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: userDir, isDirectory: true)
        if let files = try? fm.contentsOfDirectory(atPath: rootURL.path) {
            for file in files where file.hasPrefix("training_") && file.hasSuffix(".txt") {
                let path = rootURL.appendingPathComponent(file).path
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let size = attrs[.size] as? NSNumber,
                   size.int64Value > 0 {
                    return true
                }
            }
        }
        return false
    }

    /// Human-readable size description matching existing UI strings.
    public static func sizeDescription(bytes: Int64) -> String {
        if bytes <= 0 {
            return "No custom training data"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Validates and appends imported training text to the engine-owned training
    /// file on disk, inserting a newline boundary if the existing file does not
    /// end with `\n`.
    @discardableResult
    public static func persistImportedTrainingText(
        _ text: String,
        sourceFileURL: URL? = nil,
        engineReportedPath: String?,
        userDir: String
    ) throws -> URL {
        let utf8Data = Data(text.utf8)
        guard !utf8Data.isEmpty else {
            throw ImportError.emptyText
        }
        guard utf8Data.count <= maxImportBytes else {
            throw ImportError.exceedsMaxSize(utf8Data.count)
        }
        guard let targetURL = resolveTrainingFileURL(
            engineReportedPath: engineReportedPath,
            userDir: userDir,
            createDefaultIfMissing: true
        ) else {
            throw ImportError.writeFailed("No writable user directory")
        }

        if let sourceFileURL {
            let canonicalSource = sourceFileURL.resolvingSymlinksInPath().standardizedFileURL.path
            let canonicalTarget = targetURL.resolvingSymlinksInPath().standardizedFileURL.path
            if !canonicalSource.isEmpty && canonicalSource == canonicalTarget {
                throw ImportError.sameFileAsActiveTraining
            }
        }

        do {
            try appendRawDataWithNewlineBoundary(utf8Data, to: targetURL)
            return targetURL
        } catch {
            throw ImportError.writeFailed(error.localizedDescription)
        }
    }

    /// Exports the user's accumulated training text for the active alphabet
    /// (or first available `training_*.txt` in `userDir` root when `engineReportedPath`
    /// is nil/empty). Never falls back to a different alphabet when `engineReportedPath`
    /// is non-empty.
    public static func exportTrainingText(engineReportedPath: String?, userDir: String) -> String? {
        let fm = FileManager.default
        guard let url = resolveTrainingFileURL(engineReportedPath: engineReportedPath, userDir: userDir),
              fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              !data.isEmpty else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Deletes all user `training_*.txt` files at the root of `userDir` as well
    /// as any legacy `<userDir>/training/training_*.txt` files.
    public static func resetTrainingData(in userDir: String) {
        guard !userDir.isEmpty else { return }
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: userDir, isDirectory: true)

        if let rootFiles = try? fm.contentsOfDirectory(atPath: rootURL.path) {
            for file in rootFiles where file.hasPrefix("training_") && file.hasSuffix(".txt") {
                try? fm.removeItem(at: rootURL.appendingPathComponent(file))
            }
        }

        let legacyDirURL = rootURL.appendingPathComponent("training", isDirectory: true)
        // Never delete bundled Data/training files if userDir was pointed at bundle Data.
        guard !fm.fileExists(atPath: legacyDirURL.appendingPathComponent("gamemode_english_GB.txt").path) else {
            return
        }
        if let legacyFiles = try? fm.contentsOfDirectory(atPath: legacyDirURL.path) {
            for file in legacyFiles where file.hasPrefix("training_") && file.hasSuffix(".txt") {
                try? fm.removeItem(at: legacyDirURL.appendingPathComponent(file))
            }
        }
    }

    // MARK: - Helpers

    internal static func appendRawDataWithNewlineBoundary(_ data: Data, to fileURL: URL) throws {
        let fm = FileManager.default
        let parentDir = fileURL.deletingLastPathComponent()
        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

        if fm.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forUpdating: fileURL)
            defer { try? handle.close() }
            let endOffset = try handle.seekToEnd()
            if endOffset > 0 && data.first != 0x0A {
                try handle.seek(toOffset: endOffset - 1)
                let lastByte = try handle.read(upToCount: 1)?.first
                _ = try handle.seekToEnd()
                if lastByte != 0x0A {
                    try handle.write(contentsOf: Data([0x0A]))
                }
            }
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL, options: .atomic)
        }
    }
}
