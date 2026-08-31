import Foundation
import UIKit

// MARK: - Draw command buffer (engine-owned: valid until the next frame() call)

struct WatchDrawCommands {
    let commands: UnsafeMutablePointer<Int32>
    let commandCount: Int
    let strings: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    let stringCount: Int

    static let empty = WatchDrawCommands(commands: UnsafeMutablePointer<Int32>(bitPattern: 1)!,
                                         commandCount: 0, strings: nil, stringCount: 0)
}

// MARK: - Bridge

/// Lean DasherCore bridge for the watch spike. Standalone app, no DasherShared
/// (that would pull PostHog/LucideIcons into a memory-tight target) — the
/// pieces worth keeping from the app targets are built in: RFC 0018 two-phase
/// bootstrap with pendingCanvasSize replay, clamped engine timeline, label
/// measurement callback with a locked cache, and vertical (TopToBottom)
/// orientation set before the first realize.
@MainActor
final class WatchBridge {
    private var ctx: OpaquePointer?
    private let dataDir: String
    private let userDir: String

    private(set) var lastError: String?
    private var pendingCanvasSize: CGSize?

    /// Serializes ALL engine calls (audit #4, the deferred half — it bit the
    /// watch first): the detached realize() flips `realized` mid-flight and
    /// then rebuilds m_Root (pending-alphabet ChangeAlphabet), while the
    /// TimelineView drives dasher_frame at 60fps from view-appear — RenderToView
    /// caught m_Root null mid-rebuild and asserted. Every ctx-touching call
    /// holds this lock; frame() waits instead of racing.
    private let engineLock = NSLock()

    var onOutput: ((String) -> Void)?
    var onMessage: ((Bool, String) -> Void)?

    // Clamped engine timeline (mirrors the app bridges).
    private var lastWallMs: Int64?
    private var engineTimeMs: Int64 = 0
    private static let maxFrameDeltaMs: Int64 = 50

    // Label measurement cache (locked: main draw loop + bootstrap thread).
    private var textMeasureCache: [String: (w: Int32, h: Int32)] = [:]
    private let textMeasureLock = NSLock()

    init(dataDir: String, userDir: String) {
        self.dataDir = dataDir
        self.userDir = userDir
    }

    deinit {
        if let ctx = ctx {
            dasher_destroy(ctx)
        }
    }

    var isReady: Bool { ctx != nil }

    /// RFC 0009 error state (e.g. a failed Realize): frame/input no-op; the
    /// VM surfaces it instead of showing a dead canvas.
    var hasEngineError: Bool {
        guard let ctx = ctx else { return false }
        return engineLock.withLock { dasher_has_engine_error(ctx) != 0 }
    }

    // MARK: - Bootstrap (RFC 0018)

    func bootstrap() async {
        guard ctx == nil else { return }
        let dataDir = self.dataDir
        let userDir = self.userDir
        let created: (OpaquePointer?, String?) = await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return (nil, nil) }
            var errorMsg: UnsafeMutablePointer<CChar>?
            let newCtx = dasher_create(dataDir, userDir, &errorMsg)
            let err = errorMsg.map { String(cString: $0) }
            guard let newCtx else { return (nil, err) }
            let retained = Unmanaged.passUnretained(self).toOpaque()
            dasher_set_output_callback(newCtx, { eventType, text, userData in
                guard let text = text, let userData = userData else { return }
                let instance = Unmanaged<WatchBridge>.fromOpaque(userData).takeUnretainedValue()
                let str = String(cString: text)
                if eventType == 0 {
                    DispatchQueue.main.async { instance.onOutput?(str) }
                }
            }, retained)
            dasher_set_message_callback(newCtx, { messageType, text, userData in
                guard let text = text, let userData = userData else { return }
                let instance = Unmanaged<WatchBridge>.fromOpaque(userData).takeUnretainedValue()
                let str = String(cString: text)
                let isWarning = messageType == 1
                DispatchQueue.main.async { instance.onMessage?(isWarning, str) }
            }, retained)
            dasher_set_text_size_callback(newCtx, { text, fontSize, outWidth, outHeight, userData in
                guard let text = text, let outWidth = outWidth, let outHeight = outHeight, let userData = userData else { return 1 }
                let instance = Unmanaged<WatchBridge>.fromOpaque(userData).takeUnretainedValue()
                return instance.measureLabel(String(cString: text), fontSize: fontSize, outWidth: outWidth, outHeight: outHeight)
            }, retained)
            // Device locale for engine strings (RFC 0003), best-effort.
            let lang = Locale.current.language.languageCode?.identifier ?? "en"
            if dasher_set_locale(newCtx, lang) != 0 {
                _ = dasher_set_locale(newCtx, "en")
            }
            // NOTE: LP_ORIENTATION must be set AFTER the first realize —
            // HandleParameterChange for it dereferences the node-creation
            // manager / view, which are null pre-realize (SIGSEGV, verified
            // the hard way on the simulator).
            return (newCtx, err)
        }.value
        lastError = created.1
        ctx = created.0
    }

    /// Canvas orientation. MUST be applied after the first realize — see the
    /// note in bootstrap() (pre-realize parameter changes segfault ChangeView).
    /// ScreenOrientations: LeftToRight=0, RightToLeft=1, TopToBottom=2.
    func applyOrientation(_ orientation: WatchOrientation) {
        guard let ctx = ctx else { return }
        let value: Int
        switch orientation {
        case .vertical: value = 2
        case .leftToRight: value = 0
        case .rightToLeft: value = 1
        }
        engineLock.withLock {
            dasher_set_long_parameter(ctx, dasher_find_parameter_key("LP_ORIENTATION"), value)
        }
    }

    /// Off-main realize at an explicit size.
    func realize(screenWidth: Int, screenHeight: Int) async {
        guard let ctx = ctx else { return }
        let w = Int32(screenWidth), h = Int32(screenHeight)
        let lock = engineLock
        await Task.detached(priority: .userInitiated) {
            lock.withLock {
                dasher_set_screen_size(ctx, w, h)
            }
        }.value
    }

    // MARK: - Canvas

    func setCanvasSize(_ size: CGSize) {
        pendingCanvasSize = size
        guard let ctx = ctx else { return }
        engineLock.withLock {
            dasher_set_screen_size(ctx, Int32(size.width), Int32(size.height))
        }
    }

    func frame(timeMs: Int64) -> WatchDrawCommands? {
        guard let ctx = ctx else { return nil }
        if dasher_has_engine_error(ctx) != 0 { return nil }
        let engineMs = timelineMs(forWallMs: timeMs)
        var cmds: UnsafeMutablePointer<Int32>?
        var cmdCount: Int32 = 0
        var strs: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        var strCount: Int32 = 0
        engineLock.withLock {
            dasher_frame(ctx, engineMs, &cmds, &cmdCount, &strs, &strCount)
        }
        guard let cmds = cmds, cmdCount > 0 else { return nil }
        return WatchDrawCommands(commands: cmds, commandCount: Int(cmdCount),
                                 strings: strs, stringCount: Int(strCount))
    }

    private func timelineMs(forWallMs wallMs: Int64) -> Int64 {
        if let last = lastWallMs {
            var delta = wallMs - last
            if delta < 0 { delta = 0 }
            if delta > Self.maxFrameDeltaMs { delta = Self.maxFrameDeltaMs }
            engineTimeMs += delta
        }
        lastWallMs = wallMs
        return engineTimeMs
    }

    // MARK: - Input

    func mouseMove(x: Float, y: Float) {
        guard let ctx = ctx else { return }
        engineLock.withLock { dasher_mouse_move(ctx, x, y) }
    }

    func mouseDown() {
        guard let ctx = ctx else { return }
        engineLock.withLock { dasher_mouse_down(ctx) }
    }

    func mouseUp() {
        guard let ctx = ctx else { return }
        engineLock.withLock { dasher_mouse_up(ctx) }
    }

    /// One Dimensional Mode filter for crown steering: Y-only, engine
    /// synthesizes X (speed) from deflection.
    func setOneDimensionalMode(_ on: Bool) {
        guard let ctx = ctx else { return }
        let target = on ? "One Dimensional Mode" : "Normal Control"
        // Runs on the main actor; getStringValues/setStringParameter take the
        // lock individually, so hold it across the pair for consistency.
        engineLock.lock()
        defer { engineLock.unlock() }
        let values = getStringValuesLocked(ctx: ctx, key: Int(dasher_find_parameter_key("SP_INPUT_FILTER")))
        guard values.contains(target) else { return }
        dasher_set_string_parameter(ctx, Int32(dasher_find_parameter_key("SP_INPUT_FILTER")), target)
    }

    // MARK: - Text & state

    var outputText: String {
        guard let ctx = ctx else { return "" }
        return engineLock.withLock {
            guard let cStr = dasher_get_output_text(ctx) else { return "" }
            return String(cString: cStr)
        }
    }

    func resetOutput() {
        guard let ctx = ctx else { return }
        engineLock.withLock { dasher_reset_output_text(ctx) }
    }

    var speedPercent: Int {
        guard let ctx = ctx else { return 100 }
        return engineLock.withLock { Int(dasher_get_speed_percent(ctx)) }
    }

    func setSpeedPercent(_ percent: Int) {
        guard let ctx = ctx else { return }
        engineLock.withLock { dasher_set_speed_percent(ctx, Int32(percent)) }
    }

    var alphabetId: String {
        guard let ctx = ctx else { return "" }
        return engineLock.withLock {
            guard let cStr = dasher_get_alphabet_id(ctx) else { return "" }
            return String(cString: cStr)
        }
    }

    func setAlphabetId(_ id: String) {
        guard let ctx = ctx else { return }
        engineLock.withLock { dasher_set_alphabet_id(ctx, id) }
    }

    var allAlphabetNames: [String] {
        guard let ctx = ctx else { return [] }
        return engineLock.withLock {
            let count = Int(dasher_get_alphabet_count(ctx))
            return (0..<count).compactMap { i in
                guard let p = dasher_get_alphabet_name(ctx, Int32(i)) else { return nil }
                return String(cString: p)
            }
        }
    }

    func saveSettings() {
        guard let ctx = ctx else { return }
        engineLock.withLock { dasher_save_settings(ctx) }
    }

    // MARK: - Parameter helpers

    /// Caller must hold engineLock (see setOneDimensionalMode).
    private func getStringValuesLocked(ctx: OpaquePointer, key: Int) -> [String] {
        let count = Int(dasher_get_parameter_string_values(ctx, Int32(key), nil, 0))
        guard count > 0 else { return [] }
        var buffer: [UnsafePointer<CChar>?] = Array(repeating: nil, count: count)
        let actual = Int(dasher_get_parameter_string_values(ctx, Int32(key), &buffer, Int32(count)))
        return (0..<min(actual, count)).compactMap { ptr in
            guard let p = buffer[ptr] else { return nil }
            return String(cString: p)
        }
    }

    private func setStringParameter(key: Int, value: String) {
        guard let ctx = ctx else { return }
        dasher_set_string_parameter(ctx, Int32(key), value)
    }

    // MARK: - Generic engine parameters (Mac/iOS-parity settings)

    func boolParam(_ name: String) -> Bool {
        guard let ctx = ctx else { return false }
        return engineLock.withLock { dasher_get_bool_parameter(ctx, Int32(dasher_find_parameter_key(name))) != 0 }
    }

    func setBoolParam(_ name: String, _ value: Bool) {
        guard let ctx = ctx else { return }
        engineLock.withLock {
            dasher_set_bool_parameter(ctx, Int32(dasher_find_parameter_key(name)), value ? 1 : 0)
        }
    }

    func stringParam(_ name: String) -> String {
        guard let ctx = ctx else { return "" }
        return engineLock.withLock {
            guard let cStr = dasher_get_string_parameter(ctx, Int32(dasher_find_parameter_key(name))) else { return "" }
            return String(cString: cStr)
        }
    }

    func setStringParam(_ name: String, _ value: String) {
        guard let ctx = ctx else { return }
        engineLock.withLock {
            dasher_set_string_parameter(ctx, Int32(dasher_find_parameter_key(name)), value)
        }
    }

    /// Permitted string values for a parameter (e.g. SP_INPUT_FILTER) —
    /// probe-then-fetch, engine-locked.
    func permittedValues(forParam name: String) -> [String] {
        guard let ctx = ctx else { return [] }
        return engineLock.withLock {
            let key = Int32(dasher_find_parameter_key(name))
            let count = Int(dasher_get_parameter_string_values(ctx, key, nil, 0))
            guard count > 0 else { return [] }
            var buffer: [UnsafePointer<CChar>?] = Array(repeating: nil, count: count)
            let actual = Int(dasher_get_parameter_string_values(ctx, key, &buffer, Int32(count)))
            return (0..<min(actual, count)).compactMap { ptr in
                guard let p = buffer[ptr] else { return nil }
                return String(cString: p)
            }
        }
    }

    /// Factory-reset the engine: delete the persisted settings files, then
    /// reset every parameter to its built-in default (notifications fire, so a
    /// live engine reconfigures itself). Mirrors the app targets'
    /// ResetSettingsSection contract.
    func resetAllSettings() {
        guard let ctx = ctx else { return }
        for file in ["dasher_settings.xml", "appearance_settings.xml"] {
            try? FileManager.default.removeItem(atPath: URL(fileURLWithPath: userDir).appendingPathComponent(file).path)
        }
        engineLock.withLock { dasher_reset_settings(ctx) }
    }

    // MARK: - Label measurement (dasher.h contract: 0 on success)

    func measureLabel(_ text: String, fontSize: Int32,
                      outWidth: UnsafeMutablePointer<Int32>, outHeight: UnsafeMutablePointer<Int32>) -> Int32 {
        let cacheKey = "|\(fontSize)|\(text)"
        let cached: (w: Int32, h: Int32)? = textMeasureLock.withLock {
            textMeasureCache[cacheKey]
        }
        if let hit = cached {
            outWidth.pointee = hit.w
            outHeight.pointee = hit.h
            return 0
        }
        let font = UIFont.systemFont(ofSize: CGFloat(fontSize))
        let bounds = (text as NSString).size(withAttributes: [.font: font])
        guard bounds.width > 0 || bounds.height > 0 else { return 1 }
        let w = Int32(bounds.width.rounded(.up))
        let h = Int32(bounds.height.rounded(.up))
        textMeasureLock.withLock {
            if textMeasureCache.count > 4096 { textMeasureCache.removeAll() }
            textMeasureCache[cacheKey] = (w, h)
        }
        outWidth.pointee = w
        outHeight.pointee = h
        return 0
    }
}
