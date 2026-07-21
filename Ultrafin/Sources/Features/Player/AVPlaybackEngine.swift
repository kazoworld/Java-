import AVFoundation
import Combine
import CoreMedia
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
        // Don't wait to minimize stalling — resume/seek should start the instant
        // we ask, not after a re-buffer evaluation (a source of resume lag).
        player.automaticallyWaitsToMinimizeStalling = false
        // Don't let AVFoundation auto-enable subtitles from the system's
        // accessibility / preferred-language criteria — captions are controlled
        // explicitly by the app (this was the source of captions turning
        // themselves on at playback start even with captions set to Off).
        player.appliesMediaSelectionCriteriaAutomatically = false
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
        // Apply the app's caption style (font, size, color, background, bold) —
        // previously the native player ignored it entirely.
        item.textStyleRules = Self.captionStyleRules()
        observe(item: item)
        player.replaceCurrentItem(with: item)
        if seconds > 1 {
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        }
        subject.value.status = .buffering
    }

    /// The user's caption appearance as AVPlayer text-markup rules.
    private static func captionStyleRules() -> [AVTextStyleRule] {
        let subs = SettingsStore.shared.subtitles
        var attrs: [String: Any] = [
            kCMTextMarkupAttribute_RelativeFontSize as String: subs.size.scalePercent,
            kCMTextMarkupAttribute_ForegroundColorARGB as String: subs.textColor.argb,
            kCMTextMarkupAttribute_FontFamilyName as String: subs.font.fontName
        ]
        if subs.boldText {
            attrs[kCMTextMarkupAttribute_BoldStyle as String] = true
        }
        if subs.background == .box {
            attrs[kCMTextMarkupAttribute_CharacterBackgroundColorARGB as String] =
                [0.72, 0, 0, 0] as [NSNumber]
        }
        guard let rule = AVTextStyleRule(textMarkupAttributes: attrs) else { return [] }
        return [rule]
    }

    func play() {
        // Make sure the audio route is up before resuming so audio returns with
        // the picture instead of fading in a couple seconds later, then resume
        // immediately (no re-buffer wait).
        AudioSession.ensureActive()
        if player.currentItem != nil {
            player.playImmediately(atRate: 1.0)
        } else {
            player.play()
        }
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
        // Re-entry insurance: never stack observers if load() runs twice.
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        statusObservation?.invalidate()
        if let itemEndObserver { NotificationCenter.default.removeObserver(itemEndObserver); self.itemEndObserver = nil }
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
                    // Start with subtitles off by default; the view model turns
                    // them on only when the user's caption mode asks for it. This
                    // clears any subtitle the container flags as "default".
                    if let group = self.legibleGroup { item.select(nil, in: group) }
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
        // Cross-platform now (previously iOS-only, which left tvOS audio cold and
        // dropping the first seconds on each playback).
        AudioSession.activateForPlayback()
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

    // MARK: - Audio tracks

    private var audibleGroup: AVMediaSelectionGroup? {
        player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: .audible)
    }

    var audioTracks: [MediaTrack] {
        guard let group = audibleGroup else { return [] }
        return group.options.enumerated().map { MediaTrack(id: $0.offset, name: $0.element.displayName) }
    }

    var currentAudioID: Int? {
        guard let group = audibleGroup, let item = player.currentItem,
              let selected = item.currentMediaSelection.selectedMediaOption(in: group)
        else { return nil }
        return group.options.firstIndex(of: selected)
    }

    func selectAudio(id: Int) {
        guard let group = audibleGroup, let item = player.currentItem,
              group.options.indices.contains(id) else { return }
        item.select(group.options[id], in: group)
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
