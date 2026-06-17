import SwiftUI
import LucideIcons

/// Cross-platform SwiftUI wrapper for Lucide icons.
///
/// Replaces `Image(systemName:)` with Lucide icons for visual consistency
/// across Apple, Windows, and GTK frontends (RFC 0002).
///
/// Usage:
/// ```swift
/// LucideIcon("settings", size: 20)
/// LucideIcon("volume-2", size: 18, color: .accentColor)
/// ```
struct LucideIcon: View {
    let name: String
    var size: CGFloat = 20
    var color: Color? = nil

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let image = UIImage(lucideId: name) {
                Image(uiImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            #elseif canImport(AppKit)
            if let image = NSImage.image(lucideId: name) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            #endif
        }
        .frame(width: size, height: size)
        .foregroundStyle(color ?? .primary)
    }
}

/// Label with a Lucide icon, replacing `Label("text", systemImage:)`.
struct LucideLabel: View {
    let title: String
    let icon: String
    var iconSize: CGFloat = 16

    var body: some View {
        Label {
            Text(title)
        } icon: {
            LucideIcon(icon, size: iconSize)
        }
    }

    init(_ title: String, icon: String, iconSize: CGFloat = 16) {
        self.title = title
        self.icon = icon
        self.iconSize = iconSize
    }
}

/// Canonical icon names from RFC 0002.
/// Use these constants instead of raw strings to catch typos at compile time.
enum DasherIcon {
    // Toolbar actions
    static let newDocument = "file-plus"
    static let open = "folder-open"
    static let save = "save"
    static let play = "play"
    static let pause = "pause"
    static let panePosition = "flip-horizontal"
    static let settings = "settings"
    static let copy = "copy"
    static let copyAll = "clipboard-copy"
    static let paste = "clipboard-paste"
    static let speak = "volume-2"
    static let stopSpeak = "circle-stop"
    static let controlMode = "mouse-pointer-click"
    static let gameMode = "gamepad-2"
    static let alphabet = "languages"
    static let speed = "gauge"
    static let learning = "brain-circuit"
    static let keyboard = "keyboard"
    static let turbo = "rabbit"

    // Navigation
    static let chevronDown = "chevron-down"
    static let chevronUp = "chevron-up"
    static let chevronLeft = "chevron-left"
    static let chevronRight = "chevron-right"
    static let close = "x"
    static let check = "check"
    static let more = "ellipsis"

    // Pane positions
    static let paneRight = "panel-right"
    static let paneLeft = "panel-left"
    static let paneBottom = "panel-bottom"
    static let paneTop = "panel-top"

    // Misc
    static let textSize = "type"
    static let palette = "palette"
    static let share = "share"
    static let eye = "eye"
    static let mute = "volume-x"
}
