import Foundation

// MARK: - Backend User Models
/// Represents a user from the backend API
struct BackendUser: Codable, Identifiable, Hashable {
    let user_id: String
    let username: String?
    let email: String
    let first_name: String?
    let last_name: String?
    let bio: String?
    let profile_image_url: String?
    let apple_id: String?
    let auth_provider: String?

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
