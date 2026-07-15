import Foundation

/// Sends the optional onboarding personalization answers (referral source,
/// primary goal, experience level) captured on the signup "about you" step.
///
/// All fields are optional — the caller may pass `nil` for every field on a
/// pure "Skip", which still stamps `onboarding_completed_at` on the backend so
/// the step is recorded as complete. Routed through `APIClient.fancyFetch` so
/// auth and token refresh are handled automatically.
enum OnboardingService {
    private struct OnboardingResponse: Decodable { let success: Bool }

    /// PATCH /users/:userId/onboarding. Only non-empty fields are sent; the
    /// backend ignores absent keys instead of nulling existing values.
    static func submit(
        userId: String,
        referralSource: String?,
        referralDetail: String?,
        signupGoal: String?,
        experienceLevel: String?
    ) async throws {
        var payload: [String: String] = [:]
        if let referralSource, !referralSource.isEmpty { payload["referral_source"] = referralSource }
        if let referralDetail, !referralDetail.isEmpty { payload["referral_detail"] = referralDetail }
        if let signupGoal, !signupGoal.isEmpty { payload["signup_goal"] = signupGoal }
        if let experienceLevel, !experienceLevel.isEmpty { payload["experience_level"] = experienceLevel }

        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await APIClient.fancyFetch(
            endpoint: "/users/\(userId)/onboarding",
            method: .PATCH,
            body: body,
            responseType: OnboardingResponse.self
        )
    }
}
