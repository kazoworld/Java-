import SwiftUI
import Observation

/// Top-level navigation phase for the application.
enum AppPhase: Equatable {
    case launching
    case serverConnect
    case login(server: ServerConnection)
    case authenticated(session: UserSession)
    /// Saved session exists but the server is unreachable (offline / IP changed).
    case connectionLost(session: UserSession)
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

    /// The signed-in user's server record (avatar tag, admin flag) — fetched
    /// after auth; nil until it arrives.
    private(set) var currentUser: ServerUser?

    /// True when the signed-in user is a server administrator (drives the
    /// profile switcher's ability to see every account).
    var isAdmin: Bool { currentUser?.isAdministrator ?? false }

    let sessionStore: SessionStore

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
        do {
            try await client.checkConnection()
            self.client = client
            phase = .authenticated(session: session)
            refreshCurrentUser(session)
        } catch APIError.unauthorized {
            // Server reachable, but the token expired — re-login.
            sessionStore.clear()
            phase = .login(server: session.server)
        } catch {
            // Server unreachable (offline, or its address changed). Keep the
            // session and let the user retry or sign out to a new server.
            phase = .connectionLost(session: session)
        }
    }

    /// Re-attempt connecting with the saved session (from the connection-lost
    /// screen).
    func retryConnection() async {
        phase = .launching
        await bootstrap()
    }

    func didConnect(to server: ServerConnection) {
        phase = .login(server: server)
    }

    func didAuthenticate(_ session: UserSession) {
        let client = JellyfinClient(server: session.server, accessToken: session.accessToken)
        self.client = client
        sessionStore.save(session)
        phase = .authenticated(session: session)
        refreshCurrentUser(session)
    }

    /// Switches to a remembered profile. Returns false when its saved token has
    /// been revoked (the caller should fall back to re-auth / a password prompt).
    func switchTo(_ session: UserSession) async -> Bool {
        let candidate = JellyfinClient(server: session.server, accessToken: session.accessToken)
        do {
            // Must be a USER-scoped check: Jellyfin revokes the device's old
            // token when the same device signs in as another user, and a bare
            // reachability probe can pass on a revoked token — which used to
            // "switch" into a session whose every library call then failed.
            try await candidate.requireUserAccess(userID: session.userID)
        } catch APIError.unauthorized {
            sessionStore.forget(userID: session.userID, serverID: session.server.id)
            return false
        } catch {
            return false // unreachable — keep the current session
        }
        currentUser = nil
        client = candidate
        sessionStore.save(session)
        phase = .authenticated(session: session)
        refreshCurrentUser(session)
        return true
    }

    /// Fetches the signed-in user's record (avatar tag + admin flag).
    private func refreshCurrentUser(_ session: UserSession) {
        Task { [weak self] in
            guard let self, let client = self.client else { return }
            let detail = await client.userDetail(userID: session.userID)
            // Only apply if we're still on the same user (a fast switch could race).
            if case .authenticated(let current) = self.phase, current.userID == session.userID {
                self.currentUser = detail
            }
        }
    }

    func signOut() {
        Task { await client?.reportSessionEnded() }
        sessionStore.clear()
        client = nil
        currentUser = nil
        phase = .serverConnect
    }
}
