import SwiftUI
import AVKit
#if os(iOS)
import MediaPlayer
#endif

/// The full-screen music player, in the spirit of Apple Music: the album art
/// floats over its own blurred reflection, shrinking when paused and springing
/// back on play; lyrics scroll karaoke-style; the queue is one tap away.
///
/// Layout adapts to the device: tvOS always shows the coverflow carousel; an
/// iPhone shows the tall art in portrait and switches to the carousel in a
/// two-column layout when turned to landscape. Every layout sizes the artwork
/// off the available space so the transport controls are always on screen.
struct NowPlayingMusicView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var vSizeClass
    #endif

    @Bindable var player: MusicPlayer
    /// Tapping the album or artist name leaves the player and opens that page.
    var onOpen: ((MediaItem) -> Void)? = nil

    /// What fills the center stage.
    private enum Stage { case art, lyrics, queue }
    @State private var stage: Stage = .art
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    /// Slow scale breath on the center carousel card while music plays.
    @State private var breathing = false
    /// The color sampled from the current record — drives the Apple Music wash.
    @State private var artColor: ArtworkColor?
    /// Live vertical drag while swiping the player down to dismiss.
    @State private var dragOffset: CGFloat = 0
    /// Local heart state so the tap lands instantly; cleared on track change.
    @State private var favoriteOverride: Bool?

    /// True on an iPhone held in landscape — the carousel becomes the stage.
    private var isLandscapePhone: Bool {
        #if os(iOS)
        vSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        // The backdrop is a BACKGROUND, not a ZStack sibling. As a sibling its
        // 110pt blur inflated the stack, so the GeometryReader was handed a size
        // wider than the screen and every block sized off that — which is what
        // pushed the controls past both edges. A background is sized to its
        // content and can never enlarge it.
        GeometryReader { geo in
            layout(in: geo.size)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .background(backdrop)
        // Swipe the whole player down to dismiss — the sheet follows your finger
        // and springs back if you don't pull far enough. Swipe the art
        // horizontally to change track.
        .offset(y: max(0, dragOffset))
        #if os(iOS)
        .gesture(playerDrag)
        #endif
        .environment(\.colorScheme, .dark)
        .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.85), value: dragOffset)
        .animation(.smooth(duration: 0.35), value: stage)
        .task(id: player.currentTrack?.id) {
            favoriteOverride = nil // the new song has its own heart state
            guard let track = player.currentTrack,
                  let url = player.artworkURL(for: track, maxWidth: 240) else { return }
            artColor = await ImageColor.vibrant(from: url)
        }
        #if os(iOS)
        // The app is otherwise portrait-locked; let the full player rotate so
        // turning the phone sideways reveals the coverflow carousel. Back to
        // portrait when it closes.
        .onAppear { OrientationLock.unlockForPlayback() }
        .onDisappear { OrientationLock.lockPortrait() }
        #endif
        #if os(tvOS)
        .onExitCommand { dismiss() }
        .onPlayPauseCommand { player.togglePlayPause() }
        #endif
    }

    #if os(iOS)
    /// One gesture for the whole player: a downward pull dismisses it (the sheet
    /// tracks your finger), a horizontal flick on the art changes track. The
    /// scrubber and the lyrics/queue scroll views are children, so they claim
    /// their own touches first and this never fights them.
    private var playerDrag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if value.translation.height > 0,
                   value.translation.height > abs(value.translation.width) {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                if abs(dx) > abs(dy), abs(dx) > 60, stage == .art {
                    Haptics.play(.light)
                    if dx < 0 { player.next() } else { player.previous() }
                    dragOffset = 0
                } else if dy > 140 || value.predictedEndTranslation.height > 320 {
                    dismiss()
                } else {
                    dragOffset = 0
                }
            }
    }
    #endif

    // MARK: - Layouts

    @ViewBuilder
    private func layout(in size: CGSize) -> some View {
        #if os(tvOS)
        tvLayout(in: size)
        #else
        if isLandscapePhone {
            landscapePhoneLayout(in: size)
        } else {
            portraitLayout(in: size)
        }
        #endif
    }

    #if os(tvOS)
    private func tvLayout(in size: CGSize) -> some View {
        // Proportional, not fixed: tvOS hands us points (1920×1080 on both the
        // 1080p and 4K Apple TV, rendered at 2× on 4K), but a TV's title-safe
        // area and the block below the stage both scale with the screen. Give
        // the carousel at most half the height — the card is 1.45× its art once
        // the reflection is counted — and cap it on width so it never crowds.
        let stageHeight = size.height * 0.50
        let side = max(200, min(size.width * 0.24, stageHeight / 1.45))
        return VStack(spacing: size.height * 0.022) {
            carouselStage(side: side)
                .frame(height: side * 1.45)
                .frame(maxWidth: .infinity)
            trackInfo
            scrubber
            transport
            bottomBar
        }
        // Stay inside the TV's title-safe area, proportionally.
        .padding(.horizontal, size.width * 0.08)
        .padding(.vertical, size.height * 0.04)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Left/right on the remote moves through the queue, so the carousel is
        // steerable without hunting for the transport buttons.
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left: player.previous()
            case .right: player.next()
            default: break
            }
        }
    }
    #endif

    #if os(iOS)
    /// Portrait iPhone — the Apple Music player: grabber, big square cover, then
    /// a left-aligned title/artist row with heart and "…" on the right, the
    /// scrubber, large transport, a volume slider, and three route/lyrics/queue
    /// controls. Everything inside one padded column so nothing can clip.
    private func portraitLayout(in size: CGSize) -> some View {
        // Every block gets an EXPLICIT width rather than relying on padding.
        // Padding only insets the proposed size; a child that reports a larger
        // ideal width (a long title Text does exactly that) makes its stack
        // wider than the padded area and then overflows both edges — which is
        // why the title, scrubber and volume row ran off-screen while the
        // artwork and transport looked fine.
        let contentWidth = max(0, min(size.width - edgePadding * 2, 520))
        // Apple's cover is ~85% of the screen width and sits high — its top edge
        // is about 12% down the screen, with a modest gap to the title. Matching
        // that means a bigger cover, pinned near the top rather than floating in
        // the middle of the remaining space.
        let artMax = min(contentWidth, size.height * 0.42)
        return VStack(spacing: 0) {
            grabber
                .padding(.bottom, Spacing.md)

            if stage == .art {
                centerStage(maxSide: artMax)
                    .frame(width: contentWidth)
                // Nudge the cover toward the top and let the slack fall below.
                Spacer(minLength: 0)
            } else {
                // Lyrics and the queue get the full middle; the cover shrinks to
                // a thumbnail in a compact header, exactly as Apple Music does.
                compactHeader
                    .frame(width: contentWidth)
                    .padding(.bottom, Spacing.md)
                centerStage(maxSide: artMax)
                    .frame(width: contentWidth)
                    .frame(maxHeight: .infinity)
            }

            VStack(spacing: Spacing.md) {
                if stage == .art { infoRow }
                scrubber
                transport
                volumeRow
                bottomBar
            }
            .frame(width: contentWidth)
            .padding(.top, stage == .art ? Spacing.md : Spacing.sm)
        }
        .padding(.bottom, Spacing.md)
        .frame(width: size.width, alignment: .center)
        .frame(maxHeight: .infinity)
    }

    /// Landscape iPhone: the carousel on the left, controls stacked on the
    /// right — the standard landscape music layout, and where the coverflow
    /// lives on the phone.
    private func landscapePhoneLayout(in size: CGSize) -> some View {
        // Explicit column widths for the same reason as portrait: padding alone
        // doesn't stop a long title from widening its stack past the screen.
        let usable = max(0, size.width - edgePadding * 2)
        let artColumn = usable * 0.44
        let controlColumn = usable - artColumn - Spacing.xl
        let artMax = min(artColumn, size.height * 0.72)
        return HStack(spacing: Spacing.xl) {
            centerStage(maxSide: artMax)
                .frame(width: artColumn)
                .frame(maxHeight: .infinity)

            VStack(spacing: Spacing.sm) {
                HStack {
                    grabber
                    Spacer()
                }
                Spacer(minLength: 0)
                infoRow
                scrubber
                transport
                bottomBar
                Spacer(minLength: 0)
            }
            .frame(width: max(0, controlColumn))
        }
        .padding(.vertical, Spacing.md)
        .frame(width: size.width, alignment: .center)
        .frame(maxHeight: .infinity)
    }
    #endif

    // MARK: - Backdrop

    /// The record's color poured into a soft, slowly-drifting wash with the
    /// blurred art underneath — the Apple Music look, with a hint of the cover's
    /// own color even on near-monochrome art.
    private var backdrop: some View {
        NowPlayingBackdrop(
            color: artColor,
            artURL: player.currentTrack.flatMap { player.artworkURL(for: $0, maxWidth: 400) }
        )
    }

    /// The sheet handle — a soft pill, as on Apple Music's player.
    private var grabber: some View {
        #if os(iOS)
        Button { dismiss() } label: {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 38, height: 5)
                .frame(width: 90, height: 26) // generous tap target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #else
        EmptyView()
        #endif
    }

    // MARK: - Center stage

    @ViewBuilder
    private func centerStage(maxSide: CGFloat) -> some View {
        switch stage {
        case .art:
            if isLandscapePhone {
                carouselStage(side: maxSide)
            } else {
                #if os(tvOS)
                carouselStage(side: maxSide)
                #else
                artStage(side: maxSide)
                #endif
            }
        case .lyrics: lyricsStage
        case .queue: queueStage
        }
    }

    private func artStage(side: CGFloat) -> some View {
        RemoteImage(url: player.currentTrack.flatMap { player.artworkURL(for: $0) })
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.06, style: .continuous))
            .specularRim(cornerRadius: side * 0.06, intensity: 0.8)
            .shadow(color: .black.opacity(0.55), radius: 40, y: 22)
            // The Apple Music breath: full size while playing, settles back when
            // paused.
            .scaleEffect(player.isPlaying ? 1 : 0.85)
            .animation(.spring(duration: 0.5, bounce: 0.25), value: player.isPlaying)
            .frame(maxWidth: .infinity)
    }

    /// A living coverflow of the queue. The current record stands front and
    /// center — breathing gently while it plays, mirrored in a fading reflection
    /// — with its neighbors receding into the room on either side. Changing
    /// tracks glides the whole shelf across on a spring.
    private func carouselStage(side: CGFloat) -> some View {
        ZStack {
            // Three records: the one playing, and one either side. Neighbours
            // first so the centre draws on top.
            ForEach([-1, 1, 0], id: \.self) { offset in
                if let track = queueTrack(at: offset) {
                    carouselCard(track: track, offset: offset, side: side)
                        // Identity follows the queue slot so a track change
                        // animates cards BETWEEN positions (the glide), not a
                        // crossfade-in-place.
                        .id(track.id)
                }
            }
        }
        // A FIXED stage width keeps the playing record dead centre. Sized by its
        // contents, the stack centred whichever cards happened to exist — so at
        // the start of a queue (no left neighbour) the current card sat left.
        .frame(width: side * 2.5, height: side * 1.45)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.75, bounce: 0.16), value: player.index)
        .onAppear {
            withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }

    private func queueTrack(at offset: Int) -> MediaItem? {
        let i = player.index + offset
        guard player.queue.indices.contains(i) else { return nil }
        return player.queue[i]
    }

    private func carouselCard(track: MediaItem, offset: Int, side baseSide: CGFloat) -> some View {
        let isCenter = offset == 0
        let side = baseSide * (isCenter ? 1 : 0.58)
        let corner = side * 0.05
        return VStack(spacing: 0) {
            RemoteImage(url: player.artworkURL(for: track, maxWidth: isCenter ? 800 : 400))
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .specularRim(cornerRadius: corner, intensity: isCenter ? 0.85 : 0.4)
                .shadow(color: .black.opacity(isCenter ? 0.55 : 0.35),
                        radius: isCenter ? 44 : 22, y: isCenter ? 24 : 12)
                // Side cards hang from the same floor line as the centre one.
                .frame(maxHeight: .infinity, alignment: .bottom)

            // The reflection: the same art flipped, melting into the floor.
            RemoteImage(url: player.artworkURL(for: track, maxWidth: isCenter ? 800 : 400))
                .frame(width: side, height: side)
                .scaleEffect(x: 1, y: -1)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .mask(
                    LinearGradient(stops: [
                        .init(color: .black.opacity(isCenter ? 0.35 : 0.2), location: 0),
                        .init(color: .clear, location: 0.55)
                    ], startPoint: .top, endPoint: .bottom)
                )
                .frame(height: side * 0.45, alignment: .top)
                .clipped()
                .padding(.top, 6)
        }
        // Neighbors turn away into the room, coverflow-style.
        .rotation3DEffect(.degrees(Double(-offset) * 26), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .offset(x: CGFloat(offset) * baseSide * 0.66)
        .opacity(isCenter ? 1 : 0.45)
        .zIndex(isCenter ? 10 : Double(5 - abs(offset)))
        // The center record breathes while the music plays.
        .scaleEffect(isCenter && player.isPlaying ? (breathing ? 1.015 : 0.995) : (isCenter ? 0.96 : 1))
        .animation(isCenter ? .spring(duration: 0.5, bounce: 0.25) : nil, value: player.isPlaying)
    }

    private var lyricsStage: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: lyricSpacing) {
                    if player.lyrics.isEmpty {
                        Text("No lyrics for this song.")
                            .font(.system(size: lyricSize * 0.8))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.top, Spacing.xxl)
                    }
                    ForEach(player.lyrics) { line in
                        let distance = lyricDistance(to: line.id)
                        let isCurrent = distance == 0
                        Button {
                            if let start = line.start, player.duration > 0 {
                                player.seek(toProgress: start / player.duration)
                            }
                        } label: {
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: lyricSize, weight: .bold))
                                .foregroundStyle(.white.opacity(isCurrent ? 1 : max(0.22, 0.5 - Double(distance) * 0.06)))
                                // Apple's signature touch: lines fall out of
                                // focus the further they are from the one being
                                // sung, so your eye is pulled to the right place.
                                .blur(radius: isCurrent ? 0 : min(4.5, Double(distance) * 1.1))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(UltrafinButtonStyle(focusScale: 1.0, lift: false))
                        .id(line.id)
                        .animation(.smooth(duration: 0.35), value: player.currentLyricIndex)
                    }
                }
                .padding(.vertical, Spacing.xxl)
            }
            .mask(
                // Fade lyrics at both edges so they melt in and out of view.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88), .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            )
            .onChange(of: player.currentLyricIndex) { _, current in
                guard let current else { return }
                // Sit the active line a little above centre, the way Apple does,
                // so you can read ahead rather than only behind.
                withAnimation(.smooth(duration: 0.5)) {
                    proxy.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.38))
                }
            }
        }
    }

    /// How many lines this one sits from the line currently being sung — drives
    /// how far out of focus it falls. Lines before the first sung line are
    /// treated as one step away so the opening verse isn't fully blurred.
    private func lyricDistance(to id: Int) -> Int {
        guard let current = player.currentLyricIndex else { return 1 }
        return abs(id - current)
    }

    private var queueStage: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { position, track in
                        Button {
                            player.jump(to: track)
                        } label: {
                            TrackRow(track: track,
                                     position: position + 1,
                                     isCurrent: player.currentTrack?.id == track.id,
                                     showsArt: true)
                        }
                        .buttonStyle(UltrafinButtonStyle(focusScale: 1.01, lift: false))
                        .id(track.id)
                    }
                }
            }
            .onAppear {
                if let current = player.currentTrack?.id { proxy.scrollTo(current, anchor: .center) }
            }
        }
    }

    // MARK: - Info + transport

    #if os(iOS)
    /// Title and artist on the left, heart and "…" on the right — Apple Music's
    /// info row. The artist and album names are links to their pages.
    private var infoRow: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.currentTrack?.name ?? "—")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if player.currentTrack?.isExplicit == true {
                        ExplicitBadge(size: 13)
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize()
                    }
                }
                creditLine
            }
            // Take what's left after the buttons, and no more — without this the
            // text column reports its full ideal width and widens the whole row.
            .frame(maxWidth: .infinity, alignment: .leading)

            // The buttons keep their size; only the text gives way.
            roundControl(isFavorite ? "heart.fill" : "heart",
                         label: "Favorite",
                         tint: isFavorite ? .red : .white) { toggleFavorite() }
                .fixedSize()
            moreMenu
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }

    /// The header shown while lyrics or the queue own the screen: the cover as a
    /// thumbnail, the song beside it, heart and "…" still to hand.
    private var compactHeader: some View {
        HStack(spacing: Spacing.md) {
            RemoteImage(url: player.currentTrack.flatMap { player.artworkURL(for: $0, maxWidth: 200) })
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(player.currentTrack?.name ?? "—")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let artist = player.currentTrack?.artistText {
                    Text(artist)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            roundControl(isFavorite ? "heart.fill" : "heart",
                         label: "Favorite",
                         tint: isFavorite ? .red : .white) { toggleFavorite() }
            moreMenu
        }
        .transition(.opacity)
    }

    /// Just the artist, tappable — Apple shows the artist alone here. The album
    /// name made the line long and busy; it lives in the "…" menu instead.
    @ViewBuilder
    private var creditLine: some View {
        let track = player.currentTrack
        Button {
            open(track?.artistDestination)
        } label: {
            Text(track?.artistText ?? " ")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(track?.artistDestination == nil)
    }

    /// The "…" menu: album, artist, and queue actions.
    private var moreMenu: some View {
        Menu {
            if let album = player.currentTrack?.albumDestination {
                Button { open(album) } label: {
                    Label("Go to Album", systemImage: "square.stack")
                }
            }
            if let artist = player.currentTrack?.artistDestination {
                Button { open(artist) } label: {
                    Label("Go to Artist", systemImage: "music.mic")
                }
            }
            Divider()
            Button { player.toggleShuffle() } label: {
                Label(player.shuffleOn ? "Shuffle Off" : "Shuffle", systemImage: "shuffle")
            }
            Button { player.cycleRepeat() } label: {
                Label(repeatLabel, systemImage: player.repeatMode.icon)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.16), in: Circle())
        }
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: "Repeat"
        case .all: "Repeat One"
        case .one: "Repeat Off"
        }
    }

    private func roundControl(_ icon: String, label: String, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.selection)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.16), in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Dismiss the player, then hand the destination to the app so it opens in
    /// the Music tab's own navigation stack.
    private func open(_ item: MediaItem?) {
        guard let item, let onOpen else { return }
        Haptics.play(.light)
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            onOpen(item)
        }
    }

    private var isFavorite: Bool {
        favoriteOverride ?? (player.currentTrack?.userData?.isFavorite ?? false)
    }

    private func toggleFavorite() {
        guard let track = player.currentTrack, let source = player.activeSource else { return }
        let next = !isFavorite
        favoriteOverride = next
        Task { await source.setFavorite(itemID: track.id, isFavorite: next) }
    }

    /// The system volume slider, flanked by speaker glyphs. The slider is a
    /// UIKit view with no intrinsic width, so it's given the row's remaining
    /// space explicitly rather than being left to claim whatever it likes.
    private var volumeRow: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize()
            SystemVolumeSlider()
                .frame(maxWidth: .infinity)
                .frame(height: 28)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }
    #endif

    #if os(tvOS)
    private var trackInfo: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                if player.currentTrack?.isExplicit == true {
                    ExplicitBadge(size: titleSize * 0.72)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text(player.currentTrack?.name ?? "—")
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(artistLine)
                .font(.system(size: titleSize * 0.68, weight: .semibold, design: .rounded))
                .foregroundStyle(artColor?.shade(brightness: 1.15, saturation: 0.9) ?? settings.theme.accent.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    /// "Artist — Album" when both exist, so the player carries more detail.
    private var artistLine: String {
        let artist = player.currentTrack?.artistText
        let album = player.currentTrack?.album
        switch (artist, album) {
        case let (a?, b?) where !a.isEmpty && !b.isEmpty && a != b: return "\(a) — \(b)"
        case let (a?, _) where !a.isEmpty: return a
        case let (_, b?) where !b.isEmpty: return b
        default: return " "
        }
    }
    #endif

    private var scrubber: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                let progress = (isScrubbing ? scrubValue : player.progress).clamped01Music()
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white.opacity(0.9)).frame(width: width * progress)
                }
                .frame(height: isScrubbing ? 10 : 6)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                #if os(iOS)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            scrubValue = (value.location.x / width).clamped01Music()
                        }
                        .onEnded { value in
                            player.seek(toProgress: (value.location.x / width).clamped01Music())
                            isScrubbing = false
                        }
                )
                #endif
            }
            .frame(height: 24)
            .animation(.smooth(duration: 0.18), value: isScrubbing)

            HStack {
                Text(timeText(isScrubbing ? scrubValue * player.duration : player.currentTime))
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: Spacing.md)
                Text("-" + timeText(max(0, player.duration - (isScrubbing ? scrubValue * player.duration : player.currentTime))))
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var transport: some View {
        HStack(spacing: transportSpacing) {
            transportButton("backward.fill", size: sideButtonSize) { player.previous() }
            transportButton(player.isPlaying ? "pause.fill" : "play.fill", size: playButtonSize) {
                player.togglePlayPause()
            }
            transportButton("forward.fill", size: sideButtonSize) { player.next() }
        }
        .frame(maxWidth: .infinity)
    }

    private func transportButton(_ icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: size * 2, height: size * 2)
                .contentShape(Circle())
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.2, lift: false))
    }

    /// Lyrics · AirPlay · Queue, evenly spread. Shuffle and repeat live in the
    /// "…" menu on iOS, the way Apple Music arranges them; tvOS keeps them here
    /// since it has no menu affordance.
    /// Fixed-size controls separated by Spacers. Deliberately NOT
    /// `.frame(maxWidth: .infinity)` per item: AVRoutePickerView is a UIKit view
    /// with no intrinsic size, and a flexible frame lets it claim far more width
    /// than it needs — which pushes the outer controls past the screen edge.
    private var bottomBar: some View {
        HStack(spacing: 0) {
            #if os(tvOS)
            toggleChip(icon: "shuffle", active: player.shuffleOn) { player.toggleShuffle() }
            Spacer(minLength: 0)
            #endif

            toggleChip(icon: "quote.bubble", active: stage == .lyrics) {
                stage = stage == .lyrics ? .art : .lyrics
            }

            Spacer(minLength: 0)

            #if os(iOS)
            AirPlayButton()
                .frame(width: chipSize * 2.2, height: chipSize * 2.2)
                .fixedSize()
            Spacer(minLength: 0)
            #endif

            toggleChip(icon: "list.bullet", active: stage == .queue) {
                stage = stage == .queue ? .art : .queue
            }

            #if os(tvOS)
            Spacer(minLength: 0)
            toggleChip(icon: player.repeatMode.icon, active: player.repeatMode != .off) {
                player.cycleRepeat()
            }
            #endif
        }
        .frame(maxWidth: .infinity)
        #if os(iOS)
        // Apple insets this row well inside the content margins rather than
        // pinning the outer icons to the edges.
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.xs)
        #endif
    }

    private func toggleChip(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.selection)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: chipSize, weight: .semibold))
                // Active reads as a filled chip with a dark glyph, like Apple's
                // lyrics button when lyrics are showing.
                .foregroundStyle(active ? .black : .white.opacity(0.75))
                .frame(width: chipSize * 2.2, height: chipSize * 2.2)
                .background {
                    if active { Circle().fill(.white.opacity(0.92)) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.15, lift: false))
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Metrics

    private var titleSize: CGFloat {
        #if os(tvOS)
        34
        #else
        isLandscapePhone ? 18 : 20
        #endif
    }
    private var lyricSize: CGFloat {
        #if os(tvOS)
        40
        #else
        26
        #endif
    }
    private var lyricSpacing: CGFloat {
        #if os(tvOS)
        Spacing.lg
        #else
        Spacing.md
        #endif
    }
    private var playButtonSize: CGFloat {
        #if os(tvOS)
        44
        #else
        isLandscapePhone ? 26 : 33
        #endif
    }
    private var sideButtonSize: CGFloat {
        #if os(tvOS)
        30
        #else
        isLandscapePhone ? 19 : 26
        #endif
    }
    private var transportSpacing: CGFloat {
        #if os(tvOS)
        Spacing.xxl
        #else
        isLandscapePhone ? Spacing.md : Spacing.xl
        #endif
    }
    private var chipSize: CGFloat {
        #if os(tvOS)
        24
        #else
        isLandscapePhone ? 14 : 15
        #endif
    }
    private var edgePadding: CGFloat {
        #if os(tvOS)
        80
        #else
        isLandscapePhone ? Spacing.xl : 28
        #endif
    }
}

#if os(iOS)
/// The system AirPlay route picker, tinted for the dark player.
private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor.white.withAlphaComponent(0.7)
        view.activeTintColor = .white
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// The real system volume control (MPVolumeView), so dragging it moves device
/// volume exactly as Apple Music's slider does — a plain SwiftUI Slider can't
/// drive output volume.
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.tintColor = UIColor.white.withAlphaComponent(0.9)
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
#endif

private extension Double {
    func clamped01Music() -> Double { Swift.max(0, Swift.min(1, self)) }
}
