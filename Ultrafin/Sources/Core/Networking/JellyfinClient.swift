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
        if !query.isEmpty { components.queryItems = query }
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

    /// Cheap call used on launch to confirm a restored token is still valid.
    func validateSession() async -> Bool {
        do {
            _ = try await get(PublicSystemInfo.self, path: "/System/Info")
            return true
        } catch {
            return false
        }
    }

    func reportSessionEnded() async {
        guard let request = try? makeRequest(path: "/Sessions/Logout", method: "POST") else { return }
        _ = try? await perform(request)
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
            .init(name: "fields", value: "Overview,Genres")
        ]).items
    }

    /// Recently added across the user's libraries, or within one library when
    /// `parentID` is given.
    func latestItems(userID: String, parentID: String? = nil) async throws -> [MediaItem] {
        var query: [URLQueryItem] = [
            .init(name: "limit", value: "24"),
            .init(name: "fields", value: "Overview,Genres")
        ]
        if let parentID { query.append(.init(name: "parentId", value: parentID)) }
        return try await get([MediaItem].self, path: "/Users/\(userID)/Items/Latest", query: query)
    }

    /// Children of a library or container (movies in a library, episodes in a season, …).
    func items(in parentID: String, userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Users/\(userID)/Items", query: [
            .init(name: "parentId", value: parentID),
            .init(name: "sortBy", value: "SortName"),
            .init(name: "sortOrder", value: "Ascending"),
            .init(name: "fields", value: "Overview,Genres,PrimaryImageAspectRatio")
        ]).items
    }

    func itemDetail(_ itemID: String, userID: String) async throws -> MediaItem {
        try await get(MediaItem.self, path: "/Users/\(userID)/Items/\(itemID)")
    }

    // MARK: - Series (seasons / episodes / next up)

    /// Seasons of a series, ordered.
    func seasons(seriesID: String, userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Shows/\(seriesID)/Seasons", query: [
            .init(name: "userId", value: userID),
            .init(name: "fields", value: "Overview,Genres")
        ]).items
    }

    /// Episodes in a season of a series, ordered.
    func episodes(seriesID: String, seasonID: String, userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Shows/\(seriesID)/Episodes", query: [
            .init(name: "seasonId", value: seasonID),
            .init(name: "userId", value: userID),
            .init(name: "fields", value: "Overview,Genres")
        ]).items
    }

    /// The next episode the user should watch for a series (resume or unwatched).
    func nextUp(seriesID: String, userID: String) async throws -> MediaItem? {
        try await get(ItemsResponse.self, path: "/Shows/NextUp", query: [
            .init(name: "seriesId", value: seriesID),
            .init(name: "userId", value: userID),
            .init(name: "fields", value: "Overview,Genres")
        ]).items.first
    }

    // MARK: - Home rails

    /// "Coming Up" — next episodes across all the user's shows.
    func nextUp(userID: String) async throws -> [MediaItem] {
        try await get(ItemsResponse.self, path: "/Shows/NextUp", query: [
            .init(name: "userId", value: userID),
            .init(name: "limit", value: "24"),
            .init(name: "fields", value: "Overview,Genres")
        ]).items
    }

    /// Recently added items of a specific type, e.g. `Series`.
    func latestItems(userID: String, includeItemTypes: String) async throws -> [MediaItem] {
        try await get([MediaItem].self, path: "/Users/\(userID)/Items/Latest", query: [
            .init(name: "limit", value: "24"),
            .init(name: "includeItemTypes", value: includeItemTypes),
            .init(name: "fields", value: "Overview,Genres")
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
            .init(name: "fields", value: "Overview,Genres")
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
            .init(name: "fields", value: "Overview,Genres")
        ]).items
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
}
