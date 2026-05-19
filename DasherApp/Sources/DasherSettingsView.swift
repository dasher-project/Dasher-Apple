import SwiftUI

struct DasherSettingsView: View {
    @ObservedObject var viewModel: DasherViewModel
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

                Section("Colours") {
                    HStack(spacing: 12) {
                        ForEach(0..<viewModel.colourPresets.count, id: \.self) { index in
                            let preset = viewModel.colourPresets[index]
                            Button(action: { viewModel.selectedColourIndex = index }) {
                                Circle()
                                    .fill(preset.1)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(viewModel.selectedColourIndex == index ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Toggle(isOn: $viewModel.eyeGazeMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Eye Gaze Mode")
                            Text("Accepts pointer hover as input. Enable iPadOS Eye Tracking in Settings > Accessibility.")
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
                            ForEach(DasherViewModel.dwellDurationOptions, id: \.1) { option in
                                Text(option.0).tag(option.1)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
