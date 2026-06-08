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
                    PlayerControlsView(model: model, onClose: close)
                        .transition(.opacity)
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
        .task { await startIfNeeded() }
        .onChange(of: model?.state.status) { _, status in
            if status == .ended { close() }
        }
        .onAppear { scheduleHide() }
        .onDisappear { model?.stop() }
        .animation(.smooth(duration: 0.25), value: controlsVisible)
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

/// Bridges the engine's native video view into SwiftUI without recreating it
/// on every state change (which would stutter playback).
struct PlayerSurface: UIViewRepresentable {
    let view: PlatformView
    func makeUIView(context: Context) -> PlatformView { view }
    func updateUIView(_ uiView: PlatformView, context: Context) {}
}
