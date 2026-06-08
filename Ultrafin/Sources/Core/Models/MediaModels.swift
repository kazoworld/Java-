import Foundation

/// A media item returned by Jellyfin (movie, series, episode, collection, …).
/// Only the fields the UI actually renders are modeled; everything else is
/// ignored during decoding so the client stays resilient to server changes.
struct MediaItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let type: ItemKind
    let overview: String?
    let productionYear: Int?
    let officialRating: String?
    let communityRating: Double?
    let runTimeTicks: Int64?
    let userData: UserData?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let seriesName: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case overview = "Overview"
        case productionYear = "ProductionYear"
        case officialRating = "OfficialRating"
        case communityRating = "CommunityRating"
        case runTimeTicks = "RunTimeTicks"
        case userData = "UserData"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case seriesName = "SeriesName"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
    }

    /// Human-friendly runtime, e.g. "1h 47m".
    var runtimeText: String? {
        guard let ticks = runTimeTicks else { return nil }
        let totalMinutes = Int(ticks / 600_000_000)
        guard totalMinutes > 0 else { return nil }
        let h = totalMinutes / 60, m = totalMinutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    /// 0...1 resume position, or nil if not started.
    var playbackProgress: Double? {
        guard let played = userData?.playbackPositionTicks, let total = runTimeTicks, total > 0, played > 0
        else { return nil }
        return min(1, Double(played) / Double(total))
    }
}

enum ItemKind: String, Codable, Sendable {
    case movie = "Movie"
    case series = "Series"
    case season = "Season"
    case episode = "Episode"
    case boxSet = "BoxSet"
    case collectionFolder = "CollectionFolder"
    case folder = "Folder"
    case audio = "Audio"
    case musicAlbum = "MusicAlbum"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ItemKind(rawValue: raw) ?? .unknown
    }
}

struct UserData: Codable, Hashable, Sendable {
    let playbackPositionTicks: Int64?
    let playedPercentage: Double?
    let isFavorite: Bool?
    let played: Bool?

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playedPercentage = "PlayedPercentage"
        case isFavorite = "IsFavorite"
        case played = "Played"
    }
}

/// Wrapper around Jellyfin's `{ Items: [...], TotalRecordCount: n }` responses.
struct ItemsResponse: Codable, Sendable {
    let items: [MediaItem]
    let totalRecordCount: Int

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

// MARK: - Playback

/// Playback details resolved from `/Items/{id}/PlaybackInfo`. Determines which
/// engine the hybrid player uses and the exact stream URL to open.
struct PlaybackResolution: Sendable {
    let streamURL: URL
    /// `true` when the server returned a direct-play source AVFoundation can
    /// handle; `false` means HLS transcode or a container we route to VLCKit.
    let isDirectPlay: Bool
    let container: String?
    let playSessionID: String?
}
