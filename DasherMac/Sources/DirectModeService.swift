import Cocoa
import CoreGraphics
import DasherShared

@MainActor
class DirectModeService: ObservableObject {
    @Published var isActive = false
    @Published var hasAccessibilityPermission = false
    @Published var targetAppName: String = ""

    /// RFC 0019 clause 6: fires when the caret/selection changes in the target
    /// app's focused text field. The view model re-seeds the engine from the
    /// field's content at the new caret position.
    var onTargetCaretChanged: (() -> Void)?

    /// Self-injection echo suppression (Windows #58/#61): when Dasher types
    /// into the target, the AX caret watcher fires for our own injected text.
    /// The engine already knows — don't re-seed from our own output.
    private var echoSuppressionUntil = Date.distantPast

    func suppressEchoes(for interval: TimeInterval = 0.3) {
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

    /// AXObserver-based caret watcher. NotificationCenter only delivers AX
    /// notifications for elements in our own process; cross-process watching
    /// requires AXObserverCreate(pid:) + per-element notification registration
    /// on the focused element, re-attached whenever focus moves.
    private func startCaretWatcher() {
        stopCaretWatcher()
        guard let pid = lastTargetApp?.processIdentifier else { return }

        let callback: AXObserverCallback = { _, _, _, refcon in
            let service = Unmanaged<DirectModeService>.fromOpaque(refcon!).takeUnretainedValue()
            DispatchQueue.main.async {
                guard let front = NSWorkspace.shared.frontmostApplication,
                      front.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
                guard !service.isEchoSuppressed else { return }
                service.onTargetCaretChanged?()
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
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Watch focus changes on the app element — tabbing between text fields
        // within the same app fires this; re-register the caret notification
        // on the newly focused element so clause-6 survives field switches.
        AXObserverAddNotification(observer, app, kAXFocusedUIElementChangedNotification as CFString, refcon)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedCF = focusedRef,
              CFGetTypeID(focusedCF) == AXUIElementGetTypeID() else { return }
        let focused = unsafeBitCast(focusedCF, to: AXUIElement.self)
        AXObserverAddNotification(observer, focused, kAXSelectedTextChangedNotification as CFString, refcon)
    }

    private func stopCaretWatcher() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            axObserver = nil
        }
    }

    /// Reads the focused text field's content + caret via AX, for engine
    /// re-seeding (RFC 0019 clause 6 / RFC 0015 tier 3). A 300 ms timeout on
    /// the AX messages prevents an unresponsive target from stalling the
    /// caret watcher (Windows' hard budget, PR #52).
    func readTargetFieldContext() -> (before: String, after: String)? {
        guard hasAccessibilityPermission,
              let pid = lastTargetApp?.processIdentifier else { return nil }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)

        var focusedRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusErr == .success,
              let focusedCF = focusedRef,
              CFGetTypeID(focusedCF) == AXUIElementGetTypeID() else {
            LogManager.kb("  [AX] no focused element for pid=\(pid) err=\(focusErr.rawValue)")
            return nil
        }
        let focused = unsafeBitCast(focusedCF, to: AXUIElement.self)

        var valueRef: CFTypeRef?
        let valueErr = AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef)
        guard valueErr == .success, let value = valueRef as? String else {
            LogManager.kb("  [AX] kAXValueAttribute unavailable for pid=\(pid) err=\(valueErr.rawValue)")
            return nil
        }

        // Caret position (selectedTextRange gives (loc, len))
        var rangeRef: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        var caretOffset = (value as NSString).length
        if rangeErr == .success, let rangeCF = rangeRef,
              CFGetTypeID(rangeCF) == AXValueGetTypeID() {
            let range = unsafeBitCast(rangeCF, to: AXValue.self)
            var loc = CFRange()
            if AXValueGetValue(range, .cfRange, &loc) {
                caretOffset = loc.location
            }
        }

        let nsValue = value as NSString
        LogManager.kb("  [AX] read \(nsValue.length) utf16, caret16=\(caretOffset)")
        let before = nsValue.substring(to: min(caretOffset, nsValue.length))
        let after = nsValue.substring(from: min(caretOffset, nsValue.length))
        return (before, after)
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
        startCaretWatcher()
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                DispatchQueue.main.async {
                    self?.lastTargetApp = app
                    self?.targetAppName = app.localizedName ?? "Unknown"
                    LogManager.kb("target switched: bundle=\(app.bundleIdentifier ?? "unknown") pid=\(app.processIdentifier)")
                    // Re-attach the AX observer to the new target's pid —
                    // the observer is per-process, so switching apps without
                    // this leaves the watcher on the old pid (dead).
                    self?.startCaretWatcher()
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
    }

    func stopWatching() {
        stopCaretWatcher()
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
            // echoes for 1500 ms after our own newline injection.
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
    }

    static let keyCodeBackspace: CGKeyCode = 51   // kVK_Delete (0x33)
    static let keyCodeLeftArrow: CGKeyCode = 123  // kVK_LeftArrow (0x7B)
    static let keyCodeRightArrow: CGKeyCode = 124 // kVK_RightArrow (0x7C)
    static let keyCodeDownArrow: CGKeyCode = 125  // kVK_DownArrow (0x7D)
    static let keyCodeUpArrow: CGKeyCode = 126    // kVK_UpArrow (0x7E)

    /// Inject a single virtual key press + release into the target application
    /// (used by the Direct Mode editing keys strip: Backspace, Left, Right).
    func injectVirtualKey(_ keyCode: CGKeyCode) {
        guard hasAccessibilityPermission else { return }
        suppressEchoes()
        LogManager.kb("  injectVirtualKey code=\(keyCode)")
        postKeycode(keyCode)
    }

    /// RFC 0021: send a Direct Mode selection chord (`Shift+Arrow`,
    /// `Shift+Opt+Arrow`, `Shift+Opt+Up/Down`, or `Cmd+A`) to the target app.
    /// Extends the 1500 ms own-injection settle window (RFC 0021 / Windows #79)
    /// so selection-induced `AXSelectedTextChanged` events do not re-seed the
    /// canvas mid-selection.
    func sendSelectChord(_ keystroke: SelectActions.SelectKeystroke) {
        guard hasAccessibilityPermission else { return }
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
