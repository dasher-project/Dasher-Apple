import SwiftUI

struct TopBarView: View {
    @ObservedObject var viewModel: DasherViewModel

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                BarButton(title: "New") { viewModel.newMessage() }
                BarDivider()
                BarButton(title: viewModel.isPlaying ? "Pause" : "Play", isAccent: viewModel.isPlaying) {
                    viewModel.togglePlay()
                }
            }

            Spacer()

            BarButton(title: viewModel.showMessagePane ? "Hide Pane" : "Show Pane") {
                viewModel.toggleMessagePane()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Color("BarBackground"))
    }
}

struct BarButton: View {
    let title: String
    var isAccent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(isAccent ? .white : Color("BarText"))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isAccent ? Color("AccentColor") : Color("ButtonBackground"))
                )
        }
        .buttonStyle(.plain)
    }
}

struct BarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color("Divider"))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
}

#Preview {
    TopBarView(viewModel: DasherViewModel())
}
