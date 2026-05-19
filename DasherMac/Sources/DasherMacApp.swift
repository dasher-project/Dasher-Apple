import SwiftUI

@main
struct DasherMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Message") {
                    NotificationCenter.default.post(name: .newMessage, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let newMessage = Notification.Name("newMessage")
}
