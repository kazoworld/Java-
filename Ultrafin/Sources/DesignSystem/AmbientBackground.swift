import SwiftUI

/// The app's signature backdrop: the adaptive base color washed with soft,
/// colorful gradient "blobs" derived from the live accent. Frosted glass
/// (`.ultraThinMaterial`) surfaces sit on top and pick up this color, giving
/// the premium "liquid glass" feel in both light and dark.
///
/// Built from `RadialGradient`s (not a `blur` pass) so it stays GPU-cheap and
/// never costs frame rate, even on Apple TV.
struct AmbientBackground: View {
    @Environment(SettingsStore.self) private var settings

    private var accent: Color { settings.theme.accent.color }

    /// Show the colorful wash only when enabled and not in OLED mode (OLED wants
    /// true black for deeper contrast and lower power).
    private var showsWash: Bool {
        settings.appearance.ambientBackground && !settings.appearance.oledMode
    }

    var body: some View {
        ZStack {
            (settings.appearance.oledMode ? Color.black : UltrafinColors.background)

            if showsWash {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    ZStack {
                        blob(accent, center: UnitPoint(x: 0.05, y: 0.0), radius: w * 0.75)
                        blob(accent.complement, center: UnitPoint(x: 1.0, y: 0.15), radius: w * 0.6)
                        blob(accent.analogous, center: UnitPoint(x: 0.85, y: 1.0), radius: w * 0.8)
                        blob(accent, center: UnitPoint(x: 0.1, y: 1.05), radius: h * 0.7)
                    }
                }
                .opacity(0.5)
            }
        }
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(
            colors: [color.opacity(0.55), color.opacity(0.0)],
            center: center,
            startRadius: 0,
            endRadius: radius
        )
    }
}

private extension Color {
    /// A hue-shifted partner color for the ambient wash. Approximations are
    /// fine here — these only tint a soft background.
    var complement: Color { shiftedHue(by: 0.5) }
    var analogous: Color { shiftedHue(by: 0.08) }

    func shiftedHue(by delta: Double) -> Color {
        #if canImport(UIKit)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            return Color(hue: (Double(h) + delta).truncatingRemainder(dividingBy: 1.0),
                         saturation: Double(s), brightness: Double(b))
        }
        #endif
        return self
    }
}
