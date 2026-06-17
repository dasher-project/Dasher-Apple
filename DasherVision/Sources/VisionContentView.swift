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
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            VisionSettingsView(viewModel: viewModel)
        }
    }

    private func toolbarButton(_ icon: String, isAccent: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(icon, size: 18, color: .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(isAccent ? Color.blue : Color.white.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
