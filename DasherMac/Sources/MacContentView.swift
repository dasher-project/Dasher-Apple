import SwiftUI

struct MacContentView: View {
    @ObservedObject var viewModel: MacDasherViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    Button("New") { viewModel.newMessage() }
                        .buttonStyle(.bordered)
                    Button(viewModel.isPlaying ? "Pause" : "Play") { viewModel.togglePlay() }
                        .buttonStyle(.bordered)
                        .tint(viewModel.isPlaying ? .teal : .blue)
                }
                Spacer()
                Button(viewModel.showMessagePane ? "Hide Pane" : "Show Pane") {
                    withAnimation { viewModel.showMessagePane.toggle() }
                }.buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            GeometryReader { geo in
                HStack(spacing: 0) {
                    MacCanvasView(viewModel: viewModel)
                        .frame(width: viewModel.showMessagePane ? geo.size.width * 0.65 : geo.size.width)

                    if viewModel.showMessagePane {
                        Divider()
                        ScrollView {
                            Text(viewModel.outputText)
                                .font(.system(size: 18))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(width: geo.size.width * 0.35 - 1)
                        .background(Color(nsColor: .textBackgroundColor))
                    }
                }
            }

            Divider()

            HStack(spacing: 16) {
                Text("Speed").foregroundColor(.secondary)
                Button("-") { viewModel.decreaseSpeed() }
                Text(String(format: "%.1f", viewModel.speed))
                    .monospacedDigit()
                Button("+") { viewModel.increaseSpeed() }
                Spacer()
                Text("Colour").foregroundColor(.secondary)
                HStack(spacing: 6) {
                    ForEach(0..<viewModel.colourPresets.count, id: \.self) { index in
                        Button(action: { viewModel.selectedColourIndex = index }) {
                            Circle()
                                .fill(viewModel.colourPresets[index].1)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().stroke(viewModel.selectedColourIndex == index ? Color.accentColor : Color.clear, lineWidth: 2))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

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

        if vm.isPlaying {
            let timeMs = Int64(Date().timeIntervalSince1970 * 1000.0)
            if let cmds = vm.bridge.frame(timeMs: timeMs) {
                cmds.render(in: ctx, bounds: bounds, viewHeight: bounds.height)
            }
            vm.outputText = vm.bridge.getOutputText()
        } else {
            let timeMs = Int64(Date().timeIntervalSince1970 * 1000.0)
            if let cmds = vm.bridge.frame(timeMs: timeMs) {
                cmds.render(in: ctx, bounds: bounds, viewHeight: bounds.height)
            }
        }
    }
}
