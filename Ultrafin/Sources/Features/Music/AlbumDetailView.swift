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
    /// Local heart state so the tap reflects instantly; the server catches up.
    @State private var favoriteOverride: Bool?
    /// Offline storage, so the download button reflects live state.
    @State private var downloads = MusicLibraryCache.shared

    private var player: MusicPlayer { .shared }

    private var isFavorite: Bool {
        favoriteOverride ?? (container.userData?.isFavorite ?? false)
    }

    private func toggleFavorite() {
        let next = !isFavorite
        favoriteOverride = next
        guard let source = appState.musicSource else { return }
        Task { await source.setFavorite(itemID: container.id, isFavorite: next) }
    }

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
        .background(AlbumBackdrop(color: artColor))
        .environment(\.colorScheme, .dark)
        #if os(iOS)
        .navigationTitle(container.name)
        .navigationBarTitleDisplayMode(.inline)
        .adaptsChromeOnScroll()
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
    /// iPhone: the Apple Music album layout — centered cover, title, artist, a
    /// quiet "year · format · length" line, then Shuffle / Play / Heart.
    private var phoneHeader: some View {
        VStack(spacing: Spacing.lg) {
            RemoteImage(url: artURL)
                .frame(width: artSide, height: artSide)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadius, style: .continuous))
                .specularRim(cornerRadius: Spacing.cornerRadius, intensity: 0.7)
                .shadow(color: .black.opacity(0.5), radius: 30, y: 16)

            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    Text(container.name)
                        .font(.system(size: titleSize, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                    if container.isExplicit { ExplicitBadge(size: titleSize * 0.66) }
                }
                if let artist = container.artistText, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: titleSize * 0.88, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }
                // "2012 · FLAC · 12 songs · 48 min" — the quiet detail line.
                if let detail = detailLine {
                    Text(detail)
                        .font(.system(size: titleSize * 0.6, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            // Shuffle · Play · Heart — the Apple Music action row.
            HStack(spacing: Spacing.lg) {
                circleAction("shuffle", label: "Shuffle", isEnabled: !tracks.isEmpty) {
                    start(shuffled: true)
                }
                playPill
                circleAction(isFavorite ? "heart.fill" : "heart",
                             label: isFavorite ? "Remove from Favorites" : "Add to Favorites",
                             tint: isFavorite ? .red : .white) { toggleFavorite() }
            }
            .padding(.top, Spacing.xs)

            downloadButton
        }
        .frame(maxWidth: .infinity)
    }

    /// Keep this album on the device — or, once it's here, remove it again.
    @ViewBuilder
    private var downloadButton: some View {
        if MusicLibraryCache.isSupported && !tracks.isEmpty {
            let state = downloadState
            Button {
                Haptics.play(.selection)
                switch state {
                case .downloaded:
                    for track in tracks { downloads.remove(track.id) }
                case .idle, .partial:
                    guard let source = appState.musicSource else { return }
                    Task {
                        await downloads.store(tracks: tracks, source: source,
                                              label: "Downloading \(container.name)",
                                              albumTotal: tracks.count)
                    }
                case .working:
                    break
                }
            } label: {
                HStack(spacing: 7) {
                    switch state {
                    case .working:
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Downloading…")
                    case .downloaded:
                        Image(systemName: "checkmark.circle.fill")
                        Text(tracks.count == 1 ? "Single Downloaded" : "Album Downloaded")
                    case .partial:
                        Image(systemName: "arrow.down.circle.dotted")
                        // Say plainly that only part of the record is here.
                        Text("Get the rest · \(storedHere) of \(tracks.count)")
                    case .idle:
                        Image(systemName: "arrow.down.circle")
                        Text(tracks.count == 1 ? "Download Single" : "Download Album")
                    }
                }
                .font(.system(size: pillFont * 0.86, weight: .semibold, design: .rounded))
                .foregroundStyle(state == .downloaded ? .white.opacity(0.75) : .white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .glassCapsule(dim: 0.1)
            }
            .buttonStyle(UltrafinButtonStyle(focusScale: 1.05, lift: false))
            .disabled(state == .working)
            .animation(.smooth(duration: 0.25), value: state)
        }
    }

    private enum DownloadState { case idle, working, partial, downloaded }

    /// How many of this release's songs are already downloaded.
    private var storedHere: Int {
        tracks.filter { downloads.isDownloaded($0.id) }.count
    }

    private var downloadState: DownloadState {
        if tracks.contains(where: { downloads.isFetching($0.id) }) { return .working }
        guard !tracks.isEmpty else { return .idle }
        let have = storedHere
        if have == tracks.count { return .downloaded }
        return have > 0 ? .partial : .idle
    }

    /// The big white Play capsule at the center of the action row.
    private var playPill: some View {
        Button {
            Haptics.play(.medium)
            start(shuffled: false)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "play.fill")
                    .font(.system(size: pillFont * 0.95, weight: .bold))
                Text("Play")
                    .font(.system(size: pillFont, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.05, lift: false))
        .frame(maxWidth: 210)
        .disabled(tracks.isEmpty)
    }

    /// A round secondary action flanking the Play pill.
    private func circleAction(_ icon: String, label: String, tint: Color = .white,
                              isEnabled: Bool = true,
                              action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.selection)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: pillFont, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: circleSide, height: circleSide)
                .background(.white.opacity(0.14), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.08, lift: false))
        .accessibilityLabel(label)
        .disabled(!isEnabled)
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
            LazyVStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { position, track in
                    HStack(spacing: 0) {
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

                        #if os(iOS)
                        trackMenu(for: track, at: position)
                        #endif
                    }
                    #if os(iOS)
                    // Hairline separators between songs, inset past the number
                    // column — the Apple Music track list rhythm.
                    if position < tracks.count - 1 {
                        Rectangle()
                            .fill(.white.opacity(0.09))
                            .frame(height: 1)
                            .padding(.leading, Spacing.xxl)
                    }
                    #endif
                }
            }
        }
    }

    #if os(iOS)
    /// The per-song "..." menu: queue actions and a heart, like Apple Music.
    private func trackMenu(for track: MediaItem, at position: Int) -> some View {
        Menu {
            Button {
                guard let source = appState.musicSource else { return }
                player.play(tracks: tracks, startAt: position, source: source)
            } label: { Label("Play", systemImage: "play.fill") }

            Button {
                guard let source = appState.musicSource else { return }
                player.playNext(track, source: source)
            } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }

            Button {
                guard let source = appState.musicSource else { return }
                player.playLater(track, source: source)
            } label: { Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") }

            Divider()

            if MusicLibraryCache.isSupported {
                if downloads.isDownloaded(track.id) {
                    Button(role: .destructive) {
                        downloads.remove(track.id)
                    } label: { Label("Remove Download", systemImage: "trash") }
                } else {
                    Button {
                        guard let source = appState.musicSource else { return }
                        // Record the release's real size so one song off a
                        // twelve-track album never looks like the whole album.
                        Task {
                            await downloads.store(track, source: source, pinned: true,
                                                  albumTotal: tracks.count)
                        }
                    } label: { Label("Download", systemImage: "arrow.down.circle") }
                }
            }

            Button {
                guard let source = appState.musicSource else { return }
                let next = !(track.userData?.isFavorite ?? false)
                Task { await source.setFavorite(itemID: track.id, isFavorite: next) }
            } label: {
                Label((track.userData?.isFavorite ?? false) ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: (track.userData?.isFavorite ?? false) ? "heart.slash" : "heart")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
    #endif

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

    /// "Single · 2012 · FLAC · 3 min" — what kind of release it is comes first,
    /// so a one-song release is never mistaken for a full album.
    private var detailLine: String? {
        var parts: [String] = []
        if container.type == .playlist {
            parts.append("Playlist")
        } else if let kind = releaseKind {
            parts.append(kind.label)
        }
        if let year = container.productionYear { parts.append(String(year)) }
        // Quality comes off the tracks (the album itself has no container).
        if let format = tracks.first?.formatBadge { parts.append(format) }
        if let meta = metaLine { parts.append(meta) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Single vs album, preferring the tracks we actually loaded over the
    /// server's count (which can be stale or absent).
    private var releaseKind: ReleaseKind? {
        guard container.type != .playlist else { return nil }
        if !tracks.isEmpty { return tracks.count <= 1 ? .single : .album }
        return container.releaseKind
    }

    /// "12 songs · 48 min" — grammatically correct count plus total runtime.
    /// A single says only its length; "Single · 1 song" reads as a stutter.
    private var metaLine: String? {
        guard !tracks.isEmpty else { return nil }
        if releaseKind == .single { return totalDurationText }
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
        260
        #endif
    }
    private var circleSide: CGFloat {
        #if os(tvOS)
        76
        #else
        52
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
