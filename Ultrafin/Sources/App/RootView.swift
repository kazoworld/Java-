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
                MainTabView()
                    // Rebuild the whole tab tree when the profile changes so every
                    // screen's cached view model reloads as the new user.
                    .id(session.userID)
                    .transition(.opacity)
            case .connectionLost(let session):
                ConnectionLostView(session: session)
                    .transition(.opacity)
            }

            if case .authenticated = appState.phase, !tourComplete {
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
        .task {
            if case .launching = appState.phase {
                await appState.bootstrap()
            }
        }
    }
}

/// Minimal, premium splash shown while the saved session is validated (a
/// fallback under the cold-launch intro).
struct LaunchView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var pulse = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Text("ULTRAFIN")
                .font(.system(size: launchSize, weight: .light, design: .default))
                .tracking(launchSize * 0.34)
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.74)],
                                                startPoint: .top, endPoint: .bottom))
                .padding(.leading, launchSize * 0.34)

            Capsule()
                .fill(settings.theme.accent.color)
                .frame(width: 56, height: 3)
                .opacity(pulse ? 1 : 0.25)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        }
        .onAppear { pulse = true }
    }

    private var launchSize: CGFloat {
        #if os(tvOS)
        56
        #else
        34
        #endif
    }
}
