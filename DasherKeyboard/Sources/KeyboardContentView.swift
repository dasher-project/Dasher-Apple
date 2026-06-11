import SwiftUI

struct KeyboardContentView: View {
    @ObservedObject var viewModel: KeyboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            KeyboardCanvasView(viewModel: viewModel)

            Divider()

            HStack(spacing: 8) {
                Button(action: { viewModel.decreaseSpeed() }) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(white: 0.9)))
                }
                .buttonStyle(.plain)

                Text("\(viewModel.bridge.speedPercent)%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)

                Button(action: { viewModel.increaseSpeed() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(white: 0.9)))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { viewModel.bridge.reset() }) {
                    Image(systemName: "delete.left")
                        .font(.system(size: 13))
                        .frame(width: 32, height: 28)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.9)))
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.advanceToNextInputMode() }) {
                    Image(systemName: "globe")
                        .font(.system(size: 15))
                        .frame(width: 32, height: 28)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.9)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(white: 0.95))
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

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
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
    }
}
