import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DasherViewModel()
    @State private var showSettings = false

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            if isLandscape {
                landscapeLayout(geometry: geometry)
            } else {
                portraitLayout(geometry: geometry)
            }
        }
        .background(Color("BarBackground").ignoresSafeArea())
        .preferredColorScheme(.light)
        .sheet(isPresented: $showSettings) {
            DasherSettingsView(viewModel: viewModel)
        }
    }

    private func portraitLayout(geometry: GeometryProxy) -> some View {
        let barHeight: CGFloat = 44
        let toolbarHeight: CGFloat = 44
        let textHeight = geometry.size.height / 4
        let canvasHeight = geometry.size.height - barHeight - toolbarHeight - textHeight

        return VStack(spacing: 0) {
            toolbarBar
                .frame(height: barHeight)

            DasherCanvasView(viewModel: viewModel)
                .frame(height: canvasHeight)

            Divider().overlay(Color("GridBorder"))

            OutputTextView(viewModel: viewModel)
                .frame(height: textHeight)

            Divider().overlay(Color("BarBorder"))

            speedBar
                .frame(height: toolbarHeight)
        }
    }

    private func landscapeLayout(geometry: GeometryProxy) -> some View {
        let barHeight: CGFloat = 44
        let toolbarHeight: CGFloat = 44
        let textWidth = geometry.size.width * 2 / 9
        let canvasWidth = geometry.size.width - textWidth
        let contentHeight = geometry.size.height - barHeight - toolbarHeight

        return VStack(spacing: 0) {
            toolbarBar
                .frame(height: barHeight)

            HStack(spacing: 0) {
                OutputTextView(viewModel: viewModel)
                    .frame(width: textWidth, height: contentHeight)

                Divider().overlay(Color("GridBorder"))

                DasherCanvasView(viewModel: viewModel)
                    .frame(width: canvasWidth, height: contentHeight)
            }

            Divider().overlay(Color("BarBorder"))

            speedBar
                .frame(height: toolbarHeight)
        }
    }

    private var toolbarBar: some View {
        HStack(spacing: 8) {
            Button(action: { viewModel.newMessage() }) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 14))
                    .foregroundColor(Color("BarText"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
            }
            .buttonStyle(.plain)

            Button(action: { viewModel.togglePlay() }) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color("AccentColor")))
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: { viewModel.eyeGazeMode.toggle() }) {
                Image(systemName: viewModel.eyeGazeMode ? "eye.fill" : "eye")
                    .font(.system(size: 14))
                    .foregroundColor(viewModel.eyeGazeMode ? .white : Color("BarText"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(viewModel.eyeGazeMode ? Color.blue : Color("ButtonBackground")))
            }
            .buttonStyle(.plain)

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(Color("BarText"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .background(Color("BarBackground"))
    }

    private var speedBar: some View {
        HStack(spacing: 12) {
            Text("Speed")
                .font(.system(size: 13))
                .foregroundColor(Color("MutedText"))

            Button(action: { viewModel.decreaseSpeed() }) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("ButtonBackground")))
            }
            .buttonStyle(.plain)

            Text(String(format: "%.1f", viewModel.speed))
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(Color("BarText"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color("ChipBackground")))

            Button(action: { viewModel.increaseSpeed() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("ButtonBackground")))
            }
            .buttonStyle(.plain)

            Spacer()

            PaletteBarPicker(bridge: viewModel.bridge)
        }
        .padding(.horizontal, 14)
        .background(Color("BarBackground"))
    }
}

#Preview {
    ContentView()
}
