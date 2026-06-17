import SwiftUI

/// First-launch analytics opt-in dialog (RFC 0001).
/// Mirrors the Windows `ShowAnalyticsOptIn` dialog.
public struct AnalyticsOptInView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 12) {
                Text("Help improve Dasher")
                    .font(.title2.bold())
                    .foregroundColor(Color("DeepNavy"))

                Text("Dasher collects anonymous, privacy-respecting analytics to understand usage patterns and fix crashes. No typed text, clipboard contents, or personal information is ever collected.\n\nYou can change this anytime in Settings > Privacy.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    AnalyticsService.shared.setOptIn(true)
                    dismiss()
                } label: {
                    Text("Help improve Dasher")
                        .font(.headline)
                        .foregroundColor(Color("DeepNavy"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color("DasherTeal"))
                        .cornerRadius(10)
                }

                Button {
                    AnalyticsService.shared.setOptIn(false)
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

/// Settings > Privacy section for analytics controls.
public struct AnalyticsPrivacySection: View {
    @State private var optedIn = AnalyticsService.shared.isOptedIn

    public init() {}

    public var body: some View {
        Section {
            Toggle("Anonymous usage analytics", isOn: $optedIn)
                .onChange(of: optedIn) { _, value in
                    AnalyticsService.shared.setOptIn(value)
                }

            if optedIn {
                Button("Reset anonymous ID") {
                    AnalyticsService.shared.resetAnonymousId()
                }
                .foregroundColor(.accentColor)
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Dasher collects anonymous analytics to understand usage and fix crashes. No typed text, clipboard, or personal info is ever collected. See the open event schema at github.com/dasher-project/Dasher-Apple.")
        }
    }
}
