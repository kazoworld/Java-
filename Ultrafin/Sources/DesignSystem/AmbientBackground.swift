import SwiftUI

/// The app's signature backdrop: the adaptive base color washed with soft,
/// colorful gradient "blobs" derived from the live accent. Frosted glass
/// (`.ultraThinMaterial`) surfaces sit on top and pick up this color, giving
/// the premium "liquid glass" feel in both light and dark.
///
/// Built from `RadialGradient`s (not a `blur` pass) so it stays GPU-cheap and
/// never costs frame rate, even on Apple TV.
struct AmbientBackground: View {
    /// Optional content color (e.g. the featured title's artwork) the wash leans
    /// toward, so the whole screen subtly "lights up" in the mood of what you're
    /// browsing and shifts as the media bar rotates. Falls back to the accent.
    var tint: Color? = nil

    @Environment(SettingsStore.self) private var settings

    private var accent: Color { settings.theme.accent.color }
    /// The dominant wash color — the content tint when present, else the accent.
    private var primary: Color { tint ?? accent }

    /// Show the colorful wash only when enabled and not in OLED mode (OLED wants
    /// true black for deeper contrast and lower power).
    private var showsWash: Bool {
        settings.appearance.ambientBackground && !settings.appearance.oledMode
    }

    var body: some View {
        ZStack {
            (settings.appearance.oledMode ? Color.black : UltrafinColors.background)

            if showsWash {
                // Fixed radii (no GeometryReader) so the wash is a single static
                // layer the GPU can cache — cheaper when tabs swap in and out.
                ZStack {
                    blob(primary, center: UnitPoint(x: 0.0, y: 0.0), radius: 900)
                    blob(primary.complement, center: UnitPoint(x: 1.0, y: 0.1), radius: 760)
                    blob(primary.analogous, center: UnitPoint(x: 0.9, y: 1.0), radius: 950)
                }
                .opacity(0.5)
                // A gentle crossfade as the featured color changes — the room
                // breathes with the content. (Just a gradient recolor, no mask,
                // so it stays GPU-cheap.)
                .animation(.easeInOut(duration: 0.9), value: tint)
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

/// A full-screen backdrop tinted entirely by a title's cover art, used on movie
/// and series detail pages instead of the accent-derived ``AmbientBackground``.
///
/// The wash is concentrated up top (under the hero) and fades to a whisper lower
/// down so synopsis/episode text stays legible, with a touch of frost to keep it
/// soft. It blends with the system background so it reads in both light and dark.
struct ArtworkBackground: View {
    let color: ArtworkColor?

    private var tint: Color { color?.color ?? UltrafinColors.accent }

    var body: some View {
        ZStack {
            UltrafinColors.background

            LinearGradient(stops: [
                .init(color: tint.opacity(0.55), location: 0.0),
                .init(color: tint.opacity(0.22), location: 0.35),
                .init(color: tint.opacity(0.08), location: 0.7),
                .init(color: tint.opacity(0.03), location: 1.0)
            ], startPoint: .top, endPoint: .bottom)

            RadialGradient(colors: [tint.opacity(0.28), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 760)

            // A whisper of frost to soften the wash.
            Rectangle().fill(.ultraThinMaterial).opacity(0.12)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: color)
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
