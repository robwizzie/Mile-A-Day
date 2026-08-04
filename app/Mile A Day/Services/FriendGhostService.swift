import Foundation
import SwiftUI

/// One friend you can race, from `GET /ghosts/friends`.
///
/// Plain snake_case properties with NO explicit `CodingKeys` — a struct with
/// one loses Codable synthesis the moment a stored property is added without a
/// matching case, and there's no iOS CI to catch it.
struct FriendGhost: Codable, Identifiable, Equatable {
    let user_id: String
    let username: String?
    let first_name: String?
    let last_name: String?
    let profile_image_url: String?
    /// Their fastest completed mile, in seconds.
    let mile_seconds: Double

    var id: String { user_id }

    /// What to call them in the picker and, once armed, in the live chip and
    /// the celebration — so it has to stay short.
    var displayName: String {
        if let first_name, !first_name.isEmpty { return first_name }
        if let username, !username.isEmpty { return username }
        return "A friend"
    }

    /// Full name for the avatar's initials fallback — usernames make noisy
    /// initials, which is why the leaderboard rows do the same.
    var avatarName: String {
        let parts = [first_name, last_name].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? displayName : parts.joined(separator: " ")
    }

    var target: BestEffortStore.GhostTarget {
        .friend(id: user_id, seconds: mile_seconds, name: displayName)
    }
}

private struct FriendGhostsResponse: Decodable {
    let ghosts: [FriendGhost]
}

/// Loads the friends whose mile you can chase, cached per activity.
///
/// A shared singleton because `GhostRaceOptionsContent` renders in two places —
/// the pre-start wizard step and the buddy lobby sheet — and both should hit
/// one load path and one cache rather than each fetching on appear.
@MainActor
final class FriendGhostService: ObservableObject {
    static let shared = FriendGhostService()

    /// Cached per activity key ("running" / "walking"). The two are genuinely
    /// different lists: a friend's fastest RUN mile is not a fair walk ghost,
    /// and the server filters on `workout_type` for exactly that reason.
    @Published private(set) var ghostsByActivity: [String: [FriendGhost]] = [:]
    @Published private(set) var isLoading = false

    /// Last successful load per activity, so re-opening the picker inside a
    /// session doesn't re-fetch.
    private var loadedAt: [String: Date] = [:]
    private let cacheLifetime: TimeInterval = 5 * 60

    private init() {}

    func ghosts(for activityKey: String) -> [FriendGhost] {
        ghostsByActivity[activityKey] ?? []
    }

    /// Load if the cache is cold or stale. Failures are silent by design: the
    /// picker always has your own targets, so a friend list that didn't arrive
    /// costs a row, not the feature.
    func refreshIfNeeded(activityKey: String) async {
        if let at = loadedAt[activityKey], Date().timeIntervalSince(at) < cacheLifetime {
            return
        }
        await refresh(activityKey: activityKey)
    }

    func refresh(activityKey: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            // Enum-ish literal, no free text — nothing here needs percent
            // encoding (same reasoning as LeaderboardService).
            let response: FriendGhostsResponse = try await APIClient.fancyFetch(
                endpoint: "/ghosts/friends?activity=\(activityKey)",
                method: .GET,
                body: nil,
                responseType: FriendGhostsResponse.self
            )
            ghostsByActivity[activityKey] = response.ghosts
            loadedAt[activityKey] = Date()
        } catch {
            // Leave whatever was cached in place.
            print("[FriendGhostService] load failed: \(error)")
        }
    }
}
