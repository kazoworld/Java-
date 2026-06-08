import SwiftUI

/// Transport HUD overlaid on the video. The interaction model is deliberately
/// different per platform:
///
/// - **iOS:** touch — tappable transport buttons and a draggable scrubber.
/// - **tvOS:** the Siri Remote drives everything (handled in `VideoPlayerView`),
///   so here the overlay is an *informational* HUD: state, progress, time, and a
///   subtle hint. No focus-trapping buttons fighting the remote.
struct PlayerControlsView: View {
    @Bindable var model: VideoPlayerViewModel
    let onClose: () -> Void
    /// Transient "+15s / −15s" feedback shown while scrubbing on tvOS.
    var skipFeedback: Int? = nil

    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.65), .clear, .black.opacity(0.75)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                centerState
                Spacer()
                bottomBar
            }
            .padding(platformPadding)
        }
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
                Text(model.item.name)
                    .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                if !model.activeEngineName.isEmpty {
                    Label(model.activeEngineName, systemImage: "cpu")
                        .font(Typography.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            #if !os(tvOS)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(Spacing.sm)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            #endif
        }
    }

    private var titleSize: CGFloat {
        #if os(tvOS)
        34
        #else
        18
        #endif
    }

    // MARK: - Center

    @ViewBuilder
    private var centerState: some View {
        if model.state.status == .buffering {
            ProgressView().tint(.white).scaleEffect(centerScale)
        } else if let skipFeedback {
            // tvOS scrub feedback
            Label("\(skipFeedback > 0 ? "+" : "")\(skipFeedback)s",
                  systemImage: skipFeedback > 0 ? "goforward" : "gobackward")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(Spacing.lg)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.scale.combined(with: .opacity))
        } else {
            #if os(tvOS)
            // Big state glyph; the remote (not a button) drives playback.
            Image(systemName: model.state.status == .playing ? "play.fill" : "pause.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white.opacity(model.state.status == .playing ? 0 : 0.9))
                .animation(.smooth, value: model.state.status)
            #else
            iOSTransport
            #endif
        }
    }

    private var centerScale: CGFloat {
        #if os(tvOS)
        2.0
        #else
        1.4
        #endif
    }

    #if !os(tvOS)
    private var iOSTransport: some View {
        HStack(spacing: Spacing.xxl) {
            transportButton("gobackward.\(Int(model.seekInterval))") { model.skip(by: -model.seekInterval) }
            Button(action: { model.togglePlayPause() }) {
                Image(systemName: model.state.status == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            transportButton("goforward.\(Int(model.seekInterval))") { model.skip(by: model.seekInterval) }
        }
    }

    private func transportButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - Bottom

    private var bottomBar: some View {
        VStack(spacing: Spacing.sm) {
            #if os(tvOS)
            ProgressTrack(progress: model.state.progress,
                          buffered: bufferedFraction,
                          height: 8)
            #else
            Scrubber(
                progress: isScrubbing ? scrubProgress : model.state.progress,
                buffered: bufferedFraction,
                onScrubChanged: { value in isScrubbing = true; scrubProgress = value },
                onScrubEnded: { value in model.seek(toProgress: value); isScrubbing = false }
            )
            #endif

            HStack {
                Text(timecode(currentTime))
                Spacer()
                #if os(tvOS)
                Text("Swipe ◀ ▶ skip · Click play/pause · Menu exit")
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                #endif
                Text("-" + timecode(max(0, model.state.duration - currentTime)))
            }
            .font(Typography.monoTimecode)
            .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var bufferedFraction: Double {
        model.state.duration > 0 ? model.state.bufferedTime / model.state.duration : 0
    }

    private var currentTime: Double {
        isScrubbing ? scrubProgress * model.state.duration : model.state.currentTime
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Display-only progress bar with a buffered track (tvOS, and reused by the
/// interactive iOS scrubber).
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
/// A draggable progress bar for touch platforms. Pure SwiftUI so it stays at
/// 60fps and matches the app's accent.
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
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .offset(x: width * progress.clamped01() - 7)
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in onScrubChanged((value.location.x / width).clamped01()) }
                    .onEnded { value in onScrubEnded((value.location.x / width).clamped01()) }
            )
        }
        .frame(height: 28)
    }
}
#endif

private extension Double {
    func clamped01() -> Double { Swift.max(0, Swift.min(1, self)) }
}
