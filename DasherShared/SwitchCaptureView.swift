import SwiftUI

public struct SwitchCaptureRow: View {
    @Binding public var slot: SwitchSlot
    public let bridge: AccessSettingsBridge

    @State private var isCapturing = false

    public var body: some View {
        HStack {
            LucideIcon(slot.isAssigned ? "circle-dot" : "circle", color: slot.isAssigned ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(slot.label)
                if slot.isAssigned {
                    Text(slot.keyDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(isCapturing ? "Press key or switch now..." : (slot.isAssigned ? "Reassign" : "Assign")) {
                isCapturing = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            #if os(iOS) || os(visionOS)
            .keyboardShortcut(nil)
            #endif
        }
        .contentShape(Rectangle())
        #if os(macOS)
        .onKeyPress(phases: .down) { keyPress in
            guard isCapturing else { return .ignored }
            let code = keyCodeFromEvent(keyPress)
            if code > 0 {
                slot.keyCode = code
                isCapturing = false
                return .handled
            }
            return .ignored
        }
        #endif
        #if os(iOS) || os(visionOS)
        .onAppear {
            NotificationCenter.default.addObserver(forName: .dasherKeyDown, object: nil, queue: .main) { notification in
                guard isCapturing, let code = notification.userInfo?["keyCode"] as? Int else { return }
                slot.keyCode = code
                isCapturing = false
            }
        }
        #endif
    }

    #if os(macOS)
    private func keyCodeFromEvent(_ keyPress: KeyPress) -> Int {
        switch keyPress.key {
        case .space: return 32
        case .return: return 13
        case .tab: return 9
        case .escape: return 27
        case .upArrow: return 63232
        case .downArrow: return 63233
        case .leftArrow: return 63234
        case .rightArrow: return 63235
        default:
            let chars = keyPress.characters
            if chars.count == 1, let first = chars.first, first.isASCII {
                return Int(first.asciiValue!)
            }
            return 0
        }
    }
    #endif
}

extension Notification.Name {
    public static let dasherKeyDown = Notification.Name("dasherKeyDown")
}
