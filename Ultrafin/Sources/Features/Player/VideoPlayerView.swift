import SwiftUI

/// Full-screen player. Hosts the active engine's video output and overlays
/// custom, auto-hiding controls. The overlay is the only thing that animates
/// during playback so the video stays at full frame rate.
struct VideoPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @Environment(AppState.self) private var appState

    let item: MediaItem
    let userID: String

    @State private var model: VideoPlayerViewModel?
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    /// Transient skip amount for the tvOS scrub feedback chip.
    @State private var skipFeedback: Int?
    @State private var skipFeedbackTask: Task<Void, Never>?

    #if os(tvOS)
    @FocusState private var surfaceFocused: Bool
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let model {
                if let engine = model.engine {
                    PlayerSurface(view: engine.playerLayerView)
                        .ignoresSafeArea()
                }

                if let error = model.errorMessage {
                    errorOverlay(error)
                } else if controlsVisible {
                    PlayerControlsView(model: model, onClose: close, skipFeedback: skipFeedback)
                        .transition(.opacity)
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .modifier(PlayerInteraction(
            seekInterval: seekInterval,
            onTap: { toggleControls() },
            onPlayPause: { togglePlayPause() },
            onExit: { close() },
            onSkip: { seconds in scrub(by: seconds) }
        ))
        #if os(tvOS)
        .focusable()
        .focused($surfaceFocused)
        .onAppear { surfaceFocused = true }
        #endif
        .task { await startIfNeeded() }
        .onChange(of: model?.state.status) { _, status in
            if status == .ended { close() }
        }
        .onAppear { scheduleHide() }
        .onDisappear { model?.stop() }
        .animation(.smooth(duration: 0.25), value: controlsVisible)
        .animation(.smooth(duration: 0.2), value: skipFeedback)
    }

    private func togglePlayPause() {
        model?.togglePlayPause()
        showControlsTemporarily()
    }

    /// Skips and flashes the feedback chip (used by the tvOS remote).
    private func scrub(by seconds: Double) {
        model?.skip(by: seconds)
        showControlsTemporarily()
        skipFeedback = Int(seconds)
        skipFeedbackTask?.cancel()
        skipFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { skipFeedback = nil }
        }
    }

    private func showControlsTemporarily() {
        controlsVisible = true
        scheduleHide()
    }

    /// Builds the view model once, using the live client from the environment,
    /// then begins playback.
    private func startIfNeeded() async {
        guard model == nil, let client = appState.client else { return }
        let vm = VideoPlayerViewModel(
            item: item,
            userID: userID,
            client: client,
            settings: settings.playback
        )
        model = vm
        await vm.start()
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))
            Text(message)
                .font(Typography.body)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("Close") { close() }
                .buttonStyle(.borderedProminent)
        }
        .padding(Spacing.xl)
    }

    private var seekInterval: Double { model?.seekInterval ?? 15 }

    private func toggleControls() {
        controlsVisible.toggle()
        if controlsVisible { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled, model?.state.status == .playing {
                controlsVisible = false
            }
        }
    }

    private func close() {
        model?.stop()
        dismiss()
    }
}

/// Platform-specific player input.
///
/// - **tvOS:** maps the Siri Remote to playback — Play/Pause button toggles,
///   the Menu button exits, left/right swipes scrub, and a click toggles
///   playback. This is the focus-engine-native model that makes Apple TV
///   playback feel right (and that touch-port clients get wrong).
/// - **iOS:** a tap toggles the controls; the on-screen buttons/scrubber do the
///   rest. Also hides the status bar and home indicator during playback.
private struct PlayerInteraction: ViewModifier {
    let seekInterval: Double
    let onTap: () -> Void
    let onPlayPause: () -> Void
    let onExit: () -> Void
    let onSkip: (Double) -> Void

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .onPlayPauseCommand { onPlayPause() }
            .onExitCommand { onExit() }
            .onMoveCommand { direction in
                switch direction {
                case .left: onSkip(-seekInterval)
                case .right: onSkip(seekInterval)
                default: break
                }
            }
        #else
        content
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
        #endif
    }
}

/// Bridges the engine's native video view into SwiftUI without recreating it
/// on every state change (which would stutter playback).
struct PlayerSurface: UIViewRepresentable {
    let view: PlatformView
    func makeUIView(context: Context) -> PlatformView { view }
    func updateUIView(_ uiView: PlatformView, context: Context) {}
}
