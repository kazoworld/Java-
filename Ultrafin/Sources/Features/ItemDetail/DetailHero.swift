import SwiftUI

/// Media-bar-style hero for detail screens.
///
/// Instead of a plain backdrop with a content column below it on the ambient
/// background, this matches the Home media bar: the artwork fills the top, a
/// dark legibility gradient plus a glow tinted by the artwork's *own* color sit
/// over it, and the title, badges and action buttons are overlaid directly on
/// the image. The sampled color is handed back to the overlay so the Play button
/// can carry the title's color, exactly like the media bar.
struct DetailHero<Overlay: View>: View {
    let backdropURL: URL?
    let logoURL: URL?
    let title: String
    /// Color sampled from the cover art by the host view (also tints the page
    /// background), so the hero and background always agree.
    let artColor: ArtworkColor?
    let height: CGFloat
    let edgePadding: CGFloat
    let titleSize: CGFloat
    let logoMaxWidth: CGFloat
    let logoMaxHeight: CGFloat
    @ViewBuilder var overlay: (ArtworkColor?) -> Overlay

    private var tint: Color { artColor?.color ?? Color.white.opacity(0.9) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                RemoteImage(url: backdropURL)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .clipped()
                scrim
            }
            .mask(bottomFade)

            VStack(alignment: .leading, spacing: Spacing.md) {
                TitleLogo(logoURL: logoURL, title: title,
                          fallbackFont: .system(size: titleSize, weight: .heavy, design: .rounded),
                          fallbackColor: .white, maxWidth: logoMaxWidth, maxHeight: logoMaxHeight)
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 4)

                overlay(artColor)
            }
            .padding(.horizontal, edgePadding)
            .padding(.bottom, Spacing.lg)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .animation(.easeInOut(duration: 0.4), value: artColor)
    }

    /// Opaque at the top, transparent at the bottom — dissolves the hero into the
    /// page so there's no hard seam against the content below.
    private var bottomFade: LinearGradient {
        LinearGradient(stops: [
            .init(color: .black, location: 0.0),
            .init(color: .black, location: 0.65),
            .init(color: .clear, location: 1.0)
        ], startPoint: .top, endPoint: .bottom)
    }

    private var scrim: some View {
        ZStack {
            // Dark legibility gradient so the overlaid white text always reads.
            LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.0), location: 0.30),
                .init(color: .black.opacity(0.74), location: 0.85),
                .init(color: .clear, location: 1.0)
            ], startPoint: .top, endPoint: .bottom)

            // Content-color glow — the hero's color comes from the artwork. The
            // fades are baked into the stops so these don't need their own masks
            // (the shared bottom-fade on the group handles the page blend).
            LinearGradient(stops: [
                .init(color: .clear, location: 0.45),
                .init(color: tint.opacity(0.5), location: 0.9),
                .init(color: tint.opacity(0.2), location: 1.0)
            ], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [tint.opacity(0.38), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: height * 0.95)
        }
    }
}

/// A frosted "Liquid Glass" bar used to hold the synopsis (and cast) below the
/// hero, spaced down a little so it reads as its own surface.
struct GlassInfoCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .glassCard()
    }
}
