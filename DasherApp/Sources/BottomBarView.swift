import SwiftUI

struct BottomBarView: View {
    @ObservedObject var viewModel: DasherViewModel

    var body: some View {
        HStack(spacing: 16) {
            Text("Speed")
                .font(.system(size: 13))
                .foregroundColor(Color("MutedText"))

            Button(action: { viewModel.decreaseSpeed() }) {
                Text("-")
                    .font(.system(size: 16, weight: .medium))
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
                Text("+")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color("ButtonBackground")))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Auto")
                .font(.system(size: 13))
                .foregroundColor(Color("MutedText"))

            Toggle("", isOn: $viewModel.autoSpeed)
                .labelsHidden()
                .scaleEffect(0.8)

            Spacer()

            Text("Colour")
                .font(.system(size: 13))
                .foregroundColor(Color("MutedText"))

            HStack(spacing: 6) {
                ForEach(0..<viewModel.colourPresets.count, id: \.self) { index in
                    let preset = viewModel.colourPresets[index]
                    Button(action: { viewModel.selectedColourIndex = index }) {
                        Circle()
                            .fill(preset.1)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(viewModel.selectedColourIndex == index ? Color("AccentColor") : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color("BarBackground"))
    }
}

#Preview {
    BottomBarView(viewModel: DasherViewModel())
}
