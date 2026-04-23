import Foundation
import Combine

/// Persistence + query interface for daily-challenge completions.
///
/// Today backed by UserDefaults via `LocalChallengeService`. A `RemoteChallengeService`
/// backed by the backend can be swapped into `ChallengeService.shared` later without
/// touching callers.
protocol ChallengeServiceProtocol {
    func recordCompletion(_ completion: ChallengeCompletion)
    func allCompletions() -> [ChallengeCompletion]
    func completion(on date: Date) -> ChallengeCompletion?
    /// Consecutive calendar-day streak of completions, anchored to today or yesterday.
    /// Today counts if completed; otherwise the streak is measured from yesterday backwards.
    func currentChallengeStreak() -> Int
}

enum ChallengeService {
    static let changedNotification = Notification.Name("ChallengeServiceChanged")

    /// Shared instance. Replace the assignment here when a remote implementation lands.
    static let shared: ChallengeServiceProtocol = LocalChallengeService()

    /// One-time cleanup for users who earned bogus challenge data from the v1 predicate bug
    /// (pace challenges auto-completing when distance goal hit). Runs once per install; gated
    /// by the `challengeCleanupV2Done` UserDefaults flag.
    static func runLegacyCleanupIfNeeded(userManager: UserManager) {
        let defaults = UserDefaults.standard
        let flagKey = "challengeCleanupV2Done"
        guard !defaults.bool(forKey: flagKey) else { return }

        // Wipe all recorded completions.
        defaults.removeObject(forKey: "challengeCompletionsV1")

        // Strip every challenge_* badge from the user.
        let before = userManager.currentUser.badges.count
        userManager.currentUser.badges.removeAll { $0.id.starts(with: "challenge_") }
        if userManager.currentUser.badges.count != before {
            userManager.saveUserData()
        }

        defaults.set(true, forKey: flagKey)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }
}

final class LocalChallengeService: ChallengeServiceProtocol {
    private let defaults: UserDefaults
    private let storageKey = "challengeCompletionsV1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recordCompletion(_ completion: ChallengeCompletion) {
        var completions = allCompletions()
        // De-dupe by calendar day.
        if completions.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: completion.date) }) {
            return
        }
        completions.append(completion)
        save(completions)
        NotificationCenter.default.post(name: ChallengeService.changedNotification, object: nil)
    }

    func allCompletions() -> [ChallengeCompletion] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ChallengeCompletion].self, from: data)) ?? []
    }

    func completion(on date: Date) -> ChallengeCompletion? {
        let target = Calendar.current.startOfDay(for: date)
        return allCompletions().first { Calendar.current.isDate($0.date, inSameDayAs: target) }
    }

    func currentChallengeStreak() -> Int {
        let completions = allCompletions()
        guard !completions.isEmpty else { return 0 }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = Set(completions.map { calendar.startOfDay(for: $0.date) })

        // Streak anchor: today if completed, else yesterday (grace window).
        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    private func save(_ completions: [ChallengeCompletion]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(completions) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
