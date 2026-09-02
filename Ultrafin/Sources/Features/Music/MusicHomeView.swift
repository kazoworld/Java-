import SwiftUI

@Observable
@MainActor
final class MusicHomeViewModel {
    var recentAlbums: [MediaItem] = []
    var allAlbums: [MediaItem] = []
    var artists: [MediaItem] = []
    var playlists: [MediaItem] = []
    var heartedSongs: [MediaItem] = []
    /// Songs for the Up Next shelf when nothing is queued.
    var recentSongs: [MediaItem] = []
    /// Albums you've played lately, for the Recently Played shelf.
    var recentlyPlayedAlbums: [MediaItem] = []
    /// Up to four cover URLs per mix, for the playlist-style collage.
    var mixCovers: [String: [URL]] = [:]
    var isLoading = true
    private(set) var didLoad = false
    /// Which backend the current lists came from — switching sources in
    /// Settings blanks and reloads instead of showing the other server's music.
    private var loadedKind: MusicSourceKind?

    var isEmpty: Bool {
        recentAlbums.isEmpty && allAlbums.isEmpty && artists.isEmpty
            && playlists.isEmpty && heartedSongs.isEmpty
    }

    /// Only full-length releases belong on the album shelves — see
    /// `MediaItem.albumTrackThreshold`. A single song carries its parent album's
    /// name in its metadata, so the server happily creates a one-track "album"
    /// for it; that's what floods the shelf.
    ///
    /// Unknown counts (nil, or the 0 some servers send instead of a real figure)
    /// stay with the albums — filtering on a number we never really got is what
    /// emptied the shelves.
    private func isShortRelease(_ item: MediaItem) -> Bool {
        guard let kind = item.releaseKind else { return false }
        return !kind.isAlbum
    }

    private func fullAlbums(_ items: [MediaItem]) -> [MediaItem] {
        items.filter { !isShortRelease($0) }
    }

    /// The **Albums** shelf, and only that one. Recently Added shows everything
    /// new — a shelf answering "what did I just add" that hides half the answer
    /// is worse than no shelf, and for a library that grows a single at a time
    /// it was empty outright.
    var albumShelf: [MediaItem] { fullAlbums(allAlbums) }

    func load(source: MusicSource) async {
        if loadedKind != source.kind {
            didLoad = false
            recentAlbums = []; allAlbums = []; artists = []; playlists = []; heartedSongs = []
        }
        if !didLoad { isLoading = true }
        defer { isLoading = false; didLoad = true; loadedKind = source.kind }
        async let recentTask = try? source.recentAlbums()
        async let albumsTask = try? source.allAlbums()
        async let artistsTask = try? source.artists()
        async let playlistsTask = try? source.playlists()
        async let heartedTask = try? source.favoriteSongs()
        if let v = await recentTask { recentAlbums = v }
        if let v = await albumsTask { allAlbums = v }
        if let v = await artistsTask { artists = v }
        if let v = await playlistsTask { playlists = v }
        if let v = await heartedTask { heartedSongs = v }
        if let played = try? await source.recentlyPlayedSongs() {
            recentSongs = played
            // Collapse the recently-played songs into the albums they came from.
            var seen = Set<String>()
            recentlyPlayedAlbums = played.compactMap { song -> MediaItem? in
                guard let album = song.albumDestination,
                      seen.insert(album.id).inserted else { return nil }
                return album
            }
        }
        await loadMixCovers(source: source)
    }

    /// Peek at each mix's first few songs so its card can show real artwork.
    private func loadMixCovers(source: MusicSource) async {
        for mix in SmartMix.all {
            let songs = await mix.load(from: source)
            let urls = songs.prefix(4).compactMap { source.artworkURL(for: $0, maxWidth: 300) }
            mixCovers[mix.id] = urls
        }
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
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.xxl)
                        .transition(.opacity)
                } else if model.isEmpty {
                    emptyState
                } else {
                    madeForYou

                    if !upNextSongs.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            sectionHeader("Up Next")
                            UpNextSection(songs: upNextSongs)
                        }
                    }
                    if !model.recentlyPlayedAlbums.isEmpty {
                        albumRail(title: "Recently Played", albums: model.recentlyPlayedAlbums)
                    }
                    if !model.recentAlbums.isEmpty {
                        albumRail(title: "Recently Added", albums: model.recentAlbums)
                    }

                    if !model.albumShelf.isEmpty {
                        albumRail(title: "Albums", albums: model.albumShelf)
                    }
                    if !model.playlists.isEmpty {
                        albumRail(title: "Playlists", albums: model.playlists)
                    }
                    if !model.heartedSongs.isEmpty {
                        songRail(title: "Hearted Songs", songs: model.heartedSongs)
                    }
                    if !model.artists.isEmpty {
                        artistRail
                    }
                    identityBanner
                }
            }
            .padding(.vertical, Spacing.lg)
            // Cross-fade in rather than cutting: the shelves arrive together and
            // settle, instead of the spinner vanishing and content snapping in.
            .animation(.smooth(duration: 0.45), value: model.isLoading)
        }
        .musicCanvas()
        #if os(iOS)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .adaptsChromeOnScroll()
        #endif
        .navigationDestination(for: MediaItem.self) { item in
            Group {
                switch item.type {
                case .musicArtist: ArtistDetailView(artist: item)
                default: AlbumDetailView(container: item)
                }
            }
            .cardZoomDestination(item.id)
        }
        .navigationDestination(for: SmartMix.self) { mix in
            SmartMixDetailView(mix: mix)
                .cardZoomDestination(mix.id)
        }
        // Re-runs when the user switches source in Settings, so the tab swaps
        // to the other server's library without an app restart.
        .task(id: settings.musicSource) {
            guard let source = appState.musicSource else { return }
            await model.load(source: source)
        }
    }

    /// What's actually coming up: the rest of the play queue when there is one,
    /// otherwise the songs played most recently.
    private var upNextSongs: [MediaItem] {
        let queued = MusicPlayer.shared.upNext
        return queued.isEmpty ? model.recentSongs : queued
    }

    // MARK: - Made For You (smart mixes)

    /// A row of app-generated mixes drawn from the user's own listening — the
    /// "Made For You" shelf, Apple Music-style. Tapping a tile plays it.
    private var madeForYou: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Made For You")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: railSpacing) {
                    ForEach(SmartMix.all) { mix in
                        // Opens the mix so you can see what's in it first.
                        NavigationLink(value: mix) {
                            SmartMixCard(mix: mix, side: mixSide,
                                         covers: model.mixCovers[mix.id] ?? [])
                        }
                        .mediaCardButtonStyle()
                        .cardZoomSource(mix.id)
                    }
                }
                .padding(.horizontal, edgePadding)
                .padding(.vertical, focusInset)
            }
            .scrollClipDisabled()
        }
    }

    /// A shelf title with the Apple Music chevron beside it.
    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(sectionFont)
                .foregroundStyle(UltrafinColors.primaryText)
            Image(systemName: "chevron.right")
                .font(.system(size: chevronSize, weight: .bold))
                .foregroundStyle(UltrafinColors.tertiaryText)
        }
        .padding(.horizontal, edgePadding)
    }

    /// A tappable banner into the Music Identity screen.
    private var identityBanner: some View {
        NavigationLink {
            MusicIdentityView()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: identityIcon, weight: .semibold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Music Identity")
                        .font(.system(size: shuffleFont, weight: .bold))
                        .foregroundStyle(.white)
                    Text("See how you listen")
                        .font(.system(size: shuffleFont * 0.72, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: Spacing.sm)
                Image(systemName: "chevron.right")
                    .font(.system(size: shuffleFont * 0.8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .background {
                LinearGradient(colors: [Color(hex: 0x5B2A86), Color(hex: 0x24243E)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(LiquidGlass.rim(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.03, lift: true))
        .padding(.horizontal, edgePadding)
    }

    private func albumRail(title: String, albums: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader(title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: railSpacing) {
                    ForEach(albums) { album in
                        NavigationLink(value: album) {
                            AlbumCard(album: album)
                        }
                        .mediaCardButtonStyle()
                        .cardZoomSource(album.id)
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
            sectionHeader("Artists")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: railSpacing) {
                    ForEach(model.artists) { artist in
                        NavigationLink(value: artist) {
                            ArtistCard(artist: artist)
                        }
                        .buttonStyle(UltrafinButtonStyle(focusScale: 1.1, lift: false))
                        .cardZoomSource(artist.id)
                    }
                }
                .padding(.horizontal, edgePadding)
                .padding(.vertical, focusInset)
            }
            .scrollClipDisabled()
        }
    }

    /// A rail of individual songs (Hearted Songs) — tapping one starts the
    /// whole list playing from there.
    private func songRail(title: String, songs: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader(title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: railSpacing) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { position, song in
                        Button {
                            guard let source = appState.musicSource else { return }
                            Haptics.play(.selection)
                            MusicPlayer.shared.play(tracks: songs, startAt: position, source: source)
                        } label: {
                            SongCard(song: song)
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

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(UltrafinColors.tertiaryText)
            Text("No music on this server")
                .font(.system(size: 22, weight: .bold))
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
        .system(size: 32, weight: .bold)
        #else
        // Apple Music's shelf headers: SF Pro, bold, tight — not rounded.
        .system(size: 22, weight: .bold)
        #endif
    }
    private var shuffleFont: CGFloat {
        #if os(tvOS)
        26
        #else
        15
        #endif
    }
    /// Apple Music sets its phone margins at 16, not 20 — a small difference
    /// that shows up as noticeably more shelf visible per screen.
    private var edgePadding: CGFloat {
        #if os(tvOS)
        56
        #else
        16
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
    private var chevronSize: CGFloat {
        #if os(tvOS)
        22
        #else
        15
        #endif
    }
    private var mixSide: CGFloat {
        #if os(tvOS)
        300
        #else
        158
        #endif
    }
    private var identityIcon: CGFloat {
        #if os(tvOS)
        44
        #else
        30
        #endif
    }
}

// MARK: - Smart mix tile

/// A "Made For You" mix, presented as a playlist: a square cover built from the
/// songs actually in it (a four-up collage, like Apple Music's generated
/// playlists), with the title and description beneath — so it sits in the shelf
/// as a peer of the albums rather than as a differently-shaped tile.
struct SmartMixCard: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(SettingsStore.self) private var settings

    let mix: SmartMix
    let side: CGFloat
    /// Cover art for the first few songs in the mix, when they're known.
    let covers: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            cover
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous)
                        .strokeBorder(isFocused ? settings.accent : UltrafinColors.separator,
                                      lineWidth: isFocused ? 3 : 1)
                )
                .shadow(color: isFocused ? settings.accent.opacity(0.5) : .clear,
                        radius: isFocused ? 20 : 0, y: isFocused ? 6 : 0)

            Text(mix.title)
                .font(titleFont)
                .foregroundStyle(UltrafinColors.primaryText)
                .lineLimit(1)
            Text(mix.subtitle)
                .font(subtitleFont)
                .foregroundStyle(UltrafinColors.tertiaryText)
                .lineLimit(1)
        }
        .frame(width: side)
        .animation(.smooth(duration: 0.2), value: isFocused)
    }

    /// Four covers in a grid when we have them, else the mix's own colours.
    private var cover: some View {
        SmartMixArtwork(mix: mix, side: side, covers: covers)
    }

    private var titleFont: Font {
        #if os(tvOS)
        .system(size: 22, weight: .semibold)
        #else
        .system(size: 14, weight: .medium)
        #endif
    }
    private var subtitleFont: Font {
        #if os(tvOS)
        .system(size: 17, weight: .regular)
        #else
        .system(size: 14, weight: .regular)
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
        138
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            RemoteImage(url: artURL)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous)
                        .strokeBorder(isFocused ? settings.accent : UltrafinColors.separator,
                                      lineWidth: isFocused ? 3 : 1)
                )
                .shadow(color: isFocused ? settings.accent.opacity(0.5) : .clear,
                        radius: isFocused ? 20 : 0, y: isFocused ? 6 : 0)
            Text(album.name)
                .font(titleFont)
                .foregroundStyle(isFocused ? UltrafinColors.primaryText : UltrafinColors.secondaryText)
                .lineLimit(1)
            HStack(spacing: 5) {
                // A one-track release says "Single" so it never passes for a
                // full album on a shelf of covers.
                Text(albumSubtitle)
                    .font(subtitleFont)
                    .foregroundStyle(UltrafinColors.tertiaryText)
                    .lineLimit(1)
                if album.isExplicit {
                    Spacer(minLength: 0)
                    ExplicitBadge(size: side * 0.075)
                }
            }
        }
        .frame(width: side)
        .animation(.smooth(duration: 0.2), value: isFocused)
    }

    /// Artist normally; "Single · Artist" or "EP · Artist" when the release is
    /// too short to be a full record.
    private var albumSubtitle: String {
        let base = album.artistText ?? album.productionYear.map(String.init)
        guard let kind = album.releaseKind, !kind.isAlbum else { return base ?? " " }
        return base.map { "\(kind.label) · \($0)" } ?? kind.label
    }

    private var artURL: URL? {
        appState.musicSource?.artworkURL(for: album, maxWidth: Int(side * 2))
    }
    private var titleFont: Font {
        #if os(tvOS)
        .system(size: 22, weight: .semibold)
        #else
        // Apple Music card labels are quiet: regular weight, small, not rounded.
        .system(size: 14, weight: .regular)
        #endif
    }
    private var subtitleFont: Font {
        #if os(tvOS)
        .system(size: 17, weight: .regular)
        #else
        .system(size: 14, weight: .regular)
        #endif
    }
}

/// A square song tile: album art with title + artist beneath. Used by the
/// Hearted Songs rail.
struct SongCard: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @Environment(\.isFocused) private var isFocused

    let song: MediaItem

    private var side: CGFloat {
        #if os(tvOS)
        220
        #else
        120
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(url: artURL)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.posterCornerRadius, style: .continuous)
                            .strokeBorder(isFocused ? settings.accent : UltrafinColors.separator,
                                          lineWidth: isFocused ? 3 : 1)
                    )
                    .shadow(color: isFocused ? settings.accent.opacity(0.5) : .clear,
                            radius: isFocused ? 20 : 0, y: isFocused ? 6 : 0)
                // A little filled heart marks these as hearted.
                Image(systemName: "heart.fill")
                    .font(.system(size: heartSize, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(heartSize * 0.5)
                    .background(settings.accent.opacity(0.92), in: Circle())
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .padding(Spacing.sm)
            }
            Text(song.name)
                .font(titleFont)
                .foregroundStyle(isFocused ? UltrafinColors.primaryText : UltrafinColors.secondaryText)
                .lineLimit(1)
            HStack(spacing: 5) {
                Text(song.artistText ?? " ")
                    .font(subtitleFont)
                    .foregroundStyle(UltrafinColors.tertiaryText)
                    .lineLimit(1)
                if song.isExplicit {
                    Spacer(minLength: 0)
                    ExplicitBadge(size: side * 0.08)
                }
            }
        }
        .frame(width: side)
        .animation(.smooth(duration: 0.2), value: isFocused)
    }

    private var artURL: URL? {
        appState.musicSource?.artworkURL(for: song, maxWidth: Int(side * 2))
    }
    private var heartSize: CGFloat {
        #if os(tvOS)
        14
        #else
        10
        #endif
    }
    private var titleFont: Font {
        #if os(tvOS)
        .system(size: 22, weight: .semibold)
        #else
        // Apple Music card labels are quiet: regular weight, small, not rounded.
        .system(size: 14, weight: .regular)
        #endif
    }
    private var subtitleFont: Font {
        #if os(tvOS)
        .system(size: 17, weight: .regular)
        #else
        .system(size: 14, weight: .regular)
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
        102
        #endif
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            RemoteImage(url: artURL)
                .frame(width: side, height: side)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(
                    isFocused ? settings.accent : UltrafinColors.separator,
                    lineWidth: isFocused ? 3 : 1))
                .shadow(color: isFocused ? settings.accent.opacity(0.5) : .clear,
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
        .system(size: 20, weight: .semibold)
        #else
        .system(size: 14, weight: .regular)
        #endif
    }
}
