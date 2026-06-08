import Foundation
import Security

/// Persists the active `UserSession`. Non-secret metadata lives in
/// `UserDefaults`; the access token is stored in the Keychain so it survives
/// reinstalls policy and is never written to disk in the clear.
final class SessionStore {
    static let shared = SessionStore()

    private let defaults = UserDefaults.standard
    private let sessionKey = "com.ultrafin.session"
    private let keychainAccount = "com.ultrafin.accessToken"

    private init() {}

    func save(_ session: UserSession) {
        // Store the token in Keychain, the rest as JSON in defaults.
        keychainSet(session.accessToken)
        var redacted = session
        redacted.accessToken = "" // never persist the token in defaults
        if let data = try? JSONEncoder().encode(redacted) {
            defaults.set(data, forKey: sessionKey)
        }
    }

    func loadSession() -> UserSession? {
        guard let data = defaults.data(forKey: sessionKey),
              var session = try? JSONDecoder().decode(UserSession.self, from: data),
              let token = keychainGet(), !token.isEmpty
        else { return nil }
        session.accessToken = token
        return session
    }

    func clear() {
        defaults.removeObject(forKey: sessionKey)
        keychainDelete()
    }

    // MARK: - Keychain helpers

    private func keychainSet(_ value: String) {
        keychainDelete()
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func keychainGet() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
