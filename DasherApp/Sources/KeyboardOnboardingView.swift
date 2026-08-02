import SwiftUI
import DasherShared

/// First-run guide for enabling the Dasher iOS system keyboard (RFC 0008).
///
/// iOS offers no public API to detect keyboard-enablement state, so this is a
/// proactive, copy-driven guide: step-by-step instructions plus a deep link into
/// the app's Settings pane. A heartbeat written by the keyboard extension lets
/// the host app stop prompting once the keyboard is active with Full Access.
struct KeyboardOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    var onOpenSettings: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Use Dasher as your keyboard")
                    .font(.title2.bold())

                Text("Dasher also works as a system keyboard, so you can write in any app. Enable it once in Settings.")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 14) {
                    stepRow("1", "Settings → General → Keyboard")
                    stepRow("2", "Keyboards → Add New Keyboard → Dasher")
                    stepRow("3", "Tap Dasher → turn on Allow Full Access")
                }
                .padding(.vertical, 8)

                Text("Full Access lets Dasher speak what you write and remember your training. The keyboard still works for basic entry without it.")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button {
                        KeyboardOnboarding.markShown()
                        onOpenSettings()
                    } label: {
                        Text("Open Settings").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Not now") {
                        KeyboardOnboarding.markShown()
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(24)
            .navigationTitle("Dasher Keyboard")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func stepRow(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n)
                .font(.subheadline.bold())
                .foregroundStyle(.tint)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
