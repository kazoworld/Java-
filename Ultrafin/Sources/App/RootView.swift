import SwiftUI

/// Routes between the major flows based on `AppState.phase`.
///
/// Transitions use a soft cross-fade so launch → onboarding → app never feels
/// like a hard cut. Each branch owns its own navigation stack.
struct RootView: View {
    @Environment(AppState.self) private var appState

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
            case .authenticated:
                MainTabView()
                    .transition(.opacity)
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

/// Branded splash shown while the saved session is validated.
struct LaunchView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(UltrafinColors.accentGradient)
                .scaleEffect(pulse ? 1.05 : 0.95)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            Text("Ultrafin")
                .font(Typography.displayTitle)
                .foregroundStyle(UltrafinColors.primaryText)
        }
        .onAppear { pulse = true }
    }
}
