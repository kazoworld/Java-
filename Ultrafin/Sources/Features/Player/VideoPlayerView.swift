import SwiftUI

/// Which selection panel (if any) is open over the player.
enum PlayerPanel: Equatable { case none, captions, quality }

/// A request to open the player on a queue of items at a starting index — used
/// by screens that present playback (e.g. a season of episodes).
struct PlaybackRequest: Identifiable {
    let id = UUID()
    let queue: [MediaItem]
    let index: Int
}

/// Full-screen player. Hosts the active engine's video output and overlays
/// custom, auto-hiding controls. Supports a queue (episodes), captions, and a
/// quality selector.
struct VideoPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @Environment(AppState.self) private var appState

    let queue: [MediaItem]
    let startIndex: Int
    let userID: String

    @State private var model: VideoPlayerViewModel?
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var skipFeedback: Int?
    @State private var skipFeedbackTask: Task<Void, Never>?
    @State private var panel: PlayerPanel = .none

    #if os(tvOS)
    @FocusState private var surfaceFocused: Bool
    #endif

    init(item: MediaItem, userID: String) {
        self.queue = [item]
        self.startIndex = 0
        self.userID = userID
    }

    init(queue: [MediaItem], startIndex: Int, userID: String) {
        self.queue = queue
        self.startIndex = startIndex
        self.userID = userID
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let model {
                if let engine = model.engine {
                    PlayerSurface(view: engine.playerLayerView)
                        .id(ObjectIdentifier(engine)) // swap cleanly when the engine changes
                        .ignoresSafeArea()
                        #if os(tvOS)
                        .focusable(!controlsVisible)
                        .focused($surfaceFocused)
                        .onMoveCommand { direction in
                            switch direction {
                            case .left: scrub(by: -seekInterval)
                            case .right: scrub(by: seekInterval)
                            default: break
                            }
                        }
                        .onTapGesture { revealControls() }
                        #else
                        .onTapGesture { if controlsVisible { hideControls() } else { revealControls() } }
                        #endif
                }

                if let error = model.errorMessage {
                    errorOverlay(error)
                } else if controlsVisible {
                    PlayerControlsView(
                        model: model,
                        skipFeedback: skipFeedback,
                        panel: $panel,
                        onPlayPause: { togglePlayPause() },
                        onSkip: { scrub(by: $0) },
                        onSeekProgress: { model.seek(toProgress: $0); resetHide() },
                        onNext: { Task { await model.playNext() }; resetHide() },
                        onPrevious: { Task { await model.playPrevious() }; resetHide() },
                        onInteraction: { resetHide() }
                    )
                    .transition(.opacity)
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        #if os(tvOS)
        .onPlayPauseCommand { togglePlayPause() }
        .onExitCommand { handleBack() }
        #endif
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
        .task { await startIfNeeded() }
        .onChange(of: model?.state.status) { _, status in
            if status == .ended { handleEnded() }
        }
        #if os(tvOS)
        .onChange(of: controlsVisible) { _, visible in
            if !visible { surfaceFocused = true }
        }
        #endif
        .onAppear { scheduleHide() }
        .onDisappear { model?.stop() }
        .animation(.smooth(duration: 0.25), value: controlsVisible)
        .animation(.smooth(duration: 0.2), value: panel)
        .animation(.smooth(duration: 0.2), value: skipFeedback)
    }

    // MARK: - Start

    private func startIfNeeded() async {
        guard model == nil, let client = appState.client else { return }
        let vm = VideoPlayerViewModel(
            queue: queue,
            startIndex: startIndex,
            userID: userID,
            client: client,
            settings: settings.playback,
            captionMode: settings.subtitles.captionMode
        )
        model = vm
        await vm.start()
    }

    // MARK: - Transport

    private var seekInterval: Double { model?.seekInterval ?? 15 }

    private func togglePlayPause() {
        model?.togglePlayPause()
        resetHide()
    }

    private func scrub(by seconds: Double) {
        model?.skip(by: seconds)
        resetHide()
        skipFeedback = Int(seconds)
        skipFeedbackTask?.cancel()
        skipFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { skipFeedback = nil }
        }
    }

    private func handleEnded() {
        guard let model else { close(); return }
        Task {
            let advanced = await model.handlePlaybackEnded()
            if !advanced { close() }
        }
    }

    // MARK: - Controls visibility

    /// Back/Menu: close a panel first, then hide controls, then exit.
    private func handleBack() {
        if panel != .none { panel = .none; return }
        if controlsVisible { hideControls() } else { close() }
    }

    private func revealControls() {
        controlsVisible = true
        scheduleHide()
    }

    private func resetHide() {
        controlsVisible = true
        scheduleHide()
    }

    private func hideControls() {
        hideTask?.cancel()
        controlsVisible = false
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, panel == .none else { return }
            let status = model?.state.status
            if status == .playing || status == .paused {
                controlsVisible = false
            }
        }
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

    private func close() {
        model?.stop()
        dismiss()
    }
}

/// Bridges the engine's native video view into SwiftUI without recreating it on
/// every state change (which would stutter playback).
struct PlayerSurface: UIViewRepresentable {
    let view: PlatformView
    func makeUIView(context: Context) -> PlatformView { view }
    func updateUIView(_ uiView: PlatformView, context: Context) {}
}
