import UIKit
import os.log

class KeyboardViewController: UIInputViewController {
    private var canvas: KeyboardCanvas?
    private var speedLabel: UILabel?
    private var viewModel: KeyboardViewModel?

    override func viewDidLoad() {
        super.viewDidLoad()

        // RFC 0008 heartbeat: tell the host app the keyboard was activated by the
        // system, and whether Full Access is on. iOS exposes no public API for
        // "is the keyboard enabled", so the host app reads this to drive its
        // enablement onboarding. Keys must match DasherShared.KeyboardOnboarding.
        if let group = UserDefaults(suiteName: "group.at.dasher.Dasher") {
            group.set(Date(), forKey: "keyboardActivatedAt")
            group.set(hasFullAccess, forKey: "keyboardHasFullAccess")
        }

        let vm = KeyboardViewModel(textDocumentProxy: textDocumentProxy)
        vm.onAdvanceInputMode = { [weak self] in
            self?.advanceToNextInputMode()
        }
        viewModel = vm

        let canvasView = KeyboardCanvas()
        canvasView.viewModel = vm
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvasView)
        canvas = canvasView

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = .separator
        view.addSubview(divider)

        let toolbar = UIView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        view.addSubview(toolbar)

        let minusBtn = makeButton(systemName: "minus", action: #selector(speedDown))
        let plusBtn = makeButton(systemName: "plus", action: #selector(speedUp))
        let resetBtn = makeButton(systemName: "delete.left", action: #selector(resetTapped))
        let globeBtn = makeButton(systemName: "globe", action: #selector(nextKeyboard))

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.text = "\(vm.bridge.speedPercent)%"
        label.textColor = .label
        toolbar.addSubview(label)
        speedLabel = label

        toolbar.addSubview(minusBtn)
        toolbar.addSubview(plusBtn)
        toolbar.addSubview(resetBtn)
        toolbar.addSubview(globeBtn)

        NSLayoutConstraint.activate([
            canvasView.topAnchor.constraint(equalTo: view.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            divider.topAnchor.constraint(equalTo: canvasView.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            toolbar.topAnchor.constraint(equalTo: divider.bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),

            minusBtn.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            minusBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            minusBtn.widthAnchor.constraint(equalToConstant: 28),
            minusBtn.heightAnchor.constraint(equalToConstant: 28),

            label.leadingAnchor.constraint(equalTo: minusBtn.trailingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            plusBtn.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            plusBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            plusBtn.widthAnchor.constraint(equalToConstant: 28),
            plusBtn.heightAnchor.constraint(equalToConstant: 28),

            globeBtn.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            globeBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            globeBtn.widthAnchor.constraint(equalToConstant: 32),
            globeBtn.heightAnchor.constraint(equalToConstant: 28),

            resetBtn.trailingAnchor.constraint(equalTo: globeBtn.leadingAnchor, constant: -8),
            resetBtn.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            resetBtn.widthAnchor.constraint(equalToConstant: 32),
            resetBtn.heightAnchor.constraint(equalToConstant: 28),
        ])

        // Critical for keyboard extensions: declare the desired keyboard
        // height via an explicit Auto Layout constraint. Without this, iOS
        // computes the extension's required height as just the toolbar (44pt)
        // and collapses the canvas to 0. Use a high but not required priority
        // so iOS can adjust on devices where 320 wouldn't fit.
        let keyboardHeight = view.heightAnchor.constraint(equalToConstant: 320)
        keyboardHeight.priority = .defaultHigh
        keyboardHeight.isActive = true
    }

    private func makeButton(systemName: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(systemName: systemName), for: .normal)
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    @objc private func speedDown() {
        viewModel?.decreaseSpeed()
        updateSpeedLabel()
    }

    @objc private func speedUp() {
        viewModel?.increaseSpeed()
        updateSpeedLabel()
    }

    @objc private func resetTapped() {
        viewModel?.bridge.setSystemAppearance(dark: traitCollection.userInterfaceStyle == .dark)
        viewModel?.bridge.reset()
    }

    @objc private func nextKeyboard() {
        viewModel?.advanceToNextInputMode()
    }

    private func updateSpeedLabel() {
        speedLabel?.text = "\(viewModel?.bridge.speedPercent ?? 100)%"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The bridge is a singleton so its model state survives across open/close
        // cycles. Reset to the root so each keyboard session starts fresh.
        viewModel?.bridge.setSystemAppearance(dark: traitCollection.userInterfaceStyle == .dark)
        viewModel?.bridge.reset()
        canvas?.requestRedraw()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        viewModel?.bridge.setSystemAppearance(dark: traitCollection.userInterfaceStyle == .dark)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        viewModel?.setCanvasSize(canvas?.bounds.size ?? view.bounds.size)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        viewModel?.updateProxy(textDocumentProxy)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        os_log("viewWillDisappear — iOS is dismissing the keyboard", log: keyboardLog)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        os_log("viewDidDisappear", log: keyboardLog)
    }

    deinit {
        os_log("KeyboardViewController deinit", log: keyboardLog)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        os_log("didReceiveMemoryWarning", log: keyboardLog)
        // Intentionally do NOT call bridge.reset() here - that would rebuild
        // the node tree and spike memory further. Just log it for now; we
        // need to know how often this fires to pick the right response.
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(nibName: String?, bundle: Bundle?) {
        super.init(nibName: nibName, bundle: bundle)
    }
}
