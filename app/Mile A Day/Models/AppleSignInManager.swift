import AuthenticationServices
import Foundation
import SwiftUI

class AppleSignInManager: NSObject, ObservableObject {
    @Published var isSignedIn = false
    @Published var userProfile: AppleUserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let backendURL = "https://mad.mindgoblin.tech"
    private var currentDelegate: AppleSignInDelegate?

    struct AppleUserProfile {
        let id: String
        let email: String?
        let fullName: PersonNameComponents?
        let profileImage: UIImage?
    }

    struct BackendAuthResponse: Codable {
        let user: BackendUser
        let token: String
    }

    struct BackendUser: Codable {
        let user_id: String
        let username: String?
        let email: String
        let first_name: String?
        let last_name: String?
        let apple_id: String?
    }

    func signIn() async throws -> (AppleUserProfile, BackendAuthResponse) {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        // Add timeout to prevent infinite loading
        let result = try await withThrowingTaskGroup(of: ASAuthorization.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    let controller = ASAuthorizationController(authorizationRequests: [request])
                    
                    // Create delegate on main actor
                    Task { @MainActor in
                        let delegate = AppleSignInDelegate { [weak self] result in
                            self?.currentDelegate = nil  // Clear the delegate reference
                            continuation.resume(with: result)
                        }

                        // Retain the delegate to prevent it from being deallocated
                        self.currentDelegate = delegate
                        controller.delegate = delegate
                        controller.presentationContextProvider = delegate
                        controller.performRequests()
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)  // 30 second timeout
                throw AppleSignInError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        guard let appleIDCredential = result.credential as? ASAuthorizationAppleIDCredential else {
            throw AppleSignInError.invalidCredential
        }

        // Apple doesn't provide profile images through Sign in with Apple
        let profile = AppleUserProfile(
            id: appleIDCredential.user,
            email: appleIDCredential.email,
            fullName: appleIDCredential.fullName,
            profileImage: nil
        )

        // Send to backend
        let backendResponse = try await authenticateWithBackend(profile, appleIDCredential)

        await MainActor.run {
            self.userProfile = profile
            self.isSignedIn = true
            self.isLoading = false
        }

        return (profile, backendResponse)
    }

    private func authenticateWithBackend(
        _ profile: AppleUserProfile, _ credential: ASAuthorizationAppleIDCredential
    ) async throws -> BackendAuthResponse {
        // First, test if backend is reachable
        guard let testURL = URL(string: "\(backendURL)/status") else {
            throw AppleSignInError.invalidURL
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: testURL)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
            else {
                throw AppleSignInError.backendError("Backend server is not responding")
            }
        } catch {
            throw AppleSignInError.backendError(
                "Cannot connect to backend server: \(error.localizedDescription)")
        }

        // Convert identity token from Data to String
        let identityTokenString: String
        if let identityTokenData = credential.identityToken,
           let tokenString = String(data: identityTokenData, encoding: .utf8) {
            identityTokenString = tokenString
        } else {
            throw AppleSignInError.backendError("Failed to convert identity token to string")
        }
        
        // Convert authorization code from Data to String
        let authorizationCodeString: String
        if let authCodeData = credential.authorizationCode,
           let codeString = String(data: authCodeData, encoding: .utf8) {
            authorizationCodeString = codeString
        } else {
            throw AppleSignInError.backendError("Failed to convert authorization code to string")
        }
        
        let authData = [
            "user_id": profile.id,
            "identity_token": identityTokenString,
            "authorization_code": authorizationCodeString,
            "email": profile.email ?? "",
        ]

        guard let url = URL(string: "\(backendURL)/auth/signin") else {
            throw AppleSignInError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: authData)
        } catch {
            throw AppleSignInError.encodingError
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppleSignInError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AppleSignInError.backendError(errorMessage)
        }

        do {
            let backendResponse = try JSONDecoder().decode(BackendAuthResponse.self, from: data)
            return backendResponse
        } catch {
            throw AppleSignInError.decodingError
        }
    }

    enum AppleSignInError: Error, LocalizedError {
        case invalidCredential
        case cancelled
        case failed
        case invalidURL
        case encodingError
        case networkError
        case backendError(String)
        case decodingError
        case timeout

        var errorDescription: String? {
            switch self {
            case .invalidCredential:
                return "Invalid Apple Sign In credential"
            case .cancelled:
                return "Apple Sign In was cancelled"
            case .failed:
                return "Apple Sign In failed"
            case .invalidURL:
                return "Invalid backend URL"
            case .encodingError:
                return "Failed to encode request data"
            case .networkError:
                return "Network error occurred"
            case .backendError(let message):
                return "Backend error: \(message)"
            case .decodingError:
                return "Failed to decode backend response"
            case .timeout:
                return "Apple Sign In timed out"
            }
        }
    }
}

// Delegate to handle Apple Sign In callbacks
@MainActor
class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private let completion: (Result<ASAuthorization, Error>) -> Void

    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
        super.init()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        completion(.success(authorization))
    }

    func authorizationController(
        controller: ASAuthorizationController, didCompleteWithError error: Error
    ) {
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                completion(.failure(AppleSignInManager.AppleSignInError.cancelled))
            default:
                completion(.failure(AppleSignInManager.AppleSignInError.failed))
            }
        } else {
            completion(.failure(error))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first
        else {
            fatalError("No window found")
        }
        return window
    }
}
