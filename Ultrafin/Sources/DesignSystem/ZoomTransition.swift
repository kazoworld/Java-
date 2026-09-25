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
/// **Both ends are required.** A destination that declares a zoom with no
/// matching source on screen still runs the transition machinery and comes up
/// empty-handed, which costs a beat of dead input at the end of the gesture. A
/// `navigationDestination` is registered once at the root of a stack but is
/// reached from many screens, so the namespace travels in the environment
/// rather than living in whichever view happened to declare it — that way a
/// card three pushes deep marks itself with the same namespace the destination
/// is looking in.
///
/// tvOS has no interactive back gesture and no matched-transition support, so
/// all of this is inert there.
private struct CardZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The namespace paired zoom transitions resolve against, app-wide.
    var cardZoomNamespace: Namespace.ID? {
        get { self[CardZoomNamespaceKey.self] }
        set { self[CardZoomNamespaceKey.self] = newValue }
    }
}

/// Marks a tappable card as the thing a push should zoom out of.
private struct CardZoomSource: ViewModifier {
    let id: String
    @Environment(\.cardZoomNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        #if os(iOS)
        if let namespace, !reduceMotion {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Marks a destination page as the far end of that zoom.
private struct CardZoomDestination: ViewModifier {
    let id: String
    @Environment(\.cardZoomNamespace) private var namespace
    /// A zoom is a large scale animation across the whole screen — precisely
    /// what Reduce Motion is asking not to see. The standard push remains, and
    /// the system cross-fades it instead.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        #if os(iOS)
        if let namespace, !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Publishes the namespace every paired zoom in this subtree resolves in.
    func cardZoomNamespace(_ namespace: Namespace.ID) -> some View {
        environment(\.cardZoomNamespace, namespace)
    }

    /// The card the push zooms out of. `id` must match ``cardZoomDestination``.
    func cardZoomSource(_ id: String) -> some View {
        modifier(CardZoomSource(id: id))
    }

    /// The page that push arrives at.
    func cardZoomDestination(_ id: String) -> some View {
        modifier(CardZoomDestination(id: id))
    }
}
