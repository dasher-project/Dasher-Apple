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
            if let image = UIImage.lucideIcon(name, size: size) {
                Image(uiImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
            }
            #elseif canImport(AppKit)
            if let image = NSImage.lucideIcon(name, size: size) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
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
            Text(LocalizedStringKey(title))
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
    public static let cut = "scissors"
    public static let paste = "clipboard-paste"
    public static let backspace = "delete"
    public static let arrowLeft = "arrow-left"
    public static let arrowRight = "arrow-right"
    public static let reanchor = "locate"
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


/// Normalized icon loading.
///
/// The compiled asset catalog ships each Lucide glyph as a Vector rendition
/// plus 18pt/36pt raster fallbacks; which one `image(forResource:)` hands
/// back — and the point size it reports — varies by SDK. Binaries built
/// with the Xcode 26.6 SDK rendered toolbar *menu* labels (layout picker,
/// alphabet-picker chevron) with the glyph's aspect distorted: a square
/// glyph drawn as a narrow pill. Rasterizing to an exact square at the
/// requested size before handing the image to SwiftUI makes the result
/// aspect-proof under every menu/toolbar metric path and SDK.
// Review round 1: rasterization is cached per (id, size) — LucideIcon body
// re-evaluates on every typing-rate update and re-rasterizing ~26 glyphs
// per keystroke was wasteful. The backing scale is taken from the screen
// explicitly (lockFocus alone can silently pick 1x in offscreen contexts,
// producing blurry Retina output).
#if canImport(AppKit)
import AppKit

private let lucideAppKitCache = NSCache<NSString, NSImage>()

public extension NSImage {
    static func lucideIcon(_ id: String, size: CGFloat) -> NSImage? {
        let key = "\(id)-\(Int(size))" as NSString
        if let cached = lucideAppKitCache.object(forKey: key) { return cached }
        guard let source = NSImage.image(lucideId: id) else { return nil }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixels = max(1, Int(size * scale))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: NSColorSpaceName.deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            return source
        }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                    from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        let normalized = NSImage(size: NSSize(width: size, height: size))
        normalized.addRepresentation(rep)
        lucideAppKitCache.setObject(normalized, forKey: key)
        return normalized
    }
}
#endif

#if canImport(UIKit)
import UIKit

private let lucideUIKitCache = NSCache<NSString, UIImage>()

public extension UIImage {
    static func lucideIcon(_ id: String, size: CGFloat) -> UIImage? {
        let key = "\(id)-\(Int(size))" as NSString
        if let cached = lucideUIKitCache.object(forKey: key) { return cached }
        guard let source = UIImage(lucideId: id) else { return nil }
        // Format default() already carries the trait-collection display
        // scale; no UIScreen.main reference (deprecated, wrong off-device).
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        let normalized = renderer.image { _ in
            source.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        lucideUIKitCache.setObject(normalized, forKey: key)
        return normalized
    }
}
#endif
