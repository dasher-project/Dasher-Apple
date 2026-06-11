import Foundation

public enum SharedDefaults {
    public static let groupIdentifier = "group.at.dasher.Dasher"

    public static var shared: UserDefaults? {
        UserDefaults(suiteName: groupIdentifier)
    }

    public static var fallback: UserDefaults {
        shared ?? .standard
    }
}
