import SwiftUI
#if os(tvOS)
import UIKit

/// Watches for any sign of life from the Siri Remote, so the app can tell when
/// nobody is looking at the screen.
///
/// Focus changes are no use for this: when the room has gone quiet there are no
/// focus changes, which is precisely the state we're trying to detect. What's
/// needed is the opposite signal — anything at all arriving from the remote —
/// and the only place that's reliably visible is the window, before any view
/// has had a chance to consume it.
@Observable
@MainActor
final class RemoteIdleState {
    static let shared = RemoteIdleState()
    private init() {}

    /// How long the remote has to stay still before the screen goes dark.
    static let threshold: TimeInterval = 30

    private(set) var isIdle = false

    /// Set while something on screen would actually react to going idle. The
    /// clock only runs when armed — there's no reason to burn a wakeup a second
    /// while nothing is playing.
    var isArmed = false {
        didSet {
            guard isArmed != oldValue else { return }
            if isArmed { start() } else { stop() }
        }
    }

    private var lastInput = Date.now
    private var ticker: Task<Void, Never>?

    /// Called from the window for every touch and every button press.
    func noteActivity() {
        lastInput = .now
        guard isIdle else { return }
        withAnimation(.easeInOut(duration: 0.5)) { isIdle = false }
    }

    private func start() {
        lastInput = .now
        // Apple's own screensaver would otherwise take the screen out from under
        // ours after a couple of minutes.
        UIApplication.shared.isIdleTimerDisabled = true
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isArmed else { return }
                let quiet = Date.now.timeIntervalSince(self.lastInput)
                if quiet >= Self.threshold, !self.isIdle {
                    withAnimation(.easeInOut(duration: 1.2)) { self.isIdle = true }
                }
            }
        }
    }

    private func stop() {
        ticker?.cancel()
        ticker = nil
        UIApplication.shared.isIdleTimerDisabled = false
        if isIdle {
            withAnimation(.easeInOut(duration: 0.5)) { isIdle = false }
        }
    }
}

/// A recognizer that never recognizes. It exists only to see input go past —
/// failing immediately means it can't swallow a press or delay a touch, so
/// nothing downstream can tell it's there.
///
/// Both overrides call super, and that is not a formality: without it the press
/// is never handed on, which is what made the Menu button stop dismissing the
/// player while the idle screen was up. A watcher that eats the input it was
/// only supposed to observe is worse than no watcher at all.
private final class PassiveInputRecognizer: UIGestureRecognizer {
    var onInput: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        onInput?()
        state = .failed
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        super.pressesBegan(presses, with: event)
        onInput?()
        state = .failed
    }
}

/// Attaches the recognizer to the window rather than to itself, so input is seen
/// wherever it lands — including on top of a presented full-screen player.
private final class ActivityProbeView: UIView {
    private var recognizer: PassiveInputRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window, recognizer == nil else { return }
        let probe = PassiveInputRecognizer(target: nil, action: nil)
        probe.cancelsTouchesInView = false
        probe.delaysTouchesBegan = false
        probe.delaysTouchesEnded = false
        probe.onInput = { RemoteIdleState.shared.noteActivity() }
        window.addGestureRecognizer(probe)
        recognizer = probe
    }
}

private struct ActivityProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = ActivityProbeView()
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension View {
    /// Report remote activity from this view's window into ``RemoteIdleState``.
    func tracksRemoteActivity() -> some View {
        background(ActivityProbe().frame(width: 0, height: 0).allowsHitTesting(false))
    }
}
#endif
