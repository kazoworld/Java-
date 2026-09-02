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
        // Skeletons only on the FIRST load — a pull-to-refresh must never blank
        // the rows it's refreshing (swapping the content mid-drag also cancels
        // the refresh task's own requests).
        if !didLoad { isLoading = true }
        errorMessage = nil
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
        // Replace, never clobber: a failed/cancelled fetch keeps what's on screen.
        if let v = await resumeTask { resume = v }
        if let v = await latestTask { latest = v }
        if let v = await viewsTask { libraries = v }
        if let v = await comingTask { comingUp = v }
        if let v = await showsTask { recentShows = v }
        if let v = await favTask { favorites = v }
        if let v = await gemsTask { hiddenGems = v }
        if let v = await shuffledTask { shuffled = v }

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

    /// Light refresh after playback ends: just the rows whose watch state moved
    /// (Continue Watching / Next Up), with no loading skeletons.
    func refreshContinueWatching(client: JellyfinClient, userID: String) async {
        async let resumeTask = try? client.resumeItems(userID: userID)
        async let comingTask = try? client.nextUp(userID: userID)
        if let fresh = await resumeTask { resume = fresh }
        if let fresh = await comingTask { comingUp = fresh }
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
    // Home Screen-style row rearranging (tvOS): the row being moved, and a
    // snapshot of the order to restore if the user backs out.
    @State private var editingRow: HomeRowKind?
    @State private var preEditRows: [HomeRowConfig]?
    #if os(tvOS)
    @FocusState private var reorderFocused: Bool
    #endif

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
      ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                if model.isLoading {
                    loadingRows
                        .transition(.opacity)
                } else {
                    // Rows render in the user's configured order, skipping any
                    // they've disabled or that have no content. They settle in
                    // with a gentle staggered reveal on first load (one-time,
                    // change-driven — no continuous animation cost).
                    ForEach(Array(settings.homeLayout.rows.enumerated()), id: \.element.id) { idx, config in
                        if config.isEnabled {
                            row(for: config.kind)
                                .id(config.kind)
                                // A fade, with no rise. The rows used to slide up
                                // 18 points as they appeared, which on top of the
                                // skeleton's own mismatch read as the whole page
                                // lurching upward.
                                .opacity(revealed ? 1 : 0)
                                .animation(.smooth(duration: 0.5).delay(Double(idx) * 0.06), value: revealed)
                                // Dim every row except the one being rearranged.
                                .opacity(editingRow == nil || editingRow == config.kind ? 1 : 0.28)
                                .animation(.smooth(duration: 0.3), value: editingRow)
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
            .animation(.smooth(duration: 0.45), value: model.isLoading)
        }
        // Full-bleed so the hero media bar reaches every edge; rails self-pad
        // to stay within the tvOS title-safe area.
        .ignoresSafeArea()
        .background(AmbientBackground(tint: heroTint))
        #if os(iOS)
        // On iPhone the avatar lives in the nav bar; on tvOS the profile is a
        // real tab in the top row instead (a floating overlay was unreachable
        // for the focus engine).
        .toolbar { ToolbarItem(placement: .topBarTrailing) { profileButton } }
        .fullScreenCoverCompat(isPresented: $showProfiles) {
            ProfileSwitcherView()
        }
        #endif
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
        // Coming back from playback: quietly refresh Continue Watching / Next Up
        // so the row shows the position the session just reported.
        .onChange(of: playingItem?.id) { _, current in
            guard current == nil, let session, let client = appState.client else { return }
            Task { await model.refreshContinueWatching(client: client, userID: session.userID) }
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
        // While rearranging, the content is inert (disabled first) and an
        // invisible capture layer on top owns the remote.
        .disabled(editingRow != nil)
        .overlay { reorderCaptureLayer(proxy: proxy) }
      }
    }

    // MARK: - Row rearranging (tvOS)

    /// The invisible modal that drives rearranging: it holds focus, moves the
    /// row on up/down, commits on Select, and cancels on Menu.
    @ViewBuilder
    private func reorderCaptureLayer(proxy: ScrollViewProxy) -> some View {
        #if os(tvOS)
        if let kind = editingRow {
            ZStack(alignment: .top) {
                Button { commitReorder(proxy: proxy) } label: { Color.clear }
                    .buttonStyle(.plain)
                    .focused($reorderFocused)
                    .onMoveCommand { direction in
                        switch direction {
                        case .up:   moveEditing(kind, up: true, proxy: proxy)
                        case .down: moveEditing(kind, up: false, proxy: proxy)
                        default: break
                        }
                    }
                    .onExitCommand { cancelReorder(proxy: proxy) }

                reorderBanner
                    .padding(.top, 40)
            }
            .ignoresSafeArea()
            .onAppear { reorderFocused = true }
        }
        #endif
    }

    private var reorderBanner: some View {
        HStack(spacing: Spacing.lg) {
            Label("Move Row", systemImage: "arrow.up.arrow.down")
                .foregroundStyle(settings.accent)
            Text("Select to save")
            Text("Menu to cancel")
                .foregroundStyle(UltrafinColors.secondaryText)
        }
        .font(.system(size: 22, weight: .semibold, design: .rounded))
        .foregroundStyle(UltrafinColors.primaryText)
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .glassCapsule(dim: 0.12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func beginReorder(_ kind: HomeRowKind) {
        guard editingRow == nil, kind != .featured else { return }
        preEditRows = settings.homeLayout.rows
        withAnimation(.smooth(duration: 0.3)) { editingRow = kind }
    }

    private func moveEditing(_ kind: HomeRowKind, up: Bool, proxy: ScrollViewProxy) {
        withAnimation(.smooth(duration: 0.3)) {
            // Hop over rows that aren't on screen (disabled or empty) so every
            // press moves the row past something the user can actually see.
            settings.moveHomeRow(kind, up: up, isVisible: { k in
                (settings.homeLayout.rows.first(where: { $0.kind == k })?.isEnabled ?? true)
                    && rowHasContent(k)
            })
            proxy.scrollTo(kind, anchor: .center)
        }
    }

    /// Whether a row currently renders anything — mirrors `row(for:)`'s
    /// emptiness checks so reordering skips rows that aren't visible.
    private func rowHasContent(_ kind: HomeRowKind) -> Bool {
        switch kind {
        case .featured: return !featured.isEmpty
        case .continueWatching: return !continueWatching.isEmpty
        case .comingUp: return false
        case .recentlyAdded: return !visible(model.latest).isEmpty
        case .recentShows: return !visible(model.recentShows).isEmpty
        case .favorites: return !model.favorites.isEmpty
        case .hiddenGems: return !visible(model.hiddenGems).isEmpty
        case .libraries: return !model.libraries.isEmpty
        }
    }

    private func commitReorder(proxy: ScrollViewProxy) {
        // The new order is already persisted (moveHomeRow writes through).
        let kind = editingRow
        preEditRows = nil
        withAnimation(.smooth(duration: 0.3)) {
            editingRow = nil
            // Keep the settled row centered so focus lands back near it.
            if let kind { proxy.scrollTo(kind, anchor: .center) }
        }
    }

    private func cancelReorder(proxy: ScrollViewProxy) {
        let kind = editingRow
        if let snapshot = preEditRows { settings.homeLayout.rows = snapshot }
        preEditRows = nil
        withAnimation(.smooth(duration: 0.3)) {
            editingRow = nil
            // The row snapped back to its old spot — follow it there.
            if let kind { proxy.scrollTo(kind, anchor: .center) }
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

    /// A Home rail wired for rearranging — holding Select on a card lifts this
    /// row (tvOS).
    private func rail(_ title: String, _ items: [MediaItem],
                      style: MediaRail.Style, kind: HomeRowKind) -> some View {
        MediaRail(title: title, items: items, style: style,
                  reorderable: true,
                  isReordering: editingRow == kind,
                  onBeginReorder: { beginReorder(kind) })
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
                rail("Continue Watching", continueWatching, style: .landscape, kind: kind)
            }
        case .comingUp:
            // Folded into Continue Watching — no standalone row.
            EmptyView()
        case .recentlyAdded:
            let items = visible(model.latest)
            if !items.isEmpty {
                rail("Recently Added", items, style: .poster, kind: kind)
            }
        case .recentShows:
            let items = visible(model.recentShows)
            if !items.isEmpty {
                rail("Recently Added TV Shows", items, style: .poster, kind: kind)
            }
        case .favorites:
            // Favorites are intentional — never filtered.
            if !model.favorites.isEmpty {
                rail("Favorites", model.favorites, style: .poster, kind: kind)
            }
        case .hiddenGems:
            let items = visible(model.hiddenGems)
            if !items.isEmpty {
                rail("Hidden Gems", items, style: .poster, kind: kind)
            }
        case .libraries:
            if !model.libraries.isEmpty {
                // Libraries read as wide banners (their art is landscape and the
                // names need room), not tall posters.
                rail("Your Libraries", model.libraries, style: .landscape, kind: kind)
            }
        }
    }

    /// The loading state, shaped like the page it stands in for: the hero's
    /// full-bleed block first, then rails.
    ///
    /// It used to be two bare rails starting at the very top of the screen. The
    /// page is full-bleed so the hero can reach the edges, which meant the
    /// skeleton's first row sat under the status bar and behind the large title
    /// — and then everything appeared to leap downwards as the real hero claimed
    /// its space. Reserving the hero's exact height is what removes the jump.
    private var loadingRows: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            RoundedRectangle(cornerRadius: 0)
                .fill(UltrafinColors.elevatedSurface)
                .frame(height: FeaturedHero.height)
                .shimmer()

            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Spacing.md) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(UltrafinColors.elevatedSurface)
                        .frame(width: 180, height: 22)
                        .shimmer()
                        // Line the heading up with the rails' own inset instead
                        // of letting it sit flush against the screen edge.
                        .padding(.leading, Spacing.lg)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.md) {
                            ForEach(0..<5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: Spacing.posterCornerRadius)
                                    .fill(UltrafinColors.elevatedSurface)
                                    .frame(width: posterSkeleton.width, height: posterSkeleton.height)
                                    .shimmer()
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                    }
                    .scrollDisabled(true)
                }
            }
        }
    }

    private var posterSkeleton: CGSize {
        #if os(tvOS)
        CGSize(width: 240, height: 360)
        #else
        CGSize(width: 130, height: 195)
        #endif
    }
}
