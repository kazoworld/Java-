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
    // Music fields (songs and albums).
    let albumArtist: String?
    let artists: [String]?
    let album: String?
    let albumId: String?
    let albumPrimaryImageTag: String?
    /// Source container/codec ("flac", "mp3", "m4a") — shown as the quality
    /// badge on album pages.
    let container: String?
    /// The release's credited artists, with IDs — lets a song link through to
    /// its artist page.
    let albumArtists: [NameIdPair]?

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
        case albumArtist = "AlbumArtist"
        case artists = "Artists"
        case album = "Album"
        case albumId = "AlbumId"
        case albumPrimaryImageTag = "AlbumPrimaryImageTag"
        case container = "Container"
        case albumArtists = "AlbumArtists"
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

    /// "Artist" or "Artist A, Artist B" for songs/albums.
    var artistText: String? {
        if let artists, !artists.isEmpty { return artists.joined(separator: ", ") }
        return albumArtist
    }

    /// "3:42" for songs.
    var trackDurationText: String? {
        guard let ticks = runTimeTicks, ticks > 0 else { return nil }
        let total = Int(ticks / 10_000_000)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Times played (0 when the server hasn't reported any).
    var playCount: Int { userData?.playCount ?? 0 }

    /// Runtime in seconds (0 when unknown) — used to total listening time.
    var runtimeSeconds: Double { Double(runTimeTicks ?? 0) / 10_000_000 }

    /// The song's primary artist for grouping in insights.
    var primaryArtist: String? {
        if let first = artists?.first, !first.isEmpty { return first }
        if let albumArtist, !albumArtist.isEmpty { return albumArtist }
        return nil
    }

    /// Whether the track/album is flagged explicit (servers that tag it put it
    /// in the official rating). Drives the "E" badge in music lists.
    var isExplicit: Bool {
        guard let rating = officialRating?.lowercased() else { return false }
        return rating.contains("explicit")
    }

    /// The quality badge for an album page — "FLAC", "MP3", "ALAC"…
    var formatBadge: String? {
        guard let container, !container.isEmpty else { return nil }
        return container.uppercased()
    }

    /// How many songs a release holds, when the server reports it.
    var trackCount: Int? { childCount }

    /// A one-track release is a single, not an album. Two or more makes it an
    /// album. Without a count from the server we can't tell, so we say nothing
    /// rather than guess.
    var releaseKind: ReleaseKind? {
        guard type == .musicAlbum, let count = trackCount else { return nil }
        return count <= 1 ? .single : .album
    }
}

/// An id + display name, as Jellyfin returns for artists on an item.
struct NameIdPair: Codable, Hashable, Sendable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

extension MediaItem {
    /// The artist to open when the user taps the artist name, when the server
    /// gave us an id for them. (`primaryArtist` is the display string; this is
    /// the linkable credit.)
    var artistCredit: NameIdPair? { albumArtists?.first }

    /// A stand-in album item for navigation from a song (the detail page loads
    /// the rest from the id).
    var albumDestination: MediaItem? {
        guard let albumId, !albumId.isEmpty else { return nil }
        return .music(id: albumId, name: album ?? "Album", type: .musicAlbum,
                      artist: artistText, albumID: albumId,
                      coverArtID: albumPrimaryImageTag ?? albumId)
    }

    /// A stand-in artist item for navigation from a song.
    var artistDestination: MediaItem? {
        guard let artist = artistCredit else { return nil }
        return .music(id: artist.id, name: artist.name, type: .musicArtist,
                      coverArtID: artist.id)
    }
}

/// Album vs. single, so a one-song release never masquerades as a full record.
enum ReleaseKind: String, Sendable {
    case single, album

    var label: String { self == .single ? "Single" : "Album" }
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
    case musicArtist = "MusicArtist"
    case playlist = "Playlist"
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
    /// How many times this item has been played — drives On Repeat and the
    /// listening insights.
    let playCount: Int?
    /// ISO date of the last play, used for "Recently Played" ordering.
    let lastPlayedDate: String?

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playedPercentage = "PlayedPercentage"
        case isFavorite = "IsFavorite"
        case played = "Played"
        case playCount = "PlayCount"
        case lastPlayedDate = "LastPlayedDate"
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

/// One line of synced lyrics for a song. `start` is seconds into the track
/// (nil when the server only has unsynced lyrics).
struct LyricLine: Identifiable, Hashable, Sendable {
    let id: Int
    let text: String
    let start: Double?
}
