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
        .sheet(isPresented: $showSettings) {
            DasherSettingsView(viewModel: viewModel)
        }
    }

    private func portraitLayout(geometry: GeometryProxy) -> some View {
        let barHeight: CGFloat = 44
        let bottomBarHeight: CGFloat = 44
        let textHeight = geometry.size.height / 4
        let canvasHeight = geometry.size.height - barHeight - bottomBarHeight - textHeight

        return VStack(spacing: 0) {
            toolbarBar
                .frame(height: barHeight)

            DasherCanvasView(viewModel: viewModel)
                .frame(height: canvasHeight)

            Divider().overlay(Color("GridBorder"))

            OutputTextView(viewModel: viewModel)
                .frame(height: textHeight)

            Divider().overlay(Color("BarBorder"))

            bottomBar
                .frame(height: bottomBarHeight)
        }
    }

    private func landscapeLayout(geometry: GeometryProxy) -> some View {
        let barHeight: CGFloat = 44
        let bottomBarHeight: CGFloat = 44
        let textWidth = geometry.size.width * 2 / 9
        let canvasWidth = geometry.size.width - textWidth
        let contentHeight = geometry.size.height - barHeight - bottomBarHeight

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

            bottomBar
                .frame(height: bottomBarHeight)
        }
    }

    private var toolbarBar: some View {
        HStack(spacing: 8) {
            Button(action: { viewModel.newMessage() }) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 16))
                    .foregroundColor(Color("DeepNavy"))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color("ButtonBackground")))
            }
            .buttonStyle(.plain)

            Button(action: { viewModel.togglePlay() }) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color("AccentColor")))
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: { viewModel.pointerHoverEnabled.toggle() }) {
                Image(systemName: viewModel.pointerHoverEnabled ? "eye.fill" : "eye")
                    .font(.system(size: 16))
                    .foregroundColor(viewModel.pointerHoverEnabled ? .white : Color("BarText"))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(viewModel.pointerHoverEnabled ? Color("AccentColor") : Color("ButtonBackground")))
            }
            .buttonStyle(.plain)

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundColor(Color("BarText"))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color("ButtonBackground")))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .background(Color("BarBackground"))
    }

    private var bottomBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                alphabetPicker
                barDivider
                speedStepper
                barDivider
                learningToggle
                barDivider
                palettePicker
                barDivider
                fontPicker
                barDivider
                fontSizeStepper
                barDivider
                speechPicker
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 44)
        .background(Color("BarBackground"))
    }

    private var barDivider: some View {
        Rectangle()
            .fill(Color("Divider"))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 8)
    }

    private var alphabetPicker: some View {
        let alphabets = viewModel.bridge.allAlphabets
        return Menu {
            ForEach(alphabets, id: \.name) { a in
                Button(a.name) { viewModel.bridge.setAlphabetId(a.name) }
            }
        } label: {
            HStack(spacing: 3) {
                Text(viewModel.bridge.alphabetId)
                    .font(.system(size: 13))
                    .foregroundColor(Color("BarText"))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Color("MutedText"))
            }
        }
    }

    private var speedStepper: some View {
        HStack(spacing: 0) {
            Text("Speed ")
                .font(.system(size: 12))
                .foregroundColor(Color("MutedText"))

            stepperBox(
                label: String(format: "%.1f", viewModel.speed),
                onDecrement: { viewModel.decreaseSpeed() },
                onIncrement: { viewModel.increaseSpeed() }
            )
        }
    }

    private var learningToggle: some View {
        let binding = Binding<Bool>(
            get: { viewModel.bridge.getBoolParameter(key: 15) },
            set: { viewModel.bridge.setBoolParameter(key: 15, value: $0) }
        )
        return Toggle("Learning ", isOn: binding)
            .font(.system(size: 12))
            .toggleStyle(.switch)
            .controlSize(.small)
    }

    private var palettePicker: some View {
        let palettes = viewModel.bridge.allPalettes
        return Menu {
            ForEach(palettes, id: \.name) { p in
                Button(action: { viewModel.bridge.setPalette(p.name) }) {
                    Label(p.name, systemImage: "circle.fill")
                }
            }
        } label: {
            paletteSwatchIcon
                .overlay(
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(Color("MutedText"))
                        .offset(x: 12, y: 8)
                )
        }
    }

    private var paletteSwatchIcon: some View {
        let palettes = viewModel.bridge.allPalettes
        let currentName = viewModel.bridge.currentPalette
        let palette = palettes.first { $0.name == currentName } ?? palettes.first
        let colors = palette?.previewColors ?? []

        return HStack(spacing: 1) {
            VStack(spacing: 1) {
                Circle().fill(colors.count > 0 ? Color(cgColor: colors[0]) : Color.gray).frame(width: 7, height: 7)
                Circle().fill(colors.count > 2 ? Color(cgColor: colors[2]) : Color.gray).frame(width: 7, height: 7)
            }
            VStack(spacing: 1) {
                Circle().fill(colors.count > 1 ? Color(cgColor: colors[1]) : Color.gray).frame(width: 7, height: 7)
                Circle().fill(colors.count > 3 ? Color(cgColor: colors[3]) : Color.gray).frame(width: 7, height: 7)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color("ButtonBackground")))
    }

    private var fontPicker: some View {
        let fontValues = viewModel.bridge.getStringValues(key: 99)
        let currentFont = viewModel.bridge.getStringParameter(key: 99)
        return Menu {
            ForEach(fontValues, id: \.self) { f in
                Button(f) { viewModel.bridge.setStringParameter(key: 99, value: f) }
            }
        } label: {
            HStack(spacing: 3) {
                Text(currentFont)
                    .font(.system(size: 13))
                    .foregroundColor(Color("BarText"))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Color("MutedText"))
            }
        }
    }

    private var fontSizeStepper: some View {
        let binding = Binding<Int>(
            get: { viewModel.bridge.getLongParameter(key: 33) },
            set: { viewModel.bridge.setLongParameter(key: 33, value: $0) }
        )
        return HStack(spacing: 0) {
            stepperBox(
                label: "\(binding.wrappedValue)",
                onDecrement: { viewModel.bridge.setLongParameter(key: 33, value: max(8, binding.wrappedValue - 1)) },
                onIncrement: { viewModel.bridge.setLongParameter(key: 33, value: min(72, binding.wrappedValue + 1)) }
            )
        }
    }

    private var speechPicker: some View {
        let isOn = viewModel.bridge.getBoolParameter(key: 24)
        return Menu {
            Button("Speech on") { viewModel.bridge.setBoolParameter(key: 24, value: true) }
            Button("Speech off") { viewModel.bridge.setBoolParameter(key: 24, value: false) }
        } label: {
            HStack(spacing: 3) {
                Text(isOn ? "Speech on" : "Speech off")
                    .font(.system(size: 13))
                    .foregroundColor(Color("BarText"))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Color("MutedText"))
            }
        }
    }

    private func stepperBox(label: String, onDecrement: @escaping () -> Void, onIncrement: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: onDecrement) {
                Text("–")
                    .font(.system(size: 14))
                    .foregroundColor(Color("BarText"))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color("BarText"))
                .frame(minWidth: 30)
                .padding(.horizontal, 4)
                .overlay(Rectangle().fill(Color("Divider")).frame(width: 1), alignment: .leading)
                .overlay(Rectangle().fill(Color("Divider")).frame(width: 1), alignment: .trailing)

            Button(action: onIncrement) {
                Text("+")
                    .font(.system(size: 14))
                    .foregroundColor(Color("BarText"))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color("Divider"), lineWidth: 1)
        )
    }
}

#Preview {
    ContentView()
}
