import SwiftUI

struct MessagePaneView: View {
    @ObservedObject var viewModel: DasherViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Message")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color("MutedText"))
                .padding(.horizontal, 12)
                .padding(.top, 8)

            TextEditor(text: .constant(viewModel.outputText))
                .font(.system(size: 18))
                .scrollContentBackground(.hidden)
                .background(Color("MessageBackground"))
                .padding(.horizontal, 4)
        }
        .background(Color("MessagePaneBackground"))
    }
}

#Preview {
    MessagePaneView(viewModel: DasherViewModel())
        .frame(width: 300, height: 400)
}
