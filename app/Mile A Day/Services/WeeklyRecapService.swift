import Foundation

/// Fetches one week's recap (`GET /users/:userId/weekly-recap`).
///
/// A server that predates the endpoint answers 404, and the screen must still
/// be worth opening then — the feed's Sunday teaser has always opened a week
/// recap — so `load` falls back to a recap built on the phone from HealthKit
/// (`localRecap`): totals and the seven days, without the friends board, the
/// challenge or the highlights, which only the server can know.
enum WeeklyRecapService {

    enum LoadError: Error, Equatable {
        /// 400 `week_in_future` — nothing to recap yet.
        case weekInFuture
        /// Anything else: offline, 5xx, an unreadable body.
        case failed
    }

    @MainActor
    static func load(weekStart: String?) async -> Result<WeeklyRecap, LoadError> {
        guard let userId = UserDefaults.standard.string(forKey: "backendUserId"), !userId.isEmpty else {
            return localRecap(weekStart: weekStart).map { .success($0) } ?? .failure(.failed)
        }
        var endpoint = "/users/\(userId)/weekly-recap"
        if let weekStart, !weekStart.isEmpty {
            endpoint += "?week_start=\(weekStart)"
        }
        do {
            let recap = try await APIClient.fancyFetch(endpoint: endpoint, responseType: WeeklyRecap.self)
            // A body with no week at all is not a recap — treat it like an
            // older server rather than draw an empty screen.
            guard !recap.weekStart.isEmpty else {
                return localRecap(weekStart: weekStart).map { .success($0) } ?? .failure(.failed)
            }
            return .success(recap)
        } catch APIError.notFound {
            return localRecap(weekStart: weekStart).map { .success($0) } ?? .failure(.failed)
        } catch APIError.badRequest(let message) where message.lowercased().contains("future") {
            // 400 `week_in_future`. APIClient surfaces the body's `error`
            // text, not its `code`, so match the one word both carry.
            return .failure(.weekInFuture)
        } catch {
            print("[WeeklyRecap] load failed: \(error.localizedDescription)")
            return .failure(.failed)
        }
    }

    /// The week, from what this phone can see: HealthKit's counted (deduped)
    /// miles per local day, scored against the goal with the app's tolerance.
    @MainActor
    static func localRecap(weekStart: String?) -> WeeklyRecap? {
        let startKey = weekStart ?? WeeklyRecap.weekStart(containing: Date())
        guard let start = WeeklyRecap.dayFormatter.date(from: startKey) else { return nil }
        let health = HealthKitManager.shared
        let user = UserManager.shared.currentUser
        let goal = max(user.goalMiles, 0.01)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var days: [WeeklyRecap.Day] = []
        var total = 0.0
        var longest = 0.0
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { continue }
            let miles = day > today ? 0 : health.countedMiles(onLocalDay: day)
            total += miles
            longest = max(longest, miles)
            days.append(WeeklyRecap.Day(
                date: WeeklyRecap.dayFormatter.string(from: day),
                miles: miles,
                goalMet: miles > 0 && ProgressCalculator.isGoalCompleted(current: miles, goal: goal),
                covered: false
            ))
        }
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        return WeeklyRecap(
            weekStart: startKey,
            weekEnd: WeeklyRecap.dayFormatter.string(from: end),
            isComplete: end < today,
            totalMiles: total,
            priorWeekMiles: nil,
            days: days,
            daysGoalMet: nil,
            goalMiles: goal,
            workouts: nil,
            totalDurationSeconds: nil,
            longestWorkoutMiles: nil,
            fastestMilePaceSeconds: nil,
            currentStreak: user.streak > 0 ? user.streak : nil,
            streakAtWeekStart: nil
        )
    }
}

/// The weekly recap, as content for the Share Studio's WEEK templates.
extension WeeklyRecap {
    var storyContent: MADStoryContent {
        var content = MADStoryContent(
            distanceMiles: totalMiles,
            streak: currentStreak,
            date: WeeklyRecap.dayFormatter.date(from: weekStart)
        )
        content.week = self
        return content
    }
}

/// Asks the app to open a week's recap from anywhere — a push, the inbox, a
/// dashboard card. Presented once, at MainTabView root, so a request from a
/// tab the user isn't on (or from a cold launch) still lands.
@MainActor
final class WeeklyRecapLink: ObservableObject {
    static let shared = WeeklyRecapLink()
    private init() {}

    struct Request: Identifiable, Equatable {
        let id = UUID()
        /// nil = the latest week.
        let weekStart: String?
    }

    @Published var pending: Request?

    func open(weekStart: String? = nil) {
        pending = Request(weekStart: weekStart?.isEmpty == true ? nil : weekStart)
    }

    /// For callers dismissing their OWN sheet first (the notification inbox):
    /// two presentations in one transaction race and SwiftUI drops one.
    func openAfterDismiss(weekStart: String? = nil) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.open(weekStart: weekStart)
        }
    }
}
