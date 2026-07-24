import SwiftUI
import AVKit

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

    /// What fills the center stage.
    private enum Stage { case art, lyrics, queue }
    @State private var stage: Stage = .art
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    /// Slow scale breath on the center carousel card while music plays.
    @State private var breathing = false
    /// The color sampled from the current record — drives the Apple Music wash.
    @State private var artColor: ArtworkColor?

    /// True on an iPhone held in landscape — the carousel becomes the stage.
    private var isLandscapePhone: Bool {
        #if os(iOS)
        vSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        ZStack {
            backdrop
            GeometryReader { geo in
                layout(in: geo.size)
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.smooth(duration: 0.35), value: stage)
        .task(id: player.currentTrack?.id) {
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
        VStack(spacing: Spacing.lg) {
            centerStage(maxSide: 560)
                .frame(maxHeight: .infinity)
            trackInfo
            scrubber
            transport
            bottomBar
        }
        .padding(.horizontal, 80)
        .padding(.vertical, Spacing.xl)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    #if os(iOS)
    /// Portrait iPhone: a vertical stack with the art sized to a fraction of the
    /// height so the transport can never be pushed off the bottom.
    private func portraitLayout(in size: CGSize) -> some View {
        let artMax = min(size.width - edgePadding * 2, size.height * 0.42)
        return VStack(spacing: Spacing.md) {
            grabber
            centerStage(maxSide: artMax)
                .frame(maxHeight: .infinity)
            trackInfo
            scrubber
            transport
                .padding(.vertical, Spacing.xs)
            bottomBar
        }
        .padding(.horizontal, edgePadding)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Landscape iPhone: the carousel on the left, controls stacked on the
    /// right — the standard landscape music layout, and where the coverflow
    /// lives on the phone.
    private func landscapePhoneLayout(in size: CGSize) -> some View {
        let artMax = min(size.width * 0.42, size.height * 0.62)
        return HStack(spacing: Spacing.xl) {
            centerStage(maxSide: artMax)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: Spacing.sm) {
                HStack {
                    grabber
                    Spacer()
                }
                Spacer(minLength: 0)
                trackInfo
                scrubber
                transport
                bottomBar
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, edgePadding)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var grabber: some View {
        #if os(iOS)
        Button { dismiss() } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 40, height: 32)
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
            // Side cards first, center drawn last so it layers on top.
            ForEach([-2, -1, 2, 1, 0], id: \.self) { offset in
                if let track = queueTrack(at: offset) {
                    carouselCard(track: track, offset: offset, side: side)
                        // Identity follows the queue slot so a track change
                        // animates cards BETWEEN positions (the glide), not a
                        // crossfade-in-place.
                        .id(track.id)
                }
            }
        }
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
        .offset(x: CGFloat(offset) * baseSide * 0.60)
        .opacity(isCenter ? 1 : max(0.2, 0.5 - Double(abs(offset) - 1) * 0.18))
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
                        let isCurrent = player.currentLyricIndex == line.id
                        Button {
                            if let start = line.start, player.duration > 0 {
                                player.seek(toProgress: start / player.duration)
                            }
                        } label: {
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: lyricSize, weight: .bold, design: .rounded))
                                .foregroundStyle(isCurrent ? .white : .white.opacity(0.35))
                                .scaleEffect(isCurrent ? 1.0 : 0.92, anchor: .leading)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(UltrafinButtonStyle(focusScale: 1.0, lift: false))
                        .id(line.id)
                        .animation(.smooth(duration: 0.3), value: player.currentLyricIndex)
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
                withAnimation(.smooth(duration: 0.45)) {
                    proxy.scrollTo(current, anchor: .center)
                }
            }
        }
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

    private var bottomBar: some View {
        HStack {
            toggleChip(icon: "shuffle", active: player.shuffleOn) { player.toggleShuffle() }
            Spacer()
            toggleChip(icon: "quote.bubble", active: stage == .lyrics) {
                stage = stage == .lyrics ? .art : .lyrics
            }
            #if os(iOS)
            AirPlayButton()
                .frame(width: 44, height: 44)
            #endif
            toggleChip(icon: "list.bullet", active: stage == .queue) {
                stage = stage == .queue ? .art : .queue
            }
            Spacer()
            toggleChip(icon: player.repeatMode.icon, active: player.repeatMode != .off) {
                player.cycleRepeat()
            }
        }
    }

    private func toggleChip(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.selection)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: chipSize, weight: .semibold))
                .foregroundStyle(active ? settings.theme.accent.color : .white.opacity(0.7))
                .frame(width: chipSize * 2.4, height: chipSize * 2.4)
                .background {
                    if active { Circle().fill(.white.opacity(0.12)) }
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
        isLandscapePhone ? 28 : 34
        #endif
    }
    private var sideButtonSize: CGFloat {
        #if os(tvOS)
        30
        #else
        isLandscapePhone ? 20 : 24
        #endif
    }
    private var transportSpacing: CGFloat {
        #if os(tvOS)
        Spacing.xxl
        #else
        isLandscapePhone ? Spacing.lg : Spacing.xl
        #endif
    }
    private var chipSize: CGFloat {
        #if os(tvOS)
        24
        #else
        isLandscapePhone ? 15 : 17
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
#endif

private extension Double {
    func clamped01Music() -> Double { Swift.max(0, Swift.min(1, self)) }
}
