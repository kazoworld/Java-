import SwiftUI
import AVKit

/// The full-screen music player, in the spirit of Apple Music: the album art
/// floats over its own blurred reflection, shrinking when paused and springing
/// back on play; lyrics scroll karaoke-style; the queue is one tap away.
struct NowPlayingMusicView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings

    @Bindable var player: MusicPlayer

    /// What fills the center stage.
    private enum Stage { case art, lyrics, queue }
    @State private var stage: Stage = .art
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: Spacing.lg) {
                grabber

                Group {
                    switch stage {
                    case .art: artStage
                    case .lyrics: lyricsStage
                    case .queue: queueStage
                    }
                }
                .frame(maxHeight: .infinity)

                trackInfo
                scrubber
                transport
                bottomBar
            }
            .padding(.horizontal, edgePadding)
            .padding(.vertical, Spacing.xl)
            .frame(maxWidth: stageMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .environment(\.colorScheme, .dark)
        .animation(.smooth(duration: 0.35), value: stage)
        #if os(tvOS)
        .onExitCommand { dismiss() }
        .onPlayPauseCommand { player.togglePlayPause() }
        #endif
    }

    // MARK: - Backdrop

    /// The album art itself, blown up and heavily blurred — the room takes on
    /// the record's color, like Apple Music's player.
    private var backdrop: some View {
        ZStack {
            UltrafinColors.background
            if let track = player.currentTrack, let url = player.artworkURL(for: track, maxWidth: 300) {
                RemoteImage(url: url)
                    .frame(width: 700, height: 700)
                    .blur(radius: 120)
                    .opacity(0.55)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.5)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: player.currentTrack?.id)
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

    // MARK: - Stages

    private var artStage: some View {
        RemoteImage(url: player.currentTrack.flatMap { player.artworkURL(for: $0) })
            .frame(width: artSide, height: artSide)
            .clipShape(RoundedRectangle(cornerRadius: artSide * 0.06, style: .continuous))
            .specularRim(cornerRadius: artSide * 0.06, intensity: 0.8)
            .shadow(color: .black.opacity(0.55), radius: 40, y: 22)
            // The Apple Music breath: full size while playing, settles back when
            // paused.
            .scaleEffect(player.isPlaying ? 1 : 0.85)
            .animation(.spring(duration: 0.5, bounce: 0.25), value: player.isPlaying)
            .frame(maxWidth: .infinity)
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
            Text(player.currentTrack?.name ?? "—")
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(player.currentTrack?.artistText ?? player.currentTrack?.album ?? " ")
                .font(.system(size: titleSize * 0.68, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
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
                Spacer()
                Text("-" + timeText(max(0, player.duration - (isScrubbing ? scrubValue * player.duration : player.currentTime))))
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

    private var artSide: CGFloat {
        #if os(tvOS)
        560
        #else
        300
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        34
        #else
        20
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
        34
        #endif
    }
    private var sideButtonSize: CGFloat {
        #if os(tvOS)
        30
        #else
        24
        #endif
    }
    private var transportSpacing: CGFloat {
        #if os(tvOS)
        Spacing.xxl
        #else
        Spacing.xl
        #endif
    }
    private var chipSize: CGFloat {
        #if os(tvOS)
        24
        #else
        17
        #endif
    }
    private var edgePadding: CGFloat {
        #if os(tvOS)
        80
        #else
        28
        #endif
    }
    private var stageMaxWidth: CGFloat {
        #if os(tvOS)
        900
        #else
        520
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
