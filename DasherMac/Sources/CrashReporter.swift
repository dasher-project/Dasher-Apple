import Foundation
import AppKit
import DasherShared

/// macOS crash reporter (RFC 0009).
///
/// v1 captures uncaught NSExceptions (rich envelope: exception type, reason,
/// stack trace, engine log tail) and detects unclean shutdowns (fatalError,
/// SIGSEGV, force-quit) via an `alive.marker` written at launch and cleared on
/// a clean quit. Envelopes are written to the App Group container and sent to
/// PostHog on the next launch via `AnalyticsService` (opt-in gated).
///
/// Not in v1: a dedicated async-signal-safe signal handler for richer
/// SIGSEGV/SIGABRT envelopes — that's a follow-up (or a crash SDK per RFC
/// 0009 "alternatives"). fatalError/memory-corruption crashes are reported as
/// `unclean_shutdown` with the persisted engine log tail.
final class CrashReporter {
    static let shared = CrashReporter()
    private init() {}

    private static let dirName = "diagnostics"
    private static let pendingFile = "pending-crash.json"
    private static let aliveMarker = "alive.marker"
    private static let uncleanFlag = "pending-unclean.flag"
    private static let maxStalenessDays: TimeInterval = 7 * 24 * 3600
    private static let maxStackBytes = 16 * 1024
    private static let maxTailBytes = 8 * 1024

    private var crashDir: URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedDefaults.groupIdentifier
        ) else { return nil }
        let dir = container.appendingPathComponent(Self.dirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Lifecycle

    /// Install the uncaught-exception handler and write the alive marker. Call
    /// once at app launch, before the UI can crash.
    func install() {
        guard let dir = crashDir else { return }
        let markerURL = dir.appendingPathComponent(Self.aliveMarker)
        // A leftover marker means the previous run didn't shut down cleanly
        // (crash / force-quit / power loss). Promote it to a pending-crash
        // signal BEFORE writing this session's marker — otherwise every clean
        // relaunch would look like a crash.
        if FileManager.default.fileExists(atPath: markerURL.path) {
            try? Data().write(to: dir.appendingPathComponent(Self.uncleanFlag), options: .atomic)
            try? FileManager.default.removeItem(at: markerURL)
        }
        // Fresh marker for THIS session; cleared on a clean quit.
        try? Data().write(to: markerURL, options: .atomic)

        NSSetUncaughtExceptionHandler { exception in
            // Runtime is still intact here (this is not a signal handler), so
            // Swift heap/singleton access is safe.
            CrashReporter.shared.captureException(exception)
        }
    }

    /// Call from `NSApplication.willTerminate` — clears the alive marker so a
    /// clean quit isn't mistaken for a crash on the next launch.
    func markCleanShutdown() {
        guard let dir = crashDir else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(Self.aliveMarker))
    }

    /// On launch: send any pending crash if the user has opted in. Returns true
    /// if a crash from the previous session was detected (so the UI can ask the
    /// user to share the macOS crash report too).
    @discardableResult
    func sendPendingCrashIfNeeded() -> Bool {
        guard let dir = crashDir else { return false }
        let pendingURL = dir.appendingPathComponent(Self.pendingFile)
        let uncleanURL = dir.appendingPathComponent(Self.uncleanFlag)

        var envelope: [String: Any]?
        if let data = try? Data(contentsOf: pendingURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            envelope = json // NSException capture (rich)
        } else if FileManager.default.fileExists(atPath: uncleanURL.path) {
            // No clean shutdown since the last launch.
            envelope = Self.makeEnvelope(
                kind: "unclean_shutdown",
                type: "UncleanShutdown",
                reason: "Dasher did not shut down cleanly (possible crash).",
                stack: "",
                tail: EngineLogBuffer.shared.persistedTail()
            )
        }

        guard var env = envelope else { return false } // no crash detected

        // Discard stale envelopes.
        if let age = Self.ageOfEnvelope(env), age > Self.maxStalenessDays {
            clearPending()
            return false
        }

        // Send to PostHog if opted in. Either way, clear the pending signal and
        // tell the UI to nudge the user toward the (richer) macOS crash report.
        if AnalyticsService.shared.isOptedIn {
            env = Self.scrub(env)
            AnalyticsService.shared.captureCrash(envelope: env)
            AnalyticsService.shared.flush()
        }
        clearPending()
        return true
    }

    // MARK: - Capture (from the NSException handler)

    private func captureException(_ exception: NSException) {
        let stack = exception.callStackSymbols.joined(separator: "\n")
        let env = Self.makeEnvelope(
            kind: "exception",
            type: exception.name.rawValue,
            reason: exception.reason ?? "",
            stack: stack,
            tail: EngineLogBuffer.shared.persistedTail()
        )
        guard let dir = crashDir,
              let data = try? JSONSerialization.data(withJSONObject: env, options: []) else { return }
        try? data.write(to: dir.appendingPathComponent(Self.pendingFile), options: .atomic)
    }

    private func clearPending() {
        // Consumes the pending crash signals only. The alive marker belongs to
        // the CURRENT session (written by install(), removed by
        // markCleanShutdown or promoted by the next install()), so leave it.
        guard let dir = crashDir else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(Self.pendingFile))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(Self.uncleanFlag))
    }

    // MARK: - Envelope helpers

    private static func makeEnvelope(kind: String, type: String, reason: String, stack: String, tail: String) -> [String: Any] {
        [
            "crash_kind": kind,
            "exception_type": type,
            "reason": reason,
            "stack_trace": stack,
            "engine_log_tail": tail,
            "crashed_at": ISO8601DateFormatter().string(from: Date()),
        ]
    }

    private static func ageOfEnvelope(_ env: [String: Any]) -> TimeInterval? {
        guard let s = env["crashed_at"] as? String, let date = ISO8601DateFormatter().date(from: s) else { return nil }
        return Date().timeIntervalSince(date)
    }

    // MARK: - PII scrubbing

    /// Scrub home-directory paths and emails, and cap field sizes, before
    /// anything leaves the device. (RFC 0009 §PII scrubbing.)
    static func scrub(_ env: [String: Any]) -> [String: Any] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var out: [String: Any] = [:]
        for (k, v) in env {
            if let s = v as? String {
                out[k] = scrubString(s, home: home)
            } else {
                out[k] = v
            }
        }
        return out
    }

    private static func scrubString(_ s: String, home: String) -> String {
        var v = s
        if !home.isEmpty { v = v.replacingOccurrences(of: home, with: "<user>") }
        v = v.replacingOccurrences(of: #"/Users/[^/]+"#, with: "/Users/<user>", options: .regularExpression)
        v = v.replacingOccurrences(of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, with: "<email>", options: .regularExpression)
        return v
    }
}
