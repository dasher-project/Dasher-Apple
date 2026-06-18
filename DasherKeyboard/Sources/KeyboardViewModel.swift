import UIKit
import os.log

class KeyboardViewModel {
    let bridge: DasherBridge
    private weak var textDocumentProxy: UITextDocumentProxy?
    var onAdvanceInputMode: (() -> Void)?
    private var lastReportedHeight: Int = -1

    init(textDocumentProxy: UITextDocumentProxy) {
        os_log("KeyboardViewModel.init: locating data bundle", log: keyboardLog)
        let dataPath = Bundle.main.path(forResource: "DasherKeyboardData", ofType: nil)
            ?? Bundle.main.path(forResource: "Data", ofType: nil)
            ?? ""
        if dataPath.isEmpty {
            os_log("KeyboardViewModel.init: data bundle MISSING", log: keyboardLog, type: .error)
        }
        assert(!dataPath.isEmpty, "Data folder not found in keyboard bundle")
        let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedDefaults.groupIdentifier
        )
        os_log("KeyboardViewModel.init: creating bridge", log: keyboardLog)
        self.bridge = DasherBridge.getOrCreate(dataDir: dataPath, userDir: sharedURL?.path)
        if let err = bridge.lastError {
            os_log("KeyboardViewModel.init: bridge init error: %{public}@", log: keyboardLog, type: .error, err)
            NSLog("[DasherKeyboard] bridge init error: \(err)")
        }
        os_log("KeyboardViewModel.init: configureForLowMemory", log: keyboardLog)
        bridge.configureForLowMemory()

        // First-run: no dasher_settings.xml yet means DasherCore fell back to
        // its compiled-in default alphabet ("English with limited punctuation").
        // If the user's system locale maps to a different bundled alphabet,
        // switch to it once and save. Subsequent launches read the saved value.
        if let sharedURL = sharedURL, !FileManager.default.fileExists(atPath: sharedURL.appendingPathComponent("dasher_settings.xml").path) {
            let localeAlphabet = Self.alphabetID(for: Locale.current)
            os_log("KeyboardViewModel.init: first run, locale alphabet = %{public}@", log: keyboardLog, localeAlphabet)
            bridge.setAlphabetId(localeAlphabet)
            bridge.saveSettings()
        }

        os_log("KeyboardViewModel.init: wiring callbacks", log: keyboardLog)
        self.textDocumentProxy = textDocumentProxy
        bridge.onOutput = { [weak self] text in
            self?.textDocumentProxy?.insertText(text)
        }
        bridge.onDelete = { [weak self] text in
            guard let proxy = self?.textDocumentProxy else { return }
            let deleteCount = min(text.count, proxy.documentContextBeforeInput?.count ?? 0)
            for _ in 0..<deleteCount {
                proxy.deleteBackward()
            }
        }
        bridge.onClipboard = { text in
            UIPasteboard.general.string = text
        }
    }

    func updateProxy(_ proxy: UITextDocumentProxy) {
        textDocumentProxy = proxy
    }

    func setCanvasSize(_ size: CGSize) {
        // Log any height change so we can see when iOS shrinks the keyboard.
        if Int(size.height) != lastReportedHeight {
            os_log("setCanvasSize: %{public}f x %{public}f (was %{public}d)",
                   log: keyboardLog, size.width, size.height, lastReportedHeight)
            lastReportedHeight = Int(size.height)
        }
        bridge.setScreenSize(width: Int(size.width), height: Int(size.height))
    }

    func advanceToNextInputMode() {
        onAdvanceInputMode?()
    }

    func decreaseSpeed() {
        let s = max(20, bridge.speedPercent - 10)
        bridge.setSpeedPercent(s)
    }

    func increaseSpeed() {
        let s = min(400, bridge.speedPercent + 10)
        bridge.setSpeedPercent(s)
    }

    /// Map an iOS `Locale` to a bundled Dasher alphabet ID. Update this table
    /// whenever new alphabets are added to `DasherKeyboardData/alphabets/`.
    /// Unknown locales fall back to the English default.
    static func alphabetID(for locale: Locale) -> String {
        switch locale.language.languageCode?.identifier {
        case "de":
            return "Deutsch German with limited punctuation"
        default:
            return "English with limited punctuation"
        }
    }
}
