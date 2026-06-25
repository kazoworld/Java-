import SwiftUI

/// Netflix-style season browser: a vertical list of **seasons on the left** and
/// the selected season's **episodes on the right**. Moving focus up/down the
/// season list swaps the episode column instantly (seasons are cached by the
/// caller), and focus crosses cleanly between the two columns on tvOS.
///
/// On a compact width (iPhone portrait) there's no room for two columns, so it
/// collapses to a season dropdown above the episode list — exactly how Netflix
/// adapts on phone.
struct SeasonEpisodeBrowser: View {
    let seriesName: String
    let seasons: [MediaItem]
    let selectedSeasonID: String?
    let episodes: [MediaItem]
    /// The episode the user came from (gets a "Now Viewing" marker), if any.
    var currentEpisodeID: String? = nil
    let episodeImageURL: (MediaItem) -> URL?
    let onSelectSeason: (String) -> Void
    let onPlay: (MediaItem) -> Void

    @Environment(SettingsStore.self) private var settings
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSize
    #endif
    @FocusState private var focusedSeason: String?

    /// Two columns when there's room (tvOS, iPad, landscape); a dropdown + list
    /// when compact (iPhone portrait).
    private var useColumns: Bool {
        #if os(iOS)
        return hSize != .compact
        #else
        return true
        #endif
    }

    var body: some View {
        Group {
            if useColumns {
                HStack(alignment: .center, spacing: columnGap) {
                    seasonColumn
                    episodeColumn
                }
                // Cap the block to its content width, then center it on screen
                // with balanced margins (instead of hugging the left), like
                // Netflix. Capping first is what lets the centering take effect.
                .frame(maxWidth: leftWidth + columnGap + episodeMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    compactSeasonPicker
                    episodeColumn
                }
            }
        }
        .task {
            // Land focus on the current season so the remote starts in the list.
            try? await Task.sleep(for: .milliseconds(60))
            if focusedSeason == nil { focusedSeason = selectedSeasonID }
        }
    }

    // MARK: - Season column (left)

    private var seasonColumn: some View {
        // The title + season list are vertically centered in the column so the
        // left side reads as a balanced, centered panel (no big empty space
        // beneath a top-pinned title). Scrolls only if a show has many seasons.
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(seriesName)
                            .font(.system(size: headerSize, weight: .bold, design: .rounded))
                            .foregroundStyle(UltrafinColors.primaryText)
                            .lineLimit(2)
                        Text("\(seasons.count) Season\(seasons.count == 1 ? "" : "s")")
                            .font(.system(size: subHeaderSize, weight: .semibold))
                            .foregroundStyle(UltrafinColors.secondaryText)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.bottom, Spacing.xs)

                    VStack(spacing: Spacing.xs) {
                        ForEach(seasons) { season in
                            seasonRow(season)
                        }
                    }
                }
                // Inset so the focus pill never touches the column edge.
                .padding(.horizontal, Spacing.xs)
                .frame(minHeight: geo.size.height, alignment: .center)
            }
        }
        .frame(width: leftWidth)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func seasonRow(_ season: MediaItem) -> some View {
        Button { Haptics.play(.selection); onSelectSeason(season.id) } label: {
            SeasonRowLabel(season: season,
                           active: season.id == selectedSeasonID,
                           seasonFont: seasonFont,
                           accent: settings.theme.accent.color)
        }
        // No focus scale — a scaled row would spill its highlight outside the
        // season column. The focused look is a solid pill drawn inside the row.
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.0, lift: false))
        .focused($focusedSeason, equals: season.id)
    }

    // MARK: - Compact season picker (iPhone portrait)

    @ViewBuilder
    private var compactSeasonPicker: some View {
        #if os(iOS)
        Menu {
            ForEach(seasons) { season in
                Button { onSelectSeason(season.id) } label: {
                    if season.id == selectedSeasonID {
                        Label(season.name, systemImage: "checkmark")
                    } else {
                        Text(season.name)
                    }
                }
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(selectedSeason?.name ?? "Seasons")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(UltrafinColors.primaryText)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(LiquidGlass.sheen)
                Capsule().strokeBorder(LiquidGlass.rim(0.5), lineWidth: 1)
            }
        }
        #endif
    }

    private var selectedSeason: MediaItem? { seasons.first { $0.id == selectedSeasonID } }

    // MARK: - Episode column (right)

    /// Show exactly three episodes at a time; the rest scroll into view one at a
    /// time as focus moves. (Rows are a fixed height, so this is a clean window.)
    private var episodeViewportHeight: CGFloat {
        EpisodeRow.rowHeight * 3 + Spacing.md * 2 + Spacing.sm * 2
    }

    private var episodeColumn: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: Spacing.md) {
                    ForEach(episodes) { episode in
                        Button { onPlay(episode) } label: {
                            EpisodeRow(episode: episode, imageURL: episodeImageURL(episode))
                                .overlay(alignment: .topTrailing) {
                                    if episode.id == currentEpisodeID { nowViewingBadge }
                                }
                        }
                        .buttonStyle(UltrafinButtonStyle(focusScale: 1.02, lift: true))
                        .id(episode.id)
                    }
                }
                // Inset so a focused row's lift never clips against the edge.
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.sm)
            }
            // Always open at the top (episode 1); the focus engine scrolls the
            // rest into view one at a time as you move down.
            .onChange(of: selectedSeasonID) { _, _ in
                if let first = episodes.first?.id {
                    withAnimation(.smooth(duration: 0.3)) { proxy.scrollTo(first, anchor: .top) }
                }
            }
        }
        // A fixed three-row viewport (two-column layouts only), centered in the
        // column, with a capped width so the block centers on screen. On compact
        // iPhone the list fills naturally instead.
        .frame(maxWidth: episodeMaxWidth)
        .frame(height: useColumns ? episodeViewportHeight : nil)
        .frame(maxHeight: useColumns ? .infinity : nil)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private var nowViewingBadge: some View {
        Text("Now Viewing")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.sm).padding(.vertical, 3)
            .background(settings.theme.accent.color, in: Capsule())
            .padding(Spacing.sm)
    }

    // MARK: - Metrics

    private var leftWidth: CGFloat {
        #if os(tvOS)
        360
        #else
        240
        #endif
    }
    private var columnGap: CGFloat {
        #if os(tvOS)
        Spacing.xxl
        #else
        Spacing.xl
        #endif
    }
    /// Cap on the episode list width so rows stay a comfortable reading measure
    /// and the block can center instead of stretching into empty space.
    private var episodeMaxWidth: CGFloat {
        #if os(tvOS)
        920
        #else
        720
        #endif
    }
    private var headerSize: CGFloat {
        #if os(tvOS)
        32
        #else
        22
        #endif
    }
    private var subHeaderSize: CGFloat {
        #if os(tvOS)
        20
        #else
        14
        #endif
    }
    private var seasonFont: CGFloat {
        #if os(tvOS)
        28
        #else
        18
        #endif
    }
}

/// A single season entry. Reads the focus engine so the focused row becomes a
/// bright, high-contrast pill (Netflix-style) entirely inside the column — no
/// scaling, so the highlight never spills past the season list.
private struct SeasonRowLabel: View {
    let season: MediaItem
    let active: Bool
    let seasonFont: CGFloat
    let accent: Color

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // A slim accent bar marks the current season (hidden while focused,
            // where the bright pill already signals position).
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(active && !isFocused ? accent : .clear)
                .frame(width: 4, height: seasonFont)
            VStack(alignment: .leading, spacing: 1) {
                Text(season.name)
                    .font(.system(size: seasonFont, weight: .semibold, design: .rounded))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                if let count = season.childCount, count > 0 {
                    Text("\(count) episode\(count == 1 ? "" : "s")")
                        .font(.system(size: seasonFont * 0.6, weight: .medium))
                        .foregroundStyle(subColor)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fillColor)
        )
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var fillColor: Color {
        if isFocused { return .white }            // bright focus pill
        if active { return .white.opacity(0.10) } // current season, subtle
        return .clear
    }
    private var textColor: Color { isFocused ? .black : .white }
    private var subColor: Color { isFocused ? .black.opacity(0.6) : .white.opacity(0.62) }
}
