import SwiftUI

enum DC {
    @MainActor static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static var bg: Color {
        Color(red: 0.9569, green: 0.9686, blue: 0.9647)
    }

    static var bgDark: Color {
        Color(red: 0.0706, green: 0.0941, blue: 0.1059)
    }

    static var text: Color {
        Color(red: 0.0588, green: 0.2941, blue: 0.4588)
    }

    static var textDark: Color {
        Color.white
    }

    static var navy: Color {
        Color(red: 0.0588, green: 0.2941, blue: 0.4588)
    }

    static var btnBg: Color {
        Color.white
    }

    static var btnBgDark: Color {
        Color(red: 0.1176, green: 0.1490, blue: 0.1686)
    }

    static var muted: Color {
        Color(red: 0.0588, green: 0.2941, blue: 0.4588)
    }

    static var mutedDark: Color {
        Color(red: 0.6000, green: 0.8314, blue: 0.8039)
    }

    static var div: Color {
        Color(red: 0.8784, green: 0.9020, blue: 0.9098)
    }

    static var divDark: Color {
        Color(red: 0.1647, green: 0.2078, blue: 0.2392)
    }

    static var paneBg: Color {
        Color(red: 0.9569, green: 0.9686, blue: 0.9647)
    }

    static var paneBgDark: Color {
        Color(red: 0.0706, green: 0.0941, blue: 0.1059)
    }

    static var accent: Color {
        Color(red: 0.6000, green: 0.8314, blue: 0.8039)
    }
}
