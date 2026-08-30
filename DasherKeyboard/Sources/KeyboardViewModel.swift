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

        // Auto-calibration stays off in the keyboard extension (DasherCore #64/
        // #65, Dasher-Windows #41): the keyboard surface is touch/pointer, never
        // eye gaze, and this engine shares the app group's dasher_settings.xml —
        // a stale persisted BP_AUTOCALIBRATE=true from an older build would
        // otherwise drift the steering offset here.
        bridge.setBoolParameter(key: bridge.findParameterKey("BP_AUTOCALIBRATE"), value: false)

        // First-run: no dasher_settings.xml yet means DasherCore fell back to
        // its compiled-in default alphabet ("English with limited punctuation").
        // Follow the device locale via the shared metadata index (replaces the
        // old hardcoded en/de table) while locale-follow isn't pinned — the pin
        // lives in the app group, so a pick in the main app applies here too.
        if let sharedURL = sharedURL, !FileManager.default.fileExists(atPath: sharedURL.appendingPathComponent("dasher_settings.xml").path) {
            let follows = UserDefaults(suiteName: SharedDefaults.groupIdentifier)?
                .object(forKey: "alphabet_follows_locale") as? Bool ?? true
            let localeAlphabet = follows
                ? Self.suggestedAlphabet(for: Locale.current, dataDir: dataPath,
                                         available: Set(bridge.allAlphabets.map { $0.name }))
                : Self.alphabetID(for: Locale.current)
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
        // Cross-component settings sync (issue #44, Dasher-Android #30 pattern):
        // the main app may have saved dasher_settings.xml while the keyboard
        // process stayed warm holding an older snapshot. This fires each time
        // the keyboard attaches to a text field — reload is cheap and a no-op
        // when nothing changed (differing values only; edit buffer preserved).
        bridge.reloadSettings()
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
        let s = max(DasherBridge.speedRangePercent.lowerBound, bridge.speedPercent - 10)
        bridge.setSpeedPercent(s)
    }

    func increaseSpeed() {
        let s = min(DasherBridge.speedRangePercent.upperBound, bridge.speedPercent + 10)
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

    /// Locale→alphabet via DasherCore's `alphabet_index.json` (bundled in
    /// DasherKeyboardData), constrained to the alphabets this keyboard
    /// actually ships. A minimal port of DasherShared/AlphabetIndex.swift —
    /// the keyboard cannot link DasherShared (it would pull PostHog into the
    /// memory-constrained extension). Falls back to the table above.
    static func suggestedAlphabet(for locale: Locale, dataDir: String, available: Set<String>) -> String {
        struct Entry: Decodable {
            let id: String
            let lang: String?
            let source: String?
        }
        struct IndexFile: Decodable { let alphabets: [Entry] }
        let url = URL(fileURLWithPath: dataDir)
            .appendingPathComponent("alphabets", isDirectory: true)
            .appendingPathComponent("alphabet_index.json")
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(IndexFile.self, from: data) else {
            return alphabetID(for: locale)
        }
        guard let language = locale.language.languageCode?.identifier.lowercased() else {
            return alphabetID(for: locale)
        }
        let entries = file.alphabets.filter { available.contains($0.id) && $0.lang != nil }
        func rank(_ e: Entry) -> Int {
            let tier = e.source == "maintained" ? 0 : (e.source == "worldalphabets" ? 1 : 2)
            return (2 - tier) * 1_000_000 + (e.id == "English with limited punctuation" ? 500_000 : 0)
        }
        let match = entries.filter { $0.lang!.lowercased().hasPrefix(language) }
            .max(by: { rank($0) < rank($1) })
        return match?.id ?? alphabetID(for: locale)
    }
}
