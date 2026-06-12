import SwiftUI

/// Which selection panel (if any) is open over the player. Captions are a
/// one-press toggle (no panel); quality opens a small list.
enum PlayerPanel: Equatable { case none, quality, episodes }

/// What currently holds focus in the player. `surface` is the invisible remote
/// capture layer used while the controls are hidden; the rest are control-bar
/// buttons. Sharing one `@FocusState` lets us move focus reliably between the
/// video and the controls on tvOS.
enum PlayerFocusTarget: Hashable {
    case surface, previous, back, playPause, forward, next, captions, quality, episodes, skipIntro, upNext
}

/// A request to open the player on a queue of items at a starting index — used
/// by screens that present playback (e.g. a season of episodes).
struct PlaybackRequest: Identifiable {
    let id = UUID()
    let queue: [MediaItem]
    let index: Int
    var resume: Bool = true
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
    /// When false, playback starts from the beginning even if there's a saved
    /// resume position (the detail "Play from beginning" action).
    var resume: Bool = true

    @State private var model: VideoPlayerViewModel?
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var skipFeedback: Int?
    @State private var skipFeedbackTask: Task<Void, Never>?
    @State private var panel: PlayerPanel = .none
    /// Holds the HDMI/eARC audio route open so VLC resume isn't delayed.
    @State private var routeKeeper = AudioRouteKeeper()

    @FocusState private var focus: PlayerFocusTarget?

    init(item: MediaItem, userID: String, resume: Bool = true) {
        self.queue = [item]
        self.startIndex = 0
        self.userID = userID
        self.resume = resume
    }

    init(queue: [MediaItem], startIndex: Int, userID: String, resume: Bool = true) {
        self.queue = queue
        self.startIndex = startIndex
        self.userID = userID
        self.resume = resume
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let model {
                if let engine = model.engine {
                    PlayerSurface(view: engine.playerLayerView)
                        .id(ObjectIdentifier(engine)) // swap cleanly when the engine changes
                        .ignoresSafeArea()
                        #if os(iOS)
                        .onTapGesture { if controlsVisible { hideControls() } else { revealControls() } }
                        #endif
                }

                #if os(tvOS)
                // While controls are hidden, an invisible focusable layer owns
                // the remote: swipe to scrub, click to reveal the controls.
                if !controlsVisible && model.errorMessage == nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .focusable()
                        .focused($focus, equals: .surface)
                        .onMoveCommand { direction in
                            switch direction {
                            case .left: scrub(by: -seekInterval)
                            case .right: scrub(by: seekInterval)
                            default: break
                            }
                        }
                        .onTapGesture { revealControls() }
                }
                #endif

                // Floating "Skip Intro / Skip Credits" prompt, shown over the
                // video regardless of whether the controls are visible.
                if let skip = model.activeSkip {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button { model.skipCurrentSegment() } label: {
                                HStack(spacing: Spacing.sm) {
                                    #if os(tvOS)
                                    // Hint: press the remote's center (select) button.
                                    RemoteSelectGlyph(height: skipFont * 1.35)
                                    #endif
                                    Text(skip.label)
                                    Image(systemName: "forward.fill")
                                }
                                .font(.system(size: skipFont, weight: .bold, design: .rounded))
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, Spacing.md)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(UltrafinButtonStyle(focusScale: 1.1, lift: true))
                            .focused($focus, equals: .skipIntro)
                        }
                    }
                    .padding(skipPadding)
                    .transition(.opacity)
                }

                // "Up Next" auto-play card near the end of an episode.
                if model.showUpNext, let next = model.nextItem {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            upNextCard(next: next, model: model)
                        }
                    }
                    .padding(skipPadding)
                    .transition(.opacity)
                }

                if let error = model.errorMessage {
                    errorOverlay(error)
                } else if controlsVisible {
                    PlayerControlsView(
                        model: model,
                        skipFeedback: skipFeedback,
                        panel: $panel,
                        focus: $focus,
                        onPlayPause: { togglePlayPause() },
                        onSkip: { scrub(by: $0) },
                        onSeekProgress: { model.seek(toProgress: $0); resetHide() },
                        onNext: { Task { await model.playNext() }; resetHide() },
                        onPrevious: { Task { await model.playPrevious() }; resetHide() },
                        onToggleCaptions: { model.toggleCaptions(); resetHide() }
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
        .onChange(of: controlsVisible) { _, visible in
            focus = visible ? .playPause : .surface
        }
        .onChange(of: panel) { _, newPanel in
            if newPanel == .none && controlsVisible { focus = .playPause }
        }
        .onChange(of: focus) { _, _ in
            if controlsVisible && panel == .none { resetHide() }
        }
        .onChange(of: model?.activeSkip) { _, skip in
            // Pull focus to the Skip button while it's showing, then release.
            if skip != nil { focus = .skipIntro }
            else if !controlsVisible { focus = .surface }
        }
        .onChange(of: model?.showUpNext ?? false) { _, show in
            // Highlight the Up Next card when it appears so a click plays next.
            if show && !controlsVisible { focus = .upNext }
            else if !show && !controlsVisible && model?.activeSkip == nil { focus = .surface }
        }
        #endif
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
        .task { await startIfNeeded() }
        .onChange(of: model?.state.status) { _, status in
            if status == .ended { handleEnded() }
        }
        .onAppear {
            // Open the audio route as soon as the player appears — before the
            // stream finishes loading — so audio is ready when video starts, and
            // keep it warm so pausing doesn't drop the eARC/soundbar link.
            AudioSession.activateForPlayback()
            routeKeeper.start()
            scheduleHide()
        }
        .onDisappear {
            routeKeeper.stop()
            model?.stop()
        }
        .animation(.smooth(duration: 0.25), value: controlsVisible)
        .animation(.smooth(duration: 0.2), value: panel)
        .animation(.smooth(duration: 0.2), value: skipFeedback)
        .animation(.smooth(duration: 0.25), value: model?.activeSkip)
        .animation(.smooth(duration: 0.25), value: model?.showUpNext)
    }

    // MARK: - Up Next

    private func upNextCard(next: MediaItem, model: VideoPlayerViewModel) -> some View {
        Button {
            Task { await model.playNext() }
            resetHide()
        } label: {
            HStack(spacing: Spacing.md) {
                RemoteImage(url: model.episodeImageURL(next))
                    .frame(width: upNextThumb, height: upNextThumb * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Up Next · Playing in \(model.timeRemaining)s")
                        .font(.system(size: upNextCaption, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(upNextTitle(next))
                        .font(.system(size: upNextTitleSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Image(systemName: "play.fill")
                    .font(.system(size: upNextTitleSize, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.leading, Spacing.sm)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1))
            .frame(maxWidth: upNextMaxWidth)
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.06, lift: true))
        .focused($focus, equals: .upNext)
    }

    private func upNextTitle(_ item: MediaItem) -> String {
        if let tag = item.episodeTag { return "\(tag) · \(item.name)" }
        return item.name
    }

    private var upNextThumb: CGFloat {
        #if os(tvOS)
        150
        #else
        92
        #endif
    }
    private var upNextCaption: CGFloat {
        #if os(tvOS)
        18
        #else
        12
        #endif
    }
    private var upNextTitleSize: CGFloat {
        #if os(tvOS)
        24
        #else
        16
        #endif
    }
    private var upNextMaxWidth: CGFloat {
        #if os(tvOS)
        640
        #else
        380
        #endif
    }

    private var skipFont: CGFloat {
        #if os(tvOS)
        24
        #else
        16
        #endif
    }
    private var skipPadding: CGFloat {
        #if os(tvOS)
        Spacing.xxl
        #else
        Spacing.xl
        #endif
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
            captionMode: settings.subtitles.captionMode,
            defaultQuality: settings.video.defaultQuality,
            resume: resume
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

/// A small glyph of the Siri Remote with its center (select) button glowing —
/// hints that pressing the remote's middle button triggers the action it sits
/// next to (the Skip Intro button, which is auto-focused when it appears).
private struct RemoteSelectGlyph: View {
    var height: CGFloat

    var body: some View {
        let w = height * 0.56
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: w * 0.42, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: max(1, height * 0.06))
                .frame(width: w, height: height)
            Circle()
                .fill(Color.white)
                .frame(width: w * 0.62, height: w * 0.62)
                .padding(.top, w * 0.24)
                .shadow(color: .white.opacity(0.85), radius: height * 0.12)
        }
        .frame(width: w, height: height)
        .accessibilityHidden(true)
    }
}
