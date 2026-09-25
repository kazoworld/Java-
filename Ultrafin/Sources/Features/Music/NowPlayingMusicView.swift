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
    /// The cover melted to a 3×3 grid of its colours — the living backdrop.
    @State private var palette: [ArtworkColor] = []
    /// Local heart state so the tap lands instantly; cleared on track change.
    @State private var favoriteOverride: Bool?
    /// Taps on the skip buttons, so each one can nudge its arrows forward.
    @State private var nextTaps = 0
    @State private var previousTaps = 0
    /// Set while the reader drags the lyrics themselves: auto-follow stands
    /// down and every line comes into focus until they've been still a moment.
    @State private var isBrowsingLyrics = false
    @State private var browsingSince: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    /// The cover flies between the stage and the compact header rather than
    /// cross-fading — the one object on screen should visibly be one object.
    @Namespace private var coverSpace
    /// How far the cover is being dragged sideways, already rubber-banded.
    @State private var artDrag: CGFloat = 0
    @State private var isAdjustingVolume = false
    @State private var volume = SystemVolume.shared
    #endif

    #if os(tvOS)
    /// Which control the remote is on.
    ///
    /// These are real focus targets. The player used to be one big
    /// `.focusable()` container, which meant it swallowed focus so no button
    /// inside could ever be reached, and its move handler ate up and down as
    /// well — the screen you could only look at.
    enum TVControl: Hashable { case art, scrub, playPause }
    @FocusState private var tvFocus: TVControl?
    #endif

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
        .environment(\.colorScheme, .dark)
        .animation(.spring(duration: 0.5, bounce: 0.14), value: stage)
        .task(id: player.currentTrack?.id) {
            favoriteOverride = nil // the new song has its own heart state
            prefetchNeighbours()
            guard let track = player.currentTrack,
                  let url = player.artworkURL(for: track, maxWidth: 240) else { return }
            async let vivid = ImageColor.vibrant(from: url)
            async let grid = ImageColor.palette(from: url)
            let (color, colors) = await (vivid, grid)
            guard !Task.isCancelled else { return }
            // Both land together, so the backdrop turns over once, not twice.
            artColor = color
            palette = colors
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
        .musicScreensaver(player: player, eligible: true)
        #endif
    }

    #if os(iOS)
    /// A horizontal flick to change track, attached to the ARTWORK only.
    ///
    /// This used to cover the whole player and also handle a downward pull to
    /// dismiss. Now that the player is a sheet, the system owns the downward
    /// pull — and a gesture spanning the whole view would capture the touch
    /// before the sheet ever saw it, which is exactly the kind of fight that
    /// makes a dismissal feel like it's sticking. Only acts on a clearly
    /// sideways drag, so a vertical swipe starting on the cover still dismisses.
    ///
    /// The cover follows the finger — with growing resistance, and a slight
    /// turn into the room like a record on a shelf — so the gesture is
    /// something you feel rather than a guess that either fires or doesn't.
    private var artworkSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > abs(dy) * 1.4 else { return }
                artDrag = ElasticSlider.rubberBand(dx, limit: 80)
            }
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                let sideways = abs(dx) > abs(dy) * 1.6
                let far = abs(dx) > 60 || abs(value.predictedEndTranslation.width) > 180
                if sideways && far {
                    Haptics.play(.light)
                    if dx < 0 { player.next() } else { player.previous() }
                }
                withAnimation(.spring(duration: 0.55, bounce: 0.32)) { artDrag = 0 }
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
        let stageHeight = size.height * 0.46
        let side = max(200, min(size.width * 0.22, stageHeight / 1.45))
        return VStack(spacing: size.height * 0.022) {
            Group {
                if stage == .art {
                    carouselStage(side: side)
                        .frame(height: side * 1.45)
                        // Focusable in its own right, so left/right steps through
                        // the queue without hunting for the transport buttons.
                        .focusable()
                        .focused($tvFocus, equals: .art)
                        .onMoveCommand { direction in
                            switch direction {
                            case .left: player.previous()
                            case .right: player.next()
                            // Handled explicitly rather than left to the focus
                            // engine: onMoveCommand consumes the event, so
                            // without this the art would trap the remote.
                            case .down: tvFocus = .scrub
                            default: break
                            }
                        }
                } else {
                    // Lyrics and the queue take the stage when their chip is on.
                    centerStage(maxSide: side)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity)

            if stage == .art { trackInfo }
            tvScrubber
            transport.focusSection()
            bottomBar.focusSection()
        }
        // Stay inside the TV's title-safe area, proportionally.
        .padding(.horizontal, size.width * 0.08)
        .padding(.vertical, size.height * 0.04)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Something must own focus the moment the player appears, or Menu has
        // nothing to bubble out of and the whole screen goes inert.
        .defaultFocus($tvFocus, .playPause)
        .onExitCommand { dismiss() }
    }

    /// The scrub bar as a real focus target: left and right move the playhead,
    /// up and down hand off to the neighbouring row.
    private var tvScrubber: some View {
        scrubber
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(tvFocus == .scrub ? 0.16 : 0))
            )
            .scaleEffect(tvFocus == .scrub ? 1.015 : 1)
            .animation(.smooth(duration: 0.2), value: tvFocus)
            .focusable()
            .focused($tvFocus, equals: .scrub)
            .onMoveCommand { direction in
                switch direction {
                case .left: nudge(by: -10)
                case .right: nudge(by: 10)
                case .up: tvFocus = stage == .art ? .art : .scrub
                case .down: tvFocus = .playPause
                default: break
                }
            }
    }

    /// Move the playhead by a few seconds — left/right while the bar has focus.
    private func nudge(by seconds: Double) {
        guard player.duration > 0 else { return }
        let target = min(max(0, player.currentTime + seconds), player.duration)
        player.seek(toProgress: target / player.duration)
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
                // A measured gap under the cover — Apple's is about 5% of the
                // screen. The slack is then shared BETWEEN the control rows
                // below rather than dumped here, which is what left a hole
                // under the artwork and crushed the controls to the bottom.
                Spacer(minLength: 0).frame(height: size.height * 0.045)
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

            VStack(spacing: 0) {
                if stage == .art { infoRow }
                Spacer(minLength: Spacing.sm)
                scrubber
                Spacer(minLength: Spacing.sm)
                transport
                Spacer(minLength: Spacing.sm)
                volumeRow
                Spacer(minLength: Spacing.sm)
                bottomBar
            }
            .frame(width: contentWidth)
            .frame(maxHeight: .infinity)
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
        let artColumn = usable * 0.48
        let controlColumn = usable - artColumn - Spacing.xl
        // The card is 1.45× its art once the reflection counts, and the stage
        // needs room for both neighbours. Sizing off BOTH constraints is what
        // stops the cover being cropped top-and-bottom and the next record
        // spilling over the controls.
        let side = max(80, min(artColumn / 1.75, size.height * 0.58))
        return HStack(spacing: Spacing.xl) {
            Group {
                if stage == .art {
                    carouselStage(side: side, spread: 0.52, stageWidth: artColumn)
                } else {
                    // Lyrics / queue take the same column so the controls stay put.
                    centerStage(maxSide: side)
                }
            }
            .frame(width: artColumn)
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: Spacing.md) {
                Spacer(minLength: 0)
                infoRow
                // No scrubber here: the carousel IS the navigation in landscape
                // — swipe or tap through records — so a duration bar just
                // crowds a short screen. Portrait and tvOS keep theirs.
                transport
                bottomBar
                Spacer(minLength: 0)
            }
            .frame(width: max(0, controlColumn))
        }
        .overlay(alignment: .top) { grabber }
        .padding(.vertical, Spacing.sm)
        .frame(width: size.width, alignment: .center)
        .frame(maxHeight: .infinity)
    }
    #endif

    // MARK: - Backdrop

    /// The record's color poured into a soft, slowly-drifting wash with the
    /// blurred art underneath — the Apple Music look, with a hint of the cover's
    /// own color even on near-monochrome art.
    private var backdrop: some View {
        LivingBackdrop(palette: palette, fallback: artColor, isAnimating: player.isPlaying)
    }

    /// Warm the covers either side of the playhead, so a skip dissolves
    /// straight into the next record instead of waiting on the network.
    private func prefetchNeighbours() {
        for offset in [1, -1] {
            guard let track = queueTrack(at: offset),
                  let url = player.artworkURL(for: track) else { continue }
            Task.detached(priority: .utility) { _ = await ImageLoader.shared.image(for: url) }
        }
    }

    /// The sheet handle — a soft pill, as on Apple Music's player.
    private var grabber: some View {
        #if os(iOS)
        Button { dismiss() } label: {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 38, height: 5)
                .frame(width: 90, height: A11y.minimumTarget)
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
        let playing = player.isPlaying
        return RemoteImage(url: player.currentTrack.flatMap { player.artworkURL(for: $0) },
                           crossfades: true)
            .accessibilityHidden(true)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.06, style: .continuous))
            .specularRim(cornerRadius: side * 0.06, intensity: 0.8)
            #if os(iOS)
            .matchedGeometryEffect(id: "cover", in: coverSpace)
            #endif
            .frame(width: side, height: side)
            // The shadow sinks with the record: a playing cover floats high over
            // its own long shadow; a paused one settles close to the page.
            .shadow(color: .black.opacity(playing ? 0.5 : 0.3),
                    radius: playing ? 40 : 18, y: playing ? 24 : 10)
            // The Apple Music breath: full size while playing, settles back when
            // paused.
            .scaleEffect(playing ? 1 : 0.82)
            .animation(.spring(duration: 0.6, bounce: 0.3), value: playing)
            #if os(iOS)
            .rotation3DEffect(.degrees(Double(artDrag) * 0.12), axis: (x: 0, y: 1, z: 0),
                              perspective: 0.6)
            .offset(x: artDrag)
            #endif
            .frame(maxWidth: .infinity)
            #if os(iOS)
            // Sideways on the cover changes track; everything else the sheet
            // hears, so a downward pull from here still dismisses.
            .simultaneousGesture(artworkSwipe)
            #endif
    }

    /// A living coverflow of the queue. The current record stands front and
    /// center — breathing gently while it plays, mirrored in a fading reflection
    /// — with its neighbors receding into the room on either side. Changing
    /// tracks glides the whole shelf across on a spring.
    private func carouselStage(side: CGFloat, spread: CGFloat = 0.66,
                               stageWidth: CGFloat? = nil) -> some View {
        ZStack {
            // Three records: the one playing, and one either side. Neighbours
            // first so the centre draws on top.
            ForEach([-1, 1, 0], id: \.self) { offset in
                if let track = queueTrack(at: offset) {
                    carouselCard(track: track, offset: offset, side: side, spread: spread)
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
        // Callers that live in a narrow column pass their own width and the
        // neighbours tuck in closer.
        .frame(width: stageWidth ?? side * 2.5, height: side * 1.45)
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .calmAnimation(.spring(duration: 0.75, bounce: 0.16), value: player.index)
        .onAppear {
            // Reduce Motion: the cards still glide between positions when the
            // track changes, but the endless in-and-out breath stops. Continuous
            // ambient movement is the thing that setting is really about.
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }

    private func queueTrack(at offset: Int) -> MediaItem? {
        let i = player.index + offset
        guard player.queue.indices.contains(i) else { return nil }
        return player.queue[i].track
    }

    private func carouselCard(track: MediaItem, offset: Int, side baseSide: CGFloat,
                              spread: CGFloat = 0.66) -> some View {
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
        .offset(x: CGFloat(offset) * baseSide * spread)
        .opacity(isCenter ? 1 : 0.45)
        .zIndex(isCenter ? 10 : Double(5 - abs(offset)))
        // The center record breathes while the music plays.
        .scaleEffect(isCenter && player.isPlaying ? (breathing ? 1.015 : 0.995) : (isCenter ? 0.96 : 1))
        .animation(isCenter ? .spring(duration: 0.5, bounce: 0.25) : nil, value: player.isPlaying)
    }

    private var lyricsStage: some View {
        let synced = player.lyrics.contains { $0.start != nil }
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: lyricSpacing) {
                    if player.lyrics.isEmpty {
                        Text("No lyrics for this song.")
                            .font(.system(size: lyricSize * 0.8))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.top, Spacing.xxl)
                    }
                    // A long intro gets the waiting dots too, so the page isn't
                    // just a blurred verse sitting there until the singer comes in.
                    if synced, let lead = player.lyrics.first(where: { $0.start != nil })?.start,
                       lead > 4 {
                        interlude(from: 0, to: lead, isActive: player.currentLyricIndex == nil)
                            .id(Self.introLineID)
                    }
                    ForEach(player.lyrics) { line in
                        lyricLine(line, synced: synced)
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
            // Reading ahead (or back) is allowed: the moment a finger moves the
            // lyrics, following stops and the blur lifts so any line can be read.
            .onScrollPhaseChange { _, phase in
                guard synced, phase == .interacting else { return }
                browsingSince = .now
                if !isBrowsingLyrics {
                    withAnimation(.smooth(duration: 0.3)) { isBrowsingLyrics = true }
                }
            }
            // ...and a few seconds after they let go, the page drifts back to
            // the line being sung.
            .task(id: browsingSince) {
                guard isBrowsingLyrics else { return }
                try? await Task.sleep(for: .seconds(3.5))
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.5)) { isBrowsingLyrics = false }
                withAnimation(.spring(duration: 0.9, bounce: 0.1)) {
                    proxy.scrollTo(player.currentLyricIndex ?? Self.introLineID, anchor: lyricAnchor)
                }
            }
            .onChange(of: player.currentLyricIndex) { _, current in
                guard let current, !isBrowsingLyrics else { return }
                withAnimation(.spring(duration: 0.8, bounce: 0.12)) {
                    proxy.scrollTo(current, anchor: lyricAnchor)
                }
            }
            .onAppear {
                // Open on the line being sung, not the top of the song.
                guard let current = player.currentLyricIndex else { return }
                proxy.scrollTo(current, anchor: lyricAnchor)
            }
        }
    }

    /// Scroll id for the intro's waiting dots (lyric ids start at zero).
    private static let introLineID = -1

    /// The active line sits a little above centre, the way Apple does, so you
    /// can read ahead rather than only behind.
    private var lyricAnchor: UnitPoint { UnitPoint(x: 0, y: 0.36) }

    @ViewBuilder
    private func lyricLine(_ line: LyricLine, synced: Bool) -> some View {
        let distance = lyricDistance(to: line.id)
        let isCurrent = synced && distance == 0
        // Plain (unsynced) lyrics have no "current" line to focus on, so they
        // read as a page — every line clear, none dimmed into a blur.
        let clear = !synced || isBrowsingLyrics
        let isGap = line.text.trimmingCharacters(in: .whitespaces).isEmpty
        Button {
            guard let start = line.start, player.duration > 0 else { return }
            Haptics.play(.selection)
            player.seek(toProgress: start / player.duration)
            browsingSince = nil
            isBrowsingLyrics = false
        } label: {
            if isGap, synced, let start = line.start {
                interlude(from: start, to: nextLyricStart(after: line) ?? start + 8,
                          isActive: isCurrent)
            } else {
                Text(isGap ? "♪" : line.text)
                    .font(.system(size: lyricSize, weight: .bold))
                    .foregroundStyle(.white.opacity(lyricOpacity(isCurrent: isCurrent,
                                                                 distance: distance,
                                                                 synced: synced)))
                    // Apple's signature touch: lines fall out of focus the
                    // further they are from the one being sung, so your eye is
                    // pulled to the right place.
                    .blur(radius: isCurrent || clear ? 0 : min(4, Double(distance) * 1.0))
                    // The sung line stands a touch larger than its neighbours.
                    .scaleEffect(isCurrent || !synced ? 1 : 0.955, anchor: .leading)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.0, lift: false))
        .id(line.id)
        // Lines below the new one follow a beat behind each other, so the
        // change ripples down the page instead of snapping all at once.
        .animation(.spring(duration: 0.6, bounce: 0.18).delay(lyricStagger(for: line.id)),
                   value: player.currentLyricIndex)
    }

    private func lyricOpacity(isCurrent: Bool, distance: Int, synced: Bool) -> Double {
        if !synced { return 0.88 }
        if isCurrent { return 1 }
        if isBrowsingLyrics { return 0.62 }
        return max(0.24, 0.52 - Double(distance) * 0.06)
    }

    private func lyricStagger(for id: Int) -> Double {
        guard !reduceMotion, let current = player.currentLyricIndex else { return 0 }
        return Double(min(6, max(0, id - current))) * 0.035
    }

    private func nextLyricStart(after line: LyricLine) -> Double? {
        player.lyrics.first(where: { $0.id > line.id && $0.start != nil })?.start
    }

    /// The waiting dots across an instrumental gap, filling in step with the
    /// music. Only the active one runs a clock.
    private func interlude(from start: Double, to end: Double, isActive: Bool) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive || !player.isPlaying)) { context in
            let now = player.estimatedTime(at: context.date)
            let progress = end > start ? (now - start) / (end - start) : 0
            InterludeDots(progress: isActive ? progress : 0, isActive: isActive,
                          size: lyricSize * 0.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, lyricSize * 0.3)
    }

    /// How many lines this one sits from the line currently being sung — drives
    /// how far out of focus it falls. Lines before the first sung line are
    /// treated as one step away so the opening verse isn't fully blurred.
    private func lyricDistance(to id: Int) -> Int {
        guard let current = player.currentLyricIndex else { return 1 }
        return abs(id - current)
    }

    /// The queue, Spotify's way: what's playing, then the songs you added by
    /// hand, then the rest of wherever this came from. Both up-next blocks drag
    /// to reorder and swipe to remove.
    private var queueStage: some View {
        #if os(tvOS)
        // No edit mode on the TV — the remote can't drag. Focus a row and click
        // to jump to it.
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { position, entry in
                    Button { player.jump(to: entry) } label: {
                        TrackRow(track: entry.track,
                                 position: position + 1,
                                 isCurrent: entry.id == player.currentEntry?.id,
                                 showsArt: true)
                    }
                    .buttonStyle(UltrafinButtonStyle(focusScale: 1.01, lift: false))
                }
            }
        }
        #else
        VStack(spacing: Spacing.sm) {
            queueModes
            queueList
        }
        #endif
    }

    #if os(iOS)
    /// Shuffle and Repeat as two wide toggles above the queue — where Apple
    /// Music puts them, right beside the order they change, so you can watch
    /// the list reshuffle under your thumb.
    private var queueModes: some View {
        HStack(spacing: Spacing.sm) {
            modeToggle("Shuffle", icon: "shuffle", isOn: player.shuffleOn) {
                player.toggleShuffle()
            }
            modeToggle("Repeat", icon: player.repeatMode.icon, isOn: player.repeatMode != .off) {
                player.cycleRepeat()
            }
            .accessibilityValue(repeatSpokenValue)
        }
    }

    private var repeatSpokenValue: String {
        switch player.repeatMode {
        case .off: "Off"
        case .all: "All"
        case .one: "One song"
        }
    }

    private func modeToggle(_ title: String, icon: String, isOn: Bool,
                            action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.selection)
            withAnimation(.spring(duration: 0.45, bounce: 0.18)) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                // On, the glyph takes the record's own colour against the lit
                // pill — the same trick Apple uses to keep the toggles part of
                // the player rather than generic chrome.
                .foregroundStyle(isOn ? (artColor?.shade(brightness: 0.55, saturation: 1.1) ?? .black)
                                      : Color.white.opacity(0.85))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(isOn ? 0.9 : 0.12))
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1, pressScale: 0.95, lift: false))
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private var queueList: some View {
        List {
            if let current = player.currentEntry {
                Section {
                    QueueRow(entry: current, isCurrent: true) {}
                        .queueRowChrome()
                        // The song that's playing is not something to drag or
                        // delete — Next is what moves past it.
                        .moveDisabled(true)
                        .deleteDisabled(true)
                } header: {
                    queueHeader("Now Playing") { EmptyView() }
                }
            }

            if !player.manualUpNext.isEmpty {
                Section {
                    ForEach(player.manualUpNext) { entry in
                        QueueRow(entry: entry, isCurrent: false) { player.jump(to: entry) }
                            .queueRowChrome()
                    }
                    .onMove { player.moveManual(from: $0, to: $1) }
                    .onDelete { offsets in
                        let doomed = offsets.map { player.manualUpNext[$0] }
                        withAnimation(.smooth(duration: 0.25)) {
                            for entry in doomed { player.remove(entry) }
                        }
                    }
                } header: {
                    queueHeader("Next in Queue") { clearQueueButton }
                }
            }

            if !player.contextUpNext.isEmpty {
                Section {
                    ForEach(player.contextUpNext) { entry in
                        QueueRow(entry: entry, isCurrent: false) { player.jump(to: entry) }
                            .queueRowChrome()
                    }
                    .onMove { player.moveContext(from: $0, to: $1) }
                    .onDelete { offsets in
                        let doomed = offsets.map { player.contextUpNext[$0] }
                        withAnimation(.smooth(duration: 0.25)) {
                            for entry in doomed { player.remove(entry) }
                        }
                    }
                } header: {
                    queueHeader(contextHeader) { EmptyView() }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        // Always-on edit mode so the drag handles are simply there, the way
        // Spotify's queue works — no "Edit" button to hunt for first.
        .environment(\.editMode, .constant(.active))
    }
    #endif

    #if os(iOS)
    /// "Next From: American Teen" — or a plain heading when the session didn't
    /// come from anywhere nameable.
    private var contextHeader: String {
        guard let title = player.contextTitle, !title.isEmpty else { return "Up Next" }
        return "Next From: \(title)"
    }

    private func queueHeader<Trailing: View>(_ title: String,
                                             @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: Spacing.sm)
            trailing()
        }
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: Spacing.md, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
    }

    private var clearQueueButton: some View {
        Button {
            Haptics.play(.selection)
            withAnimation(.smooth(duration: 0.25)) { player.clearUpNext() }
        } label: {
            Text("Clear")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - Info + transport

    #if os(iOS)
    /// Title and artist on the left, heart and "…" on the right — Apple Music's
    /// info row. The artist and album names are links to their pages.
    private var infoRow: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // A title too long for the row glides sideways to show the
                    // rest, rather than being cut off mid-word.
                    MarqueeText(text: player.currentTrack?.name ?? "—",
                                font: .system(size: 20, weight: .semibold))
                        .id(player.currentTrack?.id)
                        .transition(.opacity)
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
            // Deliberately NOT combined: the artist line is a link to their
            // page, and merging the column would make it unreachable.

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
            // Same URL as the big cover, so it's the cached picture that flies
            // up here — no reload mid-flight.
            RemoteImage(url: player.currentTrack.flatMap { player.artworkURL(for: $0) },
                        crossfades: true)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .matchedGeometryEffect(id: "cover", in: coverSpace)
                .frame(width: 52, height: 52)
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
            // Same size as the title; only the weight and the dimming separate
            // them, which is how Apple stacks the two lines.
            MarqueeText(text: track?.artistText ?? " ",
                        font: .system(size: 20, weight: .regular),
                        color: .white.opacity(0.68))
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
                .minimumHitTarget()
        }
        .accessibilityLabel("More options")
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
                .contentTransition(.symbolEffect(.replace))
                // The heart gives a little jump when it changes — the tap
                // landed, whichever way it went.
                .symbolEffect(.bounce, value: icon)
                .animation(.snappy(duration: 0.25), value: icon)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.16), in: Circle())
                .minimumHitTarget()
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

    /// Device volume on the same elastic bar as the scrubber, flanked by
    /// speaker glyphs: the right one fills its waves as the level rises, and
    /// each gives a small jump when you pin the volume against its end.
    private var volumeRow: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(isAdjustingVolume ? 0.9 : 0.5))
                .symbolEffect(.bounce.down, value: volume.level <= 0.001)
                .fixedSize()
            ElasticSlider(value: volume.level, isEditing: $isAdjustingVolume,
                          restingHeight: 6, activeHeight: 11,
                          onChange: { volume.set($0) })
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .accessibilityElement()
                .accessibilityLabel("Volume")
                .accessibilityValue("\(Int((volume.level * 100).rounded())) percent")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: volume.set(min(1, volume.level + 0.0625))
                    case .decrement: volume.set(max(0, volume.level - 0.0625))
                    @unknown default: break
                    }
                }
            Image(systemName: "speaker.wave.3.fill", variableValue: volume.level)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(isAdjustingVolume ? 0.9 : 0.5))
                .symbolEffect(.bounce.up, value: volume.level >= 0.999)
                .fixedSize()
        }
        .scaleEffect(x: isAdjustingVolume ? 1.02 : 1, y: 1)
        .animation(.spring(duration: 0.35, bounce: 0.3), value: isAdjustingVolume)
        .frame(maxWidth: .infinity)
        // The hidden system control this row drives — and the reason the
        // volume buttons move this bar instead of covering the art with a HUD.
        .background { SystemVolumeBridge().frame(width: 1, height: 1).allowsHitTesting(false) }
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
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(artistLine)
                .font(.system(size: titleSize * 0.68, weight: .semibold))
                .foregroundStyle(artColor?.shade(brightness: 1.15, saturation: 0.9) ?? settings.accent)
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
            scrubBar
                .frame(height: 24)
                // A hand-drawn bar is invisible to VoiceOver unless it says what
                // it is. As one adjustable element it reads its position aloud
                // and moves on a swipe, which is the only way to scrub without
                // sight.
                .accessibilityElement()
                .accessibilityLabel("Playback position")
                .accessibilityValue(scrubberSpokenValue)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: nudgePlayhead(15)
                    case .decrement: nudgePlayhead(-15)
                    @unknown default: break
                    }
                }

            HStack {
                Text(timeText(isScrubbing ? scrubValue * player.duration : player.currentTime))
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: Spacing.md)
                Text("-" + timeText(max(0, player.duration - (isScrubbing ? scrubValue * player.duration : player.currentTime))))
                    .lineLimit(1)
                    .fixedSize()
            }
            .accessibilityHidden(true) // the bar above speaks both times
            // Monospaced digits, NOT the monospaced typeface — the latter is a
            // visibly different font and only the numbers need to stop jittering.
            .font(.system(size: 13, weight: .medium).monospacedDigit())
            // The times brighten and step aside as the bar thickens under a
            // finger — they're what you're reading while you scrub.
            .foregroundStyle(.white.opacity(isScrubbing ? 0.95 : 0.62))
            .offset(y: isScrubbing ? 3 : 0)
            .animation(.spring(duration: 0.35, bounce: 0.3), value: isScrubbing)
        }
    }

    @ViewBuilder
    private var scrubBar: some View {
        #if os(iOS)
        ElasticSlider(value: player.progress, isEditing: $isScrubbing,
                      onChange: { scrubValue = $0 },
                      onCommit: { player.seek(toProgress: $0) })
        #else
        GeometryReader { geo in
            let progress = player.progress.clamped01Music()
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white.opacity(0.9)).frame(width: geo.size.width * progress)
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        #endif
    }

    /// "1 minute 21 seconds of 2 minutes 53 seconds" — spoken, not "1:21".
    private var scrubberSpokenValue: String {
        let elapsed = Duration.seconds(Int(player.currentTime))
        let total = Duration.seconds(Int(player.duration))
        let style = Duration.UnitsFormatStyle(allowedUnits: [.minutes, .seconds],
                                              width: .wide)
        return "\(elapsed.formatted(style)) of \(total.formatted(style))"
    }

    /// Nudge the playhead — the adjustable action VoiceOver drives with a swipe.
    private func nudgePlayhead(_ seconds: Double) {
        guard player.duration > 0 else { return }
        let target = min(max(0, player.currentTime + seconds), player.duration)
        player.seek(toProgress: target / player.duration)
    }

    private var transport: some View {
        HStack(spacing: transportSpacing) {
            transportButton("backward.fill", size: sideButtonSize, nudge: -1, taps: previousTaps) {
                previousTaps += 1
                player.previous()
            }
            playPauseButton
            transportButton("forward.fill", size: sideButtonSize, nudge: 1, taps: nextTaps) {
                nextTaps += 1
                player.next()
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Split out because on tvOS this is where focus lands when the player
    /// opens — the rest of the remote's navigation works outward from here.
    @ViewBuilder
    private var playPauseButton: some View {
        let button = transportButton(player.isPlaying ? "pause.fill" : "play.fill",
                                     size: playButtonSize) {
            player.togglePlayPause()
        }
        #if os(tvOS)
        button.focused($tvFocus, equals: .playPause)
        #else
        button
        #endif
    }

    /// One transport control. Play and pause morph into each other rather than
    /// swapping; the skip arrows lurch the way they point on each press, so a
    /// skip feels like a push rather than a switch being flipped.
    @ViewBuilder
    private func transportButton(_ icon: String, size: CGFloat, nudge: CGFloat = 0, taps: Int = 0,
                                 action: @escaping () -> Void) -> some View {
        let button = Button {
            Haptics.play(.light)
            action()
        } label: {
            Image(systemName: icon)
                // Regular, not heavy. These are already solid shapes — adding
                // weight on top thickens the silhouette and is a good part of
                // why the transport read as clunky next to Apple Music's.
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .animation(.snappy(duration: 0.28), value: icon)
                .keyframeAnimator(initialValue: CGFloat(0), trigger: taps) { content, x in
                    content.offset(x: x)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(nudge * size * 0.3, duration: 0.1)
                        SpringKeyframe(0, duration: 0.45, spring: .bouncy)
                    }
                }
                .frame(width: size * 1.7, height: size * 1.7)
                .contentShape(Circle())
        }
        #if os(iOS)
        button.buttonStyle(TransportButtonStyle())
        #else
        button.buttonStyle(UltrafinButtonStyle(focusScale: 1.2, lift: false))
        #endif
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
                .minimumHitTarget()
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
                .minimumHitTarget()
                .contentShape(Rectangle())
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
        isLandscapePhone ? 28 : 40
        #endif
    }
    private var sideButtonSize: CGFloat {
        #if os(tvOS)
        30
        #else
        isLandscapePhone ? 21 : 31
        #endif
    }
    /// Apple's transport sits far apart — the three controls span most of the
    /// width rather than huddling in the middle.
    private var transportSpacing: CGFloat {
        #if os(tvOS)
        Spacing.xxl
        #else
        isLandscapePhone ? Spacing.md : 40
        #endif
    }
    private var chipSize: CGFloat {
        #if os(tvOS)
        24
        #else
        isLandscapePhone ? 15 : 18
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

/// One song in the queue sheet: artwork, title, artist — and, for the song
/// that's playing, a live equalizer instead of a tap target.
struct QueueRow: View {
    let entry: QueueEntry
    let isCurrent: Bool
    let onTap: () -> Void

    private var player: MusicPlayer { .shared }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RemoteImage(url: player.artworkURL(for: entry.track, maxWidth: 160))
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    if isCurrent {
                        // The playing song dims its cover under a bar glyph, so
                        // the eye lands on it without needing a colour cue.
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.black.opacity(0.5))
                            .frame(width: 46, height: 46)
                        NowPlayingBars(isPlaying: player.isPlaying, color: .white, height: 16)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(entry.track.name)
                            .font(.system(size: 16, weight: isCurrent ? .semibold : .regular))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if entry.track.isExplicit { ExplicitBadge(size: 11) }
                    }
                    Text(entry.track.artistText ?? " ")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
    }
}

#if os(iOS)
extension View {
    /// Strips a queue row back to bare content: no separators, no fill, no
    /// inset — the list has to read as part of the player, not as Settings.
    ///
    /// iOS only: the queue is a plain focusable stack on tvOS, and
    /// `listRowSeparator` doesn't exist there at all.
    func queueRowChrome() -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
#endif

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
