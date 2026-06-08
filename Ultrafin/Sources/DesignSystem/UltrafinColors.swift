import SwiftUI

/// Centralized color tokens. Everything reads from here so the accent and
/// surface palette can be re-skinned from Settings without touching screens.
enum UltrafinColors {
    static var background: Color { Color(hex: 0x0A0B0F) }
    static var surface: Color { Color(hex: 0x14161D) }
    static var elevatedSurface: Color { Color(hex: 0x1C1F29) }

    static var primaryText: Color { Color(hex: 0xF5F6FA) }
    static var secondaryText: Color { Color(hex: 0x9AA0B0) }
    static var tertiaryText: Color { Color(hex: 0x5C6173) }

    static var separator: Color { Color.white.opacity(0.08) }

    /// Default accent; the live accent is resolved through `SettingsStore.theme`.
    static var accent: Color { AccentColor.aurora.color }

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x6D8BFF), Color(hex: 0xB56DFF)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Subtle top-to-bottom scrim used behind hero artwork for legible overlays.
    static var heroScrim: LinearGradient {
        LinearGradient(
            colors: [.clear, background.opacity(0.6), background],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// User-selectable accent colors exposed in Settings.
enum AccentColor: String, CaseIterable, Identifiable, Codable {
    case aurora, ember, mint, rose, gold

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aurora: "Aurora"
        case .ember: "Ember"
        case .mint: "Mint"
        case .rose: "Rose"
        case .gold: "Gold"
        }
    }

    var color: Color {
        switch self {
        case .aurora: Color(hex: 0x6D8BFF)
        case .ember: Color(hex: 0xFF6D5A)
        case .mint: Color(hex: 0x3DD9A0)
        case .rose: Color(hex: 0xFF6DAE)
        case .gold: Color(hex: 0xFFC857)
        }
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
