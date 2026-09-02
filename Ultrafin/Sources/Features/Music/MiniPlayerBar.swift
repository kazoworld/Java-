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
    #endif

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: Spacing.md) {
                RemoteImage(url: player.artworkURL(for: track, maxWidth: 200))
                    .accessibilityHidden(true)
                    .frame(width: artSide, height: artSide)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)

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
                // Takes what's left and no more, so a long title can't widen the
                // bar past its container.
                .frame(maxWidth: .infinity, alignment: .leading)
                // Combine the CREDIT only. Combining the whole bar would swallow
                // the play and next buttons into one element and leave VoiceOver
                // no way to reach them.
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the full player")

                barButton(player.isPlaying ? "pause.fill" : "play.fill", size: buttonSize) {
                    player.togglePlayPause()
                }
                .fixedSize()
                if !isCompact {
                    barButton("forward.fill", size: buttonSize) {
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
            .gesture(dismissDrag)
            .onTapGesture { onExpand() }
            #endif
            // Scale and fade, NOT a move. This lives inside a safe-area inset
            // whose own height animates as the bar appears; a move transition
            // races that and can leave the bar parked below the visible area.
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
        }
    }

    #if os(iOS)
    /// Pull the bar down to end the session. It follows your finger and springs
    /// back if you don't mean it.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 44 || value.predictedEndTranslation.height > 120 {
                    Haptics.play(.light)
                    withAnimation(.smooth(duration: 0.3)) { player.stop() }
                }
                withAnimation(.spring(duration: 0.35, bounce: 0.2)) { dragOffset = 0 }
            }
    }
    #endif

    private func barButton(_ icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(UltrafinColors.primaryText)
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
