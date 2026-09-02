import Foundation
import Security

/// Persists the active `UserSession` plus every profile that has signed in on
/// this device (so switching accounts never re-asks for a password). Non-secret
/// metadata lives in `UserDefaults`; tokens live in the Keychain so they survive
/// the reinstall policy and are never written to disk in the clear.
final class SessionStore {
    static let shared = SessionStore()

    private let defaults = UserDefaults.standard
    private let sessionKey = "com.ultrafin.session"
    private let keychainAccount = "com.ultrafin.accessToken"
    /// Keychain account holding ALL remembered profiles (sessions incl. tokens).
    private let profilesAccount = "com.ultrafin.savedProfiles"

    private init() {}

    func save(_ session: UserSession) {
        // Store the token in Keychain, the rest as JSON in defaults.
        keychainSet(session.accessToken, account: keychainAccount)
        var redacted = session
        redacted.accessToken = "" // never persist the token in defaults
        if let data = try? JSONEncoder().encode(redacted) {
            defaults.set(data, forKey: sessionKey)
        }
        remember(session)
    }

    func loadSession() -> UserSession? {
        guard let data = defaults.data(forKey: sessionKey),
              var session = try? JSONDecoder().decode(UserSession.self, from: data),
              let token = keychainGet(account: keychainAccount), !token.isEmpty
        else { return nil }
        session.accessToken = token
        return session
    }

    /// Clears only the ACTIVE session (sign out) — remembered profiles stay so
    /// switching back in is instant.
    func clear() {
        defaults.removeObject(forKey: sessionKey)
        keychainDelete(account: keychainAccount)
    }

    // MARK: - Remembered profiles

    /// Every profile that has authenticated on this device, tokens included
    /// (stored as one JSON blob in the Keychain).
    func savedSessions() -> [UserSession] {
        guard let raw = keychainGet(account: profilesAccount),
              let data = raw.data(using: .utf8),
              let sessions = try? JSONDecoder().decode([UserSession].self, from: data)
        else { return [] }
        return sessions
    }

    /// The remembered session for a user on a server, if any.
    func savedSession(userID: String, serverID: String) -> UserSession? {
        savedSessions().first { $0.userID == userID && $0.server.id == serverID }
    }

    /// Upserts a profile into the remembered list (keyed by user + server).
    func remember(_ session: UserSession) {
        guard !session.accessToken.isEmpty else { return }
        var sessions = savedSessions()
        sessions.removeAll { $0.userID == session.userID && $0.server.id == session.server.id }
        sessions.append(session)
        persistProfiles(sessions)
    }

    /// Drops a remembered profile (e.g. after its token is rejected).
    func forget(userID: String, serverID: String) {
        var sessions = savedSessions()
        sessions.removeAll { $0.userID == userID && $0.server.id == serverID }
        persistProfiles(sessions)
    }

    private func persistProfiles(_ sessions: [UserSession]) {
        guard let data = try? JSONEncoder().encode(sessions),
              let json = String(data: data, encoding: .utf8) else { return }
        keychainSet(json, account: profilesAccount)
    }

    // MARK: - Keychain helpers

    private func keychainSet(_ value: String, account: String) {
        keychainDelete(account: account)
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func keychainGet(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
