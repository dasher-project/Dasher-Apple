import SwiftUI

public enum AccessMethod: String, CaseIterable, Identifiable, Codable {
    case pointer
    case touch
    case eyeGaze
    case tilt
    case joystick
    case handTracking
    case switchesOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pointer: return "Pointer"
        case .touch: return "Touch"
        case .eyeGaze: return "Eye Gaze"
        case .tilt: return "Tilt"
        case .joystick: return "Joystick / Gamepad"
        case .handTracking: return "Hand Tracking"
        case .switchesOnly: return "Switches Only"
        }
    }

    public var subtitle: String {
        switch self {
        case .pointer: return "Mouse or trackpad"
        case .touch: return "Direct touch or stylus"
        case .eyeGaze: return "Eye tracker camera"
        case .tilt: return "Tilt device to steer"
        case .joystick: return "Gamepad or joystick"
        case .handTracking: return "Pinch and hand position"
        case .switchesOnly: return "No continuous steering"
        }
    }

    public var iconName: String {
        switch self {
        case .pointer: return DasherIcon.controlMode
        case .touch: return "hand"
        case .eyeGaze: return DasherIcon.eye
        case .tilt: return "move"
        case .joystick: return DasherIcon.gameMode
        case .handTracking: return "hand"
        case .switchesOnly: return "toggle-right"
        }
    }

    public var availablePlatforms: InputPlatform {
        switch self {
        case .pointer: return [.iOS, .macOS]
        case .touch: return .iOS
        case .eyeGaze: return [.iOS, .macOS, .visionOS]
        case .tilt: return .iOS
        case .joystick: return .macOS
        case .handTracking: return .visionOS
        case .switchesOnly: return [.iOS, .macOS, .visionOS]
        }
    }

    public var isAvailable: Bool {
        #if os(iOS)
        availablePlatforms.contains(.iOS)
        #elseif os(macOS)
        availablePlatforms.contains(.macOS)
        #elseif os(visionOS)
        availablePlatforms.contains(.visionOS)
        #else
        false
        #endif
    }

    public var hasContinuousInput: Bool {
        self != .switchesOnly
    }
}
