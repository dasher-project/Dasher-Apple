import SwiftUI

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
                    HStack {
                        Text("Alphabet")
                        Spacer()
                        Text(viewModel.bridge.alphabetId)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Section {
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
                    Label("Pointer Input", systemImage: "eye")
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
                    Label("Speech", systemImage: "speaker.wave.2")
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
