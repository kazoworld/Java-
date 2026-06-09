import Foundation
import Combine
import UIKit

// Import whichever VLCKit module is linked. `tylerjonesio/vlckit-spm` exposes a
// unified `VLCKitSPM` module for iOS + tvOS; the other names cover alternative
// distributions (3.x MobileVLCKit/TVVLCKit, or the 4.x unified `VLCKit`).
#if canImport(VLCKitSPM)
import VLCKitSPM
#elseif canImport(MobileVLCKit)
import MobileVLCKit
#elseif canImport(TVVLCKit)
import TVVLCKit
#elseif canImport(VLCKit)
import VLCKit
#endif

#if canImport(VLCKitSPM) || canImport(MobileVLCKit) || canImport(TVVLCKit) || canImport(VLCKit)

/// VLCKit-backed engine — the same media core Swiftfin relies on. Handles the
/// long tail of codecs/containers (MKV, HEVC variants, exotic audio) that
/// AVFoundation refuses, so direct-play works without forcing a server
/// transcode. Used as the fallback in the hybrid policy.
@MainActor
final class VLCPlaybackEngine: NSObject, PlaybackEngine, VLCMediaPlayerDelegate {
    static let isAvailable = true

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
        // Larger caches smooth out high-bitrate 4K streams where short stalls
        // would otherwise cause dropped frames; VideoToolbox HW decode is on by
        // default on Apple TV so the CPU isn't the bottleneck on real hardware.
        media.addOption(":network-caching=3500")
        media.addOption(":file-caching=3500")
        media.addOption(":clock-jitter=0")
        media.addOption(":clock-synchro=0")
        // Loudness normalization evens out loud/quiet passages (VLC volnorm).
        if SettingsStore.shared.audio.loudnessNormalization {
            media.addOption(":audio-filter=normvol")
            media.addOption(":norm-max-level=2.0")
        }
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

    // MARK: - Subtitles

    var subtitleTracks: [MediaTrack] {
        let indexes = (mediaPlayer.videoSubTitlesIndexes as? [NSNumber])?.map(\.intValue) ?? []
        let names = (mediaPlayer.videoSubTitlesNames as? [String]) ?? []
        var tracks: [MediaTrack] = []
        for (i, idx) in indexes.enumerated() where idx >= 0 { // -1 is VLC's "Disable"
            tracks.append(MediaTrack(id: idx, name: i < names.count ? names[i] : "Subtitle \(idx)"))
        }
        return tracks
    }

    var currentSubtitleID: Int? {
        let current = Int(mediaPlayer.currentVideoSubTitleIndex)
        return current >= 0 ? current : nil
    }

    func selectSubtitle(id: Int?) {
        mediaPlayer.currentVideoSubTitleIndex = Int32(id ?? -1)
    }

    // MARK: - VLCMediaPlayerDelegate
    //
    // VLCKit invokes these on its own thread, so they're `nonisolated` and hop
    // to the main actor before touching player state.

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification!) {
        Task { @MainActor in self.syncState() }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification!) {
        Task { @MainActor in self.syncTime() }
    }

    private func syncState() {
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

    private func syncTime() {
        var state = subject.value
        state.currentTime = Double(mediaPlayer.time.intValue) / 1000.0
        if let length = mediaPlayer.media?.length.intValue, length > 0 {
            state.duration = Double(length) / 1000.0
        }
        // If time is advancing the stream is really playing — clear any stuck
        // buffering spinner even if a state-change callback was missed.
        if mediaPlayer.isPlaying, state.status == .buffering {
            state.status = .playing
        }
        subject.value = state
    }
}

#else

/// Stub used when no VLCKit module is linked, so the project still compiles. The
/// hybrid coordinator detects this via `VLCPlaybackEngine.isAvailable` and stays
/// on AVPlayer rather than handing playback to a no-op.
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
