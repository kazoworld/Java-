import SwiftUI

/// A full-screen list of every episode in an episode's season, opened from the
/// "More Episodes" button on an episode's detail page. Scrolls to (and highlights)
/// the episode you came from; tapping any episode plays it.
struct SeasonEpisodesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let episode: MediaItem

    @State private var episodes: [MediaItem] = []
    @State private var isLoading = true
    @State private var playback: PlaybackRequest?

    private var session: UserSession? {
        if case .authenticated(let s) = appState.phase { return s }
        return nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    header
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xxl)
                    } else {
                        LazyVStack(spacing: Spacing.md) {
                            ForEach(episodes) { ep in
                                Button { play(ep) } label: {
                                    EpisodeRow(episode: ep, imageURL: imageURL(ep))
                                        .overlay(alignment: .topTrailing) {
                                            if ep.id == episode.id { nowPlayingBadge }
                                        }
                                }
                                .buttonStyle(UltrafinButtonStyle(focusScale: 1.02, lift: true))
                                .id(ep.id)
                            }
                        }
                    }
                }
                .padding(edgePadding)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: episodes) { _, list in
                guard list.contains(where: { $0.id == episode.id }) else { return }
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo(episode.id, anchor: .center) }
                }
            }
        }
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
        HStack(spacing: Spacing.md) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(UltrafinButtonStyle(focusScale: 1.1, lift: false))

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.seriesName ?? "Episodes")
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(UltrafinColors.primaryText)
                if let s = episode.parentIndexNumber {
                    Text("Season \(s)")
                        .font(.system(size: titleSize * 0.5, weight: .medium))
                        .foregroundStyle(UltrafinColors.secondaryText)
                }
            }
            Spacer()
        }
    }

    private var nowPlayingBadge: some View {
        Text("Now Viewing")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.sm).padding(.vertical, 3)
            .background(UltrafinColors.accent, in: Capsule())
            .padding(Spacing.sm)
    }

    private func load() async {
        guard let session, let client = appState.client,
              let seriesID = episode.seriesId, let seasonID = episode.seasonId else {
            isLoading = false
            return
        }
        episodes = (try? await client.episodes(seriesID: seriesID, seasonID: seasonID, userID: session.userID)) ?? []
        isLoading = false
    }

    private func play(_ ep: MediaItem) {
        guard let idx = episodes.firstIndex(where: { $0.id == ep.id }) else { return }
        playback = PlaybackRequest(queue: episodes, index: idx)
    }

    private func imageURL(_ ep: MediaItem) -> URL? {
        let tag = ep.imageTags?["Primary"]
        return appState.client?.imageURL(itemID: ep.id, kind: .primary, tag: tag, maxWidth: 600)
    }

    private var titleSize: CGFloat {
        #if os(tvOS)
        40
        #else
        24
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
