import Foundation
import WidgetKit

struct WidgetDataStore {
    private static let suiteName = "group.mileaday.shared"
    private static let milesKey = "today_miles_completed"
    private static let goalKey = "daily_goal"
    private static let streakKey = "streak_count"
    private static let liveWorkoutActiveKey = "live_workout_active"
    private static let liveWorkoutDistanceKey = "live_workout_distance"

    /// Saves today's progress data with live workout integration
    /// Ensures progress never exceeds 100% and maintains 1-to-1 sync
    static func save(todayMiles: Double, goal: Double, liveWorkoutDistance: Double = 0.0) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        
        // Calculate total current distance including live workout
        let totalCurrentDistance = todayMiles + liveWorkoutDistance
        
        // Ensure goal is never 0
        let safeGoal = goal > 0 ? goal : 1.0
        
        // Calculate progress and cap at 100%
        let progress = min(totalCurrentDistance / safeGoal, 1.0)
        let isCompleted = totalCurrentDistance >= safeGoal
        
        print("[WidgetDataStore] Saving - Base Miles: \(todayMiles), Live: \(liveWorkoutDistance), Total: \(totalCurrentDistance), Goal: \(safeGoal), Progress: \(progress * 100)%")
        
        defaults.set(todayMiles, forKey: milesKey)
        defaults.set(safeGoal, forKey: goalKey)
        defaults.set(isCompleted, forKey: "streak_completed_today")
        
        // Save total distance for widget display
        defaults.set(totalCurrentDistance, forKey: "total_current_distance")
        defaults.set(progress, forKey: "current_progress")
        
        WidgetCenter.shared.reloadTimelines(ofKind: "TodayProgressWidget")
    }

    /// Loads today's progress data with live workout integration
    static func load() -> (miles: Double, goal: Double, streakCompleted: Bool, totalDistance: Double, progress: Double) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            print("[WidgetDataStore] Failed to access App Group UserDefaults")
            return (0, 1, false, 0, 0)
        }
        
        let baseMiles = defaults.double(forKey: milesKey)
        let goal = defaults.double(forKey: goalKey) == 0 ? 1 : defaults.double(forKey: goalKey)
        let streakCompleted = defaults.bool(forKey: "streak_completed_today")
        let totalDistance = defaults.double(forKey: "total_current_distance")
        let progress = defaults.double(forKey: "current_progress")
        
        print("[WidgetDataStore] Loading - Base Miles: \(baseMiles), Goal: \(goal), Total: \(totalDistance), Progress: \(progress * 100)%, Completed: \(streakCompleted)")
        return (baseMiles, goal, streakCompleted, totalDistance, progress)
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
        
        // Immediately update the main data with live workout
        let currentData = load()
        save(todayMiles: currentData.miles, goal: currentData.goal, liveWorkoutDistance: currentDistance)
    }
    
    static func loadLiveWorkout() -> (isActive: Bool, distance: Double) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return (false, 0.0)
        }
        let isActive = defaults.bool(forKey: liveWorkoutActiveKey)
        let distance = defaults.double(forKey: liveWorkoutDistanceKey)
        return (isActive, distance)
    }
    
    // MARK: - Unified data access
    
    /// Get complete current state including live workout data
    static func getCurrentState() -> (baseMiles: Double, liveDistance: Double, totalDistance: Double, goal: Double, progress: Double, isCompleted: Bool) {
        let mainData = load()
        let liveData = loadLiveWorkout()
        
        let totalDistance = mainData.miles + liveData.distance
        let progress = min(totalDistance / mainData.goal, 1.0)
        let isCompleted = totalDistance >= mainData.goal
        
        return (mainData.miles, liveData.distance, totalDistance, mainData.goal, progress, isCompleted)
    }
} 