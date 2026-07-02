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
    let criticRating: Double?
    let runTimeTicks: Int64?
    let userData: UserData?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let seriesName: String?
    let seriesId: String?
    let seasonId: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let genres: [String]?
    let childCount: Int?
    let people: [Person]?
    /// Trickplay sprite metadata, keyed by media-source id then resolution width.
    let trickplay: [String: [String: TrickplayInfo]]?
    /// Parent (series) logo, used so episodes can show the show's logo art.
    let parentLogoItemId: String?
    let parentLogoImageTag: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case overview = "Overview"
        case productionYear = "ProductionYear"
        case officialRating = "OfficialRating"
        case communityRating = "CommunityRating"
        case criticRating = "CriticRating"
        case runTimeTicks = "RunTimeTicks"
        case userData = "UserData"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case seriesName = "SeriesName"
        case seriesId = "SeriesId"
        case seasonId = "SeasonId"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case genres = "Genres"
        case childCount = "ChildCount"
        case people = "People"
        case trickplay = "Trickplay"
        case parentLogoItemId = "ParentLogoItemId"
        case parentLogoImageTag = "ParentLogoImageTag"
    }

    /// Rotten Tomatoes Tomatometer percentage (Jellyfin's CriticRating).
    var criticScoreText: String? {
        guard let criticRating else { return nil }
        return "\(Int(criticRating.rounded()))%"
    }
    /// True when the Tomatometer is "Fresh" (≥ 60%).
    var isFresh: Bool { (criticRating ?? 0) >= 60 }

    /// "Drama · Sci-Fi · Thriller" from the first few genres.
    var genreText: String? {
        guard let genres, !genres.isEmpty else { return nil }
        return genres.prefix(3).joined(separator: " · ")
    }

    /// Top-billed cast names, comma separated.
    var castText: String? {
        let names = (people ?? []).filter { $0.type == "Actor" }.prefix(4).map(\.name)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// Director (movie) or creator/writer (series), labeled.
    var crewLine: (label: String, name: String)? {
        let people = people ?? []
        if let director = people.first(where: { $0.type == "Director" }) {
            return ("Director", director.name)
        }
        if let writer = people.first(where: { $0.type == "Writer" }) {
            return ("Creator", writer.name)
        }
        return nil
    }

    /// Compact episode tag like "S1·E4" for episodes.
    var episodeTag: String? {
        guard type == .episode else { return nil }
        let s = parentIndexNumber.map { "S\($0)" } ?? ""
        let e = indexNumber.map { "E\($0)" } ?? ""
        return [s, e].filter { !$0.isEmpty }.joined(separator: "·")
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

    /// Time remaining for an in-progress item, e.g. "24m left" — answers "how
    /// much of this is left?" at a glance on Continue Watching.
    var remainingText: String? {
        guard let played = userData?.playbackPositionTicks, let total = runTimeTicks,
              total > 0, played > 0, played < total else { return nil }
        let minutes = Int((total - played) / 600_000_000)
        guard minutes > 0 else { return nil }
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m left" : "\(m)m left"
    }

    /// True when the server has this item marked fully watched.
    var isWatched: Bool { userData?.played == true }
}

/// A cast or crew member attached to an item.
struct Person: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let type: String
    let role: String?
    let primaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case role = "Role"
        case primaryImageTag = "PrimaryImageTag"
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

/// An intro/outro/etc. segment from the Media Segments API (e.g. Intro Skipper).
struct MediaSegment: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case intro, outro, other }
    let kind: Kind
    let start: Double // seconds
    let end: Double
}

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
