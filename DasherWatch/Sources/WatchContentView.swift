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

struct WatchContentView: View {
    @StateObject private var viewModel = WatchViewModel()

    var body: some View {
        VStack(spacing: 4) {
            canvasArea
            bottomBar
        }
        .navigationTitle("Dasher")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                TimelineView(.animation) { timeline in
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

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 6) {
            Text(viewModel.recentOutput.isEmpty ? "—" : viewModel.recentOutput)
                .font(.caption2.monospaced())
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .minimumScaleFactor(0.6)

            NavigationLink {
                WatchTextView(viewModel: viewModel)
            } label: {
                Image(systemName: "text.quote")
                    .font(.caption)
            }
            .disabled(viewModel.outputText.isEmpty)

            NavigationLink {
                WatchSettingsView(viewModel: viewModel)
            } label: {
                Image(systemName: "gearshape")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 6)
    }
}

// MARK: - Full text (read + Handoff)

struct WatchTextView: View {
    @ObservedObject var viewModel: WatchViewModel

    var body: some View {
        ScrollView {
            Text(viewModel.outputText.isEmpty ? " " : viewModel.outputText)
                .font(.caption2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Text")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Handoff") {
                    viewModel.handoff()
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

            Section("Alphabet") {
                Picker("Alphabet", selection: alphabetBinding) {
                    ForEach(viewModel.bridge.allAlphabetNames.sorted(), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }

            Section("Text") {
                Button("Clear output") {
                    viewModel.clearOutput()
                }
            }
        }
        .navigationTitle("Settings")
    }

    private var alphabetBinding: Binding<String> {
        Binding(
            get: { viewModel.bridge.alphabetId },
            set: { viewModel.bridge.setAlphabetId($0); viewModel.bridge.saveSettings() }
        )
    }
}
