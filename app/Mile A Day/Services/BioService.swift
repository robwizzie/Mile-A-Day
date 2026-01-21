import Foundation

class BioService {
    private static let backendURL = "https://mad.mindgoblin.tech"
    
    static func updateBio(_ bio: String, userId: String, authToken: String) async throws {
        let endpoint = "/users/\(userId)/bio"
        let body = ["bio": bio]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        
        struct Response: Codable {
            // Empty response expected
        }
        
        do {
            let _: Response = try await APIClient.fancyFetch(
                endpoint: endpoint,
                method: .PATCH,
                body: bodyData,
                responseType: Response.self
            )
        } catch let error as APIError {
            // Map APIError to BioError
            switch error {
            case .invalidURL:
                throw BioError.invalidURL
            case .invalidResponse, .networkError:
                throw BioError.networkError
            case .serverError:
                throw BioError.serverError("Server error")
            case .badRequest(let message):
                throw BioError.serverError(message)
            default:
                throw BioError.serverError(error.localizedDescription)
            }
        } catch {
            throw BioError.serverError(error.localizedDescription)
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
