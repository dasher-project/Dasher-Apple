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

final class VisionCanvas: UIView, UIPointerInteractionDelegate {
    var viewModel: VisionViewModel?
    private var displayLink: CADisplayLink?

    private var hoverTimer: Timer?
    private var dwellStartTime: CFTimeInterval = 0
    private var lastHoverPoint: CGPoint = .zero
    private var isDwelling: Bool = false
    private var dwellProgress: CGFloat = 0
    private var isHovering: Bool = false
    private let dwellRadius: CGFloat = 20

    // MARK: - Debug telemetry (always on for now — we need data, not theories)
    // Toggled from the Settings > Diagnostics "Show Input Debug" switch.
    private var hoverBeganCount = 0
    private var hoverChangedCount = 0
    private var hoverEndedCount = 0
    private var touchBeganCount = 0
    private var touchMovedCount = 0
    private var pointerEnterCount = 0
    private var pointerMoveCount = 0
    private var pointerExitCount = 0
    private var lastState: String = "idle"
    private var lastReportedPoint: CGPoint = .zero
    private var lastEventTime: CFTimeInterval = 0

    var debugOverlayEnabled: Bool {
        viewModel?.debugInputOverlay ?? false
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .black

        // UIHoverGestureRecognizer — Apple's documented visionOS gaze API.
        // Confirmed to deliver ZERO events in a windowed app (log analysis).
        // Kept for forward compatibility if Apple changes this.
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hover)

        // UIPointerInteraction — architecturally different from hover gestures.
        // Uses a delegate pattern with pointerEnter/Move/Exit callbacks. On
        // visionOS this MIGHT bridge to gaze where hover gestures don't.
        // This is the experiment: if these counts climb when you look around,
        // we've found our gaze API.
        let pointer = UIPointerInteraction(delegate: self)
        pointer.isEnabled = true
        addInteraction(pointer)
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

    // MARK: - Touch input (pinch — follows HAND position, not gaze)
    // On visionOS, pinch-and-hold generates touchesMoved whose coordinates
    // follow where the pinch is in 3D space (hand position), NOT where the
    // eyes are looking. This is how all visionOS drag gestures work — the
    // element follows the hand. Gaze is used only by the system for visual
    // highlighting, not exposed as continuous coordinates to the app.
    // Touch is ALWAYS enabled; it is not gated on pointerHoverEnabled.

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchBeganCount += 1
        lastState = "touch.began"
        lastEventTime = CACurrentMediaTime()
        guard let vm = viewModel else { return }
        cancelDwell()
        guard let touch = touches.first else { return }
        vm.handleTouch(at: touch.location(in: self))
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchMovedCount += 1
        lastState = "touch.moved"
        lastEventTime = CACurrentMediaTime()
        guard let vm = viewModel else { return }
        guard let touch = touches.first else { return }
        let p = touch.location(in: self)
        lastReportedPoint = p
        vm.handleTouchMove(at: p)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastState = "touch.ended"
        lastEventTime = CACurrentMediaTime()
        guard let vm = viewModel else { return }
        vm.handleTouchEnd()
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastState = "touch.cancelled"
        lastEventTime = CACurrentMediaTime()
        guard let vm = viewModel else { return }
        vm.handleTouchEnd()
        setNeedsDisplay()
    }

    // MARK: - Eye gaze input (UIHoverGestureRecognizer == eye gaze on visionOS)
    // Ported from DasherApp/Sources/DasherCanvasView.swift.
    // Continuous-selection model: look to zoom, look away to pause.

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        guard let vm = viewModel, vm.pointerHoverEnabled else { return }
        let point = gesture.location(in: self)
        lastReportedPoint = point
        lastEventTime = CACurrentMediaTime()

        switch gesture.state {
        case .began:
            hoverBeganCount += 1
            lastState = "hover.began"
            isHovering = true
            lastHoverPoint = point
            vm.handlePointerHover(at: point)
            if vm.isContinuousSelection {
                // Continuous gaze → engage zoom immediately, no pinch needed.
                vm.handleHoverDown(at: point)
            } else if vm.appLevelDwell {
                startDwell(point: point)
            }

        case .changed:
            hoverChangedCount += 1
            lastState = "hover.changed"
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
            hoverEndedCount += 1
            lastState = "hover.ended"
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
        setNeedsDisplay()
    }

    // MARK: - UIPointerInteractionDelegate (experiment: does this bridge to gaze?)

    func pointerInteraction(_ interaction: UIPointerInteraction,
                            regionFor request: UIPointerRegionRequest,
                            defaultRegion: UIPointerRegion) -> UIPointerRegion? {
        // Accept the default region — we want to receive pointer events over
        // the entire canvas.
        pointerEnterCount += 1
        lastState = "pointer.region"
        lastEventTime = CACurrentMediaTime()
        setNeedsDisplay()
        return defaultRegion
    }

    func pointerInteraction(_ interaction: UIPointerInteraction,
                            styleFor region: UIPointerRegion) -> UIPointerStyle? {
        // Return nil to suppress the system's default hover visual; Dasher
        // draws its own crosshair.
        return nil
    }

    // MARK: - Dwell-to-click (kept for parity; continuous mode is the default)

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

        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(rect)

        let timeMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        if let cmds = vm.bridge.frame(timeMs: timeMs) {
            cmds.render(in: ctx, bounds: bounds)
        }

        vm.syncGameModeState()

        if vm.pointerHoverEnabled && isHovering {
            if vm.appLevelDwell && isDwelling && dwellProgress > 0 {
                drawDwellIndicator(in: ctx)
            } else if vm.isContinuousSelection {
                drawHoverIndicator(in: ctx)
            }
        }

        if debugOverlayEnabled {
            drawDebugOverlay(in: ctx)
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

    private func drawHoverIndicator(in ctx: CGContext) {
        // Small white dot at the current gaze point so we can see whether
        // hover coordinates are arriving and where Dasher thinks we're looking.
        let center = lastHoverPoint
        let radius: CGFloat = 5

        ctx.setFillColor(UIColor.white.withAlphaComponent(0.6).cgColor)
        ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2))
        ctx.fillPath()
    }

    // MARK: - Debug overlay
    // Draws a panel top-left with: last event type, (x,y), event counts,
    // canvas size, seconds since last event. If you see this update when
    // you look around, hover events ARE firing and we have a coordinate
    // problem. If it stays frozen, hover is NOT firing and we have an
    // input- plumbing problem.

    private func drawDebugOverlay(in ctx: CGContext) {
        let secsSinceEvent = lastEventTime == 0 ? -1 : CACurrentMediaTime() - lastEventTime
        let canvasW = bounds.width
        let canvasH = bounds.height

        let lines: [String] = [
            "VISION INPUT DEBUG",
            "state: \(lastState)",
            "point: (\(Int(lastReportedPoint.x)), \(Int(lastReportedPoint.y)))",
            "canvas: \(Int(canvasW))×\(Int(canvasH))",
            "hover: began=\(hoverBeganCount) changed=\(hoverChangedCount) ended=\(hoverEndedCount)",
            "touch: began=\(touchBeganCount) moved=\(touchMovedCount)",
            "pointer: enter=\(pointerEnterCount) move=\(pointerMoveCount) exit=\(pointerExitCount)",
            "since last event: \(String(format: "%.2f", secsSinceEvent))s",
            "pointerHoverEnabled: \(viewModel?.pointerHoverEnabled ?? false)",
            "isContinuousSelection: \(viewModel?.isContinuousSelection ?? false)",
            "selection: \(viewModel?.selectionMethod.rawValue ?? "?")"
        ]

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Menlo", size: 12) ?? UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.green
        ]

        let panelWidth: CGFloat = 360
        let lineHeight: CGFloat = 15
        let panelHeight = lineHeight * CGFloat(lines.count) + 16
        let panelRect = CGRect(x: 16, y: 16, width: panelWidth, height: panelHeight)

        ctx.setFillColor(UIColor.black.withAlphaComponent(0.75).cgColor)
        ctx.fill(panelRect)
        ctx.setStrokeColor(UIColor.green.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(panelRect)

        let textOriginY = panelRect.maxY - 10
        for (i, line) in lines.enumerated() {
            let lineY = textOriginY - CGFloat(i + 1) * lineHeight
            (line as NSString).draw(
                at: CGPoint(x: panelRect.minX + 8, y: lineY),
                withAttributes: attrs
            )
        }
    }
}
