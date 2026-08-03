import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Centralized, **appearance-adaptive** color tokens.
///
/// Every token resolves differently in light vs. dark so the app reads as
/// frosted glass and a breath of fresh air either way: airy, near-white
/// surfaces in light; deep, cool surfaces in dark. Translucent materials
/// (`.ultraThinMaterial`) sit on top of these and adapt automatically.
enum UltrafinColors {
    // Light = airy off-white with a cool tint; Dark = deep near-black.
    static var background: Color { dynamic(light: 0xEFF2F8, dark: 0x0A0B0F) }
    static var surface: Color { dynamic(light: 0xFFFFFF, dark: 0x14161D) }
    static var elevatedSurface: Color { dynamic(light: 0xE6EAF2, dark: 0x1C1F29) }

    static var primaryText: Color { dynamic(light: 0x0F1320, dark: 0xF5F6FA) }
    static var secondaryText: Color { dynamic(light: 0x5A6172, dark: 0x9AA0B0) }
    static var tertiaryText: Color { dynamic(light: 0x9097A8, dark: 0x5C6173) }

    /// Hairline divider/stroke that stays subtle on either background.
    static var separator: Color { dynamicAlpha(light: (0x000000, 0.10), dark: (0xFFFFFF, 0.10)) }

    /// Default accent; the live accent is resolved through `SettingsStore.theme`.
    static var accent: Color { AccentColor.ultrafinRed.color }

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xFA2D48), Color(hex: 0xFF5E6E)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Top/left-to-content scrim behind hero artwork; fades into the adaptive
    /// background so overlaid text stays legible in light and dark.
    static var heroScrim: LinearGradient {
        LinearGradient(
            colors: [.clear, background.opacity(0.55), background],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Dynamic helpers

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? rgb(dark) : rgb(light)
        })
        #else
        return Color(hex: dark)
        #endif
    }

    private static func dynamicAlpha(light: (UInt32, Double), dark: (UInt32, Double)) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            let spec = traits.userInterfaceStyle == .dark ? dark : light
            return rgb(spec.0).withAlphaComponent(spec.1)
        })
        #else
        return Color(hex: dark.0, alpha: dark.1)
        #endif
    }

    #if canImport(UIKit)
    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
    #endif
}

/// User-selectable accent colors exposed in Settings.
/// The app's single accent. Ultrafin follows Apple Music's look now, so the
/// old multi-colour palette is gone — one red, everywhere.
enum AccentColor: String, CaseIterable, Identifiable, Codable {
    case ultrafinRed

    var id: String { rawValue }
    var displayName: String { "Ultrafin Red" }

    /// Apple Music's red.
    var color: Color { Color(hex: 0xFA2D48) }

    /// Anything stored by an older build (aurora, ocean, …) resolves here
    /// rather than failing to decode and resetting the whole theme group.
    init(from decoder: Decoder) throws {
        _ = try? decoder.singleValueContainer().decode(String.self)
        self = .ultrafinRed
    }
}

extension Color {
    /// Convenience initializer for hex literals like `0x1C1F29`.
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
