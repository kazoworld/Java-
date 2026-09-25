import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A Jellyfin server found on the local network via UDP discovery.
struct DiscoveredServer: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// Base URL string the server advertises, e.g. `http://192.168.1.10:8096`.
    let address: String
}

/// Discovers Jellyfin servers on the LAN using the official discovery protocol:
/// broadcast `"Who is JellyfinServer?"` to UDP `255.255.255.255:7359` and
/// collect JSON replies (`{ Address, Id, Name }`).
///
/// On tvOS/iOS the first broadcast triggers the system Local Network permission
/// prompt (backed by `NSLocalNetworkUsageDescription`). If it's denied, this
/// simply returns an empty list and the user falls back to manual entry.
struct ServerDiscovery {
    private static let port: UInt16 = 7359
    private static let message = "Who is JellyfinServer?"

    func discover(timeout: TimeInterval = 2.5) async -> [DiscoveredServer] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.broadcastAndCollect(timeout: timeout))
            }
        }
    }

    private static func broadcastAndCollect(timeout: TimeInterval) -> [DiscoveredServer] {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var enable: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))

        // Short per-recv timeout so we can poll until the overall deadline.
        var tv = timeval(tv_sec: 0, tv_usec: 400_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = port.bigEndian
        dest.sin_addr.s_addr = inet_addr("255.255.255.255")

        let payload = Array(message.utf8)
        let sent = withUnsafePointer(to: &dest) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                payload.withUnsafeBytes { raw in
                    sendto(fd, raw.baseAddress, payload.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent >= 0 else { return [] }

        var found: [String: DiscoveredServer] = [:]
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 4096)

        while Date() < deadline {
            let n = recvfrom(fd, &buffer, buffer.count, 0, nil, nil)
            if n > 0, let server = parse(Data(bytes: buffer, count: n)) {
                found[server.id] = server
            }
            // n <= 0 means this poll timed out or errored; keep polling until the deadline.
        }
        return Array(found.values)
    }

    private static func parse(_ data: Data) -> DiscoveredServer? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // Jellyfin uses PascalCase; tolerate camelCase just in case.
        let address = (obj["Address"] ?? obj["address"]) as? String
        let id = (obj["Id"] ?? obj["id"]) as? String
        let name = ((obj["Name"] ?? obj["name"]) as? String) ?? "Jellyfin Server"
        guard let address, let id else { return nil }
        return DiscoveredServer(id: id, name: name, address: address)
    }
}
