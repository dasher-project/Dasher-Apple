import SwiftUI

struct DasherSettingsView: View {
    @ObservedObject var viewModel: DasherViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var parameters: [DasherParameterInfo] = []
    @State private var showAdvanced: Bool = false

    private let sectionIcons: [String: String] = [
        "Input": "cursorarrow.motionlines",
        "Language": "textformat",
        "Appearance": "paintpalette",
        "Speed": "gauge.with.dots.needle.33percent",
        "Output": "text.bubble",
        "Advanced": "gearshape.2",
        "Other": "square.grid.2x2"
    ]

    private let sectionOrder: [DasherSettingsSection] = [.input, .language, .appearance, .speed, .output, .other, .advanced]

    var body: some View {
        NavigationView {
            List {
                inputSection

                ForEach([DasherSettingsSection.language, .appearance, .speed, .output, .other], id: \.rawValue) { section in
                    let params = parameters(for: section)
                    if !params.isEmpty {
                        engineSection(section, params: params)
                    }
                }

                if showAdvanced {
                    let params = parameters(for: .advanced)
                    if !params.isEmpty {
                        engineSection(.advanced, params: params)
                    }
                }

                Section {
                    Toggle("Show Advanced Settings", isOn: $showAdvanced)
                }
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
            parameters = DasherBridge.allParameters
        }
    }

    private func parameters(for section: DasherSettingsSection) -> [DasherParameterInfo] {
        parameters.filter { DasherSettingsSection.section(for: $0) == section }
    }

    // MARK: - Input (with platform-specific eye gaze)

    private var inputSection: some View {
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

            ForEach(parameters(for: .input)) { param in
                parameterRow(param)
            }
        } header: {
            Label("Input", systemImage: "cursorarrow.motionlines")
        }
    }

    // MARK: - Language (with alphabet picker)

    private var languageSection: some View {
        let params = parameters(for: .language)
        return Section {
            let alphabets = viewModel.bridge.allAlphabets
            if !alphabets.isEmpty {
                Picker("Alphabet", selection: Binding(
                    get: { viewModel.bridge.alphabetId },
                    set: { viewModel.bridge.setAlphabetId($0) }
                )) {
                    ForEach(alphabets, id: \.name) { alphabet in
                        Text(alphabet.name).tag(alphabet.name)
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

    // MARK: - Dynamic engine section

    @ViewBuilder
    private func engineSection(_ section: DasherSettingsSection, params: [DasherParameterInfo]) -> some View {
        let icon = sectionIcons[section.rawValue] ?? "gearshape"

        if section == .appearance {
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
                Label(section.rawValue, systemImage: icon)
            }
        } else if section == .speed {
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
                Label(section.rawValue, systemImage: icon)
            }
        } else {
            Section {
                ForEach(params) { param in
                    parameterRow(param)
                }
            } header: {
                Label(section.rawValue, systemImage: icon)
            }
        }
    }

    // MARK: - Dynamic parameter row

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
                set: { viewModel.bridge.setStringParameter(key: param.key, value: $0) }
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
                    set: { viewModel.bridge.setLongParameter(key: param.key, value: $0) }
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
