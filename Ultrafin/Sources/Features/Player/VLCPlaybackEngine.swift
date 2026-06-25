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
        // A healthy buffer keeps audio and video in sync — too small starves the
        // (heavier) video decoder so it slips behind the audio (lips lag the
        // talking). Resume speed is handled by AudioRouteKeeper, not this buffer,
        // so we can afford a proper 2s buffer here without re-introducing the
        // resume delay.
        media.addOption(":network-caching=2000")
        media.addOption(":file-caching=2000")
        media.addOption(":audio-desync=0")
        // Loudness normalization evens out loud/quiet passages (VLC volnorm).
        let audio = SettingsStore.shared.audio
        if audio.loudnessNormalization {
            media.addOption(":audio-filter=normvol")
            media.addOption(":norm-max-level=2.0")
        }
        // Auto-select the preferred audio language at open (English by default),
        // so files that default to another language (e.g. Russian) start in the
        // right one. An explicit preference wins over the English default.
        if !audio.preferredLanguage.isEmpty {
            media.addOption(":audio-language=\(audio.preferredLanguage)")
        } else if SettingsStore.shared.preferEnglishAudio {
            media.addOption(":audio-language=eng,en,english")
        }

        // Subtitle appearance + language.
        let subs = SettingsStore.shared.subtitles
        media.addOption(":sub-text-scale=\(subs.size.scalePercent)")
        media.addOption(":freetype-color=\(subs.textColor.vlcColor)")
        if !subs.preferredLanguage.isEmpty {
            media.addOption(":sub-language=\(subs.preferredLanguage)")
        } else if subs.captionMode != .always {
            // Don't auto-enable a subtitle the container flags as "default" when
            // captions are meant to be off — open with no SPU track selected.
            // (The view model still turns them on for "Always on" / when engaged.)
            media.addOption(":sub-track=-1")
        }

        mediaPlayer.media = media
        // Decode audio to PCM unless the user explicitly wants bitstream
        // passthrough. Passthrough makes the receiver re-lock the audio format
        // after a pause (the multi-second audio gap on resume); decoding keeps a
        // stable PCM route that resumes instantly, like other streaming apps.
        mediaPlayer.audio?.passthrough = audio.passthrough
        subject.value.status = .buffering
    }

    func play() {
        AudioSession.ensureActive()
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

    // MARK: - Audio tracks

    var audioTracks: [MediaTrack] {
        let indexes = (mediaPlayer.audioTrackIndexes as? [NSNumber])?.map(\.intValue) ?? []
        let names = (mediaPlayer.audioTrackNames as? [String]) ?? []
        var tracks: [MediaTrack] = []
        for (i, idx) in indexes.enumerated() where idx >= 0 { // -1 is "Disable"
            tracks.append(MediaTrack(id: idx, name: i < names.count ? names[i] : "Audio \(idx)"))
        }
        return tracks
    }

    var currentAudioID: Int? {
        let current = Int(mediaPlayer.currentAudioTrackIndex)
        return current >= 0 ? current : nil
    }

    func selectAudio(id: Int) {
        mediaPlayer.currentAudioTrackIndex = Int32(id)
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
