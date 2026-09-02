import SwiftUI
import Observation

/// Whether the floating bottom chrome should pull itself in.
///
/// Scrolling down a page is a statement that you want to read it, so the bar
/// gets out of the way: the four tabs collapse to the one you're on and the
/// now-playing bar takes the width they leave behind. Scrolling back up, or
/// reaching the top, restores it.
///
/// This tracks *direction*, not position. Condensing on absolute offset alone
/// means the bar can never come back until you return to the very top, which is
/// wrong on a long library — the moment you start heading back up you're looking
/// for the tabs again.
@Observable
@MainActor
final class ChromeState {
    static let shared = ChromeState()
    private init() {}

    private(set) var isCondensed = false

    /// Back to full size — called when a tab changes or a page disappears, so
    /// the bar is never stuck small on a screen that can't scroll.
    func reset() {
        guard isCondensed else { return }
        withAnimation(Self.transition) { isCondensed = false }
    }

    fileprivate func set(_ condensed: Bool) {
        guard isCondensed != condensed else { return }
        withAnimation(Self.transition) { isCondensed = condensed }
    }

    /// Snappy enough to feel connected to the scroll, soft enough that a bar
    /// changing shape under your thumb doesn't snatch at the eye.
    static let transition: Animation = .snappy(duration: 0.3, extraBounce: 0.05)
}

extension View {
    /// Report this scroll view's direction to the app chrome.
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
                    guard abs(delta) > 12 else { return }
                    anchor = offset
                    // Condensed only while heading down and clear of the top.
                    ChromeState.shared.set(offset > 90 && delta > 0)
                }
            }
            .onDisappear { ChromeState.shared.reset() }
    }
}
