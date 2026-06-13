import SwiftUI

struct DasherCanvasView: View {
    @ObservedObject var viewModel: DasherViewModel

    var body: some View {
        DasherCanvasRepresentable(viewModel: viewModel)
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

    private var hoverTimer: Timer?
    private var dwellStartTime: CFTimeInterval = 0
    private var lastHoverPoint: CGPoint = .zero
    private var isDwelling: Bool = false
    private var dwellProgress: CGFloat = 0
    private var isHovering: Bool = false

    private let dwellRadius: CGFloat = 20

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = UIColor(named: "CanvasBackground") ?? UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0)

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
        guard let vm = viewModel, vm.isPlaying else { return }
        setNeedsDisplay()
    }

    // MARK: - Touch input (finger/stylus)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelDwell()
        guard let vm = viewModel, vm.isPlaying else { return }
        guard let touch = touches.first else { return }
        vm.handleTouch(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let vm = viewModel, vm.isPlaying else { return }
        guard let touch = touches.first else { return }
        vm.handleTouchMove(at: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let vm = viewModel, vm.isPlaying else { return }
        vm.handleTouchEnd()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let vm = viewModel, vm.isPlaying else { return }
        vm.handleTouchEnd()
    }

    // MARK: - Hover input (eye gaze / pointer / assistive devices)

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        guard let vm = viewModel, vm.pointerHoverEnabled else { return }
        let point = gesture.location(in: self)

        switch gesture.state {
        case .began:
            isHovering = true
            lastHoverPoint = point
            vm.handlePointerHover(at: point)
            if vm.isContinuousSelection {
                vm.handleHoverDown(at: point)
            } else if vm.appLevelDwell {
                startDwell(point: point)
            }

        case .changed:
            let prevPoint = lastHoverPoint
            vm.handlePointerHover(at: point)
            lastHoverPoint = point

            if !vm.isContinuousSelection && vm.appLevelDwell {
                let distance = hypot(point.x - prevPoint.x, point.y - prevPoint.y)
                if distance > dwellRadius {
                    resetDwell(point: point)
                } else if !isDwelling {
                    startDwell(point: point)
                }
            }

        case .ended, .cancelled:
            isHovering = false
            cancelDwell()
            if vm.isContinuousSelection {
                vm.handleHoverUp()
            } else {
                vm.handleTouchEnd()
            }

        default:
            break
        }
    }

    // MARK: - Dwell-to-click

    private func startDwell(point: CGPoint) {
        isDwelling = true
        dwellStartTime = CACurrentMediaTime()
        lastHoverPoint = point
        dwellProgress = 0

        hoverTimer?.invalidate()
        let _ = viewModel?.dwellDuration ?? 0.5
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

    private func resetDwell(point: CGPoint) {
        hoverTimer?.invalidate()
        hoverTimer = nil
        isDwelling = false
        dwellProgress = 0
        dwellStartTime = CACurrentMediaTime()
        lastHoverPoint = point
        startDwell(point: point)
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

        ctx.setFillColor((UIColor(named: "CanvasBackground") ?? UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0)).cgColor)
        ctx.fill(rect)

        if vm.isPlaying {
            let timeMs = Int64(Date().timeIntervalSince1970 * 1000.0)
            if let cmds = vm.bridge.frame(timeMs: timeMs) {
                cmds.render(in: ctx, bounds: bounds)
            }
            vm.outputText = vm.bridge.getOutputText()
            vm.syncGameModeState()
        } else {
            if let cmds = vm.bridge.frame(timeMs: Int64(Date().timeIntervalSince1970 * 1000.0)) {
                cmds.render(in: ctx, bounds: bounds)
            }
        }

        if vm.pointerHoverEnabled && isHovering {
            if vm.appLevelDwell && isDwelling && dwellProgress > 0 {
                drawDwellIndicator(in: ctx)
            } else if vm.isContinuousSelection {
                drawHoverIndicator(in: ctx)
            }
        }
    }

    private func drawDwellIndicator(in ctx: CGContext) {
        let center = lastHoverPoint
        let radius: CGFloat = 18

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

    private func drawHoverIndicator(in ctx: CGContext) {
        let center = lastHoverPoint
        let radius: CGFloat = 4

        ctx.setFillColor(UIColor.white.withAlphaComponent(0.5).cgColor)
        ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2))
        ctx.fillPath()
    }
}
