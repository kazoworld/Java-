import Foundation

/// Errors surfaced from the networking layer, mapped to friendly messages.
enum APIError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized
    case server(status: Int)
    case decoding
    case network(String)
    case unreachable

    var errorDescription: String? {
        switch self {
        case .invalidURL: "That doesn't look like a valid server address."
        case .unauthorized: "Your session expired. Please sign in again."
        case .server(let status): "The server returned an error (\(status))."
        case .decoding: "The server sent a response Ultrafin couldn't read."
        case .network(let message): message
        case .unreachable: "Couldn't reach the server. Check the address and your connection."
        }
    }
}
