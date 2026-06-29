import Foundation

/// Thread-safe ring buffer of recent engine diagnostic log lines (RFC 0009).
///
/// Kept so a crash report can include a "what was the engine doing" tail. The
/// ring is mirrored to `engine.log` in the App Group container on every append,
/// so it survives a hard crash (where the in-memory ring is lost) and can be
/// attached to an unclean-shutdown report on the next launch.
///
/// Shared across targets; currently fed by the macOS bridge's log callback.
public final class EngineLogBuffer {
    public static let shared = EngineLogBuffer()

    private struct Entry {
        let level: Int
        let message: String
    }

    private let lock = NSLock()
    private var ring: [Entry] = []
    private let maxLines = 64
    private let maxBytes = 8 * 1024

    private lazy var logFileURL: URL? = {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedDefaults.groupIdentifier
        ) else { return nil }
        let dir = container.appendingPathComponent("diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("engine.log")
    }()

    private init() {
        _ = logFileURL // touch lazy init
    }

    /// Append a line. Called from the engine log callback (any thread). Levels
    /// mirror `dasher_set_log_callback`: 0 debug / 1 info / 2 warn / 3 error.
    public func append(level: Int, message: String) {
        let trimmed = String(message.prefix(512))
        lock.lock()
        defer { lock.unlock() }
        ring.append(Entry(level: level, message: trimmed))
        if ring.count > maxLines { ring.removeFirst(ring.count - maxLines) }
        trimToBytesLocked()
        persistLocked()
    }

    /// Read the persisted tail (for crash reports where the in-memory ring is
    /// gone). Returns at most `maxBytes` of the most recent lines.
    public func persistedTail(maxBytes: Int = 8 * 1024) -> String {
        guard let url = logFileURL, let data = try? Data(contentsOf: url) else { return "" }
        return String(data: data.suffix(maxBytes), encoding: .utf8) ?? ""
    }

    private func trimToBytesLocked() {
        var total = ring.reduce(0) { $0 + $1.message.utf8.count }
        while total > maxBytes, !ring.isEmpty {
            let removed = ring.removeFirst()
            total -= removed.message.utf8.count
        }
    }

    /// Overwrite engine.log with the current ring (bounded, always current).
    /// Called under lock; engine logs are sparse so the rewrite cost is fine.
    private func persistLocked() {
        guard let url = logFileURL else { return }
        let blob = ring.map { "\($0.level) \($0.message)" }.joined(separator: "\n")
        try? blob.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}
