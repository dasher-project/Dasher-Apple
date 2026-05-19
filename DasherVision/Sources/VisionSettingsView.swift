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
                    Toggle(isOn: $viewModel.eyeGazeMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Eye Gaze Mode")
                            Text("Uses your natural eye gaze as pointer input. Look to navigate, dwell or pinch to select.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label("Eye Gaze", systemImage: "eye")
                }

                if viewModel.eyeGazeMode {
                    Section("Dwell Duration") {
                        Picker("Dwell Duration", selection: $viewModel.dwellDuration) {
                            ForEach(VisionViewModel.dwellDurationOptions, id: \.1) { option in
                                Text(option.0).tag(option.1)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
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
