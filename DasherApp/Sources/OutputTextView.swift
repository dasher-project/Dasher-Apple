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
                Divider().overlay(Color("BarBorder"))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.outputText)
                        .font(OutputFontSettings.font)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .id("outputText")
                }
                .onChange(of: viewModel.outputText) { _, _ in
                    withAnimation {
                        proxy.scrollTo("outputText", anchor: .bottom)
                    }
                }
            }
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
                Text("Phrase \(viewModel.gamePhrasesCompleted + 1)")
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

    // MARK: - Drag Handle

    private var dragHandleStrip: some View {
        Group {
            switch handleEdge {
            case .leading, .trailing:
                sideDragHandle
            case .top, .bottom:
                topBottomDragHandle
            }
        }
    }

    private var sideDragHandle: some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 2)
                .fill(Color("MutedText").opacity(0.4))
                .frame(width: 4, height: 28)
            Spacer()
        }
        .contentShape(Rectangle())
        .cursor(.resizeLeftRight)
        .padding(.horizontal, 3)
        .gesture(DragGesture(minimumDistance: 1).onChanged { value in
            let delta: CGFloat = handleEdge == .leading
                ? -value.translation.width
                : value.translation.width
            paneSize = min(maxPane, max(minPane, paneSize + delta))
        })
    }

    private var topBottomDragHandle: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 2)
                .fill(Color("MutedText").opacity(0.4))
                .frame(width: 28, height: 4)
            Spacer()
        }
        .contentShape(Rectangle())
        .cursor(.resizeUpDown)
        .padding(.vertical, 3)
        .gesture(DragGesture(minimumDistance: 1).onChanged { value in
            let delta: CGFloat = handleEdge == .top
                ? -value.translation.height
                : value.translation.height
            paneSize = min(maxPane, max(minPane, paneSize + delta))
        })
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
        if width >= 280 { return .full }
        if width >= 160 { return .compact }
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
            toolbarButton(icon: DasherIcon.close, label: "Clear") { viewModel.newMessage() }
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
            iconOnlyButton(icon: DasherIcon.close) { viewModel.newMessage() }
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
            Menu {
                Button("Copy All", action: copyAllText)
                Button("Paste", action: pasteText)
                Divider()
                Button("Clear", role: .destructive) { viewModel.newMessage() }
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

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color("Divider"))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
    }

    // MARK: - Actions

    private func copyAllText() {
        UIPasteboard.general.string = viewModel.outputText
    }

    private func pasteText() {
        if let clipboardString = UIPasteboard.general.string {
            viewModel.outputText += clipboardString
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
