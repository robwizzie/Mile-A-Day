import Foundation
import SwiftUI

/// Service for handling all competition-related API operations
@MainActor
class CompetitionService: ObservableObject {

    // MARK: - Published Properties
    @Published var competitions: [Competition] = []
    @Published var invites: [Competition] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private Properties
    private let baseURL = "https://mad.mindgoblin.tech"
    private var authToken: String?

    // MARK: - Initialization
    init() {
        // Load auth token from UserDefaults
        self.authToken = UserDefaults.standard.string(forKey: "authToken")
    }

    // MARK: - Authentication
    func setAuthToken(_ token: String) {
        self.authToken = token
        UserDefaults.standard.set(token, forKey: "authToken")
    }

    func clearAuthToken() {
        self.authToken = nil
        UserDefaults.standard.removeObject(forKey: "authToken")
    }

    // MARK: - Private Helper Methods
    private func makeRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        do {
            return try await APIClient.fancyFetch(
                endpoint: endpoint,
                method: method,
                body: body,
                responseType: responseType
            )
        } catch let error as APIError {
            // Map APIError to CompetitionServiceError
            switch error {
            case .invalidURL:
                throw CompetitionServiceError.invalidURL
            case .invalidResponse:
                throw CompetitionServiceError.invalidResponse
            case .notAuthenticated:
                throw CompetitionServiceError.notAuthenticated
            case .unauthorized:
                throw CompetitionServiceError.unauthorized
            case .badRequest(let message):
                throw CompetitionServiceError.apiError(message)
            case .serverError(let code):
                throw CompetitionServiceError.serverError(code)
            case .tokenRefreshFailed:
                throw CompetitionServiceError.notAuthenticated
            case .networkError(let message):
                throw CompetitionServiceError.networkError(message)
            case .notFound:
                throw CompetitionServiceError.competitionNotFound
            }
        } catch let error as DecodingError {
            print("[CompetitionService] ❌ Decoding error: \(error)")
            throw CompetitionServiceError.networkError(error.localizedDescription)
        } catch {
            throw CompetitionServiceError.networkError(error.localizedDescription)
        }
    }

    // MARK: - Competition CRUD Operations

    /// Create a new competition (lobby mode - no start_date)
    func createCompetition(
        name: String,
        type: CompetitionType,
        workouts: [CompetitionActivity],
        goal: Double,
        unit: CompetitionUnit,
        firstTo: Int,
        history: Bool,
        interval: CompetitionInterval,
        durationHours: Int?
    ) async throws -> String {
        print("[CompetitionService] Creating competition: \(name)")

        let request = CreateCompetitionRequest(
            competition_name: name,
            type: type,
            start_date: nil,
            end_date: nil,
            workouts: workouts,
            options: CompetitionOptionsRequest(
                goal: goal,
                unit: unit,
                first_to: firstTo,
                history: history,
                interval: interval,
                duration_hours: durationHours
            )
        )

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(request)

        let response: CreateCompetitionResponse = try await makeRequest(
            endpoint: "/competitions",
            method: .POST,
            body: jsonData,
            responseType: CreateCompetitionResponse.self
        )

        print("[CompetitionService] Competition created: \(response.competition_id)")

        // Refresh competitions list
        try await loadCompetitions()

        return response.competition_id
    }

    /// Get all competitions for the authenticated user
    func loadCompetitions(page: Int = 1, pageSize: Int = 25, status: String? = nil) async throws {
        print("[CompetitionService] Loading competitions")

        var endpoint = "/competitions?page=\(page)&pageSize=\(pageSize)"
        if let status = status {
            endpoint += "&status=\(status)"
        }

        let response: CompetitionsListResponse = try await makeRequest(
            endpoint: endpoint,
            responseType: CompetitionsListResponse.self
        )

        competitions = response.competitions
        print("[CompetitionService] Loaded \(competitions.count) competitions")
    }

    /// Get a specific competition
    func loadCompetition(id: String) async throws -> Competition {
        print("[CompetitionService] Loading competition: \(id)")

        let response: CompetitionResponse = try await makeRequest(
            endpoint: "/competitions/\(id)",
            responseType: CompetitionResponse.self
        )

        print("[CompetitionService] Competition loaded: \(response.competition.competition_name)")
        return response.competition
    }

    /// Update a competition
    func updateCompetition(
        id: String,
        name: String? = nil,
        type: CompetitionType? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        workouts: [CompetitionActivity]? = nil,
        goal: Double? = nil,
        unit: CompetitionUnit? = nil,
        firstTo: Int? = nil,
        history: Bool? = nil,
        interval: CompetitionInterval? = nil
    ) async throws -> Competition {
        print("[CompetitionService] Updating competition: \(id)")

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        let request = UpdateCompetitionRequest(
            competition_name: name,
            type: type,
            start_date: startDate.map { dateFormatter.string(from: $0) },
            end_date: endDate.map { dateFormatter.string(from: $0) },
            workouts: workouts,
            options: PartialCompetitionOptionsRequest(
                goal: goal,
                unit: unit,
                first_to: firstTo,
                history: history,
                interval: interval
            )
        )

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(request)

        let response: CompetitionResponse = try await makeRequest(
            endpoint: "/competitions/\(id)",
            method: .PATCH,
            body: jsonData,
            responseType: CompetitionResponse.self
        )

        print("[CompetitionService] Competition updated")

        // Update local cache
        if let index = competitions.firstIndex(where: { $0.competition_id == id }) {
            competitions[index] = response.competition
        }

        return response.competition
    }

    /// Start a competition (owner only, requires 2+ accepted participants)
    /// Starts at the beginning of the next day to avoid mid-day edge cases
    func startCompetition(id: String) async throws -> Competition {
        // Calculate tomorrow midnight in ISO8601 format
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date())!)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let startDateStr = formatter.string(from: tomorrow)

        print("[CompetitionService] Starting competition: \(id) with start_date: \(startDateStr)")

        let body: [String: String] = ["start_date": startDateStr]
        let jsonData = try JSONEncoder().encode(body)

        let response: CompetitionResponse = try await makeRequest(
            endpoint: "/competitions/\(id)/start",
            method: .POST,
            body: jsonData,
            responseType: CompetitionResponse.self
        )

        print("[CompetitionService] Competition started successfully")

        // Update local cache
        if let index = competitions.firstIndex(where: { $0.competition_id == id }) {
            competitions[index] = response.competition
        }

        return response.competition
    }

    /// Delete a competition (owner only)
    func deleteCompetition(id: String) async throws {
        print("[CompetitionService] Deleting competition: \(id)")

        let _: DeleteCompetitionResponse = try await makeRequest(
            endpoint: "/competitions/\(id)",
            method: .DELETE,
            responseType: DeleteCompetitionResponse.self
        )

        print("[CompetitionService] Competition deleted")

        // Remove from local cache
        competitions.removeAll { $0.competition_id == id }
    }

    // MARK: - Competition Invitations

    /// Get all pending invites
    func loadInvites(page: Int = 1) async throws {
        print("[CompetitionService] Loading invites")

        let response: CompetitionInvitesResponse = try await makeRequest(
            endpoint: "/competitions/invites?page=\(page)",
            responseType: CompetitionInvitesResponse.self
        )

        invites = response.competitionInvites
        print("[CompetitionService] Loaded \(invites.count) invites")
    }

    /// Invite a user to a competition
    func inviteUser(competitionId: String, userId: String) async throws {
        print("[CompetitionService] Inviting user \(userId) to competition \(competitionId)")

        let request = InviteUserRequest(inviteUser: userId)
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(request)

        let _: InviteUserResponse = try await makeRequest(
            endpoint: "/competitions/\(competitionId)/invite",
            method: .POST,
            body: jsonData,
            responseType: InviteUserResponse.self
        )

        print("[CompetitionService] User invited successfully")

        // Refresh competition to get updated user list
        let updatedCompetition = try await loadCompetition(id: competitionId)
        if let index = competitions.firstIndex(where: { $0.competition_id == competitionId }) {
            competitions[index] = updatedCompetition
        }
    }

    /// Accept a competition invite
    func acceptInvite(competitionId: String) async throws {
        print("[CompetitionService] Accepting invite for competition \(competitionId)")

        let response: CompetitionResponse = try await makeRequest(
            endpoint: "/competitions/\(competitionId)/accept",
            method: .POST,
            responseType: CompetitionResponse.self
        )

        print("[CompetitionService] Invite accepted")

        // Remove from invites and add to competitions
        invites.removeAll { $0.competition_id == competitionId }
        if !competitions.contains(where: { $0.competition_id == competitionId }) {
            competitions.append(response.competition)
        }
    }

    /// Decline a competition invite
    func declineInvite(competitionId: String) async throws {
        print("[CompetitionService] Declining invite for competition \(competitionId)")

        let _: CompetitionResponse = try await makeRequest(
            endpoint: "/competitions/\(competitionId)/decline",
            method: .POST,
            responseType: CompetitionResponse.self
        )

        print("[CompetitionService] Invite declined")

        // Remove from invites
        invites.removeAll { $0.competition_id == competitionId }
    }

    // MARK: - Social Actions (Flex / Nudge)

    /// Send a "flex" to all competitors in a competition (once per day)
    func sendFlex(competitionId: String) async throws {
        print("[CompetitionService] Sending flex for competition \(competitionId)")

        let _: FlexNudgeResponse = try await makeRequest(
            endpoint: "/competitions/\(competitionId)/flex",
            method: .POST,
            responseType: FlexNudgeResponse.self
        )

        print("[CompetitionService] Flex sent successfully")
    }

    /// Send a "nudge" to a specific user in a competition (once per user per day)
    func sendNudge(competitionId: String, targetUserId: String) async throws {
        print("[CompetitionService] Sending nudge to \(targetUserId) in competition \(competitionId)")

        let body = ["targetUserId": targetUserId]
        let jsonData = try JSONEncoder().encode(body)

        let _: FlexNudgeResponse = try await makeRequest(
            endpoint: "/competitions/\(competitionId)/nudge",
            method: .POST,
            body: jsonData,
            responseType: FlexNudgeResponse.self
        )

        print("[CompetitionService] Nudge sent successfully")
    }

    // MARK: - Convenience Methods

    /// Refresh all competition data
    func refreshAllData() async {
        isLoading = true
        errorMessage = nil

        do {
            // Run all operations concurrently
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.loadCompetitions()
                }
                group.addTask {
                    try await self.loadInvites()
                }

                // Wait for all tasks to complete
                for try await _ in group {}
            }

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Get current user ID from UserDefaults
    private func getCurrentUserId() -> String? {
        return UserDefaults.standard.string(forKey: "backendUserId")
    }

    /// Check if the current user is the owner of a competition
    func isOwner(of competition: Competition) -> Bool {
        guard let currentUserId = getCurrentUserId() else {
            return false
        }
        return competition.owner == currentUserId
    }

    /// Get the current user's invite status for a competition
    func getInviteStatus(for competition: Competition) -> InviteStatus? {
        guard let currentUserId = getCurrentUserId() else {
            return nil
        }
        return competition.users.first(where: { $0.user_id == currentUserId })?.invite_status
    }
}

// MARK: - Error Types
enum CompetitionServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case notAuthenticated
    case unauthorized
    case competitionNotFound
    case badRequest
    case serverError(Int)
    case networkError(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .notAuthenticated:
            return "User not authenticated"
        case .unauthorized:
            return "Unauthorized access"
        case .competitionNotFound:
            return "Competition not found"
        case .badRequest:
            return "Bad request"
        case .serverError(let code):
            return "Server error: \(code)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .apiError(let message):
            return message
        }
    }
}
