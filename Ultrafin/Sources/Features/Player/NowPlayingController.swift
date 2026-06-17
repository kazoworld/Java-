import MediaPlayer

/// Publishes playback to the system **Now Playing** info center and registers
/// remote commands.
///
/// This is what makes the app show up as the Apple TV's active "Now Playing"
/// app — which is how external integrations (Control Center, the Siri Remote's
/// system transport, and **Home Assistant via pyatv**) see play/pause state.
/// Without it, our custom player is invisible to those, so HA automations that
/// react to play/pause never fire for this app (they work in YouTube because it
/// publishes this state).
@MainActor
final class NowPlayingController {
    private var didConfigure = false

    /// Register the system transport commands once, routing them into the player.
    /// Handlers are invoked on the main thread by `MPRemoteCommandCenter`.
    func configure(onPlay: @escaping @MainActor () -> Void,
                   onPause: @escaping @MainActor () -> Void,
                   onToggle: @escaping @MainActor () -> Void,
                   onSeek: @escaping @MainActor (Double) -> Void) {
        guard !didConfigure else { return }
        didConfigure = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { _ in MainActor.assumeIsolated { onPlay() }; return .success }
        c.pauseCommand.addTarget { _ in MainActor.assumeIsolated { onPause() }; return .success }
        c.togglePlayPauseCommand.addTarget { _ in MainActor.assumeIsolated { onToggle() }; return .success }
        c.changePlaybackPositionCommand.addTarget { event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { onSeek(e.positionTime) }
            return .success
        }
    }

    func update(title: String, subtitle: String?, duration: Double, elapsed: Double, isPlaying: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, elapsed),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let subtitle, !subtitle.isEmpty { info[MPMediaItemPropertyArtist] = subtitle }
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(tvOS)
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        #endif
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(tvOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.removeTarget(nil)
        c.pauseCommand.removeTarget(nil)
        c.togglePlayPauseCommand.removeTarget(nil)
        c.changePlaybackPositionCommand.removeTarget(nil)
        didConfigure = false
    }
}
