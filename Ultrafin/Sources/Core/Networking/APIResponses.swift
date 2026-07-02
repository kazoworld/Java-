import Foundation

/// `/Users/AuthenticateByName` response.
struct AuthenticationResult: Decodable {
    let user: AuthUser
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
    }
}

struct AuthUser: Decodable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

/// A user account on the server (`/Users`, `/Users/Public`, `/Users/{id}`).
struct ServerUser: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Tag of the user's profile image, or nil when none is set.
    let primaryImageTag: String?
    let hasPassword: Bool?
    let policy: Policy?

    struct Policy: Decodable, Hashable, Sendable {
        let isAdministrator: Bool?
        enum CodingKeys: String, CodingKey { case isAdministrator = "IsAdministrator" }
    }

    var isAdministrator: Bool { policy?.isAdministrator ?? false }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case primaryImageTag = "PrimaryImageTag"
        case hasPassword = "HasPassword"
        case policy = "Policy"
    }
}

/// `/System/Info/Public` — used for server discovery and token validation.
struct PublicSystemInfo: Decodable {
    let serverName: String?
    let version: String?
    let id: String?

    enum CodingKeys: String, CodingKey {
        case serverName = "ServerName"
        case version = "Version"
        case id = "Id"
    }
}

/// `/Items/{id}/PlaybackInfo` response.
struct PlaybackInfoResponse: Decodable {
    let mediaSources: [MediaSource]
    let playSessionID: String?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionID = "PlaySessionId"
    }
}

/// `/MediaSegments/{itemId}` response (intro/outro detection).
struct MediaSegmentsResponse: Decodable {
    let items: [Segment]

    struct Segment: Decodable {
        let type: String
        let startTicks: Int64
        let endTicks: Int64

        enum CodingKeys: String, CodingKey {
            case type = "Type"
            case startTicks = "StartTicks"
            case endTicks = "EndTicks"
        }
    }

    enum CodingKeys: String, CodingKey { case items = "Items" }
}

struct MediaSource: Decodable {
    let id: String?
    let container: String?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let supportsTranscoding: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case container = "Container"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding"
    }
}
