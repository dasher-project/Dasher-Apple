import SwiftUI

public struct InputPlatform: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let iOS = InputPlatform(rawValue: 1 << 0)
    public static let macOS = InputPlatform(rawValue: 1 << 1)
    public static let visionOS = InputPlatform(rawValue: 1 << 2)
}
