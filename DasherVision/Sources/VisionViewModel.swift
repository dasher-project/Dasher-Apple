import SwiftUI
import UIKit
import DasherShared
import DasherSpeech
import os.log

private let visionLog = OSLog(subsystem: "at.dasher.Dasher.vision", category: "gaze")

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
    /// Selection method mirrored from AccessConfiguration so the Settings UI
    /// can change it and the canvas can read `isContinuousSelection`.
    /// Defaults to `.continuous` on visionOS (see AccessConfiguration.defaultConfiguration).
    @Published var selectionMethod: SelectionMethod = AccessConfiguration.current.selection
    /// On-canvas debug overlay showing live hover/touch telemetry.
    /// Default ON while we diagnose the eye-gaze issue — flip from Settings.
    @Published var debugInputOverlay: Bool = true

    let bridge: DasherBridge
    let speech = SpeechService.shared
    private var lastSpokenText: String = ""
    private var touchMoveLogCounter: Int = 0

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
        self.dataPath = dataPath
        self.bridge = DasherBridge(dataDir: dataPath, userDir: sharedURL?.path)
        let savedConfig = AccessConfiguration.current
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
                self?.speech.phonemeMode = self?.bridge.alphabetId.contains("X-SAMPA") ?? false
                self?.speech.speak(text)
            }
        }
        bridge.onClipboard = { text in
            Task { @MainActor in
                UIPasteboard.general.string = text
            }
        }

        // RFC 0018 two-phase start: engine create + locale + first realize on
        // a background task; gaze defaults + access config need the live
        // engine, so they run post-boot.
        Task { [weak self] in
            await bridge.bootstrap()
            guard let self else { return }
            if let size = self.pendingCanvasSize {
                await bridge.realize(screenWidth: Int(size.width), screenHeight: Int(size.height))
            }
            self.configureForEyeGaze()
            savedConfig.apply(to: self.bridge)
            self.applyLocaleFollowIfNeeded()
            self.isEngineReady = true
        }
    }

    /// RFC 0003 locale-follow (Dasher-Android #31 parity).
    private func applyLocaleFollowIfNeeded() {
        guard AlphabetFollow.followsLocale,
              let suggested = AlphabetIndex.suggestForLocale(dataDir: dataPath, localeTag: Locale.current.identifier),
              suggested.id != bridge.alphabetId else { return }
        bridge.setAlphabetId(suggested.id)
        bridge.saveSettings()
    }

    /// RFC 0018: false until the background engine bootstrap completes —
    /// drives the canvas loading overlay.
    @Published private(set) var isEngineReady = false

    private let dataPath: String

    /// Buffered like the iOS app: pre-bootstrap sizes no-op at the engine and
    /// are re-applied as the real first realize (portrait first-run fix).
    private var pendingCanvasSize: CGSize?

    func setCanvasSize(_ size: CGSize) {
        pendingCanvasSize = size
        bridge.setScreenSize(width: Int(size.width), height: Int(size.height))
    }

    func handlePointerHover(at point: CGPoint) {
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    /// Continuous-selection model (ported from DasherApp/Sources/DasherViewModel.swift).
    /// When selection == .continuous, looking at the canvas engages the zoom
    /// and looking away pauses it — no pinch required.
    var isContinuousSelection: Bool {
        selectionMethod == .continuous
    }

    /// Called by UIHoverGestureRecognizer .began when continuous selection is on.
    func handleHoverDown(at point: CGPoint) {
        bridge.mouseDown()
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
        os_log("GAZE: hoverDown (mouseDown) at %{public}f, %{public}f", log: visionLog, point.x, point.y)
    }

    /// Called by UIHoverGestureRecognizer .ended/.cancelled when continuous selection is on.
    func handleHoverUp() {
        bridge.mouseUp()
        os_log("GAZE: hoverUp (mouseUp)", log: visionLog)
    }

    /// Persist the current selection method to AccessConfiguration so it survives
    /// relaunches and so `AccessConfiguration.current.selection` stays in sync.
    func setSelectionMethod(_ method: SelectionMethod) {
        selectionMethod = method
        var config = AccessConfiguration.current
        config.selection = method
        AccessConfiguration.current = config
        config.apply(to: bridge)
    }

    /// Reset all engine params to visionOS defaults. Useful when old persisted
    /// settings are causing unexpected behaviour.
    func resetToDefaults() {
        AlphabetFollow.followsLocale = true // reset re-enables locale-follow (RFC 0003)
        // Clear persisted settings
        let userDir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedDefaults.groupIdentifier
        )?.path ?? ""
        try? FileManager.default.removeItem(atPath: userDir + "/dasher_settings.xml")
        try? FileManager.default.removeItem(atPath: userDir + "/appearance_settings.xml")

        // Re-apply visionOS defaults
        configureForEyeGaze()

        // Reset view state
        isPlaying = true
        speed = 1.0
        pointerHoverEnabled = true
        appLevelDwell = false
        selectionMethod = .continuous
        debugInputOverlay = true
        outputText = ""
        bridge.reset()

        os_log("RESET: All settings cleared and visionOS defaults applied", log: visionLog)
    }

    func handleTouch(at point: CGPoint) {
        bridge.mouseDown()
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
        os_log("TOUCH: began (mouseDown) at %{public}f, %{public}f", log: visionLog, point.x, point.y)
    }

    func handleTouchMove(at point: CGPoint) {
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
        // Log every ~30th move to avoid log spam but still confirm flow
        touchMoveLogCounter += 1
        if touchMoveLogCounter % 30 == 0 {
            os_log("TOUCH: moved (mouseMove) at %{public}f, %{public}f [count=%{public}d]", log: visionLog, point.x, point.y, touchMoveLogCounter)
        }
    }

    func handleTouchEnd() {
        bridge.mouseUp()
        os_log("TOUCH: ended (mouseUp) [moves=%{public}d]", log: visionLog, touchMoveLogCounter)
        touchMoveLogCounter = 0
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
        let newSpeed = min(bridge.speedPercent + 10, DasherBridge.speedRangePercent.upperBound)
        bridge.setSpeedPercent(newSpeed)
        speed = Double(newSpeed) / 100.0
    }

    func decreaseSpeed() {
        let newSpeed = max(bridge.speedPercent - 10, DasherBridge.speedRangePercent.lowerBound)
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
