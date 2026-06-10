import SwiftUI
import UniformTypeIdentifiers

@main
struct DasherMacApp: App {
    @StateObject private var viewModel = MacDasherViewModel()
    @State private var showSettings = false

    var body: some Scene {
        WindowGroup {
            MacContentView(viewModel: viewModel)
                .sheet(isPresented: $showSettings) {
                    MacDasherSettingsView(viewModel: viewModel)
                }
                .fileImporter(
                    isPresented: $viewModel.showOpenFile,
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
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Message") {
                    viewModel.newMessage()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Open...") {
                    viewModel.showOpenFile = true
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandGroup(after: .saveItem) {
                Button("Save...") {
                    saveFile()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    showSettings = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu("Input") {
                Button(viewModel.isPlaying ? "Pause" : "Play") {
                    viewModel.togglePlay()
                }
                .keyboardShortcut("p", modifiers: [.command])

                Button("Increase Speed") {
                    viewModel.increaseSpeed()
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Decrease Speed") {
                    viewModel.decreaseSpeed()
                }
                .keyboardShortcut("-", modifiers: [.command])
            }
        }
    }

    private func saveFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "dasher-output.txt"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                viewModel.saveText(to: url)
            }
        }
    }
}

struct MacDasherSettingsView: View {
    @ObservedObject var viewModel: MacDasherViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var parameters: [DasherParameterInfo] = []
    @State private var selectedSection: DasherSettingsSection = .customization
    @State private var selectedLocale: String = "en"
    @State private var accessSummary: String = ""

    private let availableLocales: [(code: String, name: String)] = [
        ("en", "English"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("fr", "Français"),
        ("it", "Italiano"),
        ("pt", "Português (BR)"),
        ("pt-PT", "Português (PT)"),
        ("zh-CN", "中文"),
        ("ar", "العربية")
    ]

    private static let spInputFilter = 101
    private static let spGameTextFile = 100
    @State private var showGameTextFileImporter = false

    private static let dasherFonts = [
        "System",
        "Georgia",
        "Helvetica Neue",
        "Menlo",
        "Courier New",
        "Avenir Next",
        "Futura",
        "Palatino",
        "Trebuchet MS",
        "Verdana",
    ]

    private let filterToSubgroup: [String: Set<String>] = [
        "Normal Control": ["CDefaultFilter", "CDynamicFilter", "CDynamicButtons"],
        "Press Mode": ["CPressFilter"],
        "Smoothing Mode": ["CSmoothingFilter", "CPressFilter"],
        "Stylus Control": ["CStylusFilter"],
        "Click Mode": ["CClickFilter"],
        "Button Mode": ["CButtonMode", "CDasherButtons"],
        "Direct Mode": ["CButtonMode", "CDasherButtons"],
        "Menu Mode": ["CButtonMode", "CDasherButtons"],
        "Alternating Direct Mode": ["CButtonMode", "CDasherButtons"],
        "Compass Mode": ["CCompassMode"],
        "One Button Mode": ["COneButtonFilter", "CStaticFilter"],
        "One Button Dynamic Mode": ["COneButtonFilter"],
        "Two Button Dynamic Mode": ["CTwoButtonDynamicFilter"],
        "Two Push Dynamic Mode": ["CTwoPushDynamicFilter"],
        "Button Dynamic Mode": ["CDynamicButtons"],
        "Multi-Press Mode": ["CButtonMultiPress"],
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(DasherSettingsSection.allCases, id: \.self) { section in
                    Button {
                        withAnimation { selectedSection = section }
                    } label: {
                        Text(section.rawValue)
                            .font(.subheadline.weight(selectedSection == section ? .semibold : .regular))
                            .foregroundColor(selectedSection == section ? .white : .primary)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedSection == section ? Color.accentColor : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                sectionContent(for: selectedSection)
                    .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    viewModel.bridge.saveSettings()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 520)
        .onAppear {
            selectedLocale = viewModel.bridge.locale
            updateAccessSummary()
            parameters = DasherBridge.allParameters
        }
        .onChange(of: accessSummary) {
            parameters = DasherBridge.allParameters
        }
    }

    private func updateAccessSummary() {
        let config = AccessConfiguration.current
        accessSummary = "\(config.method.displayName), \(config.selection.displayName)"
    }

    private var activeSubgroups: Set<String> {
        let currentFilter = viewModel.bridge.getStringParameter(key: Self.spInputFilter)
        return filterToSubgroup[currentFilter] ?? []
    }

    private func parameters(for section: DasherSettingsSection) -> [DasherParameterInfo] {
        parameters.filter { param in
            guard DasherSettingsSection.section(for: param) == section else { return false }
            if section != .input { return true }
            if param.subgroup.isEmpty { return true }
            return activeSubgroups.contains(param.subgroup)
        }
    }

    @ViewBuilder
    private func sectionContent(for section: DasherSettingsSection) -> some View {
        let params = parameters(for: section)
        switch section {
        case .customization:
            customizationSection(params)
        case .input:
            inputSection(params)
        case .language:
            languageSection(params)
        case .output:
            outputSection(params)
        case .speech:
            SpeechSettingsView(service: SpeechService.shared)
        case .gameMode:
            gameModeSection(params)
        }
    }

    private func customizationSection(_ params: [DasherParameterInfo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let palettes = viewModel.bridge.allPalettes
            if !palettes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Colour Theme").font(.subheadline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(0..<palettes.count, id: \.self) { i in
                                let palette = palettes[i]
                                let isSelected = viewModel.bridge.currentPalette == palette.name
                                Button(action: { viewModel.bridge.setPalette(palette.name) }) {
                                    VStack(spacing: 4) {
                                        HStack(spacing: 2) {
                                            ForEach(0..<min(palette.previewColors.count, 4), id: \.self) { ci in
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(Color(cgColor: palette.previewColors[ci]))
                                                    .frame(width: 16, height: 24)
                                            }
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                                        )
                                        Text(palette.name)
                                            .font(.system(size: 9))
                                            .lineLimit(1)
                                            .foregroundColor(isSelected ? .primary : .secondary)
                                    }
                                    .frame(width: 72)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            ForEach(params.filter { $0.name != "Color Palette" }) { param in
                parameterRow(param)
            }
        }
    }

    @State private var showInputMethodSelector = false

    private func inputSection(_ params: [DasherParameterInfo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showInputMethodSelector = true
            } label: {
                HStack {
                    Text("Access")
                    Spacer()
                    Text(accessSummary)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showInputMethodSelector) {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Done") { showInputMethodSelector = false }
                            .padding(12)
                    }
                    AccessSettingsView(bridge: viewModel.bridge)
                }
                .frame(minWidth: 350, minHeight: 400)
            }

            ForEach(params) { param in
                parameterRow(param)
            }
        }
    }

    private func languageSection(_ params: [DasherParameterInfo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("App Language", selection: $selectedLocale) {
                ForEach(availableLocales, id: \.code) { loc in
                    Text(loc.name).tag(loc.code)
                }
            }
            .onChange(of: selectedLocale) {
                if viewModel.bridge.setLocale(selectedLocale) {
                    parameters = DasherBridge.allParameters
                }
            }

            let alphabets = viewModel.bridge.allAlphabets
            if !alphabets.isEmpty {
                Picker("Alphabet", selection: Binding(
                    get: { viewModel.bridge.alphabetId },
                    set: { viewModel.bridge.setAlphabetId($0) }
                )) {
                    ForEach(alphabets, id: \.name) { a in
                        Text(a.name).tag(a.name)
                    }
                }
            }

            let lmId = viewModel.bridge.currentLanguageModelId
            let lmParamKeys = Set(viewModel.bridge.getLanguageModelParamKeys(lmId))
            let lmSelKey = viewModel.bridge.languageModelIdParamKey

            ForEach(params.filter { param in
                if param.type == .string { return false }
                if param.type == .bool { return true }
                if param.key == lmSelKey { return true }
                return lmParamKeys.contains(param.key)
            }) { param in
                parameterRow(param)
            }
        }
    }

    private func outputSection(_ params: [DasherParameterInfo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text("\(viewModel.bridge.speedPercent)%").foregroundColor(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(viewModel.bridge.speedPercent) },
                    set: { viewModel.bridge.setSpeedPercent(Int($0)) }
                ), in: 20...400)
            }
            ForEach(params) { param in
                parameterRow(param)
            }
        }
    }

    private func genericSection(_ params: [DasherParameterInfo], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(params) { param in
                parameterRow(param)
            }
        }
    }

    private func gameModeSection(_ params: [DasherParameterInfo]) -> some View {
        let otherParams = params.filter { $0.key != Self.spGameTextFile }
        let currentFile = viewModel.bridge.getStringParameter(key: Self.spGameTextFile)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Game Text File")
                    .frame(width: 120, alignment: .leading)
                if currentFile.isEmpty {
                    Text("Default")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Choose File...") {
                        showGameTextFileImporter = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Text(URL(fileURLWithPath: currentFile).lastPathComponent)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Choose File...") {
                        showGameTextFileImporter = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button {
                        viewModel.bridge.setStringParameter(key: Self.spGameTextFile, value: "")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(otherParams) { param in
                parameterRow(param)
            }
        }
        .fileImporter(
            isPresented: $showGameTextFileImporter,
            allowedContentTypes: [.plainText, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    let accessing = url.startAccessingSecurityScopedResource()
                    let path = url.path
                    viewModel.bridge.setStringParameter(key: Self.spGameTextFile, value: path)
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }
            case .failure:
                break
            }
        }
    }

    @ViewBuilder
    private func parameterRow(_ param: DasherParameterInfo) -> some View {
        switch param.type {
        case .bool:
            let binding = Binding<Bool>(
                get: { viewModel.bridge.getBoolParameter(key: param.key) },
                set: { viewModel.bridge.setBoolParameter(key: param.key, value: $0) }
            )
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(param.name)
                    if !param.desc.isEmpty {
                        Text(param.desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Toggle("", isOn: binding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

        case .long:
            if param.uiType == .dropdown {
                let enumVals = DasherBridge.getEnumValues(key: param.key)
                if !enumVals.isEmpty {
                    let binding = Binding<Int>(
                        get: { viewModel.bridge.getLongParameter(key: param.key) },
                        set: { viewModel.bridge.setLongParameter(key: param.key, value: $0) }
                    )
                    Picker(param.name, selection: binding) {
                        ForEach(enumVals, id: \.value) { ev in
                            Text(ev.name).tag(ev.value)
                        }
                    }
                } else {
                    longField(param)
                }
            } else if param.uiType == .slider && param.maxVal > param.minVal {
                let binding = Binding<Double>(
                    get: { Double(viewModel.bridge.getLongParameter(key: param.key)) },
                    set: { viewModel.bridge.setLongParameter(key: param.key, value: Int($0)) }
                )
                VStack(alignment: .leading) {
                    HStack {
                        Text(param.name)
                        Spacer()
                        Text("\(viewModel.bridge.getLongParameter(key: param.key))")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: binding, in: Double(param.minVal)...Double(param.maxVal), step: Double(param.step))
                }
            } else if param.uiType == .step {
                let binding = Binding<Int>(
                    get: { viewModel.bridge.getLongParameter(key: param.key) },
                    set: { viewModel.bridge.setLongParameter(key: param.key, value: $0) }
                )
                Stepper(value: binding, in: param.minVal...param.maxVal, step: param.step) {
                    HStack {
                        Text(param.name)
                        Spacer()
                        Text("\(viewModel.bridge.getLongParameter(key: param.key))")
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                longField(param)
            }

        case .string:
            if param.name == "Dasher Font" {
                fontPickerRow(param)
            } else {
                stringPickerRow(param)
            }

        case .invalid:
            EmptyView()
        }
    }

    @ViewBuilder
    private func stringPickerRow(_ param: DasherParameterInfo) -> some View {
        let stringValues = viewModel.bridge.getStringValues(key: param.key)
        let currentValue = viewModel.bridge.getStringParameter(key: param.key)
        if param.uiType == .dropdown && !stringValues.isEmpty && (currentValue.isEmpty || stringValues.contains(currentValue)) {
            let binding = Binding<String>(
                get: {
                    let val = viewModel.bridge.getStringParameter(key: param.key)
                    return stringValues.contains(val) ? val : (stringValues.first ?? val)
                },
                set: { newValue in
                    viewModel.bridge.setStringParameter(key: param.key, value: newValue)
                    if param.key == Self.spInputFilter { updateAccessSummary() }
                }
            )
            Picker(param.name, selection: binding) {
                ForEach(stringValues, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
        } else if param.uiType == .dropdown {
            let enumVals = DasherBridge.getEnumValues(key: param.key)
            if !enumVals.isEmpty {
                let binding = Binding<Int>(
                    get: { viewModel.bridge.getLongParameter(key: param.key) },
                    set: { newValue in
                        viewModel.bridge.setLongParameter(key: param.key, value: newValue)
                        if param.key == Self.spInputFilter {
                            updateAccessSummary()
                        }
                    }
                )
                Picker(param.name, selection: binding) {
                    ForEach(enumVals, id: \.value) { ev in
                        Text(ev.name).tag(ev.value)
                    }
                }
            } else {
                stringField(param)
            }
        } else {
            stringField(param)
        }
    }

    @ViewBuilder
    private func fontPickerRow(_ param: DasherParameterInfo) -> some View {
        let currentFont = viewModel.bridge.getStringParameter(key: param.key)
        let mapped = Self.dasherFonts.contains(currentFont) ? currentFont : "System"
        let binding = Binding<String>(
            get: { mapped },
            set: { viewModel.bridge.setStringParameter(key: param.key, value: $0 == "System" ? "" : $0) }
        )
        Picker(param.name, selection: binding) {
            ForEach(Self.dasherFonts, id: \.self) { font in
                Text(font).tag(font)
            }
        }
    }

    @ViewBuilder
    private func longField(_ param: DasherParameterInfo) -> some View {
        let binding = Binding<Int>(
            get: { viewModel.bridge.getLongParameter(key: param.key) },
            set: { viewModel.bridge.setLongParameter(key: param.key, value: $0) }
        )
        HStack {
            Text(param.name)
            Spacer()
            TextField("", value: binding, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
        }
    }

    @ViewBuilder
    private func stringField(_ param: DasherParameterInfo) -> some View {
        let binding = Binding<String>(
            get: { viewModel.bridge.getStringParameter(key: param.key) },
            set: { viewModel.bridge.setStringParameter(key: param.key, value: $0) }
        )
        HStack {
            Text(param.name)
            Spacer()
            TextField("", text: binding)
                .multilineTextAlignment(.trailing)
        }
    }
}
