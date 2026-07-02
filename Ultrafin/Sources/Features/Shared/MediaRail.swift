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

    // Local overrides so the long-press quick actions reflect instantly on the
    // card (the server round-trip and the next rail refresh catch up later).
    @State private var playedOverride: Bool?
    @State private var favoriteOverride: Bool?

    private var isWatched: Bool { playedOverride ?? item.isWatched }
    private var isFavorite: Bool { favoriteOverride ?? (item.userData?.isFavorite ?? false) }

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
                    VStack(alignment: .leading, spacing: 3) {
                        // "24m left" right on the art — answers the question a
                        // progress bar only hints at.
                        if let remaining = item.remainingText {
                            Text(remaining)
                                .font(.system(size: remainingFontSize, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.black.opacity(0.4))
                                Capsule()
                                    .fill(settings.theme.accent.color)
                                    .frame(width: geo.size.width * progress)
                            }
                            .frame(height: 4)
                        }
                        .frame(height: 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.bottom, Spacing.sm)
                }
            }
            // A quiet checkmark chip for anything you've finished, so a shelf
            // scans at a glance.
            .overlay(alignment: .topTrailing) {
                if isWatched && item.playbackProgress == nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: watchedIconSize, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(watchedIconSize * 0.45)
                        .background(settings.theme.accent.color.opacity(0.92), in: Circle())
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                        .padding(Spacing.sm)
                }
            }
            // A glassy specular sheen sweeps across the art when focused, so a
            // lit poster catches the light like a pane of glass. Built only for
            // the focused card — an always-present layer at opacity 0 still costs
            // the compositor across a hundred cards.
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous)
                        .fill(LiquidGlass.sheen)
                        .transition(.opacity)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous)
                    .strokeBorder(isFocused ? settings.theme.accent.color : UltrafinColors.separator,
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
        #if os(iOS)
        // Long-press quick actions — the fastest way to tidy a shelf without
        // opening the detail page. iPhone only: on tvOS a context menu wires
        // long-press interaction machinery into every cell of every rail, which
        // measurably drags Home below 60fps (the detail page carries the same
        // actions there).
        .contextMenu {
            if item.type == .movie || item.type == .episode || item.type == .series {
                Button { toggleWatched() } label: {
                    Label(isWatched ? "Mark as Unwatched" : "Mark as Watched",
                          systemImage: isWatched ? "eye.slash" : "eye")
                }
                Button { toggleFavorite() } label: {
                    Label(isFavorite ? "Remove from My List" : "Add to My List",
                          systemImage: isFavorite ? "minus.circle" : "plus.circle")
                }
            }
        }
        #endif
    }

    private func toggleWatched() {
        let newValue = !isWatched
        playedOverride = newValue
        Haptics.play(.success)
        guard case .authenticated(let session) = appState.phase,
              let client = appState.client else { return }
        Task { await client.setPlayed(itemID: item.id, userID: session.userID, isPlayed: newValue) }
    }

    private func toggleFavorite() {
        let newValue = !isFavorite
        favoriteOverride = newValue
        Haptics.play(.success)
        guard case .authenticated(let session) = appState.phase,
              let client = appState.client else { return }
        Task { await client.setFavorite(itemID: item.id, userID: session.userID, isFavorite: newValue) }
    }

    /// A uniformly-sized, center-cropped artwork box: a fixed-aspect container
    /// the image *fills* (and is clipped to), so every card is identical no
    /// matter what dimensions the server's image happens to be. When focused on
    /// tvOS the image zooms slightly *within* its clip — moving faster than the
    /// card frame for a subtle sense of depth (parallax).
    @ViewBuilder
    private var artwork: some View {
        if fillWidth {
            Color.clear
                .aspectRatio(aspect, contentMode: .fit)
                .overlay(RemoteImage(url: artworkURL, contentMode: .fill).scaleEffect(isFocused ? 1.07 : 1))
                .clipped()
        } else {
            Color.clear
                .frame(width: width, height: height)
                .overlay(RemoteImage(url: artworkURL, contentMode: .fill).scaleEffect(isFocused ? 1.07 : 1))
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
    private var remainingFontSize: CGFloat {
        #if os(tvOS)
        16
        #else
        11
        #endif
    }
    private var watchedIconSize: CGFloat {
        #if os(tvOS)
        14
        #else
        10
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
