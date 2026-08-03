import Foundation

/// Self-contained async client for the Jellyfin REST API.
///
/// It is intentionally small and dependency-free so the app compiles and runs
/// against a real server out of the box. Screens depend on this type rather
/// than on the generated SDK, which makes it easy to swap the transport later
/// (e.g. onto `JellyfinSDK`) without touching the UI.
actor JellyfinClient {
    let server: ServerConnection
    private(set) var accessToken: String?

    private let session: URLSession
    private let decoder: JSONDecoder

    /// Identifies this client to the server in the `Authorization` header.
    private let deviceID: String
    private let clientName = "Ultrafin"
    private let clientVersion = "1.0.0"

    init(server: ServerConnection, accessToken: String? = nil) {
        self.server = server
        self.accessToken = accessToken
        self.deviceID = DeviceIdentity.persistentID
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Auth header

    /// Jellyfin's `MediaBrowser` authorization scheme, with the token appended
    /// once the user has signed in.
    private var authorizationHeader: String {
        var fields = [
            "Client=\"\(clientName)\"",
            "Device=\"\(DeviceIdentity.deviceName)\"",
            "DeviceId=\"\(deviceID)\"",
            "Version=\"\(clientVersion)\""
        ]
        if let token = accessToken {
            fields.append("Token=\"\(token)\"")
        }
        return "MediaBrowser " + fields.joined(separator: ", ")
    }

    // MARK: - Request plumbing

    private func makeRequest(path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        guard var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = (components.path.isEmpty ? "" : components.path) + path
        if !query.isEmpty {
            components.queryItems = query
            // URLComponents leaves "+" literal in query values, and Jellyfin
            // decodes a literal "+" as a space — so a search for "Disney+"
            // arrived as "Disney ". Encode it explicitly.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.unreachable }
            switch http.statusCode {
            case 200...299: return data
            case 401, 403: throw APIError.unauthorized
            default: throw APIError.server(status: http.statusCode)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    private func get<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        let request = try makeRequest(path: path, query: query)
        let data = try await perform(request)
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding }
    }

    // MARK: - Authentication

    /// Authenticates by username/password and returns a fully-formed session.
    func authenticate(username: String, password: String) async throws -> UserSession {
        let payload = ["Username": username, "Pw": password]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/Users/AuthenticateByName", method: "POST", body: body)
        let data = try await perform(request)
        guard let result = try? decoder.decode(AuthenticationResult.self, from: data) else {
            throw APIError.decoding
        }
        accessToken = result.accessToken
        return UserSession(
            server: server,
            userID: result.user.id,
            username: result.user.name,
            accessToken: result.accessToken
        )
    }

    // MARK: - Quick Connect

    /// Starts a Quick Connect attempt: the server hands back a short code the
    /// user enters in any signed-in Jellyfin app to approve this device.
    /// (10.9+ expects POST; 10.8 used GET — try both so any server works.)
    func quickConnectInitiate() async throws -> QuickConnectResult {
        if let request = try? makeRequest(path: "/QuickConnect/Initiate", method: "POST"),
           let data = try? await perform(request),
           let result = try? decoder.decode(QuickConnectResult.self, from: data) {
            return result
        }
        return try await get(QuickConnectResult.self, path: "/QuickConnect/Initiate")
    }

    /// Polls whether the code has been approved yet.
    func quickConnectState(secret: String) async throws -> QuickConnectResult {
        try await get(QuickConnectResult.self, path: "/QuickConnect/Connect",
                      query: [.init(name: "secret", value: secret)])
    }

    /// Exchanges an approved Quick Connect secret for a signed-in session.
    func authenticateWithQuickConnect(secret: String) async throws -> UserSession {
        let body = try JSONSerialization.data(withJSONObject: ["Secret": secret])
        let request = try makeRequest(path: "/Users/AuthenticateWithQuickConnect", method: "POST", body: body)
        let data = try await perform(request)
        guard let result = try? decoder.decode(AuthenticationResult.self, from: data) else {
            throw APIError.decoding
        }
        accessToken = result.accessToken
        return UserSession(
            server: server,
            userID: result.user.id,
            username: result.user.name,
            accessToken: result.accessToken
        )
    }

    /// Cheap call used on launch to confirm a restored token is still valid.
    func validateSession() async -> Bool {
        do {
            _ = try await get(PublicSystemInfo.self, path: "/System/Info")
            return true
        } catch {
            return false
        }
    }

    /// Fast launch reachability + auth check. Throws `.unauthorized` when the
    /// token is rejected (server reachable but session expired), or a network
    /// error when the server can't be reached (offline / address changed). Uses
    /// a short timeout so a dead address doesn't hang the splash screen.
    func checkConnection() async throws {
        var request = try makeRequest(path: "/System/Info")
        request.timeoutInterval = 8
        _ = try await perform(request)
    }

    func reportSessionEnded() async {
        guard let request = try? makeRequest(path: "/Sessions/Logout", method: "POST") else { return }
        _ = try? await perform(request)
    }

    // MARK: - Users & profiles

    /// Every account on the server. `/Users` needs admin rights; everyone else
    /// falls back to the server's public login list (accounts the server shows
    /// on its own login screen).
    func serverUsers() async throws -> [ServerUser] {
        if let all = try? await get([ServerUser].self, path: "/Users"), !all.isEmpty {
            return all
        }
        return try await get([ServerUser].self, path: "/Users/Public")
    }

    /// The full record for one user — used for the admin check and avatar tag.
    func userDetail(userID: String) async -> ServerUser? {
        try? await get(ServerUser.self, path: "/Users/\(userID)")
    }

    /// Strict, user-scoped token check — throws `.unauthorized` when this token
    /// can no longer act as `userID`. (Jellyfin revokes a device's previous
    /// token when the same device signs in as another user, and `/System/Info`
    /// alone doesn't always catch that.)
    func requireUserAccess(userID: String) async throws {
        _ = try await get(ServerUser.self, path: "/Users/\(userID)")
    }

    /// A user's profile image. Served without auth (the server login screen
    /// shows these pre-auth), so it's safe for the shared image loader.
    nonisolated func userImageURL(userID: String, tag: String? = nil, maxWidth: Int = 300) -> URL? {
        guard var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path += "/Users/\(userID)/Images/Primary"
        var query: [URLQueryItem] = [
            .init(name: "maxWidth", value: String(maxWidth)),
            .init(name: "quality", value: "90")
        ]
        if let tag { query.append(.init(name: "tag", value: tag)) }
        components.queryItems = query
        return components.url
    }

    // MARK: - Libraries & items

    /// Top-level libraries ("Views") for the signed-in user.
    func userViews(userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/UserViews", query: [.init(name: "userId", value: userID)]).items
    }

    /// "Continue Watching" resume items.
    func resumeItems(userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items/Resume", query: [
            .init(name: "limit", value: "20"),
            .init(name: "mediaTypes", value: "Video"),
            .init(name: "fields", value: "Overview,Genres,CriticRating")
        ]).items
    }

    /// Recently added across the user's libraries, or within one library when
    /// `parentID` is given.
    func latestItems(userID: String, parentID: String? = nil) async throws -> [MediaItem] {
        var query: [URLQueryItem] = [
            .init(name: "limit", value: "24"),
            .init(name: "fields", value: "Overview,Genres,CriticRating")
        ]
        if let parentID { query.append(.init(name: "parentId", value: parentID)) }
        return try await get([MediaItem].self, path: "/Users/\(userID)/Items/Latest", query: query)
    }

    /// Children of a library or container (movies in a library, episodes in a season, …).
    func items(in parentID: String, userID: String,
               sortBy: String = "SortName", sortOrder: String = "Ascending") async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "parentId", value: parentID),
            .init(name: "sortBy", value: sortBy),
            .init(name: "sortOrder", value: sortOrder),
            .init(name: "fields", value: "Overview,Genres,CriticRating,PrimaryImageAspectRatio")
        ]).items
    }

    func itemDetail(_ itemID: String, userID: String) async throws -> MediaItem {
        try await get(MediaItem.self, path: "/Users/\(userID)/Items/\(itemID)")
    }

    /// Fetches the full item for the player (logo art, parent logo) plus its
    /// Trickplay scrubber-preview sprites (highest resolution; nil when the
    /// server hasn't generated trickplay for it).
    func playbackDetail(itemID: String, userID: String) async -> (item: MediaItem, trickplay: TrickplaySource?)? {
        guard let item = try? await get(MediaItem.self, path: "/Users/\(userID)/Items/\(itemID)",
                                        query: [.init(name: "fields", value: "Trickplay")]) else { return nil }
        var source: TrickplaySource?
        // Sort media-source keys so the same source is picked every time —
        // Dictionary.values.first is order-undefined across runs.
        if let bySource = item.trickplay, let byWidth = bySource.min(by: { $0.key < $1.key })?.value,
           let best = byWidth.max(by: { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }),
           let width = Int(best.key) {
            source = TrickplaySource(itemID: itemID, width: width, info: best.value,
                                     baseURL: server.baseURL, token: accessToken)
        }
        return (item, source)
    }

    // MARK: - Series (seasons / episodes / next up)

    /// Seasons of a series, ordered.
    func seasons(seriesID: String, userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Shows/\(seriesID)/Seasons", query: [
            .init(name: "userId", value: userID),
            .init(name: "fields", value: "Overview,Genres,CriticRating")
        ]).items
    }

    /// Episodes in a season of a series, ordered.
    func episodes(seriesID: String, seasonID: String, userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Shows/\(seriesID)/Episodes", query: [
            .init(name: "seasonId", value: seasonID),
            .init(name: "userId", value: userID),
            .init(name: "fields", value: "Overview,Genres,CriticRating")
        ]).items
    }

    /// The next episode the user should watch for a series (resume or unwatched).
    func nextUp(seriesID: String, userID: String) async throws -> MediaItem? {
        try await get(ItemsResponse.self, path: "/Shows/NextUp", query: [
            .init(name: "seriesId", value: seriesID),
            .init(name: "userId", value: userID),
            .init(name: "fields", value: "Overview,Genres,CriticRating")
        ]).items.first
    }

    // MARK: - Home rails

    /// "Coming Up" — next episodes across all the user's shows.
    func nextUp(userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Shows/NextUp", query: [
            .init(name: "userId", value: userID),
            .init(name: "limit", value: "24"),
            .init(name: "fields", value: "Overview,Genres,CriticRating")
        ]).items
    }

    /// A fresh random spread of movies/shows from across the whole library, with
    /// backdrops — used to shuffle the media bar each launch.
    func randomItems(userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "recursive", value: "true"),
            .init(name: "includeItemTypes", value: "Movie,Series"),
            .init(name: "sortBy", value: "Random"),
            .init(name: "limit", value: "40"),
            .init(name: "imageTypeLimit", value: "1"),
            .init(name: "imageTypes", value: "Backdrop"),
            .init(name: "fields", value: "Overview,Genres,CriticRating")
        ]).items
    }

    /// "Hidden Gems" — unwatched movies/shows with the highest community rating.
    func hiddenGems(userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "recursive", value: "true"),
            .init(name: "includeItemTypes", value: "Movie,Series"),
            .init(name: "filters", value: "IsUnplayed"),
            .init(name: "sortBy", value: "CommunityRating"),
            .init(name: "sortOrder", value: "Descending"),
            .init(name: "limit", value: "24"),
            .init(name: "imageTypeLimit", value: "1"),
            .init(name: "fields", value: "Overview,Genres,CriticRating")
        ]).items
    }

    /// Full-library search across movies, shows and episodes.
    func search(query: String, userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "searchTerm", value: query),
            .init(name: "recursive", value: "true"),
            .init(name: "includeItemTypes", value: "Movie,Series,Episode"),
            .init(name: "limit", value: "60"),
            .init(name: "imageTypeLimit", value: "1"),
            .init(name: "fields", value: "Overview,Genres,CriticRating,PrimaryImageAspectRatio")
        ]).items
    }

    /// Recently added items of a specific type, e.g. `Series`.
    func latestItems(userID: String, includeItemTypes: String) async throws -> [MediaItem] {
        try await get([MediaItem].self, path: "/Users/\(userID)/Items/Latest", query: [
            .init(name: "limit", value: "24"),
            .init(name: "includeItemTypes", value: includeItemTypes),
            .init(name: "fields", value: "Overview,Genres,CriticRating")
        ])
    }

    /// Favorited movies and shows.
    func favorites(userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "filters", value: "IsFavorite"),
            .init(name: "recursive", value: "true"),
            .init(name: "includeItemTypes", value: "Movie,Series"),
            .init(name: "sortBy", value: "SortName"),
            .init(name: "limit", value: "24"),
            .init(name: "fields", value: "Overview,Genres,CriticRating")
        ]).items
    }

    /// Toggle an item's favorite ("My List") status.
    @discardableResult
    func setFavorite(itemID: String, userID: String, isFavorite: Bool) async -> Bool {
        let method = isFavorite ? "POST" : "DELETE"
        guard let request = try? makeRequest(path: "/Users/\(userID)/FavoriteItems/\(itemID)", method: method) else {
            return false
        }
        return (try? await perform(request)) != nil
    }

    /// Toggle an item's watched/played status.
    @discardableResult
    func setPlayed(itemID: String, userID: String, isPlayed: Bool) async -> Bool {
        let method = isPlayed ? "POST" : "DELETE"
        guard let request = try? makeRequest(path: "/Users/\(userID)/PlayedItems/\(itemID)", method: method) else {
            return false
        }
        return (try? await perform(request)) != nil
    }

    /// "More Like This" — items similar to the given one.
    func similarItems(itemID: String, userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Items/\(itemID)/Similar", query: [
            .init(name: "userId", value: userID),
            .init(name: "limit", value: "12"),
            .init(name: "fields", value: "Overview,Genres,CriticRating")
        ]).items
    }

    /// Intro/outro segments for an item (from the Intro Skipper plugin / Media
    /// Segments API). Returns empty when unavailable so the UI degrades cleanly.
    func mediaSegments(itemID: String) async -> [MediaSegment] {
        // Core media segments first (Jellyfin 10.9+ / segment-provider plugins)…
        if let request = try? makeRequest(path: "/MediaSegments/\(itemID)"),
           let data = try? await perform(request),
           let result = try? decoder.decode(MediaSegmentsResponse.self, from: data),
           !result.items.isEmpty {
            return result.items.map { seg in
                let kind: MediaSegment.Kind = seg.type == "Intro" ? .intro
                    : (seg.type == "Outro" ? .outro : .other)
                return MediaSegment(kind: kind,
                                    start: Double(seg.startTicks) / 10_000_000,
                                    end: Double(seg.endTicks) / 10_000_000)
            }
        }
        // …falling back to the Intro Skipper plugin's own endpoints, so servers
        // running the plugin (rather than core segments) still get Skip Intro /
        // Skip Credits.
        return await introSkipperSegments(itemID: itemID)
    }

    /// Segments from the Intro Skipper plugin: the modern combined endpoint,
    /// then the legacy intro-only one. Empty when the plugin isn't installed.
    private func introSkipperSegments(itemID: String) async -> [MediaSegment] {
        if let request = try? makeRequest(path: "/Episode/\(itemID)/IntroSkipperSegments"),
           let data = try? await perform(request),
           let result = try? decoder.decode(IntroSkipperSegments.self, from: data) {
            var out: [MediaSegment] = []
            if let intro = result.introduction, intro.valid != false,
               let start = intro.introStart, let end = intro.introEnd, end > start {
                out.append(MediaSegment(kind: .intro, start: start, end: end))
            }
            if let credits = result.credits, credits.valid != false,
               let start = credits.introStart, let end = credits.introEnd, end > start {
                out.append(MediaSegment(kind: .outro, start: start, end: end))
            }
            if !out.isEmpty { return out }
        }
        if let request = try? makeRequest(path: "/Episode/\(itemID)/IntroTimestamps/v1"),
           let data = try? await perform(request),
           let seg = try? decoder.decode(IntroSkipperSegment.self, from: data),
           seg.valid != false, let start = seg.introStart, let end = seg.introEnd, end > start {
            return [MediaSegment(kind: .intro, start: start, end: end)]
        }
        return []
    }

    /// Plugins installed on the server (`/Plugins` is admin-only; everyone else
    /// gets an empty list).
    func installedPlugins() async -> [InstalledPlugin] {
        (try? await get([InstalledPlugin].self, path: "/Plugins")) ?? []
    }

    // MARK: - Theater mode & theme music

    /// Direct stream URL for the muted theater preview — no PlaybackInfo round
    /// trip and never a transcode (browsing must not spin up server encodes).
    /// Containers AVPlayer can't direct-play simply fail to render and the
    /// static art remains, which is the right fallback.
    func previewStreamURL(itemID: String) async -> URL? {
        guard let token = accessToken,
              var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path += "/Videos/\(itemID)/stream"
        components.queryItems = [
            .init(name: "static", value: "true"),
            .init(name: "api_key", value: token)
        ]
        return components.url
    }

    /// The item's theme song (Jellyfin's theme.mp3 support), if the server has
    /// one — inherited from the series for episodes.
    func themeSongURL(itemID: String) async -> URL? {
        struct ThemeMedia: Decodable {
            struct Entry: Decodable {
                let id: String
                enum CodingKeys: String, CodingKey { case id = "Id" }
            }
            let items: [Entry]?
            enum CodingKeys: String, CodingKey { case items = "Items" }
        }
        guard let result = try? await get(ThemeMedia.self, path: "/Items/\(itemID)/ThemeSongs",
                                          query: [.init(name: "inheritFromParent", value: "true")]),
              let theme = result.items?.first,
              let token = accessToken,
              var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path += "/Audio/\(theme.id)/stream"
        components.queryItems = [
            .init(name: "static", value: "true"),
            .init(name: "api_key", value: token)
        ]
        return components.url
    }


    // MARK: - Music

    /// Newest albums for the Music home.
    func recentAlbums(userID: String) async throws -> [MediaItem] {
        try await get([MediaItem].self, path: "/Users/\(userID)/Items/Latest", query: [
            .init(name: "limit", value: "24"),
            .init(name: "includeItemTypes", value: "MusicAlbum"),
            // ChildCount is what separates a single or EP from a real album.
            .init(name: "fields", value: "ChildCount")
        ])
    }

    /// The whole album library, A–Z.
    func allAlbums(userID: String, limit: Int = 300) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "IncludeItemTypes", value: "MusicAlbum"),
            .init(name: "Recursive", value: "true"),
            .init(name: "SortBy", value: "SortName"),
            .init(name: "Fields", value: "ChildCount"),
            .init(name: "Limit", value: String(limit))
        ]).items
    }

    /// Album artists, A–Z.
    func artists(userID: String, limit: Int = 200) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Artists/AlbumArtists", query: [
            .init(name: "userId", value: userID),
            .init(name: "SortBy", value: "SortName"),
            .init(name: "Limit", value: String(limit))
        ]).items
    }

    /// The user's playlists.
    func playlists(userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "IncludeItemTypes", value: "Playlist"),
            .init(name: "Recursive", value: "true"),
            .init(name: "SortBy", value: "SortName")
        ]).items
    }

    /// An album's tracks in disc/track order.
    func albumTracks(albumID: String, userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "ParentId", value: albumID),
            .init(name: "IncludeItemTypes", value: "Audio"),
            .init(name: "SortBy", value: "ParentIndexNumber,IndexNumber,SortName")
        ]).items
    }

    /// A playlist's tracks in playlist order.
    func playlistTracks(playlistID: String, userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Playlists/\(playlistID)/Items", query: [
            .init(name: "userId", value: userID)
        ]).items
    }

    /// An artist's albums, newest first.
    func artistAlbums(artistID: String, userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "IncludeItemTypes", value: "MusicAlbum"),
            .init(name: "Recursive", value: "true"),
            .init(name: "AlbumArtistIds", value: artistID),
            .init(name: "SortBy", value: "PremiereDate,ProductionYear,SortName"),
            .init(name: "SortOrder", value: "Descending"),
            .init(name: "Fields", value: "ChildCount")
        ]).items
    }

    /// A random pile of songs — "Shuffle Library".
    func randomSongs(userID: String, limit: Int = 100) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "IncludeItemTypes", value: "Audio"),
            .init(name: "Recursive", value: "true"),
            .init(name: "SortBy", value: "Random"),
            .init(name: "Limit", value: String(limit))
        ]).items
    }

    /// Songs the user has hearted — "Hearted Songs".
    func favoriteSongs(userID: String, limit: Int = 300) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "IncludeItemTypes", value: "Audio"),
            .init(name: "Recursive", value: "true"),
            .init(name: "Filters", value: "IsFavorite"),
            .init(name: "SortBy", value: "SortName"),
            .init(name: "Limit", value: String(limit))
        ]).items
    }

    /// Most-played songs — the "On Repeat" mix.
    func mostPlayedSongs(userID: String, limit: Int = 100) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "IncludeItemTypes", value: "Audio"),
            .init(name: "Recursive", value: "true"),
            .init(name: "Filters", value: "IsPlayed"),
            .init(name: "SortBy", value: "PlayCount"),
            .init(name: "SortOrder", value: "Descending"),
            .init(name: "Limit", value: String(limit))
        ]).items
    }

    /// Recently-played songs, newest play first.
    func recentlyPlayedSongs(userID: String, limit: Int = 100) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "IncludeItemTypes", value: "Audio"),
            .init(name: "Recursive", value: "true"),
            .init(name: "Filters", value: "IsPlayed"),
            .init(name: "SortBy", value: "DatePlayed"),
            .init(name: "SortOrder", value: "Descending"),
            .init(name: "Limit", value: String(limit))
        ]).items
    }

    /// Never-played songs, shuffled — the "Discovery" mix of gems you haven't
    /// heard yet.
    func discoverySongs(userID: String, limit: Int = 100) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "IncludeItemTypes", value: "Audio"),
            .init(name: "Recursive", value: "true"),
            .init(name: "Filters", value: "IsUnplayed"),
            .init(name: "SortBy", value: "Random"),
            .init(name: "Limit", value: String(limit))
        ]).items
    }

    /// Every song in the library, for "download everything" and library sync.
    func allSongs(userID: String, limit: Int = 5000) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "IncludeItemTypes", value: "Audio"),
            .init(name: "Recursive", value: "true"),
            .init(name: "SortBy", value: "AlbumArtist,Album,ParentIndexNumber,IndexNumber"),
            .init(name: "Limit", value: String(limit))
        ]).items
    }

    /// Music-only search: albums, artists and songs (the media search above is
    /// scoped to movies/shows, so music mode needs its own).
    func searchMusic(query: String, userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "searchTerm", value: query),
            .init(name: "recursive", value: "true"),
            .init(name: "includeItemTypes", value: "MusicAlbum,MusicArtist,Audio"),
            .init(name: "limit", value: "60"),
            .init(name: "imageTypeLimit", value: "1"),
            .init(name: "fields", value: "ChildCount")
        ]).items
    }

    /// A large sample of songs carrying play counts + genres, used to compute
    /// the listening insights and Music Identity locally.
    func songsForInsights(userID: String, limit: Int = 2000) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "IncludeItemTypes", value: "Audio"),
            .init(name: "Recursive", value: "true"),
            .init(name: "Filters", value: "IsPlayed"),
            .init(name: "SortBy", value: "PlayCount"),
            .init(name: "SortOrder", value: "Descending"),
            .init(name: "Fields", value: "Genres"),
            .init(name: "Limit", value: String(limit))
        ]).items
    }

    /// Synced lyrics for a song (Jellyfin 10.9+ / the LrcLib plugin). Empty when
    /// the server has none.
    func lyrics(itemID: String) async -> [LyricLine] {
        struct Response: Decodable {
            struct Line: Decodable {
                let text: String
                let start: Int64?
                enum CodingKeys: String, CodingKey { case text = "Text", start = "Start" }
            }
            let lyrics: [Line]?
            enum CodingKeys: String, CodingKey { case lyrics = "Lyrics" }
        }
        guard let response = try? await get(Response.self, path: "/Audio/\(itemID)/Lyrics") else { return [] }
        return (response.lyrics ?? []).enumerated().map { index, line in
            LyricLine(id: index, text: line.text,
                      start: line.start.map { Double($0) / 10_000_000 })
        }
    }

    /// Stream URL for a song via the universal endpoint: direct-plays common
    /// containers and transparently transcodes anything exotic to AAC.
    func audioStreamURL(itemID: String, userID: String) async -> URL? {
        guard let token = accessToken,
              var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path += "/Audio/\(itemID)/universal"
        components.queryItems = [
            .init(name: "UserId", value: userID),
            .init(name: "DeviceId", value: deviceID),
            .init(name: "api_key", value: token),
            .init(name: "Container", value: "mp3,aac,m4a|aac,m4b|aac,flac,alac,m4a|alac,m4b|alac,wav,ogg"),
            .init(name: "TranscodingContainer", value: "aac"),
            .init(name: "TranscodingProtocol", value: "hls"),
            .init(name: "AudioCodec", value: "aac")
        ]
        return components.url
    }

    // MARK: - Admin dashboard tools

    /// Full server details (admin-scoped `/System/Info`).
    func systemInfo() async -> ServerSystemInfo? {
        try? await get(ServerSystemInfo.self, path: "/System/Info")
    }

    /// Kicks off a scan of every library — the dashboard's "Scan All Libraries".
    /// Returns whether the server accepted the request.
    func refreshAllLibraries() async -> Bool {
        guard let request = try? makeRequest(path: "/Library/Refresh", method: "POST") else { return false }
        return (try? await perform(request)) != nil
    }

    /// Restarts the Jellyfin server process (admin). Every stream drops while
    /// it comes back — callers must confirm with the user first.
    func restartServer() async -> Bool {
        guard let request = try? makeRequest(path: "/System/Restart", method: "POST") else { return false }
        return (try? await perform(request)) != nil
    }

    /// Sessions connected to the server within the last few minutes (admin) —
    /// who's streaming what, right now.
    func activeSessions() async -> [ActiveSession] {
        (try? await get([ActiveSession].self, path: "/Sessions",
                        query: [.init(name: "activeWithinSeconds", value: "960")])) ?? []
    }

    /// The dashboard's recent-activity feed (logins, playback, scans…).
    func recentActivity(limit: Int = 12) async -> [ActivityEntry] {
        let response = try? await get(ActivityLogResponse.self, path: "/System/ActivityLog/Entries",
                                      query: [.init(name: "limit", value: String(limit))])
        return response?.items ?? []
    }

    // MARK: - Images & streaming URLs

    /// Builds a primary/backdrop image URL with an optional pixel width so the
    /// server can downscale and the grid never decodes oversized art.
    nonisolated func imageURL(itemID: String, kind: ImageKind = .primary, tag: String? = nil, maxWidth: Int? = nil) -> URL? {
        guard var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path += "/Items/\(itemID)/Images/\(kind.rawValue)"
        var query: [URLQueryItem] = []
        if let tag { query.append(.init(name: "tag", value: tag)) }
        if let maxWidth { query.append(.init(name: "maxWidth", value: String(maxWidth))) }
        query.append(.init(name: "quality", value: "90"))
        components.queryItems = query
        return components.url
    }

    enum ImageKind: String { case primary = "Primary", backdrop = "Backdrop", thumb = "Thumb", logo = "Logo" }

    /// Resolves the best playback URL for an item, deciding direct-play vs.
    /// transcode. AVFoundation handles direct-play/HLS; the rest falls to VLCKit.
    /// Passing `maxBitrate` forces an HLS transcode capped at that bitrate (used
    /// by the in-player Quality selector); `nil` means automatic.
    func resolvePlayback(for item: MediaItem, userID: String, maxBitrate: Int? = nil) async throws -> PlaybackResolution {
        var infoQuery: [URLQueryItem] = [.init(name: "userId", value: userID)]
        if let maxBitrate { infoQuery.append(.init(name: "maxStreamingBitrate", value: String(maxBitrate))) }
        let info = try await get(PlaybackInfoResponse.self, path: "/Items/\(item.id)/PlaybackInfo", query: infoQuery)
        let source = info.mediaSources.first

        // Auto quality can direct-play; a chosen quality always transcodes.
        if maxBitrate == nil, let source, source.supportsDirectPlay == true, let token = accessToken {
            // Direct stream the original file.
            var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false)!
            components.path += "/Videos/\(item.id)/stream"
            components.queryItems = [
                .init(name: "static", value: "true"),
                .init(name: "mediaSourceId", value: source.id ?? item.id),
                .init(name: "api_key", value: token)
            ]
            return PlaybackResolution(
                streamURL: components.url!,
                isDirectPlay: AVPlaybackEngine.canDirectPlay(container: source.container),
                container: source.container,
                playSessionID: info.playSessionID
            )
        }

        // Fall back to an HLS transcode the server produces on demand.
        guard let token = accessToken else { throw APIError.unauthorized }
        var components = URLComponents(url: server.baseURL, resolvingAgainstBaseURL: false)!
        components.path += "/Videos/\(item.id)/master.m3u8"
        var query: [URLQueryItem] = [
            .init(name: "mediaSourceId", value: source?.id ?? item.id),
            .init(name: "api_key", value: token),
            .init(name: "playSessionId", value: info.playSessionID ?? UUID().uuidString)
        ]
        if let maxBitrate {
            query.append(.init(name: "maxStreamingBitrate", value: String(maxBitrate)))
            query.append(.init(name: "videoBitRate", value: String(maxBitrate)))
        }
        components.queryItems = query
        return PlaybackResolution(
            streamURL: components.url!,
            isDirectPlay: false, // HLS — AVPlayer handles this well
            container: "hls",
            playSessionID: info.playSessionID
        )
    }

    // MARK: - Playback progress reporting

    func reportPlaybackProgress(itemID: String, positionTicks: Int64, isPaused: Bool, playSessionID: String?) async {
        let payload: [String: Any] = [
            "ItemId": itemID,
            "PositionTicks": positionTicks,
            "IsPaused": isPaused,
            "PlaySessionId": playSessionID ?? ""
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let request = try? makeRequest(path: "/Sessions/Playing/Progress", method: "POST", body: body)
        else { return }
        _ = try? await perform(request)
    }

    /// Registers the play session with the server when playback begins, so the
    /// progress/stop reports that follow are treated as authoritative.
    func reportPlaybackStarted(itemID: String, positionTicks: Int64, playSessionID: String?) async {
        let payload: [String: Any] = [
            "ItemId": itemID,
            "PositionTicks": positionTicks,
            "PlaySessionId": playSessionID ?? "",
            "CanSeek": true
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let request = try? makeRequest(path: "/Sessions/Playing", method: "POST", body: body)
        else { return }
        _ = try? await perform(request)
    }

    /// The definitive "user left playback here" report — Jellyfin persists the
    /// resume position from this immediately (a paused progress post doesn't
    /// carry the same weight).
    func reportPlaybackStopped(itemID: String, positionTicks: Int64, playSessionID: String?) async {
        let payload: [String: Any] = [
            "ItemId": itemID,
            "PositionTicks": positionTicks,
            "PlaySessionId": playSessionID ?? ""
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let request = try? makeRequest(path: "/Sessions/Playing/Stopped", method: "POST", body: body)
        else { return }
        _ = try? await perform(request)
    }
}
