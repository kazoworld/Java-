import SwiftUI

/// Season + episode browser, tuned for the Apple TV focus engine.
///
/// - **Multiple seasons:** a season list on the left, the selected season's
///   episodes on the right — the Netflix-style two-column look, top-aligned so
///   vertical focus motion is predictable.
/// - **Single season** (no choice to make): the season list is dropped entirely
///   and the episodes get a clean, centered, wider column.
/// - **Compact iPhone:** a season dropdown above the list.
///
/// Performance: this view is meant to be hosted over a *cheap opaque* background
/// (see `SeriesDetailView`), never over the live masked backdrop — that was the
/// source of the "laggy" feel. It uses only solid fills + gradients, no per-row
/// material/blur, so it holds 60fps on Apple TV.
struct SeasonEpisodeBrowser: View {
    let seriesName: String
    let seasons: [MediaItem]
    let selectedSeasonID: String?
    let episodes: [MediaItem]
    /// The episode the user is currently on (gets a "Now Viewing" marker), if any.
    var currentEpisodeID: String? = nil
    /// Hosts that render their own series title (e.g. the morphing logo on the
    /// series page) pass false to suppress the browser's internal one.
    var showsTitle: Bool = true
    let episodeImageURL: (MediaItem) -> URL?
    let onSelectSeason: (String) -> Void
    let onPlay: (MediaItem) -> Void

    @Environment(SettingsStore.self) private var settings
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSize
    #endif
    @FocusState private var focusedSeason: String?
    @FocusState private var focusedEpisode: String?
    /// The one-time landing of focus on the current episode has happened.
    @State private var didAutoFocus = false

    private var accent: Color { settings.theme.accent.color }
    private var multiSeason: Bool { seasons.count > 1 }

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
            if !useColumns {
                // iPhone portrait: dropdown (multi-season only) above the list.
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if multiSeason { compactSeasonPicker }
                    episodeColumn(maxWidth: 720)
                }
            } else if multiSeason {
                twoColumn
            } else {
                singleSeason
            }
        }
    }

    /// The current episode when it's in this season's list, else the first.
    private var initialEpisodeID: String? {
        if let currentEpisodeID, episodes.contains(where: { $0.id == currentEpisodeID }) {
            return currentEpisodeID
        }
        return episodes.first?.id
    }

    // MARK: - Layouts

    private var twoColumn: some View {
        HStack(alignment: .top, spacing: columnGap) {
            seasonColumn
            episodeColumn(maxWidth: episodeMaxWidth)
        }
        // Cap to content width, then center on screen with balanced margins.
        .frame(maxWidth: leftWidth + columnGap + episodeMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var singleSeason: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if showsTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(seriesName)
                        .font(.system(size: headerSize, weight: .bold, design: .rounded))
                        .foregroundStyle(UltrafinColors.primaryText)
                        .lineLimit(1)
                    if let count = seasons.first?.childCount ?? (episodes.isEmpty ? nil : episodes.count), count > 0 {
                        Text("\(count) Episode\(count == 1 ? "" : "s")")
                            .font(.system(size: subHeaderSize, weight: .semibold))
                            .foregroundStyle(UltrafinColors.secondaryText)
                    }
                }
                .padding(.leading, Spacing.sm)
            }
            episodeColumn(maxWidth: singleColumnMaxWidth)
        }
        .frame(maxWidth: singleColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Season column (left, multi-season only)

    private var seasonColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Seasons")
                .font(.system(size: subHeaderSize, weight: .semibold))
                .foregroundStyle(UltrafinColors.tertiaryText)
                .tracking(0.5)
                .padding(.leading, Spacing.md)
                .padding(.bottom, Spacing.xs)

            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.sm) {
                    ForEach(seasons) { season in
                        seasonRow(season)
                    }
                }
                .padding(.horizontal, Spacing.sm)
            }
            // Match the episode window height so the two columns read as a pair.
            .frame(maxHeight: episodeViewportHeight)
        }
        .frame(width: leftWidth, alignment: .leading)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func seasonRow(_ season: MediaItem) -> some View {
        Button { Haptics.play(.selection); onSelectSeason(season.id) } label: {
            SeasonRowLabel(season: season,
                           active: season.id == selectedSeasonID,
                           seasonFont: seasonFont,
                           accent: accent)
        }
        // No focus scale (a scaled row spills its highlight past the column); the
        // button style owns the single focus animation.
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

    /// Show three episodes comfortably; the rest scroll into view as focus
    /// moves. (Rows are a fixed height, so this is a clean window.)
    private var episodeViewportHeight: CGFloat {
        EpisodeRow.rowHeight * 3 + Spacing.lg * 2 + Spacing.md * 2
    }

    private func episodeColumn(maxWidth: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: Spacing.lg) {
                    ForEach(episodes) { episode in
                        Button { onPlay(episode) } label: {
                            EpisodeRow(episode: episode, imageURL: episodeImageURL(episode))
                                .overlay(alignment: .topTrailing) {
                                    if episode.id == currentEpisodeID { nowViewingBadge }
                                }
                        }
                        .buttonStyle(UltrafinButtonStyle(focusScale: 1.02, lift: true))
                        .id(episode.id)
                        .focused($focusedEpisode, equals: episode.id)
                        // Depth of field at the window edges: rows entering or
                        // leaving the viewport recede into a soft blur and fade
                        // instead of being cut by a hard clip line.
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.25)
                                .blur(radius: phase.isIdentity ? 0 : 9)
                                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                        }
                    }
                }
                // Inset so a focused row's lift never clips against the edge.
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.md)
            }
            // Snap (not animate) to the top on season change so it never competes
            // with the focus engine's own scrolling.
            .onChange(of: selectedSeasonID) { _, _ in
                if let first = episodes.first?.id { proxy.scrollTo(first, anchor: .top) }
            }
            // Open with focus on the episode the user is on (or episode 1) —
            // scrolled into view first so its lazy row exists, then focused.
            // Runs once; season switches never yank focus back afterwards.
            .task(id: episodes.first?.id) {
                guard !didAutoFocus, let target = initialEpisodeID else { return }
                didAutoFocus = true
                try? await Task.sleep(for: .milliseconds(80))
                proxy.scrollTo(target, anchor: .top)
                try? await Task.sleep(for: .milliseconds(140))
                focusedEpisode = target
            }
        }
        // A three-row window (two-column / landscape only); compact iPhone
        // fills naturally.
        .frame(maxWidth: maxWidth)
        .frame(height: useColumns ? episodeViewportHeight : nil)
    }

    private var nowViewingBadge: some View {
        Text("Now Viewing")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.sm).padding(.vertical, 3)
            .background(accent, in: Capsule())
            .padding(Spacing.sm)
    }

    // MARK: - Metrics

    private var leftWidth: CGFloat {
        #if os(tvOS)
        340
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
    /// Episode list width in the two-column layout.
    private var episodeMaxWidth: CGFloat {
        #if os(tvOS)
        900
        #else
        720
        #endif
    }
    /// Wider episode list when there's no season column to share the row with.
    private var singleColumnMaxWidth: CGFloat {
        #if os(tvOS)
        1040
        #else
        720
        #endif
    }
    private var headerSize: CGFloat {
        #if os(tvOS)
        36
        #else
        24
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

/// A single season entry with three calm, distinct states for a 10-foot read:
/// idle (dim text), selected-but-not-focused (accent-tinted with a leading bar),
/// and focused (an on-brand frosted-accent pill — not a harsh pure-white block).
/// No `.animation` here: the enclosing button style owns the single focus
/// transaction so the fill/text move together without a competing animator.
private struct SeasonRowLabel: View {
    let season: MediaItem
    let active: Bool
    let seasonFont: CGFloat
    let accent: Color

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // A slim accent bar marks the current season when it's not focused
            // (the focused pill already signals position).
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(active && !isFocused ? accent : .clear)
                .frame(width: 4, height: seasonFont)
            VStack(alignment: .leading, spacing: 1) {
                Text(season.name)
                    .font(.system(size: seasonFont, weight: active || isFocused ? .semibold : .medium, design: .rounded))
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
        .padding(.vertical, Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(rowBackground)
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if isFocused {
            // On-brand frosted-accent focus pill (cheap: one small material pane).
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(accent.opacity(0.30))
                shape.fill(LiquidGlass.sheen)
                shape.strokeBorder(accent.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: accent.opacity(0.35), radius: 10, y: 4)
        } else if active {
            shape.fill(accent.opacity(0.16))
        } else {
            Color.clear
        }
    }

    private var textColor: Color {
        if isFocused { return .white }
        if active { return .white }
        return .white.opacity(0.72)
    }
    private var subColor: Color { isFocused ? .white.opacity(0.85) : .white.opacity(0.55) }
}
