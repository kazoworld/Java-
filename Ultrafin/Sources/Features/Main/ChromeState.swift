import SwiftUI
import Observation

/// Tracks whether the app's floating chrome (the now-playing bar) should be
/// condensed. Scroll views report their direction into this; the mini player
/// shrinks to a compact pill as the user moves down a page and expands again on
/// the way back up — the way Apple Music gets out of the content's way.
@Observable
@MainActor
final class ChromeState {
    static let shared = ChromeState()
    private init() {}

    var isCondensed = false

    /// Back to the resting state — called when a tab changes or a scroll view
    /// disappears, so chrome never gets stuck small on a screen that can't scroll.
    func reset() {
        guard isCondensed else { return }
        withAnimation(.smooth(duration: 0.3)) { isCondensed = false }
    }
}

extension View {
    /// Report this scroll view's direction to the app chrome. Scrolling down
    /// past the top condenses the mini player; scrolling up (or returning to the
    /// top) expands it.
    func adaptsChromeOnScroll() -> some View {
        modifier(ChromeScrollModifier())
    }
}

private struct ChromeScrollModifier: ViewModifier {
    /// The offset the last decision was made at — small jitters are ignored so
    /// the bar doesn't flicker between states.
    @State private var anchor: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                MainActor.assumeIsolated {
                    let delta = offset - anchor
                    guard abs(delta) > 8 else { return }
                    anchor = offset
                    // Condensed only while heading down and clear of the top.
                    let condensed = offset > 80 && delta > 0
                    guard ChromeState.shared.isCondensed != condensed else { return }
                    withAnimation(.smooth(duration: 0.3)) {
                        ChromeState.shared.isCondensed = condensed
                    }
                }
            }
            .onDisappear { ChromeState.shared.reset() }
    }
}
