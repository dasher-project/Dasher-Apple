import Foundation
import CoreMotion
import SwiftUI
import UIKit

enum WatchInputMethod: String, CaseIterable, Identifiable {
    case touch
    case crown
    case tilt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .touch: return "Touch"
        case .crown: return "Crown"
        case .tilt: return "Tilt"
        }
    }

    var symbol: String {
        switch self {
        case .touch: return "hand.tap"
        case .crown: return "crown" // SF Symbol "crown" (watchOS 8+)
        case .tilt: return "iphone.gen3.radiowaves.left.and.right"
        }
    }
}

@MainActor
final class WatchViewModel: ObservableObject {
    let bridge: WatchBridge
    private let dataPath: String

    @Published private(set) var isEngineReady = false
    @Published private(set) var engineErrorMessage: String?
    @Published var outputText = ""

    /// Selected input method (persisted; crown uses the engine's One
    /// Dimensional Mode filter, touch/tilt use the default 2-D filter).
    @Published var inputMethod: WatchInputMethod {
        didSet {
            UserDefaults.standard.set(inputMethod.rawValue, forKey: "watch_input_method")
            applyInputFilter()
            tiltActive = (inputMethod == .tilt)
        }
    }

    /// Canvas orientation (persisted; applied post-realize — see the LP_ORIENTATION
    /// note in WatchBridge). Vertical was the spike default; horizontal is the
    /// classic layout. User's call now.
    @Published var orientation: WatchOrientation {
        didSet {
            UserDefaults.standard.set(orientation.rawValue, forKey: "watch_orientation")
            bridge.applyOrientation(orientation)
        }
    }

    // MARK: - Parity settings (Mac/iOS footer controls)

    /// Learn from what is typed (BP_LM_ADAPTIVE) — "Learning" on Mac.
    @Published var learningMode: Bool = true {
        didSet {
            bridge.setBoolParam("BP_LM_ADAPTIVE", learningMode)
            bridge.saveSettings()
        }
    }

    /// Adapt speed to the user's pace (BP_AUTO_SPEEDCONTROL) — "Auto" on Mac.
    @Published var adaptiveSpeed: Bool = false {
        didSet {
            bridge.setBoolParam("BP_AUTO_SPEEDCONTROL", adaptiveSpeed)
            bridge.saveSettings()
        }
    }

    /// Control characters in the alphabet (BP_CONTROL_MODE): copy, speak,
    /// paragraph/cursor commands — the "Control Mode" Mac setting.
    @Published var controlMode: Bool = false {
        didSet {
            bridge.setBoolParam("BP_CONTROL_MODE", controlMode)
            bridge.saveSettings()
        }
    }

    /// Speed as the Apple-style multiplier the other frontends show
    /// (1.0× = 100 %). The raw engine unit is MaxBitRate×100; the % we
    /// previously presented confused users coming from Dasher-Apple.
    @Published var speedMultiplier: Double = 1.0 {
        didSet {
            bridge.setSpeedPercent(Int(speedMultiplier * 100))
            bridge.saveSettings()
        }
    }

    /// Engine input filter (SP_INPUT_FILTER) — "Normal Control",
    /// "One Dimensional Mode", button modes, etc. The input-method picker
    /// above still drives the common cases; this exposes the full engine list.
    @Published var inputFilter: String = "Normal Control" {
        didSet {
            bridge.setStringParam("SP_INPUT_FILTER", inputFilter)
            bridge.saveSettings()
        }
    }

    var permittedInputFilters: [String] {
        bridge.permittedValues(forParam: "SP_INPUT_FILTER")
    }

    static let speedChoices: [Double] = [0.5, 0.8, 1.0, 1.3, 1.6, 2.0, 2.5, 3.2]

    // MARK: - Crown state (0...1, 0.5 = centreline)

    @Published var crownPosition: Double = 0.5 {
        didSet { crownSteer() }
    }

    // MARK: - Tilt state

    private let motion = CMMotionManager()
    private var tiltActive = false
    private var tiltNeutral: (x: Double, y: Double)?
    private var tiltEngaged = false
    private var canvasSize: CGSize = CGSize(width: 200, height: 200)

    private static let crownDeadZone = 0.12
    private static let tiltDeadZone = 0.10

    init() {
        // The folder-reference resource keeps its source name: DasherWatchData
        // (not "Data" like the iOS targets). A wrong name silently produced an
        // empty dataDir and the engine's current_path() fallback scanned the
        // user's home directory — now a hard, surfaced failure instead.
        let dataPath = Bundle.main.path(forResource: "DasherWatchData", ofType: nil) ?? ""
        self.dataPath = dataPath
        if dataPath.isEmpty {
            engineErrorMessage = "Bundled data is missing (DasherWatchData). Reinstall the app."
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.bridge = WatchBridge(dataDir: dataPath, userDir: docs.path)
        let saved = UserDefaults.standard.string(forKey: "watch_input_method")
            .flatMap(WatchInputMethod.init(rawValue:)) ?? .touch
        self.inputMethod = saved
        let savedOrientation = UserDefaults.standard.string(forKey: "watch_orientation")
            .flatMap(WatchOrientation.init(rawValue:)) ?? .vertical
        self.orientation = savedOrientation

        bridge.onOutput = { [weak self] _ in
            self?.outputText = self?.bridge.outputText ?? ""
        }

        Task { [weak self] in
            await bridge.bootstrap()
            guard let self else { return }
            if let err = bridge.lastError {
                self.engineErrorMessage = err
                return
            }
            // Only realize at a sane size (>= 32pt via the setCanvasSize gate);
            // the default covers the pre-layout window. Orientation and the
            // input filter MUST follow a genuine realize — setting them against
            // an unrealized engine segfaults (ChangeView with no screen).
            let target = self.pendingCanvasSize ?? CGSize(width: 324, height: 394)
            guard target.width >= 32, target.height >= 32 else { return }
            self.isRealizing = true
            defer { self.isRealizing = false }
            await bridge.realize(screenWidth: Int(target.width), screenHeight: Int(target.height))
            if bridge.hasEngineError {
                self.engineErrorMessage = "The engine could not start (data scan failed). Try reinstalling the app."
                return
            }
            bridge.applyOrientation(self.orientation)
            self.applyInputFilter()
            self.learningMode = bridge.boolParam("BP_LM_ADAPTIVE")
            self.adaptiveSpeed = bridge.boolParam("BP_AUTO_SPEEDCONTROL")
            self.controlMode = bridge.boolParam("BP_CONTROL_MODE")
            self.speedMultiplier = Double(bridge.speedPercent) / 100.0
            self.inputFilter = bridge.stringParam("SP_INPUT_FILTER")
            self.isEngineReady = true
        }
    }

    private var pendingCanvasSize: CGSize?

    /// SwiftUI reports transient zero/tiny fractional sizes during multi-pass
    /// layout. Forwarding them realizes/resizes the engine at a degenerate
    /// geometry, which corrupts the model (verified crash — see the DasherCore
    /// issues). Ignore anything below a sane floor; the settled size arrives
    /// within a few passes.
    func setCanvasSize(_ size: CGSize) {
        guard size.width >= 32, size.height >= 32 else { return }
        canvasSize = size
        pendingCanvasSize = size
        bridge.setCanvasSize(size)
    }

    private func applyInputFilter() {
        bridge.setOneDimensionalMode(inputMethod == .crown)
    }

    // MARK: - Frame

    /// True while the (long) off-main realize runs: frame() returns nil
    /// instead of blocking on the engine lock, so the UI stays responsive —
    /// a slow realize previously froze the whole render loop behind the lock.
    @Published private(set) var isRealizing = false

    /// Called from the TimelineView/Canvas each animation tick.
    func frame(timeMs: Int64) -> WatchDrawCommands? {
        return bridge.frame(timeMs: timeMs)
    }

    // MARK: - Touch input (2-D default filter, like the iOS app)

    private var touchDown = false

    func touchAt(_ point: CGPoint) {
        if !touchDown {
            touchDown = true
            bridge.mouseDown()
        }
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    func touchEnded() {
        touchDown = false
        bridge.mouseUp()
    }

    // MARK: - Crown input (One Dimensional Mode: Y-only, X synthesized)

    private var crownEngaged = false

    private func crownSteer() {
        guard isEngineReady, inputMethod == .crown else { return }
        let deflection = crownPosition - 0.5
        let y = crownPosition * Double(canvasSize.height)
        if abs(deflection) < Self.crownDeadZone {
            if crownEngaged {
                crownEngaged = false
                bridge.mouseUp()
            }
            return
        }
        if !crownEngaged {
            crownEngaged = true
            bridge.mouseDown()
        }
        bridge.mouseMove(x: Float(canvasSize.width / 2), y: Float(y))
    }

    // MARK: - Tilt input (gravity vector around a captured neutral)

    func startTilt() {
        guard tiltActive, motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] motionData, _ in
            guard let self, let gravity = motionData?.gravity else { return }
            self.tiltSteer(gx: gravity.x, gy: gravity.y, gz: gravity.z)
        }
    }

    func stopTilt() {
        motion.stopDeviceMotionUpdates()
        tiltNeutral = nil
        if tiltEngaged {
            tiltEngaged = false
            bridge.mouseUp()
        }
    }

    func recalibrateTilt() {
        tiltNeutral = nil
    }

    private func tiltSteer(gx: Double, gy: Double, gz: Double) {
        guard isEngineReady, inputMethod == .tilt else { return }
        if tiltNeutral == nil {
            tiltNeutral = (gx, gy)
            return
        }
        let dx = gx - tiltNeutral!.x
        let dy = gy - tiltNeutral!.y
        let scale = 2.5
        let x = Double(canvasSize.width) / 2 + dx * scale * Double(canvasSize.width)
        let y = Double(canvasSize.height) / 2 + dy * scale * Double(canvasSize.height)
        if hypot(dx, dy) < Self.tiltDeadZone {
            if tiltEngaged {
                tiltEngaged = false
                bridge.mouseUp()
            }
            return
        }
        if !tiltEngaged {
            tiltEngaged = true
            bridge.mouseDown()
        }
        bridge.mouseMove(x: Float(x), y: Float(y))
    }

    // MARK: - Output

    var recentOutput: String {
        String(outputText.suffix(90))
    }


    /// watchOS has no UIPasteboard — the platform-native "copy" is Handoff:
    /// publish the text in a user activity so a receiving device (the Dasher
    /// iPhone app, once it adopts the activity type) can continue with it.
    func handoff() {
        let activity = NSUserActivity(activityType: "at.dasher.Dasher.watch.text")
        activity.title = "Dasher text"
        activity.userInfo = ["dasherText": outputText]
        activity.isEligibleForHandoff = true
        activity.becomeCurrent()
    }

    func clearOutput() {
        bridge.resetOutput()
        outputText = ""
    }

    /// Factory reset: wipe persisted settings, reset the live engine, refresh
    /// every published setting from the fresh defaults.
    func resetAllSettings() {
        bridge.resetAllSettings()
        learningMode = bridge.boolParam("BP_LM_ADAPTIVE")
        adaptiveSpeed = bridge.boolParam("BP_AUTO_SPEEDCONTROL")
        controlMode = bridge.boolParam("BP_CONTROL_MODE")
        speedMultiplier = Double(bridge.speedPercent) / 100.0
        inputFilter = bridge.stringParam("SP_INPUT_FILTER")
        bridge.applyOrientation(orientation)
        clearOutput()
    }

    // MARK: - Rendering (SwiftUI GraphicsContext port of the command buffer)

    func render(in context: GraphicsContext, size: CGSize, timeMs: Int64) {
        guard let cmds = bridge.frame(timeMs: timeMs) else {
            // No commands this frame: keep the canvas black.
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            return
        }
        let count = cmds.commandCount / 6
        for i in 0..<count {
            let base = i * 6
            let op = Int(cmds.commands[base + 0])
            let a = CGFloat(cmds.commands[base + 1])
            let b = CGFloat(cmds.commands[base + 2])
            let c = CGFloat(cmds.commands[base + 3])
            let d = CGFloat(cmds.commands[base + 4])
            let argb = Int32(cmds.commands[base + 5])
            let color = argbColor(argb)

            switch op {
            case 0:
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))
            case 1:
                let radius = c
                let rect = CGRect(x: a - radius, y: b - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            case 2:
                var line = Path()
                line.move(to: CGPoint(x: a, y: b))
                line.addLine(to: CGPoint(x: c, y: d))
                context.stroke(line, with: .color(color), lineWidth: 2)
            case 3:
                let rect = CGRect(x: a, y: b, width: c - a, height: d - b)
                context.stroke(Path(rect), with: .color(color), lineWidth: 1)
            case 4:
                let rect = CGRect(x: a, y: b, width: c - a, height: d - b)
                context.fill(Path(rect), with: .color(color))
            case 5:
                let fontSize = c > 0 ? c : 14
                let stringIndex = Int(d)
                if let strings = cmds.strings, stringIndex >= 0, stringIndex < cmds.stringCount,
                   let strPtr = strings[stringIndex] {
                    let text = String(cString: strPtr)
                    context.draw(
                        Text(text).font(.system(size: fontSize)).foregroundColor(color),
                        at: CGPoint(x: a, y: b),
                        anchor: .topLeading
                    )
                }
            default:
                break
            }
        }
    }

    /// CoreGraphics rendering path (WatchCanvasView) — same command-walking
    /// as the SwiftUI render but drawing into a CGContext via UIView.draw(_:).
    func renderCG(in ctx: CGContext, bounds: CGRect, timeMs: Int64) {
        guard let cmds = bridge.frame(timeMs: timeMs) else {
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fill(bounds)
            return
        }
        let count = cmds.commandCount / 6
        for i in 0..<count {
            let base = i * 6
            let op = Int(cmds.commands[base + 0])
            let a = CGFloat(cmds.commands[base + 1])
            let b = CGFloat(cmds.commands[base + 2])
            let c = CGFloat(cmds.commands[base + 3])
            let d = CGFloat(cmds.commands[base + 4])
            let argb = Int32(cmds.commands[base + 5])
            let color = argbUIColor(argb)

            switch op {
            case 0:
                ctx.setFillColor(color)
                ctx.fill(bounds)
            case 1:
                let radius = c
                let rect = CGRect(x: a - radius, y: b - radius, width: radius * 2, height: radius * 2)
                ctx.setFillColor(color)
                ctx.fillEllipse(in: rect)
            case 2:
                ctx.setStrokeColor(color)
                ctx.setLineWidth(2)
                ctx.move(to: CGPoint(x: a, y: b))
                ctx.addLine(to: CGPoint(x: c, y: d))
                ctx.strokePath()
            case 3:
                let rect = CGRect(x: a, y: b, width: c - a, height: d - b)
                ctx.setStrokeColor(color)
                ctx.setLineWidth(1)
                ctx.stroke(rect)
            case 4:
                let rect = CGRect(x: a, y: b, width: c - a, height: d - b)
                ctx.setFillColor(color)
                ctx.fill(rect)
            case 5:
                let fontSize = c > 0 ? c : 14
                let stringIndex = Int(d)
                if let strings = cmds.strings, stringIndex >= 0, stringIndex < cmds.stringCount,
                   let strPtr = strings[stringIndex] {
                    let text = String(cString: strPtr) as NSString
                    let font = UIFont.systemFont(ofSize: fontSize)
                    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(cgColor: color)]
                    text.draw(at: CGPoint(x: a, y: b), withAttributes: attrs)
                }
            default:
                break
            }
        }
    }

    private func argbUIColor(_ argb: Int32) -> CGColor {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        return CGColor(red: r, green: g, blue: b, alpha: a)
    }

    private func argbColor(_ argb: Int32) -> Color {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}
