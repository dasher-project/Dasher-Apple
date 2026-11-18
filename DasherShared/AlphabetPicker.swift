import SwiftUI

public struct AlphabetPicker: View {
    let names: [String]
    @Binding var selection: String
    @AppStorage(AlphabetIndex.showAllLanguagesKey, store: SharedDefaults.fallback)
    private var showAllLanguages = false

    public init(names: [String], selection: Binding<String>) {
        self.names = names
        _selection = selection
    }

    public var body: some View {
        Picker("Alphabet", selection: $selection) {
            ForEach(AlphabetIndex.visibleNames(names, selectedID: selection, showAll: showAllLanguages), id: \.self) { name in
                Text(name).tag(name)
            }
        }
        Toggle("Show All Languages", isOn: $showAllLanguages)
    }
}
