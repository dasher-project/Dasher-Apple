import SwiftUI

struct VisionCanvasView: UIViewRepresentable {
    @ObservedObject var viewModel: VisionViewModel

    func makeUIView(context: Context) -> VisionCanvas {
        let canvas = VisionCanvas()
        canvas.viewModel = viewModel
        return canvas
    }

    func updateUIView(_ uiView: VisionCanvas, context: Context) {
        uiView.viewModel = viewModel
    }
}

final class VisionCanvas: UIView {
    var viewModel: VisionViewModel?
    private var displayLink: CADisplayLink?

    private var hoverTimer: Timer?
    private var dwellStartTime: CFTimeInterval = 0
    private var lastHoverPoint: CGPoint = .zero
    private var isDwelling: Bool = false
    private var dwellProgress: CGFloat = 0
    private let dwellRadius: CGFloat = 20
    private var gazeMouseIsDown = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .black

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hover)
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

    // MARK: - Touch input (pinch gesture on visionOS)
    // When pointer hover is OFF: pinch to start, look while pinching, release to stop.

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let vm = viewModel, !vm.pointerHoverEnabled else { return }
        cancelDwell()
        guard let touch = touches.first else { return }
        vm.handleTouch(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let vm = viewModel, !vm.pointerHoverEnabled else { return }
        guard let touch = touches.first else { return }
        vm.handleTouchMove(at: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let vm = viewModel, !vm.pointerHoverEnabled else { return }
        vm.handleTouchEnd()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let vm = viewModel, !vm.pointerHoverEnabled else { return }
        vm.handleTouchEnd()
    }

    // MARK: - Eye gaze input (native on visionOS — eyes drive Dasher directly)

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        guard let vm = viewModel, vm.pointerHoverEnabled else { return }
        let point = gesture.location(in: self)

        switch gesture.state {
        case .began:
            // Gaze entered canvas → start Dasher zooming
            gazeMouseIsDown = true
            vm.bridge.mouseDown()
            vm.bridge.mouseMove(x: Float(point.x), y: Float(point.y))
            cancelDwell()

        case .changed:
            // Continuous gaze → steer Dasher
            if !gazeMouseIsDown {
                gazeMouseIsDown = true
                vm.bridge.mouseDown()
            }
            vm.bridge.mouseMove(x: Float(point.x), y: Float(point.y))

            // Dwell-to-select (for selecting nodes, not for zooming)
            let distance = hypot(point.x - lastHoverPoint.x, point.y - lastHoverPoint.y)
            if distance > dwellRadius {
                if vm.appLevelDwell { startDwell(point: point) }
            }

        case .ended, .cancelled:
            // Gaze left canvas → pause Dasher
            if gazeMouseIsDown {
                gazeMouseIsDown = false
                vm.bridge.mouseUp()
            }
            cancelDwell()

        default:
            break
        }
    }

    // MARK: - Dwell-to-select

    private func startDwell(point: CGPoint) {
        isDwelling = true
        dwellStartTime = CACurrentMediaTime()
        lastHoverPoint = point
        dwellProgress = 0

        hoverTimer?.invalidate()
        let tickInterval = 1.0 / 60.0

        hoverTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateDwell()
        }
    }

    private func updateDwell() {
        guard isDwelling else { return }
        let elapsed = CACurrentMediaTime() - dwellStartTime
        let duration = viewModel?.dwellDuration ?? 0.5
        dwellProgress = CGFloat(elapsed / duration)

        if dwellProgress >= 1.0 {
            dwellProgress = 1.0
            isDwelling = false
            hoverTimer?.invalidate()
            hoverTimer = nil

            viewModel?.handleTouch(at: lastHoverPoint)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.viewModel?.handleTouchEnd()
                self?.dwellProgress = 0
                self?.setNeedsDisplay()
            }
        }

        setNeedsDisplay()
    }

    private func cancelDwell() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        isDwelling = false
        dwellProgress = 0
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let vm = viewModel else { return }

        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(rect)

        let timeMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        if let cmds = vm.bridge.frame(timeMs: timeMs) {
            cmds.render(in: ctx, bounds: bounds)
        }

        vm.syncGameModeState()

        if vm.pointerHoverEnabled && vm.appLevelDwell && isDwelling && dwellProgress > 0 {
            drawDwellIndicator(in: ctx)
        }
    }

    private func drawDwellIndicator(in ctx: CGContext) {
        let center = lastHoverPoint
        let radius: CGFloat = 22

        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(3)
        ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2))
        ctx.strokePath()

        let startAngle = -CGFloat.pi / 2
        let endAngle = startAngle + (2 * CGFloat.pi * dwellProgress)

        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.setLineWidth(3)
        ctx.setLineCap(.round)
        ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        ctx.strokePath()
    }
}
