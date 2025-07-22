import Foundation
import WidgetKit

/// Centralized, thread-safe data store for app-widget communication
/// Handles all data persistence and synchronization
struct WidgetDataStore {
    private static let suiteName = "group.mileaday.shared"
    private static let milesKey = "today_miles_completed"
    private static let goalKey = "daily_goal"
    private static let streakKey = "streak_count"
    private static let lastUpdateKey = "last_update_timestamp"
    private static let dataVersionKey = "data_version"
    
    // Thread safety
    private static let queue = DispatchQueue(label: "com.mileaday.widgetstore", qos: .userInitiated)
    
    /// Atomically saves today's progress data
    /// Ensures data consistency across all app components and widgets
    static func save(todayMiles: Double, goal: Double) {
        queue.sync {
            guard let defaults = UserDefaults(suiteName: suiteName) else { 
                print("[WidgetDataStore] ❌ Failed to access App Group UserDefaults")
                return 
            }
            
            // Ensure goal is never 0
            let safeGoal = goal > 0 ? goal : 1.0
            
            // Calculate progress and cap at 100%
            let progress = min(todayMiles / safeGoal, 1.0)
            let isCompleted = todayMiles >= safeGoal
            
            // Atomic update with versioning
            let currentVersion = defaults.integer(forKey: dataVersionKey) + 1
            let timestamp = Date().timeIntervalSince1970
            
            defaults.set(todayMiles, forKey: milesKey)
            defaults.set(safeGoal, forKey: goalKey)
            defaults.set(isCompleted, forKey: "streak_completed_today")
            defaults.set(todayMiles, forKey: "total_current_distance")
            defaults.set(progress, forKey: "current_progress")
            defaults.set(timestamp, forKey: lastUpdateKey)
            defaults.set(currentVersion, forKey: dataVersionKey)
            
            print("[WidgetDataStore] 💾 Atomic Save - Miles: \(todayMiles), Goal: \(safeGoal), Progress: \(Int(progress * 100))%, Version: \(currentVersion)")
            
            // Force widget updates
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadTimelines(ofKind: "TodayProgressWidget")
                WidgetCenter.shared.reloadTimelines(ofKind: "StreakCountWidget")
            }
        }
    }

    /// Atomically loads today's progress data with version checking
    static func load() -> (miles: Double, goal: Double, streakCompleted: Bool, totalDistance: Double, progress: Double, version: Int, lastUpdate: Date) {
        return queue.sync {
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                print("[WidgetDataStore] ❌ Failed to access App Group UserDefaults")
                return (0, 1, false, 0, 0, 0, Date())
            }
            
            let baseMiles = defaults.double(forKey: milesKey)
            let goal = defaults.double(forKey: goalKey) == 0 ? 1 : defaults.double(forKey: goalKey)
            let streakCompleted = defaults.bool(forKey: "streak_completed_today")
            let totalDistance = defaults.double(forKey: "total_current_distance")
            let progress = defaults.double(forKey: "current_progress")
            let version = defaults.integer(forKey: dataVersionKey)
            let lastUpdateTimestamp = defaults.double(forKey: lastUpdateKey)
            let lastUpdate = Date(timeIntervalSince1970: lastUpdateTimestamp)
            
            print("[WidgetDataStore] 📖 Load - Base: \(baseMiles), Goal: \(goal), Total: \(totalDistance), Progress: \(Int(progress * 100))%, Completed: \(streakCompleted), Version: \(version)")
            return (baseMiles, goal, streakCompleted, totalDistance, progress, version, lastUpdate)
        }
    }

    // MARK: - Streak helpers with thread safety
    static func save(streak: Int) {
        queue.sync {
            guard let defaults = UserDefaults(suiteName: suiteName) else { return }
            let currentVersion = defaults.integer(forKey: dataVersionKey) + 1
            defaults.set(streak, forKey: streakKey)
            defaults.set(currentVersion, forKey: dataVersionKey)
            print("[WidgetDataStore] 🏆 Streak saved: \(streak), Version: \(currentVersion)")
            
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadTimelines(ofKind: "StreakCountWidget")
            }
        }
    }

    static func loadStreak() -> Int {
        return queue.sync {
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                print("[WidgetDataStore] ❌ Failed to access App Group UserDefaults for streak")
                return 0
            }
            return defaults.integer(forKey: streakKey)
        }
    }
    

    
    // MARK: - Unified data access with consistency checks
    
    /// Get complete current state with data integrity validation
    static func getCurrentState() -> (baseMiles: Double, totalDistance: Double, goal: Double, progress: Double, isCompleted: Bool, dataAge: TimeInterval) {
        return queue.sync {
            let mainData = load()
            
            let progress = min(mainData.miles / mainData.goal, 1.0)
            let isCompleted = mainData.miles >= mainData.goal
            let dataAge = Date().timeIntervalSince(mainData.lastUpdate)
            
            // Data freshness validation
            if dataAge > 300 { // 5 minutes
                print("[WidgetDataStore] ⚠️ Data potentially stale - Age: \(Int(dataAge))s")
            }
            
            return (mainData.miles, mainData.totalDistance, mainData.goal, progress, isCompleted, dataAge)
        }
    }
    
    // MARK: - Data validation and cleanup
    
    /// Validates data integrity and fixes any inconsistencies
    static func validateAndRepair() -> Bool {
        return queue.sync {
            guard let defaults = UserDefaults(suiteName: suiteName) else { return false }
            
            var needsRepair = false
            
            // Check for invalid goal
            let goal = defaults.double(forKey: goalKey)
            if goal <= 0 {
                defaults.set(1.0, forKey: goalKey)
                needsRepair = true
                print("[WidgetDataStore] 🔧 Repaired invalid goal: \(goal) -> 1.0")
            }
            
            // Check for negative miles
            let miles = defaults.double(forKey: milesKey)
            if miles < 0 {
                defaults.set(0.0, forKey: milesKey)
                needsRepair = true
                print("[WidgetDataStore] 🔧 Repaired negative miles: \(miles) -> 0.0")
            }
            

            
            if needsRepair {
                let currentVersion = defaults.integer(forKey: dataVersionKey) + 1
                defaults.set(currentVersion, forKey: dataVersionKey)
                defaults.set(Date().timeIntervalSince1970, forKey: lastUpdateKey)
                
                DispatchQueue.main.async {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            
            return needsRepair
        }
    }
    
} 