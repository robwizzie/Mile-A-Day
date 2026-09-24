import Foundation

// MARK: - Backend User Models
/// Represents a user from the backend API
struct BackendUser: Codable, Identifiable, Hashable {
    let user_id: String
    let username: String?
    // Optional: public endpoints (search, friend lists, suggestions) omit email
    // for privacy; only the authenticated user's own record carries it.
    let email: String?
    let first_name: String?
    let last_name: String?
    let bio: String?
    let profile_image_url: String?
    let apple_id: String?
    let auth_provider: String?
    let role: String?
    /// Profile banner — the header behind the avatar: an uploaded image path
    /// (nil = none) and the gradient preset drawn when there is no image
    /// (`ProfileBannerStyle`). `var` + default so every memberwise
    /// `BackendUser(...)` call site (feed authors, mention lookups, previews)
    /// keeps compiling, and nil on the projections that don't carry them
    /// (friend lists, search) — the profile screen re-fetches the full record.
    var profile_banner_url: String? = nil
    var profile_banner_style: String? = nil
    /// `users.created_at` — the day Flamey met you (his anniversary). Only
    /// the full `GET /users/:id` record carries it; a String because backend
    /// timestamps have fractional seconds `.iso8601` can't decode.
    var created_at: String? = nil
    /// 'fun' | 'modern' | nil (a build that never reported one, or an older
    /// server). Carried by `GET /users/:id` and the friends-list rows.
    var dashboard_style: String? = nil
    /// Their Flamey, on `GET /users/:id` only — enabled for a Fun user seen
    /// by themselves or an accepted friend. Absent on an older server, which
    /// every reader treats exactly like `enabled: false`.
    var flamey: FlameyProfileBlock? = nil

    var id: String { user_id }

    // Computed properties for convenience
    var displayName: String {
        if let first = first_name, let last = last_name {
            return "\(first) \(last)"
        } else if let first = first_name {
            return first
        } else if let username = username, !username.isEmpty {
            return username
        } else {
            return "Unknown User"
        }
    }

    var hasProfileImage: Bool {
        return profile_image_url != nil && !profile_image_url!.isEmpty
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(user_id)
    }

    static func == (lhs: BackendUser, rhs: BackendUser) -> Bool {
        lhs.user_id == rhs.user_id
    }
}

/// The `flamey` block on `GET /users/:id`: the durable facts someone's Flamey
/// is dressed from. Foundation-only and defined HERE (not beside the
/// wardrobe) because this file may be a Watch-target member. Every field but
/// `enabled` is optional so a partial block still decodes; readers treat a
/// missing block, `enabled: false` or a garbled one identically — no Flamey.
struct FlameyProfileBlock: Codable {
    /// Optional too: one malformed block must never fail the whole profile.
    var enabled: Bool? = nil
    var longest_streak: Int? = nil
    /// Holiday medals held, as `HolidayKey` raw values ("halloween").
    var holiday_keys: [String]? = nil
    /// "YYYY-MM-DD", the day they signed up, on their own calendar.
    var signup_date: String? = nil
    /// Their Flamey's Closet choice, the wire `{slot: itemId | null}` (a
    /// missing slot is auto, null is bare). Additive; absent on older servers.
    var look: [String: String?]? = nil
    /// Every wardrobe item they own, when the server sends it. Additive.
    var owned_item_ids: [String]? = nil
}

// MARK: - Friendship Models
/// Represents a friendship relationship
struct Friendship: Codable, Identifiable {
    let user_id: String
    let friend_id: String
    let status: FriendshipStatus
    
    var id: String { "\(user_id)-\(friend_id)" }
}

/// Friendship status enum
enum FriendshipStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case accepted = "accepted"
    case ignored = "ignored"
    case rejected = "rejected"
    case removed = "removed"
    
    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .accepted:
            return "Friends"
        case .ignored:
            return "Ignored"
        case .rejected:
            return "Rejected"
        case .removed:
            return "Removed"
        }
    }
}

// MARK: - Friend Request Models
/// Represents a friend request with user details
struct FriendRequest: Codable, Identifiable {
    let user: BackendUser
    let status: FriendshipStatus
    let sentAt: Date?
    
    var id: String { user.user_id }
}

// MARK: - User Search Response
struct UserSearchResponse: Codable {
    let user: BackendUser
    let friendshipStatus: FriendshipStatus?
}

// MARK: - API Response Models
struct APIResponse<T: Codable>: Codable {
    let data: T?
    let message: String?
    let error: String?
}

struct FriendshipListResponse: Codable {
    let friends: [BackendUser]
}

struct FriendRequestsResponse: Codable {
    let requests: [BackendUser]
    let ignored_requests: [BackendUser]
}

// MARK: - Privacy Settings
/// Represents user privacy preferences
struct PrivacySettings: Codable {
    var isPublic: Bool
    var showStats: Bool
    var showBadges: Bool
    var showStreak: Bool
    
    init(isPublic: Bool = true, showStats: Bool = true, showBadges: Bool = true, showStreak: Bool = true) {
        self.isPublic = isPublic
        self.showStats = showStats
        self.showBadges = showBadges
        self.showStreak = showStreak
    }
    
    /// Default privacy settings for new users
    static let `default` = PrivacySettings()
    
    /// Private settings - only show username and profile picture
    static let privateAccount = PrivacySettings(
        isPublic: false,
        showStats: false,
        showBadges: false,
        showStreak: false
    )
}
