import Foundation

struct HypeResponse: Decodable {
    let message: String
    let hypes_remaining: Int
}

struct HypeStatusResponse: Decodable {
    let hypes_remaining: Int
    let resets_at: String?
}

/// Optional context describing what was hyped. When provided, the backend uses
/// it to produce a contextual hype-back notification ("X hyped you earning 'Y'")
/// and dedupes by (sender, target, type, id) so the same event can't be re-hyped.
struct HypeContext {
    let contextType: String   // "mile" | "badge" | "pr" | "challenge"
    let contextId: String
    let contextLabel: String
}

/// Sends and queries hype state. Stateless; safe to call from anywhere
/// including the notification action handler.
enum HypeService {
    /// Mirrors `HYPE_DAILY_LIMIT` in backend/src/services/hypeService.ts.
    static let dailyLimit = 3

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

    /// Send a contextual hype tied to a specific event (mile / badge / pr / challenge).
    /// Maps APIError.conflict → silent "already hyped" state (caller should keep
    /// the button hidden). APIError.rateLimited propagates so the caller can
    /// surface "out of hypes for today".
    static func sendHype(targetUserId: String, context: HypeContext) async throws -> HypeResponse {
        struct Body: Encodable {
            let target_user_id: String
            let context_type: String
            let context_id: String
            let context_label: String
        }
        let bodyData = try JSONEncoder().encode(
            Body(
                target_user_id: targetUserId,
                context_type: context.contextType,
                context_id: context.contextId,
                context_label: context.contextLabel
            )
        )

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
