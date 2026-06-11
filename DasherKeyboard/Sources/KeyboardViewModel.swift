import SwiftUI
import DasherShared

class KeyboardViewModel: ObservableObject {
    let bridge: DasherBridge
    weak var textDocumentProxy: UITextDocumentProxy?
    var onAdvanceInputMode: (() -> Void)?

    init(textDocumentProxy: UITextDocumentProxy) {
        self.textDocumentProxy = textDocumentProxy
        let dataPath = Bundle.main.path(forResource: "Data", ofType: nil) ?? ""
        assert(!dataPath.isEmpty, "Data folder not found in keyboard bundle")
        let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedDefaults.groupIdentifier
        )
        self.bridge = DasherBridge(dataDir: dataPath, userDir: sharedURL?.path)
        if let err = bridge.lastError {
            NSLog("[DasherKeyboard] bridge init error: \(err)")
        }
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
    }

    func setCanvasSize(_ size: CGSize) {
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
}
