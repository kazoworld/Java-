import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Ultrafin's bridge to the system accessibility settings.
///
/// Apple's guidance here is unusually specific, and worth taking literally:
/// controls measure at least 44×44 points, text is never below 11, and the
/// system switches — Reduce Motion, Reduce Transparency — are instructions
/// rather than hints. Reduce Motion in particular exists because large-scale
/// movement can be genuinely unpleasant for people with vestibular disorders,
/// and an app built out of drifting gradients, breathing artwork and zooming
/// pages is precisely the case it was written for.
enum A11y {
    /// "Create controls that measure at least 44 points x 44 points so they can
    /// be accurately tapped with a finger." — Apple, UI Design Dos and Don'ts.
    static let minimumTarget: CGFloat = 44
}

extension View {
    /// Guarantee a comfortable hit target without changing how a control looks.
    ///
    /// The glyph keeps whatever size the design calls for; this only grows the
    /// *touchable* area around it, which is the part a finger actually has to
    /// find. Several of the player's controls drew at 34 points square.
    func minimumHitTarget(_ side: CGFloat = A11y.minimumTarget) -> some View {
        frame(minWidth: side, minHeight: side)
    }
}

// MARK: - Motion

/// An animation that yields when the system asks for less movement.
private struct CalmAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V
    let reduced: Animation?

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? reduced : animation, value: value)
    }
}

extension View {
    /// Like `.animation(_:value:)`, but honours Reduce Motion.
    ///
    /// The reduced form defaults to a plain cross-fade rather than nothing at
    /// all: Reduce Motion asks for less *movement*, not for state to change
    /// invisibly, and a hard cut is its own kind of jarring.
    func calmAnimation<V: Equatable>(_ animation: Animation?, value: V,
                                     reduced: Animation? = .easeInOut(duration: 0.2)) -> some View {
        modifier(CalmAnimation(animation: animation, value: value, reduced: reduced))
    }
}

// MARK: - Type

/// A designed point size that still grows with the reader's text setting.
///
/// `Font.system(size:)` is frozen — it ignores Dynamic Type entirely, which is
/// why every fixed size in a codebase is quietly an accessibility bug. This
/// scales the design's size through `UIFontMetrics` and caps the result, so a
/// list stays readable at large text sizes without a single row swallowing the
/// screen.
private struct ScaledFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    let size: CGFloat
    let weight: Font.Weight
    let relativeTo: UIFont.TextStyle
    let maximum: CGFloat

    func body(content: Content) -> some View {
        content.font(.system(size: resolved, weight: weight))
    }

    /// Reading `typeSize` above is what re-evaluates this when the setting
    /// changes; `UIFontMetrics` itself reports off the current trait collection.
    private var resolved: CGFloat {
        min(UIFontMetrics(forTextStyle: relativeTo).scaledValue(for: size), maximum)
    }
}

extension View {
    /// A system font at `size` that grows with Dynamic Type, up to `maximum`.
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular,
                    relativeTo style: UIFont.TextStyle = .body,
                    maximum: CGFloat? = nil) -> some View {
        modifier(ScaledFont(size: size, weight: weight, relativeTo: style,
                            maximum: maximum ?? size * 1.6))
    }
}
