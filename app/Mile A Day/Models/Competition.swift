import Foundation

// MARK: - Competition Models

/// Represents a competition from the backend API
struct Competition: Codable, Identifiable {
    let competition_id: String
    let competition_name: String
    let start_date: String
    let end_date: String
    let workouts: [CompetitionActivity]
    let type: CompetitionType
    let options: CompetitionOptions
    let owner: String
    let users: [CompetitionUser]

    var id: String { competition_id }

    // Computed properties
    var isOwner: Bool {
        guard let currentUserId = UserDefaults.standard.string(forKey: "user_id") else {
            return false
        }
        return owner == currentUserId
    }

    var currentUserInviteStatus: InviteStatus? {
        guard let currentUserId = UserDefaults.standard.string(forKey: "user_id") else {
            return nil
        }
        return users.first(where: { $0.user_id == currentUserId })?.invite_status
    }

    var acceptedUsersCount: Int {
        users.filter { $0.invite_status == .accepted }.count
    }

    var startDateFormatted: Date? {
        ISO8601DateFormatter().date(from: start_date)
    }

    var endDateFormatted: Date? {
        ISO8601DateFormatter().date(from: end_date)
    }
}

/// Competition type enum
enum CompetitionType: String, Codable, CaseIterable {
    case streaks = "streaks"
    case apex = "apex"
    case targets = "targets"
    case clash = "clash"
    case race = "race"

    var displayName: String {
        switch self {
        case .streaks: return "Streaks"
        case .apex: return "Apex"
        case .targets: return "Targets"
        case .clash: return "Clash"
        case .race: return "Race"
        }
    }

    var description: String {
        switch self {
        case .streaks:
            return "Hold a running streak as long as you can. First to break the streak loses"
        case .apex:
            return "Over a period of time (ex: 1 week) whoever has the most distance during that time wins"
        case .targets:
            return "Anyone who completes the goal in a given day gets a point. Whoever has the most points at the end of the period wins"
        case .clash:
            return "Whoever gets the most distance in a day gets a point. Whoever has the most points at the end of the period or whoever reaches a certain amount of points first wins. Same as 'targets' but only one person can score on a given day"
        case .race:
            return "There is a distance goal set and whoever gets there first wins"
        }
    }

    var icon: String {
        switch self {
        case .streaks: return "flame.fill"
        case .apex: return "arrow.up.circle.fill"
        case .targets: return "target"
        case .clash: return "bolt.fill"
        case .race: return "flag.fill"
        }
    }

    var gradient: [String] {
        switch self {
        case .streaks: return ["FF6B6B", "FF8E53"]
        case .apex: return ["4ECDC4", "44A08D"]
        case .targets: return ["F7971E", "FFD200"]
        case .clash: return ["C33764", "1D2671"]
        case .race: return ["667EEA", "764BA2"]
        }
    }
}

/// Competition activity type
enum CompetitionActivity: String, Codable, CaseIterable {
    case run = "run"
    case walk = "walk"

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        }
    }
}

/// Competition options
struct CompetitionOptions: Codable {
    let goal: Double
    let unit: CompetitionUnit
    let first_to: Int
    let history: Bool?
    let interval: CompetitionInterval?

    var goalFormatted: String {
        if unit == .miles {
            return String(format: "%.1f", goal)
        } else {
            return String(format: "%.0f", goal)
        }
    }
}

/// Competition unit
enum CompetitionUnit: String, Codable, CaseIterable {
    case miles = "miles"
    case steps = "steps"

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .miles: return "figure.run"
        case .steps: return "figure.walk"
        }
    }
}

/// Competition interval
enum CompetitionInterval: String, Codable, CaseIterable {
    case day = "day"
    case week = "week"
    case month = "month"

    var displayName: String {
        rawValue.capitalized
    }
}

/// Competition user
struct CompetitionUser: Codable, Identifiable {
    let competition_id: String
    let user_id: String
    let invite_status: InviteStatus

    var id: String { "\(competition_id)-\(user_id)" }
}

/// Invite status
enum InviteStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case accepted = "accepted"
    case declined = "declined"

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - API Request Models

/// Request to create a competition
struct CreateCompetitionRequest: Codable {
    let competition_name: String
    let type: CompetitionType
    let start_date: String
    let end_date: String
    let workouts: [CompetitionActivity]
    let options: CompetitionOptionsRequest
}

struct CompetitionOptionsRequest: Codable {
    let goal: Double
    let unit: CompetitionUnit
    let first_to: Int
    let history: Bool
    let interval: CompetitionInterval
}

/// Request to update a competition
struct UpdateCompetitionRequest: Codable {
    let competition_name: String?
    let type: CompetitionType?
    let start_date: String?
    let end_date: String?
    let workouts: [CompetitionActivity]?
    let options: PartialCompetitionOptionsRequest?
}

struct PartialCompetitionOptionsRequest: Codable {
    let goal: Double?
    let unit: CompetitionUnit?
    let first_to: Int?
    let history: Bool?
    let interval: CompetitionInterval?
}

/// Request to invite a user
struct InviteUserRequest: Codable {
    let inviteUser: String
}

// MARK: - API Response Models

struct CreateCompetitionResponse: Codable {
    let competition_id: String
}

struct CompetitionResponse: Codable {
    let competition: Competition
}

struct CompetitionsListResponse: Codable {
    let competitions: [Competition]
}

struct CompetitionInvitesResponse: Codable {
    let competitionInvites: [Competition]
}

struct InviteUserResponse: Codable {
    let message: String
}
