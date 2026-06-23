import SwiftUI
import UIKit
import DasherSpeech

@MainActor
class VisionViewModel: ObservableObject {
    @Published var outputText: String = ""
    @Published var isPlaying: Bool = true
    @Published var isGameModeActive: Bool = false
    @Published var gameTargetText: String = ""
    @Published var gameCorrectCount: Int = 0
    @Published var gameTargetLength: Int = 0
    @Published var gameWrongText: String = ""
    @Published var pendingMessage: (isWarning: Bool, text: String)?
    @Published var speed: Double = 1.0
    @Published var pointerHoverEnabled: Bool = true
    @Published var appLevelDwell: Bool = false
    @Published var dwellDuration: Double = 0.5

    let bridge: DasherBridge
    let speech = SpeechService.shared
    private var lastSpokenText: String = ""

    static let dwellDurationOptions: [(String, Double)] = [
        ("0.3s", 0.3),
        ("0.5s", 0.5),
        ("0.8s", 0.8),
        ("1.0s", 1.0),
        ("1.5s", 1.5),
    ]

    init() {
        let dataPath = Bundle.main.path(forResource: "Data", ofType: nil) ?? ""
        let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedDefaults.groupIdentifier
        )
        self.bridge = DasherBridge(dataDir: dataPath, userDir: sharedURL?.path)
        configureForEyeGaze()
        let savedConfig = AccessConfiguration.current
        savedConfig.apply(to: bridge)
        bridge.onOutput = { [weak self] _ in
            self?.outputText = self?.bridge.getOutputText() ?? ""
        }
        bridge.onDelete = { [weak self] _ in
            self?.outputText = self?.bridge.getOutputText() ?? ""
        }
        bridge.onMessage = { [weak self] isWarning, text in
            if text.contains("No user training text found") { return }
            self?.pendingMessage = (isWarning, text)
        }
        bridge.onSpeak = { [weak self] text, interrupt in
            Task { @MainActor in
                self?.lastSpokenText = text
                if interrupt {
                    self?.speech.stop()
                }
                self?.speech.speak(text)
            }
        }
        bridge.onClipboard = { text in
            Task { @MainActor in
                UIPasteboard.general.string = text
            }
        }
    }

    func setCanvasSize(_ size: CGSize) {
        bridge.setScreenSize(width: Int(size.width), height: Int(size.height))
    }

    func handlePointerHover(at point: CGPoint) {
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    func handleTouch(at point: CGPoint) {
        bridge.mouseDown()
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    func handleTouchMove(at point: CGPoint) {
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    func handleTouchEnd() {
        bridge.mouseUp()
    }

    func togglePlay() {
        isPlaying.toggle()
    }

    func toggleGameMode() {
        if isGameModeActive {
            bridge.leaveGameMode()
            isGameModeActive = false
        } else {
            let success = bridge.enterGameMode()
            isGameModeActive = success
            if !success {
                bridge.reset()
                outputText = ""
            }
        }
    }

    func syncGameModeState() {
        let active = bridge.isGameModeActive
        if active != isGameModeActive {
            isGameModeActive = active
        }
        if active {
            gameTargetText = bridge.getGameTargetText()
            gameCorrectCount = bridge.getGameCorrectCount()
            gameTargetLength = bridge.getGameTargetLength()
            gameWrongText = bridge.getGameWrongText()
        } else {
            gameTargetText = ""
            gameCorrectCount = 0
            gameTargetLength = 0
            gameWrongText = ""
        }
    }

    func newMessage() {
        bridge.reset()
        outputText = ""
        lastSpokenText = ""
    }

    func increaseSpeed() {
        let newSpeed = min(bridge.speedPercent + 10, 400)
        bridge.setSpeedPercent(newSpeed)
        speed = Double(newSpeed) / 100.0
    }

    func decreaseSpeed() {
        let newSpeed = max(bridge.speedPercent - 10, 20)
        bridge.setSpeedPercent(newSpeed)
        speed = Double(newSpeed) / 100.0
    }

    func copyOutput() {
        UIPasteboard.general.string = outputText
    }

    // MARK: - Eye gaze defaults

    private func configureForEyeGaze() {
        // Pinch = start Dasher (mouseDown), release = pause
        setParam("BP_START_MOUSE", true)
        setParam("LP_START_MODE", 1) // 1 = start on mouse down
        // Pause when gaze leaves the canvas — prevents uncontrolled zooming
        setParam("BP_STOP_OUTSIDE", true)
        // Eye gaze drifts; auto-calibrate keeps the target centred
        setParam("BP_AUTOCALIBRATE", true)
        // Adapt speed to user's pace
        setParam("BP_AUTO_SPEEDCONTROL", true)
        // Eye gaze reaches extreme angles; remap helps navigation
        setParam("BP_REMAP_XTREME", true)
        // Non-linear Y smooths jerky vertical gaze
        setParam("BP_NONLINEAR_Y", true)
        // No turbo on visionOS — no keyboard/right-mouse to trigger
        setParam("BP_TURBO_MODE", false)
        // Slightly slower than default — eye gaze needs more precision
        bridge.setSpeedPercent(100) // 100% = moderate; auto-speed will adapt
    }

    private func setParam(_ name: String, _ value: Bool) {
        let key = bridge.findParameterKey(name)
        if key >= 0 { bridge.setBoolParameter(key: key, value: value) }
    }

    private func setParam(_ name: String, _ value: Int) {
        let key = bridge.findParameterKey(name)
        if key >= 0 { bridge.setLongParameter(key: key, value: value) }
    }
}
