import SwiftUI
import UniformTypeIdentifiers

struct MacContentView: View {
    @ObservedObject var viewModel: MacDasherViewModel
    @State private var showSettings = false
    @State private var currentLayoutPosition = "Right"
    @State private var outputPaneFraction: CGFloat = 2.0 / 9.0

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
        .alert(
            viewModel.pendingMessage?.isWarning == true ? "Dasher Warning" : "Dasher",
            isPresented: Binding(
                get: { viewModel.pendingMessage != nil },
                set: { if !$0 { viewModel.pendingMessage = nil } }
            ),
            presenting: viewModel.pendingMessage
        ) { _ in
            Button("OK") { viewModel.pendingMessage = nil }
        } message: { msg in
            Text(msg.text)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { viewModel.newMessage() }) {
                    Label("New", systemImage: "doc.badge.plus")
                }
                Button(action: { viewModel.togglePlay() }) {
                    Label(viewModel.isPlaying ? "Pause" : "Play",
                          systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill")
                }

                if currentLayoutPosition != "Direct" {
                    Button(action: { viewModel.toggleGameMode() }) {
                        Label(viewModel.isGameModeActive ? "Game On" : "Game Mode",
                              systemImage: viewModel.isGameModeActive ? "gamecontroller.fill" : "gamecontroller")
                    }
                }

                layoutPickerMenu

                Button(action: { showSettings = true }) {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
            }
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
            Label(currentLayoutPosition, systemImage: layoutIcon)
        }
    }

    private var layoutIcon: String {
        switch currentLayoutPosition {
        case "Right": return "sidebar.right"
        case "Left": return "sidebar.left"
        case "Bottom": return "rectangle.split.1x2"
        case "Top": return "rectangle.split.1x2"
        case "Direct": return "keyboard"
        default: return "sidebar.right"
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
            } else {
                ZStack(alignment: .topTrailing) {
                    MacCanvasView(viewModel: viewModel)
                    targetAppIndicator.padding(8)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "textbox")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
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
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.6)))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            alphabetPicker
            barDivider
            speedStepper
            barDivider
            learningToggle
            barDivider
            palettePicker
            barDivider
            fontPicker
            barDivider
            fontSizeStepper
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
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
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
            get: { viewModel.bridge.getBoolParameter(key: 15) },
            set: { viewModel.bridge.setBoolParameter(key: 15, value: $0) }
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

    private var palettePicker: some View {
        let palettes = viewModel.bridge.allPalettes
        return Menu {
            ForEach(palettes, id: \.name) { p in
                Button(action: { viewModel.bridge.setPalette(p.name) }) {
                    Label(p.name, systemImage: "circle.fill")
                }
            }
        } label: {
            Image(systemName: "paintpalette")
        }
    }

    private var fontPicker: some View {
        let fontValues = viewModel.bridge.getStringValues(key: 99)
        let currentFont = viewModel.bridge.getStringParameter(key: 99)
        return Menu {
            ForEach(fontValues, id: \.self) { f in
                Button(f) { viewModel.bridge.setStringParameter(key: 99, value: f) }
            }
        } label: {
            HStack(spacing: 3) {
                Text(currentFont)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var fontSizeStepper: some View {
        let binding = Binding<Int>(
            get: { viewModel.bridge.getLongParameter(key: 33) },
            set: { viewModel.bridge.setLongParameter(key: 33, value: $0) }
        )
        return HStack(spacing: 4) {
            Text("Size")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Button("-") { viewModel.bridge.setLongParameter(key: 33, value: max(8, binding.wrappedValue - 1)) }
            Text("\(binding.wrappedValue)")
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 24)
            Button("+") { viewModel.bridge.setLongParameter(key: 33, value: min(72, binding.wrappedValue + 1)) }
        }
    }

    private var speechPicker: some View {
        let isOn = viewModel.bridge.getBoolParameter(key: 24)
        return Menu {
            Button("Speech on") { viewModel.bridge.setBoolParameter(key: 24, value: true) }
            Button("Speech off") { viewModel.bridge.setBoolParameter(key: 24, value: false) }
        } label: {
            Image(systemName: isOn ? "speaker.wave.2.fill" : "speaker.slash")
        }
    }

    // MARK: - Accessibility

    private var accessibilityPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
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
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.isKeyWindow }) else { return }
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
        GeometryReader { geo in
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
                    let current = viewModel.bridge.getBoolParameter(key: 24)
                    viewModel.bridge.setBoolParameter(key: 24, value: !current)
                }) {
                    let isOn = viewModel.bridge.getBoolParameter(key: 24)
                    Image(systemName: isOn ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { copyAllText() }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { viewModel.newMessage() }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.outputText)
                        .font(.system(size: 18))
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

    override init(frame: CGRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layout() {
        super.layout()
        viewModel?.setCanvasSize(bounds.size)
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
        let point = convert(event.locationInWindow, from: nil)
        viewModel?.handleTouch(at: CGPoint(x: point.x, y: bounds.height - point.y))
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        viewModel?.handleTouch(at: CGPoint(x: point.x, y: bounds.height - point.y))
    }

    override func mouseUp(with event: NSEvent) {
        viewModel?.handleTouchEnd()
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
