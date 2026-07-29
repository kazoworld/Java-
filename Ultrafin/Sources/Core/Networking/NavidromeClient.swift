import Foundation
import CryptoKit
import Security
import Observation

/// A linked Navidrome server: address plus the credentials the Subsonic API
/// signs every request with.
struct NavidromeConfig: Codable, Sendable, Equatable {
    var serverURL: URL
    var username: String
    var password: String
}

/// Persists the linked Navidrome server. Credentials live in the Keychain only
/// (the Subsonic token scheme needs the password to salt each request, so it
/// can never be reduced to a revocable token the way Jellyfin's session is).
@Observable
@MainActor
final class NavidromeStore {
    static let shared = NavidromeStore()

    private(set) var config: NavidromeConfig?

    private let account = "com.ultrafin.navidrome"

    private init() {
        if let raw = Self.keychainGet(account: account),
           let data = raw.data(using: .utf8) {
            config = try? JSONDecoder().decode(NavidromeConfig.self, from: data)
        }
    }

    func link(_ config: NavidromeConfig) {
        self.config = config
        if let data = try? JSONEncoder().encode(config),
           let json = String(data: data, encoding: .utf8) {
            Self.keychainSet(json, account: account)
        }
    }

    func unlink() {
        config = nil
        Self.keychainDelete(account: account)
    }

    // MARK: - Keychain

    private static func keychainSet(_ value: String, account: String) {
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

    private static func keychainGet(account: String) -> String? {
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

    private static func keychainDelete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Talks the Subsonic API that Navidrome implements. Auth is the spec's token
/// scheme: `t = md5(password + salt)` sent with a salt on every request.
///
/// The salt is derived deterministically from the config (not random per
/// request) so generated URLs — cover art, streams — are byte-identical across
/// renders; the image cache keys on the URL, and a fresh salt each time would
/// re-download every artwork on every screen.
actor NavidromeClient {
    private let config: NavidromeConfig
    private let salt: String
    private let token: String

    init(config: NavidromeConfig) {
        self.config = config
        let salt = String(Self.md5Hex("ultrafin." + config.username + "@" + config.serverURL.absoluteString).prefix(12))
        self.salt = salt
        self.token = Self.md5Hex(config.password + salt)
    }

    private static func md5Hex(_ string: String) -> String {
        Insecure.MD5.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Request plumbing

    nonisolated private func url(_ endpoint: String, query: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(url: config.serverURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path += "/rest/\(endpoint)"
        components.queryItems = [
            .init(name: "u", value: config.username),
            .init(name: "t", value: token),
            .init(name: "s", value: salt),
            .init(name: "v", value: "1.16.1"),
            .init(name: "c", value: "Ultrafin"),
            .init(name: "f", value: "json")
        ] + query
        // Same fix as JellyfinClient: a literal "+" in a query value decodes
        // server-side as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// Subsonic wraps everything in `{"subsonic-response": {"status": …}}` and
    /// reports failures as `status: "failed"` inside an HTTP 200 — so errors
    /// are surfaced from the envelope, not the status code.
    private struct SubsonicResponse<Body: Decodable>: Decodable {
        let body: Body

        private enum RootKey: String, CodingKey { case root = "subsonic-response" }
        private struct Meta: Decodable {
            let status: String
            let error: ErrorBody?
            struct ErrorBody: Decodable { let message: String? }
        }

        init(from decoder: Decoder) throws {
            let root = try decoder.container(keyedBy: RootKey.self)
            let meta = try root.decode(Meta.self, forKey: .root)
            guard meta.status == "ok" else {
                throw APIError.network(meta.error?.message ?? "The Navidrome server reported an error.")
            }
            body = try root.decode(Body.self, forKey: .root)
        }
    }

    private func get<Body: Decodable>(_ type: Body.Type, _ endpoint: String,
                                      query: [URLQueryItem] = []) async throws -> Body {
        guard let url = url(endpoint, query: query) else { throw APIError.invalidURL }
        let data: Data
        do {
            let (payload, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else { throw APIError.unreachable }
            guard (200...299).contains(http.statusCode) else { throw APIError.server(status: http.statusCode) }
            data = payload
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        return try JSONDecoder().decode(SubsonicResponse<Body>.self, from: data).body
    }

    // MARK: - Connection

    /// Validates the address + credentials (used by the linking flow).
    func ping() async throws {
        struct Body: Decodable {}
        _ = try await get(Body.self, "ping")
    }

    // MARK: - Library

    func recentAlbums() async throws -> [MediaItem] {
        struct Body: Decodable {
            let albumList2: List?
            struct List: Decodable { let album: [SubsonicAlbum]? }
        }
        let body = try await get(Body.self, "getAlbumList2", query: [
            .init(name: "type", value: "newest"),
            .init(name: "size", value: "24")
        ])
        return (body.albumList2?.album ?? []).map(\.mediaItem)
    }

    func allAlbums(limit: Int = 300) async throws -> [MediaItem] {
        struct Body: Decodable {
            let albumList2: List?
            struct List: Decodable { let album: [SubsonicAlbum]? }
        }
        let body = try await get(Body.self, "getAlbumList2", query: [
            .init(name: "type", value: "alphabeticalByName"),
            .init(name: "size", value: String(limit))
        ])
        return (body.albumList2?.album ?? []).map(\.mediaItem)
    }

    func artists() async throws -> [MediaItem] {
        struct Body: Decodable {
            let artists: Indexes?
            struct Indexes: Decodable { let index: [Index]? }
            struct Index: Decodable { let artist: [SubsonicArtist]? }
        }
        let body = try await get(Body.self, "getArtists")
        return (body.artists?.index ?? []).flatMap { $0.artist ?? [] }.map(\.mediaItem)
    }

    func playlists() async throws -> [MediaItem] {
        struct Body: Decodable {
            let playlists: List?
            struct List: Decodable { let playlist: [SubsonicPlaylist]? }
        }
        let body = try await get(Body.self, "getPlaylists")
        return (body.playlists?.playlist ?? []).map(\.mediaItem)
    }

    func albumTracks(albumID: String) async throws -> [MediaItem] {
        struct Body: Decodable {
            let album: Album?
            struct Album: Decodable { let song: [SubsonicSong]? }
        }
        let body = try await get(Body.self, "getAlbum", query: [.init(name: "id", value: albumID)])
        return (body.album?.song ?? []).map(\.mediaItem)
    }

    func playlistTracks(playlistID: String) async throws -> [MediaItem] {
        struct Body: Decodable {
            let playlist: Playlist?
            struct Playlist: Decodable { let entry: [SubsonicSong]? }
        }
        let body = try await get(Body.self, "getPlaylist", query: [.init(name: "id", value: playlistID)])
        return (body.playlist?.entry ?? []).map(\.mediaItem)
    }

    func artistAlbums(artistID: String) async throws -> [MediaItem] {
        struct Body: Decodable {
            let artist: Artist?
            struct Artist: Decodable { let album: [SubsonicAlbum]? }
        }
        let body = try await get(Body.self, "getArtist", query: [.init(name: "id", value: artistID)])
        // Newest first, like the Jellyfin artist page.
        return (body.artist?.album ?? []).map(\.mediaItem)
            .sorted { ($0.productionYear ?? 0) > ($1.productionYear ?? 0) }
    }

    func randomSongs(limit: Int = 100) async throws -> [MediaItem] {
        struct Body: Decodable {
            let randomSongs: List?
            struct List: Decodable { let song: [SubsonicSong]? }
        }
        let body = try await get(Body.self, "getRandomSongs", query: [.init(name: "size", value: String(limit))])
        return (body.randomSongs?.song ?? []).map(\.mediaItem)
    }

    func favoriteSongs() async throws -> [MediaItem] {
        struct Body: Decodable {
            let starred2: List?
            struct List: Decodable { let song: [SubsonicSong]? }
        }
        let body = try await get(Body.self, "getStarred2")
        return (body.starred2?.song ?? []).map(\.mediaItem)
    }

    // MARK: - Smart mixes

    /// Subsonic exposes play frequency at the album level, so the song-level
    /// mixes are drawn from the most-/recently-played albums' tracks.
    private func albums(type: String, size: Int) async throws -> [String] {
        struct Body: Decodable {
            let albumList2: List?
            struct List: Decodable { let album: [SubsonicAlbum]? }
        }
        let body = try await get(Body.self, "getAlbumList2", query: [
            .init(name: "type", value: type),
            .init(name: "size", value: String(size))
        ])
        return (body.albumList2?.album ?? []).map(\.id)
    }

    private func songs(fromAlbums ids: [String]) async -> [MediaItem] {
        var out: [MediaItem] = []
        // Sequential to stay gentle on the server; the album counts are small.
        for id in ids {
            if let tracks = try? await albumTracks(albumID: id) { out.append(contentsOf: tracks) }
        }
        return out
    }

    func mostPlayedSongs() async throws -> [MediaItem] {
        await songs(fromAlbums: try await albums(type: "frequent", size: 12))
    }

    func recentlyPlayedSongs() async throws -> [MediaItem] {
        await songs(fromAlbums: try await albums(type: "recent", size: 12))
    }

    /// No "unplayed" filter in Subsonic — a random spread stands in for Discovery.
    func discoverySongs() async throws -> [MediaItem] {
        try await randomSongs()
    }

    func songsForInsights() async throws -> [MediaItem] {
        await songs(fromAlbums: try await albums(type: "frequent", size: 40))
    }

    // MARK: - Search

    /// Subsonic `search3` — artists, albums and songs in one pass.
    func searchMusic(query: String) async throws -> [MediaItem] {
        struct Body: Decodable {
            let searchResult3: Result?
            struct Result: Decodable {
                let artist: [SubsonicArtist]?
                let album: [SubsonicAlbum]?
                let song: [SubsonicSong]?
            }
        }
        let body = try await get(Body.self, "search3", query: [
            .init(name: "query", value: query),
            .init(name: "artistCount", value: "20"),
            .init(name: "albumCount", value: "30"),
            .init(name: "songCount", value: "40")
        ])
        guard let result = body.searchResult3 else { return [] }
        return (result.album ?? []).map(\.mediaItem)
            + (result.artist ?? []).map(\.mediaItem)
            + (result.song ?? []).map(\.mediaItem)
    }

    // MARK: - Lyrics

    /// Synced lyrics via the OpenSubsonic `getLyricsBySongId` extension
    /// (Navidrome supports it), falling back to classic unsynced `getLyrics`.
    func lyrics(for track: MediaItem) async -> [LyricLine] {
        struct Body: Decodable {
            let lyricsList: List?
            struct List: Decodable { let structuredLyrics: [Structured]? }
            struct Structured: Decodable {
                let synced: Bool?
                let line: [Line]?
                struct Line: Decodable {
                    let start: Int64? // milliseconds
                    let value: String
                }
            }
        }
        if let body = try? await get(Body.self, "getLyricsBySongId", query: [.init(name: "id", value: track.id)]),
           let best = (body.lyricsList?.structuredLyrics ?? []).first(where: { $0.synced == true })
               ?? body.lyricsList?.structuredLyrics?.first,
           let lines = best.line, !lines.isEmpty {
            return lines.enumerated().map { index, line in
                LyricLine(id: index, text: line.value,
                          start: best.synced == true ? line.start.map { Double($0) / 1000 } : nil)
            }
        }
        struct Plain: Decodable {
            let lyrics: Value?
            struct Value: Decodable { let value: String? }
        }
        guard let artist = track.artistText,
              let body = try? await get(Plain.self, "getLyrics", query: [
                  .init(name: "artist", value: artist),
                  .init(name: "title", value: track.name)
              ]),
              let text = body.lyrics?.value, !text.isEmpty else { return [] }
        return text.components(separatedBy: .newlines).enumerated().map {
            LyricLine(id: $0.offset, text: $0.element, start: nil)
        }
    }

    // MARK: - Streaming & art

    /// Raw stream — no transcode, so the original quality reaches the speakers.
    /// AVPlayer handles the common cases (MP3, AAC/ALAC, FLAC, WAV) natively.
    nonisolated func streamURL(itemID: String) -> URL? {
        url("stream", query: [.init(name: "id", value: itemID)])
    }

    nonisolated func coverArtURL(coverID: String, size: Int) -> URL? {
        url("getCoverArt", query: [
            .init(name: "id", value: coverID),
            .init(name: "size", value: String(size))
        ])
    }

    // MARK: - Play reporting

    /// Scrobble: `submission=false` is "now playing", `true` records the play.
    func scrobble(itemID: String, submission: Bool) async {
        struct Body: Decodable {}
        _ = try? await get(Body.self, "scrobble", query: [
            .init(name: "id", value: itemID),
            .init(name: "submission", value: submission ? "true" : "false")
        ])
    }

    /// Subsonic's star/unstar — the Navidrome equivalent of a Jellyfin favorite.
    func setFavorite(itemID: String, isFavorite: Bool) async {
        struct Body: Decodable {}
        _ = try? await get(Body.self, isFavorite ? "star" : "unstar",
                           query: [.init(name: "id", value: itemID)])
    }
}

// MARK: - Subsonic models → MediaItem

private struct SubsonicAlbum: Decodable {
    let id: String
    let name: String?
    let album: String?
    let artist: String?
    let year: Int?
    let coverArt: String?
    let songCount: Int?
    /// Present (an ISO date) when the user has starred this album.
    let starred: String?

    var mediaItem: MediaItem {
        .music(id: id, name: name ?? album ?? "Album", type: .musicAlbum,
               year: year, artist: artist, coverArtID: coverArt, childCount: songCount,
               isFavorite: starred != nil)
    }
}

private struct SubsonicArtist: Decodable {
    let id: String
    let name: String
    let coverArt: String?
    let albumCount: Int?

    var mediaItem: MediaItem {
        .music(id: id, name: name, type: .musicArtist,
               coverArtID: coverArt, childCount: albumCount)
    }
}

private struct SubsonicPlaylist: Decodable {
    let id: String
    let name: String
    let coverArt: String?
    let songCount: Int?

    var mediaItem: MediaItem {
        .music(id: id, name: name, type: .playlist,
               coverArtID: coverArt, childCount: songCount)
    }
}

private struct SubsonicSong: Decodable {
    let id: String
    let title: String?
    let album: String?
    let artist: String?
    let albumId: String?
    let track: Int?
    let discNumber: Int?
    let year: Int?
    let duration: Int? // seconds
    let coverArt: String?
    let genre: String?
    let playCount: Int?
    /// File extension ("flac", "mp3") — the Subsonic equivalent of Container.
    let suffix: String?
    /// Present (an ISO date) when the user has starred this song.
    let starred: String?

    var mediaItem: MediaItem {
        .music(id: id, name: title ?? "Song", type: .audio,
               year: year, durationSeconds: duration, artist: artist,
               album: album, albumID: albumId, coverArtID: coverArt,
               trackNumber: track, discNumber: discNumber,
               genre: genre, playCount: playCount,
               container: suffix, isFavorite: starred != nil)
    }
}
