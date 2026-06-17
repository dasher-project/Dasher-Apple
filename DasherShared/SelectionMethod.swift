import SwiftUI

public enum SelectionMethod: String, CaseIterable, Identifiable, Codable {
    case continuous
    case pressToMove
    case clickToZoom
    case dwell
    case oneSwitch
    case twoSwitches
    case twoPush
    case scanning
    case directBoxes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .continuous: return "Continuous"
        case .pressToMove: return "Press to Move"
        case .clickToZoom: return "Click to Zoom"
        case .dwell: return "Dwell"
        case .oneSwitch: return "1 Switch"
        case .twoSwitches: return "2 Switches"
        case .twoPush: return "2 Push"
        case .scanning: return "Scanning"
        case .directBoxes: return "Direct Boxes"
        }
    }

    public var subtitle: String {
        switch self {
        case .continuous: return "Always follows pointer"
        case .pressToMove: return "Hold to move, release to pause"
        case .clickToZoom: return "Click to zoom into area"
        case .dwell: return "Hold still to select"
        case .oneSwitch: return "Single switch, dynamic timing"
        case .twoSwitches: return "Two switches, up/down"
        case .twoPush: return "Single switch, push timing"
        case .scanning: return "Auto-scan boxes, press to select"
        case .directBoxes: return "Press to select a box"
        }
    }

    public var iconName: String {
        switch self {
        case .continuous: return DasherIcon.controlMode
        case .pressToMove: return "pointer"
        case .clickToZoom: return "zoom-in"
        case .dwell: return DasherIcon.eye
        case .oneSwitch: return "circle"
        case .twoSwitches: return "circle-dot"
        case .twoPush: return "circle-dot"
        case .scanning: return "layout-grid"
        case .directBoxes: return "grid-3x3"
        }
    }

    public var filterName: String {
        switch self {
        case .continuous: return "Normal Control"
        case .pressToMove: return "Press Mode"
        case .clickToZoom: return "Click Mode"
        case .dwell: return "Normal Control"
        case .oneSwitch: return "One Button Dynamic Mode"
        case .twoSwitches: return "Two Button Dynamic Mode"
        case .twoPush: return "Two Push Dynamic Mode"
        case .scanning: return "Menu Mode"
        case .directBoxes: return "Direct Mode"
        }
    }

    public var isSwitchBased: Bool {
        switch self {
        case .oneSwitch, .twoSwitches, .twoPush, .scanning, .directBoxes:
            return true
        default:
            return false
        }
    }

    public var requiredSwitchCount: Int {
        switch self {
        case .oneSwitch, .twoPush: return 1
        case .twoSwitches: return 2
        case .scanning, .directBoxes: return 1
        default: return 0
        }
    }

    public static func validFor(method: AccessMethod) -> [SelectionMethod] {
        allCases.filter { $0.isCompatible(with: method) }
    }

    private func isCompatible(with method: AccessMethod) -> Bool {
        switch method {
        case .pointer, .touch:
            return true
        case .eyeGaze:
            switch self {
            case .continuous, .dwell, .oneSwitch, .twoSwitches, .scanning, .directBoxes:
                return true
            default:
                return false
            }
        case .tilt:
            switch self {
            case .continuous, .pressToMove, .oneSwitch, .twoSwitches, .twoPush, .scanning, .directBoxes:
                return true
            default:
                return false
            }
        case .joystick:
            switch self {
            case .continuous, .pressToMove, .clickToZoom, .oneSwitch, .twoSwitches, .scanning, .directBoxes:
                return true
            default:
                return false
            }
        case .handTracking:
            switch self {
            case .continuous, .dwell, .oneSwitch, .twoSwitches:
                return true
            default:
                return false
            }
        case .switchesOnly:
            return isSwitchBased
        }
    }
}
