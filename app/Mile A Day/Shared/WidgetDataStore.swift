import Foundation
import WidgetKit

struct WidgetDataStore {
    private static let suiteName = "group.mileaday.shared"
    private static let milesKey = "today_miles_completed"
    private static let goalKey = "daily_goal"
    private static let streakKey = "streak_count"
    private static let liveWorkoutActiveKey = "live_workout_active"
    private static let liveWorkoutDistanceKey = "live_workout_distance"

    static func save(todayMiles: Double, goal: Double) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        print("[WidgetDataStore] Saving - Miles: \(todayMiles), Goal: \(goal)")
        defaults.set(todayMiles, forKey: milesKey)
        defaults.set(goal, forKey: goalKey)
        // Determine if streak is completed (miles >= goal)
        defaults.set(todayMiles >= goal, forKey: "streak_completed_today")
        WidgetCenter.shared.reloadTimelines(ofKind: "TodayProgressWidget")
    }

    static func load() -> (miles: Double, goal: Double, streakCompleted: Bool) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            print("[WidgetDataStore] Failed to access App Group UserDefaults")
            return (0, 1, false)
        }
        let miles = defaults.double(forKey: milesKey)
        let goal = defaults.double(forKey: goalKey) == 0 ? 1 : defaults.double(forKey: goalKey)
        let streakCompleted = defaults.bool(forKey: "streak_completed_today")
        print("[WidgetDataStore] Loading - Miles: \(miles), Goal: \(goal), Completed: \(streakCompleted)")
        return (miles, goal, streakCompleted)
    }

    // MARK: - Streak helpers
    static func save(streak: Int) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(streak, forKey: streakKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "StreakCountWidget")
    }

    static func loadStreak() -> Int {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            print("[WidgetDataStore] Failed to access App Group UserDefaults for streak")
            return 0
        }
        return defaults.integer(forKey: streakKey)
    }
    
    // MARK: - Live Workout helpers
    static func saveLiveWorkout(isActive: Bool, currentDistance: Double = 0.0) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(isActive, forKey: liveWorkoutActiveKey)
        defaults.set(currentDistance, forKey: liveWorkoutDistanceKey)
    }
    
    static func loadLiveWorkout() -> (isActive: Bool, distance: Double) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return (false, 0.0)
        }
        let isActive = defaults.bool(forKey: liveWorkoutActiveKey)
        let distance = defaults.double(forKey: liveWorkoutDistanceKey)
        return (isActive, distance)
    }
} 