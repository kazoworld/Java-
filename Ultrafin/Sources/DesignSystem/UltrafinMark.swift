import SwiftUI

/// The Ultrafin brand mark: the glass "U" tile rendered live in system Liquid
/// Glass. Shared by the launch splash, the auth screens and the vibe chooser so
/// the identity is one consistent object everywhere.
struct UltrafinMark: View {
    var size: CGFloat = 110

    var body: some View {
        Text("U")
            .font(.system(size: size * 0.52, weight: .thin))
            .foregroundStyle(LinearGradient(colors: [.white, Color(hex: 0xBFD0FF)],
                                            startPoint: .top, endPoint: .bottom))
            .shadow(color: Color(hex: 0x6D8BFF).opacity(0.8), radius: size * 0.16)
            .frame(width: size, height: size)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(LiquidGlass.rim(), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: size * 0.27, y: size * 0.14)
    }
}

/// The app's signature drifting mesh — deep blue → violet → black. Reused by the
/// launch splash and the vibe chooser so the "feel" is continuous from cold
/// launch into the app.
struct UltrafinMeshBackdrop: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let drift = { (p: Double, a: Double) in Float(sin(t * p) * a) }
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5 + drift(0.23, 0.10), 0], [1, 0],
                    [0, 0.5 + drift(0.17, 0.12)],
                    [0.5 + drift(0.31, 0.16), 0.5 + drift(0.27, 0.16)],
                    [1, 0.5 + drift(0.21, 0.12)],
                    [0, 1], [0.5 + drift(0.19, 0.10), 1], [1, 1]
                ],
                colors: [
                    Color(hex: 0x0A0B0F), Color(hex: 0x141B38), Color(hex: 0x0A0B0F),
                    Color(hex: 0x1B2340), Color(hex: 0x33418C), Color(hex: 0x2A1B4E),
                    Color(hex: 0x0A0B0F), Color(hex: 0x121B33), Color(hex: 0x0A0B0F)
                ]
            )
        }
        .ignoresSafeArea()
    }
}
