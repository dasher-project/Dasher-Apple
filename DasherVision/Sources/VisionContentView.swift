import SwiftUI
import LucideIcons
import DasherShared

struct VisionContentView: View {
    @StateObject private var viewModel = VisionViewModel()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            VisionCanvasView(viewModel: viewModel)
                .ignoresSafeArea()

            // Transparent overlay for continuous eye-gaze tracking.
            // .onContinuousHover is the visionOS-native way to get
            // continuous gaze coordinates — more reliable than UIHoverGestureRecognizer.
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard viewModel.pointerHoverEnabled else { return }
                    switch phase {
                    case .active(let location):
                        viewModel.handleGazeHover(at: location)
                    case .ended:
                        viewModel.handleGazeHoverEnded()
                    }
                }
                .allowsHitTesting(true)
                .ignoresSafeArea()

            VStack {
                HStack {
                    toolbarButton(DasherIcon.newDocument) { viewModel.newMessage() }
                    toolbarButton(viewModel.isPlaying ? DasherIcon.pause : DasherIcon.play, isAccent: true) { viewModel.togglePlay() }
                    Spacer()
                    toolbarButton(DasherIcon.eye, isAccent: viewModel.pointerHoverEnabled) { viewModel.pointerHoverEnabled.toggle() }
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
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            VisionSettingsView(viewModel: viewModel)
        }
        .onAppear { viewModel.bridge.setSystemAppearance(dark: true) }
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
