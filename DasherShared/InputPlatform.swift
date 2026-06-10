import SwiftUI

struct InputPlatform: OptionSet, Sendable {
    let rawValue: UInt
    static let iOS = InputPlatform(rawValue: 1 << 0)
    static let macOS = InputPlatform(rawValue: 1 << 1)
    static let visionOS = InputPlatform(rawValue: 1 << 2)
}
