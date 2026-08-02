import SwiftUI
import DasherShared
import DasherSpeech
import LucideIcons

struct DasherSettingsView: View {
    @ObservedObject var viewModel: DasherViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var parameters: [DasherParameterInfo] = []
    @State private var selectedSection: DasherSettingsSection = .input
    @State private var selectedLocale: String = "en"
    @State private var currentAccessSummary: String = ""
    @State private var availableLocales: [(code: String, name: String)] = [("en", "English")]
    @AppStorage("localeAutoDefaulted") private var localeAutoDefaulted = false

    private static let spInputFilter = "SP_INPUT_FILTER"
    private static let spGameTextFile = "SP_GAME_TEXT_FILE"
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
        "Normal Control": ["CDefaultFilter", "CDynamicFilter", "CDynamicButtons", "Control"],
        "Press Mode": ["CPressFilter", "Control"],
        "Smoothing Mode": ["CSmoothingFilter", "CPressFilter", "Control"],
        "Stylus Control": ["CStylusFilter", "Control"],
        "Click Mode": ["CClickFilter", "Control"],
        "Button Mode": ["CButtonMode", "CDasherButtons", "Control"],
        "Direct Mode": ["CButtonMode", "CDasherButtons", "Control"],
        "Menu Mode": ["CButtonMode", "CDasherButtons", "Control"],
        "Alternating Direct Mode": ["CButtonMode", "CDasherButtons", "Control"],
        "Compass Mode": ["CCompassMode", "Control"],
        "One Button Mode": ["COneButtonFilter", "CStaticFilter", "Control"],
        "One Button Dynamic Mode": ["COneButtonFilter", "Control"],
        "Two Button Dynamic Mode": ["CTwoButtonDynamicFilter", "Control"],
        "Two Push Dynamic Mode": ["CTwoPushDynamicFilter", "Control"],
        "Button Dynamic Mode": ["CDynamicButtons", "Control"],
        "Multi-Press Mode": ["CButtonMultiPress", "Control"],
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(DasherSettingsSection.allCases, id: \.self) { section in
                        Button {
                            withAnimation { selectedSection = section }
                            AnalyticsService.shared.capture("settings_viewed", properties: ["tab_name": section.rawValue])
                        } label: {
                            VStack(spacing: 3) {
                                LucideIcon(section.icon, size: 16)
                                Text(section.rawValue)
                                    .font(.system(size: 10, weight: selectedSection == section ? .semibold : .regular))
                            }
                            .foregroundColor(selectedSection == section ? Color("DeepNavy") : Color("MutedText"))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedSection == section ? Color("DasherTeal") : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                List {
                    if selectedSection == .privacy {
                        AnalyticsPrivacySection()
                        KeyboardSetupSection()
                        ResetSettingsSection {
                            viewModel.bridge.resetToDefaults()
                        }
                    } else {
                        if selectedSection == .output {
                            TypingRateSection()
                        }
                        sectionContent(for: selectedSection)
                    }
                }
                .listStyle(.grouped)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.bridge.saveSettings()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            let loaded = viewModel.bridge.availableLocales()
            if loaded.count > 1 { availableLocales = loaded }
            // Align the engine locale with the device language once (RFC 0003),
            // so engine parameter labels match the localised chrome by default.
            if !localeAutoDefaulted {
                localeAutoDefaulted = true
                if let dev = preferredLocaleCode(in: availableLocales),
                   dev != viewModel.bridge.locale {
                    selectedLocale = dev
                    viewModel.bridge.setLocale(dev)
                } else {
                    selectedLocale = viewModel.bridge.locale
                }
            } else {
                selectedLocale = viewModel.bridge.locale
            }
            updateAccessSummary()
            parameters = DasherBridge.allParameters
        }
        .onChange(of: currentAccessSummary) {
            parameters = DasherBridge.allParameters
        }
    }

    /// Map the device language to a supported DasherCore locale code, if any.
    private func preferredLocaleCode(in locales: [(code: String, name: String)]) -> String? {
        let lang = Locale.current.language.languageCode?.identifier ?? ""
        let codes = Set(locales.map { $0.code })
        if codes.contains(lang) { return lang }
        if lang == "zh" { return codes.contains("zh-CN") ? "zh-CN" : nil }
        return nil
    }

    // MARK: - Filtering

    private func updateAccessSummary() {
        let config = AccessConfiguration.current
        currentAccessSummary = "\(config.method.displayName), \(config.selection.displayName)"
    }

    private var activeSubgroups: Set<String> {
        let currentFilter = viewModel.bridge.getStringParameter(key: viewModel.bridge.findParameterKey(Self.spInputFilter))
        return filterToSubgroup[currentFilter] ?? []
    }

    private func parameters(for section: DasherSettingsSection) -> [DasherParameterInfo] {
        parameters.filter { param in
            if param.name == "Simulate Transparency" { return false }
            guard DasherSettingsSection.section(for: param) == section else { return false }
            if section != .input { return true }
            if param.subgroup.isEmpty { return true }
            return activeSubgroups.contains(param.subgroup)
        }
    }

    // MARK: - Section Content

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
            speechSection
        case .gameMode:
            gameModeSection(params)
        case .privacy:
            EmptyView()
        }
    }

    // MARK: - Customization

    private func customizationSection(_ params: [DasherParameterInfo]) -> some View {
        Section {
            Picker("Appearance", selection: Binding<Int>(
                get: { viewModel.bridge.getAppearanceMode() },
                set: { viewModel.bridge.setAppearanceMode($0) }
            )) {
                Text("System").tag(0)
                Text("Light").tag(1)
                Text("Dark").tag(2)
            }
            .pickerStyle(.segmented)

            let palettes = viewModel.bridge.allPalettes
            if !palettes.isEmpty {
                palettePickerRow(
                    label: "Light Palette",
                    palettes: palettes,
                    selectedName: viewModel.bridge.getLightPalette()
                ) { name in
                    viewModel.bridge.setLightPalette(name)
                }
                palettePickerRow(
                    label: "Dark Palette",
                    palettes: palettes,
                    selectedName: viewModel.bridge.getDarkPalette()
                ) { name in
                    viewModel.bridge.setDarkPalette(name)
                }
            }
            ForEach(params.filter { $0.name != "Color Palette" }) { param in
                parameterRow(param)
            }
        } header: {
            LucideLabel("Customization", icon: DasherIcon.palette)
        }
    }

    @ViewBuilder
    private func palettePickerRow(
        label: String,
        palettes: [DasherPalette],
        selectedName: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<palettes.count, id: \.self) { i in
                        let palette = palettes[i]
                        let isSelected = selectedName == palette.name
                        Button(action: { onSelect(palette.name) }) {
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
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Input

    private func inputSection(_ params: [DasherParameterInfo]) -> some View {
        Section {
            NavigationLink {
                AccessSettingsView(
                    bridge: viewModel.bridge,
                    onMethodChanged: { method in
                        viewModel.activateTiltIfNeeded(method: method)
                    },
                    tiltService: viewModel.tiltService
                )
            } label: {
                HStack {
                    LucideLabel("Access", icon: "move")
                    Spacer()
                    Text(currentAccessSummary)
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            }

            #if os(iOS) || os(visionOS)
            Toggle(isOn: $viewModel.pointerHoverEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pointer Hover Input")
                    Text("Accept hover/pointer events as Dasher input. Enable for eye tracking or external pointers.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if viewModel.pointerHoverEnabled {
                Toggle(isOn: $viewModel.appLevelDwell) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App-Level Dwell to Select")
                        Text("Auto-select after fixating. Only enable if OS dwell is off.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.appLevelDwell {
                    Picker("Dwell Duration", selection: $viewModel.dwellDuration) {
                        ForEach(DasherViewModel.dwellDurationOptions, id: \.1) { option in
                            Text(option.0).tag(option.1)
                        }
                    }
                }
            }
            #endif

            ForEach(params) { param in
                parameterRow(param)
            }
        } header: {
            Text("Input")
        }
    }

    // MARK: - Language

    private func languageSection(_ params: [DasherParameterInfo]) -> some View {
        Group {
            Section {
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
        } header: {
            LucideLabel("Language", icon: DasherIcon.alphabet)
        }

        TrainingTextManagementSection(
            userTrainingFileSize: viewModel.bridge.userTrainingFileSize,
            userTrainingSizeDescription: viewModel.bridge.userTrainingSizeDescription,
            onImport: { viewModel.bridge.importTrainingText($0) },
            onExport: { viewModel.bridge.exportTrainingText() },
            onReset: { viewModel.bridge.resetTrainingData() }
        )
        }
    }

    // MARK: - Output

    private func outputSection(_ params: [DasherParameterInfo]) -> some View {
        Section {
            VStack(alignment: .leading) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text("\(viewModel.bridge.speedPercent)%")
                        .foregroundColor(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(viewModel.bridge.speedPercent) },
                    set: { viewModel.bridge.setSpeedPercent(Int($0)) }
                ), in: 20...400)
            }
            // Output text font
            Picker("Output Font", selection: Binding(
                get: { OutputFontSettings.fontName },
                set: {
                    OutputFontSettings.fontName = $0
                    NotificationCenter.default.post(name: .outputFontChanged, object: nil)
                }
            )) {
                ForEach(OutputFontSettings.availableFonts, id: \.self) { Text($0).tag($0) }
            }
            // Output text font size
            HStack {
                Text("Output Font Size")
                Spacer()
                Stepper("\(Int(OutputFontSettings.fontSize))", value: Binding(
                    get: { OutputFontSettings.fontSize },
                    set: {
                        OutputFontSettings.fontSize = $0
                        NotificationCenter.default.post(name: .outputFontChanged, object: nil)
                    }
                ), in: 10...48)
            }
            ForEach(params) { param in
                parameterRow(param)
            }
        } header: {
            LucideLabel("Output", icon: "message-square")
        }
    }

    // MARK: - Generic

    private var speechSection: some View {
        Section {
            SpeechSettingsView(service: SpeechService.shared)
        } header: {
            LucideLabel("Speech", icon: DasherIcon.speak)
        }
    }

    private func genericSection(_ params: [DasherParameterInfo], icon: String) -> some View {
        Section {
            ForEach(params) { param in
                parameterRow(param)
            }
        } header: {
            LucideLabel(selectedSection.rawValue, icon: icon)
        }
    }

    private func gameModeSection(_ params: [DasherParameterInfo]) -> some View {
        let gameTextKey = viewModel.bridge.findParameterKey(Self.spGameTextFile)
        let otherParams = params.filter { $0.key != gameTextKey }
        let currentFile = viewModel.bridge.getStringParameter(key: gameTextKey)

        return Section {
            HStack {
                Text("Game Text File")
                Spacer()
                if currentFile.isEmpty {
                    Text("Default")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(URL(fileURLWithPath: currentFile).lastPathComponent)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Button("Choose...") {
                    showGameTextFileImporter = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if !currentFile.isEmpty {
                    Button {
                        viewModel.bridge.setStringParameter(key: gameTextKey, value: "")
                    } label: {
                        LucideIcon(DasherIcon.close, size: 16, color: .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(otherParams) { param in
                parameterRow(param)
            }
        } header: {
            LucideLabel("Game Mode", icon: DasherIcon.gameMode)
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
                    viewModel.bridge.setStringParameter(key: viewModel.bridge.findParameterKey(Self.spGameTextFile), value: path)
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }
            case .failure:
                break
            }
        }
    }

    // MARK: - Parameter Row

    @ViewBuilder
    private func parameterRow(_ param: DasherParameterInfo) -> some View {
        switch param.type {
        case .bool:
            let binding = Binding<Bool>(
                get: { viewModel.bridge.getBoolParameter(key: param.key) },
                set: { viewModel.bridge.setBoolParameter(key: param.key, value: $0) }
            )
            VStack(alignment: .leading, spacing: 2) {
                Toggle(param.name, isOn: binding)
                if !param.desc.isEmpty {
                    Text(param.desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

        case .long:
            if param.uiType == .dropdown {
                let enumVals = DasherBridge.getEnumValues(key: param.key)
                if !enumVals.isEmpty {
                    let binding = Binding<Int>(
                        get: { viewModel.bridge.getLongParameter(key: param.key) },
                        set: { viewModel.bridge.setLongParameter(key: param.key, value: $0) }
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Picker(param.name, selection: binding) {
                            ForEach(enumVals, id: \.value) { ev in
                                Text(ev.name).tag(ev.value)
                            }
                        }
                        if !param.desc.isEmpty {
                            Text(param.desc)
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                    if param.key == viewModel.bridge.findParameterKey(Self.spInputFilter) { updateAccessSummary() }
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
                        if param.key == viewModel.bridge.findParameterKey(Self.spInputFilter) { updateAccessSummary() }
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

extension DasherParameterInfo: Identifiable {
    var id: Int { key }
}
