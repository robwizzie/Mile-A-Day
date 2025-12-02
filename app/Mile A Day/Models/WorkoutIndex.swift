//
//  WorkoutIndex.swift
//  Mile A Day
//
//  Created by AI Assistant
//  Persistent, pre-computed workout index for fast, reliable data access
//

import Foundation
import HealthKit

#if !os(watchOS)

private func workoutIndexLog(_ message: String) {}

/// ARCHITECTURAL IMPROVEMENT: Single Source of Truth for Workout Data
/// This index pre-computes and caches workout data to eliminate:
/// - Race conditions and data inconsistencies
/// - Slow app opens (no more 72→161 day jumps)
/// - Multiple HealthKit queries
/// - Calendar bugs (icons with no workout details)
struct WorkoutIndex: Codable {
    /// Pre-computed workout mappings by LOCAL date (timezone-corrected)
    var workoutsByDate: [String: [WorkoutRecord]] // String key for Codable
    
    /// Pre-computed list of days with qualifying workouts (>= 0.95 miles)
    var qualifyingDays: Set<String> // String dates for Codable
    
    /// Current streak count (pre-computed)
    var currentStreak: Int
    
    /// When this index was last updated
    var lastUpdated: Date
    
    /// Latest workout date in the index
    var latestWorkoutDate: Date?
    
    /// UUID of latest processed workout (for incremental updates)
    var latestWorkoutUUID: String?
    
    /// Version of the index format (for future migrations)
    var version: Int
    
    /// Total number of workouts in index
    var totalWorkouts: Int
    
    /// Total lifetime miles (sum of all workout distances)
    var totalLifetimeMiles: Double
    
    init() {
        self.workoutsByDate = [:]
        self.qualifyingDays = Set()
        self.currentStreak = 0
        self.lastUpdated = Date.distantPast
        self.latestWorkoutDate = nil
        self.latestWorkoutUUID = nil
        self.version = 1
        self.totalWorkouts = 0
        self.totalLifetimeMiles = 0.0
    }
    
    // MARK: - Computed Properties
    
    /// Get workouts for a specific date (instant lookup)
    func workouts(for date: Date) -> [WorkoutRecord] {
        let key = dateKey(from: date)
        return workoutsByDate[key] ?? []
    }
    
    /// Check if a date has qualifying workouts
    func hasQualifyingWorkout(on date: Date) -> Bool {
        let key = dateKey(from: date)
        return qualifyingDays.contains(key)
    }
    
    /// Get total miles for a specific date
    func totalMiles(for date: Date) -> Double {
        return workouts(for: date).reduce(0) { $0 + $1.distance }
    }
    
    /// Get all dates with workouts (sorted)
    var allDates: [Date] {
        return workoutsByDate.keys.compactMap { dateFromKey($0) }.sorted()
    }
    
    // MARK: - Helper Methods
    
    private func dateKey(from date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", 
                     components.year ?? 0,
                     components.month ?? 0,
                     components.day ?? 0)
    }
    
    private func dateFromKey(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: key)
    }
    
    // MARK: - Index Persistence
    
    private static let indexKey = "com.mileaday.workoutIndex.v1"
    
    /// Save index to persistent storage
    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(self)
            UserDefaults.standard.set(data, forKey: Self.indexKey)
            workoutIndexLog("[WorkoutIndex] ✅ Saved index: \(totalWorkouts) workouts, \(currentStreak) day streak")
        } catch {
            workoutIndexLog("[WorkoutIndex] ❌ Failed to save index: \(error)")
        }
    }
    
    /// Load index from persistent storage
    static func load() -> WorkoutIndex? {
        guard let data = UserDefaults.standard.data(forKey: indexKey) else {
            workoutIndexLog("[WorkoutIndex] No cached index found")
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let index = try decoder.decode(WorkoutIndex.self, from: data)
            workoutIndexLog("[WorkoutIndex] ✅ Loaded index: \(index.totalWorkouts) workouts, \(index.currentStreak) day streak")
            return index
        } catch {
            workoutIndexLog("[WorkoutIndex] ❌ Failed to load index: \(error)")
            return nil
        }
    }
    
    /// Clear the cached index (for testing/reset)
    static func clear() {
        UserDefaults.standard.removeObject(forKey: indexKey)
        workoutIndexLog("[WorkoutIndex] 🗑️ Cleared cached index")
    }
}

/// Lightweight workout record with pre-computed timezone correction
struct WorkoutRecord: Codable, Identifiable {
    /// Unique identifier for the workout
    let id: String // UUID as string for Codable
    
    /// Original end date from HealthKit (device timezone)
    let deviceEndDate: Date
    
    /// Local date where workout was performed (timezone-corrected, start of day)
    let localDate: Date
    
    /// Corrected end time in local timezone (for display)
    let localEndTime: Date
    
    /// Timezone offset applied (in hours) - 0 if no correction
    let timezoneOffset: Int
    
    /// Distance in miles
    let distance: Double
    
    /// Duration in seconds
    let duration: TimeInterval
    
    /// Workout type (running, walking, etc.)
    let workoutType: String
    
    /// When this record was created/processed
    let processedDate: Date
    
    init(id: String, deviceEndDate: Date, localDate: Date, localEndTime: Date, timezoneOffset: Int, 
         distance: Double, duration: TimeInterval, workoutType: String, processedDate: Date = Date()) {
        self.id = id
        self.deviceEndDate = deviceEndDate
        self.localDate = localDate
        self.localEndTime = localEndTime
        self.timezoneOffset = timezoneOffset
        self.distance = distance
        self.duration = duration
        self.workoutType = workoutType
        self.processedDate = processedDate
    }
    
    /// Create from HKWorkout with timezone correction
    init(from workout: HKWorkout, timezoneCorrectedDate: Date, timezoneOffset: Int = 0) {
        self.id = workout.uuid.uuidString
        self.deviceEndDate = workout.endDate
        self.localDate = timezoneCorrectedDate
        
        // Calculate local end time by applying the same offset
        if timezoneOffset != 0 {
            self.localEndTime = Calendar.current.date(byAdding: .hour, value: timezoneOffset, to: workout.endDate) ?? workout.endDate
        } else {
            self.localEndTime = workout.endDate
        }
        
        self.timezoneOffset = timezoneOffset
        self.distance = workout.totalDistance?.doubleValue(for: .mile()) ?? 0.0
        self.duration = workout.duration
        
        if workout.workoutActivityType == .running {
            self.workoutType = "running"
        } else if workout.workoutActivityType == .walking {
            self.workoutType = "walking"
        } else {
            self.workoutType = "other"
        }
        
        self.processedDate = Date()
    }
    
    // MARK: - Computed Properties
    
    /// Average pace in minutes per mile
    var averagePace: TimeInterval? {
        guard distance > 0 else { return nil }
        return (duration / 60.0) / distance
    }
    
    /// Whether this workout qualifies for streak (>= 0.95 miles)
    var qualifies: Bool {
        return distance >= 0.95
    }
}
#endif

