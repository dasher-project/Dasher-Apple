import Cocoa
import CoreGraphics

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
        echoSuppressionUntil = Date().addingTimeInterval(interval)
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
              CFGetTypeID(focusedCF) == AXUIElementGetTypeID() else { return nil }
        let focused = unsafeBitCast(focusedCF, to: AXUIElement.self)

        var valueRef: CFTypeRef?
        let valueErr = AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef)
        guard valueErr == .success, let value = valueRef as? String else { return nil }

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
            postKeycode(51)
            return
        }
        if text == "\n" {
            postKeycode(36)
            return
        }

        // UTF-16 code units are exactly what keyboardSetUnicodeString wants —
        // using unicodeScalars truncates non-BMP characters (emoji → garbage).
        let unichars = Array(text.utf16)
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

    private func postKeycode(_ code: CGKeyCode) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
        postEvent(down)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        postEvent(up)
    }
}
