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
        RemoteImage(url: backdropURL)
            .frame(height: heroHeight)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(
                LinearGradient(colors: [.clear, .clear, UltrafinColors.background],
                               startPoint: .top, endPoint: .bottom)
            )
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(displayed.name)
                .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                .foregroundStyle(UltrafinColors.primaryText)
                .lineLimit(2)

            DetailBadges(item: displayed)

            playButton

            if let overview = displayed.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: overviewSize))
                    .foregroundStyle(UltrafinColors.secondaryText)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CastCrewView(item: displayed)

            actionRow

            if !similar.isEmpty {
                Text("More Like This")
                    .font(.system(size: titleSize * 0.5, weight: .bold, design: .rounded))
                    .foregroundStyle(UltrafinColors.primaryText)
                    .padding(.top, Spacing.md)
                similarRail
            }
        }
        .padding(.horizontal, edgePadding)
    }

    private var playButton: some View {
        Button { presentPlayer = true } label: {
            Label(playButtonTitle, systemImage: "play.fill")
                .font(.system(size: actionFont, weight: .bold, design: .rounded))
                .frame(maxWidth: 420)
                .padding(.vertical, Spacing.md)
                .background(settings.theme.accent.color, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.05, lift: true))
    }

    private var actionRow: some View {
        HStack(spacing: Spacing.xl) {
            DetailActionButton(title: "My List",
                               systemImage: isFavorite ? "checkmark" : "plus",
                               active: isFavorite) { toggleFavorite() }
            DetailActionButton(title: "Watched",
                               systemImage: isWatched ? "eye.fill" : "eye",
                               active: isWatched) { toggleWatched() }
            Spacer()
        }
        .padding(.top, Spacing.xs)
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
        return appState.client?.imageURL(itemID: displayed.id, kind: kind, tag: tag, maxWidth: 1920)
    }

    // MARK: - Metrics

    private var heroHeight: CGFloat {
        #if os(tvOS)
        540
        #else
        300
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
}

// MARK: - Cross-platform full-screen presentation

extension View {
    /// `fullScreenCover` exists on iOS/tvOS; this wrapper keeps call sites tidy.
    @ViewBuilder
    func fullScreenCoverCompat<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        self.fullScreenCover(isPresented: isPresented, content: content)
    }
}
