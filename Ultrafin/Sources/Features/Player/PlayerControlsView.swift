import SwiftUI

/// Transport overlay: title, progress, a focusable button bar (play/pause,
/// skip, previous/next episode, captions, quality), and the selection panels.
/// On tvOS the bar is driven by the focus engine; on iOS by touch.
struct PlayerControlsView: View {
    @Bindable var model: VideoPlayerViewModel
    var skipFeedback: Int?
    @Binding var panel: PlayerPanel

    let onPlayPause: () -> Void
    let onSkip: (Double) -> Void
    let onSeekProgress: (Double) -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onInteraction: () -> Void

    @Environment(SettingsStore.self) private var settings
    @FocusState private var focused: Control?
    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0

    enum Control: Hashable { case previous, back, playPause, forward, next, captions, quality }

    private var accent: Color { settings.theme.accent.color }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.7), .clear, .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if panel == .none {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    centerState
                    Spacer()
                    bottomBar
                }
                .padding(platformPadding)
            } else {
                selectionPanel
            }
        }
        .onChange(of: focused) { _, _ in onInteraction() }
    }

    private var platformPadding: CGFloat {
        #if os(tvOS)
        Spacing.xxl
        #else
        Spacing.lg
        #endif
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.currentItem?.name ?? "")
                    .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                if let tag = model.currentItem?.episodeTag {
                    Text(tag).font(Typography.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
            Label(model.activeEngineName, systemImage: "cpu")
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.6))
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

    // MARK: - Bottom (progress + buttons)

    private var bottomBar: some View {
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
            .foregroundStyle(.white.opacity(0.8))

            buttonBar
        }
    }

    private var buttonBar: some View {
        HStack(spacing: buttonSpacing) {
            if model.hasPrevious {
                controlButton("backward.end.fill", focus: .previous) { onPrevious() }
            }
            controlButton("gobackward", focus: .back) { onSkip(-model.seekInterval) }
            controlButton(model.state.status == .playing ? "pause.fill" : "play.fill",
                          focus: .playPause, prominent: true) { onPlayPause() }
            controlButton("goforward", focus: .forward) { onSkip(model.seekInterval) }
            if model.hasNext {
                controlButton("forward.end.fill", focus: .next) { onNext() }
            }

            Spacer()

            controlButton(model.currentSubtitleID == nil ? "captions.bubble" : "captions.bubble.fill",
                          focus: .captions) { panel = .captions }
            controlButton("slider.horizontal.3", focus: .quality) { panel = .quality }
        }
        .padding(.top, Spacing.xs)
    }

    private func controlButton(_ system: String, focus: Control, prominent: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: prominent ? buttonSize + 8 : buttonSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: buttonDiameter, height: buttonDiameter)
                .background(prominent ? AnyShapeStyle(accent) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.18, lift: false))
        .focused($focused, equals: focus)
    }

    // MARK: - Selection panel (captions / quality)

    private var selectionPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(panel == .captions ? "Subtitles & CC" : "Quality")
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if panel == .captions {
                panelRow(title: "Off", selected: model.currentSubtitleID == nil) {
                    model.setSubtitle(id: nil); panel = .none
                }
                ForEach(model.subtitleTracks) { track in
                    panelRow(title: track.name, selected: model.currentSubtitleID == track.id) {
                        model.setSubtitle(id: track.id); panel = .none
                    }
                }
            } else {
                ForEach(QualityOption.allCases) { option in
                    panelRow(title: option.label, selected: model.quality == option) {
                        Task { await model.setQuality(option) }
                        panel = .none
                    }
                }
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 520, alignment: .leading)
        .glassCard()
    }

    private func panelRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
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
        32
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
        64
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
