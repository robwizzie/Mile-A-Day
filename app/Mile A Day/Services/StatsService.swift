import Foundation

/// Service for managing user stats and badges with backend API
class StatsService: ObservableObject {
    static let shared = StatsService()

    private let baseURL = "https://mad.mindgoblin.tech"
    private var authToken: String?

    init() {
        // Load auth token from UserDefaults
        self.authToken = UserDefaults.standard.string(forKey: "authToken")
    }

    // MARK: - Models

    struct UserStatsResponse: Codable {
        let stats: StatsData
        let badges: [BadgeData]
    }

    struct StatsData: Codable {
        let user_id: String
        let streak: Int
        let total_miles: Double
        let fastest_mile_pace: Double
        let most_miles_in_one_day: Double
        let last_completion_date: String?
        let goal_miles: Double
    }

    struct BadgeData: Codable {
        let badge_id: Int?
        let user_id: String?
        let badge_key: String
        let name: String
        let description: String
        let date_awarded: String
        let is_new: Bool
    }

    struct UpdateStatsRequest: Codable {
        let streak: Int
        let total_miles: Double
        let fastest_mile_pace: Double
        let most_miles_in_one_day: Double
        let last_completion_date: String?
        let goal_miles: Double
    }

    // MARK: - API Methods

    /// Fetch user stats and badges from backend
    func fetchUserStats(userId: String) async throws -> UserStatsResponse {
        guard let url = URL(string: "\(baseURL)/stats/\(userId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Add auth token if available
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(UserStatsResponse.self, from: data)
    }

    /// Sync local user stats to backend
    func syncUserStats(userId: String, user: User) async throws {
        guard let url = URL(string: "\(baseURL)/stats/\(userId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Content-Type", forHTTPHeaderField: "application/json")

        // Add auth token
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Prepare stats update
        let dateFormatter = ISO8601DateFormatter()
        let lastCompletionDate = user.lastCompletionDate.map { dateFormatter.string(from: $0) }

        let updateRequest = UpdateStatsRequest(
            streak: user.streak,
            total_miles: user.totalMiles,
            fastest_mile_pace: user.fastestMilePace,
            most_miles_in_one_day: user.mostMilesInOneDay,
            last_completion_date: lastCompletionDate,
            goal_miles: user.goalMiles
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(updateRequest)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    /// Sync local badges to backend
    func syncUserBadges(userId: String, badges: [Badge]) async throws {
        guard let url = URL(string: "\(baseURL)/stats/\(userId)/badges") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Content-Type", forHTTPHeaderField: "application/json")

        // Add auth token
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Convert badges to API format
        let dateFormatter = ISO8601DateFormatter()
        let badgeData = badges.map { badge in
            BadgeData(
                badge_id: nil,
                user_id: nil,
                badge_key: badge.id,
                name: badge.name,
                description: badge.description,
                date_awarded: dateFormatter.string(from: badge.dateAwarded),
                is_new: badge.isNew
            )
        }

        let requestBody = ["badges": badgeData]
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    /// Sync all local user data to backend (stats + badges)
    func syncAllUserData(userId: String, user: User) async throws {
        // Sync stats
        try await syncUserStats(userId: userId, user: user)

        // Sync badges
        if !user.badges.isEmpty {
            try await syncUserBadges(userId: userId, badges: user.badges)
        }
    }
}

// MARK: - UserStats Model

/// Model for displaying user stats in friend profiles
struct UserStats: Codable {
    let streak: Int
    let totalMiles: Double
    let fastestMilePace: Double
    let mostMilesInOneDay: Double

    init(streak: Int, totalMiles: Double, fastestMilePace: Double, mostMilesInOneDay: Double) {
        self.streak = streak
        self.totalMiles = totalMiles
        self.fastestMilePace = fastestMilePace
        self.mostMilesInOneDay = mostMilesInOneDay
    }

    init(from statsData: StatsService.StatsData) {
        self.streak = statsData.streak
        self.totalMiles = statsData.total_miles
        self.fastestMilePace = statsData.fastest_mile_pace
        self.mostMilesInOneDay = statsData.most_miles_in_one_day
    }
}
