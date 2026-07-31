import Foundation
import DasherShared
import os
import Darwin

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let macEngineLog = OSLog(subsystem: "at.dasher.Dasher.mac", category: "engine")

// MARK: - Parameter types

enum DasherParamType: Int {
    case bool = 0, long = 1, string = 2, invalid = -1
}

enum DasherUIControl: Int {
    case `switch` = 0
    case textField = 1
    case slider = 2
    case dropdown = 3
    case step = 4
    case none = 5
}

struct DasherParameterInfo {
    let key: Int
    let name: String
    let desc: String
    let group: String
    let subgroup: String
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
        subgroup = String(cString: raw.subgroup)
        type = DasherParamType(rawValue: Int(raw.type)) ?? .invalid
        uiType = DasherUIControl(rawValue: Int(raw.ui_type)) ?? .none
        minVal = Int(raw.min_val)
        maxVal = Int(raw.max_val)
        step = Int(raw.step)
        advanced = raw.advanced != 0
    }
}

extension DasherParameterInfo: Identifiable {
    var id: Int { key }
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
    case customization = "Customization"
    case input = "Input"
    case language = "Language"
    case output = "Output"
    case speech = "Speech"
    case gameMode = "Game Mode"
    case privacy = "Privacy"

    var icon: String {
        switch self {
        case .input: return DasherIcon.controlMode
        case .language: return DasherIcon.alphabet
        case .customization: return DasherIcon.palette
        case .output: return DasherIcon.textSize
        case .speech: return DasherIcon.speak
        case .gameMode: return DasherIcon.gameMode
        case .privacy: return "shield-check"
        }
    }

    static func section(for param: DasherParameterInfo) -> DasherSettingsSection {
        if param.name == "Control Mode" || param.name == "Turbo Mode" { return .customization }
        if param.group == "Game Mode" { return .gameMode }
        if param.group == "Output" { return .output }
        if param.group == "Language" { return .language }
        if param.group == "Appearance" || param.group == "Customization" { return .customization }
        return .input
    }
}

// MARK: - Bridge

@MainActor
class DasherBridge: InputMethodBridge, DasherBridgeProtocol {
    private var ctx: OpaquePointer?
    private var lastOutputText: String = ""
    private var fontParamKey: Int = -1
    private let userDir: String

    var onOutput: ((String) -> Void)?
    var onDelete: ((String) -> Void)?
    var onMessage: ((Bool, String) -> Void)?
    var onSpeak: ((String, Bool) -> Void)?
    var onParameterChange: ((Int) -> Void)?
    var onClipboard: ((String) -> Void)?

    private(set) var lastError: String?

    init(dataDir: String, userDir: String? = nil) {
        self.userDir = userDir ?? dataDir
        var errorMsg: UnsafeMutablePointer<CChar>?
        ctx = dasher_create(dataDir, userDir, &errorMsg)
        if let errorMsg = errorMsg {
            lastError = String(cString: errorMsg)
        }
        if let ctx = ctx {
            let retained = Unmanaged.passUnretained(self).toOpaque()
            dasher_set_output_callback(ctx, { eventType, text, userData in
                guard let text = text, let userData = userData else { return }
                let instance = Unmanaged<DasherBridge>.fromOpaque(userData).takeUnretainedValue()
                let str = String(cString: text)
                if eventType == 0 {
                    instance.onOutput?(str)
                } else if eventType == 1 {
                    instance.onDelete?(str)
                }
            }, retained)
            let retained2 = Unmanaged.passUnretained(self).toOpaque()
            dasher_set_message_callback(ctx, { messageType, text, userData in
                guard let text = text, let userData = userData else { return }
                let instance = Unmanaged<DasherBridge>.fromOpaque(userData).takeUnretainedValue()
                let str = String(cString: text)
                let isWarning = messageType == 1
                instance.onMessage?(isWarning, str)
            }, retained2)
            let retained3 = Unmanaged.passUnretained(self).toOpaque()
            dasher_set_speak_callback(ctx, { text, interrupt, userData in
                guard let text = text, let userData = userData else { return }
                let instance = Unmanaged<DasherBridge>.fromOpaque(userData).takeUnretainedValue()
                let str = String(cString: text)
                instance.onSpeak?(str, interrupt != 0)
            }, retained3)
            let retained4 = Unmanaged.passUnretained(self).toOpaque()
            dasher_set_parameter_callback(ctx, { paramKey, userData in
                guard let userData = userData else { return }
                let instance = Unmanaged<DasherBridge>.fromOpaque(userData).takeUnretainedValue()
                instance.onParameterChange?(Int(paramKey))
            }, retained4)
            let retained5 = Unmanaged.passUnretained(self).toOpaque()
            dasher_set_clipboard_callback(ctx, { text, userData in
                guard let text = text, let userData = userData else { return }
                let instance = Unmanaged<DasherBridge>.fromOpaque(userData).takeUnretainedValue()
                let str = String(cString: text)
                instance.onClipboard?(str)
            }, retained5)
            // RFC 0009: forward engine diagnostic lines to the unified system log
            // (os_log) so engine state and boundary exceptions are visible in
            // Console. min_level = 1 (info) keeps per-frame debug spam out.
            dasher_set_log_callback(ctx, { level, message, _ in
                guard let message = message else { return }
                let msg = String(cString: message)
                let type: OSLogType
                switch level {
                case 0: type = .debug
                case 1: type = .info
                case 2: type = .default
                default: type = .error
                }
                os_log("%{public}@", log: macEngineLog, type: type, msg)
                // RFC 0009: also feed the crash-report ring buffer.
                EngineLogBuffer.shared.append(level: Int(level), message: msg)
            }, nil, 1)
        }
        resolveFontParamKey()
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

    func frame(timeMs: Int64) -> DrawCommands? {
        guard let ctx = ctx else { return nil }
        if dasher_has_engine_error(ctx) != 0 {
            notifyEngineErrorIfNeeded()
            return nil
        }
        var cmds: UnsafeMutablePointer<Int32>?
        var cmdCount: Int32 = 0
        var strs: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        var strCount: Int32 = 0

        dasher_frame(ctx, timeMs, &cmds, &cmdCount, &strs, &strCount)

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
            fontName: fontParamKey >= 0 ? getStringParameter(key: fontParamKey) : ""
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

    // MARK: - Training text management

    /// The user-writable training directory.
    private var userTrainingDirURL: URL {
        URL(fileURLWithPath: userDir).appendingPathComponent("training", isDirectory: true)
    }

    /// Finds any training_*.txt file in the user directory.
    private func trainingFileURL() -> URL? {
        let fm = FileManager.default
        let dir = userTrainingDirURL
        if let files = try? fm.contentsOfDirectory(atPath: dir.path) {
            let trainingFiles = files.filter { $0.hasPrefix("training_") && $0.hasSuffix(".txt") }
            if let first = trainingFiles.first {
                return dir.appendingPathComponent(first)
            }
        }
        return nil
    }

    var userTrainingFileSize: Int64 {
        guard let url = trainingFileURL(),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    var userTrainingSizeDescription: String {
        let bytes = userTrainingFileSize
        if bytes == 0 { return "No custom training data" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    func importTrainingText(_ text: String) {
        guard let ctx = ctx else { return }
        dasher_import_training_text(ctx, text)

        let dir = userTrainingDirURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = trainingFileURL() ?? dir.appendingPathComponent("training_english_GB.txt")
        if let data = text.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: url)
            }
        }
    }

    func exportTrainingText() -> String? {
        guard let url = trainingFileURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func resetTrainingData() {
        let dir = userTrainingDirURL
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for file in files where file.hasPrefix("training_") && file.hasSuffix(".txt") {
                try? FileManager.default.removeItem(atPath: dir.appendingPathComponent(file).path)
            }
        }
    }

    // MARK: - Parameter schema

    func findParameterKey(_ name: String) -> Int {
        Int(dasher_find_parameter_key(name))
    }

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
        let bufSize = 64
        var buffer: [UnsafePointer<CChar>?] = Array(repeating: nil, count: bufSize)
        let actual = Int(dasher_get_parameter_string_values(ctx, Int32(key), &buffer, Int32(bufSize)))
        return (0..<min(actual, bufSize)).compactMap { ptr in
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

    func setSystemAppearance(dark: Bool) {
        guard let ctx = ctx else { return }
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
    }

    // MARK: - Game Mode

    var isGameModeActive: Bool {
        guard let ctx = ctx else { return false }
        return dasher_game_mode_active(ctx) != 0
    }

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

    // MARK: - Typing rate (RFC 0012)

    func getWPM() -> Double {
        guard let ctx = ctx else { return 0 }
        return dasher_get_wpm(ctx)
    }

    // MARK: - Strand 2: custom rendering (RFC 0013)

    struct VisibleNode {
        let dasherY1: Int64
        let dasherY2: Int64
        let symbol: Int32
        let hasChildren: Bool
        let depth: Int32
        let isGameNode: Bool
        let screenX1: Int32
        let screenY1: Int32
        let screenX2: Int32
        let screenY2: Int32
        let fillARGB: Int32
        let outlineARGB: Int32
        let labelIndex: Int32
    }

    func setVisibleNodesEnabled(_ enabled: Bool) {
        guard let ctx = ctx else { return }
        dasher_set_visible_nodes_enabled(ctx, enabled ? 1 : 0)
    }

    func getVisibleNodes() -> [VisibleNode] {
        guard let ctx = ctx else { return [] }
        var info = dasher_node_info()
        info.struct_size = Int32(MemoryLayout<dasher_node_info>.size)
        var nodes: [VisibleNode] = []
        var strings: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? = nil
        var stringCount: Int32 = 0

        // First call with a small buffer to get total count
        var buffer = [dasher_node_info](repeating: info, count: 4)
        let total = dasher_get_visible_nodes(ctx, &buffer, 4, &strings, &stringCount)
        guard total > 0 else { return [] }

        // Re-allocate if needed
        if total > 4 {
            buffer = [dasher_node_info](repeating: info, count: Int(total))
        }

        let written = total > Int32(buffer.count) ? Int32(buffer.count) : total
        for i in 0..<Int(written) {
            buffer[i].struct_size = Int32(MemoryLayout<dasher_node_info>.size)
        }
        // Re-query with correct buffer size
        let actualTotal = dasher_get_visible_nodes(ctx, &buffer, Int32(buffer.count), &strings, &stringCount)
        let count = min(Int(actualTotal), buffer.count)

        for i in 0..<count {
            let n = buffer[i]
            nodes.append(VisibleNode(
                dasherY1: n.dasher_y1,
                dasherY2: n.dasher_y2,
                symbol: n.symbol,
                hasChildren: n.has_children != 0,
                depth: n.depth,
                isGameNode: n.is_game_node != 0,
                screenX1: n.screen_x1,
                screenY1: n.screen_y1,
                screenX2: n.screen_x2,
                screenY2: n.screen_y2,
                fillARGB: n.fill_argb,
                outlineARGB: n.outline_argb,
                labelIndex: n.label_index
            ))
        }
        _ = strings // owned by engine
        return nodes
    }

    func getVisibleNodeLabels() -> [String] {
        guard let ctx = ctx else { return [] }
        var info = dasher_node_info()
        info.struct_size = Int32(MemoryLayout<dasher_node_info>.size)
        var buffer = [dasher_node_info](repeating: info, count: 256)
        var strings: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? = nil
        var stringCount: Int32 = 0

        for i in 0..<256 { buffer[i].struct_size = Int32(MemoryLayout<dasher_node_info>.size) }
        dasher_get_visible_nodes(ctx, &buffer, 256, &strings, &stringCount)
        guard let strPtr = strings, stringCount > 0 else { return [] }
        var result: [String] = []
        for i in 0..<Int(stringCount) {
            if let cStr = strPtr[i] {
                result.append(String(cString: cStr))
            } else {
                result.append("")
            }
        }
        return result
    }

    // MARK: - Persistence

    func saveSettings() {
        guard let ctx = ctx else { return }
        dasher_save_settings(ctx)
    }

    /// Restore all Dasher settings to their built-in defaults. Deletes the
    /// persisted settings files (so defaults load on the next launch) and
    /// resets every in-memory parameter via `dasher_reset_settings` (so the
    /// live engine updates too). The engine output/position is also reset.
    func resetToDefaults() {
        guard let ctx = ctx else { return }
        let dir = URL(fileURLWithPath: userDir)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("dasher_settings.xml"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("appearance_settings.xml"))
        dasher_reset_settings(ctx)
        dasher_reset(ctx)
        lastOutputText = ""
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

private func shadeCGColor(_ color: CGColor, by factor: CGFloat) -> CGColor {
    guard let comps = color.components, comps.count >= 3 else { return color }
    let r = comps[0], g = comps[1], b = comps[2]
    let a = comps.count >= 4 ? comps[3] : 1.0
    if factor >= 0 {
        return CGColor(red: r + (1 - r) * factor, green: g + (1 - g) * factor,
                       blue: b + (1 - b) * factor, alpha: a)
    } else {
        let m = 1 + factor
        return CGColor(red: r * m, green: g * m, blue: b * m, alpha: a)
    }
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

        // Cube data buffered during pass 1 for pass-2 3D overlay.
        struct CubeCmd { let x1: CGFloat; let y1: CGFloat; let x2: CGFloat; let y2: CGFloat;
                        let fill: CGColor; let outline: CGColor; let thick: Int }
        var cubes: [CubeCmd] = []

        var i = 0
        while i < count {
            let base = i * 6
            let op = Int(commands[base + 0])
            let a = CGFloat(commands[base + 1])
            let b = CGFloat(commands[base + 2])
            let c = Int(commands[base + 3])
            let d = Int(commands[base + 4])
            let argb = Int32(commands[base + 5])
            let cgColor = argbToCGColor(argb)

            switch op {
            case 7:
                if i + 1 < count {
                    let base2 = (i + 1) * 6
                    cubes.append(CubeCmd(x1: a, y1: b, x2: CGFloat(c), y2: CGFloat(d),
                                          fill: argbToCGColor(Int32(commands[base2 + 1])),
                                          outline: argbToCGColor(Int32(commands[base2 + 2])),
                                          thick: Int(commands[base2 + 3])))
                }
                i += 2
                continue
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
                    let font: NSFont
                    if self.fontName.isEmpty {
                        font = NSFont.systemFont(ofSize: fontSize)
                    } else {
                        font = NSFont(name: self.fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
                    }
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: NSColor(cgColor: cgColor) ?? NSColor.textColor
                    ]
                    let flippedY = viewHeight - b - fontSize
                    NSAttributedString(string: text, attributes: attrs).draw(at: CGPoint(x: a, y: flippedY))
                }
            default:
                break
            }
            i += 1
        }

        // Pass 2: render buffered cubes as 3D overlay.
        for cube in cubes {
            let y1f = viewHeight - cube.y1
            let y2f = viewHeight - cube.y2
            let minY = min(y1f, y2f)
            let maxY = max(y1f, y2f)
            let w = cube.x2 - cube.x1
            let h = maxY - minY
            let e = max(5.0, min(20.0, h * 0.4))

            // Right face (darker) — to the right of the front face
            context.setFillColor(shadeCGColor(cube.fill, by: -0.35))
            context.fill(CGRect(x: cube.x2, y: minY, width: e, height: h))
            // Top face (lighter) — above the front face, spanning full width + extrusion
            context.setFillColor(shadeCGColor(cube.fill, by: 0.35))
            context.fill(CGRect(x: cube.x1, y: maxY, width: w + e, height: e))
            // Front face (base colour)
            context.setFillColor(cube.fill)
            context.fill(CGRect(x: cube.x1, y: minY, width: w, height: h))
            // Outline around the front face
            if cube.thick > 0 {
                context.setStrokeColor(cube.outline)
                context.setLineWidth(CGFloat(cube.thick))
                context.stroke(CGRect(x: cube.x1, y: minY, width: w, height: h))
            }
        }

        /// Strand 2 helper: render Strand 1 commands but SKIP opcode 4 (node fills)
        /// so the Strand 2 cube overlay renders them instead. Background (0),
        /// circles (1), lines (2), outlines (3), text (5) all pass through.
        func renderStrand1Background(in context: CGContext, bounds: CGRect, viewHeight: CGFloat) {
            let count = commandCount / 6
            var i = 0
            while i < count {
                let base = i * 6
                let op = Int(commands[base + 0])
                if op == 7 { i += 2; continue } // skip cube slots
                if op == 4 { i += 1; continue }  // skip node fills — Strand 2 handles them

                let a = CGFloat(commands[base + 1])
                let b = CGFloat(commands[base + 2])
                let c = Int(commands[base + 3])
                let d = Int(commands[base + 4])
                let argb = Int32(commands[base + 5])
                let cgColor = argbToCGColor(argb)

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
                case 5:
                    let fontSize = CGFloat(c > 0 ? c : 14)
                    let stringIndex = d
                    if let strings = strings, stringIndex >= 0, stringIndex < stringCount, let strPtr = strings[stringIndex] {
                        let text = String(cString: strPtr)
                        let font = NSFont.systemFont(ofSize: fontSize)
                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: font,
                            .foregroundColor: NSColor(cgColor: cgColor) ?? NSColor.textColor
                        ]
                        let flippedY = viewHeight - b - fontSize
                        NSAttributedString(string: text, attributes: attrs).draw(at: CGPoint(x: a, y: flippedY))
                    }
                default:
                    break
                }
                i += 1
            }
        }
    }
}
#endif
