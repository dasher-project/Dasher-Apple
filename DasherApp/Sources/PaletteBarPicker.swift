import SwiftUI

struct PaletteBarPicker: View {
    let bridge: DasherBridge
    @State private var palettes: [DasherPalette] = []

    private let maxVisible = 5

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<min(palettes.count, maxVisible), id: \.self) { i in
                let palette = palettes[i]
                let isSelected = bridge.currentPalette == palette.name
                Button(action: { bridge.setPalette(palette.name) }) {
                    HStack(spacing: 1) {
                        ForEach(0..<min(palette.previewColors.count, 3), id: \.self) { ci in
                            Circle()
                                .fill(Color(cgColor: palette.previewColors[ci]))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isSelected ? Color("AccentColor").opacity(0.2) : Color.clear)
                    )
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color("AccentColor") : Color("Divider"), lineWidth: isSelected ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            palettes = bridge.allPalettes
        }
    }
}
