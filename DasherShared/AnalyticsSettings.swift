import Foundation

/// Persists analytics opt-in state and anonymous ID using UserDefaults.
/// Mirrors `AnalyticsSettings.cs` from Dasher-Windows.
public struct AnalyticsSettings: Codable {
    public var optedIn: Bool
    public var promptShown: Bool
    public var anonymousId: String?

    private static let key = "dasher.analytics.settings"
    private static var defaults: UserDefaults {
        UserDefaults.standard
    }

    public init() {
        optedIn = false
        promptShown = false
        anonymousId = nil
    }

    public static func load() -> AnalyticsSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AnalyticsSettings.self, from: data)
        else { return AnalyticsSettings() }
        return decoded
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            Self.defaults.set(data, forKey: Self.key)
        }
    }

    public mutating func getOrCreateAnonymousId() -> String {
        if let id = anonymousId, !id.isEmpty { return id }
        anonymousId = UUID().uuidString
        save()
        return anonymousId!
    }

    public mutating func resetAnonymousId() {
        anonymousId = UUID().uuidString
        save()
    }
}
