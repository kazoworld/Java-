import SwiftUI

/// The cold-launch intro: an aurora blooms out of the dark while droplets of
/// real Liquid Glass drift up through it, and the ULTRAFIN wordmark resolves
/// from a soft blur with a light sweep and a drawing hairline. Plays once per
/// launch and, by sitting on top, also covers the first frames of content
/// loading underneath.
struct IntroView: View {
    var onFinished: () -> Void

    @Environment(SettingsStore.self) private var settings

    @State private var wordOpacity: Double = 0
    @State private var wordBlur: CGFloat = 14
    @State private var wordDrift: CGFloat = 16
    @State private var lineProgress: CGFloat = 0
    @State private var glow: Double = 0
    @State private var shimmer: CGFloat = -0.6
    /// The aurora blooming in (scale + opacity) behind everything.
    @State private var bloom: Double = 0
    /// Glass droplets rising into place.
    @State private var orbsRisen = false

    private var accent: Color { settings.accent }

    var body: some View {
        ZStack {
            // Deep base — richer than flat black.
            RadialGradient(colors: [Color(hex: 0x12162A), Color(hex: 0x06070A)],
                           center: .center, startRadius: 0, endRadius: 900)
                .ignoresSafeArea()

            // The aurora blooms outward as the wordmark resolves.
            ZStack {
                bloomBlob(Color(hex: 0x6D8BFF), radius: 560, x: -0.30, y: -0.28)
                bloomBlob(Color(hex: 0xB56DFF), radius: 500, x: 0.34, y: -0.20)
                bloomBlob(Color(hex: 0x38BDF8), radius: 540, x: -0.22, y: 0.30)
                bloomBlob(Color(hex: 0xFF6DAE), radius: 430, x: 0.28, y: 0.26)
            }
            .scaleEffect(0.72 + 0.28 * bloom)
            .opacity(bloom)
            .ignoresSafeArea()

            // Droplets of real glass drifting up through the bloom.
            orb(size: orbBase * 1.0, x: -0.34, y: -0.20)
            orb(size: orbBase * 0.55, x: 0.36, y: -0.26)
            orb(size: orbBase * 0.75, x: 0.30, y: 0.28)
            orb(size: orbBase * 0.42, x: -0.30, y: 0.24)

            RadialGradient(colors: [accent.opacity(0.16 * glow), .clear],
                           center: .center, startRadius: 0, endRadius: 460)
                .ignoresSafeArea()

            VStack(spacing: lineSpacing) {
                wordmark
                // Hairline accent that draws out from the center.
                Capsule()
                    .fill(LinearGradient(colors: [.clear, accent, .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: lineWidth * lineProgress, height: 2)
                    .opacity(lineProgress)
            }
        }
        .onAppear(perform: run)
    }

    private func bloomBlob(_ color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        GeometryReader { geo in
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.55), .clear],
                                     center: .center, startRadius: 0, endRadius: radius))
                .frame(width: radius * 2, height: radius * 2)
                .position(x: geo.size.width * (0.5 + x), y: geo.size.height * (0.5 + y))
        }
    }

    /// One droplet of system Liquid Glass, rising and fading in with the bloom.
    private func orb(size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        GeometryReader { geo in
            Color.clear
                .frame(width: size, height: size)
                .glassEffect(.regular, in: .circle)
                .overlay(Circle().strokeBorder(LiquidGlass.rim(0.9), lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(.white.opacity(0.55))
                        .frame(width: size * 0.14, height: size * 0.14)
                        .blur(radius: size * 0.05)
                        .offset(x: size * 0.22, y: size * 0.18)
                }
                .position(x: geo.size.width * (0.5 + x), y: geo.size.height * (0.5 + y))
                .offset(y: orbsRisen ? 0 : 46)
                .opacity(orbsRisen ? 1 : 0)
        }
        .allowsHitTesting(false)
    }

    private var wordmark: some View {
        // SF Pro, light weight, wide tracking — clean and premium.
        let base = Text("ULTRAFIN")
            .font(.system(size: wordSize, weight: .light, design: .default))
            .tracking(wordSize * trackRatio)

        return base
            .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.74)],
                                            startPoint: .top, endPoint: .bottom))
            .overlay {
                // One slow light sweep across the letters.
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.9), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.4)
                        .offset(x: shimmer * geo.size.width)
                        .blendMode(.plusLighter)
                }
                .mask(base.foregroundStyle(.white))
            }
            .padding(.leading, wordSize * trackRatio) // re-center for trailing track space
            .opacity(wordOpacity)
            .blur(radius: wordBlur)
            .offset(y: wordDrift)
            .shadow(color: accent.opacity(0.35 * glow), radius: 24)
    }

    private func run() {
        // The aurora blooms first, the glass rises through it, then the
        // wordmark resolves on top — three overlapping beats, one gesture.
        withAnimation(.easeOut(duration: 1.5)) { bloom = 1 }
        withAnimation(.spring(duration: 1.1, bounce: 0.2).delay(0.25)) { orbsRisen = true }
        withAnimation(.easeOut(duration: 0.95).delay(0.2)) {
            wordOpacity = 1
            wordBlur = 0
            wordDrift = 0
        }
        withAnimation(.easeOut(duration: 1.0).delay(0.2)) { glow = 1 }
        withAnimation(.easeInOut(duration: 0.8).delay(0.55)) { lineProgress = 1 }
        withAnimation(.easeInOut(duration: 1.15).delay(0.7)) { shimmer = 1.1 }
        withAnimation(.easeInOut(duration: 1.0).delay(1.2)) { glow = 0.5 }

        Task {
            try? await Task.sleep(for: .seconds(2.6))
            onFinished()
        }
    }

    // MARK: - Metrics

    private var wordSize: CGFloat {
        #if os(tvOS)
        72
        #else
        44
        #endif
    }
    private var trackRatio: CGFloat { 0.34 }
    private var lineWidth: CGFloat {
        #if os(tvOS)
        300
        #else
        190
        #endif
    }
    private var lineSpacing: CGFloat {
        #if os(tvOS)
        Spacing.xl
        #else
        Spacing.lg
        #endif
    }
    private var orbBase: CGFloat {
        #if os(tvOS)
        170
        #else
        104
        #endif
    }
}
