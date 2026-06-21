import Foundation
import SwiftUI

extension Notification.Name {
    public static let outputFontChanged = Notification.Name("dasher.outputFontChanged")
}

/// User preference for the output text area font. Stored in UserDefaults.standard
/// (not shared App Group — it's a display preference, not a DasherCore engine setting).
public enum OutputFontSettings {
    private static let fontNameKey = "dasher.output_font_name"
    private static let fontSizeKey = "dasher.output_font_size"

    public static var fontName: String {
        get { UserDefaults.standard.string(forKey: fontNameKey) ?? "System" }
        set { UserDefaults.standard.set(newValue, forKey: fontNameKey) }
    }

    public static var fontSize: Double {
        get { UserDefaults.standard.object(forKey: fontSizeKey) as? Double ?? 18 }
        set { UserDefaults.standard.set(newValue, forKey: fontSizeKey) }
    }

    public static let availableFonts: [String] = [
        "System",
        "Georgia",
        "Helvetica Neue",
        "Menlo",
        "Courier New",
        "Avenir Next",
        "Futura",
        "Palatino",
        "Trebuchet MS",
        "Verdana",
    ]

    /// SwiftUI Font for the output text area.
    public static var font: Font {
        let name = fontName
        let size = fontSize
        if name == "System" || name.isEmpty {
            return .system(size: size)
        }
        return .custom(name, size: size)
    }
}
