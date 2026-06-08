import SwiftUI

/// Custom transport controls overlaid on the video. Kept deliberately light:
/// a scrim, title, scrubber, and three transport buttons. The scrubber uses a
/// local drag state so dragging never fights the engine's time updates.
struct PlayerControlsView: View {
    @Bindable var model: VideoPlayerViewModel
    let onClose: () -> Void

    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.6), .clear, .black.opacity(0.7)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                centerTransport
                Spacer()
                bottomBar
            }
            .padding(Spacing.lg)
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.item.name)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                if !model.activeEngineName.isEmpty {
                    Label(model.activeEngineName, systemImage: "cpu")
                        .font(Typography.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(Spacing.sm)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var centerTransport: some View {
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
        .opacity(model.state.status == .buffering ? 0.4 : 1)
        .overlay {
            if model.state.status == .buffering {
                ProgressView().tint(.white).scaleEffect(1.4)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: Spacing.sm) {
            Scrubber(
                progress: isScrubbing ? scrubProgress : model.state.progress,
                buffered: model.state.duration > 0 ? model.state.bufferedTime / model.state.duration : 0,
                onScrubChanged: { value in
                    isScrubbing = true
                    scrubProgress = value
                },
                onScrubEnded: { value in
                    model.seek(toProgress: value)
                    isScrubbing = false
                }
            )
            HStack {
                Text(timecode(currentTime))
                Spacer()
                Text("-" + timecode(max(0, model.state.duration - currentTime)))
            }
            .font(Typography.monoTimecode)
            .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var currentTime: Double {
        isScrubbing ? scrubProgress * model.state.duration : model.state.currentTime
    }

    private func transportButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// A draggable progress bar with a buffered track. Pure SwiftUI so it stays at
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
                Capsule().fill(Color.white.opacity(0.3)).frame(width: width * buffered.clamped())
                Capsule().fill(settings.theme.accent.color).frame(width: width * progress.clamped())
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .offset(x: width * progress.clamped() - 7)
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in onScrubChanged((value.location.x / width).clamped()) }
                    .onEnded { value in onScrubEnded((value.location.x / width).clamped()) }
            )
        }
        .frame(height: 28)
    }
}

private extension Double {
    func clamped() -> Double { Swift.max(0, Swift.min(1, self)) }
}
