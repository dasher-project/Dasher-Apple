import SwiftUI
import DasherShared
import DasherSpeech
import UniformTypeIdentifiers

@MainActor
class MacDasherViewModel: ObservableObject {
    @Published var outputText: String = ""
    @Published var isPlaying: Bool = true
    @Published var isGameModeActive: Bool = false
    @Published var isControlModeActive: Bool = false
    @Published var gameTargetText: String = ""
    @Published var gameCorrectCount: Int = 0
    @Published var gameTargetLength: Int = 0
    @Published var gameWrongText: String = ""
    @Published var gamePhrasesCompleted: Int = 0
    @Published var typingWPM: Double = 0
    @Published var typingCPS: Double = 0
    @AppStorage("showTypingRate") public var showTypingRate = false
    @Published var typingWPMMax: Double = 0
    private var typingWPMSum: Double = 0
    private var typingWPMCount: Int = 0
    var typingWPMAvg: Double { typingWPMCount > 0 ? typingWPMSum / Double(typingWPMCount) : 0 }
    func resetTypingStats() { typingWPMMax = 0; typingWPMSum = 0; typingWPMCount = 0 }
    @Published var pendingMessage: (isWarning: Bool, text: String)?
    @Published var speed: Double = 1.0
    @Published var autoSpeed: Bool = false
    @Published var showMessagePane: Bool = true
    @Published var selectedColourIndex: Int = 0
    @Published var showShareSheet = false
    @Published var showOpenFile = false
    @Published var outputMode: OutputMode = .right {
        didSet {
            directMode = (outputMode == .direct)
            showMessagePane = (outputMode != .direct)
        }
    }
    @Published var directMode: Bool = false {
        didSet { updateDirectMode() }
    }
    @Published var directOpacity: Double = 0.75

    let bridge: DasherBridge
    let directService = DirectModeService()
    let speech = SpeechService.shared

    var v5MigrationScan = V5MigrationResult()
    init() {
        let dataPath = Bundle.main.path(forResource: "Data", ofType: nil) ?? ""
        let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedDefaults.groupIdentifier
        )
        let userDir = sharedURL?.path ?? dataPath
        self.dataPath = dataPath
        self.bridge = DasherBridge(dataDir: dataPath, userDir: userDir)

        // Store bridge reference for migration
        MigrationBridgeHolder.shared.bridge = bridge
        MigrationBridgeHolder.shared.userDir = userDir

        // Scan for v5 data (don't import yet — wait for user choice)
        if !V5MigrationService.hasBeenOffered {
            v5MigrationScan = V5MigrationService.scan()
        }

        // Wire callbacks before engine starts
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

        bridge.onOutput = { [weak self] text in
            guard let self else { return }
            if self.directMode {
                self.directService.injectText(text)
            }
            self.outputText = self.bridge.getOutputText()
        }

        bridge.onDelete = { [weak self] text in
            guard let self else { return }
            if self.directMode {
                self.directService.injectDelete(count: text.count)
            }
            self.outputText = self.bridge.getOutputText()
        }

        bridge.onSpeak = { [weak self] text, interrupt in
            Task { @MainActor in
                if interrupt {
                    self?.speech.stop()
                }
                self?.speech.phonemeMode = self?.bridge.alphabetId.contains("X-SAMPA") ?? false
                self?.speech.speak(text)
            }
        }
        bridge.onClipboard = { text in
            Task { @MainActor in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }

        let savedConfig = AccessConfiguration.current

        let bitrateKey = bridge.findParameterKey("LP_MAX_BITRATE")
        bridge.onParameterChange = { [weak self] key in
            guard key == bitrateKey else { return }
            Task { @MainActor in
                self?.speed = Double(self?.bridge.speedPercent ?? 100) / 100.0
            }
        }
        // RFC 0018 two-phase start: engine create + locale on a background
        // task (the first realize is deferred to startEngine below — the v5
        // migration must be able to set parameters first). apply(to:) also
        // needs a live engine, so it runs post-boot.
        Task { [weak self] in
            await bridge.bootstrap(realizeDefaultScreen: false)
            guard let self else { return }
            savedConfig.apply(to: self.bridge)
            self.speed = Double(self.bridge.speedPercent) / 100.0
        }
    }

    /// RFC 0003 locale-follow (Dasher-Android #31 parity): until the user
    /// explicitly picks an alphabet, follow the device locale.
    func applyLocaleFollowIfNeeded() {
        guard AlphabetFollow.followsLocale,
              let suggested = AlphabetIndex.suggestForLocale(dataDir: dataPath, localeTag: Locale.current.identifier),
              suggested.id != bridge.alphabetId else { return }
        bridge.setAlphabetId(suggested.id)
        bridge.saveSettings()
    }

    /// RFC 0018: false until the first realize completes — drives the canvas
    /// loading overlay.
    @Published private(set) var isEngineReady = false
    /// Set when dasher_create failed (audit #5) — overlay shows an error.
    @Published private(set) var engineErrorMessage: String?

    private let dataPath: String

    private var engineStarted = false

    /// Migration deferred parameters to apply after engine starts.
    var v5DeferredParams: [(key: Int, value: String)] = []

    /// Starts the Dasher engine. Call this after any v5 migration has completed.
    /// Await engine creation (idempotent — safe alongside the init boot Task).
    /// Flows that write parameters from UI timing (the v5 migration import)
    /// must call this first: writes landing before dasher_create finishes
    /// silently no-op at the bridge's ctx guard and would be lost (audit #2).
    func waitForEngine() async {
        await bridge.bootstrap(realizeDefaultScreen: false)
    }

    func startEngine(width: Int = 900, height: Int = 600) {
        engineStarted = true
        // RFC 0018 + audit #1/#3: serialize on bootstrap before realizing —
        // startEngine fires from onAppear and can beat the detached create,
        // in which case realize() no-ops and the engine stays unrealized
        // forever. Deferred migration parameters apply AFTER the first
        // realize: the engine's first set_screen_size forces
        // SP_INPUT_FILTER="Normal Control" (CAPI), clobbering a pre-realize
        // filter write — the historical order was realize-then-apply. The
        // pending canvas size (if layout already ran) becomes the realize
        // size directly instead of a second setScreenSize pass.
        Task { [weak self] in
            await bridge.bootstrap(realizeDefaultScreen: false)
            let target = self?.pendingCanvasSize
                .map { (Int($0.width), Int($0.height)) } ?? (width, height)
            await bridge.realize(screenWidth: target.0, screenHeight: target.1)
            guard let self else { return }
            if let err = bridge.lastError {
                self.engineErrorMessage = err
                return
            }
            if !self.v5DeferredParams.isEmpty {
                V5MigrationService.applyDeferredParameters(self.v5DeferredParams, bridge: self.bridge)
                self.v5DeferredParams = []
            }
            self.applyLocaleFollowIfNeeded()
            self.isEngineReady = true
        }
    }

    private func updateDirectMode() {
        if directMode {
            directService.startPolling()
            directService.startWatching()
        } else {
            directService.stopPolling()
            directService.stopWatching()
        }
    }

    /// Buffered: canvas layout can precede startEngine (migration prompt), in
    /// which case the forward no-ops — re-apply after the first realize.
    private var pendingCanvasSize: CGSize?

    func setCanvasSize(_ size: CGSize) {
        pendingCanvasSize = size
        guard engineStarted else { return }
        bridge.setScreenSize(width: Int(size.width), height: Int(size.height))
    }

    func handleTouch(at point: CGPoint) {
        guard isPlaying else { return }
        bridge.mouseDown()
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
            if !active { gamePhrasesCompleted = 0 }
        }
        typingWPM = bridge.getWPM()
        typingCPS = bridge.getCPS()
        if typingWPM > 0 {
            typingWPMMax = max(typingWPMMax, typingWPM)
            typingWPMSum += typingWPM
            typingWPMCount += 1
        }
        if active {
            let newTarget = bridge.getGameTargetText()
            if newTarget != gameTargetText && !gameTargetText.isEmpty && !newTarget.isEmpty {
                gamePhrasesCompleted += 1
            }
            gameTargetText = newTarget
            gameCorrectCount = max(0, bridge.getGameCorrectCount())
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
        resetTypingStats()
    }

    func openText(_ text: String) {
        bridge.reset()
        outputText = text
    }

    var shareText: String {
        outputText
    }

    func saveText(to url: URL) {
        try? outputText.write(to: url, atomically: true, encoding: .utf8)
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

    let colourPresets: [(String, Color)] = [
        ("1", Color(red: 0.96, green: 0.86, blue: 0.30)),
        ("2", Color(red: 1.0, green: 0.82, blue: 0.40)),
        ("3", Color(red: 0.95, green: 0.91, blue: 0.35)),
    ]

    func stopSpeech() {
        speech.stop()
    }
}

enum OutputMode: String, CaseIterable {
    case right = "Right side"
    case left = "Left side"
    case bottom = "Bottom"
    case top = "Top"
    case direct = "Direct Mode"

    var icon: String {
        switch self {
        case .right: return "sidebar.right"
        case .left: return "sidebar.left"
        case .bottom: return "rectangle.split.1x2"
        case .top: return "rectangle.split.1x2"
        case .direct: return "keyboard"
        }
    }
}
