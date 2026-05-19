import SwiftUI

struct DasherCanvasView: View {
    @ObservedObject var viewModel: DasherViewModel

    var body: some View {
        DasherCanvasRepresentable(viewModel: viewModel)
            .background(Color(UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0)))
    }
}

struct DasherCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: DasherViewModel

    func makeUIView(context: Context) -> DasherCanvas {
        let canvas = DasherCanvas()
        canvas.viewModel = viewModel
        return canvas
    }

    func updateUIView(_ uiView: DasherCanvas, context: Context) {
        uiView.viewModel = viewModel
    }
}

final class DasherCanvas: UIView {
    var viewModel: DasherViewModel?
    private var displayLink: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let vm = viewModel {
            vm.setCanvasSize(bounds.size)
            if displayLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(tick))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        viewModel?.handleTouch(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        viewModel?.handleTouch(at: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        viewModel?.handleTouchEnd()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        viewModel?.handleTouchEnd()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let vm = viewModel else { return }

        ctx.setFillColor(UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0).cgColor)
        ctx.fill(rect)

        let timeMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        if let cmds = vm.bridge.frame(timeMs: timeMs) {
            cmds.render(in: ctx, bounds: bounds)
        }

        vm.outputText = vm.bridge.getOutputText()
    }
}
