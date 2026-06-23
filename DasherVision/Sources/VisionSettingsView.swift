import SwiftUI
import LucideIcons
import DasherShared
import DasherSpeech

struct VisionSettingsView: View {
    @ObservedObject var viewModel: VisionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Speed") {
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

                Section("Language") {
                    let alphabets = viewModel.bridge.allAlphabets
                    let currentId = viewModel.bridge.alphabetId
                    let pickerAlphabets = currentId.isEmpty || alphabets.contains(where: { $0.name == currentId })
                        ? alphabets
                        : alphabets + [DasherAlphabet(name: currentId)]
                    if !pickerAlphabets.isEmpty {
                        Picker("Alphabet", selection: Binding(
                            get: { viewModel.bridge.alphabetId },
                            set: { viewModel.bridge.setAlphabetId($0) }
                        )) {
                            ForEach(pickerAlphabets, id: \.name) { a in
                                Text(a.name).tag(a.name)
                            }
                        }
                    }
                }

                Section {
                    Toggle("Pause When Looking Away", isOn: Binding(
                        get: { viewModel.bridge.getBoolParameter(key: viewModel.bridge.findParameterKey("BP_STOP_OUTSIDE")) },
                        set: { viewModel.bridge.setBoolParameter(key: viewModel.bridge.findParameterKey("BP_STOP_OUTSIDE"), value: $0) }
                    ))
                    Toggle("Auto-Centre Target", isOn: Binding(
                        get: { viewModel.bridge.getBoolParameter(key: viewModel.bridge.findParameterKey("BP_AUTOCALIBRATE")) },
                        set: { viewModel.bridge.setBoolParameter(key: viewModel.bridge.findParameterKey("BP_AUTOCALIBRATE"), value: $0) }
                    ))
                    Toggle("Adapt Speed Automatically", isOn: Binding(
                        get: { viewModel.bridge.getBoolParameter(key: viewModel.bridge.findParameterKey("BP_AUTO_SPEEDCONTROL")) },
                        set: { viewModel.bridge.setBoolParameter(key: viewModel.bridge.findParameterKey("BP_AUTO_SPEEDCONTROL"), value: $0) }
                    ))
                } header: {
                    Text("Eye Gaze")
                }

                Section {
                    NavigationLink {
                        AccessSettingsView(bridge: viewModel.bridge)
                    } label: {
                        HStack {
                            Text("Access")
                            Spacer()
                            LucideIcon(DasherIcon.chevronRight, color: .secondary)
                        }
                    }

                    Toggle(isOn: $viewModel.pointerHoverEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pointer Hover Input")
                            Text("Uses your natural eye gaze as pointer input. Look to navigate, pinch to select.")
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
                                ForEach(VisionViewModel.dwellDurationOptions, id: \.1) { option in
                                    Text(option.0).tag(option.1)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                } header: {
                    LucideLabel("Pointer Input", icon: DasherIcon.eye)
                }

                if viewModel.appLevelDwell {
                    Section("Dwell Duration") {
                        Picker("Dwell Duration", selection: $viewModel.dwellDuration) {
                            ForEach(VisionViewModel.dwellDurationOptions, id: \.1) { option in
                                Text(option.0).tag(option.1)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    SpeechSettingsView(service: SpeechService.shared)
                } header: {
                    LucideLabel("Speech", icon: DasherIcon.speak)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
