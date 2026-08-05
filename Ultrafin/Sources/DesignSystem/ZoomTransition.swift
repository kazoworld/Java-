import SwiftUI

/// Zoom navigation transitions: a pushed page grows out of the thing you
/// tapped, and — the reason this exists — the swipe back is *interactive*.
///
/// The default push/pop plays a fixed-duration slide. Your finger starts it and
/// then watches it, which is what reads as choppy: the animation isn't
/// following you, it's replaying at you. A zoom transition is driven by the
/// gesture the whole way, so dragging back tracks your thumb and releasing
/// hands off to a spring from wherever you let go.
///
/// tvOS has no interactive back gesture and no matched-transition support, so
/// both of these are no-ops there.
extension View {
    /// Marks the tappable card a push should zoom out of. `id` must match the
    /// `zoomedFrom` id on the destination; when it doesn't, the system quietly
    /// falls back to the standard push rather than misbehaving.
    @ViewBuilder
    func zoomSource(_ id: some Hashable, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        matchedTransitionSource(id: id, in: namespace)
        #else
        self
        #endif
    }

    /// Marks the destination page as the far end of that zoom.
    @ViewBuilder
    func zoomedFrom(_ id: some Hashable, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        navigationTransition(.zoom(sourceID: id, in: namespace))
        #else
        self
        #endif
    }
}
