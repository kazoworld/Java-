import SwiftUI

#if os(tvOS)
/// The music canvas on a television: a still lake at first light, drawn rather
/// than photographed, drifting slowly enough that you notice it only if you look.
///
/// The phone gets a flat OLED surface because it's held a foot away and the
/// artwork is the whole point. A television is furniture — it's in the room
/// whether or not anyone is watching it — so a record playing deserves something
/// atmospheric behind it. Everything here is kept dark and low-contrast on
/// purpose: it has to sit *behind* album covers and white text without ever
/// competing with them.
///
/// Drawn, not shipped as an image: a ridge is a handful of summed sines, which
/// costs nothing, scales to any screen, and lets the mist and the water move
/// independently of each other.
struct MusicSceneBackdrop: View {
    /// Overall presence. This is a wash, not a photograph.
    var strength: Double = 1

    /// Where the water meets the land.
    private let horizon: CGFloat = 0.56

    /// Under Reduce Motion the scene holds one frame. It's still the same
    /// picture — it simply stops drifting, which is the part being objected to.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    sky
                    // Far range, then near — each darker and more opaque, which
                    // is what reads as depth through haze.
                    ridge(in: size, seed: 0.7, height: 0.20, drift: t,
                          fill: Color(hex: 0x2A3348), opacity: 0.55)
                    ridge(in: size, seed: 2.3, height: 0.14, drift: t,
                          fill: Color(hex: 0x1B2233), opacity: 0.75)
                    ridge(in: size, seed: 5.1, height: 0.09, drift: t,
                          fill: Color(hex: 0x0E121C), opacity: 0.95)

                    water(in: size, t: t)
                    mist(in: size, t: t)

                    // Sink the edges into black so the scene never draws a line
                    // against the screen border.
                    RadialGradient(colors: [.clear, .black.opacity(0.75)],
                                   center: .center,
                                   startRadius: min(size.width, size.height) * 0.22,
                                   endRadius: max(size.width, size.height) * 0.78)
                }
            }
        }
        .opacity(strength)
        // One offscreen pass for the whole scene rather than compositing a dozen
        // blurred layers against the interface every frame.
        .drawingGroup()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Pieces

    /// Dawn: deep blue overhead warming into a band at the waterline.
    private var sky: some View {
        LinearGradient(stops: [
            .init(color: Color(hex: 0x060811), location: 0.00),
            .init(color: Color(hex: 0x141C33), location: 0.26),
            .init(color: Color(hex: 0x3B3350), location: 0.44),
            .init(color: Color(hex: 0x6B4A55), location: 0.52),
            .init(color: Color(hex: 0x8A5A52), location: horizon),
            .init(color: Color(hex: 0x1A1622), location: 0.72),
            .init(color: Color(hex: 0x05060A), location: 1.00)
        ], startPoint: .top, endPoint: .bottom)
    }

    /// One mountain silhouette. The profile is three sines at unrelated
    /// frequencies, so it reads as a range rather than as a wave.
    private func ridge(in size: CGSize, seed: Double, height: CGFloat,
                       drift: Double, fill: Color, opacity: Double) -> some View {
        let baseline = size.height * horizon
        let amplitude = size.height * height
        return Path { path in
            path.move(to: CGPoint(x: 0, y: baseline))
            // Forty samples is plenty at this amplitude and costs nothing.
            for step in 0...40 {
                let fraction = Double(step) / 40
                let x = CGFloat(fraction) * size.width
                let y = baseline - amplitude * CGFloat(profile(fraction, seed: seed, drift: drift))
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: baseline))
            path.closeSubpath()
        }
        .fill(fill.opacity(opacity))
    }

    /// The ridge's height at a point, 0...1. The drift term moves the range by a
    /// few pixels over minutes — not visible motion, just never frozen.
    private func profile(_ x: Double, seed: Double, drift: Double) -> Double {
        let d = drift * 0.0009
        let a = sin(x * 6.3 + seed + d) * 0.5
        let b = sin(x * 13.1 + seed * 2.1 - d * 0.7) * 0.26
        let c = sin(x * 27.7 + seed * 3.7 + d * 1.3) * 0.12
        return min(1, max(0.08, 0.5 + a * 0.5 + b + c))
    }

    /// The lake: the sky's warmth mirrored, with slow bands of light crossing it.
    private func water(in size: CGSize, t: Double) -> some View {
        let top = size.height * horizon
        let depth = max(1, size.height - top)
        return ZStack {
            LinearGradient(stops: [
                .init(color: Color(hex: 0x6E4A4C).opacity(0.55), location: 0.0),
                .init(color: Color(hex: 0x2A2436).opacity(0.50), location: 0.30),
                .init(color: Color(hex: 0x05060A), location: 1.0)
            ], startPoint: .top, endPoint: .bottom)

            // Three broad highlights sliding at unrelated rates — the trick that
            // makes flat water look like it's breathing.
            ForEach(0..<3, id: \.self) { band in
                let phase = t * (0.05 + Double(band) * 0.021) + Double(band) * 2.1
                let position = (sin(phase) + 1) / 2
                Ellipse()
                    .fill(Color(hex: 0xC98F79).opacity(0.10))
                    .frame(width: size.width * 1.3, height: depth * 0.10)
                    .blur(radius: 26)
                    .position(x: size.width * 0.5,
                              y: CGFloat(position) * depth * 0.85 + depth * 0.05)
            }
        }
        .frame(width: size.width, height: depth)
        .position(x: size.width / 2, y: top + depth / 2)
    }

    /// Fog lying on the water, drifting sideways. Two layers at different speeds,
    /// so the near one visibly overtakes the far one.
    private func mist(in size: CGSize, t: Double) -> some View {
        ZStack {
            ForEach(0..<2, id: \.self) { layer in
                let speed = 7.0 + Double(layer) * 5.0
                let span = Double(size.width) * 2
                let travel = (t * speed).truncatingRemainder(dividingBy: span)
                Capsule()
                    .fill(Color(hex: 0xD8CFE2).opacity(layer == 0 ? 0.10 : 0.07))
                    .frame(width: size.width * 1.1,
                           height: size.height * (layer == 0 ? 0.07 : 0.05))
                    .blur(radius: 40)
                    .position(x: CGFloat(travel) - size.width * 0.4,
                              y: size.height * (horizon + (layer == 0 ? -0.005 : 0.02)))
            }
        }
    }
}
#endif
