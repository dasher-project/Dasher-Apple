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

    private(set) var lastError: String?

    init(dataDir: String, userDir: String? = nil) {
        var errorMsg: UnsafeMutablePointer<CChar>?
        ctx = dasher_create(dataDir, userDir, &errorMsg)
        if let errorMsg = errorMsg {
            lastError = String(cString: errorMsg)
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

    func frame(timeMs: Int64) -> DrawCommands? {
        guard let ctx = ctx else { return nil }
        var cmds: UnsafeMutablePointer<Int32>?
        var cmdCount: Int32 = 0
        var strs: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        var strCount: Int32 = 0

        dasher_frame(ctx, timeMs, &cmds, &cmdCount, &strs, &strCount)

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

    // MARK: - Persistence

    func saveSettings() {
        guard let ctx = ctx else { return }
        dasher_save_settings(ctx)
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
