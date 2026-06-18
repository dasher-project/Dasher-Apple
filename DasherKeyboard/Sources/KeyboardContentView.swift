import UIKit
import os.log

final class KeyboardCanvas: UIView {
    var viewModel: KeyboardViewModel?
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var hasLoggedFirstTick = false
    private var hasLoggedFirstDraw = false
    private var hasLoggedLayout = false
    private var needsRedraw = true  // start true so we paint one initial frame

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    deinit {
        displayLink?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        viewModel?.setCanvasSize(bounds.size)

        if !hasLoggedLayout, let sv = superview {
            hasLoggedLayout = true
            os_log("layout: self.bounds=%{public}f x %{public}f, frame=(%{public}f,%{public}f), superview.bounds=%{public}f x %{public}f",
                   log: keyboardLog,
                   bounds.width, bounds.height,
                   frame.origin.x, frame.origin.y,
                   sv.bounds.width, sv.bounds.height)
        }

        // Wait to start the display link until the user actually touches the
        // canvas. This keeps the model idle (no NewFrame() calls) until input
        // arrives, which avoids per-frame memory growth on the launch path.
        if displayLink == nil, bounds.height > 100 {
            let proxy = DisplayLinkProxy(self)
            let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
            // Cap at 30 FPS to halve per-second allocation pressure.
            link.preferredFramesPerSecond = 30
            link.add(to: .main, forMode: .common)
            displayLinkProxy = proxy
            displayLink = link
        }
    }

    @objc func tick() {
        // Only redraw when something changed. Without this, the displayLink
        // fires 30 times/sec, each tick triggering a NewFrame() in Dasher
        // which expands the node tree and grows memory until iOS shrinks
        // the keyboard in response.
        guard needsRedraw else { return }
        needsRedraw = false
        if !hasLoggedFirstTick {
            hasLoggedFirstTick = true
            os_log("CADisplayLink first tick (canvas %{public}f x %{public}f)", log: keyboardLog, bounds.width, bounds.height)
        }
        setNeedsDisplay()
    }

    /// Mark the canvas as needing a redraw on the next display link tick.
    func requestRedraw() {
        needsRedraw = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        viewModel?.bridge.mouseDown()
        viewModel?.bridge.mouseMove(x: Float(point.x), y: Float(point.y))
        needsRedraw = true
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        viewModel?.bridge.mouseMove(x: Float(point.x), y: Float(point.y))
        needsRedraw = true
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        viewModel?.bridge.mouseUp()
        needsRedraw = true
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        viewModel?.bridge.mouseUp()
        needsRedraw = true
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let vm = viewModel else { return }

        let isFirstDraw = !hasLoggedFirstDraw
        if isFirstDraw {
            os_log("draw(_) first call, rect=%{public}f x %{public}f", log: keyboardLog, rect.width, rect.height)
            hasLoggedFirstDraw = true
        }

        ctx.setFillColor(UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1.0).cgColor)
        ctx.fill(rect)

        let timeMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        if let cmds = vm.bridge.frame(timeMs: timeMs) {
            cmds.render(in: ctx, bounds: bounds)
        }
    }
}

/// Weak proxy target for CADisplayLink to avoid the retain cycle created by
/// CADisplayLink retaining its target while the view retains the link.
private final class DisplayLinkProxy {
    weak var target: KeyboardCanvas?
    init(_ target: KeyboardCanvas) { self.target = target }
    @objc func tick(_ link: CADisplayLink) {
        target?.tick()
    }
}
