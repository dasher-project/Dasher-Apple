import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Parameter types

enum DasherParamType: Int {
    case bool = 0, long = 1, string = 2, invalid = -1
}

enum DasherUIControl: Int {
    case none = 0, `switch` = 1, slider = 2, step = 3, dropdown = 4, textField = 5
}

struct DasherParameterInfo {
    let key: Int
    let name: String
    let desc: String
    let group: String
    let type: DasherParamType
    let uiType: DasherUIControl
    let minVal: Int
    let maxVal: Int
    let step: Int
    let advanced: Bool

    init(from raw: dasher_parameter_info) {
        key = Int(raw.key)
        name = String(cString: raw.name)
        desc = String(cString: raw.desc)
        group = String(cString: raw.group)
        type = DasherParamType(rawValue: Int(raw.type)) ?? .invalid
        uiType = DasherUIControl(rawValue: Int(raw.ui_type)) ?? .none
        minVal = Int(raw.min_val)
        maxVal = Int(raw.max_val)
        step = Int(raw.step)
        advanced = raw.advanced != 0
    }
}

struct DasherPalette {
    let name: String
    let previewColors: [CGColor]
}

struct DasherAlphabet {
    let name: String
}

// MARK: - Settings section grouping

enum DasherSettingsSection: String, CaseIterable {
    case input = "Input"
    case language = "Language"
    case appearance = "Appearance"
    case speed = "Speed"
    case output = "Output"
    case advanced = "Advanced"
    case other = "Other"

    static func section(for param: DasherParameterInfo) -> DasherSettingsSection {
        if param.advanced { return .advanced }
        return DasherSettingsSection(rawValue: param.group) ?? .other
    }
}

// MARK: - Bridge

@MainActor
class DasherBridge: InputMethodBridge {
    private var ctx: OpaquePointer?
    private var lastOutputText: String = ""
    private var fontParamKey: Int = -1
    /// Current canvas font name (SP_DASHER_FONT). Shared by opcode-5 drawing
    /// and measureLabel so both always use the same face (issue #41).
    var fontName: String {
        fontParamKey >= 0 ? getStringParameter(key: fontParamKey) : ""
    }

    var onOutput: ((String) -> Void)?
    var onDelete: ((String) -> Void)?
    var onMessage: ((Bool, String) -> Void)?
    var onSpeak: ((String, Bool) -> Void)?
    var onClipboard: ((String) -> Void)?

    private(set) var lastError: String?
    private let userDir: String
    private let dataDir: String

    init(dataDir: String, userDir: String? = nil) {
        self.userDir = userDir ?? dataDir
        self.dataDir = dataDir
        // Two-phase start (RFC 0018 pattern, mirrors Dasher-Android): init is
        // deliberately cheap — no engine work — so the first UI frame never
        // blocks. bootstrap() creates the engine off the main thread.
            // Cross-component settings sync (issue #44, Dasher-Android #30
            // pattern): the keyboard extension shares this user dir and may
            // have written dasher_settings.xml while this app was inactive.
            // Reload on becoming active — cheap, no-op when nothing changed.
            #if canImport(UIKit)
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
                self?.reloadSettings()
            }
            #elseif canImport(AppKit)
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
                self?.reloadSettings()
            }
            #endif
        resolveFontParamKey()
    }

    /// Creates the engine, registers callbacks, applies the device locale and
    /// realizes the default alphabet (parse + training) on a background task,
    /// then marks the bridge ready on the main actor. Every engine method
    /// no-ops (ctx guard) until then, so views can be built immediately.
    /// Locale/screen-size helpers are ctx-free pre-computed on the main actor.
    /// - Parameter realizeDefaultScreen: realize immediately (alphabet parse +
    ///    training at 800×600). iOS/visionOS want this; macOS defers its first
    ///    realize to startEngine (after the v5-migration choice).
    func bootstrap(realizeDefaultScreen: Bool = true) async {
        guard ctx == nil else { return }
        let dataDir = self.dataDir
        let userDir = self.userDir
        let localeTag = Self.engineLocaleTag(dataDir: dataDir)
        let created: (OpaquePointer?, String?) = await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return (nil, nil) }
            var errorMsg: UnsafeMutablePointer<CChar>?
            let newCtx = dasher_create(dataDir, userDir, &errorMsg)
            let err = errorMsg.map { String(cString: $0) }
            guard let newCtx else { return (nil, err) }
                let retained = Unmanaged.passUnretained(self).toOpaque()
                dasher_set_output_callback(newCtx, { eventType, text, userData in
                    guard let text = text, let userData = userData else { return }
                    let instance = Unmanaged<DasherBridge>.fromOpaque(userData).takeUnretainedValue()
                    let str = String(cString: text)
                    if eventType == 0 {
                        instance.onOutput?(str)
                    } else if eventType == 1 {
                        instance.onDelete?(str)
                    }
                }, retained)
                // Real font metrics for node labels (issue #41): the engine's
                // code-point estimate under-measures wide glyphs and the error
                // compounds down the ancestor chain — squashed/jumbled labels at
                // depth. Contract (dasher.h): fill out_width/out_height in pixels
                // and return 0 on success; non-zero falls back to the estimate.
                dasher_set_text_size_callback(newCtx, { text, fontSize, outWidth, outHeight, userData in
                    guard let text = text, let outWidth = outWidth, let outHeight = outHeight, let userData = userData else { return 1 }
                    let instance = Unmanaged<DasherBridge>.fromOpaque(userData).takeUnretainedValue()
                    return instance.measureLabel(String(cString: text), fontSize: fontSize, outWidth: outWidth, outHeight: outHeight)
                }, retained)
                dasher_set_message_callback(newCtx, { messageType, text, userData in
                    guard let text = text, let userData = userData else { return }
                    let instance = Unmanaged<DasherBridge>.fromOpaque(userData).takeUnretainedValue()
                    let str = String(cString: text)
                    let isWarning = messageType == 1
                    // Engine work during bootstrap happens off the main actor;
                    // rare UI-facing callbacks hop to the main queue (output/
                    // delete stay synchronous — draw-loop ordering).
                    DispatchQueue.main.async { instance.onMessage?(isWarning, str) }
                }, retained)
                dasher_set_speak_callback(newCtx, { text, interrupt, userData in
                    guard let text = text, let userData = userData else { return }
                    let instance = Unmanaged<DasherBridge>.fromOpaque(userData).takeUnretainedValue()
                    let str = String(cString: text)
                    DispatchQueue.main.async { instance.onSpeak?(str, interrupt != 0) }
                }, retained)
                dasher_set_clipboard_callback(newCtx, { text, userData in
                    guard let text = text, let userData = userData else { return }
                    let instance = Unmanaged<DasherBridge>.fromOpaque(userData).takeUnretainedValue()
                    let str = String(cString: text)
                    DispatchQueue.main.async { instance.onClipboard?(str) }
                }, retained)

            // Device locale for engine strings (RFC 0003), then the initial
            // realize (alphabet parse + training) — off the main thread.
            if dasher_set_locale(newCtx, localeTag) != 0 {
                _ = dasher_set_locale(newCtx, "en")
            }
            if realizeDefaultScreen {
                dasher_set_screen_size(newCtx, 800, 600)
            }
            return (newCtx, err)
        }.value
        lastError = created.1
        ctx = created.0
        if ctx != nil, let dark = pendingAppearanceDark {
            pendingAppearanceDark = nil
            setSystemAppearance(dark: dark)
        }
    }

    /// Off-main realize (alphabet parse + training) at an explicit size — for
    /// targets that defer the first realize (macOS v5-migration flow) or need
    /// a large re-realize (e.g. alphabet switch on first canvas layout).
    func realize(screenWidth: Int, screenHeight: Int) async {
        guard let ctx = ctx else { return }
        let w = Int32(screenWidth), h = Int32(screenHeight)
        await Task.detached(priority: .userInitiated) {
            dasher_set_screen_size(ctx, w, h)
        }.value
    }

    /// Device locale mapped to an available engine locale code (RFC 0003).
    /// Static and ctx-free so bootstrap() can pre-compute it on the main actor.
    static func engineLocaleTag(dataDir: String) -> String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let url = URL(fileURLWithPath: dataDir)
            .appendingPathComponent("Strings", isDirectory: true)
            .appendingPathComponent("locales.json")
        struct LocalesFile: Decodable { let locales: [Entry] }
        struct Entry: Decodable { let code: String }
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(LocalesFile.self, from: data) else {
            return "en"
        }
        let codes = Set(file.locales.map { $0.code })
        if codes.contains(lang) { return lang }
        if lang == "zh" && codes.contains("zh-CN") { return "zh-CN" }
        return "en"
    }

    private func resolveFontParamKey() {
        let count = dasher_get_parameter_count()
        var info = dasher_parameter_info()
        for i in 0..<count {
            guard dasher_get_parameter_info(i, &info) == 0 else { continue }
            let name = String(cString: info.name)
            if name == "Dasher Font" {
                fontParamKey = Int(info.key)
                return
            }
        }
    }

    deinit {
        if let ctx = ctx {
            dasher_destroy(ctx)
        }
    }

    var isReady: Bool { ctx != nil }

    // MARK: - Core input/output

    func setScreenSize(width: Int, height: Int) {
        guard let ctx = ctx else { return }
        dasher_set_screen_size(ctx, Int32(width), Int32(height))
    }

    func mouseMove(x: Float, y: Float) {
        guard let ctx = ctx else { return }
        dasher_mouse_move(ctx, x, y)
    }

    func mouseDown() {
        guard let ctx = ctx else { return }
        dasher_mouse_down(ctx)
    }

    func mouseUp() {
        guard let ctx = ctx else { return }
        dasher_mouse_up(ctx)
    }

    func keyEvent(key: Int, pressed: Bool) {
        guard let ctx = ctx else { return }
        dasher_key_event(ctx, Int32(key), pressed ? 1 : 0)
    }

    /// Fires once when the engine enters the RFC 0009 A2 error state. The
    /// frontend should surface a "please restart" message; only engine
    /// recreation (dasher_destroy + dasher_create) clears the flag.
    var onEngineError: (() -> Void)?
    private var engineErrorReported = false

    private func notifyEngineErrorIfNeeded() {
        guard !engineErrorReported else { return }
        engineErrorReported = true
        onEngineError?()
    }

    // Clamped engine timeline (issue #41): the engine consumes raw deltas as
    // zoom amount, so pause gaps must never arrive as multi-second jumps.
    // Wall-clock timestamps from the caller are converted to deltas capped at
    // 50 ms, accumulated on our own monotonic timeline. Mirrors the fix in
    // Dasher-Windows #36 (their EngineTimelineTests pin the same contract).
    private var lastWallMs: Int64?
    private var engineTimeMs: Int64 = 0
    private static let maxFrameDeltaMs: Int64 = 50

    /// Convert a wall-clock millisecond timestamp into the engine timeline.
    /// Pure function of stored state — internal for testability.
    func timelineMs(forWallMs wallMs: Int64) -> Int64 {
        if let last = lastWallMs {
            var delta = wallMs - last
            if delta < 0 { delta = 0 } // clock went backwards: hold position
            if delta > Self.maxFrameDeltaMs { delta = Self.maxFrameDeltaMs }
            engineTimeMs += delta
        }
        lastWallMs = wallMs
        return engineTimeMs
    }

    /// Reset the timeline baseline (e.g. after engine reset/recreate).
    func resetTimeline() {
        lastWallMs = nil
        engineTimeMs = 0
    }

    func frame(timeMs: Int64) -> DrawCommands? {
        guard let ctx = ctx else { return nil }
        if dasher_has_engine_error(ctx) != 0 {
            notifyEngineErrorIfNeeded()
            return nil
        }
        let engineMs = timelineMs(forWallMs: timeMs)
        var cmds: UnsafeMutablePointer<Int32>?
        var cmdCount: Int32 = 0
        var strs: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        var strCount: Int32 = 0

        dasher_frame(ctx, engineMs, &cmds, &cmdCount, &strs, &strCount)

        if dasher_has_engine_error(ctx) != 0 {
            notifyEngineErrorIfNeeded()
            return nil
        }

        guard let cmds = cmds, cmdCount > 0 else { return nil }
        return DrawCommands(
            commands: cmds,
            commandCount: Int(cmdCount),
            strings: strs,
            stringCount: Int(strCount),
            fontName: fontName
        )
    }

    func getOutputText() -> String {
        guard let ctx = ctx, let cStr = dasher_get_output_text(ctx) else { return "" }
        return String(cString: cStr)
    }

    func getNewOutput() -> String? {
        let current = getOutputText()
        guard current != lastOutputText else { return nil }
        let new = String(current.dropFirst(lastOutputText.count))
        lastOutputText = current
        return new
    }

    func resetOutputText() {
        guard let ctx = ctx else { return }
        dasher_reset_output_text(ctx)
        lastOutputText = ""
    }

    func reset() {
        guard let ctx = ctx else { return }
        dasher_reset(ctx)
        lastOutputText = ""
    }

    // MARK: - Convenience getters/setters

    var alphabetId: String {
        guard let ctx = ctx, let cStr = dasher_get_alphabet_id(ctx) else { return "" }
        return String(cString: cStr)
    }

    func setAlphabetId(_ id: String) {
        guard let ctx = ctx else { return }
        dasher_set_alphabet_id(ctx, id)
    }

    var speedPercent: Int {
        guard let ctx = ctx else { return 100 }
        return Int(dasher_get_speed_percent(ctx))
    }

    func setSpeedPercent(_ percent: Int) {
        guard let ctx = ctx else { return }
        dasher_set_speed_percent(ctx, Int32(percent))
    }

    // MARK: - Parameter schema

    static var parameterCount: Int {
        Int(dasher_get_parameter_count())
    }

    static func getParameterInfo(index: Int) -> DasherParameterInfo? {
        var raw = dasher_parameter_info()
        guard dasher_get_parameter_info(Int32(index), &raw) == 0 else { return nil }
        return DasherParameterInfo(from: raw)
    }

    static var allParameters: [DasherParameterInfo] {
        let count = parameterCount
        return (0..<count).compactMap { getParameterInfo(index: $0) }
    }

    /// Speed-control bounds from the engine parameter manifest (issue #34):
    /// LP_MAX_BITRATE is in raw units where 160 = 100 %, so the engine range
    /// raw 1–1000 maps to ~1–625 %. Falls back to the historic 20–400 if the
    /// manifest is unavailable.
    static var speedRangePercent: ClosedRange<Int> {
        let key = Int(dasher_find_parameter_key("LP_MAX_BITRATE"))
        if key >= 0, let info = allParameters.first(where: { $0.key == key }), info.maxVal > 0 {
            let minPct = Int((Double(info.minVal) * 100.0 / 160.0).rounded())
            let maxPct = Int((Double(info.maxVal) * 100.0 / 160.0).rounded())
            if maxPct > minPct { return minPct...maxPct }
        }
        return 20...400
    }

    // MARK: - Enum values

    static func getEnumValues(key: Int) -> [(name: String, value: Int)] {
        let count = Int(dasher_get_parameter_enum_count(Int32(key)))
        return (0..<count).compactMap { i -> (String, Int)? in
            guard let namePtr = dasher_get_parameter_enum_name(Int32(key), Int32(i)) else { return nil }
            let val = Int(dasher_get_parameter_enum_value(Int32(key), Int32(i)))
            return (String(cString: namePtr), val)
        }
    }

    func getStringValues(key: Int) -> [String] {
        guard let ctx = ctx else { return [] }
        // Probe-then-fetch (issue #41, needs DasherCore >= v0.2.5 for the
        // probe to report the count): the old fixed 64-slot buffer silently
        // truncated longer lists — SP_DASHER_FONT runs to hundreds of entries.
        let count = Int(dasher_get_parameter_string_values(ctx, Int32(key), nil, 0))
        guard count > 0 else { return [] }
        var buffer: [UnsafePointer<CChar>?] = Array(repeating: nil, count: count)
        let actual = Int(dasher_get_parameter_string_values(ctx, Int32(key), &buffer, Int32(count)))
        return (0..<min(actual, count)).compactMap { ptr in
            guard let p = buffer[ptr] else { return nil }
            return String(cString: p)
        }
    }

    // MARK: - Palettes

    var paletteCount: Int {
        guard let ctx = ctx else { return 0 }
        return Int(dasher_get_palette_count(ctx))
    }

    func getPalette(index: Int) -> DasherPalette? {
        guard let ctx = ctx,
              let namePtr = dasher_get_palette_name(ctx, Int32(index)) else { return nil }
        let name = String(cString: namePtr)
        var colors: [Int32] = [0, 0, 0, 0]
        guard dasher_get_palette_preview_colors(ctx, Int32(index), &colors) == 0 else { return nil }
        let cgColors = colors.map { argbToCGColor($0) }
        return DasherPalette(name: name, previewColors: cgColors)
    }

    var allPalettes: [DasherPalette] {
        guard let ctx = ctx else { return [] }
        let count = Int(dasher_get_palette_count(ctx))
        if count == 0 { return [] }
        return (0..<count).compactMap { getPalette(index: $0) }
    }

    func setPalette(_ name: String) {
        guard let ctx = ctx else { return }
        dasher_set_palette(ctx, name)
    }

    var currentPalette: String {
        guard let ctx = ctx, let cStr = dasher_get_current_palette(ctx) else { return "" }
        return String(cString: cStr)
    }


    // MARK: - Appearance / dark mode (RFC 0007)

    /// Appearance requested before the engine exists is buffered and replayed
    /// at bootstrap completion — the onAppear call lands pre-boot, and a lost
    /// dark-mode request meant a light palette on first run (audit #6).
    private var pendingAppearanceDark: Bool?

    func setSystemAppearance(dark: Bool) {
        guard let ctx = ctx else {
            pendingAppearanceDark = dark
            return
        }
        dasher_set_system_appearance(ctx, dark ? 2 : 1)
    }
    func setAppearanceMode(_ mode: Int) {
        guard let ctx = ctx else { return }
        dasher_set_appearance_mode(ctx, Int32(mode))
    }
    func getAppearanceMode() -> Int {
        guard let ctx = ctx else { return 0 }
        return Int(dasher_get_appearance_mode(ctx))
    }
    func setUserPalette(_ name: String) {
        guard let ctx = ctx else { return }
        dasher_set_user_palette(ctx, name)
    }
    func setLightPalette(_ name: String) {
        guard let ctx = ctx else { return }
        dasher_set_light_palette(ctx, name)
    }
    func setDarkPalette(_ name: String) {
        guard let ctx = ctx else { return }
        dasher_set_dark_palette(ctx, name)
    }
    func getLightPalette() -> String {
        guard let ctx = ctx, let cStr = dasher_get_light_palette(ctx) else { return "" }
        return String(cString: cStr)
    }
    func getDarkPalette() -> String {
        guard let ctx = ctx, let cStr = dasher_get_dark_palette(ctx) else { return "" }
        return String(cString: cStr)
    }

    // MARK: - Alphabets

    var alphabetCount: Int {
        guard let ctx = ctx else { return 0 }
        return Int(dasher_get_alphabet_count(ctx))
    }

    func getAlphabet(index: Int) -> DasherAlphabet? {
        guard let ctx = ctx,
              let namePtr = dasher_get_alphabet_name(ctx, Int32(index)) else { return nil }
        return DasherAlphabet(name: String(cString: namePtr))
    }

    var allAlphabets: [DasherAlphabet] {
        guard let ctx = ctx else { return [] }
        let count = Int(dasher_get_alphabet_count(ctx))
        if count == 0 { return [] }
        return (0..<count).compactMap { getAlphabet(index: $0) }
    }

    // MARK: - Generic parameter get/set

    func getBoolParameter(key: Int) -> Bool {
        guard let ctx = ctx else { return false }
        return dasher_get_bool_parameter(ctx, Int32(key)) != 0
    }

    func setBoolParameter(key: Int, value: Bool) {
        guard let ctx = ctx else { return }
        dasher_set_bool_parameter(ctx, Int32(key), value ? 1 : 0)
    }

    func getLongParameter(key: Int) -> Int {
        guard let ctx = ctx else { return 0 }
        return Int(dasher_get_long_parameter(ctx, Int32(key)))
    }

    func setLongParameter(key: Int, value: Int) {
        guard let ctx = ctx else { return }
        dasher_set_long_parameter(ctx, Int32(key), Int(value))
    }

    func getStringParameter(key: Int) -> String {
        guard let ctx = ctx,
              let cStr = dasher_get_string_parameter(ctx, Int32(key)) else { return "" }
        return String(cString: cStr)
    }

    func setStringParameter(key: Int, value: String) {
        guard let ctx = ctx else { return }
        dasher_set_string_parameter(ctx, Int32(key), value)
        // The canvas font changed: cached label measurements are stale.
        if key == fontParamKey {
            textMeasureCache.removeAll()
            dasher_text_metrics_changed(ctx)
        }
    }

    // MARK: - Label measurement (issue #41)

    // Cache keyed on text+font+size; the engine also caches engine-side, this
    // keeps repeated cold misses cheap (mirrors Dasher-Windows #36).
    private var textMeasureCache: [String: (w: Int32, h: Int32)] = [:]
    /// measureLabel runs on the main draw loop AND the detached realize thread
    /// (audit #4); the engine-side cache keeps contention rare, this lock keeps
    /// the Dictionary access defined.
    private let textMeasureLock = NSLock()

    /// Measure a single-line label with the same font the canvas draws opcode-5
    /// text with. Returns 0 on success (dasher.h contract); 1 = fall back to
    /// the engine's estimate.
    func measureLabel(_ text: String, fontSize: Int32, outWidth: UnsafeMutablePointer<Int32>, outHeight: UnsafeMutablePointer<Int32>) -> Int32 {
        let cacheKey = "\(fontName)|\(fontSize)|\(text)"
        let cached: (w: Int32, h: Int32)? = textMeasureLock.withLock {
            textMeasureCache[cacheKey]
        }
        if let hit = cached {
            outWidth.pointee = hit.w
            outHeight.pointee = hit.h
            return 0
        }
        let size = CGFloat(fontSize)
        #if canImport(UIKit)
        let font = fontName.isEmpty ? UIFont.systemFont(ofSize: size) : (UIFont(name: fontName, size: size) ?? UIFont.systemFont(ofSize: size))
        #elseif canImport(AppKit)
        let font = fontName.isEmpty ? NSFont.systemFont(ofSize: size) : (NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size))
        #endif
        let bounds = (text as NSString).size(withAttributes: [.font: font])
        guard bounds.width > 0 || bounds.height > 0 else { return 1 }
        let w = Int32(bounds.width.rounded(.up))
        let h = Int32(bounds.height.rounded(.up))
        textMeasureLock.withLock {
            if textMeasureCache.count > 4096 { textMeasureCache.removeAll() } // bounded
            textMeasureCache[cacheKey] = (w, h)
        }
        outWidth.pointee = w
        outHeight.pointee = h
        return 0
    }


    // MARK: - Persistence

    func saveSettings() {
        guard let ctx = ctx else { return }
        dasher_save_settings(ctx)
    }

    /// Re-read dasher_settings.xml and apply differing values to the live
    /// engine (parameter-change notifications fire; the edit buffer is
    /// preserved). Closes the stale-engine window where two components share
    /// the user dir — the keyboard extension and this app (issue #44, the
    /// Dasher-Android #30 pattern). Needs DasherCore >= v0.2.11.
    func reloadSettings() {
        guard let ctx = ctx else { return }
        dasher_reload_settings(ctx)
    }

    // MARK: - Locale

    var locale: String {
        guard let ctx = ctx, let cStr = dasher_get_locale(ctx) else { return "en" }
        return String(cString: cStr)
    }

    func setLocale(_ code: String) -> Bool {
        guard let ctx = ctx else { return false }
        return dasher_set_locale(ctx, code) == 0
    }

    func getLocalizedString(_ key: String) -> String? {
        guard let ctx = ctx, let cStr = dasher_get_localized_string(ctx, key) else { return nil }
        return String(cString: cStr)
    }

    func setStringOverride(key: String, value: String?) {
        guard let ctx = ctx else { return }
        dasher_set_string_override(ctx, key, value)
    }

    // MARK: - Game Mode

    func enterGameMode() -> Bool {
        guard let ctx = ctx else { return false }
        let result = dasher_enter_game_mode(ctx) == 0
        if result {
            dasher_game_set_canvas_text(ctx, 0)
        }
        return result
    }

    func leaveGameMode() {
        guard let ctx = ctx else { return }
        dasher_leave_game_mode(ctx)
    }

    var isGameModeActive: Bool {
        guard let ctx = ctx else { return false }
        return dasher_game_mode_active(ctx) != 0
    }

    func getGameTargetText() -> String {
        guard let ctx = ctx, let cStr = dasher_game_get_target_text(ctx) else { return "" }
        return String(cString: cStr)
    }

    func getGameCorrectCount() -> Int {
        guard let ctx = ctx else { return -1 }
        return Int(dasher_game_get_correct_count(ctx))
    }

    func getGameTargetLength() -> Int {
        guard let ctx = ctx else { return -1 }
        return Int(dasher_game_get_target_length(ctx))
    }

    func getGameWrongText() -> String {
        guard let ctx = ctx, let cStr = dasher_game_get_wrong_text(ctx) else { return "" }
        return String(cString: cStr)
    }

    // MARK: - Language Model Registry

    struct LanguageModelInfo {
        let id: Int
        let name: String
        let description: String
    }

    func getAvailableLanguageModels() -> [LanguageModelInfo] {
        let count = Int(dasher_get_language_model_count())
        var models: [LanguageModelInfo] = []
        models.reserveCapacity(count)
        for i in 0..<count {
            let id = Int(dasher_get_language_model_id_at(Int32(i)))
            let namePtr = dasher_get_language_model_name(Int32(id))
            let descPtr = dasher_get_language_model_description(Int32(id))
            models.append(LanguageModelInfo(
                id: id,
                name: namePtr != nil ? String(cString: namePtr!) : "Unknown",
                description: descPtr != nil ? String(cString: descPtr!) : ""
            ))
        }
        return models
    }

    var currentLanguageModelId: Int {
        guard let ctx = ctx else { return 0 }
        return Int(dasher_get_language_model_id(ctx))
    }

    func setLanguageModelId(_ id: Int) {
        guard let ctx = ctx else { return }
        dasher_set_language_model_id(ctx, Int32(id))
    }

    func getLanguageModelParamKeys(_ id: Int) -> [Int] {
        let count = Int(dasher_get_language_model_param_count(Int32(id)))
        return (0..<count).map { Int(dasher_get_language_model_param_key(Int32(id), Int32($0))) }
    }

    lazy var languageModelIdParamKey: Int = {
        Int(dasher_find_parameter_key("LP_LANGUAGE_MODEL_ID"))
    }()

    func findParameterKey(_ name: String) -> Int {
        Int(dasher_find_parameter_key(name))
    }
}

// MARK: - Draw commands

struct DrawCommands {
    let commands: UnsafeMutablePointer<Int32>
    let commandCount: Int
    let strings: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    let stringCount: Int
    var fontName: String = ""
}

private func argbToCGColor(_ argb: Int32) -> CGColor {
    CGColor(red: CGFloat((argb >> 16) & 0xFF) / 255.0,
            green: CGFloat((argb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(argb & 0xFF) / 255.0,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255.0)
}

// MARK: - UIKit rendering

#if canImport(UIKit)
extension DrawCommands {
    func render(in context: CGContext, bounds: CGRect) {
        let count = commandCount / 6
        for i in 0..<count {
            let base = i * 6
            let op = Int(commands[base + 0])
            let a = CGFloat(commands[base + 1])
            let b = CGFloat(commands[base + 2])
            let c = Int(commands[base + 3])
            let d = Int(commands[base + 4])
            let argb = Int32(commands[base + 5])
            let cgColor = argbToCGColor(argb)
            let color = UIColor(cgColor: cgColor)

            switch op {
            case 0:
                context.setFillColor(cgColor)
                context.fill(bounds)
            case 1:
                let radius = CGFloat(c)
                context.setFillColor(cgColor)
                context.fillEllipse(in: CGRect(x: a - radius, y: b - radius,
                                                width: radius * 2, height: radius * 2))
            case 2:
                context.setStrokeColor(cgColor)
                context.setLineWidth(2)
                context.move(to: CGPoint(x: a, y: b))
                context.addLine(to: CGPoint(x: CGFloat(c), y: CGFloat(d)))
                context.strokePath()
            case 3:
                context.setStrokeColor(cgColor)
                context.setLineWidth(1)
                context.stroke(CGRect(x: a, y: b, width: CGFloat(c) - a, height: CGFloat(d) - b))
            case 4:
                context.setFillColor(cgColor)
                context.fill(CGRect(x: a, y: b, width: CGFloat(c) - a, height: CGFloat(d) - b))
            case 5:
                let fontSize = CGFloat(c > 0 ? c : 14)
                let stringIndex = d
                if let strings = strings, stringIndex >= 0, stringIndex < stringCount, let strPtr = strings[stringIndex] {
                    let text = String(cString: strPtr)
                    let font: UIFont
                    if self.fontName.isEmpty {
                        font = UIFont.systemFont(ofSize: fontSize)
                    } else {
                        font = UIFont(name: self.fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
                    }
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: color
                    ]
                    NSAttributedString(string: text, attributes: attrs).draw(at: CGPoint(x: a, y: b))
                }
            default:
                break
            }
        }
    }
}
#elseif canImport(AppKit)
extension DrawCommands {
    func render(in context: CGContext, bounds: CGRect, viewHeight: CGFloat) {
        let count = commandCount / 6
        for i in 0..<count {
            let base = i * 6
            let op = Int(commands[base + 0])
            let a = CGFloat(commands[base + 1])
            let b = CGFloat(commands[base + 2])
            let c = Int(commands[base + 3])
            let d = Int(commands[base + 4])
            let argb = Int32(commands[base + 5])
            let cgColor = argbToCGColor(argb)
            let color = NSColor(cgColor: cgColor)

            switch op {
            case 0:
                context.setFillColor(cgColor)
                context.fill(bounds)
            case 1:
                let radius = CGFloat(c)
                context.setFillColor(cgColor)
                context.fillEllipse(in: CGRect(x: a - radius, y: viewHeight - b - radius,
                                                width: radius * 2, height: radius * 2))
            case 2:
                context.setStrokeColor(cgColor)
                context.setLineWidth(2)
                context.move(to: CGPoint(x: a, y: viewHeight - b))
                context.addLine(to: CGPoint(x: CGFloat(c), y: viewHeight - CGFloat(d)))
                context.strokePath()
            case 3:
                context.setStrokeColor(cgColor)
                context.setLineWidth(1)
                let y1 = viewHeight - b
                let y2 = viewHeight - CGFloat(d)
                context.stroke(CGRect(x: a, y: min(y1, y2), width: CGFloat(c) - a, height: abs(y2 - y1)))
            case 4:
                context.setFillColor(cgColor)
                let y1 = viewHeight - b
                let y2 = viewHeight - CGFloat(d)
                context.fill(CGRect(x: a, y: min(y1, y2), width: CGFloat(c) - a, height: abs(y2 - y1)))
            case 5:
                let fontSize = CGFloat(c > 0 ? c : 14)
                let stringIndex = d
                if let strings = strings, stringIndex >= 0, stringIndex < stringCount, let strPtr = strings[stringIndex] {
                    let text = String(cString: strPtr)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: fontSize),
                        .foregroundColor: color
                    ]
                    let flippedY = viewHeight - b - fontSize
                    NSAttributedString(string: text, attributes: attrs).draw(at: CGPoint(x: a, y: flippedY))
                }
            default:
                break
            }
        }
    }
}
#endif
