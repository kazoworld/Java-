import AVFoundation

/// Centralized audio-session setup for video playback.
///
/// The previous setup only configured the session on iOS (`#if os(iOS)`), so on
/// **tvOS the session was never configured or activated** — the audio route to
/// the TV/receiver was cold when playback began, dropping the first couple of
/// seconds of audio (the "audio comes in late" delay). Configuring the session
/// for long-form movie playback and activating it *early* (when the player
/// appears, before the stream loads) primes the route so audio is there the
/// instant video starts. Used by both the AVPlayer and VLCKit engines since they
/// share the process-wide `AVAudioSession`.
enum AudioSession {
    /// Configure the shared session for full-screen video and open the route.
    /// Safe to call repeatedly; cheap once already configured/active.
    static func activateForPlayback() {
        configureCategory()
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Just set the category (no route grab) — call at launch so the first
    /// activation is as fast as possible.
    static func prepare() {
        configureCategory()
    }

    /// Re-assert that the session is active (cheap no-op if it already is). Call
    /// on every resume so the audio route is guaranteed up before playback
    /// continues, in case it went idle while paused.
    static func ensureActive() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// `.moviePlayback` + (on iOS) the long-form-video routing policy is the
    /// recommended pairing for full-screen video. The route-sharing policy is
    /// iOS-only — `.longFormVideo` is unavailable on tvOS — so it's guarded.
    private static func configureCategory() {
        let session = AVAudioSession.sharedInstance()
        #if os(iOS)
        do {
            try session.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
        } catch {
            try? session.setCategory(.playback, mode: .moviePlayback)
        }
        #else
        try? session.setCategory(.playback, mode: .moviePlayback)
        #endif
    }
}
