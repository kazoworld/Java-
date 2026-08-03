import SwiftUI

@Observable
@MainActor
final class MusicSearchViewModel {
    var query = ""
    var albums: [MediaItem] = []
    var artists: [MediaItem] = []
    var songs: [MediaItem] = []
    var isSearching = false

    var isEmpty: Bool { albums.isEmpty && artists.isEmpty && songs.isEmpty }

    private var task: Task<Void, Never>?

    /// Debounced so typing doesn't fire a request per keystroke.
    func search(source: MusicSource) {
        task?.cancel()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else {
            albums = []; artists = []; songs = []; isSearching = false
            return
        }
        isSearching = true
        task = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            let results = (try? await source.searchMusic(query: term)) ?? []
            guard !Task.isCancelled else { return }
            albums = results.filter { $0.type == .musicAlbum || $0.type == .playlist }
            artists = results.filter { $0.type == .musicArtist }
            songs = results.filter { $0.type == .audio }
            isSearching = false
        }
    }
}

/// Music mode's search: albums, artists and songs from whichever backend is
/// active. Separate from the media Search tab, which only looks at movies/shows.
struct MusicSearchView: View {
    @Environment(AppState.self) private var appState
    @State private var model = MusicSearchViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                if model.isSearching && model.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xxl)
                } else if model.isEmpty {
                    emptyState
                } else {
                    if !model.albums.isEmpty {
                        rail(title: "Albums", items: model.albums)
                    }
                    if !model.artists.isEmpty {
                        artistRail
                    }
                    if !model.songs.isEmpty {
                        songSection
                    }
                }
            }
            .padding(.vertical, Spacing.lg)
        }
        .musicCanvas()
        #if os(iOS)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $model.query, prompt: "Albums, artists, songs")
        .adaptsChromeOnScroll()
        #else
        .searchable(text: $model.query, prompt: "Albums, artists, songs")
        #endif
        .navigationDestination(for: MediaItem.self) { item in
            switch item.type {
            case .musicArtist: ArtistDetailView(artist: item)
            default: AlbumDetailView(container: item)
            }
        }
        .onChange(of: model.query) { _, _ in
            guard let source = appState.musicSource else { return }
            model.search(source: source)
        }
    }

    private func rail(title: String, items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(sectionFont)
                .foregroundStyle(UltrafinColors.primaryText)
                .padding(.horizontal, edgePadding)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: railSpacing) {
                    ForEach(items) { album in
                        NavigationLink(value: album) { AlbumCard(album: album) }
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
                        NavigationLink(value: artist) { ArtistCard(artist: artist) }
                            .buttonStyle(UltrafinButtonStyle(focusScale: 1.1, lift: false))
                    }
                }
                .padding(.horizontal, edgePadding)
                .padding(.vertical, focusInset)
            }
            .scrollClipDisabled()
        }
    }

    private var songSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Songs")
                .font(sectionFont)
                .foregroundStyle(UltrafinColors.primaryText)
                .padding(.horizontal, edgePadding)
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
            .padding(.horizontal, edgePadding)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(UltrafinColors.tertiaryText)
            Text(model.query.isEmpty ? "Search your music" : "Nothing found")
                .font(Typography.sectionTitle)
                .foregroundStyle(UltrafinColors.primaryText)
            Text(model.query.isEmpty
                 ? "Find albums, artists and songs across your library."
                 : "Try a different spelling or a shorter phrase.")
                .font(Typography.body)
                .foregroundStyle(UltrafinColors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xxl * 2)
        .padding(.horizontal, edgePadding)
    }

    // MARK: - Metrics

    private var sectionFont: Font {
        #if os(tvOS)
        .system(size: 30, weight: .bold, design: .rounded)
        #else
        Typography.sectionTitle
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
