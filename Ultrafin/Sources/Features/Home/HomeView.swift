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
    /// Latest items from the media bar's chosen libraries (when not "all").
    var featuredPool: [MediaItem] = []
    var isLoading = true
    var errorMessage: String?

    func load(client: JellyfinClient, userID: String, featured: FeaturedPreferences) async {
        isLoading = true
        defer { isLoading = false }
        // Fetch the rails concurrently so the screen paints fast.
        async let resumeTask = try? client.resumeItems(userID: userID)
        async let latestTask = try? client.latestItems(userID: userID)
        async let viewsTask = try? client.userViews(userID: userID)
        async let comingTask = try? client.nextUp(userID: userID)
        async let showsTask = try? client.latestItems(userID: userID, includeItemTypes: "Series")
        async let favTask = try? client.favorites(userID: userID)
        resume = await resumeTask ?? []
        latest = await latestTask ?? []
        libraries = await viewsTask ?? []
        comingUp = await comingTask ?? []
        recentShows = await showsTask ?? []
        favorites = await favTask ?? []

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
            if out.count == prefs.itemCount { break }
        }
        return out
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                if model.isLoading {
                    loadingRows
                } else {
                    // Rows render in the user's configured order, skipping any
                    // they've disabled or that have no content.
                    ForEach(settings.homeLayout.rows) { config in
                        if config.isEnabled {
                            row(for: config.kind)
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
        .background(AmbientBackground())
        .navigationDestination(for: MediaItem.self) { item in
            if item.type == .series {
                SeriesDetailView(series: item)
            } else {
                ItemDetailView(item: item)
            }
        }
        .fullScreenCover(item: $playingItem) { item in
            if let session {
                VideoPlayerView(item: item, userID: session.userID)
            }
        }
        #if os(iOS)
        .navigationTitle("Ultrafin")
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task {
            guard let session, let client = appState.client else { return }
            await model.load(client: client, userID: session.userID, featured: settings.featured)
        }
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
                             autoAdvance: settings.featured.autoAdvance) { item in
                    playingItem = item
                }
            }
        case .continueWatching:
            if !model.resume.isEmpty {
                MediaRail(title: "Continue Watching", items: model.resume, style: .landscape)
            }
        case .comingUp:
            if !model.comingUp.isEmpty {
                MediaRail(title: "Coming Up", items: model.comingUp, style: .landscape)
            }
        case .recentlyAdded:
            if !model.latest.isEmpty {
                MediaRail(title: "Recently Added", items: model.latest, style: .poster)
            }
        case .recentShows:
            if !model.recentShows.isEmpty {
                MediaRail(title: "Recently Added TV Shows", items: model.recentShows, style: .poster)
            }
        case .favorites:
            if !model.favorites.isEmpty {
                MediaRail(title: "Favorites", items: model.favorites, style: .poster)
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
