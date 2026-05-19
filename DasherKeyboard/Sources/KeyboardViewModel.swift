import SwiftUI

@MainActor
class KeyboardViewModel: ObservableObject {
    let bridge: DasherBridge
    weak var textDocumentProxy: UITextDocumentProxy?
    var onAdvanceInputMode: (() -> Void)?

    init(textDocumentProxy: UITextDocumentProxy) {
        self.textDocumentProxy = textDocumentProxy
        let dataPath = Bundle.main.path(forResource: "Data", ofType: nil) ?? ""
        self.bridge = DasherBridge(dataDir: dataPath)
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
