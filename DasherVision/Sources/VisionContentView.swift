import SwiftUI
import LucideIcons
import DasherShared

struct VisionContentView: View {
    @StateObject private var viewModel = VisionViewModel()
    @State private var showSettings = false
    @AppStorage("vision_has_seen_pinch_hint") private var hasSeenPinchHint = false

    var body: some View {
        ZStack {
            // Canvas owns its own UIHoverGestureRecognizer (dormant on
            // current visionOS — hover APIs deliver zero events) AND handles
            // pinch via touchesBegan/Moved/Ended. Pinch-and-look is the model.
            VisionCanvasView(viewModel: viewModel).overlay(EngineLoadingOverlay(isReady: viewModel.isEngineReady))
                .ignoresSafeArea()

            VStack {
                HStack {
                    toolbarButton(DasherIcon.newDocument) { viewModel.newMessage() }
                    toolbarButton(viewModel.isPlaying ? DasherIcon.pause : DasherIcon.play, isAccent: true) { viewModel.togglePlay() }
                    Spacer()
                    toolbarButton(DasherIcon.settings) { showSettings = true }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                VStack(spacing: 4) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(viewModel.outputText)
                                .font(.title3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .id("outputText")
                        }
                        .frame(maxHeight: 120)
                        .onChange(of: viewModel.outputText) { _, _ in
                            withAnimation {
                                proxy.scrollTo("outputText", anchor: .bottom)
                            }
                        }
                    }

                    HStack(spacing: 16) {
                        toolbarButton("minus") { viewModel.decreaseSpeed() }
                        Text(String(format: "%.1f", viewModel.speed))
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(.white)
                        toolbarButton("plus") { viewModel.increaseSpeed() }

                        Spacer()

                        if !viewModel.outputText.isEmpty {
                            toolbarButton(DasherIcon.copy) {
                                viewModel.copyOutput()
                            }
                        }
                        toolbarButton("delete") {
                            viewModel.newMessage()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
                .background(Color.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            // First-launch hint — the interaction model isn't discoverable
            // otherwise. Dismissed permanently via @AppStorage.
            if !hasSeenPinchHint {
                pinchHintOverlay
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            VisionSettingsView(viewModel: viewModel)
        }
        .onAppear { viewModel.bridge.setSystemAppearance(dark: true) }
    }

    private var pinchHintOverlay: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 20) {
                LucideIcon(DasherIcon.eye, size: 40, color: .white)
                Text("Pinch and Look to Write")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 12) {
                    Label("Pinch and hold anywhere on the canvas to start", systemImage: "hand.point.up.left.fill")
                    Label("Move your eyes while pinching to steer", systemImage: "arrow.up.left.and.arrow.down.right")
                    Label("Release the pinch to pause", systemImage: "hand.raised.fill")
                }
                .font(.body)
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: 420, alignment: .leading)
                Text("Your gaze is tracked continuously only while you pinch and hold — this is how all visionOS gaze apps work.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: 420)
                    .multilineTextAlignment(.center)
                Button {
                    hasSeenPinchHint = true
                } label: {
                    Text("Got it")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.accentColor))
                }
                .hoverEffect(.highlight)
            }
            .padding(40)
        }
    }

    private func toolbarButton(_ icon: String, isAccent: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(icon, size: 18, color: .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isAccent ? Color.accentColor : Color.black.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }
}
