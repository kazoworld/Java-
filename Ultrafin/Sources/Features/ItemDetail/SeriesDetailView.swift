import SwiftUI

@Observable
@MainActor
final class SeriesDetailViewModel {
    let series: MediaItem
    private let client: JellyfinClient
    private let userID: String

    var detail: MediaItem?
    var seasons: [MediaItem] = []
    var selectedSeasonID: String?
    var episodes: [MediaItem] = []
    var similar: [MediaItem] = []
    var playTarget: MediaItem?
    var isFavorite = false
    var isWatched = false
    var isLoading = true

    init(series: MediaItem, client: JellyfinClient, userID: String) {
        self.series = series
        self.client = client
        self.userID = userID
    }

    var displayed: MediaItem { detail ?? series }
    var selectedSeason: MediaItem? { seasons.first { $0.id == selectedSeasonID } }

    var playLabel: String {
        guard let target = playTarget else { return "Play" }
        let verb = (target.playbackProgress ?? 0) > 0.01 ? "Resume" : "Play"
        if let tag = target.episodeTag { return "\(verb) \(tag)" }
        return verb
    }

    func load() async {
        isLoading = true
        async let detailTask = try? client.itemDetail(series.id, userID: userID)
        async let seasonsTask = try? client.seasons(seriesID: series.id, userID: userID)
        async let nextTask = try? client.nextUp(seriesID: series.id, userID: userID)
        async let similarTask = try? client.similarItems(itemID: series.id, userID: userID)

        detail = await detailTask ?? nil
        seasons = await seasonsTask ?? []
        playTarget = await nextTask ?? nil
        similar = await similarTask ?? []

        isFavorite = displayed.userData?.isFavorite ?? false
        isWatched = displayed.userData?.played ?? false

        let initialID = playTarget?.seasonId ?? seasons.first?.id
        selectedSeasonID = initialID
        if let sid = initialID {
            episodes = (try? await client.episodes(seriesID: series.id, seasonID: sid, userID: userID)) ?? []
        }
        if playTarget == nil { playTarget = episodes.first }
        isLoading = false
    }

    func selectSeason(_ id: String) async {
        guard id != selectedSeasonID else { return }
        selectedSeasonID = id
        episodes = (try? await client.episodes(seriesID: series.id, seasonID: id, userID: userID)) ?? []
    }

    func toggleFavorite() {
        isFavorite.toggle()
        let value = isFavorite
        Task { await client.setFavorite(itemID: series.id, userID: userID, isFavorite: value) }
    }

    func toggleWatched() {
        isWatched.toggle()
        let value = isWatched
        Task { await client.setPlayed(itemID: series.id, userID: userID, isPlayed: value) }
    }
}

/// Rich, Netflix-style series page: backdrop, metadata, a smart Play button,
/// My List / Watched actions, synopsis with cast, and tabs for Episodes and
/// More Like This.
struct SeriesDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    let series: MediaItem

    @State private var model: SeriesDetailViewModel?
    @State private var playback: PlaybackRequest?
    @State private var tab = 0

    private var session: UserSession? {
        if case .authenticated(let s) = appState.phase { return s }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                hero
                if let model {
                    detailColumn(model)
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
        .fullScreenCover(item: $playback) { request in
            if let session {
                VideoPlayerView(queue: request.queue, startIndex: request.index, userID: session.userID)
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
        let item = model?.displayed ?? series
        return DetailHero(backdropURL: backdropURL,
                          colorURL: colorURL,
                          logoURL: logoURL(item),
                          title: item.name,
                          height: heroHeight,
                          edgePadding: edgePadding,
                          titleSize: titleSize,
                          logoMaxWidth: logoMaxWidth,
                          logoMaxHeight: logoMaxHeight) { art in
            if let model {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    DetailBadges(item: model.displayed, seasonCount: model.seasons.count, onDark: true)
                    heroActions(model, art: art)
                }
            }
        }
    }

    private func heroActions(_ model: SeriesDetailViewModel, art: ArtworkColor?) -> some View {
        HStack(spacing: Spacing.xl) {
            Button { if let target = model.playTarget { play(target) } } label: {
                Label(model.playLabel, systemImage: "play.fill")
                    .font(.system(size: actionFont, weight: .bold, design: .rounded))
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.md)
                    .background(tint(art), in: Capsule())
                    .foregroundStyle(playTextColor(art))
            }
            .buttonStyle(UltrafinButtonStyle(focusScale: 1.06, lift: true))

            DetailActionButton(title: "My List",
                               systemImage: model.isFavorite ? "checkmark" : "plus",
                               active: model.isFavorite, onDark: true) { model.toggleFavorite() }
            DetailActionButton(title: "Watched",
                               systemImage: model.isWatched ? "eye.fill" : "eye",
                               active: model.isWatched, onDark: true) { model.toggleWatched() }
            Spacer()
        }
    }

    private func tint(_ c: ArtworkColor?) -> Color { c?.color ?? Color.white.opacity(0.9) }
    private func playTextColor(_ c: ArtworkColor?) -> Color { (c?.isDark ?? false) ? .white : .black }

    private func logoURL(_ item: MediaItem) -> URL? {
        guard let tag = item.imageTags?["Logo"] else { return nil }
        return appState.client?.imageURL(itemID: item.id, kind: .logo, tag: tag, maxWidth: 800)
    }

    // MARK: - Content

    @ViewBuilder
    private func detailColumn(_ model: SeriesDetailViewModel) -> some View {
        let item = model.displayed
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if hasInfo(item) {
                GlassInfoCard {
                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: overviewSize))
                            .foregroundStyle(UltrafinColors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    CastCrewView(item: item)
                }
            }

            DetailTabBar(tabs: ["Episodes", "More Like This"], selection: $tab)

            if tab == 0 {
                seasonPicker(model)
                episodeList(model)
            } else {
                similarRail(model)
            }
        }
        .padding(.horizontal, edgePadding)
        .padding(.top, Spacing.sm)
    }

    private func hasInfo(_ item: MediaItem) -> Bool {
        (item.overview?.isEmpty == false) || item.castText != nil || item.crewLine != nil
    }

    // MARK: - Seasons & episodes

    private func seasonPicker(_ model: SeriesDetailViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                ForEach(model.seasons) { season in
                    Button { Task { await model.selectSeason(season.id) } } label: {
                        Text(season.name)
                            .font(.system(size: actionFont, weight: .semibold, design: .rounded))
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(Capsule().fill(season.id == model.selectedSeasonID
                                                       ? settings.theme.accent.color.opacity(0.9) : Color.clear))
                            .overlay(Capsule().strokeBorder(UltrafinColors.separator, lineWidth: 1))
                            .foregroundStyle(season.id == model.selectedSeasonID ? .white : UltrafinColors.primaryText)
                    }
                    .buttonStyle(UltrafinButtonStyle(focusScale: 1.06, lift: false))
                }
            }
            .padding(.vertical, Spacing.sm)
        }
        .scrollClipDisabled()
    }

    private func episodeList(_ model: SeriesDetailViewModel) -> some View {
        LazyVStack(spacing: Spacing.md) {
            ForEach(model.episodes) { episode in
                Button { play(episode) } label: {
                    EpisodeRow(episode: episode, imageURL: episodeImageURL(episode))
                }
                .buttonStyle(UltrafinButtonStyle(focusScale: 1.02, lift: true))
            }
        }
    }

    private func similarRail(_ model: SeriesDetailViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.lg) {
                ForEach(model.similar) { item in
                    NavigationLink(value: item) {
                        MediaCard(item: item, style: .poster)
                    }
                    .mediaCardButtonStyle()
                }
            }
            .padding(.vertical, Spacing.md)
        }
        .scrollClipDisabled()
    }

    // MARK: - Playback

    private func play(_ episode: MediaItem) {
        guard let model else { return }
        if let idx = model.episodes.firstIndex(where: { $0.id == episode.id }) {
            playback = PlaybackRequest(queue: model.episodes, index: idx)
        } else {
            playback = PlaybackRequest(queue: [episode], index: 0)
        }
    }

    // MARK: - Image URLs

    private var backdropURL: URL? {
        let item = model?.displayed ?? series
        let tag = item.backdropImageTags?.first ?? item.imageTags?["Primary"]
        let kind: JellyfinClient.ImageKind = item.backdropImageTags?.isEmpty == false ? .backdrop : .primary
        return appState.client?.imageURL(itemID: item.id, kind: kind, tag: tag, maxWidth: 1280)
    }

    /// Tiny image for color sampling only.
    private var colorURL: URL? {
        let item = model?.displayed ?? series
        let tag = item.backdropImageTags?.first ?? item.imageTags?["Primary"]
        let kind: JellyfinClient.ImageKind = item.backdropImageTags?.isEmpty == false ? .backdrop : .primary
        return appState.client?.imageURL(itemID: item.id, kind: kind, tag: tag, maxWidth: 240)
    }

    private func episodeImageURL(_ episode: MediaItem) -> URL? {
        let tag = episode.imageTags?["Primary"]
        return appState.client?.imageURL(itemID: episode.id, kind: .primary, tag: tag, maxWidth: 600)
    }

    // MARK: - Metrics

    private var heroHeight: CGFloat {
        #if os(tvOS)
        680
        #else
        480
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        52
        #else
        30
        #endif
    }
    private var overviewSize: CGFloat {
        #if os(tvOS)
        24
        #else
        15
        #endif
    }
    private var actionFont: CGFloat {
        #if os(tvOS)
        24
        #else
        16
        #endif
    }
    private var edgePadding: CGFloat {
        #if os(tvOS)
        60
        #else
        20
        #endif
    }
    private var logoMaxWidth: CGFloat {
        #if os(tvOS)
        640
        #else
        320
        #endif
    }
    private var logoMaxHeight: CGFloat {
        #if os(tvOS)
        150
        #else
        90
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
