import SwiftUI

@Observable
@MainActor
final class MusicHomeViewModel {
    var recentAlbums: [MediaItem] = []
    var allAlbums: [MediaItem] = []
    var artists: [MediaItem] = []
    var playlists: [MediaItem] = []
    var isLoading = true
    private(set) var didLoad = false
    /// Which backend the current lists came from — switching sources in
    /// Settings blanks and reloads instead of showing the other server's music.
    private var loadedKind: MusicSourceKind?

    var isEmpty: Bool {
        recentAlbums.isEmpty && allAlbums.isEmpty && artists.isEmpty && playlists.isEmpty
    }

    func load(source: MusicSource) async {
        if loadedKind != source.kind {
            didLoad = false
            recentAlbums = []; allAlbums = []; artists = []; playlists = []
        }
        if !didLoad { isLoading = true }
        defer { isLoading = false; didLoad = true; loadedKind = source.kind }
        async let recentTask = try? source.recentAlbums()
        async let albumsTask = try? source.allAlbums()
        async let artistsTask = try? source.artists()
        async let playlistsTask = try? source.playlists()
        if let v = await recentTask { recentAlbums = v }
        if let v = await albumsTask { allAlbums = v }
        if let v = await artistsTask { artists = v }
        if let v = await playlistsTask { playlists = v }
    }
}

/// The Music tab: your albums, artists and playlists, Apple Music-style.
struct MusicHomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @State private var model = MusicHomeViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xxl)
                } else if model.isEmpty {
                    emptyState
                } else {
                    shuffleHeader

                    if !model.recentAlbums.isEmpty {
                        albumRail(title: "Recently Added", albums: model.recentAlbums)
                    }
                    if !model.playlists.isEmpty {
                        albumRail(title: "Playlists", albums: model.playlists)
                    }
                    if !model.artists.isEmpty {
                        artistRail
                    }
                    if !model.allAlbums.isEmpty {
                        albumRail(title: "Albums", albums: model.allAlbums)
                    }
                }
            }
            .padding(.vertical, Spacing.lg)
        }
        .background(AmbientBackground())
        #if os(iOS)
        .navigationTitle("Music")
        #endif
        .navigationDestination(for: MediaItem.self) { item in
            switch item.type {
            case .musicAlbum, .playlist: AlbumDetailView(container: item)
            case .musicArtist: ArtistDetailView(artist: item)
            default: AlbumDetailView(container: item)
            }
        }
        // Re-runs when the user switches source in Settings, so the tab swaps
        // to the other server's library without an app restart.
        .task(id: settings.musicSource) {
            guard let source = appState.musicSource else { return }
            await model.load(source: source)
        }
    }

    /// "Shuffle Library" — the fastest way into the music.
    private var shuffleHeader: some View {
        Button {
            guard let source = appState.musicSource else { return }
            Haptics.play(.medium)
            Task {
                let songs = (try? await source.randomSongs()) ?? []
                guard !songs.isEmpty else { return }
                MusicPlayer.shared.play(tracks: songs, source: source)
            }
        } label: {
            Label("Shuffle Library", systemImage: "shuffle")
                .font(.system(size: shuffleFont, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
                .tintedGlassCapsule(settings.theme.accent.color, strength: 0.7)
                .shadow(color: settings.theme.accent.color.opacity(0.4), radius: 14, y: 6)
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.08, lift: true))
        .padding(.horizontal, edgePadding)
    }

    private func albumRail(title: String, albums: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(sectionFont)
                .foregroundStyle(UltrafinColors.primaryText)
                .padding(.horizontal, edgePadding)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: railSpacing) {
                    ForEach(albums) { album in
                        NavigationLink(value: album) {
                            AlbumCard(album: album)
                        }
                        .mediaCardButtonStyle()
                    }
                }
                .padding(.horizontal, edgePadding)
                .padding(.vertical, focusInset)
            }
            .scrollClipDisabled()
        }
    }

    private var artistRail: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Artists")
                .font(sectionFont)
                .foregroundStyle(UltrafinColors.primaryText)
                .padding(.horizontal, edgePadding)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: railSpacing) {
                    ForEach(model.artists) { artist in
                        NavigationLink(value: artist) {
                            ArtistCard(artist: artist)
                        }
                        .buttonStyle(UltrafinButtonStyle(focusScale: 1.1, lift: false))
                    }
                }
                .padding(.horizontal, edgePadding)
                .padding(.vertical, focusInset)
            }
            .scrollClipDisabled()
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(UltrafinColors.tertiaryText)
            Text("No music on this server")
                .font(Typography.sectionTitle)
                .foregroundStyle(UltrafinColors.primaryText)
            Text(settings.musicSource == .navidrome
                 ? "Your Navidrome server has no music yet — or check its link in Settings → Music."
                 : "Add a Music library in Jellyfin and it appears here.")
                .font(Typography.body)
                .foregroundStyle(UltrafinColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xxl * 2)
    }

    // MARK: - Metrics

    private var sectionFont: Font {
        #if os(tvOS)
        .system(size: 30, weight: .bold, design: .rounded)
        #else
        Typography.sectionTitle
        #endif
    }
    private var shuffleFont: CGFloat {
        #if os(tvOS)
        26
        #else
        16
        #endif
    }
    private var edgePadding: CGFloat {
        #if os(tvOS)
        56
        #else
        Spacing.lg
        #endif
    }
    private var railSpacing: CGFloat {
        #if os(tvOS)
        Spacing.xl
        #else
        Spacing.md
        #endif
    }
    private var focusInset: CGFloat {
        #if os(tvOS)
        Spacing.xl
        #else
        0
        #endif
    }
}

// MARK: - Cards

/// A square album (or playlist) tile with title + artist beneath.
struct AlbumCard: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @Environment(\.isFocused) private var isFocused

    let album: MediaItem

    private var side: CGFloat {
        #if os(tvOS)
        260
        #else
        150
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            RemoteImage(url: artURL)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous)
                        .strokeBorder(isFocused ? settings.theme.accent.color : UltrafinColors.separator,
                                      lineWidth: isFocused ? 3 : 1)
                )
                .shadow(color: isFocused ? settings.theme.accent.color.opacity(0.5) : .clear,
                        radius: isFocused ? 20 : 0, y: isFocused ? 6 : 0)
            Text(album.name)
                .font(titleFont)
                .foregroundStyle(isFocused ? UltrafinColors.primaryText : UltrafinColors.secondaryText)
                .lineLimit(1)
            Text(album.artistText ?? album.productionYear.map(String.init) ?? " ")
                .font(subtitleFont)
                .foregroundStyle(UltrafinColors.tertiaryText)
                .lineLimit(1)
        }
        .frame(width: side)
        .animation(.smooth(duration: 0.2), value: isFocused)
    }

    private var artURL: URL? {
        appState.musicSource?.artworkURL(for: album, maxWidth: Int(side * 2))
    }
    private var titleFont: Font {
        #if os(tvOS)
        .system(size: 22, weight: .semibold, design: .rounded)
        #else
        Typography.cardTitle
        #endif
    }
    private var subtitleFont: Font {
        #if os(tvOS)
        .system(size: 17, weight: .medium)
        #else
        Typography.caption
        #endif
    }
}

/// A circular artist tile.
struct ArtistCard: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @Environment(\.isFocused) private var isFocused

    let artist: MediaItem

    private var side: CGFloat {
        #if os(tvOS)
        200
        #else
        110
        #endif
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            RemoteImage(url: artURL)
                .frame(width: side, height: side)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(
                    isFocused ? settings.theme.accent.color : UltrafinColors.separator,
                    lineWidth: isFocused ? 3 : 1))
                .shadow(color: isFocused ? settings.theme.accent.color.opacity(0.5) : .clear,
                        radius: isFocused ? 18 : 0, y: isFocused ? 5 : 0)
            Text(artist.name)
                .font(nameFont)
                .foregroundStyle(isFocused ? UltrafinColors.primaryText : UltrafinColors.secondaryText)
                .lineLimit(1)
        }
        .frame(width: side + 20)
        .animation(.smooth(duration: 0.2), value: isFocused)
    }

    private var artURL: URL? {
        appState.musicSource?.artworkURL(for: artist, maxWidth: Int(side * 2))
    }
    private var nameFont: Font {
        #if os(tvOS)
        .system(size: 20, weight: .semibold, design: .rounded)
        #else
        .system(size: 14, weight: .semibold, design: .rounded)
        #endif
    }
}
