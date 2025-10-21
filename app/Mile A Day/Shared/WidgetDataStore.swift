import Foundation
import WidgetKit

struct WidgetDataStore {
    private static let suiteName = "group.mileaday.shared"
    private static let milesKey = "today_miles_completed"
    private static let goalKey = "daily_goal"
    private static let streakKey = "streak_count"

    /// Saves today's progress data
    /// Ensures progress never exceeds 100% and maintains accurate sync
    static func save(todayMiles: Double, goal: Double) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { 
            return 
        }
        
        // Ensure goal is never 0
        let safeGoal = goal > 0 ? goal : 1.0
        
        // Calculate progress and cap at 100%
        let progress = min(todayMiles / safeGoal, 1.0)
        let isCompleted = todayMiles >= safeGoal
        
        // Save all values with proper synchronization
        defaults.set(todayMiles, forKey: milesKey)
        defaults.set(safeGoal, forKey: goalKey)
        defaults.set(isCompleted, forKey: "streak_completed_today")
        defaults.set(todayMiles, forKey: "total_current_distance")
        defaults.set(progress, forKey: "current_progress")
        
        // Force synchronization to disk
        defaults.synchronize()
        
        // Reload widgets with error handling
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "TodayProgressWidget")
            
            // Additional reload after slight delay for reliability
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                WidgetCenter.shared.reloadTimelines(ofKind: "TodayProgressWidget")
            }
        }
    }

    /// Loads today's progress data
    static func load() -> (miles: Double, goal: Double, streakCompleted: Bool, progress: Double) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return (0, 1, false, 0)
        }
        
        let miles = defaults.double(forKey: milesKey)
        let goal = defaults.double(forKey: goalKey) == 0 ? 1 : defaults.double(forKey: goalKey)
        let streakCompleted = defaults.bool(forKey: "streak_completed_today")
        let progress = defaults.double(forKey: "current_progress")
        
        return (miles, goal, streakCompleted, progress)
    }

    // MARK: - Streak helpers
    static func save(streak: Int) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { 
            return 
        }
        
        defaults.set(streak, forKey: streakKey)
        defaults.synchronize()
        
        // Reload widgets with error handling
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "StreakCountWidget")
            
            // Additional reload after slight delay for reliability
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                WidgetCenter.shared.reloadTimelines(ofKind: "StreakCountWidget")
            }
        }
    }

    static func loadStreak() -> Int {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return 0
        }
        return defaults.integer(forKey: streakKey)
    }
} 