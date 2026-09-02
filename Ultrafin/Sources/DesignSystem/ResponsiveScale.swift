import SwiftUI

/// Sizes derived from the space a screen actually has, so the onboarding
/// surfaces read correctly on an iPhone SE, a Pro Max, an iPad and a 4K TV
/// without a pile of per-device constants.
///
/// The scale is anchored on a reference width per platform and clamped, so text
/// grows on bigger canvases but never balloons or collapses.
struct ResponsiveScale {
    let size: CGSize

    /// 1.0 at the reference device; smaller on compact phones, larger on pads
    /// and TVs.
    var factor: CGFloat {
        #if os(tvOS)
        let reference: CGFloat = 1920
        let bounds: ClosedRange<CGFloat> = 0.85...1.15
        #else
        let reference: CGFloat = 393 // iPhone 16 Pro width
        let bounds: ClosedRange<CGFloat> = 0.84...1.35
        #endif
        // Use the shorter edge so landscape doesn't inflate everything.
        let basis = min(size.width, size.height)
        return min(max(basis / reference, bounds.lowerBound), bounds.upperBound)
    }

    /// Scale a point size, rounded to a whole point to keep text crisp.
    func callAsFunction(_ points: CGFloat) -> CGFloat {
        (points * factor).rounded()
    }

    /// True when vertical room is tight (landscape phone) — screens use this to
    /// drop to a side-by-side arrangement instead of squeezing.
    var isVerticallyTight: Bool {
        #if os(tvOS)
        false
        #else
        size.height < 520
        #endif
    }
}
