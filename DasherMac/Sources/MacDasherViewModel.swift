import SwiftUI
import DasherShared
import DasherSpeech
import UniformTypeIdentifiers

@MainActor
class MacDasherViewModel: ObservableObject {
    @Published var outputText: String = ""
    @Published var editorSelection: NSRange = NSRange(location: 0, length: 0)
    /// RFC 0021 clause 4: active-end state machine anchor for editor-mode
    /// `Select` actions (resets when the user manually moves the caret/selection
    /// or edits text).
    var selectAnchorUTF16: Int?

    // MARK: - RFC 0019: Editor contract
    // The NSTextView Coordinator owns the sync directly.
    // RFC 0019 clause 7: when over the seed cap, the pane keeps the full
    // text — don't overwrite with the engine's truncated window buffer.
    func pushEngineText(_ text: String, insertedUTF16: Int = 0, deletedUTF16: Int = 0) {
        let oldLen = outputText.utf16.count
        if oldLen > EditorSeedPolicy.maxUTF16Units {
            if text.utf16.count > oldLen {
                outputText = text
            }
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
        let userDir = TrainingDataManager.resolveUserDirectory(
            explicitUserDir: sharedURL?.path,
            fallbackDataDir: dataPath
        )
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
                // Active output supersedes any pending debounced target context seed.
                self.contextSeedGeneration &+= 1
                self.contextSeedTask?.cancel()
                self.directService.injectText(text)
            }
            self.pushEngineText(self.bridge.getOutputText(), insertedUTF16: text.utf16.count)
        }

        bridge.onDelete = { [weak self] text in
            guard let self else { return }
            if self.directMode {
                self.contextSeedGeneration &+= 1
                self.contextSeedTask?.cancel()
                // RFC 0015 Clause 5: delete one key press per Unicode scalar
                // (not grapheme cluster), matching macOS target Backspace behaviour.
                self.directService.injectDelete(count: text.unicodeScalars.count)
            }
            self.pushEngineText(self.bridge.getOutputText(), deletedUTF16: text.utf16.count)
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
        // RFC 0018 two-phase start: engine create + locale on a background
        // task (the first realize is deferred to startEngine below — the v5
        // migration must be able to set parameters first). apply(to:) also
        // needs a live engine, so it runs post-boot.
        Task { [weak self] in
            await bridge.bootstrap(realizeDefaultScreen: false)
            guard let self else { return }
            savedConfig.apply(to: self.bridge)
            self.speed = Double(self.bridge.speedPercent) / 100.0
            self.isControlModeActive = self.bridge.getBoolParameter(key: controlModeKey)
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

    private var contextSeedGeneration: Int = 0
    private var contextSeedTask: Task<Void, Never>?

    private func updateDirectMode() {
        LogManager.kb("directMode=\(directMode)")
        if directMode {
            directService.onTargetCaretChanged = { [weak self] reason in
                self?.scheduleContextSeed(reason: reason)
            }
            directService.startPolling()
            directService.startWatching()
        } else {
            contextSeedGeneration &+= 1
            contextSeedTask?.cancel()
            contextSeedTask = nil
            directService.onTargetCaretChanged = nil
            directService.stopPolling()
            directService.stopWatching()
        }
    }

    func manualReanchor() {
        guard directMode else { return }
        LogManager.kb("manual re-anchor requested")
        scheduleContextSeed(reason: "manual re-anchor")
    }

    /// RFC 0015 (Amended) / RFC 0019 clause 6: debounced sentence-window context
    /// seeding from the target application's focused text field.
    ///
    /// Mirrors `Dasher-Windows` `SeedContextFromTargetAsync`:
    /// - 500 ms debounce (`contextSeedGeneration`) so rapid focus/caret churn
    ///   coalesces and continuous typing (which increments `contextSeedGeneration`
    ///   on every output/delete) never resets the canvas mid-word.
    /// - 1500 ms paragraph/select settle guard for `"caret moved"` triggers.
    /// - Caret-glitch guard (`caretUTF16 < 3 && text.utf16.count > 10`) for `"caret moved"`.
    /// - Read-failure preservation (keeps existing engine context on AX failure).
    /// - `ContextSeedPolicy.decide` shadow-compare over trimmed 200-char sentence windows.
    private func scheduleContextSeed(reason: String) {
        guard directMode else { return }
        contextSeedGeneration &+= 1
        let generation = contextSeedGeneration
        contextSeedTask?.cancel()
        contextSeedTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self, self.directMode, self.contextSeedGeneration == generation else {
                return
            }
            await self.seedContextFromTarget(reason: reason, generation: generation)
        }
    }

    private func seedContextFromTarget(reason: String, generation: Int) async {
        guard directMode, contextSeedGeneration == generation else { return }

        // 600 ms own-injection echo guard & 1500 ms paragraph/select settle guard (Windows #58/#79 / RFC 0021)
        let ownInjectEchoMs = 600
        let paragraphSettleMs = 1500
        if reason == "caret moved" {
            if let elapsedMs = directService.msSinceLastOwnInject,
               elapsedMs < ownInjectEchoMs {
                LogManager.kb("Context seed (\(reason)): own-inject echo window (\(elapsedMs)ms since our inject) — skipping")
                return
            }
            if let elapsedMs = directService.msSinceLastOwnParagraphOrSelectInject,
               elapsedMs < paragraphSettleMs {
                LogManager.kb("Context seed (\(reason)): paragraph/select settle window (\(elapsedMs)ms since our inject) — skipping")
                return
            }
        }

        guard let context = await directService.readTargetFieldContext() else {
            // Read failed (timeout, unsupported control, no focus): preserve
            // existing engine session context (RFC 0015 Tier 1).
            LogManager.kb("Context seed (\(reason)): read failed -> keeping existing context")
            return
        }
        guard !Task.isCancelled, contextSeedGeneration == generation else { return }

        let fullText = context.text
        let caretUTF16 = context.caretUTF16
        let totalUTF16 = fullText.utf16.count

        // Caret-glitch guard: target apps can momentarily report caret 0..2
        // during rapid text transitions in a longer field.
        if context.inputMethodSelection == nil && reason == "caret moved" && caretUTF16 < 3 && totalUTF16 > 10 {
            LogManager.kb("Context seed (\(reason)): caret glitch (pos \(caretUTF16) in \(totalUTF16)-char text) — skipping")
            return
        }

        let engineFullText = bridge.getOutputText()
        let decision: ContextSeedDecision
        if context.inputMethodSelection != nil {
            let sentence = ContextSeedPolicy.normalizeInvisible(SentenceWindow.trim(fullText, caretUTF16: caretUTF16).text)
            let engineSentence = ContextSeedPolicy.normalizeInvisible(
                SentenceWindow.trim(engineFullText, caretUTF16: engineFullText.utf16.count).text
            )
            // A shorter prefix can be a real caret move or editor-side deletion.
            decision = sentence == engineSentence
                ? .skip("sentence unchanged")
                : .seed(sentence, caretUTF16: sentence.utf16.count)
        } else {
            decision = ContextSeedPolicy.decide(
                engineFullText: engineFullText,
                targetFullText: fullText,
                targetCaretUTF16: caretUTF16
            )
        }

        if decision.action == .skip {
            LogManager.kb("Context seed (\(reason)): \(decision.reason)")
            return
        }

        let caretBytes = bridge.byteOffsetFromUTF16(decision.text, utf16Offset: decision.caretUTF16)
        // Log lengths only — never log private target text content.
        LogManager.kb("Context seed (\(reason)): \(decision.text.utf16.count) of \(totalUTF16) utf16, caret u16=\(decision.caretUTF16) -> byte=\(caretBytes)")
        bridge.seedBuffer(decision.text, caretOffset: caretBytes)
    }

    /// Buffered: canvas layout can precede startEngine (migration prompt), in
    /// which case the forward no-ops — re-apply after the first realize.
    private var pendingCanvasSize: CGSize?

    func setCanvasSize(_ size: CGSize) {
        pendingCanvasSize = size
        guard engineStarted else { return }
        bridge.setScreenSize(width: Int(size.width), height: Int(size.height))
    }

    /// Button-down: the primary-input edge (start/stop toggle per
    /// BP_START_MOUSE) plus one position sample.
    func handleTouch(at point: CGPoint) {
        guard isPlaying else { return }
        bridge.mouseDown()
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    /// Pointer motion without a button — the continuous-steering path.
    /// Hover-only movement must reach the engine so a head mouse can drive
    /// Dasher by pointing alone; never sends the mouse-down edge here
    /// (re-sending it per sample re-triggered the BP_START_MOUSE toggle).
    func handleMove(at point: CGPoint) {
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
        resetTypingStats()
    }

    func openText(_ text: String) {
        bridge.reset()
        let newLen = text.utf16.count
        outputText = text
        selectAnchorUTF16 = nil
        editorSelection = NSRange(location: newLen, length: 0)
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
        guard !isGameModeActive else { return }
        if name == "move" || name == "delete" {
            handleMoveDelete(name: name, attrs: attrs)
            return
        }
        guard name == "select" else { return }
        guard let (dist, dir) = SelectActions.parse(dist: attrs["dist"], forward: attrs["forward"]) else {
            LogManager.kb("select: unknown attributes dist=\(attrs["dist"] ?? "(nil)") forward=\(attrs["forward"] ?? "(nil)") - no-op")
            return
        }

        let stateStr = "dist=\(dist.rawValue),forward=\(dir == .forward ? "yes" : "no")"
        if directMode {
            let ks = SelectActions.keystroke(dist: dist, dir: dir)
            directService.sendSelectChord(ks)
            UITelemetry.action("control_tree", "select", state: stateStr)
        } else {
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
            UITelemetry.action("control_tree", "select", state: stateStr)
        }
    }

    /// RFC 0021 amendment (engine v0.2.28): Move/Delete ride the
    /// registered-action surface. Direct mode sends native movement/deletion
    /// keystrokes to the target app; editor mode applies measured UTF-16
    /// caret moves / deletion ranges to the output pane (and re-seeds).
    private func handleMoveDelete(name: String, attrs: [String: String]) {
        guard let (dist, dir) = MoveDeleteActions.parse(dist: attrs["dist"], forward: attrs["forward"]) else {
            LogManager.kb("\(name): unknown attributes dist=\(attrs["dist"] ?? "(nil)") forward=\(attrs["forward"] ?? "(nil)") - no-op")
            return
        }
        let stateStr = "dist=\(dist.rawValue),forward=\(dir == .forward ? "yes" : "no")"

        if directMode {
            // Native-keystroke fidelity: sentence/paragraph deletes fall back
            // to word/line chords on macOS — tag the applied granularity so
            // field data never reads sentence-accurate when it was not
            // (mirrors Dasher-Windows #92's fallback= telemetry).
            var applied = stateStr
            if name == "delete" {
                if dist == .sentence { applied += ",fallback=word" }
                if dist == .paragraph { applied += ",fallback=line" }
            }
            if dist == .all, name == "delete" {
                // Composite: select-all (Cmd+A) then Delete — the select
                // keystroke helper exists precisely for this.
                directService.sendSelectChord(SelectActions.keystroke(dist: .all, dir: .backward))
                if let chord = MoveDeleteActions.deleteKeystroke(dist: .char, dir: .backward) {
                    directService.sendSelectChord(chord)
                }
            } else if name == "move" {
                directService.sendSelectChord(MoveDeleteActions.moveKeystroke(dist: dist, dir: dir))
            } else if let chord = MoveDeleteActions.deleteKeystroke(dist: dist, dir: dir) {
                directService.sendSelectChord(chord)
            }
            UITelemetry.action("control_tree", name, state: applied)
            return
        }

        switch name {
        case "move":
            let caret = MoveDeleteActions.moveCaret(
                text: outputText, caret: editorSelection.location, dist: dist, dir: dir)
            guard caret != editorSelection.location || editorSelection.length > 0 else { return }
            selectAnchorUTF16 = nil
            editorSelection = NSRange(location: caret, length: 0)
            let (windowed, windowedCaret) = EditorSeedPolicy.apply(to: outputText, caretUTF16: caret)
            let byteOffset = bridge.byteOffsetFromUTF16(windowed, utf16Offset: windowedCaret)
            bridge.setOffset(byteOffset)
            UITelemetry.action("control_tree", "move", state: stateStr)
        case "delete":
            let (newText, newCaret) = MoveDeleteActions.deleteRange(
                text: outputText, caret: editorSelection.location, dist: dist, dir: dir)
            guard newText != outputText else { return }
            outputText = newText
            selectAnchorUTF16 = nil
            editorSelection = NSRange(location: newCaret, length: 0)
            let (windowed, windowedCaret) = EditorSeedPolicy.apply(to: newText, caretUTF16: newCaret)
            let byteOffset = bridge.byteOffsetFromUTF16(windowed, utf16Offset: windowedCaret)
            // Text changed: the edit buffer must be replaced (setOffset only
            // moves the cursor and the deleted text would resurrect on the
            // next output) — RFC 0019 clause 4.
            bridge.seedBuffer(windowed, caretOffset: byteOffset)
            UITelemetry.action("control_tree", "delete", state: stateStr)
        default:
            break
        }
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
