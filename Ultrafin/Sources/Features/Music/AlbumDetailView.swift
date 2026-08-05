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
        content
        .background(AlbumBackdrop(color: artColor))
        .environment(\.colorScheme, .dark)
        #if os(iOS)
        // No title in the bar and no material behind it: the record's own wash
        // runs edge to edge, and the back button floats over it as a glass
        // circle. Repeating the album name above its own cover was the busiest
        // thing on the page.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { albumMenu } }
        .adaptsChromeOnScroll()
        #endif
        .tvPopsOnMenu()
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

    @ViewBuilder
    private var content: some View {
        #if os(tvOS)
        tvContent
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                phoneHeader
                trackList
            }
            .padding(.horizontal, edgePadding)
            .padding(.vertical, Spacing.xl)
            .frame(maxWidth: .infinity)
        }
        #endif
    }

    #if os(tvOS)
    /// Apple TV's album page: the record and its actions stand still on the
    /// left while the songs scroll on the right.
    ///
    /// The old layout stacked the two in a single 1200pt column on a 1920pt
    /// screen, which is why it read like a phone taped to a television — one
    /// narrow strip of content with a third of the screen empty either side.
    /// Two columns use the whole canvas and give the track list somewhere to
    /// actually scroll.
    private var tvContent: some View {
        HStack(alignment: .top, spacing: 72) {
            tvSidebar
                .frame(width: 560)

            ScrollView {
                trackList
                    .padding(.bottom, 80)
            }
            .frame(maxWidth: .infinity)
            .focusSection()
        }
        .padding(.horizontal, 80)
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The left column: cover, title, credits, and the two things you came to
    /// press. Deliberately not scrollable — it's the page's anchor.
    private var tvSidebar: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            RemoteImage(url: artURL)
                .frame(width: artSide, height: artSide)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .specularRim(cornerRadius: 12, intensity: 0.7)
                .shadow(color: .black.opacity(0.5), radius: 36, y: 20)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: 10) {
                    Text(container.name)
                        .font(.system(size: titleSize, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if container.isExplicit { ExplicitBadge(size: titleSize * 0.44) }
                }
                Text(subtitleLine)
                    .font(.system(size: titleSize * 0.52, weight: .medium))
                    .foregroundStyle(artColor?.shade(brightness: 1.2, saturation: 0.85)
                                     ?? settings.accent)
                    .lineLimit(1)
                if let detail = tvDetailLine {
                    Text(detail)
                        .font(.system(size: titleSize * 0.38, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                }
            }

            HStack(spacing: Spacing.md) {
                actionPill("Play", icon: "play.fill", fill: false) { start(shuffled: false) }
                actionPill("Shuffle", icon: "shuffle", fill: false) { start(shuffled: true) }
            }
            .padding(.top, Spacing.sm)
            .focusSection()

            Spacer(minLength: 0)
        }
    }

    /// "Album · Hip Hop · 2017 · FLAC · 13 songs · 46 min" — the TV has the room
    /// for the full line, so it carries the count and length the phone drops.
    private var tvDetailLine: String? {
        var parts: [String] = []
        if let detail = detailLine { parts.append(detail) }
        if let meta = metaLine { parts.append(meta) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    #endif

    #if os(iOS)
    /// iPhone: cover in a white frame, then title, artist and a quiet
    /// "kind · genre · year · format" line, then Shuffle / Play / Heart. Nothing
    /// else — downloading and queueing live in the "…" menu up in the bar, which
    /// is what keeps this block as calm as the reference.
    private var phoneHeader: some View {
        VStack(spacing: Spacing.lg) {
            albumCover

            VStack(spacing: 4) {
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
                        .font(.system(size: titleSize * 0.85, weight: .regular))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                }
                if let detail = detailLine {
                    Text(detail)
                        .font(.system(size: titleSize * 0.58, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.top, 2)
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
            .padding(.top, Spacing.sm)
        }
        .frame(maxWidth: .infinity)
    }

    /// The cover, matted in white like a print in a frame — the detail that
    /// makes the artwork sit *on* the page rather than in it.
    private var albumCover: some View {
        RemoteImage(url: artURL)
            .frame(width: artSide, height: artSide)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(matWidth)
            .background(
                RoundedRectangle(cornerRadius: 6 + matWidth, style: .continuous)
                    .fill(.white)
            )
            .shadow(color: .black.opacity(0.45), radius: 26, y: 14)
    }

    private var matWidth: CGFloat { 9 }

    /// The bar's "…": everything that isn't Play, Shuffle or the heart.
    private var albumMenu: some View {
        Menu {
            Button {
                guard let source = appState.musicSource, !tracks.isEmpty else { return }
                player.addToQueue(tracks: tracks, source: source)
                Haptics.play(.success)
            } label: { Label("Add to Queue", systemImage: "text.append") }

            Button {
                guard let source = appState.musicSource, !tracks.isEmpty else { return }
                player.play(tracks: tracks, startAt: 0, source: source,
                            shuffled: true, context: container.name)
            } label: { Label("Shuffle", systemImage: "shuffle") }

            if let artist = container.artistDestination {
                Divider()
                NavigationLink(value: artist) {
                    Label("Go to Artist", systemImage: "music.mic")
                }
            }

            if MusicLibraryCache.isSupported && !tracks.isEmpty {
                Divider()
                downloadMenuItem
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    /// Keep this album on the device — or, once it's here, remove it again.
    @ViewBuilder
    private var downloadMenuItem: some View {
        switch downloadState {
        case .working:
            Label("Downloading…", systemImage: "arrow.down.circle.dotted")
                .foregroundStyle(.secondary)
        case .downloaded:
            Button(role: .destructive) {
                for track in tracks { downloads.remove(track.id) }
            } label: {
                Label(tracks.count == 1 ? "Remove Download" : "Remove Album Download",
                      systemImage: "trash")
            }
        case .partial:
            Button { downloadAll() } label: {
                // Say plainly that only part of the record is here.
                Label("Get the Rest · \(storedHere) of \(tracks.count)",
                      systemImage: "arrow.down.circle.dotted")
            }
        case .idle:
            Button { downloadAll() } label: {
                Label(tracks.count == 1 ? "Download Single" : "Download Album",
                      systemImage: "arrow.down.circle")
            }
        }
    }

    private func downloadAll() {
        guard let source = appState.musicSource else { return }
        Haptics.play(.selection)
        Task {
            await downloads.store(tracks: tracks, source: source,
                                  label: "Downloading \(container.name)",
                                  albumTotal: tracks.count)
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
                .tintedGlassCapsule(artColor?.color ?? settings.accent, strength: 0.65)
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
                ForEach(Array(tracks.enumerated()), id: \.offset) { position, track in
                    HStack(spacing: 0) {
                        Button {
                            guard let source = appState.musicSource else { return }
                            Haptics.play(.selection)
                            player.play(tracks: tracks, startAt: position,
                                        source: source, context: container.name)
                        } label: {
                            #if os(iOS)
                            AlbumTrackRow(track: track,
                                          position: position + 1,
                                          isCurrent: player.currentTrack?.id == track.id,
                                          showsArt: container.type == .playlist)
                            #else
                            TrackRow(track: track,
                                     position: position + 1,
                                     isCurrent: player.currentTrack?.id == track.id,
                                     showsArt: container.type == .playlist)
                            #endif
                        }
                        .buttonStyle(UltrafinButtonStyle(focusScale: 1.01, lift: false))

                        #if os(iOS)
                        trackMenu(for: track, at: position)
                        #endif
                    }
                    // Hairline separators between songs, inset to where the title
                    // starts and running out to the edge — the Apple Music rhythm.
                    if position < tracks.count - 1 {
                        Rectangle()
                            .fill(.white.opacity(0.12))
                            .frame(height: separatorHeight)
                            .padding(.leading, separatorInset)
                    }
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
                player.play(tracks: tracks, startAt: position,
                            source: source, context: container.name)
            } label: { Label("Play", systemImage: "play.fill") }

            Button {
                guard let source = appState.musicSource else { return }
                Haptics.play(.success)
                player.playNext(track, source: source)
            } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }

            Button {
                guard let source = appState.musicSource else { return }
                Haptics.play(.success)
                player.addToQueue(track, source: source)
            } label: { Label("Add to Queue", systemImage: "text.append") }

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
        player.play(tracks: tracks, startAt: 0, source: source,
                    shuffled: shuffled, context: container.name)
    }

    // MARK: - Helpers

    private var subtitleLine: String {
        if container.type == .playlist { return "Playlist" }
        return [container.artistText, container.productionYear.map(String.init)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// "Album · Hip Hop · 2017 · FLAC" — what kind of release it is, then where
    /// it sits and how it sounds.
    ///
    /// The song count and total length used to live here too; they made the line
    /// long enough to shrink, and the list right below already answers both. What
    /// stays is what you can't see anywhere else on the page.
    private var detailLine: String? {
        var parts: [String] = []
        if container.type == .playlist {
            parts.append("Playlist")
        } else if let kind = releaseKind {
            parts.append(kind.label)
        }
        if let genre = container.genres?.first ?? tracks.first?.genres?.first {
            parts.append(genre)
        }
        if let year = container.productionYear { parts.append(String(year)) }
        // Quality comes off the tracks (the album itself has no container).
        if let format = tracks.first?.formatBadge { parts.append(format) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Single vs EP vs album, preferring the tracks we actually loaded over the
    /// server's count (which can be stale or absent).
    private var releaseKind: ReleaseKind? {
        guard container.type != .playlist else { return nil }
        if !tracks.isEmpty { return ReleaseKind(trackCount: tracks.count) }
        return container.releaseKind
    }

    /// "12 songs · 48 min" — grammatically correct count plus total runtime.
    /// A single says only its length; "Single · 1 song" reads as a stutter.
    private var metaLine: String? {
        guard !tracks.isEmpty else { return nil }
        // A single says only its length; "Single · 1 song" reads as a stutter.
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

    private var separatorHeight: CGFloat {
        #if os(tvOS)
        1
        #else
        0.5
        #endif
    }
    /// Separators start where the title does, so the number column stays clear.
    private var separatorInset: CGFloat {
        #if os(tvOS)
        76
        #else
        AlbumTrackRow.titleInset
        #endif
    }

    private var artSide: CGFloat {
        #if os(tvOS)
        460
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
        26
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
}

#if os(iOS)
/// One song on an album page: track number, title, and nothing else.
///
/// No artist line (every song on a record shares one) and no duration — a
/// column of times turns a track list into a spreadsheet. The song that's
/// playing swaps its number for a bar glyph, which is all the marking it needs.
struct AlbumTrackRow: View {
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    let track: MediaItem
    let position: Int
    let isCurrent: Bool
    /// Playlists mix artists, so they show artwork and a credit; albums don't.
    var showsArt: Bool = false

    /// Where the title starts — the separators line up with it.
    static let titleInset: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: Self.titleInset, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(track.name)
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if track.isExplicit { ExplicitBadge(size: 12) }
                }
                if showsArt, let artist = track.artistText {
                    Text(artist)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.sm)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leading: some View {
        if showsArt {
            RemoteImage(url: appState.musicSource?.artworkURL(for: track, maxWidth: 120))
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else if isCurrent {
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(settings.accent)
        } else {
            Text("\(position)")
                .font(.system(size: 16))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}
#endif

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
                    .foregroundStyle(settings.accent)
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
                        .foregroundStyle(isCurrent ? settings.accent : UltrafinColors.primaryText)
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
        .padding(.horizontal, rowHPadding)
        .padding(.vertical, rowVPadding)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isFocused ? 0.14 : (isCurrent ? 0.06 : 0)))
        )
        .contentShape(Rectangle())
    }

    private var artURL: URL? {
        appState.musicSource?.artworkURL(for: track, maxWidth: 160)
    }

    private var numberSize: CGFloat {
        #if os(tvOS)
        22
        #else
        15
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        25
        #else
        16
        #endif
    }
    private var artSide: CGFloat {
        #if os(tvOS)
        56
        #else
        44
        #endif
    }
    private var rowHPadding: CGFloat {
        #if os(tvOS)
        Spacing.lg
        #else
        Spacing.md
        #endif
    }
    /// A TV is watched from across a room; rows need room to separate.
    private var rowVPadding: CGFloat {
        #if os(tvOS)
        16
        #else
        Spacing.sm + 2
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
        .musicCanvas()
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
