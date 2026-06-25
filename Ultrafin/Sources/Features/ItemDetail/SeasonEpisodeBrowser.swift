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
                HStack(alignment: .top, spacing: columnGap) {
                    seasonColumn
                    episodeColumn
                }
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
            .padding(.bottom, Spacing.xs)

            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.xs) {
                    ForEach(seasons) { season in
                        seasonRow(season)
                    }
                }
            }
        }
        .frame(width: leftWidth, alignment: .leading)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func seasonRow(_ season: MediaItem) -> some View {
        let active = season.id == selectedSeasonID
        return Button { onSelectSeason(season.id) } label: {
            HStack(spacing: Spacing.sm) {
                // A slim accent bar marks the active season at a glance.
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(active ? settings.theme.accent.color : .clear)
                    .frame(width: 3, height: seasonFont * 0.9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(season.name)
                        .font(.system(size: seasonFont, weight: active ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(active ? UltrafinColors.primaryText : UltrafinColors.secondaryText)
                        .lineLimit(1)
                    if let count = season.childCount, count > 0 {
                        Text("\(count) episode\(count == 1 ? "" : "s")")
                            .font(.system(size: seasonFont * 0.62, weight: .medium))
                            .foregroundStyle(UltrafinColors.tertiaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                if active {
                    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                    shape.fill(.ultraThinMaterial)
                    shape.fill(LiquidGlass.sheen)
                    shape.strokeBorder(LiquidGlass.rim(0.5), lineWidth: 1)
                }
            }
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.03, lift: false))
        .focused($focusedSeason, equals: season.id)
        // Netflix feel: focusing a season (tvOS) swaps the episode list live.
        .onChange(of: focusedSeason) { _, id in
            if let id, id == season.id, id != selectedSeasonID { onSelectSeason(id) }
        }
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
                .padding(.vertical, 2)
                // Cross-fade the list when switching seasons.
                .animation(.smooth(duration: 0.35), value: episodes)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onChange(of: selectedSeasonID) { _, _ in
                // Jump back to the top of the list when the season changes.
                if let first = episodes.first?.id {
                    withAnimation(.smooth(duration: 0.3)) { proxy.scrollTo(first, anchor: .top) }
                }
            }
            .task(id: currentEpisodeID) {
                guard let currentEpisodeID,
                      episodes.contains(where: { $0.id == currentEpisodeID }) else { return }
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation { proxy.scrollTo(currentEpisodeID, anchor: .center) }
            }
        }
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
        26
        #else
        17
        #endif
    }
}
