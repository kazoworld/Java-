import SwiftUI

/// The app's signature **Liquid Glass** material layer.
///
/// Real glass isn't a flat translucent panel: it catches a bright specular
/// highlight along its top-leading edge, carries a faint sheen across its
/// surface, and drops a soft ambient shadow that floats it off the background.
/// These helpers compose those three cues on top of `.ultraThinMaterial` so
/// every surface — cards, sheets, buttons, list rows, overlay pills — reads as a
/// single pane of lit glass in both light and dark.
///
/// It's all gradients and strokes (no extra `blur` passes beyond the system
/// material), so it stays GPU-cheap and never costs frame rate, even on Apple TV.
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
    /// the pane its glossy, faintly convex reflection. Used as a `fill`.
    static var sheen: LinearGradient {
        LinearGradient(stops: [
            .init(color: .white.opacity(0.24), location: 0.0),
            .init(color: .white.opacity(0.06), location: 0.16),
            .init(color: .clear, location: 0.5)
        ], startPoint: .top, endPoint: .bottom)
    }
}

/// Frosted material + top sheen + rim light + soft lift shadow, clipped to a
/// continuous rounded rectangle. The shadow is cast by the pane itself (not the
/// wrapped content) so cards float cleanly.
struct LiquidGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Spacing.cornerRadius
    /// An optional content color the glass leans toward (e.g. artwork color).
    var tint: Color? = nil
    var shadow: Bool = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay { if let tint { shape.fill(tint.opacity(0.16)) } }
                    .overlay(shape.fill(LiquidGlass.sheen))
                    .overlay(shape.strokeBorder(LiquidGlass.rim(), lineWidth: 1))
                    .compositingGroup()
                    .shadow(color: shadow ? .black.opacity(0.28) : .clear,
                            radius: shadow ? 18 : 0, y: shadow ? 12 : 0)
            }
    }
}

extension View {
    /// The signature liquid-glass panel: frosted material + top sheen + rim light
    /// + soft lift shadow. Use for cards, sheets, popovers and prominent controls.
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

    /// A frosted glass **pill** for overlay controls that sit on artwork (hero
    /// buttons, badges). A faint dark wash under the material keeps white text
    /// legible over bright backdrops.
    func glassCapsule(dim: Double = 0.22) -> some View {
        background {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(.black.opacity(dim))
            Capsule().fill(LiquidGlass.sheen)
        }
        .overlay(Capsule().strokeBorder(LiquidGlass.rim(0.85), lineWidth: 1))
    }

    /// A frosted glass **circle** — the round sibling of ``glassCapsule`` for
    /// icon-only overlay controls (e.g. the hero's prev/next chevrons).
    func glassCircle(dim: Double = 0.22) -> some View {
        background {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(.black.opacity(dim))
            Circle().fill(LiquidGlass.sheen)
        }
        .overlay(Circle().strokeBorder(LiquidGlass.rim(0.85), lineWidth: 1))
    }
}
