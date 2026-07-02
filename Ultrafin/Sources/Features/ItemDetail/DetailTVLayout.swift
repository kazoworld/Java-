import SwiftUI

/// The cover/backdrop art treatment for detail screens, in the Netflix style.
///
/// In landscape (tvOS, iPad, iPhone landscape) the art bleeds off the right edge
/// and dissolves into the dark on its left, leaving the left half for the content
/// column. In portrait the art fills the top and fades down into the page. Either
/// way it's `aspectRatio(.fill)`-cropped so it always fits the frame cleanly.
struct DetailArtBackdrop: View {
    let backdropURL: URL?
    let artColor: ArtworkColor?
    let landscape: Bool

    private var tint: Color { artColor?.color ?? UltrafinColors.accent }
    private var base: Color { UltrafinColors.background }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                base

                // The art is feathered with two stacked masks (horizontal +
                // vertical) so it dissolves into the base on its internal edges
                // like a soft vignette — no hard line against the grey. The outer
                // screen edges stay full-bleed.
                art(geo: geo)
                    .mask(horizontalFeather)
                    .mask(verticalFeather)

                // Blend the art into the page at the bottom — a tall, eased ramp
                // (several stops approximating an ease-in) so the picture melts
                // into the background rather than meeting it on a line.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.42),
                    .init(color: base.opacity(0.18), location: 0.60),
                    .init(color: base.opacity(0.48), location: 0.76),
                    .init(color: base.opacity(0.80), location: 0.89),
                    .init(color: base, location: 1.0)
                ], startPoint: .top, endPoint: .bottom)

                // A whisper of art-color on the dark side (kept subtle so the
                // photo and the dark column read as one surface, not two).
                LinearGradient(colors: [tint.opacity(0.10), .clear],
                               startPoint: landscape ? .leading : .bottom,
                               endPoint: landscape ? .center : .top)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: artColor)
    }

    @ViewBuilder
    private func art(geo: GeometryProxy) -> some View {
        if landscape {
            RemoteImage(url: backdropURL)
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width * 0.64, height: geo.size.height)
                .clipped()
                .frame(width: geo.size.width, alignment: .trailing)
        } else {
            RemoteImage(url: backdropURL)
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
    }

    /// Left↔right feather. Landscape fades the art's left edge into the dark
    /// column over a wide, gradual band. The art occupies the right 64% of the
    /// width (its left edge sits at x≈0.36), so the mask stays FULLY transparent
    /// until past that edge — otherwise the art pops in at partial opacity and
    /// reads as a hard vertical cut.
    private var horizontalFeather: LinearGradient {
        if landscape {
            return LinearGradient(stops: [
                .init(color: .clear, location: 0.36),
                .init(color: .black.opacity(0.08), location: 0.46),
                .init(color: .black.opacity(0.30), location: 0.58),
                .init(color: .black.opacity(0.65), location: 0.72),
                .init(color: .black, location: 0.86)
            ], startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.10),
                .init(color: .black, location: 0.90),
                .init(color: .clear, location: 1.0)
            ], startPoint: .leading, endPoint: .trailing)
        }
    }

    /// Top↕bottom feather, softening both horizontal edges of the art with a
    /// long, eased tail at the bottom so the picture dissolves into the page
    /// instead of ending on a line.
    private var verticalFeather: LinearGradient {
        if landscape {
            return LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.16),
                .init(color: .black, location: 0.64),
                .init(color: .black.opacity(0.55), location: 0.82),
                .init(color: .black.opacity(0.18), location: 0.93),
                .init(color: .clear, location: 1.0)
            ], startPoint: .top, endPoint: .bottom)
        } else {
            return LinearGradient(stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 0.38),
                .init(color: .black.opacity(0.55), location: 0.68),
                .init(color: .black.opacity(0.2), location: 0.86),
                .init(color: .clear, location: 1.0)
            ], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// A full-width detail action row — Netflix-style. Plain icon + label normally;
/// a light frosted pill appears when focused (tvOS) or on the primary action
/// (iOS). An optional trailing progress bar shows the resume position.
struct DetailActionRow: View {
    let icon: String
    let title: String
    var progress: Double? = nil
    /// The primary row (Resume/Play). On iOS it shows the filled pill by default
    /// since there's no focus engine to drive it.
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DetailActionRowContent(icon: icon, title: title, progress: progress, prominent: prominent)
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.03, lift: false))
    }
}

private struct DetailActionRowContent: View {
    let icon: String
    let title: String
    var progress: Double?
    var prominent: Bool

    @Environment(\.isFocused) private var isFocused
    @Environment(SettingsStore.self) private var settings

    private var filled: Bool {
        #if os(tvOS)
        isFocused
        #else
        prominent
        #endif
    }
    private var fg: Color { filled ? .black : .white }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: iconSize + 4)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer(minLength: Spacing.md)
            if let progress {
                ZStack(alignment: .leading) {
                    Capsule().fill(fg.opacity(0.25))
                    Capsule().fill(settings.theme.accent.color)
                        .frame(width: barWidth * CGFloat(min(max(progress, 0), 1)))
                }
                .frame(width: barWidth, height: 5)
            }
        }
        .foregroundStyle(fg)
        .shadow(color: filled ? .clear : .black.opacity(0.45), radius: 5, y: 2)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, rowVPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Capsule(style: .continuous)
            .fill(filled ? Color.white.opacity(0.95) : Color.clear))
        .contentShape(Capsule())
    }

    private var iconSize: CGFloat {
        #if os(tvOS)
        26
        #else
        18
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        24
        #else
        16
        #endif
    }
    private var rowVPadding: CGFloat {
        #if os(tvOS)
        Spacing.md
        #else
        Spacing.sm
        #endif
    }
    private var barWidth: CGFloat {
        #if os(tvOS)
        130
        #else
        80
        #endif
    }
}
