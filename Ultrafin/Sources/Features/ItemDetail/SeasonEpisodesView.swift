import SwiftUI

/// A full-screen list of every episode in an episode's season, opened from the
/// "More Episodes" button on an episode's detail page. Scrolls to (and highlights)
/// the episode you came from; tapping any episode plays it.
struct SeasonEpisodesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let episode: MediaItem

    @State private var seasons: [MediaItem] = []
    @State private var selectedSeasonID: String?
    /// Episodes cached per season so re-selecting one is instant (no re-fetch).
    @State private var episodesBySeason: [String: [MediaItem]] = [:]
    @State private var episodes: [MediaItem] = []
    @State private var isLoading = true
    @State private var playback: PlaybackRequest?

    private var session: UserSession? {
        if case .authenticated(let s) = appState.phase { return s }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SeasonEpisodeBrowser(
                    seriesName: episode.seriesName ?? "Episodes",
                    seasons: seasons,
                    selectedSeasonID: selectedSeasonID,
                    episodes: episodes,
                    currentEpisodeID: episode.id,
                    episodeImageURL: imageURL,
                    onSelectSeason: { id in Task { await selectSeason(id) } },
                    onPlay: play
                )
            }
        }
        .padding(edgePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(UltrafinColors.background.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task { await load() }
        .fullScreenCover(item: $playback) { request in
            if let session {
                VideoPlayerView(queue: request.queue, startIndex: request.index, userID: session.userID)
            }
        }
        #if os(tvOS)
        .onExitCommand { dismiss() }
        #endif
    }

    private var header: some View {
        Button { dismiss() } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .bold))
                Text("Back").font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
            .glassCapsule(dim: 0.12)
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.06, lift: false))
    }

    private func load() async {
        guard let session, let client = appState.client, let seriesID = episode.seriesId else {
            isLoading = false
            return
        }
        seasons = (try? await client.seasons(seriesID: seriesID, userID: session.userID)) ?? []
        let initial = episode.seasonId ?? seasons.first?.id
        selectedSeasonID = initial
        if let initial {
            let eps = (try? await client.episodes(seriesID: seriesID, seasonID: initial, userID: session.userID)) ?? []
            episodesBySeason[initial] = eps
            episodes = eps
        }
        isLoading = false
    }

    private func selectSeason(_ id: String) async {
        guard id != selectedSeasonID, let session, let client = appState.client,
              let seriesID = episode.seriesId else { return }
        selectedSeasonID = id
        if let cached = episodesBySeason[id] { episodes = cached; return }
        let eps = (try? await client.episodes(seriesID: seriesID, seasonID: id, userID: session.userID)) ?? []
        episodesBySeason[id] = eps
        episodes = eps
    }

    private func play(_ ep: MediaItem) {
        guard let idx = episodes.firstIndex(where: { $0.id == ep.id }) else { return }
        playback = PlaybackRequest(queue: episodes, index: idx)
    }

    private func imageURL(_ ep: MediaItem) -> URL? {
        let tag = ep.imageTags?["Primary"]
        return appState.client?.imageURL(itemID: ep.id, kind: .primary, tag: tag, maxWidth: 600)
    }

    private var edgePadding: CGFloat {
        #if os(tvOS)
        60
        #else
        20
        #endif
    }
}
