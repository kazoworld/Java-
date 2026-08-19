import SwiftUI

/// Apple Music's "Up Next" shelf: song rows laid out in columns of three that
/// page horizontally, each with artwork, title, artist and a "…" menu.
///
/// Falls back to what you've played recently when nothing is queued, so the
/// shelf is never empty on a fresh launch.
struct UpNextSection: View {
    @Environment(AppState.self) private var appState

    let songs: [MediaItem]
    /// Rows per page — Apple shows three.
    private let rowsPerPage = 3

    private var pages: [[MediaItem]] {
        stride(from: 0, to: songs.count, by: rowsPerPage).map {
            Array(songs[$0 ..< min($0 + rowsPerPage, songs.count)])
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                    VStack(spacing: 0) {
                        ForEach(Array(page.enumerated()), id: \.element.id) { index, song in
                            row(song)
                            if index < page.count - 1 {
                                Divider()
                                    .overlay(UltrafinColors.separator)
                                    .padding(.leading, 62)
                            }
                        }
                    }
                    .containerRelativeFrame(.horizontal, count: 1, spacing: 0)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }

    private func row(_ song: MediaItem) -> some View {
        HStack(spacing: Spacing.md) {
            Button {
                guard let source = appState.musicSource else { return }
                Haptics.play(.selection)
                MusicPlayer.shared.play(tracks: songs,
                                        startAt: songs.firstIndex(where: { $0.id == song.id }) ?? 0,
                                        source: source)
            } label: {
                HStack(spacing: Spacing.md) {
                    RemoteImage(url: appState.musicSource?.artworkURL(for: song, maxWidth: 160))
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(song.name)
                                .font(.system(size: 15))
                                .foregroundStyle(UltrafinColors.primaryText)
                                .lineLimit(1)
                            if song.isExplicit { ExplicitBadge(size: 11) }
                        }
                        Text(song.artistText ?? " ")
                            .font(.system(size: 14))
                            .foregroundStyle(UltrafinColors.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            songMenu(song)
        }
        .padding(.vertical, 8)
    }

    private func songMenu(_ song: MediaItem) -> some View {
        Menu {
            Button {
                guard let source = appState.musicSource else { return }
                MusicPlayer.shared.playNext(song, source: source)
            } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }

            Button {
                guard let source = appState.musicSource else { return }
                MusicPlayer.shared.addToQueue(song, source: source)
            } label: { Label("Add to Queue", systemImage: "text.append") }

            if let album = song.albumDestination {
                Divider()
                NavigationLink(value: album) {
                    Label("Go to Album", systemImage: "square.stack")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(UltrafinColors.secondaryText)
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
    }
}
