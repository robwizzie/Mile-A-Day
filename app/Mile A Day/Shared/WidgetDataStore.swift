import Foundation
import WidgetKit

struct WidgetDataStore {
    private static let suiteName = "group.mileaday.shared"
    private static let milesKey = "today_miles_completed"
    private static let goalKey = "daily_goal"
    private static let streakKey = "streak_count"
    private static let dataDayKey = "widget_data_day"

    /// Day stamp (device-local calendar day) for the saved progress values.
    /// Lets `load()` detect data written on a previous day so widgets show a
    /// fresh 0-mile day after midnight instead of yesterday's run.
    private static func dayStamp(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Saves today's progress data
    /// Ensures progress never exceeds 100% and maintains accurate sync
    static func save(todayMiles: Double, goal: Double) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }

        // Ensure goal is never 0
        let safeGoal = goal > 0 ? goal : 1.0
        let stamp = dayStamp()

        // Skip no-op writes: every save triggers widget timeline reloads, and
        // iOS rations those per day — burning the budget on unchanged values
        // means real updates later in the day get silently dropped.
        if defaults.double(forKey: milesKey) == todayMiles,
           defaults.double(forKey: goalKey) == safeGoal,
           defaults.string(forKey: dataDayKey) == stamp {
            return
        }

        // Calculate progress and cap at 100%
        let progress = min(todayMiles / safeGoal, 1.0)
        let isCompleted = todayMiles >= safeGoal

        // Save all values with proper synchronization
        defaults.set(todayMiles, forKey: milesKey)
        defaults.set(safeGoal, forKey: goalKey)
        defaults.set(isCompleted, forKey: "streak_completed_today")
        defaults.set(todayMiles, forKey: "total_current_distance")
        defaults.set(progress, forKey: "current_progress")
        defaults.set(stamp, forKey: dataDayKey)

        // Force synchronization to disk
        defaults.synchronize()

        // Reload both widget kinds — the streak widget renders the same
        // progress/completed values, so reloading only the progress widget
        // left the two disagreeing for up to an hour.
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "TodayProgressWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "StreakCountWidget")
        }
    }

    /// Loads today's progress data
    static func load() -> (miles: Double, goal: Double, streakCompleted: Bool, progress: Double) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return (0, 1, false, 0)
        }

        let goal = defaults.double(forKey: goalKey) == 0 ? 1 : defaults.double(forKey: goalKey)

        // Saved values are from a previous day — surface a fresh, empty day
        // (keeping the goal) rather than yesterday's miles/completion state.
        if let storedDay = defaults.string(forKey: dataDayKey), storedDay != dayStamp() {
            return (0, goal, false, 0)
        }

        let miles = defaults.double(forKey: milesKey)
        let streakCompleted = defaults.bool(forKey: "streak_completed_today")
        let progress = defaults.double(forKey: "current_progress")

        return (miles, goal, streakCompleted, progress)
    }

    // MARK: - Streak helpers
    static func save(streak: Int) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }

        // Skip no-op writes — see save(todayMiles:goal:).
        if defaults.integer(forKey: streakKey) == streak {
            return
        }

        defaults.set(streak, forKey: streakKey)
        defaults.synchronize()

        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "StreakCountWidget")
        }
    }

    static func loadStreak() -> Int {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return 0
        }
        return defaults.integer(forKey: streakKey)
    }
}
