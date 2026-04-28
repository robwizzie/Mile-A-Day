import Foundation

struct HypeResponse: Decodable {
    let message: String
    let hypes_remaining: Int
}

struct HypeStatusResponse: Decodable {
    let hypes_remaining: Int
    let resets_at: String?
}

/// Sends and queries hype state. Stateless; safe to call from anywhere
/// including the notification action handler.
enum HypeService {
    static func sendHype(targetUserId: String) async throws -> HypeResponse {
        struct Body: Encodable { let target_user_id: String }
        let bodyData = try JSONEncoder().encode(Body(target_user_id: targetUserId))

        return try await APIClient.fancyFetch(
            endpoint: "/hype",
            method: .POST,
            body: bodyData,
            responseType: HypeResponse.self
        )
    }

    static func status() async throws -> HypeStatusResponse {
        return try await APIClient.fancyFetch(
            endpoint: "/hype/status",
            responseType: HypeStatusResponse.self
        )
    }
}
