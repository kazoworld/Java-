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
                .font(Typography.sectionTitle)
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

    @ScaledMetric private var posterWidth: CGFloat = 130

    private var width: CGFloat {
        let base = style == .poster ? posterWidth : posterWidth * 1.6
        return base * settings.appearance.cardDensity.scale
    }
    private var height: CGFloat { style == .poster ? width * 1.5 : width * 9 / 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ZStack(alignment: .bottom) {
                RemoteImage(url: artworkURL)
                    .frame(width: width, height: height)
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
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous)
                    .strokeBorder(isFocused ? UltrafinColors.accent : UltrafinColors.separator,
                                  lineWidth: isFocused ? 3 : 1)
            )

            Text(item.name)
                .font(Typography.cardTitle)
                .foregroundStyle(isFocused ? UltrafinColors.primaryText : UltrafinColors.secondaryText)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(UltrafinColors.tertiaryText)
                    .lineLimit(1)
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .animation(.smooth(duration: 0.2), value: isFocused)
    }

    private var subtitle: String? {
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
