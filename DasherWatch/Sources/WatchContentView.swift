import SwiftUI

@main
struct DasherWatchApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchContentView()
            }
        }
    }
}

enum WatchOrientation: String, CaseIterable, Identifiable {
    case vertical      // TopToBottom
    case leftToRight   // classic horizontal
    case rightToLeft   // horizontal, tree on the right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vertical: return "Vertical"
        case .leftToRight: return "Horizontal L→R"
        case .rightToLeft: return "Horizontal R→L"
        }
    }
}

struct WatchContentView: View {
    @StateObject private var viewModel = WatchViewModel()

    var body: some View {
        VStack(spacing: 2) {
            canvasArea
            outputBar
        }
        .navigationBarHidden(true)
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                // Explicit 30 Hz periodic schedule: TimelineView(.animation)
                // proved unreliable on watchOS (degraded/never ticking in
                // practice — the render closure ran zero times in a logged
                // session). Periodic ticks deterministically.
                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                    Canvas { context, size in
                        viewModel.render(in: context, size: size,
                                         timeMs: Int64(timeline.date.timeIntervalSince1970 * 1000))
                    }
                }
                if let error = viewModel.engineErrorMessage {
                    errorOverlay(error)
                } else if !viewModel.isEngineReady {
                    ProgressView("Starting…")
                        .tint(.white)
                }
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                viewModel.setCanvasSize(size)
            }
            .gesture(dragGesture)
            .focusable(viewModel.inputMethod == .crown)
            .digitalCrownRotation(
                $viewModel.crownPosition,
                from: 0.0, through: 1.0, by: 0.005,
                isHapticFeedbackEnabled: true
            )
            .onChange(of: viewModel.inputMethod) { method in
                if method == .tilt {
                    viewModel.startTilt()
                } else {
                    viewModel.stopTilt()
                }
            }
            .onAppear {
                if viewModel.inputMethod == .tilt {
                    viewModel.startTilt()
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard viewModel.inputMethod == .touch else { return }
                viewModel.touchAt(value.location)
            }
            .onEnded { _ in
                viewModel.touchEnded()
            }
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            Text("Dasher could not start")
                .font(.headline)
                .foregroundColor(.white)
            Text(message)
                .font(.caption2)
                .foregroundColor(.gray)
                .lineLimit(4)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Output bar

    /// Everything the user has typed, tail-visible in two lines; tapping the
    /// text (or the text button, both full-size targets) opens the full-text
    /// view. Writing is no longer blind.
    private var outputBar: some View {
        HStack(spacing: 4) {
            NavigationLink {
                WatchTextView(viewModel: viewModel)
            } label: {
                Text(viewModel.recentOutput.isEmpty ? "Start typing…" : viewModel.recentOutput)
                    .font(.caption2.monospaced())
                    .foregroundColor(viewModel.outputText.isEmpty ? .gray : .white)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            }
            .buttonStyle(.plain)

            NavigationLink {
                WatchTextView(viewModel: viewModel)
            } label: {
                Image(systemName: "text.alignleft")
                    .font(.body.weight(.medium))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.outputText.isEmpty)

            NavigationLink {
                WatchSettingsView(viewModel: viewModel)
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
        .background(Color.black.opacity(0.85))
    }
}

// MARK: - Full text (read what you wrote)

struct WatchTextView: View {
    @ObservedObject var viewModel: WatchViewModel

    var body: some View {
        ScrollView {
            Text(viewModel.outputText.isEmpty ? "Nothing typed yet." : viewModel.outputText)
                .font(.caption2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Text")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Clear") {
                    viewModel.clearOutput()
                }
                .disabled(viewModel.outputText.isEmpty)
            }
        }
    }
}

// MARK: - Settings

struct WatchSettingsView: View {
    @ObservedObject var viewModel: WatchViewModel

    var body: some View {
        List {
            Section("Input") {
                Picker("Method", selection: $viewModel.inputMethod) {
                    ForEach(WatchInputMethod.allCases) { method in
                        Label(method.label, systemImage: method.symbol)
                            .tag(method)
                    }
                }
                if viewModel.inputMethod == .tilt {
                    Button("Recalibrate tilt") {
                        viewModel.recalibrateTilt()
                    }
                }
                Text("Crown: rotate to steer — speed grows with distance from centre; centre pauses.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Section("Canvas") {
                Picker("Orientation", selection: $viewModel.orientation) {
                    ForEach(WatchOrientation.allCases) { o in
                        Text(o.label).tag(o)
                    }
                }
            }

            Section("Alphabet") {
                Picker("Alphabet", selection: alphabetBinding) {
                    ForEach(viewModel.bridge.allAlphabetNames.sorted(), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }

            Section("Engine input filter") {
                Picker("Filter", selection: $viewModel.inputFilter) {
                    ForEach(viewModel.permittedInputFilters, id: \.self) { f in
                        Text(f).tag(f)
                    }
                }
                Text("Normal Control suits touch; One Dimensional Mode suits crown.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Section("Speed") {
                Picker("Speed", selection: $viewModel.speedMultiplier) {
                    ForEach(WatchViewModel.speedChoices, id: \.self) { m in
                        Text(String(format: "%.1f×", m)).tag(m)
                    }
                }
                Toggle("Auto (adapt speed)", isOn: $viewModel.adaptiveSpeed)
            }

            Section("Behaviour") {
                Toggle("Learning (adapt to text)", isOn: $viewModel.learningMode)
                Toggle("Control characters", isOn: $viewModel.controlMode)
                Text("Control characters add copy, speak and paragraph commands to the alphabet.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Section("Text") {
                Button("Clear output") {
                    viewModel.clearOutput()
                }
            }

            Section("Reset") {
                Button("Reset all settings", role: .destructive) {
                    showResetConfirm = true
                }
                Text("Restores every Dasher setting to its default. Typed text is cleared. Cannot be undone.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Reset all settings to their defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset all settings", role: .destructive) {
                viewModel.resetAllSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    @State private var showResetConfirm = false

    private var alphabetBinding: Binding<String> {
        Binding(
            get: { viewModel.bridge.alphabetId },
            set: { viewModel.bridge.setAlphabetId($0); viewModel.bridge.saveSettings() }
        )
    }
}
