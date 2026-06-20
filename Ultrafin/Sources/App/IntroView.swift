import SwiftUI

/// A short, cinematic launch intro (Netflix-style): the brand mark blooms in
/// with an accent glow, the ULTRAFIN wordmark reveals with a light sweep, then
/// it fades to the app. Plays once per cold launch and, by sitting on top, also
/// hides the first frames of the library loading in underneath.
struct IntroView: View {
    var onFinished: () -> Void

    @Environment(SettingsStore.self) private var settings

    @State private var markScale: CGFloat = 0.55
    @State private var markOpacity: Double = 0
    @State private var glow: Double = 0
    @State private var wordOpacity: Double = 0
    @State private var wordSpread: CGFloat = 0.04
    @State private var shimmer: CGFloat = -0.5

    private var accent: Color { settings.theme.accent.color }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Accent bloom behind the mark.
            RadialGradient(colors: [accent.opacity(0.40 * glow), .clear],
                           center: .center, startRadius: 0, endRadius: 620)
                .ignoresSafeArea()

            VStack(spacing: markSpacing) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: markSize, weight: .thin))
                    .foregroundStyle(UltrafinColors.accentGradient)
                    .scaleEffect(markScale)
                    .opacity(markOpacity)
                    .shadow(color: accent.opacity(0.7 * glow), radius: 36)

                wordmark
            }
        }
        .onAppear(perform: run)
    }

    /// The ULTRAFIN wordmark with a one-time light sweep across the letters.
    private var wordmark: some View {
        let text = Text("ULTRAFIN")
            .font(.system(size: wordSize, weight: .heavy, design: .rounded))
            .tracking(wordSize * wordSpread)

        return text
            .foregroundStyle(.white)
            .opacity(wordOpacity)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white, .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.45)
                        .offset(x: shimmer * geo.size.width)
                        .blendMode(.plusLighter)
                }
                .mask(text.foregroundStyle(.white))
                .opacity(wordOpacity)
            }
            .shadow(color: accent.opacity(0.5 * glow), radius: 18)
    }

    private func run() {
        withAnimation(.spring(response: 0.65, dampingFraction: 0.62)) {
            markScale = 1.0
            markOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.7)) { glow = 1 }
        withAnimation(.easeOut(duration: 0.6).delay(0.35)) {
            wordOpacity = 1
            wordSpread = 0.12
        }
        withAnimation(.easeInOut(duration: 1.1).delay(0.5)) { shimmer = 1.1 }
        withAnimation(.easeInOut(duration: 0.9).delay(0.9)) { glow = 0.45 }

        Task {
            try? await Task.sleep(for: .seconds(2.1))
            onFinished()
        }
    }

    // MARK: - Metrics

    private var markSize: CGFloat {
        #if os(tvOS)
        130
        #else
        96
        #endif
    }
    private var wordSize: CGFloat {
        #if os(tvOS)
        76
        #else
        46
        #endif
    }
    private var markSpacing: CGFloat {
        #if os(tvOS)
        Spacing.xl
        #else
        Spacing.lg
        #endif
    }
}
