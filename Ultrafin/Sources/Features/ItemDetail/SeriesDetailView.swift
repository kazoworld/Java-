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
    /// Episodes cached per season so re-selecting one is instant (no re-fetch).
    private var episodesBySeason: [String: [MediaItem]] = [:]
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
            let eps = (try? await client.episodes(seriesID: series.id, seasonID: sid, userID: userID)) ?? []
            episodesBySeason[sid] = eps
            episodes = eps
        }
        if playTarget == nil { playTarget = episodes.first }
        isLoading = false
    }

    func selectSeason(_ id: String) async {
        guard id != selectedSeasonID else { return }
        selectedSeasonID = id
        if let cached = episodesBySeason[id] {
            episodes = cached // instant
            return
        }
        let eps = (try? await client.episodes(seriesID: series.id, seasonID: id, userID: userID)) ?? []
        episodesBySeason[id] = eps
        episodes = eps
    }

    /// Episodes of the earliest season, for "Play from beginning".
    func firstSeasonEpisodes() async -> [MediaItem] {
        guard let first = seasons.first else { return episodes }
        if first.id == selectedSeasonID { return episodes }
        return (try? await client.episodes(seriesID: series.id, seasonID: first.id, userID: userID)) ?? episodes
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
    @State private var showEpisodes = false
    @State private var toast: String?
    @State private var artColor: ArtworkColor?
    /// Drives the one-time arrival animation (art settles in, content rises).
    @State private var appeared = false

    private var session: UserSession? {
        if case .authenticated(let s) = appState.phase { return s }
        return nil
    }

    var body: some View {
        GeometryReader { screen in
            let landscape = screen.size.width >= screen.size.height * 1.2
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection(landscape: landscape, screen: screen.size)
                    if let model, !showEpisodes {
                        belowContent(model)
                    }
                }
                .padding(.bottom, Spacing.xxl)
            }
            .background(UltrafinColors.background)
        }
        .ignoresSafeArea()
        // Detail pages are always dark (the Netflix look) so the overlaid white
        // column reads, and the episodes/“more like this” below resolve their
        // adaptive colors to the light-on-dark variants.
        .environment(\.colorScheme, .dark)
        #if os(tvOS)
        // Back/Menu closes the inline episodes browser first; otherwise the
        // navigation pops as usual (perform: nil restores the default).
        .onExitCommand(perform: showEpisodes ? { withAnimation(.easeInOut(duration: 0.25)) { showEpisodes = false } } : nil)
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await loadIfNeeded() }
        .task(id: colorURL) { artColor = await ImageColor.vibrant(from: colorURL) }
        .onAppear { appeared = true }
        .fullScreenCover(item: $playback) { request in
            if let session {
                VideoPlayerView(queue: request.queue, startIndex: request.index,
                                userID: session.userID, resume: request.resume)
            }
        }
        .toast($toast)
    }

    private func loadIfNeeded() async {
        guard model == nil, let session, let client = appState.client else { return }
        let vm = SeriesDetailViewModel(series: series, client: client, userID: session.userID)
        model = vm
        await vm.load()
    }

    // MARK: - Hero (Netflix-style art + content column)

    private func heroSection(landscape: Bool, screen: CGSize) -> some View {
        ZStack(alignment: landscape ? .leading : .bottomLeading) {
            // While browsing episodes, swap the live double-masked backdrop for a
            // cheap OPAQUE scrim. The opaque base lets the GPU cull the expensive
            // masked art entirely (the old translucent dim couldn't), which is the
            // single biggest fix for the season selector's lag — and it makes the
            // episode synopses far more readable.
            if showEpisodes {
                episodesBackground.transition(.opacity)
            } else {
                DetailArtBackdrop(backdropURL: backdropURL, artColor: artColor, landscape: landscape)
                    // Art settles in from a slight zoom — a gentle Ken-Burns arrival.
                    .scaleEffect(appeared ? 1 : 1.06)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.7), value: appeared)
                    .transition(.opacity)
            }

            if let model {
                if showEpisodes {
                    episodesPanel(model)
                        .padding(.horizontal, edgePadding)
                        .padding(.vertical, edgePadding * 0.6)
                        .transition(.opacity)
                } else {
                    contentColumn(model)
                        .frame(maxWidth: landscape ? screen.width * 0.52 : .infinity, alignment: .leading)
                        .padding(.horizontal, edgePadding)
                        .padding(.bottom, landscape ? 0 : Spacing.xl)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: landscape ? .leading : .bottom)
                        // Content rises and fades in just behind the art.
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)
                        .animation(.smooth(duration: 0.55).delay(0.12), value: appeared)
                        .transition(.opacity)
                }
            }
        }
        .frame(height: landscape ? screen.height : screen.height * 0.74)
    }

    @ViewBuilder
    private func contentColumn(_ model: SeriesDetailViewModel) -> some View {
        let item = model.displayed
        VStack(alignment: .leading, spacing: Spacing.md) {
            TitleLogo(logoURL: logoURL(item), title: item.name,
                      fallbackFont: .system(size: titleSize, weight: .heavy, design: .rounded),
                      fallbackColor: .white, maxWidth: logoMaxWidth, maxHeight: logoMaxHeight)
                .shadow(color: .black.opacity(0.6), radius: 14, y: 4)

            DetailBadges(item: item, seasonCount: model.seasons.count, onDark: true)

            if let target = model.playTarget, target.type == .episode {
                Text(episodeHeadline(target))
                    .font(.system(size: overviewSize + 2, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: 5, y: 2)
            }

            if let synopsis = (model.playTarget?.overview ?? item.overview), !synopsis.isEmpty {
                Text(synopsis)
                    .font(.system(size: overviewSize))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
            }

            actionRows(model)
                .padding(.top, Spacing.xs)
        }
    }

    private func actionRows(_ model: SeriesDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let target = model.playTarget {
                let prog = target.playbackProgress
                DetailActionRow(icon: "play.fill", title: model.playLabel,
                                progress: (prog ?? 0) > 0.01 && (prog ?? 0) < 0.95 ? prog : nil,
                                prominent: true) { play(target) }
            }
            DetailActionRow(icon: "arrow.counterclockwise", title: "Play from beginning") {
                Task {
                    let eps = await model.firstSeasonEpisodes()
                    if !eps.isEmpty { playback = PlaybackRequest(queue: eps, index: 0, resume: false) }
                }
            }
            DetailActionRow(icon: "rectangle.stack.fill", title: "Episodes and more") {
                withAnimation(.easeInOut(duration: 0.3)) { showEpisodes = true }
            }
            DetailActionRow(icon: model.isFavorite ? "checkmark" : "plus",
                            title: model.isFavorite ? "In My List" : "Add to My List") {
                model.toggleFavorite()
                Haptics.play(.success)
                toast = model.isFavorite ? "Added to My List" : "Removed from My List"
            }
            DetailActionRow(icon: model.isWatched ? "eye.fill" : "eye",
                            title: model.isWatched ? "Watched" : "Mark as Watched") {
                model.toggleWatched()
                Haptics.play(.success)
                toast = model.isWatched ? "Marked as Watched" : "Marked as Unwatched"
            }
        }
        .frame(maxWidth: actionMaxWidth)
    }

    private func episodeHeadline(_ ep: MediaItem) -> String {
        if let tag = ep.episodeTag { return "\(tag)  ·  \(ep.name)" }
        return ep.name
    }

    private func logoURL(_ item: MediaItem) -> URL? {
        guard let tag = item.imageTags?["Logo"] else { return nil }
        return appState.client?.imageURL(itemID: item.id, kind: .logo, tag: tag, maxWidth: 800)
    }

    /// The cheap, opaque background shown behind the episode browser — a solid
    /// base (so the masked backdrop behind it is culled) with a whisper of the
    /// artwork color up top for continuity. No masks, no material → 60fps.
    private var episodesBackground: some View {
        ZStack {
            UltrafinColors.background
            LinearGradient(stops: [
                .init(color: (artColor?.color ?? settings.theme.accent.color).opacity(0.22), location: 0.0),
                .init(color: .clear, location: 0.55)
            ], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    // MARK: - Inline episode browser (fills the hero card area)

    private func episodesPanel(_ model: SeriesDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Button { withAnimation(.easeInOut(duration: 0.25)) { showEpisodes = false } } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "chevron.left").font(.system(size: 20, weight: .bold))
                    Text("Back").font(.system(size: 18, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
                .glassCapsule(dim: 0.12)
            }
            .buttonStyle(UltrafinButtonStyle(focusScale: 1.06, lift: false))

            SeasonEpisodeBrowser(
                seriesName: model.displayed.name,
                seasons: model.seasons,
                selectedSeasonID: model.selectedSeasonID,
                episodes: model.episodes,
                currentEpisodeID: model.playTarget?.id,
                episodeImageURL: episodeImageURL,
                onSelectSeason: { id in Task { await model.selectSeason(id) } },
                onPlay: { play($0) }
            )
            // Center the browser in the space below the Back button so the block
            // is balanced rather than top-heavy.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Below the fold (more like this)

    @ViewBuilder
    private func belowContent(_ model: SeriesDetailViewModel) -> some View {
        let people = model.displayed.people ?? []
        VStack(alignment: .leading, spacing: Spacing.xl) {
            if !people.isEmpty {
                CastRow(people: people)
            }
            if !model.similar.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("More Like This")
                        .font(.system(size: titleSize * 0.5, weight: .bold, design: .rounded))
                        .foregroundStyle(UltrafinColors.primaryText)
                    similarRail(model)
                }
            }
        }
        .padding(.horizontal, edgePadding)
        .padding(.top, Spacing.lg)
    }

    // MARK: - Seasons & episodes

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

    private func play(_ episode: MediaItem, resume: Bool = true) {
        guard let model else { return }
        Haptics.play(.medium)
        if let idx = model.episodes.firstIndex(where: { $0.id == episode.id }) {
            playback = PlaybackRequest(queue: model.episodes, index: idx, resume: resume)
        } else {
            playback = PlaybackRequest(queue: [episode], index: 0, resume: resume)
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

    private var titleSize: CGFloat {
        #if os(tvOS)
        52
        #else
        30
        #endif
    }
    private var overviewSize: CGFloat {
        #if os(tvOS)
        22
        #else
        15
        #endif
    }
    private var actionMaxWidth: CGFloat {
        #if os(tvOS)
        600
        #else
        .infinity
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
struct EpisodeRow: View {
    let episode: MediaItem
    let imageURL: URL?

    @Environment(\.isFocused) private var isFocused
    @Environment(SettingsStore.self) private var settings

    static var thumbW: CGFloat {
        #if os(tvOS)
        300
        #else
        160
        #endif
    }
    /// The fixed total height of one row (thumbnail + vertical padding), exposed
    /// so the episode list can size its viewport to show a whole number of rows.
    static var rowHeight: CGFloat { thumbW * 9 / 16 + Spacing.sm * 2 }

    private var thumbWidth: CGFloat { Self.thumbW }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            RemoteImage(url: imageURL)
                .frame(width: thumbWidth, height: thumbWidth * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous))
                // Resume bar, bounded to the thumbnail (a fixed width — no
                // GeometryReader, which previously stretched across the row).
                .overlay(alignment: .bottom) {
                    if let progress = episode.playbackProgress {
                        let barWidth = thumbWidth - Spacing.md * 2
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.5))
                            Capsule().fill(settings.theme.accent.color)
                                .frame(width: max(0, barWidth * progress))
                        }
                        .frame(width: barWidth, height: 4)
                        .padding(.bottom, Spacing.sm)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous)
                        .strokeBorder(isFocused ? settings.theme.accent.color : UltrafinColors.separator,
                                      lineWidth: isFocused ? 3 : 1)
                )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(episodeHeadline)
                    .font(.system(size: headlineSize, weight: .bold, design: .rounded))
                    .foregroundStyle(UltrafinColors.primaryText)
                    .lineLimit(1)
                HStack(spacing: Spacing.sm) {
                    if let runtime = episode.runtimeText {
                        Text(runtime)
                            .font(.system(size: metaSize, weight: .medium))
                            .foregroundStyle(UltrafinColors.tertiaryText)
                    }
                    if episode.isWatched {
                        Label("Watched", systemImage: "checkmark.circle.fill")
                            .font(.system(size: metaSize * 0.85, weight: .semibold))
                            .foregroundStyle(UltrafinColors.secondaryText)
                            .labelStyle(.titleAndIcon)
                    }
                }
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        // Brighter than secondaryText + a little leading: the
                        // synopsis is the hardest thing to read from the couch.
                        .font(.system(size: overviewSize))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineSpacing(3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A fixed height keeps every row identical, so the list shows a whole
        // number of rows with clean top/bottom edges (no jagged partials).
        // (minHeight == maxHeight fixes the height while maxWidth stays flexible —
        // a single .frame can't mix the flexible `maxWidth` with a fixed `height`.)
        .frame(maxWidth: .infinity, minHeight: thumbWidth * 9 / 16,
               maxHeight: thumbWidth * 9 / 16, alignment: .leading)
        .padding(Spacing.sm)
        // A cheap opaque card (no per-row blur/shadow) so a long list scrolls and
        // swaps seasons smoothly. The single focus cue is the thumbnail's accent
        // ring (above) + the row fill brightening; the row border stays a static
        // hairline (no duplicate accent border), and the button style owns the
        // one focus animation — no per-row animator competing with it.
        .background(
            RoundedRectangle(cornerRadius: Spacing.cornerRadius, style: .continuous)
                .fill(.white.opacity(isFocused ? 0.12 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var episodeHeadline: String {
        if let n = episode.indexNumber { return "\(n). \(episode.name)" }
        return episode.name
    }

    private var headlineSize: CGFloat {
        #if os(tvOS)
        30
        #else
        19
        #endif
    }
    private var metaSize: CGFloat {
        #if os(tvOS)
        20
        #else
        14
        #endif
    }
    private var overviewSize: CGFloat {
        #if os(tvOS)
        22
        #else
        15
        #endif
    }
}
