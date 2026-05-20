import SwiftUI
import UniformTypeIdentifiers

@main
struct DasherMacApp: App {
    @StateObject private var viewModel = MacDasherViewModel()
    @State private var showSettings = false

    var body: some Scene {
        WindowGroup {
            MacContentView(viewModel: viewModel)
                .sheet(isPresented: $showSettings) {
                    MacSettingsView(viewModel: viewModel)
                }
                .fileImporter(
                    isPresented: $viewModel.showOpenFile,
                    allowedContentTypes: [.plainText],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            if let text = try? String(contentsOf: url, encoding: .utf8) {
                                viewModel.openText(text)
                            }
                        }
                    case .failure:
                        break
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Message") {
                    viewModel.newMessage()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Open...") {
                    viewModel.showOpenFile = true
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandGroup(after: .saveItem) {
                Button("Save...") {
                    saveFile()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    showSettings = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu("Input") {
                Button(viewModel.isPlaying ? "Pause" : "Play") {
                    viewModel.togglePlay()
                }
                .keyboardShortcut("p", modifiers: [.command])

                Button("Increase Speed") {
                    viewModel.increaseSpeed()
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Decrease Speed") {
                    viewModel.decreaseSpeed()
                }
                .keyboardShortcut("-", modifiers: [.command])
            }
        }
    }

    private func saveFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "dasher-output.txt"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                viewModel.saveText(to: url)
            }
        }
    }
}

struct MacSettingsView: View {
    @ObservedObject var viewModel: MacDasherViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Dasher Settings")
                .font(.headline)

            Form {
                Toggle("Show Message Pane", isOn: $viewModel.showMessagePane)

                HStack {
                    Text("Speed")
                    Slider(value: Binding(
                        get: { Double(viewModel.bridge.speedPercent) },
                        set: { viewModel.bridge.setSpeedPercent(Int($0)) }
                    ), in: 20...400)
                    Text("\(viewModel.bridge.speedPercent)%")
                        .monospacedDigit()
                        .frame(width: 50)
                }

                Picker("Alphabet", selection: Binding(
                    get: { viewModel.bridge.alphabetId },
                    set: { viewModel.bridge.setAlphabetId($0) }
                )) {
                    ForEach(viewModel.bridge.allAlphabets, id: \.name) { a in
                        Text(a.name).tag(a.name)
                    }
                }

                Picker("Colour Theme", selection: Binding(
                    get: { viewModel.bridge.currentPalette },
                    set: { viewModel.bridge.setPalette($0) }
                )) {
                    ForEach(viewModel.bridge.allPalettes, id: \.name) { p in
                        Text(p.name).tag(p.name)
                    }
                }

                Toggle("Learning Mode", isOn: Binding(
                    get: { viewModel.bridge.getBoolParameter(key: 15) },
                    set: { viewModel.bridge.setBoolParameter(key: 15, value: $0) }
                ))

                Toggle("Speech Output", isOn: Binding(
                    get: { viewModel.bridge.getBoolParameter(key: 24) },
                    set: { viewModel.bridge.setBoolParameter(key: 24, value: $0) }
                ))
            }
            .frame(width: 400)

            HStack {
                Spacer()
                Button("Done") {
                    viewModel.bridge.saveSettings()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
