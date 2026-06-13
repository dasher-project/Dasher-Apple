import UIKit

class KeyboardViewController: UIInputViewController {
    private var canvas: KeyboardCanvas?
    private var speedLabel: UILabel?
    private var viewModel: KeyboardViewModel?

    override func viewDidLoad() {
        super.viewDidLoad()

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
        viewModel?.bridge.reset()
    }

    @objc private func nextKeyboard() {
        viewModel?.advanceToNextInputMode()
    }

    private func updateSpeedLabel() {
        speedLabel?.text = "\(viewModel?.bridge.speedPercent ?? 100)%"
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        viewModel?.setCanvasSize(canvas?.bounds.size ?? view.bounds.size)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        viewModel?.updateProxy(textDocumentProxy)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(nibName: String?, bundle: Bundle?) {
        super.init(nibName: nibName, bundle: bundle)
    }
}
