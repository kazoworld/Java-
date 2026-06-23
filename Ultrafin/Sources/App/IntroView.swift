import SwiftUI

/// A premium cold-launch intro: a deep, rich backdrop with the ULTRAFIN wordmark
/// resolving from a soft blur with a slow light sweep and a hairline that draws
/// beneath it. Plays once per cold launch and, by sitting on top, also covers
/// the first frames of content loading underneath.
struct IntroView: View {
    var onFinished: () -> Void

    @Environment(SettingsStore.self) private var settings

    @State private var wordOpacity: Double = 0
    @State private var wordBlur: CGFloat = 14
    @State private var wordDrift: CGFloat = 16
    @State private var lineProgress: CGFloat = 0
    @State private var glow: Double = 0
    @State private var shimmer: CGFloat = -0.6

    private var accent: Color { settings.theme.accent.color }

    var body: some View {
        ZStack {
            // Deep, slightly-lit backdrop — richer than flat black.
            RadialGradient(colors: [Color(hex: 0x15171F), Color(hex: 0x06070A)],
                           center: .center, startRadius: 0, endRadius: 900)
                .ignoresSafeArea()
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
        withAnimation(.easeOut(duration: 0.95)) {
            wordOpacity = 1
            wordBlur = 0
            wordDrift = 0
        }
        withAnimation(.easeOut(duration: 1.0)) { glow = 1 }
        withAnimation(.easeInOut(duration: 0.8).delay(0.35)) { lineProgress = 1 }
        withAnimation(.easeInOut(duration: 1.15).delay(0.5)) { shimmer = 1.1 }
        withAnimation(.easeInOut(duration: 1.0).delay(1.0)) { glow = 0.5 }

        Task {
            try? await Task.sleep(for: .seconds(2.35))
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
}
