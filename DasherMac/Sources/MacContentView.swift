import SwiftUI
import DasherShared
import LucideIcons
import UniformTypeIdentifiers

struct MacContentView: View {
    @ObservedObject var viewModel: MacDasherViewModel
    @State private var showSettings = false
    @State private var currentLayoutPosition = "Right"
    @State private var outputPaneFraction: CGFloat = 2.0 / 9.0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if currentLayoutPosition == "Left" {
                leftTextLayout
            } else if currentLayoutPosition == "Bottom" {
                bottomTextLayout
            } else if currentLayoutPosition == "Top" {
                topTextLayout
            } else if currentLayoutPosition == "Direct" {
                directModeLayout
            } else {
                rightTextLayout
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
                .sheet(isPresented: $showSettings) {
                    MacDasherSettingsView(viewModel: viewModel)
                }
        .onChange(of: currentLayoutPosition) { _, newValue in
            viewModel.directMode = (newValue == "Direct")
            setFloatingWindow(newValue == "Direct")
            if newValue == "Direct" && viewModel.isGameModeActive {
                viewModel.toggleGameMode()
            }
        }
        .overlay(alignment: .top) {
            if let msg = viewModel.pendingMessage {
                MessageBanner(
                    isWarning: msg.isWarning,
                    text: msg.text,
                    onDismiss: { viewModel.pendingMessage = nil }
                )
                .padding(.top, 8)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { viewModel.newMessage() }) {
                    LucideLabel("New", icon: DasherIcon.newDocument)
                }

                layoutPickerMenu

                if currentLayoutPosition != "Direct" {
                    Button(action: { viewModel.toggleGameMode() }) {
                        LucideLabel(viewModel.isGameModeActive ? "Game On" : "Game Mode",
                              icon: DasherIcon.gameMode)
                    }
                }

                Button(action: { viewModel.toggleControlMode() }) {
                    LucideLabel(viewModel.isControlModeActive ? "Leave" : "Control",
                          icon: DasherIcon.controlMode)
                }

                Button(action: { showSettings = true }) {
                    LucideLabel("Settings", icon: DasherIcon.settings)
                }
            }
        }
        .onAppear { viewModel.bridge.setSystemAppearance(dark: colorScheme == .dark) }
        .onChange(of: colorScheme) { _, newScheme in
            viewModel.bridge.setSystemAppearance(dark: newScheme == .dark)
        }
    }

    private var layoutPickerMenu: some View {
        Menu {
            Button("Right side") { currentLayoutPosition = "Right" }
            Button("Left side") { currentLayoutPosition = "Left" }
            Button("Bottom") { currentLayoutPosition = "Bottom" }
            Button("Top") { currentLayoutPosition = "Top" }
            Divider()
            Button("Direct Mode") { currentLayoutPosition = "Direct" }
        } label: {
            LucideLabel(currentLayoutPosition, icon: layoutIcon)
        }
    }

    private var layoutIcon: String {
        switch currentLayoutPosition {
        case "Right": return DasherIcon.paneRight
        case "Left": return DasherIcon.paneLeft
        case "Bottom": return DasherIcon.paneBottom
        case "Top": return DasherIcon.paneTop
        case "Direct": return DasherIcon.keyboard
        default: return DasherIcon.paneRight
        }
    }

    // MARK: - Right Layout

    private var rightTextLayout: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let contentWidth = geo.size.width
                let contentHeight = geo.size.height - 44

                HStack(spacing: 0) {
                    MacCanvasView(viewModel: viewModel)
                        .frame(width: contentWidth * (1 - outputPaneFraction))

                    Divider()

                    MacOutputTextView(
                        viewModel: viewModel,
                        paneSize: Binding(
                            get: { contentWidth * outputPaneFraction },
                            set: { outputPaneFraction = $0 / contentWidth }
                        ),
                        handleEdge: .leading,
                        availableSpace: contentWidth
                    )
                    .frame(width: contentWidth * outputPaneFraction)
                }
            }

            Divider()
            bottomBar
        }
    }

    // MARK: - Left Layout

    private var leftTextLayout: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let contentWidth = geo.size.width

                HStack(spacing: 0) {
                    MacOutputTextView(
                        viewModel: viewModel,
                        paneSize: Binding(
                            get: { contentWidth * outputPaneFraction },
                            set: { outputPaneFraction = $0 / contentWidth }
                        ),
                        handleEdge: .trailing,
                        availableSpace: contentWidth
                    )
                    .frame(width: contentWidth * outputPaneFraction)

                    Divider()

                    MacCanvasView(viewModel: viewModel)
                        .frame(width: contentWidth * (1 - outputPaneFraction))
                }
            }

            Divider()
            bottomBar
        }
    }

    // MARK: - Bottom Layout

    private var bottomTextLayout: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let contentWidth = geo.size.width
                let contentHeight = geo.size.height - 44

                VStack(spacing: 0) {
                    MacCanvasView(viewModel: viewModel)
                        .frame(height: contentHeight * (1 - outputPaneFraction))

                    Divider()

                    MacOutputTextView(
                        viewModel: viewModel,
                        paneSize: Binding(
                            get: { contentHeight * outputPaneFraction },
                            set: { outputPaneFraction = $0 / contentHeight }
                        ),
                        handleEdge: .top,
                        availableSpace: contentHeight
                    )
                    .frame(height: contentHeight * outputPaneFraction)
                }
            }

            Divider()
            bottomBar
        }
    }

    // MARK: - Top Layout

    private var topTextLayout: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let contentHeight = geo.size.height

                VStack(spacing: 0) {
                    MacOutputTextView(
                        viewModel: viewModel,
                        paneSize: Binding(
                            get: { contentHeight * outputPaneFraction },
                            set: { outputPaneFraction = $0 / contentHeight }
                        ),
                        handleEdge: .bottom,
                        availableSpace: contentHeight
                    )
                    .frame(height: contentHeight * outputPaneFraction)

                    Divider()

                    MacCanvasView(viewModel: viewModel)
                        .frame(height: contentHeight * (1 - outputPaneFraction))
                }
            }

            Divider()
            bottomBar
        }
    }

    // MARK: - Direct Mode Layout

    private var directModeLayout: some View {
        VStack(spacing: 0) {
            if !viewModel.directService.hasAccessibilityPermission {
                accessibilityPrompt
                    .onAppear {
                        viewModel.directService.checkAccessibility()
                        viewModel.directService.startPolling()
                    }
                    .onDisappear {
                        if !viewModel.directMode {
                            viewModel.directService.stopPolling()
                        }
                    }
            } else {
                ZStack(alignment: .topTrailing) {
                    MacCanvasView(viewModel: viewModel)
                        .background(Color.clear)
                    VStack(spacing: 4) {
                        targetAppIndicator.padding(8)
                        directModeMiniBar.padding(.trailing, 8)
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                LucideIcon(DasherIcon.textSize, size: 11, color: .secondary)
                Slider(value: $viewModel.directOpacity, in: 0.2...1.0, step: 0.05)
                    .frame(width: 120)
                Text("\(Int(viewModel.directOpacity * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .trailing)
                Spacer()
                speedStepper
                Spacer()
                speechPicker
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(.ultraThinMaterial)
        }
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(viewModel.directOpacity)
                .ignoresSafeArea()
        )
    }

    private var targetAppIndicator: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.green).frame(width: 6, height: 6)
            Text("Sending to \(viewModel.directService.targetAppName)")
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.black.opacity(0.6)))
    }

    private var directModeMiniBar: some View {
        HStack(spacing: 2) {
            Button {
                viewModel.toggleControlMode()
            } label: {
                LucideIcon(DasherIcon.controlMode, size: 18, color: viewModel.isControlModeActive ? Color("DasherTeal") : Color("MutedText"))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button {
                showSettings = true
            } label: {
                LucideIcon(DasherIcon.settings, size: 18, color: Color("MutedText"))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button {
                currentLayoutPosition = "Right"
            } label: {
                LucideIcon(DasherIcon.keyboard, size: 18, color: Color("MutedText"))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            alphabetPicker
            barDivider
            speedStepper
            barDivider
            autoSpeedToggle
            barDivider
            learningToggle
            barDivider
            speechPicker
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var barDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 6)
    }

    private var alphabetPicker: some View {
        let alphabets = viewModel.bridge.allAlphabets
        return Menu {
            ForEach(alphabets, id: \.name) { a in
                Button(a.name) { viewModel.bridge.setAlphabetId(a.name) }
            }
        } label: {
            HStack(spacing: 3) {
                Text(viewModel.bridge.alphabetId)
                    .font(.system(size: 13))
                    .lineLimit(1)
                LucideIcon(DasherIcon.chevronDown, size: 8, color: .secondary)
            }
        }
    }

    private var speedStepper: some View {
        HStack(spacing: 4) {
            Text("Speed")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Button("-") { viewModel.decreaseSpeed() }
            Text(String(format: "%.1f", viewModel.speed))
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 30)
            Button("+") { viewModel.increaseSpeed() }
        }
    }

    private var learningToggle: some View {
        let binding = Binding<Bool>(
            get: { viewModel.bridge.getBoolParameter(key: viewModel.bridge.findParameterKey("BP_LM_ADAPTIVE")) },
            set: { viewModel.bridge.setBoolParameter(key: viewModel.bridge.findParameterKey("BP_LM_ADAPTIVE"), value: $0) }
        )
        return HStack(spacing: 6) {
            Text("Learning")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .fixedSize()
    }

    private var autoSpeedToggle: some View {
        let binding = Binding<Bool>(
            get: { viewModel.bridge.getBoolParameter(key: viewModel.bridge.findParameterKey("BP_AUTO_SPEEDCONTROL")) },
            set: { viewModel.bridge.setBoolParameter(key: viewModel.bridge.findParameterKey("BP_AUTO_SPEEDCONTROL"), value: $0) }
        )
        return HStack(spacing: 6) {
            Text("Auto")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .fixedSize()
    }

    private var palettePicker: some View {
        let palettes = viewModel.bridge.allPalettes
        return Menu {
            ForEach(palettes, id: \.name) { p in
                Button(action: { viewModel.bridge.setPalette(p.name) }) {
                    LucideLabel(p.name, icon: "circle", iconSize: 12)
                }
            }
        } label: {
            LucideIcon(DasherIcon.palette)
        }
    }

    private var fontPicker: some View {
        let fonts = [
            "System", "Georgia", "Helvetica Neue", "Menlo",
            "Courier New", "Avenir Next", "Futura", "Palatino",
            "Trebuchet MS", "Verdana",
        ]
        let currentFont = viewModel.bridge.getStringParameter(key: viewModel.bridge.findParameterKey("SP_DASHER_FONT"))
        return Menu {
            ForEach(fonts, id: \.self) { f in
                Button(f) { viewModel.bridge.setStringParameter(key: viewModel.bridge.findParameterKey("SP_DASHER_FONT"), value: f) }
            }
        } label: {
            HStack(spacing: 3) {
                Text(currentFont.isEmpty ? "System" : currentFont)
                    .font(.system(size: 13))
                    .lineLimit(1)
                LucideIcon(DasherIcon.chevronDown, size: 8, color: .secondary)
            }
        }
    }

    private var fontSizeStepper: some View {
        let binding = Binding<Int>(
            get: { viewModel.bridge.getLongParameter(key: viewModel.bridge.findParameterKey("LP_DASHER_FONTSIZE")) },
            set: { viewModel.bridge.setLongParameter(key: viewModel.bridge.findParameterKey("LP_DASHER_FONTSIZE"), value: $0) }
        )
        return HStack(spacing: 4) {
            Text("Size")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Button("-") { viewModel.bridge.setLongParameter(key: viewModel.bridge.findParameterKey("LP_DASHER_FONTSIZE"), value: max(8, binding.wrappedValue - 1)) }
            Text("\(binding.wrappedValue)")
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 24)
            Button("+") { viewModel.bridge.setLongParameter(key: viewModel.bridge.findParameterKey("LP_DASHER_FONTSIZE"), value: min(72, binding.wrappedValue + 1)) }
        }
    }

    private var speechPicker: some View {
        let isOn = viewModel.bridge.getBoolParameter(key: viewModel.bridge.findParameterKey("BP_SPEAK_WORDS"))
        return HStack(spacing: 4) {
            Menu {
                Button("Speech on") { viewModel.bridge.setBoolParameter(key: viewModel.bridge.findParameterKey("BP_SPEAK_WORDS"), value: true) }
                Button("Speech off") { viewModel.bridge.setBoolParameter(key: viewModel.bridge.findParameterKey("BP_SPEAK_WORDS"), value: false) }
            } label: {
                LucideIcon(isOn ? DasherIcon.speak : DasherIcon.mute)
            }
            if viewModel.speech.isSpeaking {
                Button(action: { viewModel.stopSpeech() }) {
                    LucideIcon(DasherIcon.stopSpeak, color: .red)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityPrompt: some View {
        VStack(spacing: 16) {
            LucideIcon("shield-check", size: 40, color: .secondary)
            Text("Accessibility Permission Required")
                .font(.headline)
            Text("Dasher needs accessibility access to send text to other applications.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            HStack(spacing: 12) {
                Button("Open System Settings") {
                    viewModel.directService.requestAccessibility()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Check Again") {
                    viewModel.directService.checkAccessibility()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func setFloatingWindow(_ floating: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
            if floating {
                window.level = .floating
                window.isOpaque = false
                window.hasShadow = false
                window.backgroundColor = .clear
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            } else {
                window.level = .normal
                window.isOpaque = true
                window.hasShadow = true
                window.backgroundColor = .windowBackgroundColor
                window.collectionBehavior = []
            }
        }
    }
}

// MARK: - Output Text View

struct MacOutputTextView: View {
    @ObservedObject var viewModel: MacDasherViewModel
    @Binding var paneSize: CGFloat
    let handleEdge: HandleEdge
    let availableSpace: CGFloat

    enum HandleEdge {
        case leading, trailing, top, bottom
    }

    private var minPane: CGFloat {
        handleEdge == .leading || handleEdge == .trailing ? 120 : 100
    }
    private var maxPane: CGFloat { availableSpace * 0.6 }

    var body: some View {
        GeometryReader { _ in
            switch handleEdge {
            case .leading:
                HStack(spacing: 0) {
                    dragHandle(axis: .horizontal)
                    Divider()
                    outputContent
                }
            case .trailing:
                HStack(spacing: 0) {
                    outputContent
                    Divider()
                    dragHandle(axis: .horizontal)
                }
            case .top:
                VStack(spacing: 0) {
                    dragHandle(axis: .vertical)
                    Divider()
                    outputContent
                }
            case .bottom:
                VStack(spacing: 0) {
                    outputContent
                    Divider()
                    dragHandle(axis: .vertical)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func dragHandle(axis: Axis) -> some View {
        let handleView = Group {
            switch axis {
            case .horizontal:
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 4, height: 28)
                    Spacer()
                }
                .frame(width: 10)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
            case .vertical:
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 28, height: 4)
                    Spacer()
                }
                .frame(height: 10)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                }
            }
        }

        return Color.clear
            .overlay(handleView)
            .frame(
                width: axis == .horizontal ? 10 : nil,
                height: axis == .vertical ? 10 : nil
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let delta: CGFloat
                        switch handleEdge {
                        case .leading: delta = -value.translation.width
                        case .trailing: delta = value.translation.width
                        case .top: delta = -value.translation.height
                        case .bottom: delta = value.translation.height
                        }
                        paneSize = min(maxPane, max(minPane, paneSize + delta))
                    }
            )
    }

    private var outputContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: {
                    let current = viewModel.bridge.getBoolParameter(key: viewModel.bridge.findParameterKey("BP_SPEAK_WORDS"))
                    viewModel.bridge.setBoolParameter(key: viewModel.bridge.findParameterKey("BP_SPEAK_WORDS"), value: !current)
                }) {
                    let isOn = viewModel.bridge.getBoolParameter(key: viewModel.bridge.findParameterKey("BP_SPEAK_WORDS"))
                    LucideIcon(isOn ? DasherIcon.speak : DasherIcon.mute, size: 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { copyAllText() }) {
                    LucideIcon(DasherIcon.copy, size: 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { pasteText() }) {
                    LucideIcon(DasherIcon.paste, size: 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { viewModel.newMessage() }) {
                    LucideIcon(DasherIcon.close, size: 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if viewModel.isGameModeActive && !viewModel.gameTargetText.isEmpty {
                macGameTargetBar
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.outputText)
                        .font(OutputFontSettings.font)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .id("outputText")
                }
                .onChange(of: viewModel.outputText) { _, _ in
                    withAnimation {
                        proxy.scrollTo("outputText", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func copyAllText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.outputText, forType: .string)
    }

    private func pasteText() {
        if let clipboardString = NSPasteboard.general.string(forType: .string) {
            viewModel.outputText += clipboardString
        }
    }

    private var macGameTargetBar: some View {
        let target = viewModel.gameTargetText
        let correct = viewModel.gameCorrectCount
        let wrong = viewModel.gameWrongText
        let correctIdx = target.index(target.startIndex, offsetBy: correct, limitedBy: target.endIndex) ?? target.endIndex
        let correctPart = String(target[..<correctIdx])
        let wrongCount = wrong.count
        let remainingIdx = target.index(target.startIndex, offsetBy: correct + wrongCount, limitedBy: target.endIndex) ?? target.endIndex
        let remainingPart = String(target[remainingIdx...])

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Target:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(correct)/\(viewModel.gameTargetLength)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 0) {
                if !correctPart.isEmpty {
                    Text(correctPart)
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                }
                if !wrong.isEmpty {
                    Text(wrong)
                        .foregroundColor(.red)
                        .strikethrough()
                }
                if !remainingPart.isEmpty {
                    Text(remainingPart)
                        .foregroundColor(.gray)
                }
            }
            .font(.body)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
    }
}

// MARK: - Canvas

struct MacCanvasView: NSViewRepresentable {
    @ObservedObject var viewModel: MacDasherViewModel

    func makeNSView(context: Context) -> MacDasherCanvas {
        let canvas = MacDasherCanvas()
        canvas.viewModel = viewModel
        return canvas
    }

    func updateNSView(_ nsView: MacDasherCanvas, context: Context) {
        nsView.viewModel = viewModel
    }
}

final class MacDasherCanvas: NSView {
    var viewModel: MacDasherViewModel?
    private var timer: Timer?
    private var mouseIsDown = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = .clear
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layout() {
        super.layout()
        viewModel?.setCanvasSize(bounds.size)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.needsDisplay = true
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseIsDown = true
        let point = convert(event.locationInWindow, from: nil)
        viewModel?.handleTouch(at: CGPoint(x: point.x, y: bounds.height - point.y))
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        viewModel?.handleTouch(at: CGPoint(x: point.x, y: bounds.height - point.y))
    }

    override func mouseUp(with event: NSEvent) {
        mouseIsDown = false
        viewModel?.handleTouchEnd()
    }

    override func mouseExited(with event: NSEvent) {
        // Stop Dasher when the pointer leaves the canvas while dragging.
        // Implements BP_STOP_OUTSIDE at the frontend level — without this,
        // mouseDragged stops firing when the cursor exits the view, leaving
        // DasherCore stuck at the last in-bounds position (keeps zooming).
        if mouseIsDown {
            viewModel?.handleTouchEnd()
            mouseIsDown = false
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        viewModel?.bridge.keyEvent(key: 101, pressed: true)
    }

    override func rightMouseUp(with event: NSEvent) {
        viewModel?.bridge.keyEvent(key: 101, pressed: false)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let vm = viewModel else { return }

        ctx.setFillColor(CGColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0))
        ctx.fill(dirtyRect)

        let timeMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        if let cmds = vm.bridge.frame(timeMs: timeMs) {
            cmds.render(in: ctx, bounds: bounds, viewHeight: bounds.height)
        }
        vm.outputText = vm.bridge.getOutputText()
        vm.syncGameModeState()
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
