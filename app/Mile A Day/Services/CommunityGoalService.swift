import Foundation
import Observation

/// `GET /users/:id/community-goal`. `goal` is nil between goals.
struct CommunityGoalResponse: Codable {
    let goal: CommunityGoal?
    let my_miles: Double
    let my_days: Int
}

struct CommunityGoal: Codable {
    let goal_id: String
    let title: String
    let description: String
    let target_miles: Double
    let starts_on: String
    let ends_on: String
    let days_left: Int
    /// `upcoming`, `active`, `counting` or `ended`. A plain string so a future
    /// state can't fail the decode; `phase` reads anything unknown as ended.
    let state: String
    let total_miles: Double
    let walkers: Int
    let percent: Int
    let checkpoints: [Checkpoint]
    let rewards: [Reward]
    let pace: Pace?

    struct Checkpoint: Codable, Identifiable {
        let percent: Int
        let name: String
        let fact: String
        let reached: Bool

        var id: Int { percent }
    }

    struct Reward: Codable, Identifiable {
        let days: Int
        let badge_id: String
        let item_id: String?
        let name: String
        let earned: Bool

        var id: String { badge_id }
    }

    /// Nil unless the goal is running.
    struct Pace: Codable {
        let status: String
        let miles_per_day_needed: Int
        let needs_more_walkers: Bool
    }

    enum Phase { case upcoming, active, counting, ended }

    var phase: Phase {
        switch state {
        case "upcoming": return .upcoming
        case "active": return .active
        case "counting": return .counting
        default: return .ended
        }
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dayLabel: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    /// "Dec 1"
    var startLabel: String {
        Self.dayParser.date(from: starts_on).map(Self.dayLabel.string(from:)) ?? starts_on
    }

    var reachedTarget: Bool { percent >= 100 }

    /// The one line every surface uses for where the goal stands.
    var statusLine: String {
        switch phase {
        case .upcoming: return "Starts \(startLabel)"
        case .active: return days_left == 1 ? "Last day" : "\(days_left) days left"
        case .counting: return "Final count in progress"
        case .ended: return reachedTarget ? "We made it" : "We walked \(percent)% of the way"
        }
    }

    var needsMoreWalkers: Bool { pace?.needs_more_walkers == true }

    /// The next tier still ahead of someone with this many days.
    func nextReward(days: Int) -> Reward? { rewards.first { !$0.earned && days < $0.days } }

    /// The next checkpoint ahead, or nil once they've all been reached.
    var nextCheckpoint: Checkpoint? { checkpoints.first { !$0.reached } }
}

/// Loads and caches the community goal. Snapshotted per user, so its card has
/// real content on a cold launch instead of popping in a second later.
@MainActor
@Observable
final class CommunityGoalService {
    static let shared = CommunityGoalService()

    private(set) var current: CommunityGoalResponse?

    @ObservationIgnored private let snapshotKey = "communityGoalSnapshotV1"
    @ObservationIgnored private let snapshotUserKey = "communityGoalSnapshotUserV1"
    @ObservationIgnored private var lastLoadedAt: Date?
    @ObservationIgnored private var isLoading = false

    private var userId: String? { UserDefaults.standard.string(forKey: "backendUserId") }

    private init() {
        let defaults = UserDefaults.standard
        guard let userId, defaults.string(forKey: snapshotUserKey) == userId,
              let data = defaults.data(forKey: snapshotKey) else { return }
        current = try? JSONDecoder().decode(CommunityGoalResponse.self, from: data)
    }

    /// Safe to call from every appearance: totals only change every 10 minutes.
    func refreshIfStale(maxAge: TimeInterval = 300) async {
        if let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < maxAge { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading, let userId, !userId.isEmpty, TokenStore.hasTokens else { return }
        isLoading = true
        defer { isLoading = false }
        // A failed read keeps what's on screen: the goal is never urgent.
        guard let response: CommunityGoalResponse = try? await APIClient.fancyFetch(
            endpoint: "/users/\(userId)/community-goal",
            responseType: CommunityGoalResponse.self
        ) else { return }
        current = response
        lastLoadedAt = Date()
        if let data = try? JSONEncoder().encode(response) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
            UserDefaults.standard.set(userId, forKey: snapshotUserKey)
        }
    }
}
