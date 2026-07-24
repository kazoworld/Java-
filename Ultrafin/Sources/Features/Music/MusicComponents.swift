import SwiftUI

/// The "E" explicit badge shown beside explicit tracks and albums, matching
/// the Apple Music / system convention.
struct ExplicitBadge: View {
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: "e.square.fill")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Explicit")
    }
}

/// The player's Apple Music-style backdrop: the record's own color, poured into
/// a soft multi-tone wash that slowly drifts, with the blurred artwork itself
/// underneath for texture. Falls back to a quiet neutral when no color is known
/// yet, so it never flashes flat gray.
struct NowPlayingBackdrop: View {
    let color: ArtworkColor?
    let artURL: URL?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                // A deep base pulled from the art (dark enough for white text).
                (color?.shade(brightness: 0.42, saturation: 0.85) ?? UltrafinColors.background)

                // The blurred artwork — the literal Apple Music move — for real,
                // content-true color and texture.
                if let artURL {
                    RemoteImage(url: artURL, contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .blur(radius: 110)
                        .opacity(0.55)
                        .clipped()
                }

                // Drifting color pools spun from the sampled color so even a
                // near-monochrome cover still carries a hint of color.
                if let color {
                    pool(color.shade(brightness: 0.9, saturation: 1.0),
                         x: drift(t, 0.05, 0.18), y: 0.12 + drift(t, 0.04, 0.06), radius: 520)
                    pool(color.shade(brightness: 0.7, saturation: 0.9, hue: 0.06),
                         x: 0.85 + drift(t, 0.06, 0.1), y: 0.2 + drift(t, 0.05, 0.08), radius: 460)
                    pool(color.shade(brightness: 0.55, saturation: 0.95, hue: -0.05),
                         x: 0.2 + drift(t, 0.05, 0.12), y: 0.85 + drift(t, 0.04, 0.06), radius: 560)
                }

                // Legibility scrim: darken top (status bar) and bottom (controls).
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.35), location: 0.0),
                    .init(color: .black.opacity(0.05), location: 0.4),
                    .init(color: .black.opacity(0.25), location: 0.8),
                    .init(color: .black.opacity(0.55), location: 1.0)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: color)
    }

    private func pool(_ color: Color, x: Double, y: Double, radius: CGFloat) -> some View {
        RadialGradient(colors: [color.opacity(0.5), .clear],
                       center: UnitPoint(x: x, y: y), startRadius: 0, endRadius: radius)
    }

    /// A slow sine drift so the wash breathes without ever looking busy.
    private func drift(_ t: Double, _ speed: Double, _ amount: Double) -> Double {
        sin(t * speed) * amount
    }
}
