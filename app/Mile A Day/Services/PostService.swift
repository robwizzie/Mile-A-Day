import Foundation
import UIKit
import CoreLocation

// MARK: - Models

/// Denormalized run stats captured on a post at publish time (mirrors the
/// backend `stats_snapshot` jsonb). All optional — older/edited posts may omit.
struct PostStats: Codable, Equatable {
    let distance: Double?
    let pace: Double?       // seconds per mile
    let duration: Double?   // seconds
    let streak: Int?
    let date: String?
    var calories: Double?
    var steps: Int?
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
    var caption: String?
    let workout_id: String?
    let stats_snapshot: PostStats?
    let local_date: String?
    let share_to_feed: Bool?
    let share_to_story: Bool?
    let story_expires_at: String?
    let created_at: String
    /// System-generated route/stats card (vs a deliberate user post).
    var is_auto: Bool?
    /// The linked workout's type ("running"/"walking") for the type icon.
    var workout_type: String?
    /// Simplified GPS trace [[lat, lng], ...] when synced + shared.
    var route: [[Double]]?
    /// The run's ACTIVE story photo (profile posts responses) — the real
    /// picture leads wherever it exists; the workout card is secondary.
    var story_photo_url: String?
    let is_self: Bool
    var is_hyped: Bool
    var hype_count: Int?
    var comment_count: Int?
    var is_viewed: Bool?
    /// Story rows only: does this run already have a live feed post? Hides the
    /// story viewer's "Add to feed" when the workout is already on the feed.
    var workout_on_feed: Bool?
    /// Server withheld this post's photo because it's from the viewer's local
    /// today and they haven't finished their own mile yet — the client draws a
    /// lock instead of a broken image. Absent/false = unlocked.
    var photo_locked: Bool? = nil
    /// The viewer's own emoji reaction to this story, hydrated on load so a
    /// re-view shows the reaction they already left. nil = not reacted.
    var viewer_reaction: String? = nil
    /// Collab post: the invited/accepted coauthor. Pending invites are only
    /// visible to the two authors; everyone else decodes nil.
    var coauthor_user_id: String?
    var coauthor_status: String?    // "pending" | "accepted"
    var coauthor_username: String?
    var coauthor_first_name: String?
    var coauthor_last_name: String?
    var coauthor_profile_image_url: String?

    var id: String { post_id }

    /// Whether the server locked this post's photo (viewer hasn't run today).
    var isPhotoLocked: Bool { photo_locked == true }

    var hasAcceptedCoauthor: Bool { coauthor_user_id != nil && coauthor_status == "accepted" }

    var coauthorDisplayName: String {
        if let coauthor_username, !coauthor_username.isEmpty { return coauthor_username }
        if let coauthor_first_name, !coauthor_first_name.isEmpty { return coauthor_first_name }
        return "a friend"
    }

    /// Decoded route polyline (nil when absent or degenerate).
    var routeCoordinates: [CLLocationCoordinate2D]? { decodeRouteCoordinates(route) }

    var displayName: String {
        if let username, !username.isEmpty { return username }
        if let first_name, !first_name.isEmpty { return first_name }
        return "Someone"
    }

    var mediaURL: URL? { ProfileImageService.fullImageURL(for: media_url) }

    /// The run's story photo when present and distinct from the post media.
    var storyPhotoURL: URL? {
        guard let story_photo_url, story_photo_url != media_url else { return nil }
        return ProfileImageService.fullImageURL(for: story_photo_url)
    }

    /// Short "2h", "5m", "now" relative time from created_at.
    var relativeTime: String { RelativeTime.short(from: created_at) }
}

/// Decode a backend `[[lat, lng], ...]` trace into map coordinates. Nil when
/// absent or degenerate (fewer than 2 valid points) — the single definition of
/// "drawable route" shared by post and feed-entry models.
func decodeRouteCoordinates(_ route: [[Double]]?) -> [CLLocationCoordinate2D]? {
    guard let route, route.count >= 2 else { return nil }
    let coords = route.compactMap { pair -> CLLocationCoordinate2D? in
        guard pair.count >= 2 else { return nil }
        return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
    }
    return coords.count >= 2 ? coords : nil
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
    /// Distinct author-local days ("yyyy-MM-dd") this group's stories span —
    /// drives the per-day viewing gate. Optional: absent from older servers.
    let story_local_dates: [String]?
    /// Author-local days with an unseen story — the ring lights only when one
    /// of these is a day the viewer can actually watch. Optional (older
    /// servers omit it → fall back to has_unviewed).
    let unviewed_local_dates: [String]?

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

/// One row of the unified feed: either a photo `post` or a raw `workout`
/// activity. Type-specific fields are nil for the other kind. Decodes the
/// backend's `id` into `entryId` (Identifiable's `id` combines kind + entryId).
struct FeedEntry: Codable, Identifiable {
    let kind: String            // "post" | "workout"
    let entryId: String
    let sort_ts: String
    let user_id: String
    let username: String?
    let first_name: String?
    let last_name: String?
    let profile_image_url: String?
    // post-only
    let media_url: String?
    var caption: String?
    let stats_snapshot: PostStats?
    /// The run's story-only photo, when one exists — powers the photo/route
    /// flip on the feed card without duplicating the run in the feed.
    let story_photo_url: String?
    /// post-only: system-generated route/stats card (vs a deliberate post).
    let is_auto: Bool?
    /// The entry's workout: the linked workout for posts (nil when unlinked
    /// or from an older backend), the workout itself for workout entries.
    let workout_id: String?
    // workout columns (workout_type is also set for posts via their run)
    let workout_type: String?
    let distance: Double?
    let total_duration: Double?
    let calories: Double?
    let steps: Int?
    /// Simplified GPS trace [[lat, lng], ...] for the entry's workout.
    let route: [[Double]]?
    // shared
    let is_self: Bool
    var is_hyped: Bool
    var hype_count: Int?
    /// Server withheld this post's photo (viewer hasn't run today) — carried
    /// into the rendered PostItem so the card draws a lock.
    let photo_locked: Bool?
    var comment_count: Int?
    // Collab post fields (post entries only; nil while pending unless viewer
    // is one of the two authors).
    var coauthor_user_id: String?
    var coauthor_status: String?
    var coauthor_username: String?
    var coauthor_first_name: String?
    var coauthor_last_name: String?
    var coauthor_profile_image_url: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case entryId = "id"
        case sort_ts, user_id, username, first_name, last_name, profile_image_url
        case media_url, caption, stats_snapshot, story_photo_url, is_auto
        case workout_id, workout_type, distance, total_duration, calories, steps, route
        case is_self, is_hyped, hype_count, comment_count, photo_locked
        case coauthor_user_id, coauthor_status, coauthor_username
        case coauthor_first_name, coauthor_last_name, coauthor_profile_image_url
    }

    var id: String { "\(kind)-\(entryId)" }
    var isPost: Bool { kind == "post" }

    /// Decoded route polyline (nil when absent or degenerate).
    var routeCoordinates: [CLLocationCoordinate2D]? { decodeRouteCoordinates(route) }

    var storyPhotoURL: URL? {
        guard let story_photo_url, story_photo_url != media_url else { return nil }
        return ProfileImageService.fullImageURL(for: story_photo_url)
    }

    var displayName: String {
        if let username, !username.isEmpty { return username }
        if let first_name, !first_name.isEmpty { return first_name }
        return "Someone"
    }

    var relativeTime: String { RelativeTime.short(from: sort_ts) }

    /// Render a post-kind entry through the existing PostCardView.
    func asPostItem() -> PostItem? {
        guard kind == "post", let media = media_url else { return nil }
        return PostItem(
            post_id: entryId, user_id: user_id, username: username,
            first_name: first_name, last_name: last_name,
            profile_image_url: profile_image_url, media_url: media, caption: caption,
            workout_id: workout_id, stats_snapshot: stats_snapshot, local_date: nil,
            share_to_feed: true, share_to_story: nil, story_expires_at: nil,
            created_at: sort_ts, is_auto: is_auto, workout_type: workout_type,
            route: route, story_photo_url: story_photo_url,
            is_self: is_self, is_hyped: is_hyped,
            hype_count: hype_count, comment_count: comment_count,
            is_viewed: nil, workout_on_feed: nil,
            photo_locked: photo_locked,
            coauthor_user_id: coauthor_user_id, coauthor_status: coauthor_status,
            coauthor_username: coauthor_username,
            coauthor_first_name: coauthor_first_name,
            coauthor_last_name: coauthor_last_name,
            coauthor_profile_image_url: coauthor_profile_image_url
        )
    }
}

struct UnifiedFeedResponse: Decodable {
    let items: [FeedEntry]
    let next_before: String?
}

/// One viewer of the caller's own story, with any emoji reaction they left.
struct StoryViewer: Codable, Identifiable {
    let user_id: String
    let username: String?
    let first_name: String?
    let last_name: String?
    let profile_image_url: String?
    let viewed_at: String
    let emoji: String?

    var id: String { user_id }

    var displayName: String {
        if let username, !username.isEmpty { return username }
        if let first_name, !first_name.isEmpty { return first_name }
        return "Someone"
    }

    var relativeTime: String { RelativeTime.short(from: viewed_at) }
}

struct StoryViewersResponse: Decodable {
    let viewers: [StoryViewer]
    let count: Int
}

/// One person who reacted to a story, for the bubble row shown to all viewers.
struct StoryReactor: Codable, Identifiable {
    let user_id: String
    let username: String?
    let first_name: String?
    let last_name: String?
    let profile_image_url: String?
    let emoji: String
    let created_at: String

    var id: String { user_id }

    var displayName: String {
        if let username, !username.isEmpty { return username }
        if let first_name, !first_name.isEmpty { return first_name }
        return "Someone"
    }
}

struct StoryReactorsResponse: Decodable {
    let reactors: [StoryReactor]
    let count: Int
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
    /// Percent-encoding for query-string VALUES (pagination cursors).
    /// `.urlQueryAllowed` leaves '+' literal, and the backend's query parser
    /// decodes a literal '+' as a SPACE — which corrupted the old
    /// "…12:34:56.123456+00" timestamp cursors and silently froze feed
    /// pagination after the first page. Encoding the reserved characters
    /// guarantees the cursor arrives byte-identical.
    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+&=?")
        return set
    }()

    /// A `before=` query suffix for the given cursor, safely encoded.
    fileprivate static func beforeSuffix(_ before: String?) -> String {
        guard let before,
              let encoded = before.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
        else { return "" }
        return "&before=\(encoded)"
    }

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
    /// with code "mile_not_completed" / "terms_not_accepted" when gated, and
    /// APIError.conflict ("workout_already_posted") when the workout already has
    /// a live user post for that destination (one deliberate post per workout —
    /// delete the old one to post again).
    static func createPost(
        mediaUrl: String,
        caption: String?,
        workoutId: String?,
        shareToFeed: Bool,
        shareToStory: Bool,
        stats: PostStats?,
        isAuto: Bool = false,
        includeRoute: Bool = true,
        coauthorUserId: String? = nil
    ) async throws -> PostItem {
        struct Body: Encodable {
            let media_url: String
            let caption: String?
            let workout_id: String?
            let share_to_feed: Bool
            let share_to_story: Bool
            let stats_snapshot: PostStats?
            let is_auto: Bool
            let include_route: Bool
            let coauthor_user_id: String?
        }
        let bodyData = try JSONEncoder().encode(
            Body(
                media_url: mediaUrl,
                caption: caption,
                workout_id: workoutId,
                share_to_feed: shareToFeed,
                share_to_story: shareToStory,
                stats_snapshot: stats,
                is_auto: isAuto,
                include_route: includeRoute,
                coauthor_user_id: coauthorUserId
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

    /// Who saw the caller's own story, with any emoji reactions (reactors first).
    static func storyViewers(postId: String) async throws -> StoryViewersResponse {
        try await APIClient.fancyFetch(
            endpoint: "/posts/stories/\(postId)/viewers",
            responseType: StoryViewersResponse.self
        )
    }

    /// Everyone who reacted to a story — visible to any circle viewer, for the
    /// reaction-bubble row (not just the author's private viewers list).
    static func storyReactors(postId: String) async throws -> StoryReactorsResponse {
        try await APIClient.fancyFetch(
            endpoint: "/posts/stories/\(postId)/reactions",
            responseType: StoryReactorsResponse.self
        )
    }

    /// Emoji-react to a friend's story. Re-reacting swaps the emoji.
    static func reactToStory(postId: String, emoji: String) async throws {
        struct Body: Encodable { let emoji: String }
        let bodyData = try JSONEncoder().encode(Body(emoji: emoji))
        _ = try await APIClient.fancyFetch(
            endpoint: "/posts/stories/\(postId)/react",
            method: .POST,
            body: bodyData,
            responseType: OKResponse.self
        )
    }

    /// The caller's own post photos from this day in past years — fuel for
    /// the "On this day" memories surface.
    static func fetchPostMemories() async throws -> [PostItem] {
        struct MemoriesResponse: Decodable { let items: [PostItem] }
        return try await APIClient.fancyFetch(
            endpoint: "/posts/memories",
            responseType: MemoriesResponse.self
        ).items
    }

    /// One page of the feed. Pass the previous page's `next_before` to paginate.
    static func fetchFeed(before: String? = nil) async throws -> FeedResponse {
        let endpoint = "/posts/feed?limit=20" + beforeSuffix(before)
        return try await APIClient.fancyFetch(endpoint: endpoint, responseType: FeedResponse.self)
    }

    /// The unified feed: photo posts + workout activity interleaved, paginated.
    static func fetchUnifiedFeed(before: String? = nil) async throws -> UnifiedFeedResponse {
        let endpoint = "/posts/feed/unified?limit=20" + beforeSuffix(before)
        return try await APIClient.fancyFetch(endpoint: endpoint, responseType: UnifiedFeedResponse.self)
    }

    /// A user's permanent posts for the Instagram-style profile grid.
    /// `includeStories` (own profile only — the server enforces it) also
    /// returns story-only posts whose run isn't on the feed, so the owner can
    /// review and promote them.
    static func fetchUserPosts(
        userId: String,
        before: String? = nil,
        includeStories: Bool = false
    ) async throws -> FeedResponse {
        var endpoint = "/posts/user/\(userId)?limit=24" + beforeSuffix(before)
        if includeStories { endpoint += "&include_stories=true" }
        return try await APIClient.fancyFetch(endpoint: endpoint, responseType: FeedResponse.self)
    }

    /// Accept (true) or decline/leave (false) a collab-post invite.
    static func respondToCoauthor(postId: String, accept: Bool) async throws {
        struct Body: Encodable { let accept: Bool }
        let bodyData = try JSONEncoder().encode(Body(accept: accept))
        _ = try await APIClient.fancyFetch(
            endpoint: "/posts/\(postId)/coauthor",
            method: .POST,
            body: bodyData,
            responseType: OKResponse.self
        )
    }

    /// The caller's own post (feed or story-only) linked to a workout, if any.
    /// Scans the first few pages of own posts — Recent Workouts surfaces
    /// recent runs, so the match is nearly always on page one.
    static func fetchOwnPostForWorkout(workoutId: String, userId: String) async throws -> PostItem? {
        var before: String? = nil
        for _ in 0..<3 {
            let page = try await fetchUserPosts(userId: userId, before: before, includeStories: true)
            if let match = page.items.first(where: { $0.workout_id == workoutId }) { return match }
            guard let next = page.next_before else { return nil }
            before = next
        }
        return nil
    }

    /// Edit a post's caption. Pass nil (or whitespace) to clear it.
    static func updateCaption(postId: String, caption: String?) async throws {
        struct Body: Encodable { let caption: String }
        // The server trims and stores "" as NULL, so an empty string clears.
        let bodyData = try JSONEncoder().encode(Body(caption: caption ?? ""))
        _ = try await APIClient.fancyFetch(
            endpoint: "/posts/\(postId)",
            method: .PATCH,
            body: bodyData,
            responseType: OKResponse.self
        )
    }

    /// Promote a story-only post onto the feed in place (keeps its original
    /// date, media, and stats). Throws APIError.conflict
    /// ("workout_already_posted") when the run already has a deliberate feed
    /// post.
    static func addPostToFeed(postId: String) async throws {
        struct Body: Encodable { let add_to_feed: Bool }
        let bodyData = try JSONEncoder().encode(Body(add_to_feed: true))
        _ = try await APIClient.fancyFetch(
            endpoint: "/posts/\(postId)",
            method: .PATCH,
            body: bodyData,
            responseType: OKResponse.self
        )
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
        // Pin the cache key BEFORE the await: if the account switches while
        // the request is in flight, the response must land under the user
        // who made it, not whoever is signed in when it returns.
        let cacheKey = termsCacheKey(userId: currentUserId)
        let status: TermsStatus = try await APIClient.fancyFetch(
            endpoint: "/posts/terms",
            responseType: TermsStatus.self
        )
        UserDefaults.standard.set(status.accepted, forKey: cacheKey)
        return status
    }

    @discardableResult
    static func acceptTerms() async throws -> TermsStatus {
        let cacheKey = termsCacheKey(userId: currentUserId)
        let status: TermsStatus = try await APIClient.fancyFetch(
            endpoint: "/posts/terms/accept",
            method: .POST,
            responseType: TermsStatus.self
        )
        UserDefaults.standard.set(status.accepted, forKey: cacheKey)
        return status
    }

    // MARK: Community-guidelines acceptance cache

    /// Same accessor the sibling services (WorkoutService, FriendService…)
    /// keep for the logged-in backend user id.
    private static var currentUserId: String? {
        UserDefaults.standard.string(forKey: "backendUserId")
    }

    /// Local memo of the server-side guidelines acceptance so composer gates
    /// can decide instantly (and offline) instead of blocking on a round-trip.
    /// The server stays the source of truth: every termsStatus/acceptTerms
    /// response refreshes it, and a `terms_not_accepted` publish rejection
    /// clears it. Keyed per backend user so account switches can't leak an
    /// acceptance across users.
    private static func termsCacheKey(userId: String?) -> String {
        "post.terms.accepted.\(userId ?? "anon")"
    }

    static var termsAcceptedCached: Bool {
        UserDefaults.standard.bool(forKey: termsCacheKey(userId: currentUserId))
    }

    static func cacheTermsAccepted(_ accepted: Bool) {
        UserDefaults.standard.set(accepted, forKey: termsCacheKey(userId: currentUserId))
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
