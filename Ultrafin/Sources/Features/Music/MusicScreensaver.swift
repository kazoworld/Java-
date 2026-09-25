import SwiftUI

#if os(tvOS)
/// The idle screen for a record left playing: everything goes true black and the
/// now-playing card drifts across it, reflecting off the edges — the DVD logo,
/// with your album on it.
///
/// Black rather than dimmed. On an OLED panel an unlit pixel draws no power and
/// can't retain an image, so a static interface left up for an hour is the one
/// thing worth avoiding; a small card wandering a dark screen is the fix for
/// both at once.
struct MusicScreensaver: View {
    @Bindable var player: MusicPlayer

    var body: some View {
        GeometryReader { geo in
            // TimelineView rather than an animation: the position is a pure
            // function of the clock, so nothing accumulates drift over the hours
            // this might be up for, and no state changes per frame.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let card = cardSize
                let x = travel(t, speed: 47, span: max(0, geo.size.width - card.width - inset * 2))
                let y = travel(t, speed: 31, span: max(0, geo.size.height - card.height - inset * 2))
                nowPlayingCard
                    .frame(width: card.width, alignment: .leading)
                    .position(x: inset + x + card.width / 2,
                              y: inset + y + card.height / 2)
            }
        }
        .background(Color.black.ignoresSafeArea())
        // Purely decorative: the remote is watched at the window, so this must
        // never sit between a press and whatever was focused underneath.
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            RemoteImage(url: player.currentTrack.flatMap { player.artworkURL(for: $0, maxWidth: 600) })
                .frame(width: artSide, height: artSide)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentTrack?.name ?? "")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let artist = player.currentTrack?.artistText, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
        // Held back from full white: a quiet card in a dark room, and fewer
        // photons on a panel that will be showing it for a long time.
        .opacity(0.82)
    }

    /// A triangle wave — out to the far edge, reflect, back again, forever. The
    /// two axes run at speeds that don't divide evenly into one another, so the
    /// card takes a long time before it retraces a path.
    private func travel(_ t: Double, speed: Double, span: CGFloat) -> CGFloat {
        guard span > 0 else { return 0 }
        let period = Double(span) * 2 / speed
        let phase = t.truncatingRemainder(dividingBy: period) * speed
        return CGFloat(phase <= Double(span) ? phase : Double(span) * 2 - phase)
    }

    private var artSide: CGFloat { 240 }
    private var cardSize: CGSize { CGSize(width: 340, height: artSide + 80) }
    /// Keep the card out of the TV's overscan, where it could be cropped.
    private var inset: CGFloat { 60 }
}

private struct MusicScreensaverModifier: ViewModifier {
    @Bindable var player: MusicPlayer
    /// Whether this screen is one the idle screen should be allowed to cover.
    let eligible: Bool

    @State private var idle = RemoteIdleState.shared

    func body(content: Content) -> some View {
        content
            .tracksRemoteActivity()
            .overlay {
                if idle.isIdle && eligible && player.isPlaying {
                    MusicScreensaver(player: player)
                }
            }
            // Armed only while a record is actually playing. Pausing brings the
            // interface back rather than leaving a frozen card wandering a black
            // screen with no sound.
            // No onDisappear disarm: this modifier is applied both to the tab
            // tree and to the presented player, and the player disappearing
            // doesn't mean the music stopped. Both compute the same condition,
            // so whichever evaluates last agrees with the other.
            .onChange(of: eligible && player.isPlaying, initial: true) { _, live in
                idle.isArmed = live
            }
    }
}

extension View {
    /// After half a minute of stillness, let this screen give way to the drifting
    /// now-playing card. `eligible` gates it to the music experience.
    func musicScreensaver(player: MusicPlayer, eligible: Bool) -> some View {
        modifier(MusicScreensaverModifier(player: player, eligible: eligible))
    }
}
#endif
