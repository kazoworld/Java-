import SwiftUI
import AVFoundation
import Observation

/// Drives a detail page's ambient media: the muted video highlight that plays
/// behind the cover art (theater mode) and the title's theme song. One volume
/// button rules both — muted by default; unmuting favors the video's own audio
/// when the highlight is rolling, else the theme music.
@Observable
@MainActor
final class TheaterController {
    /// True once the highlight has real frames — the host crossfades it in.
    private(set) var videoActive = false
    /// Whether a theme song is loaded (drives showing the volume button even
    /// when the highlight can't play).
    private(set) var hasAudio = false

    var muted = true {
        didSet { applyVolume() }
    }

    private let videoPlayer = AVPlayer()
    private let themePlayer = AVPlayer()
    private let videoView = PlayerLayerView()
    private var statusObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var themeLooper: NSObjectProtocol?
    private var stopped = false

    var layerView: PlatformView { videoView }

    /// Nothing loaded (fresh, or after `stop()`) — safe to start ambiance.
    var isIdle: Bool { videoPlayer.currentItem == nil && themePlayer.currentItem == nil }

    init() {
        videoView.playerLayer.player = videoPlayer
        videoPlayer.isMuted = true
        themePlayer.isMuted = true
        themePlayer.volume = 0.45 // theme music is an undertone, never a blast
    }

    /// Starts the muted highlight: seeks into the meat of the title and loops a
    /// window so browsing never runs into credits.
    func startVideo(url: URL, startAt offset: Double, window: Double = 60) {
        stopped = false
        // Re-entry safety: drop any observers from a previous start first.
        if let timeObserver { videoPlayer.removeTimeObserver(timeObserver); self.timeObserver = nil }
        statusObservation?.invalidate()
        let item = AVPlayerItem(url: url)
        // Browsing preview — never let it hoard bandwidth like real playback.
        item.preferredForwardBufferDuration = 8
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                switch item.status {
                case .readyToPlay:
                    self.videoPlayer.play()
                    withAnimation(.easeInOut(duration: 0.8)) { self.videoActive = true }
                    // The highlight owns the audio channel once it's rolling.
                    self.themePlayer.pause()
                    self.applyVolume()
                case .failed:
                    // Container AVPlayer can't direct-play — stay on the art.
                    self.videoActive = false
                default:
                    break
                }
            }
        }
        videoPlayer.replaceCurrentItem(with: item)
        videoPlayer.seek(to: CMTime(seconds: offset, preferredTimescale: 600))
        // Loop the highlight window.
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = videoPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            if time.seconds > offset + window {
                self.videoPlayer.seek(to: CMTime(seconds: offset, preferredTimescale: 600))
            }
        }
    }

    /// Starts the looping theme song (audible only when unmuted and the video
    /// highlight isn't carrying its own audio).
    func startTheme(url: URL) {
        stopped = false
        hasAudio = true
        if let themeLooper { NotificationCenter.default.removeObserver(themeLooper); self.themeLooper = nil }
        let item = AVPlayerItem(url: url)
        themeLooper = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.themePlayer.seek(to: .zero)
                self?.themePlayer.play()
            }
        }
        themePlayer.replaceCurrentItem(with: item)
        if !videoActive { themePlayer.play() }
        applyVolume()
    }

    /// Backgrounded (e.g. the episodes browser covers the hero) — halt output
    /// without tearing down, so `resume()` picks right back up.
    func pause() {
        videoPlayer.pause()
        themePlayer.pause()
    }

    func resume() {
        guard !stopped else { return }
        if videoPlayer.currentItem != nil, videoActive { videoPlayer.play() }
        else if themePlayer.currentItem != nil { themePlayer.play() }
    }

    /// Full stop — leaving the page or entering real playback.
    func stop() {
        stopped = true
        videoActive = false
        hasAudio = false
        if let timeObserver { videoPlayer.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObservation?.invalidate()
        if let themeLooper { NotificationCenter.default.removeObserver(themeLooper) }
        themeLooper = nil
        videoPlayer.replaceCurrentItem(with: nil)
        themePlayer.replaceCurrentItem(with: nil)
    }

    private func applyVolume() {
        videoPlayer.isMuted = muted
        themePlayer.isMuted = muted || videoActive
    }
}

/// The floating speaker toggle for theater mode / theme music — glass, quiet,
/// and defaulting to muted.
struct TheaterVolumeButton: View {
    @Bindable var controller: TheaterController

    var body: some View {
        Button {
            Haptics.play(.selection)
            controller.muted.toggle()
        } label: {
            Image(systemName: controller.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .glassCircle(dim: 0.2)
                .minimumHitTarget()
        }
        .buttonStyle(UltrafinButtonStyle(focusScale: 1.12, lift: false))
        .accessibilityLabel(controller.muted ? "Unmute preview" : "Mute preview")
    }

    private var iconSize: CGFloat {
        #if os(tvOS)
        24
        #else
        15
        #endif
    }
    private var diameter: CGFloat {
        #if os(tvOS)
        58
        #else
        38
        #endif
    }
}
