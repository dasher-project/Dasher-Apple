import SwiftUI

@MainActor
final class DirectCanvasWindow: NSPanel, NSWindowDelegate {
    private weak var editorWindow: NSWindow?
    var onExit: (() -> Void)?
    var onInputSourceSetup: (() -> Void)?

    init(replacing editorWindow: NSWindow, opacity: CGFloat) {
        self.editorWindow = editorWindow
        super.init(
            contentRect: editorWindow.frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = editorWindow.title
        level = .floating
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        alphaValue = opacity
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        delegate = self
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present<Content: View>(_ content: Content) {
        contentView = DirectCanvasHost(rootView: content)
        if let editorWindow {
            setFrame(editorWindow.frame, display: false)
            editorWindow.orderOut(nil)
        }
        orderFrontRegardless()
    }

    func restoreEditorWindow() {
        orderOut(nil)
        contentView = nil
        onExit = nil
        onInputSourceSetup = nil
        NSApp.activate()
        editorWindow?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onExit?()
        return false
    }
}

private final class DirectCanvasHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
