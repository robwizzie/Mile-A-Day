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
    case week
    case month
    case year
    case all
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .all: return "All-Time"
        }
    }
}

enum LeaderboardScope: String, CaseIterable, Identifiable {
    case global
    case friends
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .global: return "Global"
        case .friends: return "Friends"
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
    let is_current_user: Bool

    var id: String { user_id }

    var displayName: String {
        if let first = first_name, !first.isEmpty {
            if let last = last_name, !last.isEmpty {
                return "\(first) \(last)"
            }
            return first
        }
        if let username = username, !username.isEmpty {
            return username
        }
        return "Anonymous"
    }
}

struct LeaderboardPage: Decodable {
    let entries: [LeaderboardEntry]
    let total_count: Int
    let has_more: Bool
    let current_user_entry: LeaderboardEntry?
    /// True when the viewer has opted out of leaderboards — UI uses this to
    /// show a "you're hidden" banner with a one-tap re-enable button.
    let viewer_opted_out: Bool
}

private struct OptOutResponse: Decodable {
    let leaderboard_opt_out: Bool
}

private struct OptOutRequestBody: Encodable {
    let optOut: Bool
}

// MARK: - Service

/// Fetches paginated leaderboard pages from the backend. Stateless — pagination
/// state lives in the view model so the user can re-issue requests on every
/// filter change without coupling to a singleton's stored cursor.
enum LeaderboardService {
    static let defaultPageSize = 25

    static func fetch(
        metric: LeaderboardMetric,
        period: LeaderboardPeriod,
        scope: LeaderboardScope,
        limit: Int = defaultPageSize,
        offset: Int = 0
    ) async throws -> LeaderboardPage {
        var components = URLComponents()
        components.path = "/leaderboard"
        components.queryItems = [
            URLQueryItem(name: "metric", value: metric.rawValue),
            URLQueryItem(name: "period", value: period.rawValue),
            URLQueryItem(name: "scope", value: scope.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        let endpoint = components.url?.relativeString ?? "/leaderboard"

        return try await APIClient.fancyFetch(
            endpoint: endpoint,
            method: .GET,
            body: nil,
            responseType: LeaderboardPage.self
        )
    }

    /// Toggles the viewer's leaderboard visibility on the backend. Returns the
    /// committed value so callers can update local state without a refetch.
    static func setOptOut(userId: String, optOut: Bool) async throws -> Bool {
        let body = try JSONEncoder().encode(OptOutRequestBody(optOut: optOut))
        let response = try await APIClient.fancyFetch(
            endpoint: "/users/\(userId)/leaderboard-opt-out",
            method: .PATCH,
            body: body,
            responseType: OptOutResponse.self
        )
        return response.leaderboard_opt_out
    }
}
