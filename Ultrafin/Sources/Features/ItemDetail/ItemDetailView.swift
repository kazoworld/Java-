import SwiftUI

/// Rich, Netflix-style detail screen for a movie (or any single playable item):
/// backdrop, metadata badges, a prominent Play button, My List / Watched
/// actions, synopsis with cast, and a "More Like This" rail.
struct ItemDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    let item: MediaItem

    @State private var detail: MediaItem?
    @State private var similar: [MediaItem] = []
    @State private var isFavorite = false
    @State private var isWatched = false
    @State private var presentPlayer = false
    @State private var resumePlayback = true
    @State private var showEpisodes = false
    @State private var toast: String?
    @State private var artColor: ArtworkColor?
    /// Drives the one-time arrival animation (art settles in, content rises).
    @State private var appeared = false
    /// Theater mode + theme music for this page.
    @State private var theater = TheaterController()

    private var session: UserSession? {
        if case .authenticated(let s) = appState.phase { return s }
        return nil
    }

    private var displayed: MediaItem { detail ?? item }

    var body: some View {
        GeometryReader { screen in
            let landscape = screen.size.width >= screen.size.height * 1.2
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection(landscape: landscape, screen: screen.size)
                    belowSection
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load(); await startAmbiance() }
        .task(id: colorURL) { artColor = await ImageColor.vibrant(from: colorURL) }
        .onAppear { appeared = true }
        .onDisappear { theater.stop() }
        .onChange(of: presentPlayer) { _, showing in
            if showing { theater.stop() }
        }
        .fullScreenCoverCompat(isPresented: $presentPlayer) {
            if let session {
                VideoPlayerView(item: displayed, userID: session.userID, resume: resumePlayback)
            }
        }
        // Coming back from playback: re-pull the detail so Resume/Restart and
        // the progress bar reflect where you actually left off.
        .onChange(of: presentPlayer) { _, showing in
            if !showing { Task { await load() } }
        }
        .fullScreenCoverCompat(isPresented: $showEpisodes) {
            SeasonEpisodesView(episode: displayed)
        }
        .toast($toast)
    }

    /// Theater mode: quietly roll a highlight of the movie behind the art
    /// (muted); theme music hums underneath when the server has one. Both obey
    /// the corner volume button.
    private func startAmbiance() async {
        guard theater.isIdle, !presentPlayer, let client = appState.client else { return }
        if settings.themeMusic, let themeURL = await client.themeSongURL(itemID: displayed.id) {
            theater.startTheme(url: themeURL)
        }
        guard settings.theaterMode,
              displayed.type == .movie || displayed.type == .episode,
              let url = await client.previewStreamURL(itemID: displayed.id) else { return }
        theater.startVideo(url: url, startAt: highlightOffset(for: displayed))
    }

    /// Where the highlight starts: past the studio logos, well before spoilers.
    private func highlightOffset(for item: MediaItem) -> Double {
        guard let ticks = item.runTimeTicks, ticks > 0 else { return 120 }
        let runtime = Double(ticks) / 10_000_000
        return min(max(runtime * 0.15, 60), 480)
    }

    private func load() async {
        guard let session, let client = appState.client else { return }
        async let detailTask = try? client.itemDetail(item.id, userID: session.userID)
        async let similarTask = try? client.similarItems(itemID: item.id, userID: session.userID)
        detail = await detailTask ?? nil
        similar = await similarTask ?? []
        isFavorite = displayed.userData?.isFavorite ?? false
        isWatched = displayed.userData?.played ?? false
    }

    // MARK: - Hero (Netflix-style art + content column)

    private func heroSection(landscape: Bool, screen: CGSize) -> some View {
        ZStack(alignment: landscape ? .leading : .bottomLeading) {
            DetailArtBackdrop(backdropURL: backdropURL, artColor: artColor, landscape: landscape,
                              previewView: theater.layerView, previewActive: theater.videoActive)
                // Art settles in from a slight zoom — a gentle Ken-Burns arrival.
                .scaleEffect(appeared ? 1 : 1.06)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.7), value: appeared)

            contentColumn
                .frame(maxWidth: landscape ? screen.width * 0.52 : .infinity, alignment: .leading)
                .padding(.horizontal, edgePadding)
                .padding(.bottom, landscape ? 0 : Spacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: landscape ? .leading : .bottom)
                // Content rises and fades in just behind the art.
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 24)
                .animation(.smooth(duration: 0.55).delay(0.12), value: appeared)
        }
        .frame(height: landscape ? screen.height : screen.height * 0.74)
        // Theater/theme volume toggle — muted by default, tucked in the corner.
        .overlay(alignment: .bottomTrailing) {
            if theater.videoActive || theater.hasAudio {
                TheaterVolumeButton(controller: theater)
                    .padding(edgePadding)
                    .transition(.opacity)
            }
        }
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            TitleLogo(logoURL: logoURL(displayed), title: displayed.name,
                      fallbackFont: .system(size: titleSize, weight: .heavy, design: .rounded),
                      fallbackColor: .white, maxWidth: logoMaxWidth, maxHeight: logoMaxHeight)
                .shadow(color: .black.opacity(0.6), radius: 14, y: 4)

            DetailBadges(item: displayed, onDark: true)

            if let overview = displayed.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: overviewSize))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
            }

            CastCrewView(item: displayed, onDark: true)

            actionRows
                .padding(.top, Spacing.xs)
        }
    }

    private var actionRows: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let p = displayed.playbackProgress, p > 0.01, p < 0.95 {
                DetailActionRow(icon: "play.fill", title: "Resume", progress: p, prominent: true) {
                    Haptics.play(.medium); resumePlayback = true; presentPlayer = true
                }
                DetailActionRow(icon: "arrow.counterclockwise", title: "Restart") {
                    Haptics.play(.medium); resumePlayback = false; presentPlayer = true
                }
            } else {
                DetailActionRow(icon: "play.fill", title: "Play", prominent: true) {
                    Haptics.play(.medium); resumePlayback = true; presentPlayer = true
                }
            }
            if displayed.type == .episode {
                DetailActionRow(icon: "rectangle.stack.fill", title: "More Episodes") {
                    showEpisodes = true
                }
            }
            DetailActionRow(icon: isFavorite ? "checkmark" : "plus",
                            title: isFavorite ? "In My List" : "Add to My List") { toggleFavorite() }
            DetailActionRow(icon: isWatched ? "eye.fill" : "eye",
                            title: isWatched ? "Watched" : "Mark as Watched") { toggleWatched() }
        }
        .frame(maxWidth: actionMaxWidth)
    }

    private func logoURL(_ item: MediaItem) -> URL? {
        guard let tag = item.imageTags?["Logo"] else { return nil }
        return appState.client?.imageURL(itemID: item.id, kind: .logo, tag: tag, maxWidth: 800)
    }

    // MARK: - Below the fold

    @ViewBuilder
    private var belowSection: some View {
        let people = displayed.people ?? []
        if !people.isEmpty || !similar.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if !people.isEmpty {
                    CastRow(people: people)
                }
                if !similar.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("More Like This")
                            .font(.system(size: titleSize * 0.5, weight: .bold, design: .rounded))
                            .foregroundStyle(UltrafinColors.primaryText)
                        similarRail
                    }
                }
            }
            .padding(.horizontal, edgePadding)
            .padding(.top, Spacing.lg)
        }
    }

    private var similarRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.lg) {
                ForEach(similar) { item in
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

    // MARK: - Actions

    private func toggleFavorite() {
        isFavorite.toggle()
        let value = isFavorite
        Haptics.play(.success)
        toast = value ? "Added to My List" : "Removed from My List"
        guard let session, let client = appState.client else { return }
        Task { await client.setFavorite(itemID: item.id, userID: session.userID, isFavorite: value) }
    }

    private func toggleWatched() {
        isWatched.toggle()
        let value = isWatched
        Haptics.play(.success)
        toast = value ? "Marked as Watched" : "Marked as Unwatched"
        guard let session, let client = appState.client else { return }
        Task { await client.setPlayed(itemID: item.id, userID: session.userID, isPlayed: value) }
    }

    private var backdropURL: URL? {
        let tag = displayed.backdropImageTags?.first ?? displayed.imageTags?["Primary"]
        let kind: JellyfinClient.ImageKind = displayed.backdropImageTags?.isEmpty == false ? .backdrop : .primary
        return appState.client?.imageURL(itemID: displayed.id, kind: kind, tag: tag, maxWidth: 1280)
    }

    /// Tiny image for color sampling only.
    private var colorURL: URL? {
        let tag = displayed.backdropImageTags?.first ?? displayed.imageTags?["Primary"]
        let kind: JellyfinClient.ImageKind = displayed.backdropImageTags?.isEmpty == false ? .backdrop : .primary
        return appState.client?.imageURL(itemID: displayed.id, kind: kind, tag: tag, maxWidth: 240)
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

// MARK: - Cross-platform full-screen presentation

extension View {
    /// `fullScreenCover` exists on iOS/tvOS; this wrapper keeps call sites tidy.
    @ViewBuilder
    func fullScreenCoverCompat<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        self.fullScreenCover(isPresented: isPresented, content: content)
    }
}
