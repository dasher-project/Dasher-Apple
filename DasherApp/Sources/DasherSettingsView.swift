import SwiftUI

struct DasherSettingsView: View {
    @ObservedObject var viewModel: DasherViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var parameters: [DasherParameterInfo] = []
    @State private var selectedSection: DasherSettingsSection = .input
    @State private var selectedLocale: String = "en"
    @State private var currentInputFilter: String = ""

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

    private static let spInputFilter = 103
    private static let spGameTextFile = 102
    @State private var showGameTextFileImporter = false

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
        NavigationView {
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

                List {
                    sectionContent(for: selectedSection)
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
            selectedLocale = viewModel.bridge.locale
            currentInputFilter = viewModel.bridge.getStringParameter(key: Self.spInputFilter)
            parameters = DasherBridge.allParameters
        }
        .onChange(of: currentInputFilter) {
            parameters = DasherBridge.allParameters
        }
    }

    // MARK: - Filtering

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
        }
    }

    // MARK: - Customization

    private func customizationSection(_ params: [DasherParameterInfo]) -> some View {
        Section {
            let palettes = viewModel.bridge.allPalettes
            if !palettes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Colour Theme")
                        .font(.subheadline)
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
                        .padding(.vertical, 2)
                    }
                }
            }
            ForEach(params) { param in
                parameterRow(param)
            }
        } header: {
            Label("Customization", systemImage: "paintpalette")
        }
    }

    // MARK: - Input

    private func inputSection(_ params: [DasherParameterInfo]) -> some View {
        Section {
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
            Label("Input", systemImage: "cursorarrow.motionlines")
        }
    }

    // MARK: - Language

    private func languageSection(_ params: [DasherParameterInfo]) -> some View {
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

            ForEach(params) { param in
                parameterRow(param)
            }
        } header: {
            Label("Language", systemImage: "textformat")
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
            ForEach(params) { param in
                parameterRow(param)
            }
        } header: {
            Label("Output", systemImage: "text.bubble")
        }
    }

    // MARK: - Generic

    private var speechSection: some View {
        Section {
            SpeechSettingsView(service: SpeechService.shared)
        } header: {
            Label("Speech", systemImage: "speaker.wave.2")
        }
    }

    private func genericSection(_ params: [DasherParameterInfo], icon: String) -> some View {
        Section {
            ForEach(params) { param in
                parameterRow(param)
            }
        } header: {
            Label(selectedSection.rawValue, systemImage: icon)
        }
    }

    private func gameModeSection(_ params: [DasherParameterInfo]) -> some View {
        let otherParams = params.filter { $0.key != Self.spGameTextFile }
        let currentFile = viewModel.bridge.getStringParameter(key: Self.spGameTextFile)

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
        } header: {
            Label("Game Mode", systemImage: "gamecontroller")
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
            if param.uiType == .slider && param.maxVal > param.minVal {
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

        case .string:
            stringPickerRow(param)

        case .invalid:
            EmptyView()
        }
    }

    @ViewBuilder
    private func stringPickerRow(_ param: DasherParameterInfo) -> some View {
        let stringValues = viewModel.bridge.getStringValues(key: param.key)
        if param.uiType == .dropdown && !stringValues.isEmpty {
            let binding = Binding<String>(
                get: { viewModel.bridge.getStringParameter(key: param.key) },
                set: { newValue in
                    viewModel.bridge.setStringParameter(key: param.key, value: newValue)
                    if param.key == Self.spInputFilter { currentInputFilter = newValue }
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
                        if param.key == Self.spInputFilter { currentInputFilter = viewModel.bridge.getStringParameter(key: Self.spInputFilter) }
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
