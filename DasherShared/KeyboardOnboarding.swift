import Foundation

/// Host-app / keyboard-extension handshake for the iOS keyboard-enablement
/// onboarding (RFC 0008).
///
/// iOS exposes no public API for "is a custom keyboard enabled / selected", so
/// the keyboard extension writes a heartbeat to the App Group the first time the
/// system loads it (and again whenever Full Access changes). The host app reads
/// that heartbeat to drive a guided enablement flow.
public enum KeyboardOnboarding {
    public enum State: Equatable {
        case unknown          // heartbeat never seen — extension not activated yet
        case needsFullAccess  // activated, but Full Access is off
        case ready            // activated and Full Access granted
    }

    private static let activatedKey = "keyboardActivatedAt"
    private static let fullAccessKey = "keyboardHasFullAccess"
    private static let shownKey = "keyboardOnboardingShown"

    /// The latest state the host app can infer from the extension's heartbeat.
    public static var state: State {
        guard let defaults = SharedDefaults.shared,
              defaults.object(forKey: activatedKey) != nil else { return .unknown }
        return defaults.bool(forKey: fullAccessKey) ? .ready : .needsFullAccess
    }

    /// Whether the host app has already shown the enablement guide.
    public static var hasShownOnboarding: Bool {
        SharedDefaults.fallback.bool(forKey: shownKey)
    }

    public static func markShown() {
        SharedDefaults.fallback.set(true, forKey: shownKey)
    }

    /// Called by the keyboard extension when the system loads it. Kept self-
    /// contained (literal suite + keys) so the extension needs no new dependency.
    public static func writeHeartbeat(hasFullAccess: Bool,
                                      suiteName: String = SharedDefaults.groupIdentifier) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(Date(), forKey: activatedKey)
        defaults.set(hasFullAccess, forKey: fullAccessKey)
    }
}
