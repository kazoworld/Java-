import SwiftUI

/// The one-time welcome tour shown after the first sign-in: a short, flowing
/// walk through Home, Search and Settings. Everything animates with cheap
/// transforms (opacity / offset / scale) so it stays perfectly fluid on
/// Apple TV. Entirely optional — a Skip button, or hold the select button for
/// three seconds on the remote.
struct OnboardingTourView: View {
    let onFinish: () -> Void

    @Environment(SettingsStore.self) private var settings

    @State private var page = 0
    /// Drives the per-page staggered reveal (icon → title → text → hint).
    @State private var revealed = false
    /// Drives the slow, continuous drift of the backdrop blobs.
    @State private var drift = false
    /// Fills up while the select button is held (the 3-second skip).
    @State private var holdProgress: CGFloat = 0

    private struct TourPage {
        let icon: String
        let tint: Color
        let title: String
        let description: String
    }

    private var pages: [TourPage] {
        [
            TourPage(icon: "sparkles",
                     tint: settings.theme.accent.color,
                     title: "Welcome to Ultrafin",
                     description: "A premium home for everything on your Jellyfin server. Here's a quick look around."),
            TourPage(icon: "house.fill",
                     tint: Color(hex: 0x6D8BFF),
                     title: "Home",
                     description: "Continue watching, fresh arrivals and a spotlight that breathes with your library — everything one glance away."),
            TourPage(icon: "magnifyingglass",
                     tint: Color(hex: 0x3DD9A0),
                     title: "Search",
                     description: "Find any movie, show or episode in seconds. Your recent searches stay one tap away."),
            TourPage(icon: "gearshape.fill",
                     tint: Color(hex: 0xB56DFF),
                     title: "Your library, your way.",
                     description: "Accents and themes, profiles, playback engines, subtitles — shape every detail in Settings.")
        ]
    }

    private var current: TourPage { pages[page] }
    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: Spacing.xl) {
                Spacer()

                pageContent
                    .id(page) // drive the slide/fade between pages
                    .transition(.asymmetric(
                        insertion: .offset(x: 70).combined(with: .opacity),
                        removal: .offset(x: -70).combined(with: .opacity)))

                Spacer()

                progressDots
                controls
            }
            .padding(edgePadding)
        }
        .animation(.smooth(duration: 0.55), value: page)
        .task(id: page) {
            // Re-run the staggered reveal each time the page changes.
            revealed = false
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation { revealed = true }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
        #if os(tvOS)
        .onExitCommand { finish() } // Menu also skips
        #endif
    }

    // MARK: - Backdrop

    /// A deep field with two slow-drifting color blobs that lean toward the
    /// current page's tint — offset-animated only, so it costs nothing.
    private var backdrop: some View {
        ZStack {
            UltrafinColors.background

            Circle()
                .fill(RadialGradient(colors: [current.tint.opacity(0.32), .clear],
                                     center: .center, startRadius: 0, endRadius: blobRadius))
                .frame(width: blobRadius * 2, height: blobRadius * 2)
                .offset(x: drift ? -blobRadius * 0.5 : -blobRadius * 0.75,
                        y: drift ? -blobRadius * 0.55 : -blobRadius * 0.35)

            Circle()
                .fill(RadialGradient(colors: [current.tint.opacity(0.20), .clear],
                                     center: .center, startRadius: 0, endRadius: blobRadius))
                .frame(width: blobRadius * 2, height: blobRadius * 2)
                .offset(x: drift ? blobRadius * 0.6 : blobRadius * 0.4,
                        y: drift ? blobRadius * 0.5 : blobRadius * 0.7)
        }
        .animation(.easeInOut(duration: 0.9), value: page) // tint crossfade
        .ignoresSafeArea()
    }

    // MARK: - Page content

    private var pageContent: some View {
        VStack(spacing: Spacing.xl) {
            // The floating glass tile with the page's icon.
            ZStack {
                RoundedRectangle(cornerRadius: tileSize * 0.24, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: tileSize * 0.24, style: .continuous)
                    .fill(current.tint.opacity(0.22))
                RoundedRectangle(cornerRadius: tileSize * 0.24, style: .continuous)
                    .fill(LiquidGlass.sheen)
                Image(systemName: current.icon)
                    .font(.system(size: tileSize * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: current.tint.opacity(0.8), radius: 18)
            }
            .frame(width: tileSize, height: tileSize)
            .overlay(RoundedRectangle(cornerRadius: tileSize * 0.24, style: .continuous)
                .strokeBorder(LiquidGlass.rim(), lineWidth: 1))
            .shadow(color: current.tint.opacity(0.35), radius: 34, y: 14)
            // Gentle bob so the tile feels alive, and a settle-in on reveal.
            .offset(y: drift ? -7 : 7)
            .scaleEffect(revealed ? 1 : 0.86)
            .opacity(revealed ? 1 : 0)
            .animation(.spring(duration: 0.6, bounce: 0.25), value: revealed)

            Text(current.title)
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(UltrafinColors.primaryText)
                .multilineTextAlignment(.center)
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 16)
                .animation(.smooth(duration: 0.5).delay(0.10), value: revealed)

            Text(current.description)
                .font(.system(size: bodySize, weight: .regular))
                .foregroundStyle(UltrafinColors.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: textMaxWidth)
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 16)
                .animation(.smooth(duration: 0.5).delay(0.18), value: revealed)
        }
    }

    private var progressDots: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(pages.indices, id: \.self) { i in
                Capsule()
                    .fill(i == page ? current.tint : Color.white.opacity(0.25))
                    .frame(width: i == page ? 26 : 8, height: 8)
            }
        }
        .animation(.smooth(duration: 0.35), value: page)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: Spacing.md) {
            Button {
                if isLast { finish() } else { page += 1 }
            } label: {
                Text(isLast ? "Start Watching" : "Continue")
                    .font(.system(size: buttonFont, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.vertical, Spacing.md)
                    .background {
                        Capsule().fill(current.tint.gradient)
                        Capsule().fill(LiquidGlass.sheen)
                        // The hold-to-skip fill sweeping across the button.
                        if holdProgress > 0 {
                            GeometryReader { geo in
                                Capsule().fill(.white.opacity(0.35))
                                    .frame(width: geo.size.width * holdProgress)
                            }
                        }
                    }
                    .overlay(Capsule().strokeBorder(LiquidGlass.rim(0.6), lineWidth: 1))
                    .shadow(color: current.tint.opacity(0.45), radius: 16, y: 8)
            }
            .buttonStyle(UltrafinButtonStyle(focusScale: 1.08, lift: true))
            // Hold select for 3 seconds (while this button is focused) to skip
            // the whole tour, with a visible progress sweep filling the button.
            .onLongPressGesture(minimumDuration: 3) {
                finish()
            } onPressingChanged: { pressing in
                withAnimation(pressing ? .linear(duration: 3) : .smooth(duration: 0.25)) {
                    holdProgress = pressing ? 1 : 0
                }
            }

            Button("Skip") { finish() }
                .font(.system(size: buttonFont * 0.75, weight: .semibold, design: .rounded))
                .foregroundStyle(UltrafinColors.secondaryText)
                .buttonStyle(UltrafinButtonStyle(focusScale: 1.05, lift: false))

            #if os(tvOS)
            Text("Hold the select button for 3 seconds to skip")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(UltrafinColors.tertiaryText)
            #endif
        }
    }

    private func finish() {
        withAnimation(.smooth(duration: 0.45)) { onFinish() }
    }

    // MARK: - Metrics

    private var tileSize: CGFloat {
        #if os(tvOS)
        220
        #else
        130
        #endif
    }
    private var titleSize: CGFloat {
        #if os(tvOS)
        52
        #else
        30
        #endif
    }
    private var bodySize: CGFloat {
        #if os(tvOS)
        26
        #else
        16
        #endif
    }
    private var buttonFont: CGFloat {
        #if os(tvOS)
        26
        #else
        17
        #endif
    }
    private var textMaxWidth: CGFloat {
        #if os(tvOS)
        760
        #else
        340
        #endif
    }
    private var blobRadius: CGFloat {
        #if os(tvOS)
        640
        #else
        320
        #endif
    }
    private var edgePadding: CGFloat {
        #if os(tvOS)
        60
        #else
        24
        #endif
    }
}
