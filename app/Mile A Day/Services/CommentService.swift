import SwiftUI

/// One comment on a feed post. Replies carry the parent (top-level) comment's
/// id — the backend keeps threads one level deep, Instagram-style.
struct PostComment: Decodable, Identifiable, Equatable {
    let comment_id: String
    let post_id: String
    let user_id: String
    let username: String?
    let first_name: String?
    let last_name: String?
    let profile_image_url: String?
    let parent_comment_id: String?
    let content: String
    let created_at: String
    let is_self: Bool

    var id: String { comment_id }

    var displayName: String {
        if let username, !username.isEmpty { return username }
        if let first_name, !first_name.isEmpty { return first_name }
        return "Someone"
    }

    var relativeTime: String { RelativeTime.short(from: created_at) }
}

/// Stateless API surface for post comments (list / add / delete / report).
enum CommentService {
    /// Mirrors MAX_COMMENT in backend/src/controllers/commentsController.ts.
    static let maxLength = 1000

    static func list(postId: String) async throws -> [PostComment] {
        struct ListResponse: Decodable { let comments: [PostComment] }
        return try await APIClient.fancyFetch(
            endpoint: "/posts/\(postId)/comments",
            responseType: ListResponse.self
        ).comments
    }

    /// Add a comment; pass `parentCommentId` to reply to a top-level comment
    /// (the backend re-roots replies-to-replies automatically). Throws
    /// APIError.apiError("terms_not_accepted") before first-time terms consent.
    static func add(
        postId: String,
        content: String,
        parentCommentId: String? = nil
    ) async throws -> PostComment {
        struct Body: Encodable {
            let content: String
            let parent_comment_id: String?
        }
        struct AddResponse: Decodable { let comment: PostComment }
        let bodyData = try JSONEncoder().encode(
            Body(content: content, parent_comment_id: parentCommentId)
        )
        return try await APIClient.fancyFetch(
            endpoint: "/posts/\(postId)/comments",
            method: .POST,
            body: bodyData,
            responseType: AddResponse.self
        ).comment
    }

    /// Delete a comment (yours, or any comment on a post you author/co-author).
    /// Deleting a top-level comment removes its replies too.
    static func delete(commentId: String) async throws {
        struct OK: Decodable { let message: String? }
        _ = try await APIClient.fancyFetch(
            endpoint: "/posts/comments/\(commentId)",
            method: .DELETE,
            responseType: OK.self
        )
    }

    static func report(commentId: String, reason: String, details: String? = nil) async throws {
        struct Body: Encodable {
            let reason: String
            let details: String?
        }
        struct OK: Decodable { let message: String? }
        let bodyData = try JSONEncoder().encode(Body(reason: reason, details: details))
        _ = try await APIClient.fancyFetch(
            endpoint: "/posts/comments/\(commentId)/report",
            method: .POST,
            body: bodyData,
            responseType: OK.self
        )
    }
}

/// Renders @mentions in brand red within otherwise-plain text. Shared by
/// comment rows and post captions.
enum MentionText {
    /// Mirrors the backend's mention token rule (mentionService.ts).
    /// Extended `#/…/#` delimiters — bare-slash regex literals need a compiler
    /// flag this project doesn't set.
    private static let mentionRegex = #/@[A-Za-z0-9._-]+/#

    static func attributed(_ text: String) -> AttributedString {
        var out = AttributedString()
        var rest = Substring(text)
        while let match = rest.firstMatch(of: mentionRegex) {
            out += AttributedString(String(rest[rest.startIndex..<match.range.lowerBound]))
            var mention = AttributedString(String(match.output))
            mention.foregroundColor = MADTheme.Colors.madRed
            mention.font = .system(size: 14, weight: .bold, design: .rounded)
            out += mention
            rest = rest[match.range.upperBound...]
        }
        out += AttributedString(String(rest))
        return out
    }
}
