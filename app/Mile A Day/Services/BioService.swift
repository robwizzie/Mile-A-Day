import Foundation

class BioService {
    private static let backendURL = "https://mad.mindgoblin.tech"
    
    static func updateBio(_ bio: String, userId: String, authToken: String) async throws {
        guard let url = URL(string: "\(backendURL)/users/\(userId)/bio") else {
            throw BioError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let body = ["bio": bio]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BioError.networkError
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw BioError.serverError(errorMessage)
        }
    }
}

enum BioError: Error, LocalizedError {
    case invalidURL
    case networkError
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError:
            return "Network error occurred"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
