import SwiftUI
import DasherShared

@main
struct DasherApp: App {
    @State private var showAnalyticsPrompt = false

    init() {
        AnalyticsService.shared.initialize()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .sheet(isPresented: $showAnalyticsPrompt) {
                    AnalyticsOptInView()
                }
                .onAppear {
                    if !AnalyticsService.shared.hasPrompted {
                        showAnalyticsPrompt = true
                    }
                    AnalyticsService.shared.capture("app_launched", properties: [
                        "locale": Locale.current.identifier,
                    ])
                }
        }
    }
}
