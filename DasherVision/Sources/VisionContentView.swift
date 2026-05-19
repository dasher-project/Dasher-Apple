import SwiftUI

struct VisionContentView: View {
    @StateObject private var viewModel = VisionViewModel()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            VisionCanvasView(viewModel: viewModel)
                .ignoresSafeArea()

            VStack {
                HStack {
                    toolbarButton("doc.badge.plus") { viewModel.newMessage() }
                    toolbarButton(viewModel.isPlaying ? "pause.fill" : "play.fill", isAccent: true) { viewModel.togglePlay() }
                    Spacer()
                    toolbarButton("eye.fill", isAccent: viewModel.eyeGazeMode) { viewModel.eyeGazeMode.toggle() }
                    toolbarButton("gearshape") { showSettings = true }
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
                            .font(.system(size: 14, design: .monospaced))
                            .monospacedDigit()
                        toolbarButton("plus") { viewModel.increaseSpeed() }

                        Spacer()

                        if !viewModel.outputText.isEmpty {
                            toolbarButton("doc.on.doc") {
                                viewModel.copyOutput()
                            }
                        }
                        toolbarButton("delete.left") {
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
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isAccent ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(isAccent ? Color.blue : Color.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }
}
