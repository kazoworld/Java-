import SwiftUI

@Observable
@MainActor
final class SeriesDetailViewModel {
    let series: MediaItem
    private let client: JellyfinClient
    private let userID: String

    var seasons: [MediaItem] = []
    var selectedSeasonID: String?
    var episodes: [MediaItem] = []
    /// The episode the big Play button will start (resume / next up / first).
    var playTarget: MediaItem?
    var isLoading = true

    init(series: MediaItem, client: JellyfinClient, userID: String) {
        self.series = series
        self.client = client
        self.userID = userID
    }

    var selectedSeason: MediaItem? { seasons.first { $0.id == selectedSeasonID } }

    /// "Resume S1·E4" / "Play S1·E1" / "Play".
    var playLabel: String {
        guard let target = playTarget else { return "Play" }
        let verb = (target.playbackProgress ?? 0) > 0.01 ? "Resume" : "Play"
        if let tag = target.episodeTag { return "\(verb) \(tag)" }
        return verb
    }

    func load() async {
        isLoading = true
        async let seasonsTask = try? client.seasons(seriesID: series.id, userID: userID)
        async let nextTask = try? client.nextUp(seriesID: series.id, userID: userID)

        seasons = await seasonsTask ?? []
        playTarget = await nextTask ?? nil

        // Open on the season that contains the next-up episode, else the first.
        let initialID = playTarget?.seasonId ?? seasons.first?.id
        selectedSeasonID = initialID
        if let sid = initialID {
            episodes = (try? await client.episodes(seriesID: series.id, seasonID: sid, userID: userID)) ?? []
        }
        // No next-up (fresh series) → default to the first episode.
        if playTarget == nil { playTarget = episodes.first }
        isLoading = false
    }

    func selectSeason(_ id: String) async {
        guard id != selectedSeasonID else { return }
        selectedSeasonID = id
        episodes = (try? await client.episodes(seriesID: series.id, seasonID: id, userID: userID)) ?? []
    }
}

/// Netflix-style series page: backdrop hero with a smart Play button, a season
/// switcher, and the episode list for the selected season.
struct SeriesDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    let series: MediaItem

    @State private var model: SeriesDetailViewModel?
    @State private var playingItem: MediaItem?

    private var session: UserSession? {
        if case .authenticated(let s) = appState.phase { return s }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                hero
                if let model {
                    if !model.seasons.isEmpty {
                        seasonPicker(model)
                    }
                    episodeList(model)
                }
            }
            .padding(.bottom, Spacing.xxl)
        }
        .ignoresSafeArea(edges: .top)
        .background(AmbientBackground())
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await loadIfNeeded() }
        .fullScreenCover(item: $playingItem) { item in
            if let session {
                VideoPlayerView(item: item, userID: session.userID)
            }
        }
    }

    private func loadIfNeeded() async {
        guard model == nil, let session, let client = appState.client else { return }
        let vm = SeriesDetailViewModel(series: series, client: client, userID: session.userID)
        model = vm
        await vm.load()
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: backdropURL)
                .frame(height: heroHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(UltrafinColors.heroScrim)

            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(series.name)
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(UltrafinColors.primaryText)
                    .lineLimit(2)
                metadata
                if let overview = series.overview, !overview.isEmpty {
                    Text(overview)
                        .font(Typography.body)
                        .foregroundStyle(UltrafinColors.secondaryText)
                        .lineLimit(3)
                        .frame(maxWidth: 900, alignment: .leading)
                }
                playButton
            }
            .padding(.horizontal, edgePadding)
            .padding(.bottom, Spacing.lg)
        }
    }

    private var metadata: some View {
        HStack(spacing: Spacing.md) {
            if let year = series.productionYear { chip(String(year)) }
            if let rating = series.officialRating { chip(rating) }
            if let community = series.communityRating { chip(String(format: "★ %.1f", community)) }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(UltrafinColors.secondaryText)
    }

    @ViewBuilder
    private var playButton: some View {
        if let model, let target = model.playTarget {
            Button { playingItem = target } label: {
                Label(model.playLabel, systemImage: "play.fill")
                    .font(.system(size: actionFont, weight: .semibold, design: .rounded))
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(settings.theme.accent.color, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(UltrafinButtonStyle(focusScale: 1.08, lift: false))
            .padding(.top, Spacing.sm)
        }
    }

    // MARK: - Season picker

    private func seasonPicker(_ model: SeriesDetailViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                ForEach(model.seasons) { season in
                    Button {
                        Task { await model.selectSeason(season.id) }
                    } label: {
                        Text(season.name)
                            .font(.system(size: actionFont, weight: .semibold, design: .rounded))
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                Capsule().fill(season.id == model.selectedSeasonID
                                               ? settings.theme.accent.color.opacity(0.9)
                                               : Color.clear)
                            )
                            .overlay(Capsule().strokeBorder(UltrafinColors.separator, lineWidth: 1))
                            .foregroundStyle(season.id == model.selectedSeasonID
                                             ? .white : UltrafinColors.primaryText)
                    }
                    .buttonStyle(UltrafinButtonStyle(focusScale: 1.06, lift: false))
                }
            }
            .padding(.horizontal, edgePadding)
            .padding(.vertical, Spacing.sm)
        }
        .scrollClipDisabled()
    }

    // MARK: - Episodes

    private func episodeList(_ model: SeriesDetailViewModel) -> some View {
        LazyVStack(spacing: Spacing.md) {
            ForEach(model.episodes) { episode in
                Button { playingItem = episode } label: {
                    EpisodeRow(episode: episode, imageURL: episodeImageURL(episode))
                }
                .buttonStyle(UltrafinButtonStyle(focusScale: 1.03, lift: true))
            }
        }
        .padding(.horizontal, edgePadding)
    }

    // MARK: - Image URLs

    private var backdropURL: URL? {
        let tag = series.backdropImageTags?.first ?? series.imageTags?["Primary"]
        let kind: JellyfinClient.ImageKind = series.backdropImageTags?.isEmpty == false ? .backdrop : .primary
        return appState.client?.imageURL(itemID: series.id, kind: kind, tag: tag, maxWidth: 1920)
    }

    private func episodeImageURL(_ episode: MediaItem) -> URL? {
        let tag = episode.imageTags?["Primary"]
        return appState.client?.imageURL(itemID: episode.id, kind: .primary, tag: tag, maxWidth: 600)
    }

    // MARK: - Platform metrics

    private var heroHeight: CGFloat {
        #if os(tvOS)
        520
        #else
        300
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        52
        #else
        32
        #endif
    }
    private var actionFont: CGFloat {
        #if os(tvOS)
        22
        #else
        16
        #endif
    }
    private var edgePadding: CGFloat {
        #if os(tvOS)
        56
        #else
        20
        #endif
    }
}

/// A single episode row: thumbnail with resume progress, number, title, runtime
/// and synopsis.
private struct EpisodeRow: View {
    let episode: MediaItem
    let imageURL: URL?

    @Environment(\.isFocused) private var isFocused

    private var thumbWidth: CGFloat {
        #if os(tvOS)
        300
        #else
        160
        #endif
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ZStack(alignment: .bottom) {
                RemoteImage(url: imageURL)
                    .frame(width: thumbWidth, height: thumbWidth * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous))

                if let progress = episode.playbackProgress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.4))
                            Capsule().fill(UltrafinColors.accent).frame(width: geo.size.width * progress)
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

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(episodeHeadline)
                    .font(.system(size: headlineSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(UltrafinColors.primaryText)
                    .lineLimit(1)
                if let runtime = episode.runtimeText {
                    Text(runtime)
                        .font(Typography.caption)
                        .foregroundStyle(UltrafinColors.tertiaryText)
                }
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(Typography.caption)
                        .foregroundStyle(UltrafinColors.secondaryText)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .glassCard()
        .animation(.smooth(duration: 0.2), value: isFocused)
    }

    private var episodeHeadline: String {
        if let n = episode.indexNumber { return "\(n). \(episode.name)" }
        return episode.name
    }

    private var headlineSize: CGFloat {
        #if os(tvOS)
        24
        #else
        16
        #endif
    }
}
