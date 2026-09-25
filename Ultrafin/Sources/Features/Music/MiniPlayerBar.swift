import SwiftUI

/// The persistent now-playing bar: a floating glass pill carrying the album art,
/// the song, and just enough transport to keep a hand free — it rides directly
/// above the tab bar while you browse, and a tap opens the full player.
///
/// There is no stop button. The bar is a *status* first and a control second,
/// and a ✕ next to Play invites the wrong tap; swipe the bar down to end the
/// session instead, the same gesture that closes the full player.
struct MiniPlayerBar: View {
    @Bindable var player: MusicPlayer
    let onExpand: () -> Void
    /// Set while the tab bar is collapsed and this bar has the width to itself.
    /// Only the skip button goes — the credit is the reason the bar exists.
    var isCompact: Bool = false

    #if os(iOS)
    /// Live downward drag while swiping the bar away.
    @State private var dragOffset: CGFloat = 0
    /// Live sideways drag while swiping to another song, rubber-banded.
    @State private var swipeOffset: CGFloat = 0
    /// A drag commits to one axis on its first move, so a slightly diagonal
    /// swipe can't both skip a song and start dismissing the bar.
    @State private var dragAxis: Axis?
    #endif
    /// +1 when the last change went forward, -1 back — which side the next
    /// song slides in from.
    @State private var direction: CGFloat = 1
    @State private var nextTaps = 0

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: Spacing.md) {
                nowPlaying(track)
                    .id(track.id)
                    .transition(.asymmetric(
                        insertion: .offset(x: 70 * direction).combined(with: .opacity),
                        removal: .offset(x: -70 * direction).combined(with: .opacity)))
                    // Takes what's left and no more, so a long title can't widen
                    // the bar past its container.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(iOS)
                    .offset(x: swipeOffset)
                    #endif
                    // Clip sideways only, so a song sliding out slips under the
                    // bar's edge rather than across the buttons — the cover's
                    // shadow still has room above and below.
                    .mask(Rectangle().padding(.vertical, -14))
                    .animation(.smooth(duration: 0.4), value: track.id)

                barButton(player.isPlaying ? "pause.fill" : "play.fill", size: buttonSize) {
                    player.togglePlayPause()
                }
                .fixedSize()
                if !isCompact {
                    barButton("forward.fill", size: buttonSize, taps: nextTaps) {
                        nextTaps += 1
                        direction = 1
                        player.next()
                    }
                    .fixedSize()
                }

                #if os(tvOS)
                // tvOS: an explicit expand control (container taps don't mix
                // with focusable children on the focus engine).
                barButton("chevron.up", size: buttonSize * 0.85) { onExpand() }
                #endif
            }
            .padding(.leading, Spacing.sm)
            .padding(.trailing, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: barMaxWidth)
            // Exactly the tab bar's material. These two capsules sit a few
            // points apart; giving the upper one a heavier tint made it read as
            // a different, darker component rather than the same sheet of glass.
            .barGlass(shape: Capsule())
            .contentShape(Capsule())
            #if os(iOS)
            .offset(y: max(0, dragOffset))
            .gesture(barDrag)
            .onTapGesture { onExpand() }
            .contentShape(.contextMenuPreview, Capsule())
            .contextMenu { barMenu }
            .task(id: track.id) { prefetchNeighbours() }
            #endif
            // Scale and fade, NOT a move. This lives inside a safe-area inset
            // whose own height animates as the bar appears; a move transition
            // races that and can leave the bar parked below the visible area.
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
        }
    }

    /// Cover and credit — the part of the bar that changes with the song, and
    /// the part that slides when you swipe to the next one.
    private func nowPlaying(_ track: MediaItem) -> some View {
        HStack(spacing: Spacing.md) {
            RemoteImage(url: player.artworkURL(for: track, maxWidth: 200))
                .accessibilityHidden(true)
                .frame(width: artSide, height: artSide)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                // Paused, the cover dims a touch — the bar says "stopped" at a
                // glance, without a word.
                .opacity(player.isPlaying ? 1 : 0.72)
                .animation(.smooth(duration: 0.3), value: player.isPlaying)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.name)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(UltrafinColors.primaryText)
                    .lineLimit(1)
                if let artist = track.artistText, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: titleSize * 0.86))
                        .foregroundStyle(UltrafinColors.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Combine the CREDIT only. Combining the whole bar would swallow
            // the play and next buttons into one element and leave VoiceOver
            // no way to reach them.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the full player")
        }
    }

    #if os(iOS)
    /// One drag, two meanings, decided by the first move: sideways skips to the
    /// next or previous song (the credit follows your thumb, as on Apple
    /// Music); down ends the session, the same gesture that closes the player.
    private var barDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height)
                        ? .horizontal : .vertical
                }
                if dragAxis == .horizontal {
                    swipeOffset = ElasticSlider.rubberBand(value.translation.width, limit: 90)
                } else {
                    dragOffset = max(0, value.translation.height)
                }
            }
            .onEnded { value in
                defer { dragAxis = nil }
                if dragAxis == .horizontal {
                    let dx = value.translation.width
                    let far = abs(dx) > 50 || abs(value.predictedEndTranslation.width) > 160
                    guard far else {
                        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { swipeOffset = 0 }
                        return
                    }
                    Haptics.play(.light)
                    direction = dx < 0 ? 1 : -1
                    withAnimation(.spring(duration: 0.45, bounce: 0.15)) {
                        swipeOffset = 0
                        if dx < 0 { player.next() } else { player.previous() }
                    }
                } else {
                    if value.translation.height > 44 || value.predictedEndTranslation.height > 120 {
                        Haptics.play(.light)
                        withAnimation(.smooth(duration: 0.3)) { player.stop() }
                    }
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) { dragOffset = 0 }
                }
            }
    }

    /// Long-press: the handful of things worth doing without opening the
    /// player — and a visible way to stop, for anyone who never finds the
    /// swipe.
    @ViewBuilder
    private var barMenu: some View {
        Button(action: onExpand) {
            Label("Open Player", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        Button { player.toggleShuffle() } label: {
            Label(player.shuffleOn ? "Shuffle Off" : "Shuffle", systemImage: "shuffle")
        }
        Button { player.cycleRepeat() } label: {
            Label(repeatLabel, systemImage: player.repeatMode.icon)
        }
        Divider()
        Button(role: .destructive) {
            withAnimation(.smooth(duration: 0.3)) { player.stop() }
        } label: {
            Label("Stop Playing", systemImage: "stop.fill")
        }
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: "Repeat"
        case .all: "Repeat One"
        case .one: "Repeat Off"
        }
    }

    /// Warm the neighbours' thumbnails so a swipe slides in a cover, not a
    /// grey square.
    private func prefetchNeighbours() {
        for offset in [1, -1] {
            let i = player.index + offset
            guard player.queue.indices.contains(i),
                  let url = player.artworkURL(for: player.queue[i].track, maxWidth: 200) else { continue }
            Task.detached(priority: .utility) { _ = await ImageLoader.shared.image(for: url) }
        }
    }
    #endif

    private func barButton(_ icon: String, size: CGFloat, taps: Int = 0,
                           action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(UltrafinColors.primaryText)
                .contentTransition(.symbolEffect(.replace))
                .animation(.snappy(duration: 0.25), value: icon)
                .keyframeAnimator(initialValue: CGFloat(0), trigger: taps) { content, x in
                    content.offset(x: x)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(size * 0.3, duration: 0.1)
                        SpringKeyframe(0, duration: 0.4, spring: .bouncy)
                    }
                }
                .frame(width: size * 2, height: size * 2)
                .minimumHitTarget()
                .contentShape(Rectangle())
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.15, lift: false))
    }

    private var artSide: CGFloat {
        #if os(tvOS)
        64
        #else
        42
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        22
        #else
        15
        #endif
    }
    private var buttonSize: CGFloat {
        #if os(tvOS)
        24
        #else
        18
        #endif
    }
    private var barMaxWidth: CGFloat {
        #if os(tvOS)
        700
        #else
        .infinity
        #endif
    }
}
