import SwiftUI
import DasherShared
import DasherSpeech
import UniformTypeIdentifiers

@MainActor
class DasherViewModel: ObservableObject {
    @Published var outputText: String = ""
    @Published var isPlaying: Bool = true
    @Published var isGameModeActive: Bool = false
    @Published var isControlModeActive: Bool = false
    @Published var gameTargetText: String = ""
    @Published var gameCorrectCount: Int = 0
    @Published var gameTargetLength: Int = 0
    @Published var gameWrongText: String = ""
    @Published var pendingMessage: (isWarning: Bool, text: String)?
    @Published var speed: Double = 1.0
    @Published var autoSpeed: Bool = false
    @Published var pointerHoverEnabled: Bool = false
    @Published var appLevelDwell: Bool = false
    @Published var dwellDuration: Double = 0.5
    @Published var showOpenFile = false
    @Published var showShareSheet = false
    @Published var importedText: String?

    let bridge: DasherBridge
    let speech = SpeechService.shared
    #if os(iOS)
    let tiltService = TiltInputService()
    #endif
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
        bridge.setScreenSize(width: 800, height: 600)
        bridge.onMessage = { [weak self] isWarning, text in
            if text.contains("No user training text found") { return }
            self?.pendingMessage = (isWarning, text)
        }
        bridge.onEngineError = { [weak self] in
            guard let self else { return }
            self.pendingMessage = (true, "Dasher encountered an error and has stopped. Please restart Dasher to continue.")
            // RFC 0009: caught engine faults don't crash (TestFlight only sees
            // hard crashes), so report via PostHog with the engine_log_tail.
            AnalyticsService.shared.captureEngineError(reason: "Engine entered error state (dasher_has_engine_error)")
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
        let savedConfig = AccessConfiguration.current
        savedConfig.apply(to: bridge)
        #if os(iOS)
        if savedConfig.method == .tilt {
            tiltService.activate(bridge: bridge)
        }
        #endif

        let bitrateKey = bridge.findParameterKey("LP_MAX_BITRATE")
        bridge.onParameterChange = { [weak self] key in
            guard key == bitrateKey else { return }
            Task { @MainActor in
                self?.speed = Double(self?.bridge.speedPercent ?? 100) / 100.0
            }
        }
        speed = Double(bridge.speedPercent) / 100.0
    }

    func setCanvasSize(_ size: CGSize) {
        bridge.setScreenSize(width: Int(size.width), height: Int(size.height))
        #if os(iOS)
        tiltService.screenWidth = Int(size.width)
        tiltService.screenHeight = Int(size.height)
        #endif
    }

    func handlePointerHover(at point: CGPoint) {
        guard isPlaying else { return }
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    var isContinuousSelection: Bool {
        AccessConfiguration.current.selection == .continuous
    }

    func handleHoverDown(at point: CGPoint) {
        guard isPlaying else { return }
        bridge.mouseDown()
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    func handleHoverUp() {
        guard isPlaying else { return }
        bridge.mouseUp()
    }

    func handleTouch(at point: CGPoint) {
        guard isPlaying else { return }
        bridge.mouseDown()
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    func handleTouchMove(at point: CGPoint) {
        guard isPlaying else { return }
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    func handleTouchEnd() {
        guard isPlaying else { return }
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

    func toggleControlMode() {
        isControlModeActive.toggle()
        let key = bridge.findParameterKey("BP_CONTROL_MODE")
        bridge.setBoolParameter(key: key, value: isControlModeActive)
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

    func openText(_ text: String) {
        bridge.reset()
        outputText = text
        lastSpokenText = ""
    }

    var shareText: String {
        outputText
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

    #if os(iOS)
    func activateTiltIfNeeded(method: AccessMethod) {
        if method == .tilt && tiltService.isCalibrating == false {
            if !tiltService.isActive {
                tiltService.activate(bridge: bridge)
            }
        } else {
            if tiltService.isActive {
                tiltService.deactivate()
            }
        }
    }
    #endif
}
