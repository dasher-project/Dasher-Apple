import SwiftUI

@MainActor
class DasherViewModel: ObservableObject {
    @Published var outputText: String = ""
    @Published var isPlaying: Bool = true
    @Published var speed: Double = 1.0
    @Published var autoSpeed: Bool = false
    @Published var showMessagePane: Bool = true
    @Published var selectedColourIndex: Int = 0

    let bridge: DasherBridge

    init() {
        let dataPath = Bundle.main.path(forResource: "Data", ofType: nil) ?? ""
        NSLog("DasherViewModel: dataPath=%@", dataPath)
        self.bridge = DasherBridge(dataDir: dataPath)
        NSLog("DasherViewModel: bridge created, isReady=%@", bridge.isReady ? "YES" : "NO")
    }

    func setCanvasSize(_ size: CGSize) {
        bridge.setScreenSize(width: Int(size.width), height: Int(size.height))
    }

    func handleTouch(at point: CGPoint) {
        bridge.mouseDown()
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    func handleTouchEnd() {
        bridge.mouseUp()
    }

    func togglePlay() {
        isPlaying.toggle()
    }

    func newMessage() {
        bridge.resetOutputText()
        outputText = ""
    }

    func increaseSpeed() {
        let newSpeed = min(bridge.speedPercent + 10, 400)
        bridge.setSpeedPercent(newSpeed)
        speed = Double(newSpeed) / 100.0
    }

    func decreaseSpeed() {
        let newSpeed = max(bridge.speedPercent - 10, 20)
        bridge.setSpeedPercent(newSpeed)
        speed = Double(newSpeed) / 100.0
    }

    func toggleMessagePane() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showMessagePane.toggle()
        }
    }

    let colourPresets: [(String, Color)] = [
        ("1", Color(red: 0.96, green: 0.86, blue: 0.30)),
        ("2", Color(red: 1.0, green: 0.82, blue: 0.40)),
        ("3", Color(red: 0.95, green: 0.91, blue: 0.35)),
    ]
}
