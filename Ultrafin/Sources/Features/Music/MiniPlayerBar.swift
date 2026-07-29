import SwiftUI

/// The persistent now-playing bar: a floating Liquid Glass pill with the album
/// art, title, and transport that rides above the tab bar while you browse —
/// tap it to expand into the full player. The Apple Music pattern.
struct MiniPlayerBar: View {
    @Environment(SettingsStore.self) private var settings

    @Bindable var player: MusicPlayer
    let onExpand: () -> Void
    /// Shrunk to a compact pill while the user scrolls down a page.
    var isCondensed: Bool = false

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: Spacing.md) {
                RemoteImage(url: player.artworkURL(for: track, maxWidth: 200))
                    .frame(width: artSide, height: artSide)
                    .clipShape(RoundedRectangle(cornerRadius: isCondensed ? 6 : 8, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.name)
                        .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(UltrafinColors.primaryText)
                        .lineLimit(1)
                    // The artist line is the first thing to go when space tightens.
                    if !isCondensed, let artist = track.artistText {
                        Text(artist)
                            .font(.system(size: titleSize * 0.78))
                            .foregroundStyle(UltrafinColors.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Spacing.sm)

                barButton(player.isPlaying ? "pause.fill" : "play.fill", size: buttonSize) {
                    player.togglePlayPause()
                }
                if !isCondensed {
                    barButton("forward.fill", size: buttonSize * 0.8) {
                        player.next()
                    }
                }
                #if os(iOS)
                if !isCondensed {
                    barButton("xmark", size: buttonSize * 0.62) {
                        player.stop()
                    }
                }
                #else
                // tvOS: an explicit expand control (container taps don't mix
                // with focusable children on the focus engine).
                barButton("chevron.up", size: buttonSize * 0.8) {
                    onExpand()
                }
                #endif
            }
            .padding(.horizontal, isCondensed ? Spacing.sm : Spacing.md)
            .padding(.vertical, isCondensed ? Spacing.xs : Spacing.sm)
            .frame(maxWidth: isCondensed ? condensedMaxWidth : barMaxWidth)
            .liquidGlass(cornerRadius: cornerRadius)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            #if os(iOS)
            .onTapGesture { onExpand() }
            #endif
            .animation(.smooth(duration: 0.3), value: isCondensed)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var cornerRadius: CGFloat { isCondensed ? 24 : 18 }

    private func barButton(_ icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(UltrafinColors.primaryText)
                .frame(width: size * 2.2, height: size * 2.2)
                .contentShape(Circle())
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.15, lift: false))
    }

    private var artSide: CGFloat {
        #if os(tvOS)
        64
        #else
        isCondensed ? 30 : 42
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        22
        #else
        14
        #endif
    }
    private var buttonSize: CGFloat {
        #if os(tvOS)
        24
        #else
        17
        #endif
    }
    private var barMaxWidth: CGFloat {
        #if os(tvOS)
        700
        #else
        .infinity
        #endif
    }
    /// Condensed, the bar pulls in from the edges into a floating pill.
    private var condensedMaxWidth: CGFloat {
        #if os(tvOS)
        520
        #else
        290
        #endif
    }
}
