import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = DasherViewModel()

    var body: some View {
        VStack(spacing: 0) {
            TopBarView(viewModel: viewModel)
            Divider().overlay(Color("BarBorder"))

            GeometryReader { geo in
                HStack(spacing: 0) {
                    DasherCanvasView(viewModel: viewModel)
                        .frame(width: viewModel.showMessagePane ? geo.size.width * 0.65 : geo.size.width)

                    if viewModel.showMessagePane {
                        Divider().overlay(Color("GridBorder"))
                        MessagePaneView(viewModel: viewModel)
                            .frame(width: geo.size.width * 0.35 - 1)
                    }
                }
            }

            Divider().overlay(Color("BarBorder"))
            BottomBarView(viewModel: viewModel)
        }
        .background(Color("BarBackground").ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView()
}
