import SwiftUI
import DasherShared
import DasherSpeech
import UniformTypeIdentifiers

@MainActor
class MacDasherViewModel: ObservableObject {
    @Published var outputText: String = ""
    @Published var isPlaying: Bool = true
    @Published var isGameModeActive: Bool = false
    @Published var isControlModeActive: Bool = false
    @Published var gameTargetText: String = ""
    @Published var gameCorrectCount: Int = 0
    @Published var gameTargetLength: Int = 0
    @Published var gameWrongText: String = ""
    @Published var pendingMessage: (isWarning: Bool, text: String)?
    @Published var speed: Double = 1.0
    @Published var autoSpeed: Bool = false
    @Published var showMessagePane: Bool = true
    @Published var selectedColourIndex: Int = 0
    @Published var showShareSheet = false
    @Published var showOpenFile = false
    @Published var outputMode: OutputMode = .right {
        didSet {
            directMode = (outputMode == .direct)
            showMessagePane = (outputMode != .direct)
        }
    }
    @Published var directMode: Bool = false {
        didSet { updateDirectMode() }
    }
    @Published var directOpacity: Double = 0.75

    let bridge: DasherBridge
    let directService = DirectModeService()
    let speech = SpeechService.shared

    init() {
        let dataPath = Bundle.main.path(forResource: "Data", ofType: nil) ?? ""
        let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedDefaults.groupIdentifier
        )
        self.bridge = DasherBridge(dataDir: dataPath, userDir: sharedURL?.path)
        bridge.setScreenSize(width: 900, height: 600)

        bridge.onMessage = { [weak self] isWarning, text in
            if text.contains("No user training text found") { return }
            self?.pendingMessage = (isWarning, text)
        }

        bridge.onOutput = { [weak self] text in
            guard let self else { return }
            if self.directMode {
                self.directService.injectText(text)
            }
            self.outputText = self.bridge.getOutputText()
        }

        bridge.onDelete = { [weak self] text in
            guard let self else { return }
            if self.directMode {
                self.directService.injectDelete(count: text.count)
            }
            self.outputText = self.bridge.getOutputText()
        }

        bridge.onSpeak = { [weak self] text, interrupt in
            Task { @MainActor in
                if interrupt {
                    self?.speech.stop()
                }
                self?.speech.speak(text)
            }
        }
        bridge.onClipboard = { text in
            Task { @MainActor in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }

        let savedConfig = AccessConfiguration.current
        savedConfig.apply(to: bridge)

        let bitrateKey = bridge.findParameterKey("LP_MAX_BITRATE")
        bridge.onParameterChange = { [weak self] key in
            guard key == bitrateKey else { return }
            Task { @MainActor in
                self?.speed = Double(self?.bridge.speedPercent ?? 100) / 100.0
            }
        }
        speed = Double(bridge.speedPercent) / 100.0
    }

    private func updateDirectMode() {
        if directMode {
            directService.startPolling()
            directService.startWatching()
        } else {
            directService.stopPolling()
            directService.stopWatching()
        }
    }

    func setCanvasSize(_ size: CGSize) {
        bridge.setScreenSize(width: Int(size.width), height: Int(size.height))
    }

    func handleTouch(at point: CGPoint) {
        guard isPlaying else { return }
        bridge.mouseDown()
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

    func toggleControlMode() {
        isControlModeActive.toggle()
        let key = bridge.findParameterKey("BP_CONTROL_MODE")
        bridge.setBoolParameter(key: key, value: isControlModeActive)
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
    }

    func openText(_ text: String) {
        bridge.reset()
        outputText = text
    }

    var shareText: String {
        outputText
    }

    func saveText(to url: URL) {
        try? outputText.write(to: url, atomically: true, encoding: .utf8)
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

    let colourPresets: [(String, Color)] = [
        ("1", Color(red: 0.96, green: 0.86, blue: 0.30)),
        ("2", Color(red: 1.0, green: 0.82, blue: 0.40)),
        ("3", Color(red: 0.95, green: 0.91, blue: 0.35)),
    ]

    func stopSpeech() {
        speech.stop()
    }
}

enum OutputMode: String, CaseIterable {
    case right = "Right side"
    case left = "Left side"
    case bottom = "Bottom"
    case top = "Top"
    case direct = "Direct Mode"

    var icon: String {
        switch self {
        case .right: return "sidebar.right"
        case .left: return "sidebar.left"
        case .bottom: return "rectangle.split.1x2"
        case .top: return "rectangle.split.1x2"
        case .direct: return "keyboard"
        }
    }
}
