import Foundation

/// A reachable Jellyfin server the app can talk to.
struct ServerConnection: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    /// Normalized base URL, e.g. `https://media.example.com` (no trailing slash).
    var baseURL: URL
    var version: String?

    init(id: String, name: String, baseURL: URL, version: String? = nil) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.version = version
    }
}

/// An authenticated user bound to a server, including the access token used for
/// every subsequent request. Persisted (token in Keychain) for auto sign-in.
struct UserSession: Codable, Equatable, Sendable {
    var server: ServerConnection
    var userID: String
    var username: String
    var accessToken: String
}
