import SwiftUI

#if os(iOS)
/// What's actually downloaded, grouped by release. The point of this screen is
/// to answer "do I have the album, or just one song off it?" at a glance — a
/// single reads as a single, and a partial album says exactly how partial.
struct DownloadedMusicView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    @State private var store = MusicLibraryCache.shared

    private var albums: [MusicLibraryCache.AlbumSummary] { store.downloadedAlbums() }

    var body: some View {
        Group {
            if albums.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(albums) { album in
                            row(album)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                remove(albums[index])
                            }
                        }
                    } footer: {
                        Text("Swipe a release to remove it. Partial albums show how many of their songs are here — tap one to finish the download from its album page.")
                    }
                }
                .glassRows()
                .scrollContentBackground(.hidden)
            }
        }
        .musicCanvas()
        .navigationTitle("Downloaded")
        .tint(settings.theme.accent.color)
    }

    private func row(_ album: MusicLibraryCache.AlbumSummary) -> some View {
        HStack(spacing: Spacing.md) {
            artwork(for: album)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(album.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(UltrafinColors.primaryText)
                    .lineLimit(1)
                if let artist = album.artist {
                    Text(artist)
                        .font(.system(size: 13))
                        .foregroundStyle(UltrafinColors.secondaryText)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    kindChip(album)
                    Text(StorageFormat.string(album.bytes))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(UltrafinColors.tertiaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// The badge that settles the question: Single, Album, or partway there.
    private func kindChip(_ album: MusicLibraryCache.AlbumSummary) -> some View {
        let complete = album.isSingle || album.isComplete
        return Text(album.subtitle)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(complete ? settings.theme.accent.color : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((complete ? settings.theme.accent.color : .orange).opacity(0.16),
                        in: Capsule())
    }

    @ViewBuilder
    private func artwork(for album: MusicLibraryCache.AlbumSummary) -> some View {
        // Reuse the cached cover via a stand-in item carrying the album id.
        if let source = appState.musicSource {
            let stand = MediaItem.music(id: album.albumID, name: album.title,
                                        type: .musicAlbum, albumID: album.albumID,
                                        coverArtID: album.albumID)
            RemoteImage(url: source.artworkURL(for: stand, maxWidth: 120))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(UltrafinColors.elevatedSurface)
        }
    }

    private func remove(_ album: MusicLibraryCache.AlbumSummary) {
        Haptics.play(.light)
        for entry in store.downloadedTracks(inAlbum: album.albumID) {
            store.remove(entry.trackID)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 44))
                .foregroundStyle(UltrafinColors.tertiaryText)
            Text("Nothing downloaded yet")
                .font(Typography.sectionTitle)
                .foregroundStyle(UltrafinColors.primaryText)
            Text("Download an album or a song and it shows up here, labelled so you always know whether you have the whole record.")
                .font(Typography.body)
                .foregroundStyle(UltrafinColors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xxl * 2)
    }
}
#endif
