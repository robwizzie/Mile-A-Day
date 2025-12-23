import Foundation

/// Service for refreshing access tokens using refresh tokens
class TokenRefreshService {
    private static let baseURL = "https://mad.mindgoblin.tech"
    
    /// Response from refresh endpoint
    struct RefreshResponse: Codable {
        let accessToken: String
        let refreshToken: String
    }
    
    /// Refresh the access token using the refresh token
    /// - Parameter refreshToken: The refresh token to use
    /// - Returns: A tuple containing the new access token and refresh token
    /// - Throws: TokenRefreshError if refresh fails
    static func refreshAccessToken(refreshToken: String) async throws -> (accessToken: String, refreshToken: String) {
        guard let url = URL(string: "\(baseURL)/auth/refresh") else {
            throw TokenRefreshError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["refreshToken": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokenRefreshError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[TokenRefreshService] ❌ Refresh failed with status \(httpResponse.statusCode): \(errorMessage)")
            
            if httpResponse.statusCode == 403 {
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

