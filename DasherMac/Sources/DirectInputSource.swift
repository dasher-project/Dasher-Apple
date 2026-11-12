import AppKit
import Carbon
import DasherShared

@MainActor
final class DirectInputSource {
    private static let identifier = "at.dasher.inputmethod.direct"
    private static let previousSourceKey = "directInputPreviousSource"
    private static let helperName = "Dasher Direct Input.app"

    private var installation: Task<Void, Never>?
    private var activation: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
    private var didSelectSource = false

    init() {
        // Restore the original source on launch if Dasher previously quit
        // without its termination handler, for example after a crash.
        Self.restoreSource()
    }

    func start() {
        guard activation == nil else { return }
        if !didSelectSource && installation == nil {
            installation = Task { await Self.installBundledSource() }
        }
        selectForEditor()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func editorChanged() {
        if activation == nil {
            start()
        } else {
            selectForEditor()
        }
    }

    private func selectForEditor() {
        activation?.cancel()
        let pendingInstallation = installation
        activation = Task { [weak self] in
            await pendingInstallation?.value
            guard !Task.isCancelled else { return }
            self?.installation = nil
            // macOS can apply a remembered source when an editor activates.
            try? await Task.sleep(for: .milliseconds(100))
            var requestedEnable = false
            for _ in 0..<15 {
                guard !Task.isCancelled else { return }
                if let source = Self.source(withID: Self.identifier, includeDisabled: false),
                   Self.selectSource(source) {
                    self?.didSelectSource = true
                    return
                }
                // macOS 27 opens Keyboard Settings for an enable request. Leave
                // the editor focused and use Accessibility until the source is enabled.
                if #unavailable(macOS 27),
                   !requestedEnable, let source = Self.source(withID: Self.identifier, includeDisabled: true) {
                    let status = TISEnableInputSource(source)
                    requestedEnable = status == noErr
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            if !Task.isCancelled { LogManager.kb("Dasher Direct Input could not be selected") }
        }
    }

    func stop() {
        activation?.cancel()
        activation = nil
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        Self.restoreSource()
    }

    private static func installBundledSource() async {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(helperName)")
        guard FileManager.default.fileExists(atPath: helper.path) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.promptsUserIfNeeded = false
        do {
            // The helper identifies the bundled location and installs the user
            // copy. Launch Services ignores launch arguments from sandboxed apps.
            let installer = try await NSWorkspace.shared.openApplication(at: helper, configuration: configuration)
            for _ in 0..<40 {
                if installer.isTerminated {
                    // TIS must register the user copy, outside Dasher's sandbox container.
                    guard let home = FileManager.default.homeDirectory(forUser: NSUserName()) else { return }
                    let installed = home.appendingPathComponent("Library/Input Methods/\(helperName)")
                    let status = TISRegisterInputSource(installed as CFURL)
                    if status != noErr { LogManager.kb("Direct input source registration failed (\(status))") }
                    return
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            LogManager.kb("Direct input source setup is still running")
        } catch {
            LogManager.kb("Direct input source setup failed (\((error as NSError).code))")
        }
    }

    private static func selectSource(_ source: TISInputSource) -> Bool {
        guard let previous = currentSourceID() else { return false }
        if previous == identifier { return true }

        UserDefaults.standard.set(previous, forKey: previousSourceKey)
        let result = TISSelectInputSource(source)
        if result == noErr {
            LogManager.kb("Direct input source selected")
            return true
        }
        UserDefaults.standard.removeObject(forKey: previousSourceKey)
        LogManager.kb("Direct input source selection failed (\(result))")
        return false
    }

    private static func restoreSource() {
        let defaults = UserDefaults.standard
        guard let previous = defaults.string(forKey: previousSourceKey) else { return }
        guard let current = currentSourceID() else { return }
        guard current == identifier else {
            defaults.removeObject(forKey: previousSourceKey)
            return
        }
        let source = source(withID: previous, includeDisabled: false)
            ?? TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        if let source, TISSelectInputSource(source) == noErr {
            defaults.removeObject(forKey: previousSourceKey)
            LogManager.kb("Previous input source restored")
        }
    }

    private static func currentSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
    }

    private static func source(withID id: String, includeDisabled: Bool) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        let sources = TISCreateInputSourceList(filter, includeDisabled)?.takeRetainedValue() as? [TISInputSource]
        return sources?.first
    }
}
