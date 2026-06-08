import Foundation
import Combine
import UIKit

#if canImport(VLCKit)
import VLCKit

/// VLCKit-backed engine — the same media core Swiftfin relies on. Handles the
/// long tail of codecs/containers (MKV, HEVC variants, exotic audio) that
/// AVFoundation refuses, so direct-play works without forcing a server
/// transcode. Used as the fallback in the hybrid policy.
@MainActor
final class VLCPlaybackEngine: NSObject, PlaybackEngine, VLCMediaPlayerDelegate {
    private let mediaPlayer = VLCMediaPlayer()
    private let videoView = UIView()
    private let subject = CurrentValueSubject<PlaybackState, Never>(PlaybackState())
    private var pendingStart: Double = 0

    override init() {
        super.init()
        videoView.backgroundColor = .black
        mediaPlayer.drawable = videoView
        mediaPlayer.delegate = self
    }

    var playerLayerView: PlatformView { videoView }
    var statePublisher: AnyPublisher<PlaybackState, Never> { subject.eraseToAnyPublisher() }

    func load(url: URL, startAt seconds: Double) {
        pendingStart = seconds
        let media = VLCMedia(url: url)
        // Keep the network cache modest so seeking stays responsive.
        media.addOption(":network-caching=1500")
        mediaPlayer.media = media
        subject.value.status = .buffering
    }

    func play() {
        mediaPlayer.play()
        subject.value.status = .playing
    }

    func pause() {
        mediaPlayer.pause()
        subject.value.status = .paused
    }

    func seek(to seconds: Double) {
        guard mediaPlayer.media != nil else { return }
        mediaPlayer.time = VLCTime(int: Int32(seconds * 1000))
    }

    func teardown() {
        mediaPlayer.stop()
        mediaPlayer.media = nil
    }

    // MARK: - VLCMediaPlayerDelegate

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        switch mediaPlayer.state {
        case .playing:
            subject.value.status = .playing
            if pendingStart > 1 { seek(to: pendingStart); pendingStart = 0 }
        case .paused:
            subject.value.status = .paused
        case .stopped, .ended:
            subject.value.status = .ended
        case .error:
            subject.value.status = .failed("VLC could not play this media")
        case .buffering:
            subject.value.status = .buffering
        default:
            break
        }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        var state = subject.value
        state.currentTime = Double(mediaPlayer.time.intValue) / 1000.0
        if let length = mediaPlayer.media?.length.intValue, length > 0 {
            state.duration = Double(length) / 1000.0
        }
        subject.value = state
    }
}

#else

/// Stub used when VLCKit isn't linked, so the project still compiles. The hybrid
/// coordinator detects this via `VLCPlaybackEngine.isAvailable` and stays on
/// AVPlayer rather than handing playback to a no-op.
@MainActor
final class VLCPlaybackEngine: PlaybackEngine {
    static let isAvailable = false
    private let view = PlatformView()
    private let subject = CurrentValueSubject<PlaybackState, Never>(PlaybackState())

    var playerLayerView: PlatformView { view }
    var statePublisher: AnyPublisher<PlaybackState, Never> { subject.eraseToAnyPublisher() }

    func load(url: URL, startAt seconds: Double) {
        subject.value.status = .failed("VLCKit is not available in this build")
    }
    func play() {}
    func pause() {}
    func seek(to seconds: Double) {}
    func teardown() {}
}

#endif

#if canImport(VLCKit)
extension VLCPlaybackEngine {
    static let isAvailable = true
}
#endif
