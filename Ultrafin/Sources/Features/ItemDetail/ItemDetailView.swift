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

    private var session: UserSession? {
        if case .authenticated(let s) = appState.phase { return s }
        return nil
    }

    private var displayed: MediaItem { detail ?? item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                hero
                content
            }
            .padding(.bottom, Spacing.xxl)
        }
        .ignoresSafeArea(edges: .top)
        .background(AmbientBackground())
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .fullScreenCoverCompat(isPresented: $presentPlayer) {
            if let session {
                VideoPlayerView(item: displayed, userID: session.userID)
            }
        }
    }

    private func tint(_ c: ArtworkColor?) -> Color { c?.color ?? Color.white.opacity(0.9) }
    private func playTextColor(_ c: ArtworkColor?) -> Color { (c?.isDark ?? false) ? .white : .black }

    private func load() async {
        guard let session, let client = appState.client else { return }
        async let detailTask = try? client.itemDetail(item.id, userID: session.userID)
        async let similarTask = try? client.similarItems(itemID: item.id, userID: session.userID)
        detail = await detailTask ?? nil
        similar = await similarTask ?? []
        isFavorite = displayed.userData?.isFavorite ?? false
        isWatched = displayed.userData?.played ?? false
    }

    // MARK: - Hero

    private var hero: some View {
        DetailHero(backdropURL: backdropURL,
                   colorURL: colorURL,
                   logoURL: logoURL(displayed),
                   title: displayed.name,
                   height: heroHeight,
                   edgePadding: edgePadding,
                   titleSize: titleSize,
                   logoMaxWidth: logoMaxWidth,
                   logoMaxHeight: logoMaxHeight) { art in
            VStack(alignment: .leading, spacing: Spacing.md) {
                DetailBadges(item: displayed, onDark: true)
                heroActions(art)
            }
        }
    }

    private func heroActions(_ art: ArtworkColor?) -> some View {
        HStack(spacing: Spacing.xl) {
            Button { presentPlayer = true } label: {
                Label(playButtonTitle, systemImage: "play.fill")
                    .font(.system(size: actionFont, weight: .bold, design: .rounded))
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.md)
                    .background(tint(art), in: Capsule())
                    .foregroundStyle(playTextColor(art))
            }
            .buttonStyle(UltrafinButtonStyle(focusScale: 1.06, lift: true))

            DetailActionButton(title: "My List",
                               systemImage: isFavorite ? "checkmark" : "plus",
                               active: isFavorite, onDark: true) { toggleFavorite() }
            DetailActionButton(title: "Watched",
                               systemImage: isWatched ? "eye.fill" : "eye",
                               active: isWatched, onDark: true) { toggleWatched() }
            Spacer()
        }
    }

    private func logoURL(_ item: MediaItem) -> URL? {
        guard let tag = item.imageTags?["Logo"] else { return nil }
        return appState.client?.imageURL(itemID: item.id, kind: .logo, tag: tag, maxWidth: 800)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if hasInfo {
                GlassInfoCard {
                    if let overview = displayed.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: overviewSize))
                            .foregroundStyle(UltrafinColors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    CastCrewView(item: displayed)
                }
            }

            if !similar.isEmpty {
                Text("More Like This")
                    .font(.system(size: titleSize * 0.5, weight: .bold, design: .rounded))
                    .foregroundStyle(UltrafinColors.primaryText)
                    .padding(.top, Spacing.xs)
                similarRail
            }
        }
        .padding(.horizontal, edgePadding)
        .padding(.top, Spacing.sm)
    }

    private var hasInfo: Bool {
        (displayed.overview?.isEmpty == false) || displayed.castText != nil || displayed.crewLine != nil
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
        guard let session, let client = appState.client else { return }
        Task { await client.setFavorite(itemID: item.id, userID: session.userID, isFavorite: value) }
    }

    private func toggleWatched() {
        isWatched.toggle()
        let value = isWatched
        guard let session, let client = appState.client else { return }
        Task { await client.setPlayed(itemID: item.id, userID: session.userID, isPlayed: value) }
    }

    private var playButtonTitle: String {
        if settings.playback.autoResume, let p = displayed.playbackProgress, p > 0.01, p < 0.95 {
            return "Resume"
        }
        return "Play"
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

// MARK: - Cross-platform full-screen presentation

extension View {
    /// `fullScreenCover` exists on iOS/tvOS; this wrapper keeps call sites tidy.
    @ViewBuilder
    func fullScreenCoverCompat<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        self.fullScreenCover(isPresented: isPresented, content: content)
    }
}
