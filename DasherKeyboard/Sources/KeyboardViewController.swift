import UIKit
import SwiftUI
import DasherEngine

class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardContentView>?
    private var viewModel: KeyboardViewModel?

    override func viewDidLoad() {
        super.viewDidLoad()

        let vm = KeyboardViewModel(textDocumentProxy: textDocumentProxy)
        viewModel = vm

        let contentView = KeyboardContentView(viewModel: vm)
        let hosting = UIHostingController(rootView: contentView)
        hostingController = hosting

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leftAnchor.constraint(equalTo: view.leftAnchor),
            hosting.view.rightAnchor.constraint(equalTo: view.rightAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        viewModel?.setCanvasSize(view.bounds.size)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
