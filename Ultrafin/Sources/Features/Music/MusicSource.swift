import Foundation

/// Which backend feeds the Music tab. One source at a time — Jellyfin by
/// default, Navidrome once the user links a server in Settings → Music.
enum MusicSourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case jellyfin, navidrome
    var id: String { rawValue }
    var label: String { self == .jellyfin ? "Jellyfin" : "Navidrome" }
}

/// Everything the music feature needs from a backend: browse, tracks, stream
/// URLs, artwork, lyrics, and play reporting. The views and `MusicPlayer` only
/// ever talk to this, so a whole music backend swaps behind one value.
protocol MusicSource: Sendable {
    var kind: MusicSourceKind { get }

    func recentAlbums() async throws -> [MediaItem]
    func allAlbums() async throws -> [MediaItem]
    func artists() async throws -> [MediaItem]
    func playlists() async throws -> [MediaItem]
    func albumTracks(albumID: String) async throws -> [MediaItem]
    func playlistTracks(playlistID: String) async throws -> [MediaItem]
    func artistAlbums(artistID: String) async throws -> [MediaItem]
    func randomSongs() async throws -> [MediaItem]
    func favoriteSongs() async throws -> [MediaItem]

    // Smart mixes + insights.
    func mostPlayedSongs() async throws -> [MediaItem]
    func recentlyPlayedSongs() async throws -> [MediaItem]
    func discoverySongs() async throws -> [MediaItem]
    func songsForInsights() async throws -> [MediaItem]
    /// Albums, artists and songs matching a query.
    func searchMusic(query: String) async throws -> [MediaItem]
    /// The whole library, for offline download and sync.
    func allSongs() async throws -> [MediaItem]

    func lyrics(for track: MediaItem) async -> [LyricLine]
    func audioStreamURL(itemID: String) async -> URL?
    /// Synchronous so view bodies can compute artwork URLs inline.
    func artworkURL(for item: MediaItem, maxWidth: Int) -> URL?

    func reportStarted(itemID: String) async
    func reportStopped(itemID: String, positionTicks: Int64) async

    /// Heart / star an album or track on the backing server.
    func setFavorite(itemID: String, isFavorite: Bool) async
}

// MARK: - Jellyfin

/// The default source: the signed-in Jellyfin server's music libraries.
struct JellyfinMusicSource: MusicSource {
    let client: JellyfinClient
    let userID: String

    var kind: MusicSourceKind { .jellyfin }

    func recentAlbums() async throws -> [MediaItem] { try await client.recentAlbums(userID: userID) }
    func allAlbums() async throws -> [MediaItem] { try await client.allAlbums(userID: userID) }
    func artists() async throws -> [MediaItem] { try await client.artists(userID: userID) }
    func playlists() async throws -> [MediaItem] { try await client.playlists(userID: userID) }
    func albumTracks(albumID: String) async throws -> [MediaItem] {
        try await client.albumTracks(albumID: albumID, userID: userID)
    }
    func playlistTracks(playlistID: String) async throws -> [MediaItem] {
        try await client.playlistTracks(playlistID: playlistID, userID: userID)
    }
    func artistAlbums(artistID: String) async throws -> [MediaItem] {
        try await client.artistAlbums(artistID: artistID, userID: userID)
    }
    func randomSongs() async throws -> [MediaItem] { try await client.randomSongs(userID: userID) }
    func favoriteSongs() async throws -> [MediaItem] { try await client.favoriteSongs(userID: userID) }
    func mostPlayedSongs() async throws -> [MediaItem] { try await client.mostPlayedSongs(userID: userID) }
    func recentlyPlayedSongs() async throws -> [MediaItem] { try await client.recentlyPlayedSongs(userID: userID) }
    func discoverySongs() async throws -> [MediaItem] { try await client.discoverySongs(userID: userID) }
    func songsForInsights() async throws -> [MediaItem] { try await client.songsForInsights(userID: userID) }
    func searchMusic(query: String) async throws -> [MediaItem] {
        try await client.searchMusic(query: query, userID: userID)
    }
    func allSongs() async throws -> [MediaItem] { try await client.allSongs(userID: userID) }

    func lyrics(for track: MediaItem) async -> [LyricLine] { await client.lyrics(itemID: track.id) }
    func audioStreamURL(itemID: String) async -> URL? {
        await client.audioStreamURL(itemID: itemID, userID: userID)
    }

    func artworkURL(for item: MediaItem, maxWidth: Int) -> URL? {
        // Songs use their album's art when they have one (same fallback the
        // music views used before this abstraction).
        if item.type == .audio, let albumId = item.albumId {
            return client.imageURL(itemID: albumId, kind: .primary,
                                   tag: item.albumPrimaryImageTag, maxWidth: maxWidth)
        }
        return client.imageURL(itemID: item.id, kind: .primary,
                               tag: item.imageTags?["Primary"], maxWidth: maxWidth)
    }

    func reportStarted(itemID: String) async {
        await client.reportPlaybackStarted(itemID: itemID, positionTicks: 0, playSessionID: nil)
    }
    func reportStopped(itemID: String, positionTicks: Int64) async {
        await client.reportPlaybackStopped(itemID: itemID, positionTicks: positionTicks, playSessionID: nil)
    }
    func setFavorite(itemID: String, isFavorite: Bool) async {
        _ = await client.setFavorite(itemID: itemID, userID: userID, isFavorite: isFavorite)
    }
}

// MARK: - Navidrome

/// The linked Navidrome server, via the Subsonic API.
struct NavidromeMusicSource: MusicSource {
    let client: NavidromeClient

    var kind: MusicSourceKind { .navidrome }

    func recentAlbums() async throws -> [MediaItem] { try await client.recentAlbums() }
    func allAlbums() async throws -> [MediaItem] { try await client.allAlbums() }
    func artists() async throws -> [MediaItem] { try await client.artists() }
    func playlists() async throws -> [MediaItem] { try await client.playlists() }
    func albumTracks(albumID: String) async throws -> [MediaItem] {
        try await client.albumTracks(albumID: albumID)
    }
    func playlistTracks(playlistID: String) async throws -> [MediaItem] {
        try await client.playlistTracks(playlistID: playlistID)
    }
    func artistAlbums(artistID: String) async throws -> [MediaItem] {
        try await client.artistAlbums(artistID: artistID)
    }
    func randomSongs() async throws -> [MediaItem] { try await client.randomSongs() }
    func favoriteSongs() async throws -> [MediaItem] { try await client.favoriteSongs() }
    func mostPlayedSongs() async throws -> [MediaItem] { try await client.mostPlayedSongs() }
    func recentlyPlayedSongs() async throws -> [MediaItem] { try await client.recentlyPlayedSongs() }
    func discoverySongs() async throws -> [MediaItem] { try await client.discoverySongs() }
    func songsForInsights() async throws -> [MediaItem] { try await client.songsForInsights() }
    func searchMusic(query: String) async throws -> [MediaItem] {
        try await client.searchMusic(query: query)
    }
    func allSongs() async throws -> [MediaItem] { try await client.allSongs() }

    func lyrics(for track: MediaItem) async -> [LyricLine] { await client.lyrics(for: track) }
    func audioStreamURL(itemID: String) async -> URL? { client.streamURL(itemID: itemID) }

    func artworkURL(for item: MediaItem, maxWidth: Int) -> URL? {
        // The Subsonic cover-art id rides in imageTags["Primary"] (set by the
        // mapping layer); fall back to the item id, which Navidrome accepts.
        let coverID = item.imageTags?["Primary"] ?? item.albumPrimaryImageTag ?? item.id
        return client.coverArtURL(coverID: coverID, size: maxWidth)
    }

    func reportStarted(itemID: String) async {
        await client.scrobble(itemID: itemID, submission: false)
    }
    func reportStopped(itemID: String, positionTicks: Int64) async {
        await client.scrobble(itemID: itemID, submission: true)
    }
    func setFavorite(itemID: String, isFavorite: Bool) async {
        await client.setFavorite(itemID: itemID, isFavorite: isFavorite)
    }
}

// MARK: - MediaItem factory

extension MediaItem {
    /// Mints a music item from a non-Jellyfin source (Navidrome). Only the
    /// fields the music UI renders are populated; the backend's cover-art id
    /// rides in `imageTags["Primary"]` so artwork routing stays uniform.
    static func music(id: String, name: String, type: ItemKind,
                      year: Int? = nil, durationSeconds: Int? = nil,
                      artist: String? = nil, album: String? = nil,
                      albumID: String? = nil, coverArtID: String? = nil,
                      trackNumber: Int? = nil, discNumber: Int? = nil,
                      childCount: Int? = nil, genre: String? = nil,
                      playCount: Int? = nil, container: String? = nil,
                      isFavorite: Bool? = nil, artistID: String? = nil) -> MediaItem {
        MediaItem(id: id, name: name, type: type, overview: nil,
                  productionYear: year, officialRating: nil,
                  communityRating: nil, criticRating: nil,
                  runTimeTicks: durationSeconds.map { Int64($0) * 10_000_000 },
                  userData: (playCount != nil || isFavorite != nil)
                      ? UserData(playbackPositionTicks: nil, playedPercentage: nil,
                                 isFavorite: isFavorite, played: (playCount ?? 0) > 0,
                                 playCount: playCount, lastPlayedDate: nil)
                      : nil,
                  imageTags: coverArtID.map { ["Primary": $0] },
                  backdropImageTags: nil, seriesName: nil, seriesId: nil,
                  seasonId: nil, indexNumber: trackNumber,
                  parentIndexNumber: discNumber, genres: genre.map { [$0] },
                  childCount: childCount, people: nil, trickplay: nil,
                  parentLogoItemId: nil, parentLogoImageTag: nil,
                  albumArtist: artist, artists: artist.map { [$0] },
                  album: album, albumId: albumID,
                  albumPrimaryImageTag: coverArtID,
                  container: container,
                  albumArtists: (artistID.flatMap { id in
                      artist.map { [NameIdPair(id: id, name: $0)] }
                  }))
    }
}
