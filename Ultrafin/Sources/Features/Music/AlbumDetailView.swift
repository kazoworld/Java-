import SwiftUI

/// An album's (or playlist's) page: big art with color-washed backdrop, Play /
/// Shuffle, and the track list. Tapping a track starts the queue from there.
struct AlbumDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    /// A MusicAlbum or a Playlist.
    let container: MediaItem

    @State private var tracks: [MediaItem] = []
    @State private var isLoading = true
    @State private var artColor: ArtworkColor?

    private var session: UserSession? {
        if case .authenticated(let s) = appState.phase { return s }
        return nil
    }
    private var player: MusicPlayer { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                trackList
            }
            .padding(.horizontal, edgePadding)
            .padding(.vertical, Spacing.xl)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(ArtworkBackground(color: artColor))
        .environment(\.colorScheme, .dark)
        #if os(iOS)
        .navigationTitle(container.name)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard let session, let client = appState.client else { return }
            if container.type == .playlist {
                tracks = (try? await client.playlistTracks(playlistID: container.id, userID: session.userID)) ?? []
            } else {
                tracks = (try? await client.albumTracks(albumID: container.id, userID: session.userID)) ?? []
            }
            isLoading = false
            artColor = await ImageColor.vibrant(from: colorURL)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: Spacing.xl) {
            RemoteImage(url: artURL)
                .frame(width: artSide, height: artSide)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadius, style: .continuous))
                .specularRim(cornerRadius: Spacing.cornerRadius, intensity: 0.7)
                .shadow(color: .black.opacity(0.45), radius: 28, y: 14)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(container.name)
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(UltrafinColors.primaryText)
                    .lineLimit(2)
                Text(subtitleLine)
                    .font(.system(size: titleSize * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(artColor?.color ?? settings.theme.accent.color)
                    .lineLimit(1)
                if !tracks.isEmpty {
                    Text("\(tracks.count) songs\(totalDurationText.map { " · \($0)" } ?? "")")
                        .font(.system(size: titleSize * 0.38, weight: .medium))
                        .foregroundStyle(UltrafinColors.secondaryText)
                }

                HStack(spacing: Spacing.md) {
                    actionPill("Play", icon: "play.fill") { start(shuffled: false) }
                    actionPill("Shuffle", icon: "shuffle") { start(shuffled: true) }
                }
                .padding(.top, Spacing.sm)
            }
            Spacer(minLength: 0)
        }
    }

    private func actionPill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.medium)
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: pillFont, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
                .tintedGlassCapsule(artColor?.color ?? settings.theme.accent.color, strength: 0.65)
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.08, lift: true))
        .disabled(tracks.isEmpty)
    }

    // MARK: - Tracks

    @ViewBuilder
    private var trackList: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity)
        } else if tracks.isEmpty {
            Text("No songs here yet.")
                .font(Typography.body)
                .foregroundStyle(UltrafinColors.secondaryText)
        } else {
            LazyVStack(spacing: 2) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { position, track in
                    Button {
                        guard let session, let client = appState.client else { return }
                        Haptics.play(.selection)
                        player.play(tracks: tracks, startAt: position, client: client, userID: session.userID)
                    } label: {
                        TrackRow(track: track,
                                 position: position + 1,
                                 isCurrent: player.currentTrack?.id == track.id,
                                 showsArt: container.type == .playlist)
                    }
                    .buttonStyle(UltrafinButtonStyle(focusScale: 1.01, lift: false))
                }
            }
        }
    }

    private func start(shuffled: Bool) {
        guard let session, let client = appState.client, !tracks.isEmpty else { return }
        player.play(tracks: tracks, startAt: 0, client: client, userID: session.userID, shuffled: shuffled)
    }

    // MARK: - Helpers

    private var subtitleLine: String {
        if container.type == .playlist { return "Playlist" }
        return [container.artistText, container.productionYear.map(String.init)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var totalDurationText: String? {
        let ticks = tracks.compactMap(\.runTimeTicks).reduce(0, +)
        guard ticks > 0 else { return nil }
        let minutes = Int(ticks / 600_000_000)
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m) min"
    }

    private var artURL: URL? {
        appState.client?.imageURL(itemID: container.id, kind: .primary,
                                  tag: container.imageTags?["Primary"], maxWidth: Int(artSide * 2))
    }
    private var colorURL: URL? {
        appState.client?.imageURL(itemID: container.id, kind: .primary,
                                  tag: container.imageTags?["Primary"], maxWidth: 240)
    }

    // MARK: - Metrics

    private var artSide: CGFloat {
        #if os(tvOS)
        340
        #else
        160
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        44
        #else
        24
        #endif
    }
    private var pillFont: CGFloat {
        #if os(tvOS)
        24
        #else
        15
        #endif
    }
    private var edgePadding: CGFloat {
        #if os(tvOS)
        60
        #else
        20
        #endif
    }
    private var contentMaxWidth: CGFloat {
        #if os(tvOS)
        1200
        #else
        .infinity
        #endif
    }
}

/// One song in a track list: number (or art for playlists), title/artist,
/// duration — with the current song lit in the accent.
struct TrackRow: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @Environment(\.isFocused) private var isFocused

    let track: MediaItem
    let position: Int
    let isCurrent: Bool
    var showsArt: Bool = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            if showsArt {
                RemoteImage(url: artURL)
                    .frame(width: artSide, height: artSide)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if isCurrent {
                Image(systemName: "waveform")
                    .font(.system(size: numberSize, weight: .semibold))
                    .foregroundStyle(settings.theme.accent.color)
                    .frame(width: numberSize * 1.6)
            } else {
                Text("\(position)")
                    .font(.system(size: numberSize, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(UltrafinColors.tertiaryText)
                    .frame(width: numberSize * 1.6)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(isCurrent ? settings.theme.accent.color : UltrafinColors.primaryText)
                    .lineLimit(1)
                if let artist = track.artistText {
                    Text(artist)
                        .font(.system(size: titleSize * 0.78))
                        .foregroundStyle(UltrafinColors.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.md)
            if let duration = track.trackDurationText {
                Text(duration)
                    .font(.system(size: titleSize * 0.78, weight: .medium, design: .monospaced))
                    .foregroundStyle(UltrafinColors.tertiaryText)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isFocused ? 0.12 : (isCurrent ? 0.06 : 0)))
        )
        .contentShape(Rectangle())
    }

    private var artURL: URL? {
        guard let client = appState.client else { return nil }
        if let albumId = track.albumId {
            return client.imageURL(itemID: albumId, kind: .primary,
                                   tag: track.albumPrimaryImageTag, maxWidth: 160)
        }
        return client.imageURL(itemID: track.id, kind: .primary,
                               tag: track.imageTags?["Primary"], maxWidth: 160)
    }

    private var numberSize: CGFloat {
        #if os(tvOS)
        24
        #else
        15
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        26
        #else
        16
        #endif
    }
    private var artSide: CGFloat {
        #if os(tvOS)
        64
        #else
        44
        #endif
    }
}

/// An artist's page: circular portrait + their albums.
struct ArtistDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    let artist: MediaItem

    @State private var albums: [MediaItem] = []
    @State private var isLoading = true

    private var session: UserSession? {
        if case .authenticated(let s) = appState.phase { return s }
        return nil
    }

    private var columns: [GridItem] {
        #if os(tvOS)
        [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: Spacing.xl)]
        #else
        [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: Spacing.lg)]
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(spacing: Spacing.xl) {
                    RemoteImage(url: artURL)
                        .frame(width: portraitSide, height: portraitSide)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(LiquidGlass.rim(0.7), lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(artist.name)
                            .font(.system(size: titleSize, weight: .bold, design: .rounded))
                            .foregroundStyle(UltrafinColors.primaryText)
                        if !albums.isEmpty {
                            Text("\(albums.count) album\(albums.count == 1 ? "" : "s")")
                                .font(.system(size: titleSize * 0.42, weight: .medium))
                                .foregroundStyle(UltrafinColors.secondaryText)
                        }
                    }
                    Spacer()
                }

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.xl) {
                        ForEach(albums) { album in
                            NavigationLink(value: album) {
                                AlbumCard(album: album)
                            }
                            .mediaCardButtonStyle()
                        }
                    }
                }
            }
            .padding(edgePadding)
        }
        .background(AmbientBackground())
        #if os(iOS)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard let session, let client = appState.client else { return }
            albums = (try? await client.artistAlbums(artistID: artist.id, userID: session.userID)) ?? []
            isLoading = false
        }
    }

    private var artURL: URL? {
        appState.client?.imageURL(itemID: artist.id, kind: .primary,
                                  tag: artist.imageTags?["Primary"], maxWidth: Int(portraitSide * 2))
    }

    private var portraitSide: CGFloat {
        #if os(tvOS)
        260
        #else
        120
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        46
        #else
        26
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
