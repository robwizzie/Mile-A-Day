import Foundation

// MARK: - Filter Enums

enum LeaderboardMetric: String, CaseIterable, Identifiable {
    case miles
    case streak
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .miles: return "Miles"
        case .streak: return "Streak"
        }
    }
}

enum LeaderboardPeriod: String, CaseIterable, Identifiable {
    case today
    case week
    case month
    case year
    case all
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .all: return "All-Time"
        }
    }
}

// MARK: - Response Models

struct LeaderboardEntry: Decodable, Identifiable {
    let rank: Int
    let user_id: String
    let username: String?
    let first_name: String?
    let last_name: String?
    let profile_image_url: String?
    let value: Double
    /// Total miles within the active period (or all-time when metric=streak).
    /// Optional so older backend builds without the field still decode.
    let period_miles: Double?
    /// Fastest mile pace (seconds/mi) within the same window; nil if none recorded.
    let period_best_pace: Double?
    let is_current_user: Bool

    var id: String { user_id }

    /// Prefer @username on the leaderboard so handles are recognizable.
    /// Falls back to first/last name, then "Anonymous" if neither exists.
    var displayName: String {
        if let username = username, !username.isEmpty {
            return username
        }
        if let first = first_name, !first.isEmpty {
            if let last = last_name, !last.isEmpty {
                return "\(first) \(last)"
            }
            return first
        }
        return "Anonymous"
    }

    /// Real name for the avatar's initials fallback — username initials look noisy.
    var fullName: String {
        if let first = first_name, !first.isEmpty {
            if let last = last_name, !last.isEmpty {
                return "\(first) \(last)"
            }
            return first
        }
        return displayName
    }
}

struct LeaderboardPage: Decodable {
    let entries: [LeaderboardEntry]
    let total_count: Int
    let has_more: Bool
    let current_user_entry: LeaderboardEntry?
}

// MARK: - Service

/// Fetches paginated leaderboard pages from the backend. Scope is always the
/// viewer's friend group (plus themselves) — Global was intentionally dropped;
/// can be re-added later if needed.
enum LeaderboardService {
    static let defaultPageSize = 25

    static func fetch(
        metric: LeaderboardMetric,
        period: LeaderboardPeriod,
        limit: Int = defaultPageSize,
        offset: Int = 0
    ) async throws -> LeaderboardPage {
        // Build the query string by hand — enum raw values + ints, so no
        // URL-encoding required. Avoids URLComponents quirks with path-only URLs.
        let endpoint = "/leaderboard?metric=\(metric.rawValue)&period=\(period.rawValue)&limit=\(limit)&offset=\(offset)"

        return try await APIClient.fancyFetch(
            endpoint: endpoint,
            method: .GET,
            body: nil,
            responseType: LeaderboardPage.self
        )
    }
}
