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

/// An album page's backdrop: the cover's color, *muted* into a tasteful wash
/// that dims to near-black down the page. Deliberately desaturated and darkened
/// — the raw sampled color is boosted for vividness, which reads garish behind a
/// full page of text; Apple Music's album pages sit in a quiet, dusky version of
/// the cover instead.
struct AlbumBackdrop: View {
    let color: ArtworkColor?

    var body: some View {
        ZStack {
            UltrafinColors.background

            if let color {
                // The record's colour, held rich through the top two thirds
                // before it settles into black behind the track list. The old
                // ramp gave the colour up by a third of the way down, which read
                // as a grey page with a tint rather than a page made of the
                // artwork.
                LinearGradient(stops: [
                    .init(color: color.shade(brightness: 0.62, saturation: 0.52), location: 0.0),
                    .init(color: color.shade(brightness: 0.52, saturation: 0.5), location: 0.34),
                    .init(color: color.shade(brightness: 0.3, saturation: 0.42), location: 0.62),
                    .init(color: .black.opacity(0.97), location: 1.0)
                ], startPoint: .top, endPoint: .bottom)

                // A soft pool behind the artwork so the cover sits in its own light.
                RadialGradient(colors: [color.shade(brightness: 0.74, saturation: 0.55).opacity(0.5), .clear],
                               center: UnitPoint(x: 0.5, y: 0.18), startRadius: 0, endRadius: 460)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: color)
    }
}

/// The player's Apple Music-style backdrop: the record's own color, poured into
/// a soft multi-tone wash that slowly drifts, with the blurred artwork itself
/// underneath for texture. Falls back to a quiet neutral when no color is known
/// yet, so it never flashes flat gray.
struct NowPlayingBackdrop: View {
    let color: ArtworkColor?
    /// Kept for call-site compatibility; the backdrop no longer renders the
    /// artwork. Apple's player is a flat field of the record's colour, not a
    /// blurred copy of the cover — the blur read as murky and drew the eye away
    /// from the art itself.
    var artURL: URL? = nil

    var body: some View {
        ZStack {
            base
            // The faintest vertical shading, so it isn't a dead flat fill —
            // brighter under the cover, settling darker behind the controls.
            LinearGradient(stops: [
                .init(color: .white.opacity(0.05), location: 0.0),
                .init(color: .clear, location: 0.45),
                .init(color: .black.opacity(0.10), location: 1.0)
            ], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.7), value: color)
    }

    /// A muted, mid-dark version of the cover's colour: saturated enough to be
    /// clearly "this record", dark enough for white text to sit on it.
    private var base: Color {
        color?.shade(brightness: 0.46, saturation: 0.55) ?? UltrafinColors.background
    }
}
