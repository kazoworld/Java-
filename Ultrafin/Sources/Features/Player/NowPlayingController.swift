import MediaPlayer
import UIKit

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
    /// Artwork wrapper cached by image identity — update() runs twice a second
    /// during music playback and must not mint a fresh MPMediaItemArtwork (and
    /// force a system re-decode) on every tick.
    private var cachedArtwork: (image: UIImage, wrapped: MPMediaItemArtwork)?

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

    /// Music adds next/previous-track transport (video uses seek instead).
    func configureSkipCommands(onNext: @escaping @MainActor () -> Void,
                               onPrevious: @escaping @MainActor () -> Void) {
        let c = MPRemoteCommandCenter.shared()
        c.nextTrackCommand.addTarget { _ in MainActor.assumeIsolated { onNext() }; return .success }
        c.previousTrackCommand.addTarget { _ in MainActor.assumeIsolated { onPrevious() }; return .success }
    }

    func update(title: String, subtitle: String?, duration: Double, elapsed: Double, isPlaying: Bool,
                album: String? = nil, artwork: UIImage? = nil, mediaType: MPNowPlayingInfoMediaType = .audio) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, elapsed),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            // Declaring the media type lets iOS present music with its
            // music-style lock screen (the full-screen immersive artwork),
            // rather than a generic media card.
            MPNowPlayingInfoPropertyMediaType: mediaType.rawValue
        ]
        if let subtitle, !subtitle.isEmpty { info[MPMediaItemPropertyArtist] = subtitle }
        if let album, !album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = album }
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork {
            if cachedArtwork?.image !== artwork {
                // Serve EXACTLY the size iOS asks for. The lock screen requests
                // a small thumbnail for the compact widget AND a large size for
                // the full-screen immersive backdrop; handing back one fixed
                // image makes iOS treat it as a thumbnail only. Rendering the
                // requested size (square, matching boundsSize's aspect) lets the
                // system use the art as the full-screen lock-screen background.
                let source = artwork
                let wrapped = MPMediaItemArtwork(boundsSize: source.size) { requested in
                    let format = UIGraphicsImageRendererFormat.preferred()
                    format.opaque = true
                    return UIGraphicsImageRenderer(size: requested, format: format).image { _ in
                        source.draw(in: CGRect(origin: .zero, size: requested))
                    }
                }
                cachedArtwork = (artwork, wrapped)
            }
            info[MPMediaItemPropertyArtwork] = cachedArtwork?.wrapped
        }
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
        c.nextTrackCommand.removeTarget(nil)
        c.previousTrackCommand.removeTarget(nil)
        didConfigure = false
    }
}
