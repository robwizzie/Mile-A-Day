import Foundation
import WidgetKit

struct WidgetDataStore {
    private static let suiteName = "group.mileaday.shared"
    private static let milesKey = "today_miles_completed"
    private static let goalKey = "daily_goal"
    private static let streakKey = "streak_count"

    static func save(todayMiles: Double, goal: Double) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        print("[WidgetDataStore] Saving - Miles: \(todayMiles), Goal: \(goal)")
        defaults.set(todayMiles, forKey: milesKey)
        defaults.set(goal, forKey: goalKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "TodayProgressWidget")
    }

    static func load() -> (miles: Double, goal: Double) {
        let defaults = UserDefaults(suiteName: suiteName)
        let miles = defaults?.double(forKey: milesKey) ?? 0
        let goal = defaults?.double(forKey: goalKey) ?? 1
        print("[WidgetDataStore] Loading - Miles: \(miles), Goal: \(goal)")
        return (miles, goal)
    }

    // MARK: - Streak helpers
    static func save(streak: Int) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(streak, forKey: streakKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "StreakCountWidget")
    }

    static func loadStreak() -> Int {
        let defaults = UserDefaults(suiteName: suiteName)
        return defaults?.integer(forKey: streakKey) ?? 0
    }
} 