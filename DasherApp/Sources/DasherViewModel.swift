import SwiftUI
import DasherShared
import UniformTypeIdentifiers

@MainActor
class DasherViewModel: ObservableObject {
    @Published var outputText: String = ""
    @Published var isPlaying: Bool = true
    @Published var isGameModeActive: Bool = false
    @Published var gameTargetText: String = ""
    @Published var gameCorrectCount: Int = 0
    @Published var gameTargetLength: Int = 0
    @Published var gameWrongText: String = ""
    @Published var pendingMessage: (isWarning: Bool, text: String)?
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
    #if os(iOS)
    let tiltService = TiltInputService()
    #endif
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
        bridge.onMessage = { [weak self] isWarning, text in
            if text.contains("No user training text found") { return }
            self?.pendingMessage = (isWarning, text)
        }
        let savedConfig = AccessConfiguration.current
        savedConfig.apply(to: bridge)
        #if os(iOS)
        if savedConfig.method == .tilt {
            tiltService.activate(bridge: bridge)
        }
        #endif
    }

    func setCanvasSize(_ size: CGSize) {
        bridge.setScreenSize(width: Int(size.width), height: Int(size.height))
        #if os(iOS)
        tiltService.screenWidth = Int(size.width)
        tiltService.screenHeight = Int(size.height)
        #endif
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

    func toggleGameMode() {
        if isGameModeActive {
            bridge.leaveGameMode()
            isGameModeActive = false
        } else {
            let success = bridge.enterGameMode()
            isGameModeActive = success
            if !success {
                bridge.reset()
                outputText = ""
            }
        }
    }

    func syncGameModeState() {
        let active = bridge.isGameModeActive
        if active != isGameModeActive {
            isGameModeActive = active
        }
        if active {
            gameTargetText = bridge.getGameTargetText()
            gameCorrectCount = bridge.getGameCorrectCount()
            gameTargetLength = bridge.getGameTargetLength()
            gameWrongText = bridge.getGameWrongText()
        } else {
            gameTargetText = ""
            gameCorrectCount = 0
            gameTargetLength = 0
            gameWrongText = ""
        }
    }

    func newMessage() {
        bridge.reset()
        outputText = ""
        lastSpokenText = ""
    }

    func openText(_ text: String) {
        bridge.reset()
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

    #if os(iOS)
    func activateTiltIfNeeded(method: AccessMethod) {
        if method == .tilt && tiltService.isCalibrating == false {
            if !tiltService.isActive {
                tiltService.activate(bridge: bridge)
            }
        } else {
            if tiltService.isActive {
                tiltService.deactivate()
            }
        }
    }
    #endif
}
