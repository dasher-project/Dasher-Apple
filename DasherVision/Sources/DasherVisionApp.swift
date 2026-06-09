import SwiftUI

@main
struct DasherVisionApp: App {
    var body: some Scene {
        WindowGroup {
            VisionContentView()
        }
        .defaultSize(width: 1.2, height: 0.8, depth: 0.0, in: .meters)
    }
}
