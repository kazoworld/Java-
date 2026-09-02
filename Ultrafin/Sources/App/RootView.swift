import SwiftUI

/// Routes between the major flows based on `AppState.phase`.
///
/// Transitions use a soft cross-fade so launch → onboarding → app never feels
/// like a hard cut. Each branch owns its own navigation stack.
struct RootView: View {
    @Environment(AppState.self) private var appState
    /// One-time welcome tour: shown over the app after the very first sign-in
    /// (the intro overlay fades out above it, revealing page one).
    @State private var tourComplete = UserDefaults.standard.bool(forKey: "onboarding.tourComplete")
    /// The experience chosen by "What's the vibe?" — nil until the user picks,
    /// which is when the app tree is built. Starts pre-filled when the user has
    /// set a default launcher, so the question is skipped entirely.
    @State private var mode: AppMode? = StartupPreference.current.directMode
    /// Whether the one-time "where's your music?" question has been answered.
    @State private var musicSourceChosen = MusicSourceOnboarding.isComplete

    private var authenticatedUserID: String? {
        if case .authenticated(let session) = appState.phase { return session.userID }
        return nil
    }

    var body: some View {
        ZStack {
            AmbientBackground()

            switch appState.phase {
            case .launching:
                // Opening straight into Music skips the brand splash entirely.
                // Apple Music doesn't show you a logo before your library, and a
                // launcher that's been told to go somewhere specific shouldn't
                // stop to introduce itself. The canvas underneath is the one the
                // library lands on, so the cold start is a single surface rather
                // than a splash dissolving into a different screen.
                if mode == .music {
                    MusicBackground()
                        .transition(.opacity)
                } else {
                    LaunchView()
                        .transition(.opacity)
                }
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

            // First time into Music: ask whether it comes from Jellyfin or a
            // Navidrome server, rather than defaulting silently.
            if case .authenticated = appState.phase, mode == .music, !musicSourceChosen {
                MusicSourceOnboardingView {
                    withAnimation(.smooth(duration: 0.45)) { musicSourceChosen = true }
                }
                .transition(.opacity)
                .zIndex(4)
            }

            // The welcome tour waits its turn behind the source question.
            if case .authenticated = appState.phase, mode != nil,
               mode != .music || musicSourceChosen, !tourComplete {
                OnboardingTourView {
                    UserDefaults.standard.set(true, forKey: "onboarding.tourComplete")
                    withAnimation(.smooth(duration: 0.45)) { tourComplete = true }
                }
                .transition(.opacity)
                .zIndex(5)
            }
        }
        .animation(.smooth(duration: 0.35), value: appState.phase)
        // A new sign-in / profile switch re-asks "What's the vibe?" (the user
        // identity changed, so any prior choice no longer applies).
        // A new sign-in / profile switch starts the experience over — straight
        // into the default launcher when one is set, else back to the chooser.
        .onChange(of: authenticatedUserID) { _, _ in
            mode = StartupPreference.current.directMode
        }
        // Publish the experience so the app root can pick the window's colour
        // scheme (Music has its own black/white canvas).
        .onChange(of: mode) { _, current in
            AppModeState.shared.current = current
        }
        .onAppear { AppModeState.shared.current = mode }
        .task {
            // Give back space held by songs that stopped being played.
            MusicLibraryCache.shared.evictStale()
            if case .launching = appState.phase {
                await appState.bootstrap()
            }
        }
    }
}

/// The one screen shown while the saved session is validated.
///
/// There used to be two: a cold-launch intro overlay stacked on top of this,
/// each with its own aurora. They played over each other on every launch, and
/// the deep blue-violet mesh underneath read as another server's app rather
/// than as ours. One screen now, built out of the app icon itself — the mark
/// you tapped on the Home Screen is the mark you land on.
struct LaunchView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: markSize * 0.26) {
                // The icon art, at the icon's own corner radius. Continuing the
                // thing you tapped is worth more than any bespoke splash.
                Image("LaunchMark")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: markSize, height: markSize)
                    .clipShape(RoundedRectangle(cornerRadius: markSize * 0.225, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: markSize * 0.16, y: markSize * 0.07)
                    .scaleEffect(appeared ? 1 : 0.88)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: Spacing.sm) {
                    Text("ULTRAFIN")
                        .font(.system(size: wordSize, weight: .light))
                        .tracking(wordSize * 0.34)
                        .padding(.leading, wordSize * 0.34) // re-centre for trailing track
                        .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.7)],
                                                        startPoint: .top, endPoint: .bottom))
                    Text("Your library, your way.")
                        .font(.system(size: wordSize * 0.34, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)

                loadingDots
                    .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.22)) { appeared = true }
        }
    }

    /// Near-black, lit from behind the mark by the icon's own colours. Dark on
    /// purpose: the app is dark, and a pastel splash would flash white before
    /// dropping into it.
    private var backdrop: some View {
        ZStack {
            Color(hex: 0x06070A)
            RadialGradient(colors: [Color(hex: 0x8AD8F4).opacity(0.22), .clear],
                           center: UnitPoint(x: 0.32, y: 0.60), startRadius: 0, endRadius: glowRadius)
            RadialGradient(colors: [Color(hex: 0xD4BBF5).opacity(0.20), .clear],
                           center: UnitPoint(x: 0.66, y: 0.36), startRadius: 0, endRadius: glowRadius)
            RadialGradient(colors: [Color(hex: 0xF9CCC8).opacity(0.14), .clear],
                           center: UnitPoint(x: 0.70, y: 0.66), startRadius: 0, endRadius: glowRadius * 0.8)
        }
        .ignoresSafeArea()
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

    private var markSize: CGFloat {
        #if os(tvOS)
        260
        #else
        132
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
    private var glowRadius: CGFloat {
        #if os(tvOS)
        900
        #else
        460
        #endif
    }
}
