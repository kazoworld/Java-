import SwiftUI

/// Routes between the major flows based on `AppState.phase`.
///
/// Transitions use a soft cross-fade so launch → onboarding → app never feels
/// like a hard cut. Each branch owns its own navigation stack.
struct RootView: View {
    @Environment(AppState.self) private var appState
    /// Cold-launch intro overlay; shown once, fades out after its animation
    /// (which also covers the first frames of content loading underneath).
    @State private var showIntro = true
    /// One-time welcome tour: shown over the app after the very first sign-in
    /// (the intro overlay fades out above it, revealing page one).
    @State private var tourComplete = UserDefaults.standard.bool(forKey: "onboarding.tourComplete")
    /// The experience chosen by "What's the vibe?" — nil until the user picks,
    /// which is when the app tree is built. Reset on each fresh sign-in so the
    /// question is asked at the start of every session.
    @State private var mode: AppMode?

    private var authenticatedUserID: String? {
        if case .authenticated(let session) = appState.phase { return session.userID }
        return nil
    }

    var body: some View {
        ZStack {
            AmbientBackground()

            switch appState.phase {
            case .launching:
                LaunchView()
                    .transition(.opacity)
            case .serverConnect:
                ServerConnectView()
                    .transition(.opacity)
            case .login(let server):
                LoginView(server: server)
                    .transition(.opacity)
            case .authenticated(let session):
                if mode != nil {
                    MainTabView(mode: Binding(
                        get: { mode ?? .media },
                        set: { mode = $0 }
                    ))
                        // Rebuild the whole tab tree when the profile changes so
                        // every screen's cached view model reloads as the new user.
                        .id(session.userID)
                        // While the welcome tour is up, take the app out of the
                        // tvOS focus engine entirely — otherwise the remote keeps
                        // driving the hidden UI underneath the overlay.
                        .disabled(!tourComplete)
                        .transition(.opacity)
                } else {
                    // Awaiting the vibe choice — the chooser overlay covers this.
                    Color.clear
                }
            case .connectionLost(let session):
                ConnectionLostView(session: session)
                    .transition(.opacity)
            }

            // "What's the vibe?" — asked at the start of each authenticated
            // session, before the app tree is built.
            if case .authenticated = appState.phase, mode == nil {
                VibeChooserView { picked in
                    picked.remember()
                    withAnimation(.smooth(duration: 0.45)) { mode = picked }
                }
                .transition(.opacity)
                .zIndex(4)
            }

            if case .authenticated = appState.phase, mode != nil, !tourComplete {
                OnboardingTourView {
                    UserDefaults.standard.set(true, forKey: "onboarding.tourComplete")
                    withAnimation(.smooth(duration: 0.45)) { tourComplete = true }
                }
                .transition(.opacity)
                .zIndex(5)
            }

            if showIntro {
                IntroView {
                    withAnimation(.easeInOut(duration: 0.55)) { showIntro = false }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.smooth(duration: 0.35), value: appState.phase)
        // A new sign-in / profile switch re-asks "What's the vibe?" (the user
        // identity changed, so any prior choice no longer applies).
        .onChange(of: authenticatedUserID) { _, _ in
            mode = nil
        }
        .task {
            if case .launching = appState.phase {
                await appState.bootstrap()
            }
        }
    }
}

/// The splash shown while the saved session is validated — WWDC-grade: a live
/// mesh gradient breathing through deep aurora colors, a Liquid Glass monogram
/// floating at center with the wordmark beneath, and a quiet pulsing status.
struct LaunchView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var appeared = false

    var body: some View {
        ZStack {
            meshBackdrop

            VStack(spacing: monogramSize * 0.22) {
                monogram
                    .scaleEffect(appeared ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: Spacing.md) {
                    Text("ULTRAFIN")
                        .font(.system(size: wordSize, weight: .light))
                        .tracking(wordSize * 0.34)
                        .padding(.leading, wordSize * 0.34) // re-center for trailing track
                        .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.7)],
                                                        startPoint: .top, endPoint: .bottom))
                    Text("Your library, your way.")
                        .font(.system(size: wordSize * 0.34, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

                loadingDots
                    .padding(.top, Spacing.sm)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.2)) { appeared = true }
        }
    }

    /// A living mesh: nine control points drifting on out-of-phase sine orbits
    /// through deep blue → violet → black — the WWDC "hello" energy, but ours.
    private var meshBackdrop: some View {
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

    /// The glass "U" tile — the app icon rendered live in system Liquid Glass.
    private var monogram: some View {
        Text("U")
            .font(.system(size: monogramSize * 0.52, weight: .thin))
            .foregroundStyle(LinearGradient(colors: [.white, Color(hex: 0xBFD0FF)],
                                            startPoint: .top, endPoint: .bottom))
            .shadow(color: Color(hex: 0x6D8BFF).opacity(0.8), radius: 18)
            .frame(width: monogramSize, height: monogramSize)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: monogramSize * 0.24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: monogramSize * 0.24, style: .continuous)
                .strokeBorder(LiquidGlass.rim(), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 16)
    }

    /// Three dots breathing in sequence — quieter than a spinner.
    private var loadingDots: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(.white)
                        .frame(width: dotSize, height: dotSize)
                        .opacity(0.25 + 0.6 * max(0, sin(t * 2.6 - Double(i) * 0.7)))
                }
            }
        }
    }

    // MARK: - Metrics

    private var monogramSize: CGFloat {
        #if os(tvOS)
        190
        #else
        110
        #endif
    }
    private var wordSize: CGFloat {
        #if os(tvOS)
        50
        #else
        30
        #endif
    }
    private var dotSize: CGFloat {
        #if os(tvOS)
        9
        #else
        6
        #endif
    }
}
