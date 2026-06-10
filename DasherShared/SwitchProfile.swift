import Foundation

struct SwitchProfile: Codable, Equatable {
    var switches: [SwitchSlot]
    var scanRateMs: Int

    static let maxSwitches = 4

    init() {
        switches = [
            SwitchSlot(id: 1, label: "Switch 1", keyCode: nil, dasherButton: 2),
            SwitchSlot(id: 2, label: "Switch 2", keyCode: nil, dasherButton: 3),
            SwitchSlot(id: 3, label: "Switch 3", keyCode: nil, dasherButton: 4),
            SwitchSlot(id: 4, label: "Switch 4", keyCode: nil, dasherButton: 1),
        ]
        scanRateMs = 600
    }

    var assignedSwitches: [SwitchSlot] {
        switches.filter { $0.keyCode != nil }
    }

    var buttonMapString: String {
        let assigned = switches.filter { $0.keyCode != nil && $0.dasherButton > 0 }
        guard !assigned.isEmpty else { return "" }
        return assigned.map { "\($0.keyCode!)=\($0.dasherButton)" }.joined(separator: " ")
    }
}

struct SwitchSlot: Codable, Identifiable, Equatable {
    let id: Int
    var label: String
    var keyCode: Int?
    var dasherButton: Int

    var isAssigned: Bool { keyCode != nil }

    var keyDisplayName: String {
        guard let code = keyCode else { return "Not set" }
        return SwitchSlot.keyName(for: code)
    }

    static func keyName(for code: Int) -> String {
        switch code {
        case 32: return "Space"
        case 13: return "Enter"
        case 9: return "Tab"
        case 27: return "Escape"
        case 63232: return "Up Arrow"
        case 63233: return "Down Arrow"
        case 63234: return "Left Arrow"
        case 63235: return "Right Arrow"
        case 63236: return "F1"
        case 63237: return "F2"
        case 63238: return "F3"
        case 63239: return "F4"
        case 63240: return "F5"
        case 63241: return "F6"
        case 63242: return "F7"
        case 63243: return "F8"
        case 63244: return "F9"
        case 63245: return "F10"
        case 63246: return "F11"
        case 63247: return "F12"
        default:
            if code >= 65, code <= 90 { return String(UnicodeScalar(code)!) }
            if code >= 48, code <= 57 { return String(UnicodeScalar(code)!) }
            return "Key \(code)"
        }
    }
}
