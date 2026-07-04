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

    /// Recent hypes the current user has RECEIVED (newest first), with sender
    /// info — powers the "you got hyped" surface on the profile.
    static func received() async throws -> [ReceivedHype] {
        return try await APIClient.fancyFetch(
            endpoint: "/hype/received",
            responseType: [ReceivedHype].self
        )
    }

    /// Everyone who hyped one specific post or daily mile, newest first — the
    /// Instagram-style "who liked this" list behind a feed card's hype tally.
    /// `contextId` is the post id for posts, or the workout id for miles (the
    /// backend resolves it to the canonical composite key).
    static func hypers(
        contextType: String,
        contextId: String,
        targetUserId: String
    ) async throws -> [Hyper] {
        struct HypersResponse: Decodable {
            let hypers: [Hyper]
            let count: Int
        }
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "context_type", value: contextType),
            URLQueryItem(name: "context_id", value: contextId),
            URLQueryItem(name: "target_user_id", value: targetUserId)
        ]
        let query = components.percentEncodedQuery ?? ""
        return try await APIClient.fancyFetch(
            endpoint: "/hype/hypers?\(query)",
            responseType: HypersResponse.self
        ).hypers
    }
}

/// One person who hyped a post/mile, for the "who hyped this" list.
struct Hyper: Decodable, Identifiable {
    let user_id: String
    let username: String?
    let first_name: String?
    let last_name: String?
    let profile_image_url: String?
    let created_at: String

    var id: String { user_id }

    var displayName: String {
        if let username, !username.isEmpty { return username }
        if let first_name, !first_name.isEmpty { return first_name }
        return "Someone"
    }

    var relativeTime: String { RelativeTime.short(from: created_at) }
}

/// A hype someone sent to the current user.
struct ReceivedHype: Decodable, Identifiable {
    let sender_id: String
    let username: String?
    let first_name: String?
    let last_name: String?
    let profile_image_url: String?
    let context_type: String?
    let context_label: String?
    let created_at: String

    var id: String { "\(sender_id)-\(created_at)" }

    var displayName: String {
        if let username = username, !username.isEmpty { return username }
        if let first_name = first_name { return first_name }
        return "Someone"
    }

    /// "hyped your daily mile" / "hyped you earning 'X'" style phrase.
    var actionText: String {
        switch context_type {
        case "mile": return "hyped your daily mile"
        case "badge": return "hyped you earning '\(context_label ?? "a badge")'"
        case "pr": return "hyped your \(context_label ?? "personal best")"
        case "challenge": return "hyped your '\(context_label ?? "challenge")' challenge"
        default: return "hyped your recent workout"
        }
    }
}
