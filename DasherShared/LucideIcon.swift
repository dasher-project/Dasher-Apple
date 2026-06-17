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
public struct LucideIcon: View {
    let name: String
    var size: CGFloat
    var color: Color?

    public init(_ name: String, size: CGFloat = 20, color: Color? = nil) {
        self.name = name
        self.size = size
        self.color = color
    }

    public var body: some View {
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
public struct LucideLabel: View {
    let title: String
    let icon: String
    var iconSize: CGFloat

    public init(_ title: String, icon: String, iconSize: CGFloat = 16) {
        self.title = title
        self.icon = icon
        self.iconSize = iconSize
    }

    public var body: some View {
        Label {
            Text(title)
        } icon: {
            LucideIcon(icon, size: iconSize)
        }
    }
}

/// Canonical icon names from RFC 0002.
/// Use these constants instead of raw strings to catch typos at compile time.
public enum DasherIcon {
    // Toolbar actions
    public static let newDocument = "file-plus"
    public static let open = "folder-open"
    public static let save = "save"
    public static let play = "play"
    public static let pause = "pause"
    public static let panePosition = "flip-horizontal"
    public static let settings = "settings"
    public static let copy = "copy"
    public static let copyAll = "clipboard-copy"
    public static let paste = "clipboard-paste"
    public static let speak = "volume-2"
    public static let stopSpeak = "circle-stop"
    public static let controlMode = "mouse-pointer-click"
    public static let gameMode = "gamepad-2"
    public static let alphabet = "languages"
    public static let speed = "gauge"
    public static let learning = "brain-circuit"
    public static let keyboard = "keyboard"
    public static let turbo = "rabbit"

    // Navigation
    public static let chevronDown = "chevron-down"
    public static let chevronUp = "chevron-up"
    public static let chevronLeft = "chevron-left"
    public static let chevronRight = "chevron-right"
    public static let close = "x"
    public static let check = "check"
    public static let more = "ellipsis"

    // Pane positions
    public static let paneRight = "panel-right"
    public static let paneLeft = "panel-left"
    public static let paneBottom = "panel-bottom"
    public static let paneTop = "panel-top"

    // Misc
    public static let textSize = "type"
    public static let palette = "palette"
    public static let share = "share"
    public static let eye = "eye"
    public static let mute = "volume-x"
}
