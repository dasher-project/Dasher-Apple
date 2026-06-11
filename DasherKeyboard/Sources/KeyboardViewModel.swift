import SwiftUI

class KeyboardViewModel: ObservableObject {
    let bridge: DasherBridge
    weak var textDocumentProxy: UITextDocumentProxy?
    var onAdvanceInputMode: (() -> Void)?

    init(textDocumentProxy: UITextDocumentProxy) {
        self.textDocumentProxy = textDocumentProxy
        let dataPath = Bundle.main.path(forResource: "Data", ofType: nil) ?? ""
        assert(!dataPath.isEmpty, "Data folder not found in keyboard bundle")
        self.bridge = DasherBridge(dataDir: dataPath)
        if let err = bridge.lastError {
            NSLog("[DasherKeyboard] bridge init error: \(err)")
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
