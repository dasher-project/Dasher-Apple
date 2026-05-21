import SwiftUI
import UniformTypeIdentifiers

@MainActor
class DasherViewModel: ObservableObject {
    @Published var outputText: String = ""
    @Published var isPlaying: Bool = true
    @Published var speed: Double = 1.0
    @Published var autoSpeed: Bool = false
    @Published var pointerHoverEnabled: Bool = false
    @Published var appLevelDwell: Bool = false
    @Published var dwellDuration: Double = 0.5
    @Published var showOpenFile = false
    @Published var showShareSheet = false
    @Published var importedText: String?

    let bridge: DasherBridge
    let speech = SpeechService.shared
    private var lastSpokenText: String = ""
    private var speechDebounceTask: Task<Void, Never>?

    static let dwellDurationOptions: [(String, Double)] = [
        ("0.3s", 0.3),
        ("0.5s", 0.5),
        ("0.8s", 0.8),
        ("1.0s", 1.0),
        ("1.5s", 1.5),
    ]

    init() {
        let dataPath = Bundle.main.path(forResource: "Data", ofType: nil) ?? ""
        let userPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
        self.bridge = DasherBridge(dataDir: dataPath, userDir: userPath)
        bridge.setScreenSize(width: 800, height: 600)
    }

    func setCanvasSize(_ size: CGSize) {
        bridge.setScreenSize(width: Int(size.width), height: Int(size.height))
    }

    func handlePointerHover(at point: CGPoint) {
        guard isPlaying else { return }
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    func handleTouch(at point: CGPoint) {
        guard isPlaying else { return }
        bridge.mouseDown()
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    func handleTouchMove(at point: CGPoint) {
        guard isPlaying else { return }
        bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    func handleTouchEnd() {
        guard isPlaying else { return }
        bridge.mouseUp()
    }

    func togglePlay() {
        isPlaying.toggle()
    }

    func newMessage() {
        bridge.resetOutputText()
        outputText = ""
        lastSpokenText = ""
    }

    func openText(_ text: String) {
        bridge.resetOutputText()
        outputText = text
        lastSpokenText = ""
    }

    func checkSpeech() {
        let text = bridge.getOutputText()
        guard text != lastSpokenText, !text.isEmpty else { return }
        lastSpokenText = text
        guard bridge.getBoolParameter(key: 24) else { return }
        speechDebounceTask?.cancel()
        speechDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            speech.speak(text)
        }
    }

    var shareText: String {
        outputText
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
}
