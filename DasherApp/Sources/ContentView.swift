import SwiftUI
import DasherShared
import LucideIcons
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = DasherViewModel()
    @State private var showSettings = false
    @State private var currentLayoutPosition = "Right"
    @State private var showShareSheet = false
    @State private var showOpenFile = false
    @State private var outputPaneFraction: CGFloat = 2.0 / 9.0
    @State private var showAlphabetPopover = false

    var body: some View {
        GeometryReader { geometry in
            let isPortrait = geometry.size.width <= geometry.size.height

            if isPortrait {
                bottomTextLayout(geometry: geometry)
                    .ignoresSafeArea(edges: .leading)
            } else if currentLayoutPosition == "Left" {
                leftTextLayout(geometry: geometry)
            } else if currentLayoutPosition == "Bottom" {
                bottomTextLayout(geometry: geometry)
            } else if currentLayoutPosition == "Top" {
                topTextLayout(geometry: geometry)
            } else {
                rightTextLayout(geometry: geometry)
            }
        }
        .background(Color("BarBackground").ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            DasherSettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [viewModel.shareText])
        }
        .fileImporter(
            isPresented: $showOpenFile,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    if let text = try? String(contentsOf: url, encoding: .utf8) {
                        viewModel.openText(text)
                    }
                }
            case .failure:
                break
            }
        }
        .onChange(of: viewModel.importedText) { _, newText in
            if let text = newText {
                viewModel.importedText = nil
            }
        }
        .overlay(alignment: .top) {
            if let msg = viewModel.pendingMessage {
                MessageBanner(
                    isWarning: msg.isWarning,
                    text: msg.text,
                    onDismiss: { viewModel.pendingMessage = nil }
                )
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Layouts

    private func bottomTextLayout(geometry: GeometryProxy) -> some View {
        let isWide = geometry.size.width > 500
        let barHeight: CGFloat = isWide ? 64 : 44
        let bottomBarHeight: CGFloat = 44
        let contentHeight = geometry.size.height - barHeight - bottomBarHeight

        return VStack(spacing: 0) {
            toolbarBar
                .frame(height: barHeight)

            Divider().overlay(Color("BarBorder"))

            DasherCanvasView(viewModel: viewModel)
                .frame(height: contentHeight * (1 - outputPaneFraction))
                .ignoresSafeArea(edges: .leading)

            Divider().overlay(Color("GridBorder"))

            OutputTextView(
                viewModel: viewModel,
                paneSize: Binding(
                    get: { contentHeight * outputPaneFraction },
                    set: { outputPaneFraction = $0 / contentHeight }
                ),
                handleEdge: .top,
                availableSpace: contentHeight
            )
            .frame(height: contentHeight * outputPaneFraction)

            Divider().overlay(Color("BarBorder"))

            bottomBar
                .frame(height: bottomBarHeight)
        }
    }

    private func topTextLayout(geometry: GeometryProxy) -> some View {
        let isWide = geometry.size.width > 500
        let barHeight: CGFloat = isWide ? 64 : 44
        let bottomBarHeight: CGFloat = 44
        let contentHeight = geometry.size.height - barHeight - bottomBarHeight

        return VStack(spacing: 0) {
            toolbarBar
                .frame(height: barHeight)

            Divider().overlay(Color("BarBorder"))

            OutputTextView(
                viewModel: viewModel,
                paneSize: Binding(
                    get: { contentHeight * outputPaneFraction },
                    set: { outputPaneFraction = $0 / contentHeight }
                ),
                handleEdge: .bottom,
                availableSpace: contentHeight
            )
            .frame(height: contentHeight * outputPaneFraction)

            Divider().overlay(Color("GridBorder"))

            DasherCanvasView(viewModel: viewModel)
                .frame(height: contentHeight * (1 - outputPaneFraction))
                .ignoresSafeArea(edges: .leading)

            Divider().overlay(Color("BarBorder"))

            bottomBar
                .frame(height: bottomBarHeight)
        }
    }

    private func rightTextLayout(geometry: GeometryProxy) -> some View {
        let isWide = geometry.size.width > 500
        let barHeight: CGFloat = isWide ? 64 : 44
        let bottomBarHeight: CGFloat = 44
        let contentWidth = geometry.size.width
        let contentHeight = geometry.size.height - barHeight - bottomBarHeight

        return VStack(spacing: 0) {
            toolbarBar
                .frame(height: barHeight)

            Divider().overlay(Color("BarBorder"))

            HStack(spacing: 0) {
                DasherCanvasView(viewModel: viewModel)
                    .frame(width: contentWidth * (1 - outputPaneFraction), height: contentHeight)

                Divider().overlay(Color("GridBorder"))

                OutputTextView(
                    viewModel: viewModel,
                    paneSize: Binding(
                        get: { contentWidth * outputPaneFraction },
                        set: { outputPaneFraction = $0 / contentWidth }
                    ),
                    handleEdge: .leading,
                    availableSpace: contentWidth
                )
                .frame(width: contentWidth * outputPaneFraction, height: contentHeight)
            }

            Divider().overlay(Color("BarBorder"))

            bottomBar
                .frame(height: bottomBarHeight)
        }
    }

    private func leftTextLayout(geometry: GeometryProxy) -> some View {
        let isWide = geometry.size.width > 500
        let barHeight: CGFloat = isWide ? 64 : 44
        let bottomBarHeight: CGFloat = 44
        let contentWidth = geometry.size.width
        let contentHeight = geometry.size.height - barHeight - bottomBarHeight

        return VStack(spacing: 0) {
            toolbarBar
                .frame(height: barHeight)

            Divider().overlay(Color("BarBorder"))

            HStack(spacing: 0) {
                OutputTextView(
                    viewModel: viewModel,
                    paneSize: Binding(
                        get: { contentWidth * outputPaneFraction },
                        set: { outputPaneFraction = $0 / contentWidth }
                    ),
                    handleEdge: .trailing,
                    availableSpace: contentWidth
                )
                .frame(width: contentWidth * outputPaneFraction, height: contentHeight)

                Divider().overlay(Color("GridBorder"))

                DasherCanvasView(viewModel: viewModel)
                    .frame(width: contentWidth * (1 - outputPaneFraction), height: contentHeight)
            }

            Divider().overlay(Color("BarBorder"))

            bottomBar
                .frame(height: bottomBarHeight)
        }
    }

    // MARK: - Top Toolbar

    private var toolbarBar: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > 500
            let isPortrait = geo.size.width <= geo.size.height
            let barHeight: CGFloat = isWide ? 64 : 44

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: isWide ? 6 : 4) {
                    if isWide {
                        toolbarButton(icon: DasherIcon.newDocument, label: "New") {
                            viewModel.newMessage()
                        }
                        toolbarButton(icon: DasherIcon.open, label: "Open") {
                            showOpenFile = true
                        }
                        toolbarButton(icon: DasherIcon.share, label: "Save") {
                            showShareSheet = true
                        }
                        barDivider
                        toolbarButton(
                            icon: DasherIcon.gameMode,
                            label: viewModel.isGameModeActive ? "Game On" : "Game"
                        ) {
                            viewModel.toggleGameMode()
                        }
                        barDivider
                        layoutPicker
                        barDivider
                        toolbarButton(icon: DasherIcon.settings, label: "Prefs") {
                            showSettings = true
                        }
                    } else {
                        compactToolbarButton(icon: DasherIcon.newDocument) {
                            viewModel.newMessage()
                        }
                        compactToolbarButton(icon: DasherIcon.open) {
                            showOpenFile = true
                        }
                        compactToolbarButton(icon: DasherIcon.share) {
                            showShareSheet = true
                        }
                        barDivider
                        compactToolbarButton(icon: DasherIcon.gameMode) {
                            viewModel.toggleGameMode()
                        }
                        barDivider
                        layoutPickerCompact(portrait: isPortrait)
                        barDivider
                        compactToolbarButton(icon: DasherIcon.settings) {
                            showSettings = true
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(height: barHeight)
            .background(Color("BarBackground"))
        }
    }

    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                LucideIcon(icon, size: 16, color: Color("DeepNavy"))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color("BarText"))
            }
            .frame(width: 54, height: 52)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
        }
        .buttonStyle(.plain)
    }

    private func compactToolbarButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(icon, size: 16, color: Color("DeepNavy"))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
        }
        .buttonStyle(.plain)
    }

    private var layoutPicker: some View {
        Menu {
            Button("Right side") { currentLayoutPosition = "Right" }
            Button("Left side") { currentLayoutPosition = "Left" }
            Button("Bottom") { currentLayoutPosition = "Bottom" }
            Button("Top") { currentLayoutPosition = "Top" }
        } label: {
            HStack(spacing: 6) {
                LucideIcon(layoutIcon, size: 14, color: Color("DeepNavy"))

                Text(currentLayoutPosition)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color("BarText"))

                LucideIcon(DasherIcon.chevronDown, size: 8, color: Color("MutedText"))
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
        }
        .buttonStyle(.plain)
    }

    private var layoutPickerCompact: some View {
        Menu {
            Button("Right side") { currentLayoutPosition = "Right" }
            Button("Left side") { currentLayoutPosition = "Left" }
            Button("Bottom") { currentLayoutPosition = "Bottom" }
            Button("Top") { currentLayoutPosition = "Top" }
        } label: {
            HStack(spacing: 3) {
                LucideIcon(layoutIcon, size: 13, color: Color("DeepNavy"))
                LucideIcon(DasherIcon.chevronDown, size: 7, color: Color("MutedText"))
            }
            .frame(width: 38, height: 38)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
        }
        .buttonStyle(.plain)
    }

    private func layoutPickerCompact(portrait: Bool) -> some View {
        Menu {
            if !portrait {
                Button("Right side") { currentLayoutPosition = "Right" }
                Button("Left side") { currentLayoutPosition = "Left" }
            }
            Button("Bottom") { currentLayoutPosition = "Bottom" }
            Button("Top") { currentLayoutPosition = "Top" }
        } label: {
            HStack(spacing: 3) {
                LucideIcon(layoutIcon, size: 13, color: Color("DeepNavy"))
                LucideIcon(DasherIcon.chevronDown, size: 7, color: Color("MutedText"))
            }
            .frame(width: 38, height: 38)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
        }
        .buttonStyle(.plain)
    }

    private var layoutIcon: String {
        switch currentLayoutPosition {
        case "Right": return DasherIcon.paneRight
        case "Left": return DasherIcon.paneLeft
        case "Bottom": return DasherIcon.paneBottom
        case "Top": return DasherIcon.paneTop
        default: return DasherIcon.paneRight
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                alphabetPicker
                barDivider
                speedStepper
                barDivider
                autoSpeedToggle
                barDivider
                learningToggle
                barDivider
                fontPicker
                barDivider
                speechPicker

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 44)
        .background(Color("BarBackground"))
    }

    private var barDivider: some View {
        Rectangle()
            .fill(Color("Divider"))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 6)
    }

    private var alphabetPicker: some View {
        let alphabets = viewModel.bridge.allAlphabets
        return Button {
            showAlphabetPopover.toggle()
        } label: {
            HStack(spacing: 3) {
                Text(viewModel.bridge.alphabetId)
                    .font(.system(size: 13))
                    .foregroundColor(Color("BarText"))
                    .lineLimit(1)
                LucideIcon(DasherIcon.chevronDown, size: 8, color: Color("MutedText"))
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showAlphabetPopover, arrowEdge: .top) {
            NavigationView {
                List(alphabets, id: \.name) { a in
                    Button {
                        viewModel.bridge.setAlphabetId(a.name)
                        showAlphabetPopover = false
                    } label: {
                        HStack {
                            Text(a.name)
                            Spacer()
                            if viewModel.bridge.alphabetId == a.name {
                                LucideIcon(DasherIcon.check, size: 16, color: .accentColor)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
                .navigationTitle("Alphabet")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showAlphabetPopover = false }
                    }
                }
            }
            .frame(minWidth: 280, idealWidth: 320, minHeight: 400, idealHeight: 500)
        }
    }

    private var speedStepper: some View {
        HStack(spacing: 0) {
            Text("Speed ")
                .font(.system(size: 12))
                .foregroundColor(Color("MutedText"))

            stepperBox(
                label: String(format: "%.1f", viewModel.speed),
                onDecrement: { viewModel.decreaseSpeed() },
                onIncrement: { viewModel.increaseSpeed() }
            )
        }
    }

    private var learningToggle: some View {
        let binding = Binding<Bool>(
            get: { viewModel.bridge.getBoolParameter(key: viewModel.bridge.findParameterKey("BP_LM_ADAPTIVE")) },
            set: { viewModel.bridge.setBoolParameter(key: viewModel.bridge.findParameterKey("BP_LM_ADAPTIVE"), value: $0) }
        )

        return HStack(spacing: 6) {
            Text("Learning")
                .font(.system(size: 12))
                .foregroundColor(Color("MutedText"))

            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .fixedSize()
    }

    private var autoSpeedToggle: some View {
        let binding = Binding<Bool>(
            get: { viewModel.bridge.getBoolParameter(key: viewModel.bridge.findParameterKey("BP_AUTO_SPEEDCONTROL")) },
            set: { viewModel.bridge.setBoolParameter(key: viewModel.bridge.findParameterKey("BP_AUTO_SPEEDCONTROL"), value: $0) }
        )

        return HStack(spacing: 6) {
            Text("Auto")
                .font(.system(size: 12))
                .foregroundColor(Color("MutedText"))

            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .fixedSize()
    }

    private var palettePicker: some View {
        let palettes = viewModel.bridge.allPalettes
        return Menu {
            ForEach(palettes, id: \.name) { p in
                Button(action: { viewModel.bridge.setPalette(p.name) }) {
                    LucideLabel(p.name, icon: "circle", iconSize: 12)
                }
            }
        } label: {
            HStack(spacing: 4) {
                paletteSwatchIcon
                LucideIcon(DasherIcon.chevronDown, size: 7, color: Color("MutedText"))
            }
        }
        .buttonStyle(.plain)
    }

    private var paletteSwatchIcon: some View {
        let palettes = viewModel.bridge.allPalettes
        let currentName = viewModel.bridge.currentPalette
        let palette = palettes.first { $0.name == currentName } ?? palettes.first
        let colors = palette?.previewColors ?? []

        return HStack(spacing: 1) {
            VStack(spacing: 1) {
                Circle().fill(!colors.isEmpty ? Color(cgColor: colors[0]) : Color.gray).frame(width: 7, height: 7)
                Circle().fill(colors.count > 2 ? Color(cgColor: colors[2]) : Color.gray).frame(width: 7, height: 7)
            }
            VStack(spacing: 1) {
                Circle().fill(colors.count > 1 ? Color(cgColor: colors[1]) : Color.gray).frame(width: 7, height: 7)
                Circle().fill(colors.count > 3 ? Color(cgColor: colors[3]) : Color.gray).frame(width: 7, height: 7)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color("ButtonBackground")))
    }

    private var fontPicker: some View {
        let fontValues = viewModel.bridge.getStringValues(key: viewModel.bridge.findParameterKey("SP_DASHER_FONT"))
        let currentFont = viewModel.bridge.getStringParameter(key: viewModel.bridge.findParameterKey("SP_DASHER_FONT"))
        return Menu {
            ForEach(fontValues, id: \.self) { f in
                Button(f) { viewModel.bridge.setStringParameter(key: viewModel.bridge.findParameterKey("SP_DASHER_FONT"), value: f) }
            }
        } label: {
            HStack(spacing: 3) {
                Text(currentFont)
                    .font(.system(size: 13))
                    .foregroundColor(Color("BarText"))
                    .lineLimit(1)
                LucideIcon(DasherIcon.chevronDown, size: 8, color: Color("MutedText"))
            }
        }
    }

    private var fontSizeStepper: some View {
        let binding = Binding<Int>(
            get: { viewModel.bridge.getLongParameter(key: viewModel.bridge.findParameterKey("LP_DASHER_FONTSIZE")) },
            set: { viewModel.bridge.setLongParameter(key: viewModel.bridge.findParameterKey("LP_DASHER_FONTSIZE"), value: $0) }
        )
        return HStack(spacing: 0) {
            stepperBox(
                label: "\(binding.wrappedValue)",
                onDecrement: { viewModel.bridge.setLongParameter(key: viewModel.bridge.findParameterKey("LP_DASHER_FONTSIZE"), value: max(8, binding.wrappedValue - 1)) },
                onIncrement: { viewModel.bridge.setLongParameter(key: viewModel.bridge.findParameterKey("LP_DASHER_FONTSIZE"), value: min(72, binding.wrappedValue + 1)) }
            )
        }
    }

    private var speechPicker: some View {
        let isOn = viewModel.bridge.getBoolParameter(key: viewModel.bridge.findParameterKey("BP_SPEAK_WORDS"))
        return Menu {
            Button("Speech on") { viewModel.bridge.setBoolParameter(key: viewModel.bridge.findParameterKey("BP_SPEAK_WORDS"), value: true) }
            Button("Speech off") { viewModel.bridge.setBoolParameter(key: viewModel.bridge.findParameterKey("BP_SPEAK_WORDS"), value: false) }
        } label: {
            HStack(spacing: 3) {
                Text(isOn ? "Speech on" : "Speech off")
                    .font(.system(size: 13))
                    .foregroundColor(Color("BarText"))
                LucideIcon(DasherIcon.chevronDown, size: 8, color: Color("MutedText"))
            }
        }
    }

    private func stepperBox(label: String, onDecrement: @escaping () -> Void, onIncrement: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: onDecrement) {
                Text("–")
                    .font(.system(size: 14))
                    .foregroundColor(Color("BarText"))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color("BarText"))
                .frame(minWidth: 30)
                .padding(.horizontal, 4)
                .overlay(Rectangle().fill(Color("Divider")).frame(width: 1), alignment: .leading)
                .overlay(Rectangle().fill(Color("Divider")).frame(width: 1), alignment: .trailing)

            Button(action: onIncrement) {
                Text("+")
                    .font(.system(size: 14))
                    .foregroundColor(Color("BarText"))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color("Divider"), lineWidth: 1)
        )
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
}
