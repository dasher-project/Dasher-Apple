import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
class DasherBridge {
    private var ctx: OpaquePointer?
    private var lastOutputText: String = ""

    init(dataDir: String) {
        ctx = dasher_create(dataDir)
    }

    deinit {
        if let ctx = ctx {
            dasher_destroy(ctx)
        }
    }

    var isReady: Bool { ctx != nil }

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
            stringCount: Int(strCount)
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
}

struct DrawCommands {
    let commands: UnsafeMutablePointer<Int32>
    let commandCount: Int
    let strings: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    let stringCount: Int
}

private func argbToCGColor(_ argb: Int32) -> CGColor {
    CGColor(red: CGFloat((argb >> 16) & 0xFF) / 255.0,
            green: CGFloat((argb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(argb & 0xFF) / 255.0,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255.0)
}

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
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: fontSize),
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
