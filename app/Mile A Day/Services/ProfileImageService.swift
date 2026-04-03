import Foundation
import UIKit

class ProfileImageService {
    private static let baseURL = "https://mad.mindgoblin.tech"

    struct UploadResponse: Codable {
        let success: Bool
        let profileImageUrl: String
    }

    /// Uploads a profile image to the server and returns the image URL path
    static func uploadProfileImage(_ image: UIImage, userId: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/users/\(userId)/profile-image/upload") else {
            throw ProfileImageError.invalidURL
        }

        // Compress image to JPEG
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw ProfileImageError.compressionFailed
        }

        guard let accessToken = UserDefaults.standard.string(forKey: "authToken") else {
            throw ProfileImageError.notAuthenticated
        }

        // Build multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"profile.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProfileImageError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw ProfileImageError.serverError("Upload failed with status \(httpResponse.statusCode): \(responseBody)")
        }

        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
        return uploadResponse.profileImageUrl
    }

    /// Returns the full URL for a profile image path
    static func fullImageURL(for path: String?) -> URL? {
        guard let path = path, !path.isEmpty else { return nil }
        if path.hasPrefix("http") {
            return URL(string: path)
        }
        return URL(string: "\(baseURL)\(path)")
    }
}

enum ProfileImageError: Error, LocalizedError {
    case invalidURL
    case compressionFailed
    case notAuthenticated
    case networkError
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .compressionFailed:
            return "Failed to compress image"
        case .notAuthenticated:
            return "Not authenticated"
        case .networkError:
            return "Network error occurred"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
