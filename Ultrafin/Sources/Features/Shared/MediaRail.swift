import SwiftUI

/// A horizontally-scrolling row of media cards. Two layouts: tall posters and
/// wide landscape (used for resume items so progress is visible).
struct MediaRail: View {
    enum Style { case poster, landscape }

    let title: String
    let items: [MediaItem]
    var style: Style = .poster

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(sectionTitleFont)
                .foregroundStyle(UltrafinColors.primaryText)
                .padding(.horizontal, edgePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: railSpacing) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            MediaCard(item: item, style: style)
                        }
                        .mediaCardButtonStyle()
                    }
                }
                .padding(.horizontal, edgePadding)
                // Breathing room so focus-scaled cards never clip on tvOS.
                .padding(.vertical, focusInset)
            }
            .scrollClipDisabled()
        }
    }

    private var sectionTitleFont: Font {
        #if os(tvOS)
        .system(size: 30, weight: .bold, design: .rounded)
        #else
        Typography.sectionTitle
        #endif
    }

    /// Leading/trailing inset. Larger on tvOS to stay inside the title-safe
    /// area now that Home is laid out full-bleed for the hero.
    private var edgePadding: CGFloat {
        #if os(tvOS)
        56
        #else
        Spacing.lg
        #endif
    }

    // tvOS focus scaling needs extra spacing/padding so neighbouring cards and
    // row edges don't clip the lifted card.
    private var railSpacing: CGFloat {
        #if os(tvOS)
        Spacing.xl
        #else
        Spacing.md
        #endif
    }

    private var focusInset: CGFloat {
        #if os(tvOS)
        Spacing.xl
        #else
        0
        #endif
    }
}

/// A single tappable media card with artwork, title, and resume progress.
struct MediaCard: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    // On tvOS this reflects the focus of the enclosing card button, so the card
    // can light up under the focus engine. Always false on iOS.
    @Environment(\.isFocused) private var isFocused

    let item: MediaItem
    var style: MediaRail.Style = .poster
    /// When true the card fills its container's width (for grids); otherwise it
    /// uses a fixed width (for horizontal rails).
    var fillWidth: Bool = false

    // TVs are viewed from across the room, so cards are far larger there than
    // on a phone. Density then scales these bases up/down.
    private var basePosterWidth: CGFloat {
        #if os(tvOS)
        240
        #else
        130
        #endif
    }

    private var width: CGFloat {
        let base = style == .poster ? basePosterWidth : basePosterWidth * 1.62
        return base * settings.appearance.cardDensity.scale
    }
    private var height: CGFloat { style == .poster ? width * 1.5 : width * 9 / 16 }
    /// Width / height aspect of the artwork.
    private var aspect: CGFloat { style == .poster ? 2.0 / 3.0 : 16.0 / 9.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ZStack(alignment: .bottom) {
                artwork
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous))

                if let progress = item.playbackProgress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.4))
                            Capsule()
                                .fill(UltrafinColors.accent)
                                .frame(width: geo.size.width * progress)
                        }
                        .frame(height: 4)
                    }
                    .frame(height: 4)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.bottom, Spacing.sm)
                }
            }
            // A glassy specular sheen sweeps across the art when focused, so a
            // lit poster catches the light like a pane of glass.
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous)
                    .fill(LiquidGlass.sheen)
                    .opacity(isFocused ? 1 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous)
                    .strokeBorder(isFocused ? UltrafinColors.accent : UltrafinColors.separator,
                                  lineWidth: isFocused ? 3 : 1)
            )
            // A soft accent glow when focused for a premium, lit feel.
            .shadow(color: isFocused ? settings.theme.accent.color.opacity(0.55) : .clear,
                    radius: isFocused ? 22 : 0, y: isFocused ? 6 : 0)

            Text(item.name)
                .font(titleFont)
                .foregroundStyle(isFocused ? UltrafinColors.primaryText : UltrafinColors.secondaryText)
                .lineLimit(1)
            // Always reserve the subtitle line so every card is the same total
            // height and rows/rails line up cleanly.
            Text(subtitle ?? " ")
                .font(subtitleFont)
                .foregroundStyle(UltrafinColors.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: fillWidth ? .infinity : width)
        .frame(width: fillWidth ? nil : width)
        .contentShape(Rectangle())
        .animation(.smooth(duration: 0.2), value: isFocused)
    }

    /// A uniformly-sized, center-cropped artwork box: a fixed-aspect container
    /// the image *fills* (and is clipped to), so every card is identical no
    /// matter what dimensions the server's image happens to be.
    @ViewBuilder
    private var artwork: some View {
        if fillWidth {
            Color.clear
                .aspectRatio(aspect, contentMode: .fit)
                .overlay(RemoteImage(url: artworkURL, contentMode: .fill))
                .clipped()
        } else {
            Color.clear
                .frame(width: width, height: height)
                .overlay(RemoteImage(url: artworkURL, contentMode: .fill))
                .clipped()
        }
    }

    private var titleFont: Font {
        #if os(tvOS)
        .system(size: 22, weight: .semibold, design: .rounded)
        #else
        Typography.cardTitle
        #endif
    }
    private var subtitleFont: Font {
        #if os(tvOS)
        .system(size: 17, weight: .medium)
        #else
        Typography.caption
        #endif
    }

    private var subtitle: String? {
        // Episodes show series + season/episode so Continue Watching reads like
        // "The Office · S1 · E3" instead of just the episode title.
        if item.type == .episode {
            let s = item.parentIndexNumber.map { "S\($0)" }
            let e = item.indexNumber.map { "E\($0)" }
            let se = [s, e].compactMap { $0 }.joined(separator: " · ")
            let parts = [item.seriesName, se.isEmpty ? nil : se].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        if let series = item.seriesName { return series }
        if let year = item.productionYear { return String(year) }
        return nil
    }

    private var artworkURL: URL? {
        // Wide cards prefer a backdrop, but libraries/episodes often only have a
        // Primary image — fall back to it so cards aren't blank placeholders.
        if style == .landscape, let tag = item.backdropImageTags?.first {
            return appState.client?.imageURL(itemID: item.id, kind: .backdrop, tag: tag, maxWidth: Int(width * 2))
        }
        let tag = item.imageTags?["Primary"]
        return appState.client?.imageURL(itemID: item.id, kind: .primary, tag: tag, maxWidth: Int(width * 2))
    }
}
