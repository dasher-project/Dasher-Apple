import SwiftUI
import DasherShared
import DasherSpeech
import UniformTypeIdentifiers

@MainActor
class DasherViewModel: ObservableObject {
    @Published var outputText: String = ""
    @Published var editorSelection: NSRange = NSRange(location: 0, length: 0)
    /// RFC 0021 clause 4: active-end state machine anchor for editor-mode
    /// `Select` actions (resets when the user manually moves the caret/selection
    /// or edits text).
    var selectAnchorUTF16: Int?

    // MARK: - RFC 0019: Editor contract
    // The UITextView Coordinator owns the sync directly (no intermediate
    // @Published properties — those fought SwiftUI's render cycle). The
    // Coordinator calls bridge.seedBuffer / bridge.setOffset directly.

    /// Engine-origin text push: update outputText (for toolbar bindings)
    /// without re-seeding. The text view updates on the next SwiftUI render.
    /// RFC 0019 clause 7: when the pane exceeds the seed cap, the pane keeps
    /// the full text and the engine keeps the window — don't overwrite the
    /// pane with the truncated engine buffer.
    func pushEngineText(_ text: String, insertedUTF16: Int = 0, deletedUTF16: Int = 0) {
        let oldLen = outputText.utf16.count
        if oldLen > EditorSeedPolicy.maxUTF16Units {
            // Over-cap: engine sends the windowed text; the pane is longer.
            // Only update if the engine is genuinely ahead of us (new chars).
            let engineLen = text.utf16.count
            if engineLen > oldLen {
                // Engine grew (model expanded the window): accept but keep tail.
                // This is rare (the window shifts as we type) — just accept it.
                outputText = text
            }
            // Otherwise: engine sent the same windowed view — pane is authoritative.
        } else {
            outputText = text
        }
        let newLen = outputText.utf16.count
        let priorCaret = selectAnchorUTF16 ?? (editorSelection.location + editorSelection.length)
        let newCaret: Int
        if priorCaret >= oldLen {
            newCaret = newLen
        } else if insertedUTF16 > 0 {
            newCaret = min(newLen, priorCaret + insertedUTF16)
        } else if deletedUTF16 > 0 {
            newCaret = min(newLen, max(0, priorCaret - deletedUTF16))
        } else {
            newCaret = min(priorCaret, newLen)
        }
        selectAnchorUTF16 = nil
        editorSelection = NSRange(location: newCaret, length: 0)
    }
    @Published var isPlaying: Bool = true
    @Published var isGameModeActive: Bool = false
    @Published var isControlModeActive: Bool = false
    /// RFC 0018: false until the background engine bootstrap (create, locale,
    /// realize) completes — drives the canvas loading overlay.
    @Published private(set) var isEngineReady = false
    /// Set when dasher_create failed — the overlay shows an error state and
    /// the canvas never appears dead (audit #5).
    @Published private(set) var engineErrorMessage: String?

    private let dataPath: String
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
        self.dataPath = dataPath
        let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedDefaults.groupIdentifier
        )
        self.bridge = DasherBridge(dataDir: dataPath, userDir: sharedURL?.path)
        bridge.onOutput = { [weak self] text in
            // Engine produced text — push to the editor pane (NOT from draw()).
            self?.pushEngineText(self?.bridge.getOutputText() ?? "", insertedUTF16: text.utf16.count)
        }

        bridge.onDelete = { [weak self] text in
            self?.pushEngineText(self?.bridge.getOutputText() ?? "", deletedUTF16: text.utf16.count)
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
        bridge.onCustomAction = { [weak self] name, attrs in
            self?.handleCustomAction(name: name, attrs: attrs)
        }
        let savedConfig = AccessConfiguration.current

        let bitrateKey = bridge.findParameterKey("LP_MAX_BITRATE")
        let controlModeKey = bridge.findParameterKey("BP_CONTROL_MODE")
        bridge.onParameterChange = { [weak self] key in
            if key == bitrateKey {
                Task { @MainActor in
                    self?.speed = Double(self?.bridge.speedPercent ?? 100) / 100.0
                }
            } else if key == controlModeKey {
                Task { @MainActor in
                    guard let self else { return }
                    self.isControlModeActive = self.bridge.getBoolParameter(key: controlModeKey)
                }
            }
        }

        // RFC 0018 two-phase start (Dasher-Android pattern): the engine is
        // created + realized on a background task so the first canvas frame
        // never blocks; configuration that needs a live engine runs when it
        // completes and the UI swaps the loading state out.
        Task { [weak self] in
            await bridge.bootstrap()
            guard let self else { return }
            if let err = bridge.lastError {
                self.engineErrorMessage = err
                return
            }
            if let size = self.pendingCanvasSize {
                await bridge.realize(screenWidth: Int(size.width), screenHeight: Int(size.height))
            }
            savedConfig.apply(to: self.bridge)
            #if os(iOS)
            if savedConfig.method == .tilt {
                self.tiltService.activate(bridge: self.bridge)
            }
            #endif
            self.speed = Double(self.bridge.speedPercent) / 100.0
            self.isControlModeActive = self.bridge.getBoolParameter(key: controlModeKey)
            self.applyLocaleFollowIfNeeded()
            self.isEngineReady = true
        }
    }

    /// RFC 0003 locale-follow (Dasher-Android #31 parity): until the user
    /// explicitly picks an alphabet, follow the device locale. Runs after the
    /// first realize; the suggested alphabet lands via a normal ChangeAlphabet.
    private func applyLocaleFollowIfNeeded() {
        guard AlphabetFollow.followsLocale,
              let suggested = AlphabetIndex.suggestForLocale(dataDir: dataPath, localeTag: Locale.current.identifier),
              suggested.id != bridge.alphabetId else { return }
        bridge.setAlphabetId(suggested.id)
        bridge.saveSettings()
    }

    /// Last canvas size reported by layout. Pre-bootstrap the forward to the
    /// engine no-ops (ctx guard), so it is buffered and re-applied as the real
    /// first realize once the engine is ready — otherwise the engine stays at
    /// the bootstrap's 800×600 default and a portrait canvas draws off-layout
    /// until a rotation happens to fire layout again (first-run bug report).
    private var pendingCanvasSize: CGSize?

    func setCanvasSize(_ size: CGSize) {
        pendingCanvasSize = size
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
        selectAnchorUTF16 = nil
        editorSelection = NSRange(location: 0, length: 0)
        lastSpokenText = ""
        resetTypingStats()
    }

    func openText(_ text: String) {
        bridge.reset()
        let newLen = text.utf16.count
        outputText = text
        selectAnchorUTF16 = nil
        editorSelection = NSRange(location: newLen, length: 0)
        lastSpokenText = ""
        let (windowed, windowedCaret) = EditorSeedPolicy.apply(to: text, caretUTF16: newLen)
        let byteOffset = bridge.byteOffsetFromUTF16(windowed, utf16Offset: windowedCaret)
        bridge.seedBuffer(windowed, caretOffset: byteOffset)
    }

    // MARK: - Editing keys strip (editor mode)

    func editorInsert(_ inserted: String) {
        guard !inserted.isEmpty else { return }
        let start = editorSelection.location
        let end = editorSelection.location + editorSelection.length
        let (newText, newCaret) = EditorKeyActions.insert(
            text: inserted,
            into: outputText,
            selectionStart: start,
            selectionEnd: end
        )
        outputText = newText
        selectAnchorUTF16 = nil
        editorSelection = NSRange(location: newCaret, length: 0)
        let (windowed, windowedCaret) = EditorSeedPolicy.apply(to: newText, caretUTF16: newCaret)
        let byteOffset = bridge.byteOffsetFromUTF16(windowed, utf16Offset: windowedCaret)
        bridge.seedBuffer(windowed, caretOffset: byteOffset)
    }

    func editorBackspace() {
        let start = editorSelection.location
        let end = editorSelection.location + editorSelection.length
        let (newText, newCaret) = EditorKeyActions.backspace(
            text: outputText,
            selectionStart: start,
            selectionEnd: end
        )
        guard newText != outputText || editorSelection.length > 0 else { return }
        outputText = newText
        selectAnchorUTF16 = nil
        editorSelection = NSRange(location: newCaret, length: 0)
        let (windowed, windowedCaret) = EditorSeedPolicy.apply(to: newText, caretUTF16: newCaret)
        let byteOffset = bridge.byteOffsetFromUTF16(windowed, utf16Offset: windowedCaret)
        bridge.seedBuffer(windowed, caretOffset: byteOffset)
    }

    func editorMoveCaret(delta: Int) {
        let start = editorSelection.location
        let end = editorSelection.location + editorSelection.length
        let newCaret = EditorKeyActions.moveCaret(
            text: outputText,
            selectionStart: start,
            selectionEnd: end,
            delta: delta
        )
        guard newCaret != editorSelection.location || editorSelection.length > 0 else { return }
        selectAnchorUTF16 = nil
        editorSelection = NSRange(location: newCaret, length: 0)
        let (windowed, windowedCaret) = EditorSeedPolicy.apply(to: outputText, caretUTF16: newCaret)
        let byteOffset = bridge.byteOffsetFromUTF16(windowed, utf16Offset: windowedCaret)
        bridge.setOffset(byteOffset)
    }

    // MARK: - RFC 0021: Control-mode Select dispatch

    func handleCustomAction(name: String, attrs: [String: String]) {
        guard name == "select", !isGameModeActive else { return }
        guard let (dist, dir) = SelectActions.parse(dist: attrs["dist"], forward: attrs["forward"]) else {
            return
        }

        let start = editorSelection.location
        let end = editorSelection.location + editorSelection.length
        let bounds = SelectActions.editorBounds(
            text: outputText,
            selectionStart: start,
            selectionEnd: end,
            dist: dist,
            dir: dir,
            hadSelection: editorSelection.length > 0,
            anchorUTF16: selectAnchorUTF16
        )
        selectAnchorUTF16 = (bounds.start == bounds.end) ? nil : bounds.anchorUTF16
        editorSelection = NSRange(location: bounds.start, length: max(0, bounds.end - bounds.start))
        let stateStr = "dist=\(dist.rawValue),forward=\(dir == .forward ? "yes" : "no")"
        UITelemetry.action("control_tree", "select", state: stateStr)
    }

    var shareText: String {
        outputText
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
