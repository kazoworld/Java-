import SwiftUI

/// Music mode's canvas. The listening experience sits on a flat, true surface —
/// OLED black or paper white — rather than the ambient gradient the media side
/// uses, so artwork is the only colour on screen.
enum MusicTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Follow the device's light/dark appearance.
    case system
    /// True black (#000000) — the default, and what OLED panels want.
    case black
    /// Pure white.
    case white

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Automatic"
        case .black: "Black"
        case .white: "White"
        }
    }

    var detail: String {
        switch self {
        case .system: "Match the device's light or dark mode"
        case .black: "True black — best on OLED"
        case .white: "Pure white"
        }
    }

    /// The scheme to force, or nil to inherit the device's.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .black: .dark
        case .white: .light
        }
    }
}

/// The flat music canvas: pure black or pure white, with nothing else on it.
/// Also pins the colour scheme so every adaptive colour inside resolves against
/// the chosen surface (white text on black, dark text on white).
struct MusicBackground: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        surface.ignoresSafeArea()
    }

    private var surface: Color {
        switch settings.musicTheme {
        case .black: .black
        case .white: .white
        // Automatic: true black in dark mode, pure white in light.
        case .system: systemScheme == .dark ? .black : .white
        }
    }
}

extension View {
    /// Put a music screen on the flat OLED-black / paper-white canvas and make
    /// its adaptive colours resolve against it.
    func musicCanvas() -> some View {
        modifier(MusicCanvas())
    }
}

private struct MusicCanvas: ViewModifier {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        content
            .background(MusicBackground())
            .environment(\.colorScheme, resolvedScheme)
    }

    /// Automatic inherits the device; the fixed themes pin their own scheme so
    /// text never lands white-on-white.
    private var resolvedScheme: ColorScheme {
        settings.musicTheme.colorScheme ?? systemScheme
    }
}
