import Foundation
import Observation
import UIKit

/// `GET /users/:id/referrals`.
struct ReferralStatus: Codable {
    let username: String?
    let days_needed: Int
    let window_days: Int
    let qualified: Int
    let has_plus: Bool
    let can_add_referrer: Bool
    let referred_by: ReferredBy?
    let friends: [Friend]
    let rewards: [Reward]

    struct ReferredBy: Codable {
        let username: String?
        let first_name: String?
        let status: String
        let days: Int
    }

    struct Friend: Codable, Identifiable {
        let username: String?
        let first_name: String?
        let profile_image_url: String?
        let status: String
        let days: Int

        var id: String { username ?? first_name ?? UUID().uuidString }
        var displayName: String { first_name ?? username ?? "Friend" }
    }

    struct Reward: Codable, Identifiable {
        let count: Int
        let kind: String
        let title: String
        let description: String
        let item_id: String?
        let state: String
        let code: String?

        var id: Int { count }
        var isReached: Bool { state != "locked" }
    }

    /// The next reward still ahead, for "2 more for ...".
    var nextReward: Reward? { rewards.first { !$0.isReached } }
}

/// Loads referrals and carries out the two things a person can do with them.
@MainActor
@Observable
final class ReferralService {
    static let shared = ReferralService()

    private(set) var status: ReferralStatus?

    private var userId: String? { UserDefaults.standard.string(forKey: "backendUserId") }

    private struct CodeResponse: Decodable { let code: String }

    func refresh() async {
        guard let userId, !userId.isEmpty, TokenStore.hasTokens else { return }
        guard let fresh: ReferralStatus = try? await APIClient.fancyFetch(
            endpoint: "/users/\(userId)/referrals",
            responseType: ReferralStatus.self
        ) else { return }
        status = fresh
    }

    /// Links this account to the person who referred it.
    func setReferrer(username: String) async throws {
        guard let userId, !userId.isEmpty else { return }
        let body = try JSONSerialization.data(withJSONObject: ["username": username])
        status = try await APIClient.fancyFetch(
            endpoint: "/users/\(userId)/referrals/referrer",
            method: .POST,
            body: body,
            responseType: ReferralStatus.self
        )
    }

    /// Fetches the free-year code and opens Apple's redemption page with it.
    func redeemFreeYear() async throws {
        guard let userId, !userId.isEmpty else { return }
        let response: CodeResponse = try await APIClient.fancyFetch(
            endpoint: "/users/\(userId)/referrals/free-year",
            method: .POST,
            responseType: CodeResponse.self
        )
        await refresh()
        Self.openRedemption(code: response.code)
    }

    static func openRedemption(code: String) {
        guard let escaped = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://apps.apple.com/redeem?ctx=offercodes&id=6746970905&code=\(escaped)")
        else { return }
        UIApplication.shared.open(url)
    }

    /// An email to support, already saying who's asking.
    static func supportURL(username: String?) -> URL? {
        let who = username.map { "@\($0)" } ?? "my account"
        let body = "Hi, I need help with a referral.\n\nMy account: \(who)\nThe friend's username:\nWhat went wrong:\n"
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = "support@mileaday.run"
        parts.queryItems = [
            URLQueryItem(name: "subject", value: "Mile A Day referral help"),
            URLQueryItem(name: "body", value: body)
        ]
        return parts.url
    }
}
