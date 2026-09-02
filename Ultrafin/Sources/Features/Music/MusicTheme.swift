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
        ZStack {
            surface.ignoresSafeArea()
            #if os(tvOS)
            // A television is furniture — it's in the room whether or not
            // anyone's watching — so a record playing gets a scene behind it
            // rather than a flat field. Held right back so it never competes
            // with a cover or a line of text, and only over the dark surface;
            // on white it would read as grime rather than atmosphere.
            if isDarkSurface {
                MusicSceneBackdrop(strength: 0.55)
            }
            #endif
        }
    }

    /// True when the canvas is the black one, whether chosen or inherited.
    private var isDarkSurface: Bool {
        switch settings.musicTheme {
        case .black: true
        case .white: false
        case .system: systemScheme == .dark
        }
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
    func body(content: Content) -> some View {
        // Only the surface here — the window's colour scheme is set at the app
        // root (see UltrafinApp.effectiveColorScheme), because UltrafinColors
        // resolves through UIKit traits and a nested environment override
        // can't beat `preferredColorScheme` set higher up.
        content.background(MusicBackground())
    }
}
