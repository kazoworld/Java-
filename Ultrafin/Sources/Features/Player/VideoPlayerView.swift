import SwiftUI

/// Which selection panel (if any) is open over the player. Captions are a
/// one-press toggle (no panel); quality opens a small list.
enum PlayerPanel: Equatable { case none, quality, episodes }

/// What currently holds focus in the player. `surface` is the invisible remote
/// capture layer used while the controls are hidden; the rest are control-bar
/// buttons. Sharing one `@FocusState` lets us move focus reliably between the
/// video and the controls on tvOS.
enum PlayerFocusTarget: Hashable {
    case surface, scrubBar, previous, back, playPause, forward, next, captions, quality, episodes, skipIntro, upNext
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

                // Paused state: once the controls auto-hide, dim the frozen frame
                // and keep the title showing so it's clearly paused (the title
                // sits above the dim, unaffected).
                if model.state.status == .paused && !controlsVisible && model.errorMessage == nil {
                    pausedOverlay(model)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                #if os(tvOS)
                // While controls are hidden, an invisible focusable layer owns
                // the remote: swipe to scrub, click to reveal the controls.
                // Suppressed while a Skip prompt is up so the prompt keeps focus.
                if !controlsVisible && model.errorMessage == nil && model.activeSkip == nil {
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
                    // Lift the box above the control bar while it's showing.
                    .padding(.bottom, controlsVisible ? skipControlClearance : 0)
                    .padding(skipPadding)
                    .transition(.opacity)
                    .zIndex(3) // keep the prompt above the controls, never behind
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

                // Scrubber-preview frame while skipping (Trickplay).
                if let src = model.trickplaySource, skipFeedback != nil {
                    VStack(spacing: Spacing.sm) {
                        TrickplayThumbnail(source: src, time: model.state.currentTime,
                                           width: trickplayWidth)
                        Text(timecode(model.state.currentTime))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Spacing.sm).padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: Capsule())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, trickplayTopPadding)
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
            // With controls up, keep focus on the transport (the Skip box sits
            // above the bar — press up to reach it). With controls hidden, a
            // Skip prompt grabs focus so a single click skips it.
            if visible { focus = .playPause }
            else if model?.activeSkip != nil { focus = .skipIntro }
            else { focus = .surface }
        }
        .onChange(of: panel) { _, newPanel in
            if newPanel == .none && controlsVisible { focus = .playPause }
        }
        .onChange(of: focus) { _, _ in
            if controlsVisible && panel == .none { resetHide() }
        }
        .onChange(of: model?.activeSkip) { _, skip in
            // Only auto-focus the Skip box when controls are hidden; with controls
            // up the user navigates up to it so the transport stays usable.
            if skip != nil && !controlsVisible { focus = .skipIntro }
            else if skip == nil && !controlsVisible { focus = .surface }
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
        .animation(.smooth(duration: 0.35), value: model?.state.status)
    }

    // MARK: - Paused state

    private func pausedOverlay(_ model: VideoPlayerViewModel) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            // Same title block, same place as the top bar shown when playing, so
            // it doesn't jump when you pause.
            VStack(alignment: .leading, spacing: 4) {
                TitleLogo(logoURL: model.titleLogoURL, title: model.displayTitle,
                          fallbackFont: .system(size: pausedTitleSize, weight: .bold, design: .rounded),
                          fallbackColor: .white, maxWidth: pausedLogoWidth, maxHeight: pausedLogoHeight)
                    .shadow(color: .black.opacity(0.55), radius: 12, y: 3)
                if let sub = model.displaySubtitle {
                    Text(sub).font(Typography.caption).foregroundStyle(.white.opacity(0.75))
                }
                Label("Paused", systemImage: "pause.fill")
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, Spacing.xs)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(pausedPadding)
        }
    }

    // Match the control-bar top title exactly so it stays put on pause.
    private var pausedTitleSize: CGFloat {
        #if os(tvOS)
        34
        #else
        18
        #endif
    }
    private var pausedLogoWidth: CGFloat {
        #if os(tvOS)
        460
        #else
        240
        #endif
    }
    private var pausedLogoHeight: CGFloat {
        #if os(tvOS)
        90
        #else
        54
        #endif
    }
    private var pausedPadding: CGFloat {
        #if os(tvOS)
        Spacing.xl
        #else
        Spacing.lg
        #endif
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

    private var trickplayWidth: CGFloat {
        #if os(tvOS)
        360
        #else
        200
        #endif
    }
    private var trickplayTopPadding: CGFloat {
        #if os(tvOS)
        140
        #else
        80
        #endif
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
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
    /// Extra lift so the Skip box clears the control bar when it's visible.
    private var skipControlClearance: CGFloat {
        #if os(tvOS)
        240
        #else
        150
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
        // Close a panel first; otherwise Back/Menu always exits the player (one
        // press, the way you'd expect) rather than just hiding the controls.
        if panel != .none { panel = .none; return }
        close()
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
            // Don't hide while the user is parked on the scrub bar.
            guard !Task.isCancelled, panel == .none, focus != .scrubBar else { return }
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
