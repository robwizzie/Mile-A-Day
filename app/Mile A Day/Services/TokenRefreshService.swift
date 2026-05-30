import Foundation

/// Service for refreshing access tokens using refresh tokens.
///
/// All refresh attempts funnel through `TokenRefreshCoordinator` (single-flight):
/// if multiple callers race to refresh at the same time, only one network call
/// is sent and every caller awaits the same result. This is essential because
/// the backend rotates refresh tokens on every refresh AND detects token reuse
/// — two concurrent refresh calls would present the same old token, the second
/// would be flagged as reuse, and the backend would revoke the entire token
/// family. That's the bug that was forcing users to fully log out and back in.
class TokenRefreshService {
    private static let baseURL = "https://mad.mindgoblin.tech"

    struct RefreshResponse: Codable {
        let accessToken: String
        let refreshToken: String
    }

    /// Refresh the access token using the refresh token.
    /// Coalesces concurrent callers into a single network request.
    static func refreshAccessToken(refreshToken: String) async throws -> (accessToken: String, refreshToken: String) {
        try await TokenRefreshCoordinator.shared.refresh(presentedRefreshToken: refreshToken)
    }

    /// Raw refresh call — only invoked by the coordinator. Do not call directly.
    fileprivate static func performRefresh(refreshToken: String) async throws -> (accessToken: String, refreshToken: String) {
        guard let url = URL(string: "\(baseURL)/auth/refresh") else {
            throw TokenRefreshError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body = ["refreshToken": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokenRefreshError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[TokenRefreshService] ❌ Refresh failed with status \(httpResponse.statusCode): \(errorMessage)")

            if httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
                throw TokenRefreshError.invalidRefreshToken
            }

            throw TokenRefreshError.serverError(httpResponse.statusCode)
        }

        do {
            let refreshResponse = try JSONDecoder().decode(RefreshResponse.self, from: data)
            print("[TokenRefreshService] ✅ Token refreshed successfully")
            return (refreshResponse.accessToken, refreshResponse.refreshToken)
        } catch {
            print("[TokenRefreshService] ❌ Failed to decode refresh response: \(error)")
            throw TokenRefreshError.decodingError
        }
    }
}

/// Serializes concurrent refresh attempts. If a refresh is already in flight,
/// new callers presenting the same refresh token await the in-flight result
/// instead of starting a parallel request (which would trigger backend
/// token-reuse detection and revoke the user's whole session).
///
/// Callers presenting a *different* refresh token (i.e. they already have a
/// newer rotated value) bypass the in-flight task and start their own.
actor TokenRefreshCoordinator {
    static let shared = TokenRefreshCoordinator()

    private var inFlight: (presentedToken: String, task: Task<(accessToken: String, refreshToken: String), Error>)?

    func refresh(presentedRefreshToken token: String) async throws -> (accessToken: String, refreshToken: String) {
        if let existing = inFlight, existing.presentedToken == token {
            print("[TokenRefreshCoordinator] ⏳ Awaiting in-flight refresh")
            return try await existing.task.value
        }

        let task = Task { try await TokenRefreshService.performRefresh(refreshToken: token) }
        inFlight = (token, task)

        defer {
            // Clear in-flight slot — but only if it's still ours (a newer
            // refresh may have replaced it while we awaited).
            if inFlight?.presentedToken == token {
                inFlight = nil
            }
        }

        return try await task.value
    }
}

/// Errors that can occur during token refresh
enum TokenRefreshError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidRefreshToken
    case serverError(Int)
    case decodingError
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidRefreshToken:
            return "Invalid or expired refresh token"
        case .serverError(let code):
            return "Server error: \(code)"
        case .decodingError:
            return "Failed to decode response"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
