import SwiftUI

struct OutputTextView: View {
    @ObservedObject var viewModel: DasherViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Message")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color("MutedText"))

                Spacer()

                if !viewModel.outputText.isEmpty {
                    Button(action: { copyText() }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(Color("MutedText"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.outputText)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
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

    private func copyText() {
        UIPasteboard.general.string = viewModel.outputText
    }
}

#Preview {
    OutputTextView(viewModel: DasherViewModel())
        .frame(width: 300, height: 400)
}
