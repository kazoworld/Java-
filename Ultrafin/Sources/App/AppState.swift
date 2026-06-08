import SwiftUI
import Observation

/// Top-level navigation phase for the application.
enum AppPhase: Equatable {
    case launching
    case serverConnect
    case login(server: ServerConnection)
    case authenticated(session: UserSession)
}

/// Owns authentication state and the active Jellyfin client.
///
/// `AppState` is intentionally the only object that knows how to move between
/// phases; views observe it and render the matching flow. Restoring a saved
/// session happens once on launch so returning users land straight on Home.
@Observable
@MainActor
final class AppState {
    private(set) var phase: AppPhase = .launching

    /// The live API client for the authenticated session, or `nil` when signed out.
    private(set) var client: JellyfinClient?

    private let sessionStore: SessionStore

    init(sessionStore: SessionStore = .shared) {
        self.sessionStore = sessionStore
    }

    /// Attempts to restore the last session; otherwise routes to onboarding.
    func bootstrap() async {
        guard let session = sessionStore.loadSession() else {
            phase = .serverConnect
            return
        }
        let client = JellyfinClient(server: session.server, accessToken: session.accessToken)
        // Validate the token is still good before trusting the cached session.
        if await client.validateSession() {
            self.client = client
            phase = .authenticated(session: session)
        } else {
            sessionStore.clear()
            phase = .login(server: session.server)
        }
    }

    func didConnect(to server: ServerConnection) {
        phase = .login(server: server)
    }

    func didAuthenticate(_ session: UserSession) {
        let client = JellyfinClient(server: session.server, accessToken: session.accessToken)
        self.client = client
        sessionStore.save(session)
        phase = .authenticated(session: session)
    }

    func signOut() {
        Task { await client?.reportSessionEnded() }
        sessionStore.clear()
        client = nil
        phase = .serverConnect
    }
}
