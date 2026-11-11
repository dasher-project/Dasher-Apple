import Cocoa
import CoreGraphics
import DasherShared

@MainActor
class DirectModeService: ObservableObject {
    @Published var isActive = false
    @Published var hasAccessibilityPermission = false
    @Published var targetAppName: String = ""

    /// RFC 0019 clause 6 / RFC 0015: fires when the caret/selection, focused
    /// element, or target application changes. Carries the trigger reason
    /// (`"caret moved"`, `"focus changed"`, `"target changed"`).
    var onTargetCaretChanged: ((String) -> Void)?

    /// Self-injection echo suppression (Windows #58/#61): when Dasher types
    /// into the target, the AX caret watcher fires for our own injected text.
    /// The engine already knows — don't re-seed from our own output.
    private var echoSuppressionUntil = Date.distantPast

    /// Timestamp of our last own character/delete injection for the 600 ms
    /// echo settle check in `MacDasherViewModel.seedContextFromTarget`.
    private(set) var lastOwnInjectAt: Date?

    var msSinceLastOwnInject: Int? {
        guard let ts = lastOwnInjectAt else { return nil }
        let elapsed = Date().timeIntervalSince(ts) * 1000.0
        return max(0, Int(elapsed))
    }

    /// Timestamp of our last newline (`\n`) or selection-chord injection for
    /// the 1500 ms paragraph/selection settle guard (Windows #79 / RFC 0021).
    private(set) var lastOwnParagraphOrSelectInjectAt: Date?

    var msSinceLastOwnParagraphOrSelectInject: Int? {
        guard let ts = lastOwnParagraphOrSelectInjectAt else { return nil }
        let elapsed = Date().timeIntervalSince(ts) * 1000.0
        return max(0, Int(elapsed))
    }

    func suppressEchoes(for interval: TimeInterval = 0.3) {
        lastOwnInjectAt = Date()
        let candidate = Date().addingTimeInterval(interval)
        if candidate > echoSuppressionUntil {
            echoSuppressionUntil = candidate
        }
    }

    private var isEchoSuppressed: Bool {
        Date() < echoSuppressionUntil
    }

    private var frontmostObserver: Any?
    private var pollTimer: Timer?
    private var lastTargetApp: NSRunningApplication?

    // MARK: - RFC 0019: caret watcher (AXSelectedTextChanged)

    private var axObserver: AXObserver?
    private var watchedElement: AXUIElement?

    /// Cross-app AX notifications are best-effort: well-behaved NSTextView apps
    /// post kAXSelectedTextChanged on caret moves, but several major apps
    /// (BBEdit's custom text engine, Electron/Code editors) do not. While
    /// Windows gets guaranteed events from TSF, macOS has no equivalent — so
    /// Direct Mode pairs the observer with a low-frequency poll of the focused
    /// field, re-seeding only when the (text, caret) tuple actually changed.
    private var contextPollTimer: Timer?
    private let contextPollQueue = DispatchQueue(label: "at.dasher.directmode.context-poll", qos: .utility)
    private var lastPolledText: String?
    private var lastPolledLength: Int?
    private var lastPolledCaret: Int?
    private var loggedPollReadFailure = false
    private var isPollReadInFlight = false

    /// AXObserver-based caret watcher. NotificationCenter only delivers AX
    /// notifications for elements in our own process; cross-process watching
    /// requires AXObserverCreate(pid:) + per-element notification registration
    /// on the focused element, re-attached whenever focus moves.
    private func startCaretWatcher() {
        stopCaretWatcher()
        guard let pid = lastTargetApp?.processIdentifier else { return }

        let callback: AXObserverCallback = { observer, _, notification, refcon in
            guard let refcon else { return }
            let service = Unmanaged<DirectModeService>.fromOpaque(refcon).takeUnretainedValue()
            let notifName = notification as String
            DispatchQueue.main.async {
                guard let front = NSWorkspace.shared.frontmostApplication,
                      front.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
                if notifName == (kAXFocusedUIElementChangedNotification as String) {
                    if let pid = service.lastTargetApp?.processIdentifier {
                        service.registerCaretNotification(on: observer, pid: pid)
                    }
                    service.onTargetCaretChanged?("focus changed")
                } else {
                    guard !service.isEchoSuppressed else { return }
                    service.onTargetCaretChanged?("caret moved")
                }
            }
        }

        var observerRef: AXObserver?
        guard AXObserverCreate(pid, callback, &observerRef) == .success,
              let observer = observerRef else { return }
        axObserver = observer

        // Add the run-loop source so notifications are delivered
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        // Register on the focused element (re-attach when focus changes)
        registerCaretNotification(on: observer, pid: pid)
    }

    private func registerCaretNotification(on observer: AXObserver, pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        if let prev = watchedElement {
            AXObserverRemoveNotification(observer, prev, kAXSelectedTextChangedNotification as CFString)
            AXObserverRemoveNotification(observer, prev, kAXValueChangedNotification as CFString)
            watchedElement = nil
        }
        // Re-registration means focus moved (same app) or the target changed:
        // reset the poll baseline so a change carried over from the previous
        // field/target cannot be silently absorbed.
        lastPolledText = nil
        lastPolledLength = nil
        lastPolledCaret = nil

        // Watch focus changes on the app element — tabbing between text fields
        // within the same app fires this; re-register the caret notification
        // on the newly focused element so clause-6 survives field switches.
        AXObserverAddNotification(observer, app, kAXFocusedUIElementChangedNotification as CFString, refcon)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedCF = focusedRef,
              CFGetTypeID(focusedCF) == AXUIElementGetTypeID() else { return }
        let focused = unsafeBitCast(focusedCF, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(focused, 0.3)
        AXObserverAddNotification(observer, focused, kAXSelectedTextChangedNotification as CFString, refcon)
        // Text edits fire AXValueChanged even where selection notifications are
        // missing; both funnel into the same debounced re-seed pipeline.
        AXObserverAddNotification(observer, focused, kAXValueChangedNotification as CFString, refcon)
        watchedElement = focused
    }

    /// Echo / settle window predicates for the poller: changes Dasher itself
    /// just caused are absorbed silently (baseline updated, no re-seed) — the
    /// 600 ms seed-time guard alone cannot cover a 400 ms poll + 500 ms
    /// debounce pipeline.
    var isWithinOwnInjectEcho: Bool { (msSinceLastOwnInject ?? .max) < 600 }
    var isWithinOwnParagraphOrSelectSettle: Bool { (msSinceLastOwnParagraphOrSelectInject ?? .max) < 1500 }

    func startContextPolling() {
        stopContextPolling()
        // Baseline is unknown: the first successful poll sets it silently so
        // startup does not fire a spurious re-seed (the "target changed"
        // trigger already seeded once). Later diffs fire the normal pipeline.
        lastPolledText = nil
        lastPolledLength = nil
        lastPolledCaret = nil
        loggedPollReadFailure = false
        isPollReadInFlight = false
        contextPollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop; the hop makes MainActor
            // isolation explicit (matches startPolling's style).
            DispatchQueue.main.async { self?.pollTargetContext() }
        }
    }

    func stopContextPolling() {
        contextPollTimer?.invalidate()
        contextPollTimer = nil
        lastPolledText = nil
        lastPolledLength = nil
        lastPolledCaret = nil
        isPollReadInFlight = false
    }

    /// Main-thread half of the poll: resolve the read context, then run the
    /// AX IPC on the utility queue so a hung target (up to 0.3 s per AX call,
    /// RFC 0015's background-read budget) cannot stall the canvas.
    private func pollTargetContext() {
        guard isActive, !isPollReadInFlight,
              let appTarget = lastTargetApp, !appTarget.isTerminated else { return }
        let pid = appTarget.processIdentifier
        let prev = (text: lastPolledText, length: lastPolledLength, caret: lastPolledCaret)
        var frontPid: pid_t?
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            frontPid = front.processIdentifier
        }
        isPollReadInFlight = true
        contextPollQueue.async { [weak self] in
            guard let self else { return }
            let read = self.readFocusedField(pid: pid, frontPid: frontPid)
            DispatchQueue.main.async { self.finishContextPoll(read: read, snapshot: prev, pid: pid) }
        }
    }

    /// Main-thread completion. During Dasher's own echo/settle windows the
    /// tick is a pure no-op — the comparison baseline (the `snapshot`) is
    /// deliberately left STALE, so the first tick after the window compares
    /// against the pre-window state and fires exactly once:
    ///   - our own injected text differs from the baseline -> re-anchor (the
    ///     ContextSeedPolicy engine-ahead check skips when already in sync);
    ///   - a USER caret move during the window is caught by that same post-
    ///     window compare instead of being swallowed.
    private func finishContextPoll(read: (text: String, caretUTF16: Int, failure: String?)?, snapshot: (text: String?, length: Int?, caret: Int?), pid: pid_t) {
        isPollReadInFlight = false
        guard isActive, let appTarget = lastTargetApp, appTarget.processIdentifier == pid else { return }
        guard let read, read.failure == nil else {
            if !loggedPollReadFailure {
                loggedPollReadFailure = true
                LogManager.kb("  [AX] poll: focused field unreadable for pid=\(pid) — \(read?.failure ?? "unknown")")
            }
            return
        }
        loggedPollReadFailure = false

        if isEchoSuppressed || isWithinOwnInjectEcho || isWithinOwnParagraphOrSelectSettle {
            return   // no-op tick: baseline deliberately stays stale (see above)
        }

        let baselineKnown = (snapshot.text != nil)
        var changed = baselineKnown && (read.caretUTF16 != snapshot.caret || read.text.utf16.count != snapshot.length)
        if !changed, baselineKnown, let prev = snapshot.text {
            changed = (prev != read.text)   // same length + caret: content may still differ (1:1 replace)
        }
        lastPolledText = read.text
        lastPolledLength = read.text.utf16.count
        lastPolledCaret = read.caretUTF16

        if changed {
            LogManager.kb("  [AX] poll detected caret/context change (utf16=\(read.text.utf16.count), caret16=\(read.caretUTF16))")
            onTargetCaretChanged?("caret moved")
        }
    }

    private func stopCaretWatcher() {
        if let observer = axObserver {
            if let prev = watchedElement {
                AXObserverRemoveNotification(observer, prev, kAXSelectedTextChangedNotification as CFString)
                AXObserverRemoveNotification(observer, prev, kAXValueChangedNotification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            axObserver = nil
        }
        watchedElement = nil
    }

    /// Reads the focused text field's content + caret via AX, for engine
    /// re-seeding (RFC 0019 clause 6 / RFC 0015 tier 3). Main-thread wrapper:
    /// resolves the target/front pids, then delegates to the pure
    /// `readFocusedField` (which the context poller also runs on the
    /// utility queue). A 300 ms timeout on the AX messages prevents an
    /// unresponsive target from stalling the caller (Windows' hard budget, PR #52).
    func readTargetFieldContext(logging: Bool = true) -> (text: String, caretUTF16: Int)? {
        guard hasAccessibilityPermission,
              let appTarget = lastTargetApp,
              !appTarget.isTerminated else { return nil }
        let pid = appTarget.processIdentifier

        // Stale-target guard: if another non-Dasher app has become frontmost
        // mid-debounce, do not read from a backgrounded window.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier,
           front.processIdentifier != pid {
            if logging { LogManager.kb("  [AX] skipping read: target pid=\(pid) is not frontmost (front=\(front.processIdentifier))") }
            return nil
        }

        let read = readFocusedField(pid: pid, frontPid: nil)
        guard read.failure == nil else {
            if logging { LogManager.kb("  [AX] read failed for pid=\(pid): \(read.failure ?? "unknown")") }
            return nil
        }
        if logging { LogManager.kb("  [AX] read \(read.text.utf16.count) utf16, caret16=\(read.caretUTF16)") }
        return (read.text, read.caretUTF16)
    }

    /// Pure, thread-safe AX read of the focused field. No logging, no shared
    /// mutable state — safe from `contextPollQueue`. `frontPid != nil` (and
    /// ≠ pid) means a non-Dasher app is frontmost: refuse, so a backgrounded
    /// target is never read mid-debounce.
    nonisolated private func readFocusedField(pid: pid_t, frontPid: pid_t?) -> (text: String, caretUTF16: Int, failure: String?) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)

        if let frontPid, frontPid != pid {
            return ("", 0, "target pid=\(pid) is not frontmost (front=\(frontPid))")
        }

        var focusedRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusErr == .success,
              let focusedCF = focusedRef,
              CFGetTypeID(focusedCF) == AXUIElementGetTypeID() else {
            return ("", 0, "no focused element (err=\(focusErr.rawValue))")
        }
        let focused = unsafeBitCast(focusedCF, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(focused, 0.3)

        var valueRef: CFTypeRef?
        let valueErr = AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef)
        guard valueErr == .success, let value = valueRef as? String else {
            return ("", 0, "kAXValueAttribute unavailable (err=\(valueErr.rawValue))")
        }

        let nsLength = (value as NSString).length

        // Caret position (selectedTextRange gives (loc, len)). Guard loc.location >= 0
        // because AX can return kCFNotFound (-1) when no selection exists.
        var rangeRef: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        var caretOffset = nsLength
        if rangeErr == .success, let rangeCF = rangeRef,
              CFGetTypeID(rangeCF) == AXValueGetTypeID() {
            let range = unsafeBitCast(rangeCF, to: AXValue.self)
            var loc = CFRange()
            if AXValueGetValue(range, .cfRange, &loc), loc.location >= 0 {
                caretOffset = min(loc.location, nsLength)
            }
        }

        return (value, caretOffset, nil)
    }

    func checkAccessibility() {
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        )
    }

    func requestAccessibility() {
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
    }

    func startPolling() {
        stopPolling()
        checkAccessibility()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
            )
            DispatchQueue.main.async {
                if trusted != self.hasAccessibilityPermission {
                    self.hasAccessibilityPermission = trusted
                }
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func startWatching() {
        isActive = true
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                DispatchQueue.main.async {
                    guard let self else { return }
                    let changed = self.lastTargetApp?.processIdentifier != app.processIdentifier
                    self.lastTargetApp = app
                    self.targetAppName = app.localizedName ?? "Unknown"
                    LogManager.kb("target switched: bundle=\(app.bundleIdentifier ?? "unknown") pid=\(app.processIdentifier) changed=\(changed)")
                    // Re-attach the AX observer to the new target's pid —
                    // the observer is per-process, so switching apps without
                    // this leaves the watcher on the old pid (dead).
                    self.startCaretWatcher()
                    self.onTargetCaretChanged?(changed ? "target changed" : "refocus")
                }
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication {
            if front.bundleIdentifier != Bundle.main.bundleIdentifier {
                lastTargetApp = front
                targetAppName = front.localizedName ?? "Unknown"
            } else {
                let apps = NSWorkspace.shared.runningApplications.filter {
                    $0.bundleIdentifier != Bundle.main.bundleIdentifier && $0.isActive
                }
                lastTargetApp = apps.first
                targetAppName = apps.first?.localizedName ?? ""
            }
        }
        // Attach the caret watcher now that lastTargetApp is resolved.
        startCaretWatcher()
        // Polling safety net: catches caret moves in apps whose AX never
        // posts selection notifications (BBEdit, Electron editors, ...).
        startContextPolling()
        if lastTargetApp != nil {
            onTargetCaretChanged?("target changed")
        }
    }

    func stopWatching() {
        isActive = false
        stopCaretWatcher()
        stopContextPolling()
        if let observer = frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            frontmostObserver = nil
        }
        targetAppName = ""
    }

    func injectText(_ text: String) {
        guard hasAccessibilityPermission else { return }
        suppressEchoes()

        if text == "\u{08}" {
            LogManager.kb("  injectKey backspace")
            postKeycode(51)
            return
        }
        if text == "\n" {
            LogManager.kb("  injectKey return")
            // Paragraph / Return settle guard (Windows #79): suppress AX caret
            // echoes and record settle timestamp for 1500 ms after our own newline injection.
            lastOwnParagraphOrSelectInjectAt = Date()
            suppressEchoes(for: 1.5)
            postKeycode(36)
            return
        }

        // UTF-16 code units are exactly what keyboardSetUnicodeString wants —
        // using unicodeScalars truncates non-BMP characters (emoji → garbage).
        let unichars = Array(text.utf16)
        LogManager.kb("  injectText utf16=\(unichars.count)")
        unichars.withUnsafeBufferPointer { buf in
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            event?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            postEvent(event)

            let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            postEvent(up)
        }
    }

    func injectDelete(count: Int) {
        guard hasAccessibilityPermission else { return }
        suppressEchoes()
        LogManager.kb("  injectDelete count=\(count)")
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: true)
            postEvent(down)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: false)
            postEvent(up)
        }
    }

    private func postEvent(_ event: CGEvent?) {
        guard let event else { return }
        if let pid = lastTargetApp?.processIdentifier {
            event.postToPid(pid)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    /// Send a Cmd+<key> chord to the target app (Select All = "a", Copy = "c",
    /// Cut = "x", Paste = "v"). Used by the direct-mode mini-bar buttons
    /// (RFC 0019, mirrors the Windows keyboard mini-bar).
    func sendCmdChord(_ key: String) {
        guard hasAccessibilityPermission else { return }
        // Map lowercase ASCII to virtual key (a=0, c=8, v=9, x=7...)
        let virtualKey: CGKeyCode
        switch key.lowercased() {
        case "a": virtualKey = 0    // kVK_ANSI_A
        case "c": virtualKey = 8    // kVK_ANSI_C
        case "v": virtualKey = 9    // kVK_ANSI_V
        case "x": virtualKey = 7    // kVK_ANSI_X
        default: return
        }
        let cmdFlag: CGEventFlags = .maskCommand
        if let down = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true) {
            down.flags = cmdFlag
            postEvent(down)
        }
        if let up = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false) {
            up.flags = cmdFlag
            postEvent(up)
        }
        // Cut and Paste mutate the target field outside Dasher's engine; schedule
        // a debounced context re-seed so the engine re-anchors at the new caret.
        if key.lowercased() == "x" || key.lowercased() == "v" {
            onTargetCaretChanged?("caret moved")
        }
    }

    static let keyCodeBackspace: CGKeyCode = 51   // kVK_Delete (0x33)
    static let keyCodeLeftArrow: CGKeyCode = 123  // kVK_LeftArrow (0x7B)
    static let keyCodeRightArrow: CGKeyCode = 124 // kVK_RightArrow (0x7C)
    static let keyCodeDownArrow: CGKeyCode = 125  // kVK_DownArrow (0x7D)
    static let keyCodeUpArrow: CGKeyCode = 126    // kVK_UpArrow (0x7E)

    /// Inject a single virtual key press + release into the target application
    /// (used by the Direct Mode editing keys strip: Backspace, Left, Right).
    /// Unlike `injectText` / `injectDelete`, this moves the caret or deletes
    /// text outside the Dasher engine, so do NOT suppress AX echoes — instead
    /// notify `onTargetCaretChanged` so the 500 ms debounce re-anchors the
    /// engine once the user releases the button.
    func injectVirtualKey(_ keyCode: CGKeyCode) {
        guard hasAccessibilityPermission else { return }
        LogManager.kb("  injectVirtualKey code=\(keyCode)")
        postKeycode(keyCode)
        onTargetCaretChanged?("caret moved")
    }

    /// RFC 0021: send a Direct Mode selection chord (`Shift+Arrow`,
    /// `Shift+Opt+Arrow`, `Shift+Opt+Up/Down`, or `Cmd+A`) to the target app.
    /// Extends the 1500 ms own-injection settle window (RFC 0021 / Windows #79)
    /// so selection-induced `AXSelectedTextChanged` events do not re-seed the
    /// canvas mid-selection.
    func sendSelectChord(_ keystroke: SelectActions.SelectKeystroke) {
        guard hasAccessibilityPermission else { return }
        lastOwnParagraphOrSelectInjectAt = Date()
        suppressEchoes(for: 1.5)

        var modifiers: CGEventFlags = []
        if keystroke.shift { modifiers.insert(.maskShift) }
        if keystroke.option { modifiers.insert(.maskAlternate) }
        if keystroke.command { modifiers.insert(.maskCommand) }

        let code = CGKeyCode(keystroke.keyCode)
        LogManager.kb("  select chord: shift=\(keystroke.shift) opt=\(keystroke.option) cmd=\(keystroke.command) code=\(code)")

        // Use a private event source so physical HID modifiers (e.g. holding Shift
        // for momentary Dasher Turbo) do not bleed into the chord, and preserve
        // intrinsic arrow-key flags (.maskNumericPad, .maskSecondaryFn) so Cocoa
        // NSTextView selection key-bindings resolve properly.
        let src = CGEventSource(stateID: .privateState)
        let explicitModifiers: CGEventFlags = [.maskShift, .maskAlternate, .maskCommand, .maskControl]
        if let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true) {
            down.flags.subtract(explicitModifiers)
            down.flags.formUnion(modifiers)
            postEvent(down)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) {
            up.flags.subtract(explicitModifiers)
            up.flags.formUnion(modifiers)
            postEvent(up)
        }
    }

    private func postKeycode(_ code: CGKeyCode) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
        postEvent(down)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        postEvent(up)
    }
}
