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

/// Tracks whether a workout was recorded from HealthKit, manually entered, or edited
enum WorkoutSource: String, Codable {
    case healthkit
    case manual
    case edited
}

/// Persistent local registry of workout IDs that were manually entered or edited.
/// The WorkoutIndex is built from HealthKit which has no knowledge of our backend's
/// source field, so we track manual/edited IDs locally to flag them in the index.
struct ManualWorkoutRegistry {
    private static let manualKey = "com.mileaday.manualWorkoutIds"
    private static let editedKey = "com.mileaday.editedWorkoutIds"

    static func markManual(_ workoutId: String) {
        var ids = manualIds
        ids.insert(workoutId)
        UserDefaults.standard.set(Array(ids), forKey: manualKey)
        print("[ManualWorkoutRegistry] ✅ Marked \(workoutId.prefix(8)) as manual. Total manual: \(ids.count)")
    }

    static func markEdited(_ workoutId: String) {
        var ids = editedIds
        ids.insert(workoutId)
        UserDefaults.standard.set(Array(ids), forKey: editedKey)
    }

    static func sourceFor(_ workoutId: String) -> WorkoutSource? {
        let manual = manualIds
        let edited = editedIds
        if edited.contains(workoutId) {
            print("[ManualWorkoutRegistry] Found \(workoutId.prefix(8)) in edited set")
            return .edited
        }
        if manual.contains(workoutId) {
            print("[ManualWorkoutRegistry] Found \(workoutId.prefix(8)) in manual set")
            return .manual
        }
        return nil
    }

    private static var manualIds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: manualKey) ?? [])
    }

    private static var editedIds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: editedKey) ?? [])
    }
}

/// Workouts the user deleted in Mile A Day. Apple Health is read-only to us, so a
/// deleted HealthKit workout still exists on device and would otherwise re-appear
/// on every index rebuild (and re-upload on the next sync). We tombstone its id
/// locally so it's excluded from all app-side aggregates; the backend keeps its
/// own tombstone so it never counts there either.
struct DeletedWorkoutRegistry {
    private static let key = "com.mileaday.deletedWorkoutIds"

    static func markDeleted(_ workoutId: String) {
        var ids = all
        ids.insert(workoutId)
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    static func contains(_ workoutId: String) -> Bool {
        all.contains(workoutId)
    }

    static var all: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
}

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

    /// Recompute the active streak as of `now`, using the same today-or-yesterday
    /// grace rule as `WorkoutProcessor.calculateStreak`.
    ///
    /// IMPORTANT: the stored `currentStreak` is only a snapshot from the last time
    /// a workout was added to the index. Its correctness depends on the current
    /// date, so it goes stale as the calendar advances with no new runs (e.g. a
    /// user who ran once shows a frozen "1" forever). Always derive the *displayed*
    /// streak from this method — which reads `qualifyingDays` relative to `now` —
    /// instead of trusting `currentStreak`.
    func activeStreak(asOf now: Date = Date()) -> Int {
        // Token-covered days (Streak Save / Double Down / Assist) count as
        // "not a miss", matching the server's coverage-aware walk — otherwise
        // a local recompute would break at a rescued day and fight the backend.
        // Empty store (feature off) = byte-identical legacy behavior.
        let covered = StreakCoverageStore.coveredDayKeys
        guard !qualifyingDays.isEmpty else { return 0 }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var streak = 0

        func dayCounts(_ date: Date) -> Bool {
            let key = dateKey(from: date)
            return qualifyingDays.contains(key) || covered.contains(key)
        }

        // Today counts if it qualifies, but isn't required (grace window).
        if dayCounts(today) {
            streak += 1
        }

        // Walk backwards from yesterday; stop at the first non-qualifying day.
        guard var checkDate = calendar.date(byAdding: .day, value: -1, to: today) else {
            return streak
        }
        while dayCounts(checkDate) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previous
            if streak > 1000 { break } // safety against runaway loops
        }
        return streak
    }

    /// Get total miles for a specific date
    func totalMiles(for date: Date) -> Double {
        return workouts(for: date).reduce(0) { $0 + $1.distance }
    }
    
    /// Get all dates with workouts (sorted)
    var allDates: [Date] {
        return workoutsByDate.keys.compactMap { dateFromKey($0) }.sorted()
    }
    
    /// Pre-computed max miles in a single day (for badges and progress)
    var mostMilesInOneDay: Double {
        workoutsByDate.values.reduce(0.0) { best, records in
            let dayMiles = records.reduce(0.0) { $0 + $1.distance }
            return max(best, dayMiles)
        }
    }

    /// The date key (yyyy-MM-dd) of the day with the most miles
    var mostMilesInOneDayDateKey: String? {
        workoutsByDate.max(by: { lhs, rhs in
            let lhsMiles = lhs.value.reduce(0.0) { $0 + $1.distance }
            let rhsMiles = rhs.value.reduce(0.0) { $0 + $1.distance }
            return lhsMiles < rhsMiles
        })?.key
    }

    /// Workout records for the day with the most miles
    var mostMilesInOneDayRecords: [WorkoutRecord] {
        guard let key = mostMilesInOneDayDateKey else { return [] }
        return workoutsByDate[key] ?? []
    }

    // MARK: - Weekly Aggregation

    /// Total miles for days starting on the given date, up to `dayCount` days
    func weekTotal(startingOn weekStart: Date, dayCount: Int = 7) -> (miles: Double, daysCompleted: Int) {
        let calendar = Calendar.current
        var weekMiles = 0.0
        var daysCompleted = 0

        for offset in 0..<dayCount {
            guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: weekStart)) else { continue }
            let dayMiles = totalMiles(for: date)
            weekMiles += dayMiles
            if hasQualifyingWorkout(on: date) {
                daysCompleted += 1
            }
        }

        return (weekMiles, daysCompleted)
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
    
    private static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    private func dateFromKey(_ key: String) -> Date? {
        Self.dateKeyFormatter.date(from: key)
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

    /// Whether this workout was from HealthKit, manually entered, or edited
    let source: WorkoutSource

    /// Whether this workout was manually entered or edited by the user
    var isManualOrEdited: Bool {
        source == .manual || source == .edited
    }

    init(id: String, deviceEndDate: Date, localDate: Date, localEndTime: Date, timezoneOffset: Int,
         distance: Double, duration: TimeInterval, workoutType: String, processedDate: Date = Date(),
         source: WorkoutSource = .healthkit) {
        self.id = id
        self.deviceEndDate = deviceEndDate
        self.localDate = localDate
        self.localEndTime = localEndTime
        self.timezoneOffset = timezoneOffset
        self.distance = distance
        self.duration = duration
        self.workoutType = workoutType
        self.processedDate = processedDate
        self.source = source
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

        // Determine workout source: manual, edited, or healthkit
        let workoutUUID = workout.uuid.uuidString
        if let registeredSource = ManualWorkoutRegistry.sourceFor(workoutUUID) {
            self.source = registeredSource
            print("[WorkoutRecord] ✅ UUID \(workoutUUID.prefix(8)) found in registry → \(registeredSource)")
        } else {
            let wasUserEntered = (workout.metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true
            let isFromHealthApp = workout.sourceRevision.source.bundleIdentifier == "com.apple.health"
            let bundleId = workout.sourceRevision.source.bundleIdentifier
            self.source = (wasUserEntered || isFromHealthApp) ? .manual : .healthkit
            print("[WorkoutRecord] UUID \(workoutUUID.prefix(8)) not in registry (bundle: \(bundleId), wasUserEntered: \(wasUserEntered)) → \(self.source)")
        }
    }

    // MARK: - Codable (backward-compatible)

    enum CodingKeys: String, CodingKey {
        case id, deviceEndDate, localDate, localEndTime, timezoneOffset
        case distance, duration, workoutType, processedDate, source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        deviceEndDate = try container.decode(Date.self, forKey: .deviceEndDate)
        localDate = try container.decode(Date.self, forKey: .localDate)
        localEndTime = try container.decode(Date.self, forKey: .localEndTime)
        timezoneOffset = try container.decode(Int.self, forKey: .timezoneOffset)
        distance = try container.decode(Double.self, forKey: .distance)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        workoutType = try container.decode(String.self, forKey: .workoutType)
        processedDate = try container.decode(Date.self, forKey: .processedDate)
        // Default to .healthkit for records cached before source was added
        source = try container.decodeIfPresent(WorkoutSource.self, forKey: .source) ?? .healthkit
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

