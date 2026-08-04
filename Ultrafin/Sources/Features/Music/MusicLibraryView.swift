import SwiftUI

/// The sections a music library drills into, mirroring Apple Music's Library
/// tab. Hashable so it can drive `navigationDestination`.
enum MusicLibrarySection: String, CaseIterable, Identifiable, Hashable {
    case playlists, artists, albums, songs, downloaded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playlists: "Playlists"
        case .artists: "Artists"
        case .albums: "Albums"
        case .songs: "Songs"
        case .downloaded: "Downloaded"
        }
    }

    var systemImage: String {
        switch self {
        case .playlists: "music.note.list"
        case .artists: "music.mic"
        case .albums: "square.stack"
        case .songs: "music.note"
        case .downloaded: "arrow.down.circle"
        }
    }
}

@Observable
@MainActor
final class MusicLibraryViewModel {
    var playlists: [MediaItem] = []
    var artists: [MediaItem] = []
    var albums: [MediaItem] = []
    var songs: [MediaItem] = []
    var recentlyAdded: [MediaItem] = []
    var isLoading = true
    private var loadedKind: MusicSourceKind?

    /// Real albums only, for the **Albums** section — a short release is a
    /// single or an EP filed under its parent album's name, and putting those on
    /// an album shelf is what made it impossible to tell what you actually own.
    ///
    /// Recently Added deliberately does NOT use this. "What did I just add" is a
    /// different question from "what albums do I have", and answering it with
    /// only full-length records leaves the shelf empty for anyone whose library
    /// grows a single at a time.
    private func realAlbums(_ items: [MediaItem]) -> [MediaItem] {
        // No reported count means unknown, and unknown stays — see MediaItem.
        items.filter { $0.releaseKind?.isAlbum ?? true }
    }

    func load(source: MusicSource) async {
        if loadedKind != source.kind {
            playlists = []; artists = []; albums = []; songs = []; recentlyAdded = []
        }
        isLoading = true
        defer { isLoading = false; loadedKind = source.kind }

        async let playlistTask = try? source.playlists()
        async let artistTask = try? source.artists()
        async let albumTask = try? source.allAlbums()
        async let recentTask = try? source.recentAlbums()
        async let songTask = try? source.allSongs()

        if let v = await playlistTask { playlists = v }
        if let v = await artistTask { artists = v }
        if let v = await albumTask { albums = realAlbums(v) }
        // Everything newly added, whatever length — the card says which is which.
        if let v = await recentTask { recentlyAdded = v }
        if let v = await songTask { songs = v }
    }
}

/// Music mode's Library: the section rows Apple Music opens with, then a
/// Recently Added grid beneath.
struct MusicLibraryView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @State private var model = MusicLibraryViewModel()

    private var sections: [MusicLibrarySection] {
        MusicLibraryCache.isSupported
            ? MusicLibrarySection.allCases
            : MusicLibrarySection.allCases.filter { $0 != .downloaded }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: Spacing.md),
         GridItem(.flexible(), spacing: Spacing.md)]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    NavigationLink(value: section) {
                        sectionRow(section)
                    }
                    .buttonStyle(.plain)
                    if section != sections.last {
                        Divider()
                            .overlay(UltrafinColors.separator)
                            .padding(.leading, 54)
                    }
                }

                if !model.recentlyAdded.isEmpty {
                    Text("Recently Added")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(UltrafinColors.primaryText)
                        .padding(.top, Spacing.xxl)
                        .padding(.bottom, Spacing.md)

                    LazyVGrid(columns: gridColumns, spacing: Spacing.lg) {
                        ForEach(model.recentlyAdded) { album in
                            NavigationLink(value: album) {
                                GridAlbumCard(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if model.isLoading && model.recentlyAdded.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.xxl)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xxl * 2)
        }
        .musicCanvas()
        .navigationTitle("Library")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .adaptsChromeOnScroll()
        #endif
        .navigationDestination(for: MusicLibrarySection.self) { section in
            MusicSectionListView(section: section, model: model)
        }
        .navigationDestination(for: MediaItem.self) { item in
            switch item.type {
            case .musicArtist: ArtistDetailView(artist: item)
            default: AlbumDetailView(container: item)
            }
        }
        .task(id: settings.musicSource) {
            guard let source = appState.musicSource else { return }
            await model.load(source: source)
        }
    }

    private func sectionRow(_ section: MusicLibrarySection) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: section.systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(settings.theme.accent.color)
                .frame(width: 30)
            Text(section.title)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(UltrafinColors.primaryText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(UltrafinColors.tertiaryText)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

/// One section's contents: a grid for releases and artists, a list for songs.
struct MusicSectionListView: View {
    @Environment(AppState.self) private var appState
    let section: MusicLibrarySection
    @Bindable var model: MusicLibraryViewModel

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: Spacing.md),
         GridItem(.flexible(), spacing: Spacing.md)]
    }

    var body: some View {
        Group {
            switch section {
            case .downloaded:
                #if os(iOS)
                DownloadedMusicView()
                #else
                EmptyView()
                #endif
            case .songs:
                songList
            case .playlists:
                grid(model.playlists)
            case .artists:
                artistGrid
            case .albums:
                grid(model.albums)
            }
        }
        .musicCanvas()
        #if os(iOS)
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .tvPopsOnMenu()
    }

    private func grid(_ items: [MediaItem]) -> some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: Spacing.lg) {
                ForEach(items) { item in
                    NavigationLink(value: item) { GridAlbumCard(album: item) }
                        .buttonStyle(.plain)
                }
            }
            .padding(Spacing.lg)
        }
    }

    private var artistGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: Spacing.lg) {
                ForEach(model.artists) { artist in
                    NavigationLink(value: artist) { ArtistCard(artist: artist) }
                        .buttonStyle(.plain)
                }
            }
            .padding(Spacing.lg)
        }
    }

    private var songList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.songs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        guard let source = appState.musicSource else { return }
                        Haptics.play(.selection)
                        MusicPlayer.shared.play(tracks: model.songs, startAt: index, source: source)
                    } label: {
                        TrackRow(track: song, position: index + 1,
                                 isCurrent: MusicPlayer.shared.currentTrack?.id == song.id,
                                 showsArt: true)
                    }
                    .buttonStyle(UltrafinButtonStyle(focusScale: 1.01, lift: false))
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
    }
}

/// A grid tile: square cover, title with explicit badge, artist beneath —
/// the Recently Added card from Apple Music's Library.
struct GridAlbumCard: View {
    @Environment(AppState.self) private var appState
    let album: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(RemoteImage(url: artURL, contentMode: .fill))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack(spacing: 4) {
                Text(album.name)
                    .font(.system(size: 14))
                    .foregroundStyle(UltrafinColors.primaryText)
                    .lineLimit(1)
                if album.isExplicit { ExplicitBadge(size: 12) }
            }
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(UltrafinColors.secondaryText)
                .lineLimit(1)
        }
    }

    /// Artist normally; "Single · Artist" or "EP · Artist" when the release is
    /// too short to be a full record. Recently Added mixes all three, so the
    /// card has to say which one you're looking at.
    private var subtitle: String {
        let base = album.artistText ?? album.productionYear.map(String.init)
        guard let kind = album.releaseKind, !kind.isAlbum else { return base ?? " " }
        return base.map { "\(kind.label) · \($0)" } ?? kind.label
    }

    private var artURL: URL? {
        appState.musicSource?.artworkURL(for: album, maxWidth: 500)
    }
}
