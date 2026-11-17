#if os(iOS)
import SwiftUI

/// Riff's neutral palette, shared by the app and extensions.
public extension Color {
    static let dictusAccent = Color(light: Color(hex: 0x161616), dark: Color(hex: 0xF5F5F5))
    static let dictusOnAccent = Color(light: .white, dark: Color(hex: 0x121212))
    static let dictusAccentHighlight = Color(light: Color(hex: 0x4D4D4D), dark: Color(hex: 0xC4C4C4))
    static let dictusBackground = Color(light: Color(hex: 0xF4F4F4), dark: Color(hex: 0x0C0C0C))
    static let dictusSurface = Color(light: .white, dark: Color(hex: 0x191919))
    static let dictusBorder = Color(light: Color(hex: 0xCECECE), dark: Color(hex: 0x414141))
    static let dictusPillIconSecondary = Color(light: Color(hex: 0x4D4D4D), dark: Color(hex: 0xB5B5B5))

    // The accompanying icons and labels distinguish each status.
    static let dictusRecording = dictusAccent
    static let dictusSuccess = dictusAccentHighlight
    static let dictusGradientStart = dictusAccent
    static let dictusGradientEnd = dictusAccentHighlight

    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
#endif
