import Foundation
import SwiftUI

// MARK: - Competition Models

/// Represents a competition from the backend API
struct Competition: Codable, Identifiable {
    let competition_id: String
    let competition_name: String
    let start_date: String?
    let end_date: String?
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
        guard let dateStr = start_date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: dateStr)
    }

    var endDateFormatted: Date? {
        guard let dateStr = end_date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: dateStr)
    }

    /// Computed competition status based on dates
    var status: CompetitionStatus {
        guard let startStr = start_date else {
            return .lobby
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let now = Date()

        guard let startDate = formatter.date(from: startStr) else {
            return .lobby
        }

        if startDate > now {
            return .scheduled
        }

        // Start date is in the past - check end date
        if let endStr = end_date, let endDate = formatter.date(from: endStr) {
            if endDate < now {
                return .finished
            }
        }

        return .active
    }
}

/// Competition lifecycle status - derived from dates
enum CompetitionStatus: String {
    case lobby       // start_date is nil - waiting for owner to start
    case scheduled   // start_date is in the future
    case active      // start_date is in the past, end_date is nil or in the future
    case finished    // end_date is in the past

    var displayName: String {
        switch self {
        case .lobby: return "Lobby"
        case .scheduled: return "Scheduled"
        case .active: return "Active"
        case .finished: return "Finished"
        }
    }

    var icon: String {
        switch self {
        case .lobby: return "hourglass"
        case .scheduled: return "calendar.badge.clock"
        case .active: return "bolt.fill"
        case .finished: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .lobby: return .orange
        case .scheduled: return .blue
        case .active: return .green
        case .finished: return .gray
        }
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
            return "Whoever goes the furthest each day wins a point. First to reach the target score or most points at the end wins"
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
    let duration_hours: Int?

    var goalFormatted: String {
        if unit == .miles {
            return String(format: "%.1f", goal)
        } else {
            return String(format: "%.0f", goal)
        }
    }

    var durationFormatted: String? {
        guard let hours = duration_hours else { return nil }
        if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        let days = hours / 24
        if days == 7 { return "1 week" }
        if days == 14 { return "2 weeks" }
        if days == 30 { return "1 month" }
        return "\(days) day\(days == 1 ? "" : "s")"
    }
}

/// Competition unit
enum CompetitionUnit: String, Codable, CaseIterable {
    case miles = "miles"
    case kilometers = "kilometers"
    case steps = "steps"

    var displayName: String {
        rawValue.capitalized
    }

    var shortDisplayName: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        case .steps: return "k"
        }
    }

    var icon: String {
        switch self {
        case .miles: return "figure.run"
        case .kilometers: return "figure.run"
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

/// Competition user with enriched data from backend
struct CompetitionUser: Codable, Identifiable {
    let competition_id: String
    let user_id: String
    let invite_status: InviteStatus
    let username: String?
    let score: Double?
    let intervals: [String: Double]?

    var id: String { "\(competition_id)-\(user_id)" }

    var displayName: String {
        if let uname = username, !uname.isEmpty {
            return uname
        }
        return "Unknown"
    }
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
    let start_date: String?
    let end_date: String?
    let workouts: [CompetitionActivity]
    let options: CompetitionOptionsRequest
}

struct CompetitionOptionsRequest: Codable {
    let goal: Double
    let unit: CompetitionUnit
    let first_to: Int
    let history: Bool
    let interval: CompetitionInterval
    let duration_hours: Int?
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

struct DeleteCompetitionResponse: Codable {
    let message: String
}
