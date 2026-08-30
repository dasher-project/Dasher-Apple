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
                            set: {
                                AlphabetFollow.followsLocale = false // explicit pick pins it (RFC 0003 locale-follow)
                                viewModel.bridge.setAlphabetId($0)
                            }
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
                        set: { newValue in
                            // Explicit user choice — record it so launch-time
                            // method gating doesn't revert it.
                            AccessConfiguration.userToggledAutocalibrate(to: newValue,
                                                                        method: AccessConfiguration.current.method)
                            viewModel.bridge.setBoolParameter(key: viewModel.bridge.findParameterKey("BP_AUTOCALIBRATE"), value: newValue)
                        }
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

                    Toggle(isOn: $viewModel.appLevelDwell) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("App-Level Dwell to Select")
                            Text("Auto-select after fixating your gaze while pinching. Only enable if OS dwell is off.")
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
                } header: {
                    LucideLabel("Input", icon: DasherIcon.eye)
                } footer: {
                    Text("On visionOS, pinch and hold on the canvas to start writing, look around while pinching to steer, and release to pause. The input model is pinch-and-look.")
                        .font(.caption)
                }

                Section {
                    Toggle("Show Input Debug Overlay", isOn: $viewModel.debugInputOverlay)
                    Button("Reset All Settings to Defaults", role: .destructive) {
                        viewModel.resetToDefaults()
                    }
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("The debug overlay draws a green panel top-left of the canvas showing live touch event counts and the last reported (x, y). When you pinch and hold, you should see touch.began then touch.moved with changing coordinates as you look around.")
                        .font(.caption)
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
