import Foundation
import SwiftUI

/// Service for handling all friend-related API operations
@MainActor
class FriendService: ObservableObject {
    
    // MARK: - Published Properties
    @Published var friends: [BackendUser] = []
    @Published var friendRequests: [BackendUser] = []
    @Published var sentRequests: [BackendUser] = []
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
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw FriendServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FriendServiceError.invalidResponse
            }
            
            // Handle different status codes
            switch httpResponse.statusCode {
            case 200...299:
                break
            case 401:
                throw FriendServiceError.unauthorized
            case 404:
                throw FriendServiceError.userNotFound
            case 400:
                // Try to parse error message from response
                if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
                   let errorMessage = errorData["error"] {
                    throw FriendServiceError.apiError(errorMessage)
                }
                throw FriendServiceError.badRequest
            default:
                throw FriendServiceError.serverError(httpResponse.statusCode)
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            return try decoder.decode(T.self, from: data)
            
        } catch let error as FriendServiceError {
            throw error
        } catch {
            throw FriendServiceError.networkError(error.localizedDescription)
        }
    }
    
    // MARK: - Friend Search
    /// Search for users by exact username
    func searchUser(byUsername username: String) async throws -> BackendUser {
        let endpoint = "/users/search?username=\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username)"
        return try await makeRequest(endpoint: endpoint, responseType: BackendUser.self)
    }
    
    /// Search for users by partial username (returns multiple results)
    func searchUsersByPartialUsername(_ username: String) async throws -> [BackendUser] {
        let endpoint = "/users/search-partial?username=\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username)"
        return try await makeRequest(endpoint: endpoint, responseType: [BackendUser].self)
    }
    
    /// Search for users by email
    func searchUser(byEmail email: String) async throws -> BackendUser {
        let endpoint = "/users/search?email=\(email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email)"
        return try await makeRequest(endpoint: endpoint, responseType: BackendUser.self)
    }
    
    // MARK: - Friend Management
    /// Send a friend request
    func sendFriendRequest(to user: BackendUser) async throws {
        guard let currentUserId = getCurrentUserId() else {
            throw FriendServiceError.notAuthenticated
        }
        
        let endpoint = "/friendships/request"
        let body = [
            "fromUser": currentUserId,
            "toUser": user.user_id
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        
        struct Response: Codable {
            let message: String
        }
        
        let _: Response = try await makeRequest(
            endpoint: endpoint,
            method: .POST,
            body: jsonData,
            responseType: Response.self
        )
    }
    
    /// Get all friends
    func loadFriends() async throws {
        guard let currentUserId = getCurrentUserId() else {
            throw FriendServiceError.notAuthenticated
        }
        
        let endpoint = "/friendships/\(currentUserId)"
        friends = try await makeRequest(endpoint: endpoint, responseType: [BackendUser].self)
    }
    
    /// Get incoming friend requests
    func loadFriendRequests() async throws {
        guard let currentUserId = getCurrentUserId() else {
            throw FriendServiceError.notAuthenticated
        }
        
        let endpoint = "/friendships/requests/\(currentUserId)"
        let response: FriendRequestsResponse = try await makeRequest(endpoint: endpoint, responseType: FriendRequestsResponse.self)
        
        friendRequests = response.requests
    }
    
    /// Get sent friend requests
    func loadSentRequests() async throws {
        guard let currentUserId = getCurrentUserId() else {
            throw FriendServiceError.notAuthenticated
        }
        
        let endpoint = "/friendships/sent-requests/\(currentUserId)"
        sentRequests = try await makeRequest(endpoint: endpoint, responseType: [BackendUser].self)
    }
    
    /// Accept a friend request
    func acceptFriendRequest(from user: BackendUser) async throws {
        guard let currentUserId = getCurrentUserId() else {
            throw FriendServiceError.notAuthenticated
        }
        
        let endpoint = "/friendships/accept"
        let body = [
            "fromUser": user.user_id,
            "toUser": currentUserId
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        
        struct Response: Codable {
            let message: String
        }
        
        let _: Response = try await makeRequest(
            endpoint: endpoint,
            method: .PATCH,
            body: jsonData,
            responseType: Response.self
        )
        
        // Remove from friend requests and add to friends
        friendRequests.removeAll { $0.user_id == user.user_id }
        friends.append(user)
    }
    
    /// Decline a friend request
    func declineFriendRequest(from user: BackendUser) async throws {
        guard let currentUserId = getCurrentUserId() else {
            throw FriendServiceError.notAuthenticated
        }
        
        let endpoint = "/friendships/decline"
        let body = [
            "fromUser": user.user_id,
            "toUser": currentUserId
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        
        struct Response: Codable {
            let message: String
        }
        
        let _: Response = try await makeRequest(
            endpoint: endpoint,
            method: .DELETE,
            body: jsonData,
            responseType: Response.self
        )
        
        // Remove from friend requests
        friendRequests.removeAll { $0.user_id == user.user_id }
    }
    
    /// Ignore a friend request
    func ignoreFriendRequest(from user: BackendUser) async throws {
        guard let currentUserId = getCurrentUserId() else {
            throw FriendServiceError.notAuthenticated
        }
        
        let endpoint = "/friendships/ignore"
        let body = [
            "fromUser": user.user_id,
            "toUser": currentUserId
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        
        struct Response: Codable {
            let message: String
        }
        
        let _: Response = try await makeRequest(
            endpoint: endpoint,
            method: .PATCH,
            body: jsonData,
            responseType: Response.self
        )
        
        // Remove from friend requests
        friendRequests.removeAll { $0.user_id == user.user_id }
    }
    
    /// Remove a friend
    func removeFriend(_ user: BackendUser) async throws {
        guard let currentUserId = getCurrentUserId() else {
            throw FriendServiceError.notAuthenticated
        }
        
        let endpoint = "/friendships/remove"
        let body = [
            "fromUser": currentUserId,
            "toUser": user.user_id
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        
        struct Response: Codable {
            let message: String
        }
        
        let _: Response = try await makeRequest(
            endpoint: endpoint,
            method: .DELETE,
            body: jsonData,
            responseType: Response.self
        )
        
        // Remove from friends
        friends.removeAll { $0.user_id == user.user_id }
    }
    
    /// Cancel a sent friend request
    func cancelFriendRequest(to user: BackendUser) async throws {
        guard let currentUserId = getCurrentUserId() else {
            throw FriendServiceError.notAuthenticated
        }
        
        let endpoint = "/friendships/decline"
        let body = [
            "fromUser": currentUserId,
            "toUser": user.user_id
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        
        struct Response: Codable {
            let message: String
        }
        
        let _: Response = try await makeRequest(
            endpoint: endpoint,
            method: .DELETE,
            body: jsonData,
            responseType: Response.self
        )
        
        // Remove from sent requests
        sentRequests.removeAll { $0.user_id == user.user_id }
    }
    
    // MARK: - Convenience Methods
    /// Refresh all friend data
    func refreshAllData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Run all operations concurrently
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.loadFriends()
                }
                group.addTask {
                    try await self.loadFriendRequests()
                }
                group.addTask {
                    try await self.loadSentRequests()
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
    
    /// Check if a user is a friend
    func isFriend(_ user: BackendUser) -> Bool {
        return friends.contains { $0.user_id == user.user_id }
    }
    
    /// Check if there's a pending request from a user
    func hasPendingRequest(from user: BackendUser) -> Bool {
        return friendRequests.contains { $0.user_id == user.user_id }
    }
    
    /// Check if there's a sent request to a user
    func hasSentRequest(to user: BackendUser) -> Bool {
        return sentRequests.contains { $0.user_id == user.user_id }
    }
    
    /// Get friendship status with a user
    func getFriendshipStatus(with user: BackendUser) -> FriendshipStatus? {
        if isFriend(user) {
            return .accepted
        } else if hasPendingRequest(from: user) {
            return .pending
        } else if hasSentRequest(to: user) {
            return .pending
        }
        return nil
    }
}

// MARK: - HTTP Methods
enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PATCH = "PATCH"
    case DELETE = "DELETE"
}

// MARK: - Error Types
enum FriendServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case notAuthenticated
    case unauthorized
    case userNotFound
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
        case .userNotFound:
            return "User not found"
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