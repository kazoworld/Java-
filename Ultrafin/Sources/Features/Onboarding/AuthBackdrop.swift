import SwiftUI

/// The auth flow's stage: a bright, saturated aurora drifting behind floating
/// Liquid Glass orbs that genuinely refract it as everything moves.
///
/// All motion is transform-only (offsets on long, out-of-phase loops), so it
/// stays effortless on Apple TV — the orbs' refraction is the system material
/// doing the expensive part.
struct AuthBackdrop: View {
    /// Three independent phase toggles with different periods make the drift
    /// read as organic weather rather than a synchronized loop.
    @State private var driftA = false
    @State private var driftB = false
    @State private var driftC = false

    var body: some View {
        ZStack {
            // A deep but *blue* base — brighter than the app background, so the
            // color field reads vivid rather than murky.
            LinearGradient(colors: [Color(hex: 0x141B38), Color(hex: 0x0B0D18)],
                           startPoint: .top, endPoint: .bottom)

            // The aurora: four saturated blobs, each on its own slow orbit.
            blob(Color(hex: 0x6D8BFF), radius: 620, opacity: 0.65)
                .offset(x: driftA ? -220 : -320, y: driftA ? -260 : -160)
            blob(Color(hex: 0xB56DFF), radius: 560, opacity: 0.55)
                .offset(x: driftB ? 300 : 200, y: driftB ? -200 : -320)
            blob(Color(hex: 0x38BDF8), radius: 640, opacity: 0.50)
                .offset(x: driftC ? -260 : -140, y: driftC ? 300 : 200)
            blob(Color(hex: 0xFF6DAE), radius: 500, opacity: 0.40)
                .offset(x: driftA ? 260 : 340, y: driftB ? 280 : 180)

            // Floating glass droplets, each bobbing on its own rhythm — they
            // bend the aurora behind them as both layers move.
            orb(size: orbScale * 130, x: -0.32, y: -0.22, phase: driftA)
            orb(size: orbScale * 70,  x: 0.36,  y: -0.30, phase: driftB)
            orb(size: orbScale * 95,  x: 0.30,  y: 0.26,  phase: driftC)
            orb(size: orbScale * 52,  x: -0.36, y: 0.30,  phase: driftB)
            orb(size: orbScale * 40,  x: 0.05,  y: -0.38, phase: driftC)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) { driftA = true }
            withAnimation(.easeInOut(duration: 15).repeatForever(autoreverses: true)) { driftB = true }
            withAnimation(.easeInOut(duration: 19).repeatForever(autoreverses: true)) { driftC = true }
        }
    }

    private func blob(_ color: Color, radius: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), .clear],
                                 center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
    }

    /// One drifting droplet of real Liquid Glass with the brand rim and a tiny
    /// specular sparkle. `x`/`y` are fractions of the screen from center.
    private func orb(size: CGFloat, x: CGFloat, y: CGFloat, phase: Bool) -> some View {
        GeometryReader { geo in
            Color.clear
                .frame(width: size, height: size)
                .glassEffect(.regular, in: .circle)
                .overlay(Circle().strokeBorder(LiquidGlass.rim(0.9), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    // The sparkle: a small soft highlight up in the glass.
                    Circle()
                        .fill(.white.opacity(0.55))
                        .frame(width: size * 0.14, height: size * 0.14)
                        .blur(radius: size * 0.05)
                        .offset(x: size * 0.22, y: size * 0.18)
                }
                .position(x: geo.size.width * (0.5 + x), y: geo.size.height * (0.5 + y))
                .offset(y: phase ? -18 : 18)
        }
        .allowsHitTesting(false)
    }

    private var orbScale: CGFloat {
        #if os(tvOS)
        1.6
        #else
        1.0
        #endif
    }
}
