import Foundation

/// Jellyfin Trickplay metadata for one resolution: thumbnails are packed into
/// sprite-sheet "tiles" of `tileWidth × tileHeight` images, one thumbnail every
/// `interval` ms.
struct TrickplayInfo: Codable, Hashable, Sendable {
    let width: Int
    let height: Int
    let tileWidth: Int
    let tileHeight: Int
    let thumbnailCount: Int
    let interval: Int // milliseconds between thumbnails

    enum CodingKeys: String, CodingKey {
        case width = "Width"
        case height = "Height"
        case tileWidth = "TileWidth"
        case tileHeight = "TileHeight"
        case thumbnailCount = "ThumbnailCount"
        case interval = "Interval"
    }
}

/// Everything needed to fetch a scrubber-preview thumbnail for a given time:
/// the trickplay layout plus the authenticated tile-image URL builder.
struct TrickplaySource: Sendable {
    let itemID: String
    let width: Int
    let info: TrickplayInfo
    let baseURL: URL
    let token: String?

    /// Thumbnail index for a playback time (clamped to the available range).
    func thumbnailIndex(for seconds: Double) -> Int {
        guard info.interval > 0 else { return 0 }
        let idx = Int(seconds * 1000 / Double(info.interval))
        return max(0, min(info.thumbnailCount - 1, idx))
    }

    private var perTile: Int { max(1, info.tileWidth * info.tileHeight) }

    /// The sprite-sheet tile image that contains the thumbnail for `seconds`.
    func tileURL(for seconds: Double) -> URL? {
        let tileIndex = thumbnailIndex(for: seconds) / perTile
        guard var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        c.path += "/Videos/\(itemID)/Trickplay/\(width)/\(tileIndex).jpg"
        if let token { c.queryItems = [URLQueryItem(name: "api_key", value: token)] }
        return c.url
    }

    /// Pixel rectangle of the thumbnail within its tile sprite.
    func cropRect(for seconds: Double) -> CGRect {
        let inTile = thumbnailIndex(for: seconds) % perTile
        let col = inTile % info.tileWidth
        let row = inTile / info.tileWidth
        return CGRect(x: col * info.width, y: row * info.height, width: info.width, height: info.height)
    }

    var aspect: CGFloat {
        info.height > 0 ? CGFloat(info.width) / CGFloat(info.height) : 16.0 / 9.0
    }
}
