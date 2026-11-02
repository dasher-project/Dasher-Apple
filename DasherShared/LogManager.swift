import Foundation
import SwiftUI

/// Centralised diagnostic log management (RFC 0022; Dasher-Windows PR #82 parity).
///
/// Owns:
/// - **Version-scoped rotation**: on app-version change, the previous session's
///   live logs are archived (`keyboard_debug.v{oldVersion}.log`, etc.) so each
///   release starts clean and a tester's log is scoped to the build that produced it.
/// - **Startup size cap**: if a live or archived log exceeds `maxLogSizeBytes`
///   (10 MB), it is truncated to its last `truncateKeepLines` (1,000) lines at
///   the next startup (never mid-write, which would corrupt a line).
/// - **Archive pruning**: keeps at most `maxArchives` (2) archived logs per prefix.
/// - **The "Advanced logging" toggle**: gates verbose per-sample / per-keystroke
///   traces (messages starting with two spaces `"  "`). Non-indented lifecycle
///   events (engine created, target switched, context seeded, errors) are always
///   logged.
///
/// Privacy invariant (RFC 0022 §6): callers must NEVER pass target text content,
/// typed characters, or clipboard strings to `LogManager` — only character counts,
/// UTF-16 caret offsets, bundle identifiers, and seed/skip decisions.
public enum LogManager {
    /// Managed log filenames relative to the Dasher log directory.
    /// (Apple does not have a separate eye-gaze tracker daemon log; only
    /// `keyboard_debug.log` is managed on Apple platforms.)
    public static let managedLogs: [String] = [
        "keyboard_debug.log",
    ]

    /// Maximum size of a single log file before next-startup truncation (10 MB).
    public static let maxLogSizeBytes: Int64 = 10 * 1024 * 1024

    /// Number of trailing lines retained when truncating an oversized log.
    public static let truncateKeepLines: Int = 1_000

    /// Maximum number of `.v{oldVersion}.log` archives retained per log prefix.
    public static let maxArchives: Int = 2

    /// Marker file recording the version string of the last session.
    public static let versionMarkerFile: String = "last_version.txt"

    /// UserDefaults key for the "Advanced logging" setting.
    public static let advancedLoggingKey: String = "advanced_logging"

    private static let lock = NSLock()
    private static var _advancedLogging: Bool = SharedDefaults.fallback.bool(forKey: advancedLoggingKey)
    private static var _customLogDirectory: URL?

    private static var defaultLogDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Dasher", isDirectory: true)
    }

    /// Default log directory: `~/Library/Application Support/Dasher/` on macOS
    /// and iOS (creating it on demand). Tests may override via `initialize(currentVersion:logDirectory:)`.
    public static var logDirectory: URL {
        lock.lock()
        defer { lock.unlock() }
        return _customLogDirectory ?? defaultLogDirectory
    }

    /// Whether verbose diagnostic logging (two-space-indented trace messages) is enabled.
    /// Off by default; persisted in `SharedDefaults.fallback`.
    public static var advancedLogging: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _advancedLogging
        }
        set {
            setAdvancedLogging(newValue)
        }
    }

    /// Update the `advancedLogging` flag and persist it to `SharedDefaults`.
    public static func setAdvancedLogging(_ enabled: Bool) {
        lock.lock()
        _advancedLogging = enabled
        lock.unlock()
        SharedDefaults.fallback.set(enabled, forKey: advancedLoggingKey)
    }

    /// Re-read the persisted `advancedLogging` flag from `SharedDefaults.fallback`.
    public static func syncFromDefaults() {
        let persisted = SharedDefaults.fallback.bool(forKey: advancedLoggingKey)
        lock.lock()
        _advancedLogging = persisted
        lock.unlock()
    }

    /// Reset `_customLogDirectory` without touching disk (for unit test tearDown).
    internal static func resetCustomLogDirectoryForTesting() {
        lock.lock()
        _customLogDirectory = nil
        lock.unlock()
    }

    /// Call once at app startup before any log writes.
    ///
    /// Performs:
    /// 1. Size-cap truncation on live logs (`> 10 MB` → last 1,000 lines) *before* rotation.
    /// 2. Size-cap truncation on existing archives (`*.v*.log` `> 10 MB`).
    /// 3. Version-change rotation (`{name}.log` → `{name}.v{oldVersion}.log`) and archive pruning (`maxArchives = 2`).
    public static func initialize(currentVersion: String, logDirectory customDirectory: URL? = nil) {
        let persistedAdvanced = SharedDefaults.fallback.bool(forKey: advancedLoggingKey)

        lock.lock()
        defer { lock.unlock() }

        _customLogDirectory = customDirectory
        _advancedLogging = persistedAdvanced
        let dir = _customLogDirectory ?? defaultLogDirectory

        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // 1. Enforce size cap on live logs BEFORE rotation so an oversized log
        //    is not archived at full size.
        for name in managedLogs {
            enforceSizeCapLocked(at: dir.appendingPathComponent(name))
        }

        // 2. Also cap any oversized archives left over from earlier builds.
        for name in managedLogs {
            let prefix = (name as NSString).deletingPathExtension
            for archiveURL in archivesLocked(forPrefix: prefix, in: dir) {
                enforceSizeCapLocked(at: archiveURL)
            }
        }

        // 3. Version-change rotation + archive pruning.
        let normalizedCurrent = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let markerURL = dir.appendingPathComponent(versionMarkerFile)
        let previousVersion = (try? String(contentsOf: markerURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if previousVersion != normalizedCurrent {
            let oldTag = (previousVersion?.isEmpty == false) ? previousVersion! : "unknown"
            rotateForVersionChangeLocked(oldVersion: oldTag, in: dir)
            try? normalizedCurrent.write(to: markerURL, atomically: true, encoding: .utf8)
        }

        // Always enforce archive retention cap at startup.
        pruneOldArchivesLocked(in: dir)
    }

    // MARK: - Logging Entry Points

    /// Append a line to `keyboard_debug.log`.
    ///
    /// Indentation convention (RFC 0022 §3): messages starting with `"  "` (two
    /// spaces) are verbose traces and are skipped when `advancedLogging` is `false`.
    /// Non-indented messages are lifecycle events and are always written.
    public static func kb(_ message: String, in directory: URL? = nil) {
        write(tag: "KB", fileName: "keyboard_debug.log", message: message, in: directory)
    }

    private static func write(tag: String, fileName: String, message: String, in directory: URL?) {
        let timestamp = formatTimestamp(Date())
        let line = "[\(tag)] \(timestamp) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        lock.lock()
        defer { lock.unlock() }

        if message.hasPrefix("  ") && !_advancedLogging {
            return
        }

        let dir = directory ?? (_customLogDirectory ?? defaultLogDirectory)
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(fileName)
        if fm.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: fileURL)
        }
    }

    private static func formatTimestamp(_ date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        let s = comps.second ?? 0
        let ms = (comps.nanosecond ?? 0) / 1_000_000
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }

    // MARK: - Clear & Size Reporting

    /// Delete all managed log files and their `.v*.log` archives.
    public static func clearLogs(in directory: URL? = nil) {
        lock.lock()
        defer { lock.unlock() }

        let dir = directory ?? (_customLogDirectory ?? defaultLogDirectory)
        let fm = FileManager.default
        for name in managedLogs {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
            let prefix = (name as NSString).deletingPathExtension
            for archiveURL in archivesLocked(forPrefix: prefix, in: dir) {
                try? fm.removeItem(at: archiveURL)
            }
        }
    }

    /// Total size in bytes of all managed live and archived logs.
    public static func totalLogSizeBytes(in directory: URL? = nil) -> Int64 {
        lock.lock()
        defer { lock.unlock() }

        let dir = directory ?? (_customLogDirectory ?? defaultLogDirectory)
        let fm = FileManager.default
        var total: Int64 = 0
        for name in managedLogs {
            let liveURL = dir.appendingPathComponent(name)
            total += fileSizeLocked(at: liveURL, fm: fm)
            let prefix = (name as NSString).deletingPathExtension
            for archiveURL in archivesLocked(forPrefix: prefix, in: dir) {
                total += fileSizeLocked(at: archiveURL, fm: fm)
            }
        }
        return total
    }

    /// Human-readable summary of total log size (e.g. `"0 KB"`, `"42 KB"`, `"3.4 MB"`).
    /// Matches `Dasher.Windows.Services.LogManager.GetTotalLogSize()`.
    public static func totalLogSizeDescription(in directory: URL? = nil) -> String {
        let totalBytes = totalLogSizeBytes(in: directory)
        if totalBytes <= 0 {
            return "0 KB"
        }
        if totalBytes < 1024 * 1024 {
            return "\(max(1, totalBytes / 1024)) KB"
        }
        return String(format: "%.1f MB", Double(totalBytes) / (1024.0 * 1024.0))
    }

    // MARK: - Internal Rotation & Truncation Helpers (caller holds lock)

    private static func rotateForVersionChangeLocked(oldVersion: String, in dir: URL) {
        let fm = FileManager.default
        let safeVersion = sanitizeVersionForFilename(oldVersion)

        for name in managedLogs {
            let liveURL = dir.appendingPathComponent(name)
            guard fileSizeLocked(at: liveURL, fm: fm) > 0 else { continue }

            let prefix = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            let archiveName = "\(prefix).v\(safeVersion).\(ext)"
            let archiveURL = dir.appendingPathComponent(archiveName)

            try? fm.removeItem(at: archiveURL)
            try? fm.moveItem(at: liveURL, to: archiveURL)
        }
    }

    private static func pruneOldArchivesLocked(in dir: URL) {
        let fm = FileManager.default
        for name in managedLogs {
            let prefix = (name as NSString).deletingPathExtension
            let sortedArchives = archivesLocked(forPrefix: prefix, in: dir).sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return dateA > dateB
            }
            for oldArchive in sortedArchives.dropFirst(maxArchives) {
                try? fm.removeItem(at: oldArchive)
            }
        }
    }

    private static func enforceSizeCapLocked(at fileURL: URL) {
        let fm = FileManager.default
        let size = fileSizeLocked(at: fileURL, fm: fm)
        guard size > maxLogSizeBytes else { return }

        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return }
        // Decode lossily so a malformed UTF-8 byte from a prior crash never
        // prevents truncating an oversized log file.
        let content = String(decoding: data, as: UTF8.self)
        var lines = content.components(separatedBy: .newlines)
        if lines.last == "" {
            lines.removeLast()
        }
        let keptCount = min(truncateKeepLines, lines.count)
        let kept = lines.suffix(keptCount)
        let header = "[log truncated at startup — exceeded 10 MB; keeping last \(kept.count) of \(lines.count) lines]"
        let rebuilt = ([header] + kept).joined(separator: "\n") + "\n"
        try? rebuilt.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func archivesLocked(forPrefix prefix: String, in dir: URL) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let requiredPrefix = "\(prefix).v"
        return urls.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix(requiredPrefix) && name.hasSuffix(".log")
        }
    }

    private static func fileSizeLocked(at url: URL, fm: FileManager) -> Int64 {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    private static func sanitizeVersionForFilename(_ version: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<> ")
        return version.components(separatedBy: invalid).joined(separator: "_")
    }
}

/// Reusable Settings control for RFC 0022 diagnostic logging ("Advanced logging"
/// toggle + help text + "Clear logs" button with live total byte size).
public struct DiagnosticLoggingSection: View {
    @State private var advancedLogging: Bool = LogManager.advancedLogging
    @State private var logSizeText: String = LogManager.totalLogSizeDescription()

    public init() {}

    public var body: some View {
        let toggleBinding = Binding<Bool>(
            get: { advancedLogging },
            set: { newValue in
                guard newValue != advancedLogging else { return }
                advancedLogging = newValue
                LogManager.setAdvancedLogging(newValue)
                UITelemetry.setting("advanced_logging", newValue, surface: "settings")
            }
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Advanced logging")
                    Text("Detailed diagnostic logging for bug reports (per-sample eye-tracker lines, keystroke traces, UIA reads). Basic connection events are always logged. May generate large log files.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: toggleBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            HStack(spacing: 8) {
                Button("Clear logs") {
                    LogManager.clearLogs()
                    logSizeText = LogManager.totalLogSizeDescription()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text(logSizeText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            LogManager.syncFromDefaults()
            advancedLogging = LogManager.advancedLogging
            logSizeText = LogManager.totalLogSizeDescription()
        }
    }
}
