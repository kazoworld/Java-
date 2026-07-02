import SwiftUI

@Observable
@MainActor
final class HomeViewModel {
    var resume: [MediaItem] = []
    var latest: [MediaItem] = []
    var libraries: [MediaItem] = []
    var comingUp: [MediaItem] = []
    var recentShows: [MediaItem] = []
    var favorites: [MediaItem] = []
    var hiddenGems: [MediaItem] = []
    /// A fresh random spread for the media bar (shuffled each launch).
    var shuffled: [MediaItem] = []
    /// Latest items from the media bar's chosen libraries (when not "all").
    var featuredPool: [MediaItem] = []
    var isLoading = true
    var errorMessage: String?
    /// Set once the first load finishes so re-appearing (e.g. switching back to
    /// the Home tab) doesn't kick off a fresh, janky reload every time.
    private(set) var didLoad = false

    func load(client: JellyfinClient, userID: String, featured: FeaturedPreferences) async {
        isLoading = true
        defer { isLoading = false; didLoad = true }
        // Fetch the rails concurrently so the screen paints fast.
        async let resumeTask = try? client.resumeItems(userID: userID)
        async let latestTask = try? client.latestItems(userID: userID)
        async let viewsTask = try? client.userViews(userID: userID)
        async let comingTask = try? client.nextUp(userID: userID)
        async let showsTask = try? client.latestItems(userID: userID, includeItemTypes: "Series")
        async let favTask = try? client.favorites(userID: userID)
        async let gemsTask = try? client.hiddenGems(userID: userID)
        async let shuffledTask = try? client.randomItems(userID: userID)
        resume = await resumeTask ?? []
        latest = await latestTask ?? []
        libraries = await viewsTask ?? []
        comingUp = await comingTask ?? []
        recentShows = await showsTask ?? []
        favorites = await favTask ?? []
        hiddenGems = await gemsTask ?? []
        shuffled = await shuffledTask ?? []

        // When the media bar is scoped to specific libraries, pull their latest.
        if !featured.sourceLibraryIDs.isEmpty {
            var pool: [MediaItem] = []
            for libraryID in featured.sourceLibraryIDs {
                if let items = try? await client.latestItems(userID: userID, parentID: libraryID) {
                    pool.append(contentsOf: items)
                }
            }
            featuredPool = pool
        } else {
            featuredPool = []
        }

        if resume.isEmpty && latest.isEmpty && libraries.isEmpty {
            errorMessage = "Couldn't load your library."
        }
    }
}

/// Home dashboard: continue watching, recently added, and library shortcuts.
struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @State private var model = HomeViewModel()
    @State private var playingItem: MediaItem?
    @State private var revealed = false
    @State private var showProfiles = false
    /// The featured title's artwork color — tints the ambient background so the
    /// whole screen breathes with what's in the media bar.
    @State private var heroTint: Color?

    private var session: UserSession? {
        if case .authenticated(let session) = appState.phase { return session }
        return nil
    }

    /// Items for the hero "media bar", honoring the source, content-type,
    /// library scope and item-count preferences.
    private var featured: [MediaItem] {
        let prefs = settings.featured
        let pool: [MediaItem]
        if !prefs.sourceLibraryIDs.isEmpty {
            pool = model.featuredPool
        } else {
            switch prefs.source {
            case .shuffle: pool = model.shuffled
            case .recentlyAdded: pool = model.latest
            case .continueWatching: pool = model.resume
            case .both: pool = model.resume + model.latest
            }
        }
        let typed = pool.filter { item in
            switch prefs.contentType {
            case .all: return true
            case .movies: return item.type == .movie
            case .shows: return item.type == .series || item.type == .episode
            }
        }
        let withArt = typed.filter { $0.backdropImageTags?.isEmpty == false }
        let chosen = withArt.isEmpty ? typed : withArt
        var seen = Set<String>()
        var out: [MediaItem] = []
        for item in chosen where !seen.contains(item.id) {
            seen.insert(item.id)
            out.append(item)
            if prefs.itemCount > 0 && out.count == prefs.itemCount { break }
        }
        return out
    }

    /// Continue Watching + Next Up, merged into one de-duplicated row. The order
    /// (Next Up first vs. in-progress first) follows the user's preference.
    private var continueWatching: [MediaItem] {
        var seen = Set<String>()
        let ordered = settings.nextUpFirst
            ? (model.comingUp + model.resume)
            : (model.resume + model.comingUp)
        return ordered.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                if model.isLoading {
                    loadingRows
                } else {
                    // Rows render in the user's configured order, skipping any
                    // they've disabled or that have no content. They settle in
                    // with a gentle staggered reveal on first load (one-time,
                    // change-driven — no continuous animation cost).
                    ForEach(Array(settings.homeLayout.rows.enumerated()), id: \.element.id) { idx, config in
                        if config.isEnabled {
                            row(for: config.kind)
                                .opacity(revealed ? 1 : 0)
                                .offset(y: revealed ? 0 : 18)
                                .animation(.smooth(duration: 0.5).delay(Double(idx) * 0.07), value: revealed)
                        }
                    }
                    if let error = model.errorMessage {
                        Text(error)
                            .font(Typography.body)
                            .foregroundStyle(UltrafinColors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Spacing.xxl)
                    }
                }
            }
            .padding(.bottom, Spacing.lg)
        }
        // Full-bleed so the hero media bar reaches every edge; rails self-pad
        // to stay within the tvOS title-safe area.
        .ignoresSafeArea()
        .background(AmbientBackground(tint: heroTint))
        #if os(tvOS)
        // Profile avatar pinned to the top-right corner, level with the tab bar.
        // It's its own focus SECTION so the focus engine can actually route to
        // it (press right from the tabs, or up-right from the hero) — a bare
        // floating overlay is unreachable on tvOS.
        .overlay(alignment: .topTrailing) {
            profileButton
                .padding(.top, 46)
                .padding(.trailing, 60)
                .focusSection()
        }
        #else
        .toolbar { ToolbarItem(placement: .topBarTrailing) { profileButton } }
        #endif
        .fullScreenCoverCompat(isPresented: $showProfiles) {
            ProfileSwitcherView()
        }
        .navigationDestination(for: MediaItem.self) { item in
            if item.type == .collectionFolder || item.type == .folder || item.type == .boxSet {
                LibraryContentsView(library: item)
            } else if item.type == .series {
                SeriesDetailView(series: item)
            } else {
                ItemDetailView(item: item)
            }
        }
        .fullScreenCover(item: $playingItem) { item in
            if let session {
                VideoPlayerView(item: item, userID: session.userID,
                                resume: settings.playback.autoResume)
            }
        }
        #if os(iOS)
        .navigationTitle("Ultrafin")
        .navigationBarTitleDisplayMode(.large)
        // Pull to refresh — the natural way to pick up newly-added media without
        // relaunching (Home otherwise only loads once per session).
        .refreshable {
            if let session, let client = appState.client {
                await model.load(client: client, userID: session.userID, featured: settings.featured)
            }
        }
        #endif
        .task {
            guard let session, let client = appState.client else {
                revealed = true
                return
            }
            if !model.didLoad {
                await model.load(client: client, userID: session.userID, featured: settings.featured)
            }
            // Let the rows render hidden once, then trigger the staggered reveal.
            try? await Task.sleep(for: .milliseconds(40))
            revealed = true
        }
    }

    /// The circular profile avatar in the top-right — opens the Who's Watching
    /// switcher. Uses the Jellyfin profile picture when set, else a monogram.
    private var profileButton: some View {
        Button { showProfiles = true } label: {
            ProfileAvatar(name: session?.username ?? "?",
                          imageURL: avatarURL,
                          size: avatarSize)
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.15, lift: true))
        .accessibilityLabel("Switch profile")
    }

    private var avatarURL: URL? {
        guard let user = appState.currentUser, user.primaryImageTag != nil else { return nil }
        return appState.client?.userImageURL(userID: user.id, tag: user.primaryImageTag,
                                             maxWidth: Int(avatarSize * 3))
    }

    private var avatarSize: CGFloat {
        #if os(tvOS)
        64
        #else
        34
        #endif
    }

    /// "Play Something": pick a smart, immediately-playable item — a next-up or
    /// in-progress episode if available, otherwise a random unwatched gem/recent.
    private func playSomething() {
        let playable: (MediaItem) -> Bool = { $0.type == .movie || $0.type == .episode }
        let primary = (model.comingUp + model.resume).filter(playable)
        let fallback = (model.hiddenGems + model.latest + model.recentShows).filter(playable)
        if let pick = primary.randomElement() ?? fallback.randomElement() {
            playingItem = pick
        }
    }

    /// Applies the "hide watched" preference to a discovery row.
    private func visible(_ items: [MediaItem]) -> [MediaItem] {
        settings.hideWatched ? items.filter { !$0.isWatched } : items
    }

    /// Renders the content for a configured Home row, or nothing if there's no
    /// data for it yet.
    @ViewBuilder
    private func row(for kind: HomeRowKind) -> some View {
        switch kind {
        case .featured:
            if !featured.isEmpty {
                FeaturedHero(items: featured,
                             rotationSeconds: settings.featured.rotationSeconds,
                             autoAdvance: settings.featured.autoAdvance,
                             onPlay: { item in playingItem = item },
                             onShuffle: { playSomething() },
                             onColorChange: { heroTint = $0 })
            }
        case .continueWatching:
            if !continueWatching.isEmpty {
                MediaRail(title: "Continue Watching", items: continueWatching, style: .landscape)
            }
        case .comingUp:
            // Folded into Continue Watching — no standalone row.
            EmptyView()
        case .recentlyAdded:
            let items = visible(model.latest)
            if !items.isEmpty {
                MediaRail(title: "Recently Added", items: items, style: .poster)
            }
        case .recentShows:
            let items = visible(model.recentShows)
            if !items.isEmpty {
                MediaRail(title: "Recently Added TV Shows", items: items, style: .poster)
            }
        case .favorites:
            // Favorites are intentional — never filtered.
            if !model.favorites.isEmpty {
                MediaRail(title: "Favorites", items: model.favorites, style: .poster)
            }
        case .hiddenGems:
            let items = visible(model.hiddenGems)
            if !items.isEmpty {
                MediaRail(title: "Hidden Gems", items: items, style: .poster)
            }
        case .libraries:
            if !model.libraries.isEmpty {
                // Libraries read as wide banners (their art is landscape and the
                // names need room), not tall posters.
                MediaRail(title: "Your Libraries", items: model.libraries, style: .landscape)
            }
        }
    }

    private var loadingRows: some View {
        ForEach(0..<2, id: \.self) { _ in
            VStack(alignment: .leading, spacing: Spacing.md) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(UltrafinColors.elevatedSurface)
                    .frame(width: 180, height: 22)
                    .shimmer()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(0..<5, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: Spacing.posterCornerRadius)
                                .fill(UltrafinColors.elevatedSurface)
                                .frame(width: 130, height: 195)
                                .shimmer()
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                }
            }
        }
    }
}
