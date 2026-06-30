import Foundation
import UIKit

// MARK: - Models

/// Denormalized run stats captured on a post at publish time (mirrors the
/// backend `stats_snapshot` jsonb). All optional — older/edited posts may omit.
struct PostStats: Codable, Equatable {
    let distance: Double?
    let pace: Double?       // seconds per mile
    let duration: Double?   // seconds
    let streak: Int?
    let date: String?
}

/// A social post — a photo (run-stats overlay already baked in) plus optional
/// caption and stats. Surfaces in the Feed and/or as a Story. Field names are
/// snake_case to decode the backend JSON directly, matching FeedWorkoutItem.
struct PostItem: Codable, Identifiable {
    let post_id: String
    let user_id: String
    let username: String?
    let first_name: String?
    let last_name: String?
    let profile_image_url: String?
    let media_url: String
    let caption: String?
    let workout_id: String?
    let stats_snapshot: PostStats?
    let local_date: String?
    let share_to_feed: Bool?
    let share_to_story: Bool?
    let story_expires_at: String?
    let created_at: String
    let is_self: Bool
    var is_hyped: Bool
    var hype_count: Int?
    var is_viewed: Bool?

    var id: String { post_id }

    var displayName: String {
        if let username, !username.isEmpty { return username }
        if let first_name, !first_name.isEmpty { return first_name }
        return "Someone"
    }

    var mediaURL: URL? { ProfileImageService.fullImageURL(for: media_url) }

    /// Short "2h", "5m", "now" relative time from created_at.
    var relativeTime: String { RelativeTime.short(from: created_at) }
}

/// One author's worth of active stories in the rail (lazy-loaded on tap).
struct StoryGroup: Codable, Identifiable {
    let user_id: String
    let username: String?
    let first_name: String?
    let last_name: String?
    let profile_image_url: String?
    let story_count: Int
    let has_unviewed: Bool
    let latest_at: String

    var id: String { user_id }

    var displayName: String {
        if let username, !username.isEmpty { return username }
        if let first_name, !first_name.isEmpty { return first_name }
        return "Someone"
    }
}

struct FeedResponse: Decodable {
    let items: [PostItem]
    let next_before: String?
}

/// Generic `{ ok: true }` / `{ accepted: ... }` acknowledgements.
private struct OKResponse: Decodable {
    let ok: Bool?
}

struct TermsStatus: Decodable {
    let accepted: Bool
    var accepted_at: String?
}

enum PostError: LocalizedError {
    case invalidURL
    case compressionFailed
    case notAuthenticated
    case uploadFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .compressionFailed: return "Couldn't prepare that photo"
        case .notAuthenticated: return "You're signed out"
        case .uploadFailed(let code): return "Upload failed (\(code))"
        }
    }
}

// MARK: - Service

/// Stateless API surface for stories + the social feed. JSON calls go through
/// APIClient.fancyFetch (auto token refresh); the photo upload hand-rolls
/// multipart like ProfileImageService.
enum PostService {
    /// Upload a flattened post photo (overlay already composited). Returns the
    /// server `media_url` to reference when creating the post.
    static func uploadMedia(_ image: UIImage) async throws -> String {
        guard let url = URL(string: "\(AppConfig.baseURL)/posts/media") else {
            throw PostError.invalidURL
        }
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            throw PostError.compressionFailed
        }
        guard let accessToken = TokenStore.accessToken else {
            throw PostError.notAuthenticated
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"post.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PostError.uploadFailed(0) }
        guard http.statusCode == 200 else { throw PostError.uploadFailed(http.statusCode) }

        struct MediaResponse: Decodable { let media_url: String }
        return try JSONDecoder().decode(MediaResponse.self, from: data).media_url
    }

    /// Create a post from an already-uploaded media_url. Throws APIError.apiError
    /// with code "mile_not_completed" / "terms_not_accepted" when gated.
    static func createPost(
        mediaUrl: String,
        caption: String?,
        workoutId: String?,
        shareToFeed: Bool,
        shareToStory: Bool,
        stats: PostStats?
    ) async throws -> PostItem {
        struct Body: Encodable {
            let media_url: String
            let caption: String?
            let workout_id: String?
            let share_to_feed: Bool
            let share_to_story: Bool
            let stats_snapshot: PostStats?
        }
        let bodyData = try JSONEncoder().encode(
            Body(
                media_url: mediaUrl,
                caption: caption,
                workout_id: workoutId,
                share_to_feed: shareToFeed,
                share_to_story: shareToStory,
                stats_snapshot: stats
            )
        )
        return try await APIClient.fancyFetch(
            endpoint: "/posts",
            method: .POST,
            body: bodyData,
            responseType: PostItem.self
        )
    }

    static func fetchStoriesRail() async throws -> [StoryGroup] {
        try await APIClient.fancyFetch(endpoint: "/posts/stories", responseType: [StoryGroup].self)
    }

    static func fetchUserStories(userId: String) async throws -> [PostItem] {
        try await APIClient.fancyFetch(endpoint: "/posts/stories/\(userId)", responseType: [PostItem].self)
    }

    static func markStoryViewed(postId: String) async throws {
        _ = try await APIClient.fancyFetch(
            endpoint: "/posts/stories/\(postId)/view",
            method: .POST,
            responseType: OKResponse.self
        )
    }

    /// One page of the feed. Pass the previous page's `next_before` to paginate.
    static func fetchFeed(before: String? = nil) async throws -> FeedResponse {
        var endpoint = "/posts/feed?limit=20"
        if let before, let encoded = before.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            endpoint += "&before=\(encoded)"
        }
        return try await APIClient.fancyFetch(endpoint: endpoint, responseType: FeedResponse.self)
    }

    static func deletePost(postId: String) async throws {
        _ = try await APIClient.fancyFetch(
            endpoint: "/posts/\(postId)",
            method: .DELETE,
            responseType: OKResponse.self
        )
    }

    static func reportPost(postId: String, reason: String, details: String?) async throws {
        struct Body: Encodable {
            let reason: String
            let details: String?
        }
        let bodyData = try JSONEncoder().encode(Body(reason: reason, details: details))
        _ = try await APIClient.fancyFetch(
            endpoint: "/posts/\(postId)/report",
            method: .POST,
            body: bodyData,
            responseType: OKResponse.self
        )
    }

    static func termsStatus() async throws -> TermsStatus {
        try await APIClient.fancyFetch(endpoint: "/posts/terms", responseType: TermsStatus.self)
    }

    @discardableResult
    static func acceptTerms() async throws -> TermsStatus {
        try await APIClient.fancyFetch(
            endpoint: "/posts/terms/accept",
            method: .POST,
            responseType: TermsStatus.self
        )
    }
}

/// Blocking is broader than posts (it tears down friendship too), so it lives
/// in its own small service hitting /blocks.
enum BlockService {
    private struct OK: Decodable { let ok: Bool? }

    static func block(userId: String) async throws {
        _ = try await APIClient.fancyFetch(endpoint: "/blocks/\(userId)", method: .POST, responseType: OK.self)
    }

    static func unblock(userId: String) async throws {
        _ = try await APIClient.fancyFetch(endpoint: "/blocks/\(userId)", method: .DELETE, responseType: OK.self)
    }
}

// MARK: - Relative time helper

enum RelativeTime {
    private static let parser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let parserNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from iso: String) -> Date? {
        parser.date(from: iso) ?? parserNoFrac.date(from: iso)
    }

    /// "now", "5m", "2h", "3d" — compact age for feed/story headers.
    static func short(from iso: String) -> String {
        guard let date = date(from: iso) else { return "" }
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }
}
