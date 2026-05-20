import SwiftUI

struct OutputTextView: View {
    @ObservedObject var viewModel: DasherViewModel

    var body: some View {
        VStack(spacing: 0) {
            messageToolbarBar
                .frame(height: 56)

            Divider().overlay(Color("BarBorder"))

            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.outputText)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .id("outputText")
                }
                .onChange(of: viewModel.outputText) { _, _ in
                    withAnimation {
                        proxy.scrollTo("outputText", anchor: .bottom)
                    }
                }
            }
        }
        .background(Color("MessagePaneBackground"))
    }

    private var messageToolbarBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: {
                    let current = viewModel.bridge.getBoolParameter(key: 24)
                    viewModel.bridge.setBoolParameter(key: 24, value: !current)
                }) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 15))
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 8))
                            .offset(x: 3, y: 1)
                    }
                    .foregroundColor(Color("BarText"))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color("ButtonBackground")))
                }
                .buttonStyle(.plain)

                messageBarDivider

                HStack(spacing: 6) {
                    messageToolbarButton(icon: "doc.on.doc", label: "Copy") {
                        copyAllText()
                    }
                    messageToolbarButton(icon: "doc.on.clipboard", label: "Paste") {
                        pasteText()
                    }
                }

                messageBarDivider

                messageToolbarButton(icon: "xmark.circle", label: "Clear") {
                    viewModel.newMessage()
                }
            }
            .padding(.horizontal, 10)
        }
        .background(Color("BarBackground"))
    }

    private func messageToolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color("BarText"))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color("MutedText"))
            }
            .frame(width: 46, height: 46)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color("ButtonBackground")))
        }
        .buttonStyle(.plain)
    }

    private var messageBarDivider: some View {
        Rectangle()
            .fill(Color("Divider"))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }

    private func copyAllText() {
        UIPasteboard.general.string = viewModel.outputText
    }

    private func pasteText() {
        if let clipboardString = UIPasteboard.general.string {
            viewModel.bridge.resetOutputText()
            viewModel.outputText = clipboardString
        }
    }
}

#Preview {
    OutputTextView(viewModel: DasherViewModel())
        .frame(width: 320, height: 400)
}
