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
            guard let source = appState.musicSource else { return }
            if container.type == .playlist {
                tracks = (try? await source.playlistTracks(playlistID: container.id)) ?? []
            } else {
                tracks = (try? await source.albumTracks(albumID: container.id)) ?? []
            }
            isLoading = false
            artColor = await ImageColor.vibrant(from: colorURL)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        #if os(tvOS)
        tvHeader
        #else
        phoneHeader
        #endif
    }

    #if os(iOS)
    /// iPhone: a centered vertical layout — big art, title, artist·year, the
    /// song/runtime line, then full-width Play + Shuffle. (The old shared
    /// horizontal layout squeezed the buttons until "Play" wrapped.)
    private var phoneHeader: some View {
        VStack(spacing: Spacing.lg) {
            RemoteImage(url: artURL)
                .frame(width: artSide, height: artSide)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadius, style: .continuous))
                .specularRim(cornerRadius: Spacing.cornerRadius, intensity: 0.7)
                .shadow(color: .black.opacity(0.45), radius: 28, y: 14)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    if container.isExplicit { ExplicitBadge(size: titleSize * 0.6) }
                    Text(container.name)
                        .font(.system(size: titleSize, weight: .bold, design: .rounded))
                        .foregroundStyle(UltrafinColors.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                Text(subtitleLine)
                    .font(.system(size: titleSize * 0.6, weight: .semibold, design: .rounded))
                    .foregroundStyle(artColor?.color ?? settings.theme.accent.color)
                    .lineLimit(1)
                if let meta = metaLine {
                    Text(meta)
                        .font(.system(size: titleSize * 0.46, weight: .medium))
                        .foregroundStyle(UltrafinColors.secondaryText)
                }
            }

            HStack(spacing: Spacing.md) {
                actionPill("Play", icon: "play.fill", fill: true) { start(shuffled: false) }
                actionPill("Shuffle", icon: "shuffle", fill: true) { start(shuffled: true) }
            }
            // Cap the button row so it doesn't stretch edge-to-edge (and read as
            // bulky) on a large phone — centered under the art instead.
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
    }
    #endif

    /// tvOS keeps the wide art-left / info-right hero (plenty of room there).
    private var tvHeader: some View {
        HStack(alignment: .bottom, spacing: Spacing.xl) {
            RemoteImage(url: artURL)
                .frame(width: artSide, height: artSide)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadius, style: .continuous))
                .specularRim(cornerRadius: Spacing.cornerRadius, intensity: 0.7)
                .shadow(color: .black.opacity(0.45), radius: 28, y: 14)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: 8) {
                    if container.isExplicit { ExplicitBadge(size: titleSize * 0.5) }
                    Text(container.name)
                        .font(.system(size: titleSize, weight: .bold, design: .rounded))
                        .foregroundStyle(UltrafinColors.primaryText)
                        .lineLimit(2)
                }
                Text(subtitleLine)
                    .font(.system(size: titleSize * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(artColor?.color ?? settings.theme.accent.color)
                    .lineLimit(1)
                if let meta = metaLine {
                    Text(meta)
                        .font(.system(size: titleSize * 0.38, weight: .medium))
                        .foregroundStyle(UltrafinColors.secondaryText)
                }

                HStack(spacing: Spacing.md) {
                    actionPill("Play", icon: "play.fill", fill: false) { start(shuffled: false) }
                    actionPill("Shuffle", icon: "shuffle", fill: false) { start(shuffled: true) }
                }
                .padding(.top, Spacing.sm)
            }
            Spacer(minLength: 0)
        }
    }

    private func actionPill(_ title: String, icon: String, fill: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.medium)
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: pillFont, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize(horizontal: !fill, vertical: true)
                .frame(maxWidth: fill ? .infinity : nil)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm + 3)
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
                        guard let source = appState.musicSource else { return }
                        Haptics.play(.selection)
                        player.play(tracks: tracks, startAt: position, source: source)
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
        guard let source = appState.musicSource, !tracks.isEmpty else { return }
        player.play(tracks: tracks, startAt: 0, source: source, shuffled: shuffled)
    }

    // MARK: - Helpers

    private var subtitleLine: String {
        if container.type == .playlist { return "Playlist" }
        return [container.artistText, container.productionYear.map(String.init)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// "12 songs · 48 min" — grammatically correct count plus total runtime.
    private var metaLine: String? {
        guard !tracks.isEmpty else { return nil }
        let count = tracks.count
        let songs = "\(count) song\(count == 1 ? "" : "s")"
        if let dur = totalDurationText { return "\(songs) · \(dur)" }
        return songs
    }

    private var totalDurationText: String? {
        let ticks = tracks.compactMap(\.runTimeTicks).reduce(0, +)
        guard ticks > 0 else { return nil }
        let minutes = Int(ticks / 600_000_000)
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h) hr \(m) min" : "\(m) min"
    }

    private var artURL: URL? {
        appState.musicSource?.artworkURL(for: container, maxWidth: Int(artSide * 2))
    }
    private var colorURL: URL? {
        appState.musicSource?.artworkURL(for: container, maxWidth: 240)
    }

    // MARK: - Metrics

    private var artSide: CGFloat {
        #if os(tvOS)
        340
        #else
        240
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
                HStack(spacing: 5) {
                    Text(track.name)
                        .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(isCurrent ? settings.theme.accent.color : UltrafinColors.primaryText)
                        .lineLimit(1)
                    if track.isExplicit { ExplicitBadge(size: titleSize * 0.82) }
                }
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
        appState.musicSource?.artworkURL(for: track, maxWidth: 160)
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
            guard let source = appState.musicSource else { return }
            albums = (try? await source.artistAlbums(artistID: artist.id)) ?? []
            isLoading = false
        }
    }

    private var artURL: URL? {
        appState.musicSource?.artworkURL(for: artist, maxWidth: Int(portraitSide * 2))
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
