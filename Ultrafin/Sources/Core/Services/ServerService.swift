import Foundation

/// Resolves a user-typed address into a verified `ServerConnection` by probing
/// the public system info endpoint, trying https → http and common schemes.
struct ServerService {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    /// Attempts to connect to `address`, returning a verified server or throwing.
    func connect(to address: String) async throws -> ServerConnection {
        let candidates = normalizedCandidates(for: address)
        guard !candidates.isEmpty else { throw APIError.invalidURL }

        var lastError: APIError = .unreachable
        for base in candidates {
            do {
                let info = try await fetchPublicInfo(base: base)
                return ServerConnection(
                    id: info.id ?? base.absoluteString,
                    name: info.serverName ?? base.host ?? "Jellyfin",
                    baseURL: base,
                    version: info.version
                )
            } catch let error as APIError {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    private func fetchPublicInfo(base: URL) async throws -> PublicSystemInfo {
        let url = base.appendingPathComponent("System/Info/Public")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw APIError.unreachable
            }
            guard let info = try? JSONDecoder().decode(PublicSystemInfo.self, from: data) else {
                throw APIError.decoding
            }
            return info
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.unreachable
        }
    }

    /// Expands "media.example.com" / "192.168.1.5:8096" into ordered URL
    /// candidates, preferring the scheme/port the user typed.
    private func normalizedCandidates(for raw: String) -> [URL] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var candidates: [URL] = []
        func add(_ string: String) {
            if let url = URL(string: string), url.host != nil, !candidates.contains(url) {
                candidates.append(url)
            }
        }

        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            add(trimmed)
        } else {
            // No scheme typed — prefer https, then http, then the default port.
            add("https://\(trimmed)")
            add("http://\(trimmed)")
            if !trimmed.contains(":") {
                add("http://\(trimmed):8096")
            }
        }
        return candidates
    }
}
