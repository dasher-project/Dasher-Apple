import SwiftUI
import DasherShared
import LucideIcons

struct OutputTextView: View {
    @ObservedObject var viewModel: DasherViewModel
    @Binding var paneSize: CGFloat
    let handleEdge: HandleEdge
    let availableSpace: CGFloat

    enum HandleEdge {
        case leading
        case trailing
        case top
        case bottom
    }

    private var minPane: CGFloat {
        handleEdge == .leading || handleEdge == .trailing ? 120 : 100
    }
    private var maxPane: CGFloat { availableSpace * 0.6 }

    var body: some View {
        GeometryReader { geo in
            switch handleEdge {
            case .leading:
                HStack(spacing: 0) {
                    dragHandleStrip(axis: .horizontal)
                    Divider().overlay(Color("GridBorder"))
                    outputContent(availableWidth: geo.size.width - 11)
                }
            case .trailing:
                HStack(spacing: 0) {
                    outputContent(availableWidth: geo.size.width - 11)
                    Divider().overlay(Color("GridBorder"))
                    dragHandleStrip(axis: .horizontal)
                }
            case .top:
                VStack(spacing: 0) {
                    dragHandleStrip(axis: .vertical)
                    Divider().overlay(Color("GridBorder"))
                    outputContent(availableWidth: geo.size.width)
                }
            case .bottom:
                VStack(spacing: 0) {
                    outputContent(availableWidth: geo.size.width)
                    Divider().overlay(Color("GridBorder"))
                    dragHandleStrip(axis: .vertical)
                }
            }
        }
        .background(Color("MessagePaneBackground"))
    }

    // MARK: - Drag Handle

    private func dragHandleStrip(axis: Axis) -> some View {
        let handleView = Group {
            switch axis {
            case .horizontal:
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color("MutedText").opacity(0.4))
                        .frame(width: 4, height: 28)
                    Spacer()
                }
                .frame(width: 10)
                .contentShape(Rectangle())
                .cursor(.resizeLeftRight)
            case .vertical:
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color("MutedText").opacity(0.4))
                        .frame(width: 28, height: 4)
                    Spacer()
                }
                .frame(height: 10)
                .contentShape(Rectangle())
                .cursor(.resizeUpDown)
            }
        }

        return Color.clear
            .overlay(handleView)
            .frame(
                width: axis == .horizontal ? 10 : nil,
                height: axis == .vertical ? 10 : nil
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let delta: CGFloat
                        switch handleEdge {
                        case .leading: delta = -value.translation.width
                        case .trailing: delta = value.translation.width
                        case .top: delta = -value.translation.height
                        case .bottom: delta = value.translation.height
                        }
                        paneSize = min(maxPane, max(minPane, paneSize + delta))
                    }
            )
    }

    // MARK: - Content

    @ViewBuilder
    private func outputContent(availableWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            adaptiveToolbar(availableWidth: availableWidth)
                .frame(height: 44)

            Divider().overlay(Color("BarBorder"))

            if viewModel.isGameModeActive && !viewModel.gameTargetText.isEmpty {
                gameTargetBar
            }

            // RFC 0019: editable output pane. UITextView handles its own
            // scrolling — wrapping it in a SwiftUI ScrollView prevented the
            // text from rendering (nested scroll views on iOS).
            EditableOutputText(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var gameTargetBar: some View {
        let target = viewModel.gameTargetText
        let correct = viewModel.gameCorrectCount
        let wrong = viewModel.gameWrongText
        let correctIdx = target.index(target.startIndex, offsetBy: correct, limitedBy: target.endIndex) ?? target.endIndex
        let correctPart = String(target[..<correctIdx])
        let wrongCount = wrong.count
        let remainingIdx = target.index(target.startIndex, offsetBy: correct + wrongCount, limitedBy: target.endIndex) ?? target.endIndex
        let remainingPart = String(target[remainingIdx...])

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Phrase \(viewModel.gamePhrasesCompleted + 1) · \(String(format: "%.0f", viewModel.typingWPM)) wpm")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(correct)/\(viewModel.gameTargetLength)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 0) {
                if !correctPart.isEmpty {
                    Text(correctPart)
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                }
                if !wrong.isEmpty {
                    Text(wrong)
                        .foregroundColor(.red)
                        .strikethrough()
                }
                if !remainingPart.isEmpty {
                    Text(remainingPart)
                        .foregroundColor(.secondary)
                }
            }
            .font(.system(size: 16))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color("BarBackground"))
    }

    // MARK: - Adaptive Toolbar

    @ViewBuilder
    private func adaptiveToolbar(availableWidth: CGFloat) -> some View {
        let mode = toolbarMode(for: availableWidth)

        switch mode {
        case .full:
            fullToolbar
        case .compact:
            compactToolbar
        case .minimal:
            minimalToolbar
        }
    }

    private enum ToolbarMode {
        case full, compact, minimal
    }

    private func toolbarMode(for width: CGFloat) -> ToolbarMode {
        if width >= 430 { return .full }
        if width >= 280 { return .compact }
        return .minimal
    }

    private var fullToolbar: some View {
        HStack(spacing: 8) {
            speechButton(showLabel: true)
            if viewModel.speech.isSpeaking {
                stopSpeechButton(showLabel: true)
            }
            toolbarDivider
            turboToggleButton(showLabel: true)
            toolbarDivider
            toolbarButton(icon: DasherIcon.copy, label: "Copy") { copyAllText() }
            toolbarButton(icon: DasherIcon.paste, label: "Paste") { pasteText() }
            toolbarDivider
            toolbarButton(icon: DasherIcon.close, label: "Clear") {
                UITelemetry.action("status_bar", "new")
                viewModel.newMessage()
            }
            toolbarDivider
            repeatToolbarButton(
                icon: DasherIcon.backspace,
                label: "Del",
                repeatIntervalMs: 90,
                telemetryAction: "backspace"
            ) {
                viewModel.editorBackspace()
            }
            repeatToolbarButton(
                icon: DasherIcon.arrowLeft,
                label: "Left",
                repeatIntervalMs: 120,
                telemetryAction: "arrow_left"
            ) {
                viewModel.editorMoveCaret(delta: -1)
            }
            repeatToolbarButton(
                icon: DasherIcon.arrowRight,
                label: "Right",
                repeatIntervalMs: 120,
                telemetryAction: "arrow_right"
            ) {
                viewModel.editorMoveCaret(delta: 1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .background(Color("BarBackground"))
    }

    private var compactToolbar: some View {
        HStack(spacing: 6) {
            speechButton(showLabel: false)
            if viewModel.speech.isSpeaking {
                stopSpeechButton(showLabel: false)
            }
            toolbarDivider
            turboToggleButton(showLabel: false)
            toolbarDivider
            iconOnlyButton(icon: DasherIcon.copy) { copyAllText() }
            iconOnlyButton(icon: DasherIcon.paste) { pasteText() }
            toolbarDivider
            iconOnlyButton(icon: DasherIcon.close) {
                UITelemetry.action("status_bar", "new")
                viewModel.newMessage()
            }
            toolbarDivider
            repeatIconOnlyButton(
                icon: DasherIcon.backspace,
                repeatIntervalMs: 90,
                telemetryAction: "backspace"
            ) {
                viewModel.editorBackspace()
            }
            repeatIconOnlyButton(
                icon: DasherIcon.arrowLeft,
                repeatIntervalMs: 120,
                telemetryAction: "arrow_left"
            ) {
                viewModel.editorMoveCaret(delta: -1)
            }
            repeatIconOnlyButton(
                icon: DasherIcon.arrowRight,
                repeatIntervalMs: 120,
                telemetryAction: "arrow_right"
            ) {
                viewModel.editorMoveCaret(delta: 1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .background(Color("BarBackground"))
    }

    private var minimalToolbar: some View {
        HStack(spacing: 4) {
            speechButton(showLabel: false)
            if viewModel.speech.isSpeaking {
                stopSpeechButton(showLabel: false)
            }
            turboToggleButton(showLabel: false)
            repeatIconOnlyButton(
                icon: DasherIcon.backspace,
                repeatIntervalMs: 90,
                telemetryAction: "backspace"
            ) {
                viewModel.editorBackspace()
            }
            repeatIconOnlyButton(
                icon: DasherIcon.arrowLeft,
                repeatIntervalMs: 120,
                telemetryAction: "arrow_left"
            ) {
                viewModel.editorMoveCaret(delta: -1)
            }
            repeatIconOnlyButton(
                icon: DasherIcon.arrowRight,
                repeatIntervalMs: 120,
                telemetryAction: "arrow_right"
            ) {
                viewModel.editorMoveCaret(delta: 1)
            }
            Menu {
                Button("Copy All", action: copyAllText)
                Button("Paste", action: pasteText)
                Divider()
                Button("Clear", role: .destructive) {
                    UITelemetry.action("status_bar", "new")
                    viewModel.newMessage()
                }
            } label: {
                LucideIcon(DasherIcon.more, size: 15, color: Color("BarText"))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color("ButtonBackground")))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .background(Color("BarBackground"))
    }

    // MARK: - Toolbar Components

    private func speechButton(showLabel: Bool) -> some View {
        Button(action: {
            let current = viewModel.bridge.getBoolParameter(key: viewModel.bridge.findParameterKey("BP_SPEAK_WORDS"))
            viewModel.bridge.setBoolParameter(key: viewModel.bridge.findParameterKey("BP_SPEAK_WORDS"), value: !current)
            UITelemetry.setting("Speak Words", !current, surface: "main_ui")
        }) {
            let isOn = viewModel.bridge.getBoolParameter(key: viewModel.bridge.findParameterKey("BP_SPEAK_WORDS"))
            if showLabel {
                HStack(spacing: 4) {
                    ZStack(alignment: .bottomTrailing) {
                        LucideIcon("file-text", size: 14)
                        LucideIcon(isOn ? DasherIcon.speak : DasherIcon.mute, size: 8)
                            .offset(x: 3, y: 1)
                    }
                    Text("Speech")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color("MutedText"))
                }
                .foregroundColor(turboActive ? Color("AccentColor") : Color("BarText"))
                .frame(height: 36)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
            } else {
                ZStack(alignment: .bottomTrailing) {
                    LucideIcon("file-text", size: 15)
                    LucideIcon(isOn ? DasherIcon.speak : DasherIcon.mute, size: 8)
                        .offset(x: 3, y: 1)
                }
                .foregroundColor(turboActive ? Color("AccentColor") : Color("BarText"))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color("ButtonBackground")))
            }
        }
        .buttonStyle(.plain)
    }

    private func stopSpeechButton(showLabel: Bool) -> some View {
        Button(action: { viewModel.speech.stop() }) {
            if showLabel {
                HStack(spacing: 4) {
                    LucideIcon(DasherIcon.stopSpeak, size: 14, color: .red)
                    Text("Stop")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color("MutedText"))
                }
                .frame(height: 36)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
            } else {
                LucideIcon(DasherIcon.stopSpeak, size: 15, color: .red)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color("ButtonBackground")))
            }
        }
        .buttonStyle(.plain)
    }

    @State private var turboActive = false

    private func turboToggleButton(showLabel: Bool) -> some View {
        return Button(action: {
            turboActive.toggle()
            viewModel.bridge.keyEvent(key: 101, pressed: turboActive)
            UITelemetry.action("main_toolbar", "turbo", state: turboActive ? "on" : "off")
        }) {
            if showLabel {
                HStack(spacing: 4) {
                    LucideIcon(DasherIcon.turbo, size: 14)
                    Text("Turbo")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color("MutedText"))
                }
                .foregroundColor(turboActive ? Color("AccentColor") : Color("BarText"))
                .frame(height: 36)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
            } else {
                LucideIcon(DasherIcon.turbo, size: 15, color: turboActive ? Color("AccentColor") : Color("BarText"))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color("ButtonBackground")))
            }
        }
        .buttonStyle(.plain)
    }

    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                LucideIcon(icon, size: 14, color: Color("BarText"))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color("MutedText"))
            }
            .frame(width: 46, height: 36)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
        }
        .buttonStyle(.plain)
    }

    private func iconOnlyButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(icon, size: 14, color: Color("BarText"))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
        }
        .buttonStyle(.plain)
    }

    private func repeatToolbarButton(
        icon: String,
        label: String,
        repeatIntervalMs: Int,
        telemetryAction: String,
        action: @escaping () -> Void
    ) -> some View {
        RepeatActionButton(
            repeatIntervalMs: repeatIntervalMs,
            onPressStart: { UITelemetry.action("status_bar", telemetryAction) },
            action: action
        ) {
            VStack(spacing: 3) {
                LucideIcon(icon, size: 14, color: Color("BarText"))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color("MutedText"))
            }
            .frame(width: 46, height: 36)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
        }
    }

    private func repeatIconOnlyButton(
        icon: String,
        repeatIntervalMs: Int,
        telemetryAction: String,
        action: @escaping () -> Void
    ) -> some View {
        RepeatActionButton(
            repeatIntervalMs: repeatIntervalMs,
            onPressStart: { UITelemetry.action("status_bar", telemetryAction) },
            action: action
        ) {
            LucideIcon(icon, size: 14, color: Color("BarText"))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
        }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color("Divider"))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
    }

    // MARK: - Actions

    private func copyAllText() {
        UITelemetry.action("status_bar", "copy")
        UIPasteboard.general.string = viewModel.outputText
    }

    private func pasteText() {
        UITelemetry.action("status_bar", "paste")
        if let clipboardString = UIPasteboard.general.string, !clipboardString.isEmpty {
            viewModel.editorInsert(clipboardString)
        }
    }
}

// MARK: - Cursor Helpers

private enum Cursor: String {
    case resizeUpDown
    case resizeLeftRight
}

private extension View {
    func cursor(_ cursor: Cursor) -> some View {
        #if os(macOS)
        self.onHover { inside in
            if inside {
                switch cursor {
                case .resizeUpDown: NSCursor.resizeUpDown.push()
                case .resizeLeftRight: NSCursor.resizeLeftRight.push()
                }
            } else {
                NSCursor.pop()
            }
        }
        #else
        self
        #endif
    }
}

#Preview("Full Width") {
    OutputTextView(
        viewModel: DasherViewModel(),
        paneSize: .constant(300),
        handleEdge: .leading,
        availableSpace: 500
    )
    .frame(width: 300, height: 400)
}

#Preview("Compact Width") {
    OutputTextView(
        viewModel: DasherViewModel(),
        paneSize: .constant(180),
        handleEdge: .leading,
        availableSpace: 500
    )
    .frame(width: 180, height: 400)
}

#Preview("Minimal Width") {
    OutputTextView(
        viewModel: DasherViewModel(),
        paneSize: .constant(120),
        handleEdge: .leading,
        availableSpace: 500
    )
    .frame(width: 120, height: 400)
}


// MARK: - RFC 0019: Editable output text

/// Editable output pane using TextEditor, with caret tracking for engine
/// re-anchoring. The viewModel's editorText binding handles the sync loop
/// (user edits seed the engine; engine pushes update the text without
/// re-seeding).
struct EditableOutputText: View {
    @ObservedObject var viewModel: DasherViewModel

    var body: some View {
        EditableTextViewWrapper(viewModel: viewModel)
    }
}

/// UITextView wrapper — the Coordinator is the sole sync point between the
/// text view and the engine (RFC 0019). No intermediate @Published bindings;
/// the delegate calls bridge APIs directly on user interaction, and SwiftUI
/// renders engine pushes via updateUIView with the programmatic flag.
struct EditableTextViewWrapper: UIViewRepresentable {
    @ObservedObject var viewModel: DasherViewModel

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = UIFont.systemFont(ofSize: 16)
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        tv.isEditable = true
        tv.isSelectable = true
        // Dasher IS the input method — suppress the system on-screen keyboard.
        // An empty inputView keeps the text view fully editable (Dasher canvas
        // drives text, hardware keyboards work, selection tracked for
        // re-anchoring) but tapping the pane no longer summons the keyboard.
        tv.inputView = UIView()
        tv.text = viewModel.outputText
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        // RFC 0019 clause 2: never clobber active IME composition (marked text).
        guard tv.markedTextRange == nil else { return }

        let newLen = (viewModel.outputText as NSString).length
        let clampedLoc = max(0, min(viewModel.editorSelection.location, newLen))
        let clampedLen = max(0, min(viewModel.editorSelection.length, newLen - clampedLoc))
        let targetRange = NSRange(location: clampedLoc, length: clampedLen)

        let textChanged = tv.text != viewModel.outputText
        let selectionChanged = tv.selectedRange != targetRange

        if textChanged || selectionChanged {
            context.coordinator.setProgrammatic {
                if textChanged {
                    tv.text = viewModel.outputText
                }
                tv.selectedRange = targetRange
                tv.scrollRangeToVisible(targetRange)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        let viewModel: DasherViewModel
        var isProgrammatic = false

        init(viewModel: DasherViewModel) {
            self.viewModel = viewModel
        }

        func setProgrammatic(_ block: () -> Void) {
            isProgrammatic = true
            block()
            isProgrammatic = false
        }

        /// User typed/pasted/deleted — seed the engine buffer.
        /// RFC 0019 clause 7: over-long text seeds only a trailing 100k
        /// UTF-16 window (full model rebuild per keystroke is not acceptable
        /// at extreme sizes). Mirrors Windows EditorSeedPolicy.
        func textViewDidChange(_ tv: UITextView) {
            guard !isProgrammatic else { return }
            // RFC 0019 clause 2: defer seeding during IME composition —
            // the marked text is not committed yet.
            guard tv.markedTextRange == nil else { return }
            let selected = tv.selectedRange
            let (text, caretUTF16) = EditorSeedPolicy.apply(
                to: tv.text, caretUTF16: selected.location)
            let byteOffset = viewModel.bridge.byteOffsetFromUTF16(text, utf16Offset: caretUTF16)
            viewModel.bridge.seedBuffer(text, caretOffset: byteOffset)
            viewModel.selectAnchorUTF16 = nil
            viewModel.editorSelection = selected
            viewModel.outputText = tv.text
        }

        /// Caret/selection changed — re-anchor the model (RFC 0019 clause 3).
        /// A pure tap in the middle of text fires this without textViewDidChange.
        func textViewDidChangeSelection(_ tv: UITextView) {
            guard !isProgrammatic else { return }
            guard tv.markedTextRange == nil else { return }
            let selected = tv.selectedRange
            viewModel.selectAnchorUTF16 = nil
            viewModel.editorSelection = selected
            let (windowed, windowedCaret) = EditorSeedPolicy.apply(
                to: tv.text, caretUTF16: selected.location)
            let byteOffset = viewModel.bridge.byteOffsetFromUTF16(windowed, utf16Offset: windowedCaret)
            viewModel.bridge.setOffset(byteOffset)
        }
    }
}
