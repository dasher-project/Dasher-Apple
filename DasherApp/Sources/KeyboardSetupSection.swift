import SwiftUI
import UIKit
import DasherShared

/// Always-available iOS keyboard setup status + re-trigger (RFC 0008).
/// Lets the user re-run enablement from Settings and shows live state from the
/// keyboard extension's heartbeat.
struct KeyboardSetupSection: View {
    @State private var state: KeyboardOnboarding.State = .unknown

    var body: some View {
        Section {
            HStack {
                Text("Dasher keyboard")
                Spacer()
                Text(statusText)
                    .foregroundColor(statusColor)
            }
            Button("Open Keyboard Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } header: {
            Text("Keyboard")
        } footer: {
            Text("Enable Dasher under Settings → General → Keyboard → Keyboards, then turn on Allow Full Access so Dasher can speak and learn.")
        }
        .onAppear { state = KeyboardOnboarding.state }
    }

    private var statusText: String {
        switch state {
        case .unknown: return "Not enabled"
        case .needsFullAccess: return "Needs Full Access"
        case .ready: return "Ready"
        }
    }

    private var statusColor: Color {
        switch state {
        case .ready: return .green
        case .needsFullAccess: return .orange
        case .unknown: return .secondary
        }
    }
}
