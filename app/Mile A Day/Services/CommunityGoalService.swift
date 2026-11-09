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
    /// People who added miles on their own today. Optional: older servers
    /// don't send it, and it's null outside an active goal.
    let walkers_today: Int?
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
        var rarity: String? = nil

        var id: String { badge_id }
    }

    /// Nil unless the goal is running.
    struct Pace: Codable {
        let status: String
        let miles_per_day_needed: Int
        let needs_more_walkers: Bool
        /// Where today's rate ends up. Nil in the first days of a goal.
        let projected_miles: Int?
        /// "2026-12-26", when the rate reaches the target.
        let projected_finish: String?
        /// More people at the average rate who would close the gap.
        let walkers_needed: Int?
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

    var onPace: Bool { (pace?.projected_miles).map { Double($0) >= target_miles } ?? false }

    /// Will we get there? Nil when it's too early to say.
    var paceLine: String? {
        guard phase == .active, !reachedTarget, let projected = pace?.projected_miles else { return nil }
        if onPace {
            let day = pace?.projected_finish.flatMap(Self.dayParser.date(from:)).map(Self.dayLabel.string(from:))
            return day.map { "On pace to finish by \($0)" } ?? "On pace to finish"
        }
        let short = target_miles - Double(projected)
        return "At this pace: \(CommunityGoalCopy.whole(Double(projected))), \(CommunityGoalCopy.whole(short)) short"
    }

    /// Fewer than this reads as an empty room, so the line waits.
    static let walkingTodayMinimum = 3

    /// "214 walked today". Nil until enough people have, so it never looks quiet.
    var walkingTodayLine: String? {
        guard phase == .active, let n = walkers_today, n >= Self.walkingTodayMinimum else { return nil }
        return "\(n.formatted()) walked today"
    }

    /// How to get there sooner. Nil once it's no longer in anyone's hands.
    var inviteLine: String? {
        switch phase {
        case .upcoming: return "More walkers, more miles. Bring a friend."
        case .active where !reachedTarget:
            if !onPace, let needed = pace?.walkers_needed {
                return needed == 1 ? "1 more walker gets us there" : "\(needed) more walkers get us there"
            }
            return "Every new walker gets us there sooner"
        default: return nil
        }
    }

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
