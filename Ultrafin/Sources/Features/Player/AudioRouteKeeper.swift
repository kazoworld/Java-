import AVFoundation

/// Keeps the audio route warm by playing a continuous stream of digital silence.
///
/// VLCKit stops feeding audio the instant you pause, so an HDMI/eARC link to a
/// soundbar or receiver (e.g. Sonos) goes idle and drops its lock — and audio
/// returns a couple seconds late on resume while the link re-negotiates. Native
/// players avoid this by never letting the output go fully silent. This runs a
/// tiny zero-sample `AVAudioEngine` graph alongside the player's own output
/// (the two mix; our part is inaudible), so the route stays established across
/// pause and playback resumes with audio immediately.
///
/// Failure-safe: if the engine can't start it simply does nothing and normal
/// playback is unaffected.
@MainActor
final class AudioRouteKeeper {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var running = false

    func start(retriesLeft: Int = 5) {
        guard !running else { return }
        let format = engine.outputNode.outputFormat(forBus: 0)
        // The route isn't ready until the session is active and a real output
        // format is available; retry briefly if it isn't yet.
        guard format.sampleRate > 0, format.channelCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
            if retriesLeft > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    self.start(retriesLeft: retriesLeft - 1)
                }
            }
            return
        }
        buffer.frameLength = buffer.frameCapacity // zero-initialized == digital silence

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            engine.prepare()
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            player.play()
            running = true
        } catch {
            running = false
        }
    }

    func stop() {
        guard running else { return }
        player.stop()
        engine.stop()
        running = false
    }
}
