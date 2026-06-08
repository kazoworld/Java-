import Foundation
import Combine
import Observation

/// Drives the player screen. Resolves the stream, picks the engine per the
/// user's policy, mirrors engine state for the UI, and reports progress back to
/// the server on a throttled cadence.
@Observable
@MainActor
final class VideoPlayerViewModel {
    private(set) var state = PlaybackState()
    private(set) var engine: PlaybackEngine?
    private(set) var activeEngineName = ""
    var errorMessage: String?

    let item: MediaItem
    private let userID: String
    private let client: JellyfinClient
    private let settings: PlaybackPreferences

    private var cancellable: AnyCancellable?
    private var resolution: PlaybackResolution?
    private var lastReportedSecond: Int = -1

    init(item: MediaItem, userID: String, client: JellyfinClient, settings: PlaybackPreferences) {
        self.item = item
        self.userID = userID
        self.client = client
        self.settings = settings
    }

    var seekInterval: Double { Double(settings.seekInterval) }

    func start() async {
        do {
            let resolution = try await client.resolvePlayback(for: item, userID: userID)
            self.resolution = resolution
            let engine = makeEngine(for: resolution)
            bind(to: engine)
            self.engine = engine

            let startSeconds = resumeSeconds()
            engine.load(url: resolution.streamURL, startAt: startSeconds)
            engine.play()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Couldn't start playback."
        }
    }

    /// Chooses the concrete engine based on the user's policy and whether the
    /// resolved source is something AVFoundation can actually direct-play.
    private func makeEngine(for resolution: PlaybackResolution) -> PlaybackEngine {
        switch settings.enginePolicy {
        case .nativeOnly:
            activeEngineName = "AVPlayer"
            return AVPlaybackEngine()
        case .vlcOnly:
            activeEngineName = "VLCKit"
            return VLCPlaybackEngine()
        case .hybrid:
            if resolution.isDirectPlay || !VLCPlaybackEngine.isAvailable {
                activeEngineName = "AVPlayer"
                return AVPlaybackEngine()
            } else {
                activeEngineName = "VLCKit"
                return VLCPlaybackEngine()
            }
        }
    }

    private func bind(to engine: PlaybackEngine) {
        cancellable = engine.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self else { return }
                self.state = newState
                self.reportProgressIfNeeded(newState)
            }
    }

    func togglePlayPause() {
        guard let engine else { return }
        if state.status == .playing { engine.pause() } else { engine.play() }
    }

    func skip(by seconds: Double) {
        let target = max(0, min(state.duration, state.currentTime + seconds))
        engine?.seek(to: target)
    }

    func seek(toProgress progress: Double) {
        engine?.seek(to: progress * state.duration)
    }

    func stop() {
        engine?.teardown()
        cancellable?.cancel()
        Task { await reportStopped() }
    }

    // MARK: - Progress reporting

    private func resumeSeconds() -> Double {
        guard settings.autoResume, let ticks = item.userData?.playbackPositionTicks, ticks > 0 else { return 0 }
        return Double(ticks) / 10_000_000.0
    }

    private func reportProgressIfNeeded(_ state: PlaybackState) {
        let second = Int(state.currentTime)
        // Report roughly once every 5s of playback to keep the server in sync.
        guard second != lastReportedSecond, second % 5 == 0, state.status == .playing else { return }
        lastReportedSecond = second
        let ticks = Int64(state.currentTime * 10_000_000)
        Task {
            await client.reportPlaybackProgress(
                itemID: item.id, positionTicks: ticks, isPaused: false, playSessionID: resolution?.playSessionID
            )
        }
    }

    private func reportStopped() async {
        let ticks = Int64(state.currentTime * 10_000_000)
        await client.reportPlaybackProgress(
            itemID: item.id, positionTicks: ticks, isPaused: true, playSessionID: resolution?.playSessionID
        )
    }
}
