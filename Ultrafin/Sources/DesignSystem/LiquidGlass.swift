import SwiftUI

/// The app's signature **Liquid Glass** material layer — now backed by the
/// system's real Liquid Glass (`glassEffect`, OS 26): genuinely refractive,
/// live-sampling material identical to the rest of the platform.
///
/// What keeps it *ours* is the lighting layered on top: a specular rim along
/// the top-leading edge, a soft top sheen, and accent-colored lift glows. The
/// system provides the physics; these tokens provide the brand.
enum LiquidGlass {
    /// The rim light: bright at the top-leading edge, fading to nothing around
    /// the middle, with a whisper returning at the bottom-trailing — the single
    /// most recognizable "edge of glass" cue. Used as a `strokeBorder` style.
    static func rim(_ intensity: Double = 1) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: .white.opacity(0.70 * intensity), location: 0.0),
            .init(color: .white.opacity(0.16 * intensity), location: 0.30),
            .init(color: .white.opacity(0.0), location: 0.55),
            .init(color: .white.opacity(0.12 * intensity), location: 1.0)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The surface sheen: a soft highlight concentrated along the top that gives
    /// a pane its glossy, faintly convex reflection. Used as a `fill` on solid
    /// surfaces (accent buttons, artwork) that don't carry system glass.
    static var sheen: LinearGradient {
        LinearGradient(stops: [
            .init(color: .white.opacity(0.24), location: 0.0),
            .init(color: .white.opacity(0.06), location: 0.16),
            .init(color: .clear, location: 0.5)
        ], startPoint: .top, endPoint: .bottom)
    }
}

/// System Liquid Glass clipped to a continuous rounded rectangle, finished with
/// the brand rim light and a soft lift shadow.
struct LiquidGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Spacing.cornerRadius
    /// An optional content color the glass leans toward (e.g. artwork color).
    var tint: Color? = nil
    var shadow: Bool = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.35)) } ?? .regular, in: shape)
            .overlay(shape.strokeBorder(LiquidGlass.rim(0.8), lineWidth: 1))
            .shadow(color: shadow ? .black.opacity(0.28) : .clear,
                    radius: shadow ? 18 : 0, y: shadow ? 12 : 0)
    }
}

extension View {
    /// The signature liquid-glass panel: real system glass + brand rim light +
    /// soft lift shadow. Use for cards, sheets, popovers and prominent controls.
    func liquidGlass(cornerRadius: CGFloat = Spacing.cornerRadius,
                     tint: Color? = nil, shadow: Bool = true) -> some View {
        modifier(LiquidGlassSurface(cornerRadius: cornerRadius, tint: tint, shadow: shadow))
    }

    /// Just the rim highlight, for views that already have their own fill (e.g.
    /// the accent primary button or an artwork tile).
    func specularRim(cornerRadius: CGFloat, intensity: Double = 1) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(LiquidGlass.rim(intensity), lineWidth: 1)
        )
    }

    /// A Liquid Glass **pill** for overlay controls that sit on artwork (hero
    /// buttons, badges). `dim` darkens the glass slightly so white text stays
    /// legible over bright backdrops.
    func glassCapsule(dim: Double = 0.22) -> some View {
        glassEffect(dim > 0 ? Glass.regular.tint(.black.opacity(dim)) : .regular, in: .capsule)
            .overlay(Capsule().strokeBorder(LiquidGlass.rim(0.85), lineWidth: 1))
    }

    /// A Liquid Glass **circle** — the round sibling of ``glassCapsule`` for
    /// icon-only overlay controls (e.g. the hero's prev/next chevrons).
    func glassCircle(dim: Double = 0.22) -> some View {
        glassEffect(dim > 0 ? Glass.regular.tint(.black.opacity(dim)) : .regular, in: .circle)
            .overlay(Circle().strokeBorder(LiquidGlass.rim(0.85), lineWidth: 1))
    }

    /// Floating chrome glass — the bottom bar and its switcher.
    ///
    /// Deliberately **untinted**. The other glass helpers darken the material to
    /// keep white text legible over bright artwork, but the bottom bar spends
    /// most of its life over a true-black music canvas, where darkening glass
    /// only ever produces a blacker hole. Clear material plus a real specular
    /// edge is what makes it read as glass in both cases: over artwork it
    /// refracts, and over black the lit rim is what draws the shape.
    ///
    /// `interactive()` lets the material flex under a press, which is most of
    /// what separates Liquid Glass from a blurred rectangle.
    func barGlass(shape: some Shape & InsettableShape) -> some View {
        glassEffect(.regular.interactive(), in: shape)
            .overlay(shape.strokeBorder(LiquidGlass.rim(1.0), lineWidth: 1))
            // A second hairline just inside the first: the doubled edge is what
            // gives real glass its thickness rather than looking like a sticker.
            .overlay(shape.strokeBorder(.white.opacity(0.10), lineWidth: 0.5).padding(1))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    /// Accent-tinted interactive glass — the "colored glass" treatment for
    /// primary pills (hero Play, tour Continue): the system material drinks the
    /// color and reacts to presses.
    func tintedGlassCapsule(_ color: Color, strength: Double = 0.55) -> some View {
        glassEffect(Glass.regular.tint(color.opacity(strength)).interactive(), in: .capsule)
            .overlay(Capsule().strokeBorder(LiquidGlass.rim(0.6), lineWidth: 1))
    }
}
