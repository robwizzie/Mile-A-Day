import Foundation
import UIKit

class ProfileImageService {
    private static let baseURL = AppConfig.baseURL

    struct UploadResponse: Codable {
        let success: Bool
        let profileImageUrl: String
    }

    struct BannerUploadResponse: Codable {
        let success: Bool
        let profileBannerUrl: String
    }

    /// Uploads a profile image to the server and returns the image URL path
    static func uploadProfileImage(_ image: UIImage, userId: String) async throws -> String {
        let data = try await uploadJPEG(
            image,
            endpoint: "/users/\(userId)/profile-image/upload",
            filename: "profile.jpg",
            quality: 0.7
        )
        return try JSONDecoder().decode(UploadResponse.self, from: data).profileImageUrl
    }

    // Phone-only: UIGraphicsImageRenderer doesn't exist on watchOS, and the
    // watch never uploads a banner.
    #if !os(watchOS)
    /// Uploads a profile banner (the header behind the avatar). The server
    /// center-crops to 3:1, so no cropper is needed client-side; the photo is
    /// downscaled first because a full-resolution camera-roll shot can exceed
    /// the upload limit that the 512px avatar never approached.
    static func uploadProfileBanner(_ image: UIImage, userId: String) async throws -> String {
        let data = try await uploadJPEG(
            image.downscaled(maxDimension: 2400),
            endpoint: "/users/\(userId)/banner/upload",
            filename: "banner.jpg",
            quality: 0.82
        )
        return try JSONDecoder().decode(BannerUploadResponse.self, from: data).profileBannerUrl
    }
    #endif

    /// One multipart JPEG upload for both the avatar and the banner endpoints.
    private static func uploadJPEG(
        _ image: UIImage,
        endpoint: String,
        filename: String,
        quality: CGFloat
    ) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw ProfileImageError.invalidURL
        }

        guard let imageData = image.jpegData(compressionQuality: quality) else {
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
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProfileImageError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            throw ProfileImageError.serverError("Upload failed with status \(httpResponse.statusCode)")
        }

        return data
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

#if !os(watchOS)
private extension UIImage {
    /// The image scaled so its longer side is at most `maxDimension` points;
    /// returns self when it already fits.
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let ratio = maxDimension / longest
        let target = CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
#endif
