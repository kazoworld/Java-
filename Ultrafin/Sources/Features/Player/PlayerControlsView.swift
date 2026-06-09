import SwiftUI

/// Transport overlay: title, progress, a focusable liquid-glass button bar
/// (play/pause, skip, previous/next episode, captions, quality), and the
/// selection panels. Focus is shared with the host view so the remote can move
/// between the video and the controls reliably on tvOS.
struct PlayerControlsView: View {
    @Bindable var model: VideoPlayerViewModel
    var skipFeedback: Int?
    @Binding var panel: PlayerPanel
    var focus: FocusState<PlayerFocusTarget?>.Binding

    let onPlayPause: () -> Void
    let onSkip: (Double) -> Void
    let onSeekProgress: (Double) -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void

    @Environment(SettingsStore.self) private var settings
    @FocusState private var panelFocus: Int?
    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0

    private var accent: Color { settings.theme.accent.color }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if panel == .none {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    centerState
                    Spacer()
                    glassBar
                }
                .padding(platformPadding)
            } else {
                selectionPanel
            }
        }
    }

    private var platformPadding: CGFloat {
        #if os(tvOS)
        Spacing.xl
        #else
        Spacing.lg
        #endif
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.currentItem?.name ?? "")
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if let tag = model.currentItem?.episodeTag {
                    Text(tag).font(Typography.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
            Label(model.activeEngineName, systemImage: "cpu")
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - Center

    @ViewBuilder
    private var centerState: some View {
        if model.state.status == .buffering {
            ProgressView().tint(.white).scaleEffect(centerScale)
        } else if let skipFeedback {
            Label("\(skipFeedback > 0 ? "+" : "")\(skipFeedback)s",
                  systemImage: skipFeedback > 0 ? "goforward" : "gobackward")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(Spacing.lg)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var centerScale: CGFloat {
        #if os(tvOS)
        2.0
        #else
        1.4
        #endif
    }

    // MARK: - Bottom: liquid glass control bar

    private var glassBar: some View {
        VStack(spacing: Spacing.md) {
            #if os(tvOS)
            ProgressTrack(progress: model.state.progress, buffered: bufferedFraction, height: 8)
            #else
            Scrubber(progress: isScrubbing ? scrubProgress : model.state.progress,
                     buffered: bufferedFraction,
                     onScrubChanged: { isScrubbing = true; scrubProgress = $0 },
                     onScrubEnded: { onSeekProgress($0); isScrubbing = false })
            #endif

            HStack {
                Text(timecode(model.state.currentTime))
                Spacer()
                Text("-" + timecode(max(0, model.state.duration - model.state.currentTime)))
            }
            .font(Typography.monoTimecode)
            .foregroundStyle(.white.opacity(0.85))

            buttonBar
        }
        .padding(barPadding)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: barRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: barRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }

    private var buttonBar: some View {
        HStack(spacing: buttonSpacing) {
            if model.hasPrevious {
                glassButton("backward.end.fill", target: .previous) { onPrevious() }
            }
            glassButton("gobackward", target: .back) { onSkip(-model.seekInterval) }
            glassButton(model.state.status == .playing ? "pause.fill" : "play.fill",
                        target: .playPause, prominent: true) { onPlayPause() }
            glassButton("goforward", target: .forward) { onSkip(model.seekInterval) }
            if model.hasNext {
                glassButton("forward.end.fill", target: .next) { onNext() }
            }

            Spacer()

            glassButton(model.currentSubtitleID == nil ? "captions.bubble" : "captions.bubble.fill",
                        target: .captions) { panel = .captions }
            glassButton("slider.horizontal.3", target: .quality) { panel = .quality }
        }
        .padding(.top, Spacing.xs)
    }

    private func glassButton(_ system: String, target: PlayerFocusTarget, prominent: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: prominent ? buttonSize + 8 : buttonSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: buttonDiameter, height: buttonDiameter)
                .background {
                    if prominent {
                        Circle().fill(accent.gradient)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.18, lift: true))
        .focused(focus, equals: target)
    }

    // MARK: - Selection panel (captions / quality)

    private var selectionPanel: some View {
        let captionOptions: [(id: Int, title: String, selectedID: Int?)] = {
            var rows: [(Int, String, Int?)] = [(-1, "Off", nil)]
            for track in model.subtitleTracks { rows.append((track.id, track.name, track.id)) }
            return rows.map { (id: $0.0, title: $0.1, selectedID: $0.2) }
        }()

        return VStack(alignment: .leading, spacing: Spacing.md) {
            Text(panel == .captions ? "Subtitles & CC" : "Quality")
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if panel == .captions {
                ForEach(Array(captionOptions.enumerated()), id: \.offset) { idx, option in
                    panelRow(index: idx, title: option.title,
                             selected: model.currentSubtitleID == option.selectedID) {
                        model.setSubtitle(id: option.selectedID); panel = .none
                    }
                }
            } else {
                ForEach(Array(QualityOption.allCases.enumerated()), id: \.offset) { idx, option in
                    panelRow(index: idx, title: option.label, selected: model.quality == option) {
                        Task { await model.setQuality(option) }
                        panel = .none
                    }
                }
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: barRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: barRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear { panelFocus = 0 }
    }

    private func panelRow(index: Int, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(accent).font(.system(size: 20, weight: .bold))
                }
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.04, lift: false))
        .focused($panelFocus, equals: index)
    }

    // MARK: - Helpers

    private var bufferedFraction: Double {
        model.state.duration > 0 ? model.state.bufferedTime / model.state.duration : 0
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: - Metrics

    private var titleSize: CGFloat {
        #if os(tvOS)
        34
        #else
        18
        #endif
    }
    private var buttonSize: CGFloat {
        #if os(tvOS)
        28
        #else
        20
        #endif
    }
    private var buttonDiameter: CGFloat {
        #if os(tvOS)
        66
        #else
        46
        #endif
    }
    private var buttonSpacing: CGFloat {
        #if os(tvOS)
        Spacing.lg
        #else
        Spacing.md
        #endif
    }
    private var barPadding: CGFloat {
        #if os(tvOS)
        Spacing.xl
        #else
        Spacing.lg
        #endif
    }
    private var barRadius: CGFloat {
        #if os(tvOS)
        32
        #else
        24
        #endif
    }
}

/// Display-only progress bar with a buffered track (tvOS, and reused by the iOS
/// scrubber).
struct ProgressTrack: View {
    let progress: Double
    let buffered: Double
    var height: CGFloat = 6

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(Color.white.opacity(0.3)).frame(width: width * buffered.clamped01())
                Capsule().fill(settings.theme.accent.color).frame(width: width * progress.clamped01())
            }
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: max(height, 24))
    }
}

#if !os(tvOS)
/// A draggable progress bar for touch platforms.
private struct Scrubber: View {
    let progress: Double
    let buffered: Double
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(Color.white.opacity(0.3)).frame(width: width * buffered.clamped01())
                Capsule().fill(settings.theme.accent.color).frame(width: width * progress.clamped01())
                Circle().fill(.white).frame(width: 14, height: 14)
                    .offset(x: width * progress.clamped01() - 7)
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onScrubChanged(($0.location.x / width).clamped01()) }
                    .onEnded { onScrubEnded(($0.location.x / width).clamped01()) }
            )
        }
        .frame(height: 28)
    }
}
#endif

private extension Double {
    func clamped01() -> Double { Swift.max(0, Swift.min(1, self)) }
}
