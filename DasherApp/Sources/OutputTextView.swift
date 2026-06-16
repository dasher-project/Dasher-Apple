import SwiftUI

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
                        .font(.system(size: 18))
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
                Text("Target:")
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
            toolbarDivider
            toolbarButton(icon: "doc.on.doc", label: "Copy") { copyAllText() }
            toolbarButton(icon: "doc.on.clipboard", label: "Paste") { pasteText() }
            toolbarDivider
            toolbarButton(icon: "xmark.circle", label: "Clear") { viewModel.newMessage() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .background(Color("BarBackground"))
    }

    private var compactToolbar: some View {
        HStack(spacing: 6) {
            speechButton(showLabel: false)
            toolbarDivider
            iconOnlyButton(icon: "doc.on.doc") { copyAllText() }
            iconOnlyButton(icon: "doc.on.clipboard") { pasteText() }
            toolbarDivider
            iconOnlyButton(icon: "xmark.circle") { viewModel.newMessage() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .background(Color("BarBackground"))
    }

    private var minimalToolbar: some View {
        HStack(spacing: 4) {
            speechButton(showLabel: false)
            Menu {
                Button("Copy All", action: copyAllText)
                Button("Paste", action: pasteText)
                Divider()
                Button("Clear", role: .destructive) { viewModel.newMessage() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .foregroundColor(Color("BarText"))
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
                        Image(systemName: "doc.text")
                            .font(.system(size: 14))
                        Image(systemName: isOn ? "speaker.wave.2.fill" : "speaker.slash")
                            .font(.system(size: 8))
                            .offset(x: 3, y: 1)
                    }
                    Text("Speech")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color("MutedText"))
                }
                .foregroundColor(isOn ? Color("AccentColor") : Color("BarText"))
                .frame(height: 36)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
            } else {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 15))
                    Image(systemName: isOn ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.system(size: 8))
                        .offset(x: 3, y: 1)
                }
                .foregroundColor(isOn ? Color("AccentColor") : Color("BarText"))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color("ButtonBackground")))
            }
        }
        .buttonStyle(.plain)
    }

    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color("BarText"))
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
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Color("BarText"))
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
            viewModel.bridge.reset()
            viewModel.outputText = clipboardString
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
