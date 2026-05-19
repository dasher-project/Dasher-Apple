import SwiftUI

struct KeyboardContentView: View {
    @ObservedObject var viewModel: KeyboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                KeyboardCanvasView(viewModel: viewModel)
            }

            HStack(spacing: 8) {
                Button(action: {
                    let s = max(20, viewModel.bridge.speedPercent - 10)
                    viewModel.bridge.setSpeedPercent(s)
                }) {
                    Text("-").frame(width: 28, height: 28)
                }
                Text("\(viewModel.bridge.speedPercent)%")
                    .font(.system(size: 12, design: .monospaced))
                Button(action: {
                    let s = min(400, viewModel.bridge.speedPercent + 10)
                    viewModel.bridge.setSpeedPercent(s)
                }) {
                    Text("+").frame(width: 28, height: 28)
                }
                Spacer()
                Button(action: { viewModel.advanceToNextInputMode() }) {
                    Text("🌐").font(.system(size: 20))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(red: 0.95, green: 0.95, blue: 0.95))
        }
    }
}

struct KeyboardCanvasView: UIViewRepresentable {
    @ObservedObject var viewModel: KeyboardViewModel

    func makeUIView(context: Context) -> KeyboardCanvas {
        let canvas = KeyboardCanvas()
        canvas.viewModel = viewModel
        return canvas
    }

    func updateUIView(_ uiView: KeyboardCanvas, context: Context) {
        uiView.viewModel = viewModel
    }
}

final class KeyboardCanvas: UIView {
    var viewModel: KeyboardViewModel?
    private var displayLink: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layoutSubviews() {
        super.layoutSubviews()
        viewModel?.setCanvasSize(bounds.size)
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        viewModel?.bridge.mouseDown()
        viewModel?.bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        viewModel?.bridge.mouseMove(x: Float(point.x), y: Float(point.y))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        viewModel?.bridge.mouseUp()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let vm = viewModel else { return }

        ctx.setFillColor(UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0).cgColor)
        ctx.fill(rect)

        let timeMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        if let cmds = vm.bridge.frame(timeMs: timeMs) {
            cmds.render(in: ctx, bounds: bounds)
        }

        if let newText = vm.bridge.getNewOutput() {
            vm.textDocumentProxy?.insertText(newText)
        }
    }
}
