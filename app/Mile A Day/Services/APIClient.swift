import Foundation

/// Centralized API client with automatic token refresh
class APIClient {
    private static let baseURL = "https://mad.mindgoblin.tech"
    
    /// Shared instance for accessing UserManager
    private static var userManager: UserManager? {
        // Try to get UserManager instance - this will need to be set by the app
        // For now, we'll access tokens directly from UserDefaults
        return nil
    }
    
    /// Fancy fetch that automatically handles token refresh
    /// - Parameters:
    ///   - endpoint: API endpoint (e.g., "/workouts/user123/recent")
    ///   - method: HTTP method (default: .GET)
    ///   - body: Request body data (optional)
    ///   - responseType: Type to decode response to
    /// - Returns: Decoded response of type T
    /// - Throws: APIError if request fails
    static func fancyFetch<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        // Step 1: Check if access token exists
        guard let accessToken = getAccessToken() else {
            print("[APIClient] ❌ No access token, signing out")
            signOutUser()
            throw APIError.notAuthenticated
        }

        // Step 2: Check if access token is expired
        if TokenUtils.isTokenExpired(accessToken) {
            print("[APIClient] 🔄 Access token expired, refreshing...")

            // Step 3: Check if refresh token exists
            guard let refreshToken = getRefreshToken() else {
                print("[APIClient] ❌ No refresh token available, signing out")
                signOutUser()
                throw APIError.notAuthenticated
            }

            // Step 4: Refresh tokens
            do {
                let (newAccessToken, newRefreshToken) = try await TokenRefreshService.refreshAccessToken(refreshToken: refreshToken)

                // Step 5: Update stored tokens
                updateTokens(accessToken: newAccessToken, refreshToken: newRefreshToken)

                // Use new access token for the request
                return try await makeRequest(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    accessToken: newAccessToken,
                    responseType: responseType
                )
            } catch {
                print("[APIClient] ❌ Token refresh failed, signing out: \(error)")
                signOutUser()
                throw APIError.tokenRefreshFailed
            }
        } else {
            // Token is valid, proceed with request
            return try await makeRequest(
                endpoint: endpoint,
                method: method,
                body: body,
                accessToken: accessToken,
                responseType: responseType
            )
        }
    }
    
    /// Make the actual HTTP request
    private static func makeRequest<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        body: Data?,
        accessToken: String,
        responseType: T.Type
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        // Hard timeouts so calls can never hang the UI forever (a save sheet
        // stuck on "Saving…" is worse than a clear error). 15s is enough for a
        // slow network but short enough to feel responsive.
        request.timeoutInterval = 15

        if let body = body {
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        print("[APIClient] 📊 \(method.rawValue) \(endpoint) - Status: \(httpResponse.statusCode)")
        
        // Handle different status codes
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            print("[APIClient] ❌ Unauthorized (401)")
            throw APIError.unauthorized
        case 400:
            if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorData["error"] {
                throw APIError.badRequest(errorMessage)
            }
            throw APIError.badRequest("Bad request")
        case 404:
            throw APIError.notFound
        case 409:
            if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorData["error"] {
                throw APIError.conflict(errorMessage)
            }
            throw APIError.conflict("Conflict")
        case 429:
            if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorData["error"] {
                throw APIError.rateLimited(errorMessage)
            }
            throw APIError.rateLimited("Slow down — try again in a bit")
        default:
            // Pull the server's `{ error: "..." }` body when present so callers
            // (and the user-facing alert) see the real reason instead of a bare
            // status code.
            if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorData["error"] {
                print("[APIClient] ❌ \(httpResponse.statusCode) \(endpoint): \(errorMessage)")
                throw APIError.apiError(errorMessage)
            }
            if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                print("[APIClient] ❌ \(httpResponse.statusCode) \(endpoint) body: \(body)")
            }
            throw APIError.serverError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(T.self, from: data)
        } catch let decodingError as DecodingError {
            // Log detailed decoding error for debugging
            switch decodingError {
            case .keyNotFound(let key, let context):
                print("[APIClient] ❌ Decode error - Missing key '\(key.stringValue)' at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
            case .valueNotFound(let type, let context):
                print("[APIClient] ❌ Decode error - Null value for type '\(type)' at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
            case .typeMismatch(let type, let context):
                print("[APIClient] ❌ Decode error - Type mismatch, expected '\(type)' at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
            case .dataCorrupted(let context):
                print("[APIClient] ❌ Decode error - Data corrupted at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
            @unknown default:
                print("[APIClient] ❌ Decode error - Unknown: \(decodingError)")
            }
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[APIClient] 📄 Raw response: \(jsonString.prefix(2000))")
            }
            throw decodingError
        }
    }
    
    // MARK: - Token Management Helpers
    
    private static func getAccessToken() -> String? {
        return UserDefaults.standard.string(forKey: "authToken")
    }
    
    private static func getRefreshToken() -> String? {
        return UserDefaults.standard.string(forKey: "refreshToken")
    }
    
    private static func updateTokens(accessToken: String, refreshToken: String) {
        UserManager.shared.setTokens(accessToken: accessToken, refreshToken: refreshToken)
        print("[APIClient] ✅ Tokens updated in storage")
    }

    private static func signOutUser() {
        DispatchQueue.main.async {
            UserManager.shared.signOut()
            AppStateManager.shared.signOut()
        }
    }
}

/// Errors that can occur during API requests
enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case notAuthenticated
    case unauthorized
    case badRequest(String)
    case conflict(String)
    case rateLimited(String)
    case notFound
    case serverError(Int)
    /// Server returned a non-2xx with a parseable `{ error: "..." }` body —
    /// preferred over `.serverError(Int)` so the user-facing message is the
    /// actual reason, not just a status code.
    case apiError(String)
    case tokenRefreshFailed
    case networkError(String)

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
        case .badRequest(let message):
            return "Bad request: \(message)"
        case .conflict(let message):
            return message
        case .rateLimited(let message):
            return message
        case .notFound:
            return "Resource not found"
        case .serverError(let code):
            return "Server error: \(code)"
        case .apiError(let message):
            return message
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

extension APIError {
    /// True for HTTP 429 responses.
    var isRateLimited: Bool {
        if case .rateLimited = self { return true }
        return false
    }
}

