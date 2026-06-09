import AVFoundation
import Combine
import UIKit

/// AVFoundation-backed engine. This is the default, smoothest path: hardware
/// decoding, perfectly synced 60fps output, and native HLS for transcodes.
@MainActor
final class AVPlaybackEngine: NSObject, PlaybackEngine {
    private let player = AVPlayer()
    private let layerView = PlayerLayerView()
    private let subject = CurrentValueSubject<PlaybackState, Never>(PlaybackState())

    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var itemEndObserver: NSObjectProtocol?

    override init() {
        super.init()
        layerView.playerLayer.player = player
        player.automaticallyWaitsToMinimizeStalling = true
        configureAudioSession()
    }

    var playerLayerView: PlatformView { layerView }
    var statePublisher: AnyPublisher<PlaybackState, Never> { subject.eraseToAnyPublisher() }

    /// Containers AVFoundation can reliably direct-play. Anything else routes to
    /// VLCKit by the hybrid coordinator. `nonisolated` so the networking actor
    /// can consult it while resolving a stream.
    nonisolated static func canDirectPlay(container: String?) -> Bool {
        guard let container = container?.lowercased() else { return false }
        return ["mp4", "m4v", "mov", "hls", "m3u8", "ts"].contains(container)
    }

    func load(url: URL, startAt seconds: Double) {
        let item = AVPlayerItem(url: url)
        observe(item: item)
        player.replaceCurrentItem(with: item)
        if seconds > 1 {
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        }
        subject.value.status = .buffering
    }

    func play() {
        player.play()
        subject.value.status = .playing
    }

    func pause() {
        player.pause()
        subject.value.status = .paused
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func teardown() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        statusObservation?.invalidate()
        if let itemEndObserver { NotificationCenter.default.removeObserver(itemEndObserver) }
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - Observation

    private func observe(item: AVPlayerItem) {
        // Periodic time updates drive the scrubber at ~4Hz (cheap, smooth enough).
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            var state = self.subject.value
            state.currentTime = time.seconds
            if let duration = item.duration.seconds.isFinite ? item.duration.seconds : nil {
                state.duration = duration
            }
            state.bufferedTime = item.loadedTimeRanges.first.map { CMTimeRangeGetEnd($0.timeRangeValue).seconds } ?? 0
            // Derive play/buffer state from the player itself so the loading
            // spinner can never get stuck once playback is actually running.
            // Pause/end are set explicitly, so we only clear buffering here.
            if state.status != .ended, state.status != .paused {
                switch self.player.timeControlStatus {
                case .playing: state.status = .playing
                case .waitingToPlayAtSpecifiedRate: state.status = .buffering
                default: break
                }
            }
            self.subject.value = state
        }

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .failed:
                    self.subject.value.status = .failed(item.error?.localizedDescription ?? "Playback failed")
                case .readyToPlay:
                    if self.subject.value.status == .buffering { self.play() }
                default: break
                }
            }
        }

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.subject.value.status = .ended }
        }
    }

    private func configureAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    // MARK: - Subtitles (legible media selection)

    private var legibleGroup: AVMediaSelectionGroup? {
        player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
    }

    var subtitleTracks: [MediaTrack] {
        guard let group = legibleGroup else { return [] }
        return group.options.enumerated().map { MediaTrack(id: $0.offset, name: $0.element.displayName) }
    }

    var currentSubtitleID: Int? {
        guard let group = legibleGroup, let item = player.currentItem,
              let selected = item.currentMediaSelection.selectedMediaOption(in: group)
        else { return nil }
        return group.options.firstIndex(of: selected)
    }

    func selectSubtitle(id: Int?) {
        guard let group = legibleGroup, let item = player.currentItem else { return }
        if let id, group.options.indices.contains(id) {
            item.select(group.options[id], in: group)
        } else {
            item.select(nil, in: group)
        }
    }
}

/// A `UIView` whose backing layer is an `AVPlayerLayer`, giving us GPU-composited
/// video without an extra view-controller hop.
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
