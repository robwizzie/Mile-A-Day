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
    private static let lastSyncDateKey = "last_sync_date"
    private static let dayTrackingKey = "current_tracking_day"
    
    // Thread safety
    private static let queue = DispatchQueue(label: "com.mileaday.widgetstore", qos: .userInitiated)
    
    /// Atomically saves today's progress data with enhanced day tracking
    /// Ensures data consistency across all app components and widgets
    static func save(todayMiles: Double, goal: Double, forceRefresh: Bool = false) {
        queue.sync {
            guard let defaults = UserDefaults(suiteName: suiteName) else { 
                print("[WidgetDataStore] ❌ Failed to access App Group UserDefaults")
                return 
            }
            
            // Check if we need to reset for a new day
            let currentDay = getDayString(for: Date())
            let lastTrackedDay = defaults.string(forKey: dayTrackingKey) ?? ""
            
            var finalMiles = todayMiles
            
            // If it's a new day, reset miles to current workout miles
            if currentDay != lastTrackedDay {
                print("[WidgetDataStore] 🌅 New day detected: \(lastTrackedDay) -> \(currentDay)")
                finalMiles = todayMiles // Start fresh for new day
                defaults.set(currentDay, forKey: dayTrackingKey)
            }
            
            // Ensure goal is never 0
            let safeGoal = goal > 0 ? goal : 1.0
            
            // Calculate progress and cap at 100%
            let progress = min(finalMiles / safeGoal, 1.0)
            let isCompleted = finalMiles >= safeGoal
            
            // Atomic update with versioning
            let currentVersion = defaults.integer(forKey: dataVersionKey) + 1
            let timestamp = Date().timeIntervalSince1970
            
            defaults.set(finalMiles, forKey: milesKey)
            defaults.set(safeGoal, forKey: goalKey)
            defaults.set(isCompleted, forKey: "streak_completed_today")
            defaults.set(finalMiles, forKey: "total_current_distance")
            defaults.set(progress, forKey: "current_progress")
            defaults.set(timestamp, forKey: lastUpdateKey)
            defaults.set(timestamp, forKey: lastSyncDateKey)
            defaults.set(currentVersion, forKey: dataVersionKey)
            
            print("[WidgetDataStore] 💾 Atomic Save - Miles: \(finalMiles), Goal: \(safeGoal), Progress: \(Int(progress * 100))%, Version: \(currentVersion), Day: \(currentDay)")
            
            // Enhanced widget refresh strategy
            DispatchQueue.main.async {
                if forceRefresh || isCompleted {
                    // Force all widgets to refresh immediately for important updates
                    WidgetCenter.shared.reloadAllTimelines()
                    print("[WidgetDataStore] 🔄 Forced all widget refresh")
                } else {
                    // Standard refresh for specific widgets
                    WidgetCenter.shared.reloadTimelines(ofKind: "TodayProgressWidget")
                    WidgetCenter.shared.reloadTimelines(ofKind: "StreakCountWidget")
                }
            }
        }
    }

    /// Atomically loads today's progress data with day validation
    static func load() -> (miles: Double, goal: Double, streakCompleted: Bool, totalDistance: Double, progress: Double, version: Int, lastUpdate: Date, isToday: Bool) {
        return queue.sync {
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                print("[WidgetDataStore] ❌ Failed to access App Group UserDefaults")
                return (0, 1, false, 0, 0, 0, Date(), true)
            }
            
            // Check if data is from today
            let currentDay = getDayString(for: Date())
            let dataDay = defaults.string(forKey: dayTrackingKey) ?? ""
            let isToday = currentDay == dataDay
            
            // If data is not from today, return reset values
            if !isToday {
                print("[WidgetDataStore] 📅 Detected stale data from: \(dataDay), current: \(currentDay)")
                // Reset for new day but keep goal
                let goal = defaults.double(forKey: goalKey) == 0 ? 1 : defaults.double(forKey: goalKey)
                return (0, goal, false, 0, 0, 0, Date(), false)
            }
            
            let baseMiles = defaults.double(forKey: milesKey)
            let goal = defaults.double(forKey: goalKey) == 0 ? 1 : defaults.double(forKey: goalKey)
            let streakCompleted = defaults.bool(forKey: "streak_completed_today")
            let totalDistance = defaults.double(forKey: "total_current_distance")
            let progress = defaults.double(forKey: "current_progress")
            let version = defaults.integer(forKey: dataVersionKey)
            let lastUpdateTimestamp = defaults.double(forKey: lastUpdateKey)
            let lastUpdate = Date(timeIntervalSince1970: lastUpdateTimestamp)
            
            print("[WidgetDataStore] 📖 Load - Miles: \(baseMiles), Goal: \(goal), Total: \(totalDistance), Progress: \(Int(progress * 100))%, Completed: \(streakCompleted), Version: \(version), IsToday: \(isToday)")
            return (baseMiles, goal, streakCompleted, totalDistance, progress, version, lastUpdate, isToday)
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
    
    // MARK: - Enhanced sync and validation
    
    /// Force widget refresh - call when returning from background or after workouts
    static func forceWidgetSync() {
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadAllTimelines()
            print("[WidgetDataStore] 🔄 Forced complete widget sync")
        }
    }
    
    /// Check if widgets need refresh based on last sync time
    static func needsRefresh() -> Bool {
        return queue.sync {
            guard let defaults = UserDefaults(suiteName: suiteName) else { return true }
            
            let lastSyncTimestamp = defaults.double(forKey: lastSyncDateKey)
            let lastSync = Date(timeIntervalSince1970: lastSyncTimestamp)
            let timeSinceSync = Date().timeIntervalSince(lastSync)
            
            // Consider refresh needed if:
            // 1. Never synced (timestamp is 0)
            // 2. More than 5 minutes since last sync
            // 3. Day has changed since last sync
            let needsRefresh = lastSyncTimestamp == 0 || 
                              timeSinceSync > 300 || 
                              !Calendar.current.isDate(lastSync, inSameDayAs: Date())
            
            if needsRefresh {
                print("[WidgetDataStore] ⏰ Refresh needed - Last sync: \(Int(timeSinceSync))s ago")
            }
            
            return needsRefresh
        }
    }
    
    /// Get current day string for day tracking
    private static func getDayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    // MARK: - Unified data access with consistency checks
    
    /// Get complete current state with data integrity validation and day checking
    static func getCurrentState() -> (baseMiles: Double, totalDistance: Double, goal: Double, progress: Double, isCompleted: Bool, dataAge: TimeInterval, isToday: Bool) {
        return queue.sync {
            let mainData = load()
            
            // If data is not from today, return fresh state
            if !mainData.isToday {
                let progress = 0.0
                let isCompleted = false
                return (0.0, 0.0, mainData.goal, progress, isCompleted, 0, false)
            }
            
            let progress = min(mainData.miles / mainData.goal, 1.0)
            let isCompleted = mainData.miles >= mainData.goal
            let dataAge = Date().timeIntervalSince(mainData.lastUpdate)
            
            // Data freshness validation
            if dataAge > 300 { // 5 minutes
                print("[WidgetDataStore] ⚠️ Data potentially stale - Age: \(Int(dataAge))s")
            }
            
            return (mainData.miles, mainData.totalDistance, mainData.goal, progress, isCompleted, dataAge, true)
        }
    }
    
    // MARK: - Data validation and cleanup with day awareness
    
    /// Validates data integrity and fixes any inconsistencies, handles day transitions
    static func validateAndRepair() -> Bool {
        return queue.sync {
            guard let defaults = UserDefaults(suiteName: suiteName) else { return false }
            
            var needsRepair = false
            
            // Check for day transition
            let currentDay = getDayString(for: Date())
            let lastTrackedDay = defaults.string(forKey: dayTrackingKey) ?? ""
            
            if currentDay != lastTrackedDay && !lastTrackedDay.isEmpty {
                // New day detected - reset daily data
                defaults.set(0.0, forKey: milesKey)
                defaults.set(false, forKey: "streak_completed_today")
                defaults.set(0.0, forKey: "total_current_distance")
                defaults.set(0.0, forKey: "current_progress")
                defaults.set(currentDay, forKey: dayTrackingKey)
                needsRepair = true
                print("[WidgetDataStore] 🌅 Day transition detected - reset daily data: \(lastTrackedDay) -> \(currentDay)")
            }
            
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