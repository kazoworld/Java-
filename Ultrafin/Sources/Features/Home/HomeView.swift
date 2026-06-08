import SwiftUI

@Observable
@MainActor
final class HomeViewModel {
    var resume: [MediaItem] = []
    var latest: [MediaItem] = []
    var libraries: [MediaItem] = []
    var isLoading = true
    var errorMessage: String?

    func load(client: JellyfinClient, userID: String) async {
        isLoading = true
        defer { isLoading = false }
        // Fetch the three home rails concurrently so the screen paints fast.
        async let resumeTask = try? client.resumeItems(userID: userID)
        async let latestTask = try? client.latestItems(userID: userID)
        async let viewsTask = try? client.userViews(userID: userID)
        resume = await resumeTask ?? []
        latest = await latestTask ?? []
        libraries = await viewsTask ?? []
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

    /// Up to five items with artwork for the hero "media bar", drawn from
    /// resume + recently-added and de-duplicated.
    private var featured: [MediaItem] {
        let pool = model.resume + model.latest
        let withArt = pool.filter { $0.backdropImageTags?.isEmpty == false }
        let chosen = withArt.isEmpty ? pool : withArt
        var seen = Set<String>()
        var out: [MediaItem] = []
        for item in chosen where !seen.contains(item.id) {
            seen.insert(item.id)
            out.append(item)
            if out.count == 5 { break }
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
        .ignoresSafeArea(edges: .top)
        .background(UltrafinColors.background.ignoresSafeArea())
        .navigationDestination(for: MediaItem.self) { item in
            ItemDetailView(item: item)
        }
        .fullScreenCover(item: $playingItem) { item in
            if let session {
                VideoPlayerView(item: item, userID: session.userID)
            }
        }
        .navigationTitle("Ultrafin")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task {
            guard let session, let client = appState.client else { return }
            await model.load(client: client, userID: session.userID)
        }
    }

    /// Renders the content for a configured Home row, or nothing if there's no
    /// data for it yet.
    @ViewBuilder
    private func row(for kind: HomeRowKind) -> some View {
        switch kind {
        case .featured:
            if !featured.isEmpty {
                FeaturedHero(items: featured) { item in playingItem = item }
            }
        case .continueWatching:
            if !model.resume.isEmpty {
                MediaRail(title: "Continue Watching", items: model.resume, style: .landscape)
            }
        case .recentlyAdded:
            if !model.latest.isEmpty {
                MediaRail(title: "Recently Added", items: model.latest, style: .poster)
            }
        case .libraries:
            if !model.libraries.isEmpty {
                MediaRail(title: "Your Libraries", items: model.libraries, style: .poster)
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
