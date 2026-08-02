import SwiftUI
import UIKit
import DasherShared

@main
struct DasherApp: App {
    @State private var showAnalyticsPrompt = false
    @State private var showKeyboardOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AnalyticsService.shared.initialize()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .sheet(isPresented: $showAnalyticsPrompt) {
                    AnalyticsOptInView()
                }
                .sheet(isPresented: $showKeyboardOnboarding) {
                    KeyboardOnboardingView {
                        openSystemSettings()
                    }
                }
                .onAppear {
                    if !AnalyticsService.shared.hasPrompted {
                        showAnalyticsPrompt = true
                    }
                    maybeShowKeyboardOnboarding()
                    AnalyticsService.shared.capture("app_launched", properties: [
                        "locale": Locale.current.identifier,
                    ])
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        maybeShowKeyboardOnboarding()
                    }
                }
        }
    }

    /// Show the keyboard-enablement guide once, until the keyboard reports ready.
    /// Re-checked on resume so prompting stops after the user enables it.
    private func maybeShowKeyboardOnboarding() {
        guard !KeyboardOnboarding.hasShownOnboarding else { return }
        if KeyboardOnboarding.state == .ready {
            KeyboardOnboarding.markShown()
            return
        }
        if !showAnalyticsPrompt {
            showKeyboardOnboarding = true
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
