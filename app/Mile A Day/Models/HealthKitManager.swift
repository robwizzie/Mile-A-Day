import Foundation
import HealthKit
import WidgetKit
import CoreLocation

#if os(watchOS)
private func workoutIndexLog(_ message: String) {}

struct WorkoutRecord: Codable, Identifiable {
    let id: String
    let deviceEndDate: Date
    let localDate: Date
    let localEndTime: Date
    let timezoneOffset: Int
    let distance: Double
    let duration: TimeInterval
    let workoutType: String
    let processedDate: Date
    
    init(id: String,
         deviceEndDate: Date,
         localDate: Date,
         localEndTime: Date,
         timezoneOffset: Int,
         distance: Double,
         duration: TimeInterval,
         workoutType: String,
         processedDate: Date = Date()) {
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
    
    init(from workout: HKWorkout, timezoneCorrectedDate: Date, timezoneOffset: Int = 0) {
        self.id = workout.uuid.uuidString
        self.deviceEndDate = workout.endDate
        self.localDate = timezoneCorrectedDate
        
        if timezoneOffset != 0 {
            self.localEndTime = Calendar.current.date(byAdding: .hour, value: timezoneOffset, to: workout.endDate) ?? workout.endDate
        } else {
            self.localEndTime = workout.endDate
        }
        
        self.timezoneOffset = timezoneOffset
        self.distance = workout.totalDistance?.doubleValue(for: .mile()) ?? 0.0
        self.duration = workout.duration
        
        switch workout.workoutActivityType {
        case .running:
            self.workoutType = "running"
        case .walking:
            self.workoutType = "walking"
        case .cycling:
            self.workoutType = "cycling"
        case .hiking:
            self.workoutType = "hiking"
        default:
            self.workoutType = "other"
        }
        
        self.processedDate = Date()
    }
    
    var averagePace: TimeInterval? {
        guard distance > 0 else { return nil }
        return (duration / 60.0) / distance
    }
    
    var qualifies: Bool {
        distance >= 0.95
    }
}

struct WorkoutIndex: Codable {
    var workoutsByDate: [String: [WorkoutRecord]]
    var qualifyingDays: Set<String>
    var currentStreak: Int
    var lastUpdated: Date
    var latestWorkoutDate: Date?
    var latestWorkoutUUID: String?
    var version: Int
    var totalWorkouts: Int
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
    
    mutating func add(records: [WorkoutRecord]) {
        guard !records.isEmpty else { return }
        
        for record in records {
            let key = dateKey(from: record.localDate)
            workoutsByDate[key, default: []].append(record)
            
            totalWorkouts += 1
            totalLifetimeMiles += record.distance
            
            if record.qualifies {
                qualifyingDays.insert(key)
            }
            
            if let latest = latestWorkoutDate {
                if record.deviceEndDate > latest {
                    latestWorkoutDate = record.deviceEndDate
                    latestWorkoutUUID = record.id
                }
            } else {
                latestWorkoutDate = record.deviceEndDate
                latestWorkoutUUID = record.id
            }
        }
        
        lastUpdated = Date()
    }
    
    func workouts(for date: Date) -> [WorkoutRecord] {
        let key = dateKey(from: date)
        return workoutsByDate[key] ?? []
    }
    
    func hasQualifyingWorkout(on date: Date) -> Bool {
        let key = dateKey(from: date)
        return qualifyingDays.contains(key)
    }
    
    func totalMiles(for date: Date) -> Double {
        workouts(for: date).reduce(0) { $0 + $1.distance }
    }
    
    var allDates: [Date] {
        workoutsByDate.keys.compactMap { dateFromKey($0) }.sorted()
    }
    
    private func dateKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func dateFromKey(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }
}

extension WorkoutIndex {
    private static let indexKey = "com.mileaday.workoutIndex.v1"
    
    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let data = try? encoder.encode(self) {
            UserDefaults.standard.set(data, forKey: Self.indexKey)
            workoutIndexLog("[WorkoutIndex] ✅ Saved index: \(totalWorkouts) workouts, \(currentStreak) day streak")
        }
    }
    
    static func load() -> WorkoutIndex? {
        guard let data = UserDefaults.standard.data(forKey: indexKey) else {
            workoutIndexLog("[WorkoutIndex] No cached index found")
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let index = try? decoder.decode(WorkoutIndex.self, from: data) {
            workoutIndexLog("[WorkoutIndex] ✅ Loaded index: \(index.totalWorkouts) workouts, \(index.currentStreak) day streak")
            return index
        } else {
            workoutIndexLog("[WorkoutIndex] ❌ Failed to load index from stored data")
            return nil
        }
    }
    
    static func clear() {
        UserDefaults.standard.removeObject(forKey: indexKey)
        workoutIndexLog("[WorkoutIndex] 🗑️ Cleared cached index")
    }
}

final class WorkoutProcessor {
    private let calendar = Calendar.current
    
    func processWorkout(_ workout: HKWorkout) -> WorkoutRecord {
        let (localDate, offset) = determineLocalDateWithOffset(for: workout)
        return WorkoutRecord(from: workout, timezoneCorrectedDate: localDate, timezoneOffset: offset)
    }
    
    func processWorkouts(_ workouts: [HKWorkout]) -> [WorkoutRecord] {
        var records: [WorkoutRecord] = []
        
        for workout in workouts {
            let (localDate, offset) = determineLocalDateWithOffset(for: workout)
            records.append(WorkoutRecord(from: workout, timezoneCorrectedDate: localDate, timezoneOffset: offset))
        }
        
        return records
    }
    
    func calculateStreak(from records: [WorkoutRecord]) -> Int {
        var milesByDate: [Date: Double] = [:]
        
        for record in records {
            milesByDate[record.localDate, default: 0] += record.distance
        }
        
        let qualifyingDays = Set(milesByDate.filter { $0.value >= 0.95 }.keys)
        guard !qualifyingDays.isEmpty else { return 0 }
        
        let today = calendar.startOfDay(for: Date())
        var currentStreak = 0
        
        if qualifyingDays.contains(today) {
            currentStreak += 1
        }
        
        var checkDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        
        while qualifyingDays.contains(checkDate) {
            currentStreak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previousDay
            
            if currentStreak > 1000 { break }
        }
        
        return currentStreak
    }
    
    func qualifyingDays(from records: [WorkoutRecord]) -> Set<Date> {
        var milesByDate: [Date: Double] = [:]
        
        for record in records {
            milesByDate[record.localDate, default: 0] += record.distance
        }
        
        return Set(milesByDate.filter { $0.value >= 0.95 }.keys)
    }
    
    private func determineLocalDateWithOffset(for workout: HKWorkout) -> (Date, Int) {
        let deviceDate = workout.endDate
        let deviceStartOfDay = calendar.startOfDay(for: deviceDate)
        let hour = calendar.component(.hour, from: deviceDate)
        
        if hour >= 6 && hour <= 22 {
            return (deviceStartOfDay, 0)
        }
        
        let possibleOffsets = [-6, -5, -4, -3, -2, -1, 1, 2, 3, 4, 5, 6]
        
        for offset in possibleOffsets {
            guard let correctedDate = calendar.date(byAdding: .hour, value: offset, to: deviceDate) else {
                continue
            }
            
            let correctedHour = calendar.component(.hour, from: correctedDate)
            
            if correctedHour >= 6 && correctedHour <= 22 {
                let correctedDay = calendar.startOfDay(for: correctedDate)
                if correctedDay != deviceStartOfDay {
                    return (correctedDay, offset)
                }
            }
        }
        
        return (deviceStartOfDay, 0)
    }
}

struct AppPreferences: Codable {
    var useLocationBasedTimezone: Bool = false
    var showTimezoneDebugInfo: Bool = false
    
    static let `default` = AppPreferences()
    
    static func load() -> AppPreferences {
        .default
    }
    
    func save() {}
}
#endif
class HealthKitManager: ObservableObject {
    #if os(watchOS)
    static let shared = HealthKitManager()
    #endif
    
    let healthStore = HKHealthStore()
    
    @Published var isAuthorized = false
    @Published var todaysDistance: Double = 0.0
    @Published var recentWorkouts: [HKWorkout] = []
    @Published var totalLifetimeMiles: Double = 0.0
    @Published var fastestMilePace: TimeInterval = 0.0
    @Published var mostMilesInOneDay: Double = 0.0
    @Published var retroactiveStreak: Int = 0
    @Published var mostMilesWorkouts: [HKWorkout] = []
    @Published var todaysSteps: Int = 0
    @Published var dailyStepsData: [Date: Int] = [:]
    @Published var dailyMileGoals: [Date: Bool] = [:]
    
    // Caching properties
    @Published var cachedWorkouts: [HKWorkout] = []
    @Published var lastWorkoutCacheUpdate: Date?
    @Published var cachedFastestMilePace: TimeInterval = 0.0
    @Published var cachedMostMilesInOneDay: Double = 0.0
    @Published var cachedTotalLifetimeMiles: Double = 0.0
    @Published var cachedRetroactiveStreak: Int = 0
    @Published var cachedLatestWorkoutDate: Date?
    @Published var cachedWorkoutCount: Int = 0
    @Published var fastestMileWorkouts: [HKWorkout] = []
    @Published var currentStreakFastestMileWorkouts: [HKWorkout] = []
    
    // Efficient deduplication tracking
    private var cachedWorkoutUUIDs: Set<UUID> = []
    
    // MARK: - NEW: Persistent Workout Index (Phase 1 - Architectural Redesign)
    /// Single source of truth for workout data - eliminates inconsistencies
    #if !os(watchOS)
    @Published var workoutIndex: WorkoutIndex?
    private let workoutProcessor = WorkoutProcessor()
    private var isIndexBuilding = false
    #endif
    
    private func log(_ message: String) {}
    
    // Current streak caching properties
    @Published var cachedCurrentStreakFastestPace: TimeInterval = 0.0
    @Published var cachedCurrentStreakStats: (totalMiles: Double, mostMiles: Double, fastestPace: TimeInterval, streakDays: Int) = (0.0, 0.0, 0.0, 0)
    @Published var lastCurrentStreakStatsUpdate: Date?
    
    // Feature flag for location-based timezone calculation
    // When true, uses workout location to determine timezone for streak calculation
    // When false, uses device timezone (legacy behavior)
    // TEMPORARILY DISABLED due to deadlock issues
    @Published var useLocationBasedTimezone: Bool = false
    
    // Debug info for timezone calculations
    @Published var timezoneDebugInfo: String = ""
    
    init() {
        #if os(watchOS)
        // For watchOS, use simplified initialization
        loadCachedData()
        #else
        // Load preferences on initialization
        let prefs = AppPreferences.load()
        self.useLocationBasedTimezone = prefs.useLocationBasedTimezone
        
        // PHASE 1: Try to load workout index first (instant)
        if let cachedIndex = WorkoutIndex.load() {
            self.workoutIndex = cachedIndex
            log("[HealthKit] ✅ Loaded workout index: \(cachedIndex.currentStreak) day streak, \(cachedIndex.totalWorkouts) workouts")
            
            // Use index data immediately (no 72→161 jump!)
            self.retroactiveStreak = cachedIndex.currentStreak
        } else {
            log("[HealthKit] 📋 No workout index found - will build on first data fetch")
        }
        
        // Load cached data on initialization
        loadCachedData()
        #endif
    }
    
    // MARK: - Caching Methods
    
    /// Loads cached data from UserDefaults
    private func loadCachedData() {
        let defaults = UserDefaults.standard
        
        // Load cached values
        cachedFastestMilePace = defaults.double(forKey: "cachedFastestMilePace")
        cachedMostMilesInOneDay = defaults.double(forKey: "cachedMostMilesInOneDay")
        cachedTotalLifetimeMiles = defaults.double(forKey: "cachedTotalLifetimeMiles")
        cachedRetroactiveStreak = defaults.integer(forKey: "cachedRetroactiveStreak")
        cachedWorkoutCount = defaults.integer(forKey: "cachedWorkoutCount")
        
        // Load last cache update date
        if let lastUpdate = defaults.object(forKey: "lastWorkoutCacheUpdate") as? Date {
            lastWorkoutCacheUpdate = lastUpdate
        }
        
        // Load latest workout date
        if let latestWorkoutDate = defaults.object(forKey: "cachedLatestWorkoutDate") as? Date {
            cachedLatestWorkoutDate = latestWorkoutDate
        }
        
        // Load current streak cached data
        cachedCurrentStreakFastestPace = defaults.double(forKey: "cachedCurrentStreakFastestPace")
        let cachedStreakTotalMiles = defaults.double(forKey: "cachedCurrentStreakTotalMiles")
        let cachedStreakMostMiles = defaults.double(forKey: "cachedCurrentStreakMostMiles")
        let cachedStreakDays = defaults.integer(forKey: "cachedCurrentStreakDays")
        cachedCurrentStreakStats = (cachedStreakTotalMiles, cachedStreakMostMiles, cachedCurrentStreakFastestPace, cachedStreakDays)
        
        if let lastStreakUpdate = defaults.object(forKey: "lastCurrentStreakStatsUpdate") as? Date {
            lastCurrentStreakStatsUpdate = lastStreakUpdate
        }
        
        // Set current values from cache if available
        if cachedFastestMilePace > 0 {
            fastestMilePace = cachedFastestMilePace
        }
        if cachedMostMilesInOneDay > 0 {
            mostMilesInOneDay = cachedMostMilesInOneDay
        }
        if cachedTotalLifetimeMiles > 0 {
            totalLifetimeMiles = cachedTotalLifetimeMiles
        }
        if cachedRetroactiveStreak > 0 {
            retroactiveStreak = cachedRetroactiveStreak
        }
            }
    
    /// Saves current data to cache
    private func saveCachedData() {
        let defaults = UserDefaults.standard
        
        // Save current values
        defaults.set(fastestMilePace, forKey: "cachedFastestMilePace")
        defaults.set(mostMilesInOneDay, forKey: "cachedMostMilesInOneDay")
        defaults.set(totalLifetimeMiles, forKey: "cachedTotalLifetimeMiles")
        defaults.set(retroactiveStreak, forKey: "cachedRetroactiveStreak")
        defaults.set(cachedWorkoutCount, forKey: "cachedWorkoutCount")
        defaults.set(Date(), forKey: "lastWorkoutCacheUpdate")
        
        // Save latest workout date if available
        if let latestWorkoutDate = cachedLatestWorkoutDate {
            defaults.set(latestWorkoutDate, forKey: "cachedLatestWorkoutDate")
        }
        
        // Save current streak cache
        defaults.set(cachedCurrentStreakStats.fastestPace, forKey: "cachedCurrentStreakFastestPace")
        defaults.set(cachedCurrentStreakStats.totalMiles, forKey: "cachedCurrentStreakTotalMiles")
        defaults.set(cachedCurrentStreakStats.mostMiles, forKey: "cachedCurrentStreakMostMiles")
        defaults.set(cachedCurrentStreakStats.streakDays, forKey: "cachedCurrentStreakDays")
        defaults.set(Date(), forKey: "lastCurrentStreakStatsUpdate")
        
        // UPDATE: Only update @Published properties on main thread
        if Thread.isMainThread {
            // Update cached values (these are @Published properties)
            cachedFastestMilePace = fastestMilePace
            cachedMostMilesInOneDay = mostMilesInOneDay
            cachedTotalLifetimeMiles = totalLifetimeMiles
            cachedRetroactiveStreak = retroactiveStreak
            lastWorkoutCacheUpdate = Date()
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Update cached values (these are @Published properties)
                self.cachedFastestMilePace = self.fastestMilePace
                self.cachedMostMilesInOneDay = self.mostMilesInOneDay
                self.cachedTotalLifetimeMiles = self.totalLifetimeMiles
                self.cachedRetroactiveStreak = self.retroactiveStreak
                self.lastWorkoutCacheUpdate = Date()
            }
        }
    }
    
    /// Checks if cache is still valid and if we need to fetch new workouts
    private func isCacheValid() -> Bool {
        guard let lastUpdate = lastWorkoutCacheUpdate else { return false }
        let oneHourAgo = Date().addingTimeInterval(-3600) // 1 hour
        return lastUpdate > oneHourAgo
    }
    
    /// Checks if we need to fetch new workouts based on latest workout date
    /// Uses a lightweight query to check for new workouts without fetching them
    private func needsNewWorkoutFetch() -> Bool {
        // If no cached data, we need to fetch
        guard cachedLatestWorkoutDate != nil else { 
            log("[HealthKit] No cached data, need initial fetch")
            return true 
        }
        
        // If cache is older than 1 hour, check for new workouts
        guard let lastUpdate = lastWorkoutCacheUpdate else { 
            log("[HealthKit] No last update time, need to fetch")
            return true 
        }
        
        let oneHourAgo = Date().addingTimeInterval(-3600)
        if lastUpdate < oneHourAgo {
            log("[HealthKit] Cache is older than 1 hour, checking for new workouts...")
            // Perform lightweight check to see if there are new workouts
            return hasNewWorkoutsSinceCache()
        }
        
        // If we have very recent cache (< 1 hour), we're good
        log("[HealthKit] Cache is recent (< 1 hour), no need to fetch")
        return false
    }
    
    /// Lightweight query to check if there are new workouts without fetching them
    private func hasNewWorkoutsSinceCache() -> Bool {
        guard let lastWorkoutDate = cachedLatestWorkoutDate else { return true }
        
        // This is a synchronous check - in production, you might want to make this async
        // For now, we'll use a simple heuristic: if it's a new day or > 1 hour, assume there might be new workouts
        let calendar = Calendar.current
        let now = Date()
        
        // If last workout was yesterday or earlier, likely new workouts exist
        if !calendar.isDate(lastWorkoutDate, inSameDayAs: now) {
            log("[HealthKit] Last workout was on different day, likely new workouts exist")
            return true
        }
        
        // If last cache update was more than 2 hours ago, check again
        if let lastUpdate = lastWorkoutCacheUpdate {
            let twoHoursAgo = now.addingTimeInterval(-2 * 3600)
            if lastUpdate < twoHoursAgo {
                log("[HealthKit] Cache is > 2 hours old, checking for new workouts")
                return true
            }
        }
        
        log("[HealthKit] Recent cache for today, likely no new workouts")
        return false
    }
    
    /// Gets the date to start fetching workouts from (either from cache or beginning)
    private func getWorkoutFetchStartDate() -> Date? {
        // If we have a cached latest workout date, start from there
        if let lastWorkoutDate = cachedLatestWorkoutDate {
            // Add a small buffer (1 hour) to catch any workouts that might have been recorded
            // at the same time but processed slightly later
            return lastWorkoutDate.addingTimeInterval(-3600) // 1 hour buffer
        }
        
        // No cached data, start from beginning
        return nil
    }
    
    // Request authorization to access HealthKit data
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        
        // Define the types we want to read from HealthKit
        let readTypes: Set = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKSeriesType.workoutRoute()
        ]

        // Define the types we want to write to HealthKit (for workout tracking)
        let writeTypes: Set = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, error in
            DispatchQueue.main.async {
                self.isAuthorized = success
                
                // Enable background delivery for workouts when authorized
                if success {
                    self.enableBackgroundDelivery()
                }
                
                completion(success)
            }
        }
    }
    
    // Enable background delivery for HealthKit data
    private func enableBackgroundDelivery() {
        let workoutType = HKObjectType.workoutType()
        
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { success, error in
            if success {
            } else {
                // Background delivery failed
            }
        }
    }
    
    // Fetch today's running/walking distance from workouts only
    // Updated to use location-aware day calculation
    func fetchTodaysDistance() {
        guard isAuthorized else { return }
        
        let now = Date()
        
        // Get all recent workouts to filter by local timezone
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        
        // Look for workouts from the last 48 hours to catch timezone edge cases
        let lookbackTime = Calendar.current.date(byAdding: .hour, value: -48, to: now)!
        let recentPredicate = HKQuery.predicateForSamples(withStart: lookbackTime, end: now, options: .strictStartDate)
        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [compoundPredicate, recentPredicate])
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: finalPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self = self, let workouts = samples as? [HKWorkout], !workouts.isEmpty else {
                DispatchQueue.main.async {
                    self?.todaysDistance = 0.0
                    #if !os(watchOS)
                    // Get current goal from widget store or default to 1.0
                    let widgetData = WidgetDataStore.load()
                    let currentGoal = widgetData.goal
                    let safeGoal = currentGoal > 0 ? currentGoal : 1.0
                    
                    // Use unified progress calculation
                    WidgetDataStore.save(todayMiles: 0, goal: safeGoal)
                    #endif
                }
                return
            }
            
            // Filter workouts based on timezone setting
            if self.useLocationBasedTimezone {
                // Filter workouts to find those that occurred "today" in their local timezone
                self.filterWorkoutsForToday(workouts: workouts) { todaysWorkouts in
                    self.processTodaysWorkouts(todaysWorkouts)
                }
            } else {
                // Legacy behavior: filter by device timezone
                let todaysWorkouts = self.filterWorkoutsByDeviceToday(workouts: workouts)
                self.processTodaysWorkouts(todaysWorkouts)
            }
        }
        
        healthStore.execute(query)
    }
    
    // Fetch recent running/walking workouts
    func fetchRecentWorkouts() {
        guard isAuthorized else { return }
        
        // Look for both running and walking workouts
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: compoundPredicate,
            limit: 50, // Increased for testing workout uploads
            sortDescriptors: [sortDescriptor]
        ) { [weak self] query, samples, error in
            guard let self = self, let workouts = samples as? [HKWorkout] else { return }
            
            DispatchQueue.main.async {
                self.recentWorkouts = workouts
            }
        }
        
        healthStore.execute(query)
    }
    
    // Helper method to check if user has completed their mile goal today
    // Includes a small offset (0.05 miles) for rounding
    func hasCompletedMileToday() -> Bool {
        return todaysDistance >= 0.95
    }
    
    // MARK: - Today's Stats (Computed Properties)
    
    /// Today's total workout duration in seconds
    var todaysTotalDuration: TimeInterval {
        return recentWorkouts.reduce(0) { $0 + $1.duration }
    }
    
    /// Today's average pace in minutes per mile (calculated from all today's workouts)
    var todaysAveragePace: TimeInterval? {
        guard todaysDistance > 0 else { return nil }
        let totalDurationMinutes = todaysTotalDuration / 60.0
        return totalDurationMinutes / todaysDistance
    }
    
    /// Today's fastest pace from individual workouts (best single workout pace today)
    var todaysFastestPace: TimeInterval? {
        var fastestPace: TimeInterval = .infinity
        
        for workout in recentWorkouts {
            if let distance = workout.totalDistance {
                let miles = distance.doubleValue(for: HKUnit.mile())
                if miles >= 0.5 { // Only consider workouts with at least half a mile
                    let pace = (workout.duration / 60.0) / miles
                    if pace < fastestPace {
                        fastestPace = pace
                    }
                }
            }
        }
        
        return fastestPace == .infinity ? nil : fastestPace
    }
    
    /// Today's total calories burned (estimated from workouts)
    var todaysTotalCalories: Double {
        return recentWorkouts.reduce(0) { total, workout in
            if #available(iOS 18.0, *) {
                if let statistics = workout.statistics(for: HKQuantityType(.activeEnergyBurned)),
                   let energy = statistics.sumQuantity() {
                    return total + energy.doubleValue(for: .kilocalorie())
                }
            } else if let energyBurned = workout.totalEnergyBurned {
                // Fallback for iOS versions before the deprecation of totalEnergyBurned
                return total + energyBurned.doubleValue(for: .kilocalorie())
            }
            return total
        }
    }
    
    /// Number of workouts completed today
    var todaysWorkoutCount: Int {
        return recentWorkouts.count
    }
    
    // Get distance in miles from a workout
    func distanceInMiles(from workout: HKWorkout) -> Double {
        guard let distance = workout.totalDistance else { return 0 }
        return distance.doubleValue(for: HKUnit.mile())
    }
    
    // MARK: - New Methods for Enhanced Tracking
    
    // Fetch total lifetime miles from all running and walking workouts
    func fetchTotalLifetimeMiles() {
        guard isAuthorized else { return }
        
        // Look for both running and walking workouts
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: compoundPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [weak self] _, samples, error in
            guard let self = self, let workouts = samples as? [HKWorkout] else { return }
            
            var totalMiles: Double = 0.0
            
            for workout in workouts {
                if let distance = workout.totalDistance {
                    let miles = distance.doubleValue(for: HKUnit.mile())
                    totalMiles += miles
                }
            }
            
            DispatchQueue.main.async {
                self.totalLifetimeMiles = totalMiles
            }
        }
        
        healthStore.execute(query)
    }
    
    // Calculate personal records and retroactive streak
    func calculatePersonalRecords() {
        guard isAuthorized else { return }
        
        #if !os(watchOS)
        // CRITICAL FIX: If index exists, use it for streak and total miles
        if let index = workoutIndex {
            DispatchQueue.main.async {
                self.retroactiveStreak = index.currentStreak
                self.totalLifetimeMiles = index.totalLifetimeMiles
                self.saveCachedData()
            }
            // Continue calculating other stats (fastest pace, most miles) from cached workouts
        }
        #endif
        
        // OPTIMIZATION: If we have cached workouts, use them instead of fetching ALL workouts again
        if !cachedWorkouts.isEmpty && cachedLatestWorkoutDate != nil {
                    self.log("[HealthKit] OPTIMIZED: Using \(cachedWorkouts.count) cached workouts for personal records calculation (NO FETCH)")
            
            // Use cached workouts directly
            let workouts = cachedWorkouts
            
            // Update cached workout UUIDs set if not already populated
            if cachedWorkoutUUIDs.isEmpty {
                cachedWorkoutUUIDs = Set(workouts.map { $0.uuid })
                log("[HealthKit] Populated UUID cache with \(cachedWorkoutUUIDs.count) workout IDs")
            }
            
            // Track most miles in a day
            let mostMilesInDay: Double = 0.0
            let mostMilesWorkouts: [HKWorkout] = []
            
            // Group workouts by day using location-aware time zones if enabled
            if self.useLocationBasedTimezone {
                    // For large datasets, only process recent workouts with location-aware logic
                    if workouts.count > 100 {                    
                        // Split into recent (last 30 days) and older workouts (placeholder for future optimization)
                        // TEMPORARY: Use device timezone for all until we fix the deadlock
                        let allWorkoutsByDay = self.groupWorkoutsByDeviceDay(workouts: workouts)
                        self.processWorkoutsByDay(allWorkoutsByDay, mostMilesInDay: mostMilesInDay, mostMilesWorkouts: mostMilesWorkouts)
                    } else {
                        // TEMPORARY: Use device timezone even for small datasets to prevent deadlock
                        let workoutsByDay = self.groupWorkoutsByDeviceDay(workouts: workouts)
                        self.processWorkoutsByDay(workoutsByDay, mostMilesInDay: mostMilesInDay, mostMilesWorkouts: mostMilesWorkouts)
                    }
            } else {
                // Legacy behavior: group by device timezone (safer for large datasets)
                log("[HealthKit] Using device timezone grouping (\(workouts.count) workouts)")
                let workoutsByDay = self.groupWorkoutsWithTimezoneAwareness(workouts: workouts)
                self.processWorkoutsByDay(workoutsByDay, mostMilesInDay: mostMilesInDay, mostMilesWorkouts: mostMilesWorkouts)
            }
            
            // Early return - we're done, no need to fetch
            return
        }
        
        // No cached data - need to fetch ALL workouts (initial load only)
        log("[HealthKit] No cached data - performing initial full workout fetch")
        
        // Look for both running and walking workouts
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        
        // Sort by date to calculate streak
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: compoundPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self = self, let workouts = samples as? [HKWorkout] else { return }
            
            // Populate cached workouts for future use
            DispatchQueue.main.async {
                self.cachedWorkouts = workouts
                self.cachedWorkoutCount = workouts.count
                self.cachedWorkoutUUIDs = Set(workouts.map { $0.uuid })
                if let latestWorkout = workouts.max(by: { $0.endDate < $1.endDate }) {
                    self.cachedLatestWorkoutDate = latestWorkout.endDate
                }
                self.log("[HealthKit] Initial fetch: Populated cachedWorkouts with \(workouts.count) workouts")
            }
            
            // Track most miles in a day
            let mostMilesInDay: Double = 0.0
            let mostMilesWorkouts: [HKWorkout] = []
            
            // Group workouts by day using location-aware time zones if enabled
            if self.useLocationBasedTimezone {
                // For large datasets, only process recent workouts with location-aware logic
                if workouts.count > 100 {
                    log("[HealthKit] Large dataset (\(workouts.count) workouts) - using hybrid approach")
                    
                    // Split into recent (last 30 days) and older workouts
                    let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                    let recentWorkouts = workouts.filter { $0.endDate >= thirtyDaysAgo }
                    let olderWorkouts = workouts.filter { $0.endDate < thirtyDaysAgo }
                    
                    log("[HealthKit] Processing \(recentWorkouts.count) recent workouts with location-aware timezone")
                    log("[HealthKit] Processing \(olderWorkouts.count) older workouts with device timezone")
                    
                    // TEMPORARY: Use device timezone for all until we fix the deadlock
                    log("[HealthKit] Temporarily using device timezone for all workouts to prevent deadlock")
                    let allWorkoutsByDay = self.groupWorkoutsByDeviceDay(workouts: workouts)
                    self.processWorkoutsByDay(allWorkoutsByDay, mostMilesInDay: mostMilesInDay, mostMilesWorkouts: mostMilesWorkouts)
                } else {
                    // TEMPORARY: Use device timezone even for small datasets to prevent deadlock
                    log("[HealthKit] Small dataset (\(workouts.count) workouts) - temporarily using device timezone")
                    let workoutsByDay = self.groupWorkoutsByDeviceDay(workouts: workouts)
                    self.processWorkoutsByDay(workoutsByDay, mostMilesInDay: mostMilesInDay, mostMilesWorkouts: mostMilesWorkouts)
                }
            } else {
                // Legacy behavior: group by device timezone (safer for large datasets)
                log("[HealthKit] Using device timezone grouping (\(workouts.count) workouts)")
                let workoutsByDay = self.groupWorkoutsWithTimezoneAwareness(workouts: workouts)
                self.processWorkoutsByDay(workoutsByDay, mostMilesInDay: mostMilesInDay, mostMilesWorkouts: mostMilesWorkouts)
            }
        }
        
        healthStore.execute(query)
    }
    
        // Fetch fastest mile pace from workout data (prioritizing split times over average pace)
    func fetchFastestMilePace() {
        // Use smart approach if we have cached workouts
        if !cachedWorkouts.isEmpty {
            fetchFastestMilePaceSmartly()
            return
        }
        
        // Fallback to full fetch if no cached workouts
        guard isAuthorized else { 
            return 
        }
        
        // Get all running and walking workouts
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        
        let workoutQuery = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: compoundPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [weak self] _, samples, error in
            guard let self = self else { 
                return 
            }
            
            if let error = error {
                log("[HealthKit] ❌ Failed to fetch workouts for fastest pace: \(error.localizedDescription)")
                return
            }
            
            guard let workouts = samples as? [HKWorkout] else {
                return
            }
            
            var fastestPace: TimeInterval = .infinity
            var processedWorkouts = 0
            let dispatchGroup = DispatchGroup()
            
            // Process workouts that are at least 0.95 miles
            let qualifyingWorkouts = workouts.filter { workout in
                if let distance = workout.totalDistance {
                    let miles = distance.doubleValue(for: HKUnit.mile())
                    return miles >= 0.95
                }
                return false
            }
            
            // Process each qualifying workout to get the fastest mile time
            for workout in qualifyingWorkouts {
                dispatchGroup.enter()
                
                self.calculateFastestMileTime(from: workout) { mileTime in
                    defer { dispatchGroup.leave() }
                    
                    if let mileTime = mileTime {
                        processedWorkouts += 1
                        if mileTime < fastestPace {
                            fastestPace = mileTime
                        }
                    }
                }
            }
            
            // Wait for all workout processing to complete
            dispatchGroup.notify(queue: .main) {
                let calculatedPace = fastestPace == .infinity ? 0.0 : fastestPace
                
                self.fastestMilePace = calculatedPace
                
                if calculatedPace > 0 {
                    // Find workouts that achieved this fastest mile pace
                    self.findFastestMileWorkouts()
                }
                
                // Save to cache after calculating fastest pace
                self.saveCachedData()
            }
        }
        
        healthStore.execute(workoutQuery)
    }
    
    // MARK: - Workout Processing Helpers
    
    /// Processes workouts grouped by day to calculate statistics and streaks
    private func processWorkoutsByDay(_ workoutsByDay: [Date: [HKWorkout]], mostMilesInDay: Double, mostMilesWorkouts: [HKWorkout]) {
        #if !os(watchOS)
        // CRITICAL FIX: If index exists, DON'T run old streak calculation (use index value instead)
        if let index = workoutIndex {
            let indexMostMiles = index.mostMilesInOneDay
            log("[HealthKit] ✅ Index available, skipping old streak calculation. Using index streak: \(index.currentStreak), mostMilesInOneDay: \(indexMostMiles)")
            DispatchQueue.main.async {
                self.retroactiveStreak = index.currentStreak
                self.mostMilesInOneDay = indexMostMiles
                self.mostMilesWorkouts = [] // Index has no HKWorkouts; use empty (stats still correct)
                self.saveCachedData() // Save correct value from index
            }
            return // Skip old calculation entirely
        }
        #endif
        
        log("[HealthKit] Processing workouts by day for statistics...")
        var finalMostMilesInDay = mostMilesInDay
        var finalMostMilesWorkouts = mostMilesWorkouts
        
        // Calculate most miles in a day
        for (_, dayWorkouts) in workoutsByDay {
            var totalMilesForDay: Double = 0.0
            
            for workout in dayWorkouts {
                if let distance = workout.totalDistance {
                    let miles = distance.doubleValue(for: HKUnit.mile())
                    totalMilesForDay += miles
                }
            }
            
            if totalMilesForDay > finalMostMilesInDay {
                finalMostMilesInDay = totalMilesForDay
                finalMostMilesWorkouts = dayWorkouts
            }
        }
        
        // Calculate retroactive streak (this now includes timezone corrections)
        let streak = self.calculateRetroactiveStreak(workoutsByDay: workoutsByDay)
        
        DispatchQueue.main.async {
            // NOTE: mostMilesInOneDay will be updated by calculateRetroactiveStreak with timezone corrections
            // Only update if we don't have timezone corrections to apply
            if !self.useLocationBasedTimezone {
                self.mostMilesInOneDay = finalMostMilesInDay
                self.mostMilesWorkouts = finalMostMilesWorkouts
            }
            self.retroactiveStreak = streak
            
            // Save to cache after processing
            self.saveCachedData()
        }
        
        // Now fetch the fastest mile pace separately using proper HealthKit speed data
        self.fetchFastestMilePace()
    }
    
    /// Legacy method: groups workouts by device timezone (pre-location-aware behavior)
    private func groupWorkoutsByDeviceDay(workouts: [HKWorkout]) -> [Date: [HKWorkout]] {
        var workoutsByDay: [Date: [HKWorkout]] = [:]
        let calendar = Calendar.current
        
        for workout in workouts {
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: workout.endDate)
            if let date = calendar.date(from: dateComponents) {
                if workoutsByDay[date] == nil {
                    workoutsByDay[date] = []
                }
                workoutsByDay[date]?.append(workout)
            }
        }
        
        return workoutsByDay
    }
    
    /// Filters workouts for today using device timezone (legacy behavior)
    private func filterWorkoutsByDeviceToday(workouts: [HKWorkout]) -> [HKWorkout] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let _ = calendar.date(byAdding: .day, value: 1, to: today)!
        
        return workouts.filter { workout in
            let workoutDate = calendar.startOfDay(for: workout.endDate)
            return workoutDate == today
        }
    }
    
    /// Processes today's filtered workouts to calculate distance and update UI
    private func processTodaysWorkouts(_ todaysWorkouts: [HKWorkout]) {
        var totalMiles: Double = 0.0
        
        for workout in todaysWorkouts {
            if let distance = workout.totalDistance {
                let miles = distance.doubleValue(for: HKUnit.mile())
                totalMiles += miles
            }
        }
        
        DispatchQueue.main.async {
            self.todaysDistance = totalMiles
            self.recentWorkouts = todaysWorkouts
            #if !os(watchOS)
            // Get current goal from widget store or default to 1.0
            let widgetData = WidgetDataStore.load()
            let currentGoal = widgetData.goal
            let safeGoal = currentGoal > 0 ? currentGoal : 1.0
            
            // Use unified progress calculation
            WidgetDataStore.save(todayMiles: totalMiles, goal: safeGoal)
            #endif
        }
    }
    
    // MARK: - Location-Aware Workout Grouping
    
    /// Groups workouts by local day based on workout location time zones
    /// This ensures that streaks are calculated based on the local time where the workout occurred,
    /// not the user's current time zone
    private func groupWorkoutsByLocalDay(workouts: [HKWorkout], completion: @escaping ([Date: [HKWorkout]]) -> Void) {
        var workoutsByDay: [Date: [HKWorkout]] = [:]
        let dispatchGroup = DispatchGroup()
        let processQueue = DispatchQueue(label: "com.mileaday.workout-processing", qos: .userInitiated)
        
        
        // Limit concurrent operations to prevent overwhelming the system
        let maxConcurrentOperations = min(workouts.count, 10)
        let semaphore = DispatchSemaphore(value: maxConcurrentOperations)
        
        for workout in workouts {
            dispatchGroup.enter()
            semaphore.wait()
            
            processQueue.async {
                self.getLocalCalendar(for: workout) { calendar in
                    defer {
                        semaphore.signal()
                        dispatchGroup.leave()
                    }
                    
                    // Get the local date components for this workout
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: workout.endDate)
                    
                    if let localDate = calendar.date(from: dateComponents) {
                        DispatchQueue.main.async {
                            if workoutsByDay[localDate] == nil {
                                workoutsByDay[localDate] = []
                            }
                            workoutsByDay[localDate]?.append(workout)
                        }
                        
                    } else {
                        // Could not create local date for workout
                    }
                }
            }
        }
        
        // Use notify instead of wait to avoid blocking
        dispatchGroup.notify(queue: .main) {
            let debugInfo = "Grouped \(workouts.count) workouts into \(workoutsByDay.count) distinct days using location-aware timezones"
            self.timezoneDebugInfo = debugInfo
            completion(workoutsByDay)
        }
    }
    
    /// Filters workouts to find those that occurred "today" in their local time zone
    private func filterWorkoutsForToday(workouts: [HKWorkout], completion: @escaping ([HKWorkout]) -> Void) {
        // For now, use a simpler approach to avoid deadlocks
        // We'll filter based on device timezone and add location-aware logic later
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let todaysWorkouts = workouts.filter { workout in
            let workoutDate = calendar.startOfDay(for: workout.endDate)
            return workoutDate == today
        }
        
        completion(todaysWorkouts)
    }
    
    /// Filters workouts to find those that occurred on a specific date in their local time zone
    private func filterWorkoutsForSpecificDate(workouts: [HKWorkout], targetDate: Date, completion: @escaping ([HKWorkout]) -> Void) {
        // Use device timezone for now to avoid deadlocks
        let calendar = Calendar.current
        let targetDateStart = calendar.startOfDay(for: targetDate)
        
        let targetDateWorkouts = workouts.filter { workout in
            let workoutDate = calendar.startOfDay(for: workout.endDate)
            return workoutDate == targetDateStart
        }
        
        completion(targetDateWorkouts)
    }
    
    // MARK: - Timezone Utilities
    
    /// Gets the local calendar for a workout based on its location
    /// Falls back to intelligent timezone guessing and then device timezone
    private func getLocalCalendar(for workout: HKWorkout, completion: @escaping (Calendar) -> Void) {
        // Try to get location from workout metadata first
        if let location = getLocationFromWorkoutMetadata(workout) {
            let timeZone = getTimeZone(for: location)
            var calendar = Calendar.current
            calendar.timeZone = timeZone
            completion(calendar)
            return
        }
        
        // Try to get location from workout route
        getLocationFromWorkoutRoute(workout) { [weak self] location in
            if let location = location {
                let timeZone = self?.getTimeZone(for: location) ?? TimeZone.current
                var calendar = Calendar.current
                calendar.timeZone = timeZone
                completion(calendar)
                return
            }
            
            // Fallback: Try to guess timezone based on workout timing patterns
            if let guessedTimeZone = self?.guessTimeZoneFromWorkoutTiming(workout) {
                var calendar = Calendar.current
                calendar.timeZone = guessedTimeZone
                completion(calendar)
                return
            }
            
            // Final fallback to device timezone
            completion(Calendar.current)
        }
    }
    
    /// Attempts to guess timezone based on workout timing patterns
    /// This is a heuristic fallback when location data isn't available
    private func guessTimeZoneFromWorkoutTiming(_ workout: HKWorkout) -> TimeZone? {
        // If the workout has metadata indicating it was recorded by a specific app,
        // we might be able to make educated guesses about timezone based on
        // the user's historical patterns
        
        // For now, we'll use a simple heuristic: if the workout time seems unusual
        // for the current timezone (e.g., 3 AM local time), it might have been
        // recorded in a different timezone
        
        let currentCalendar = Calendar.current
        let workoutHour = currentCalendar.component(.hour, from: workout.endDate)
        
        // If workout was at an unusual hour (midnight to 5 AM), it might be from another timezone
        if workoutHour >= 0 && workoutHour <= 5 {
            // This is a very basic heuristic - in a production app, you'd want more sophisticated logic
            // based on user's travel patterns, app usage history, etc.
        }
        
        return nil // Return nil to use device timezone as final fallback
    }
    
    /// Extracts location from workout metadata if available
    private func getLocationFromWorkoutMetadata(_ workout: HKWorkout) -> CLLocation? {
        // Check if workout has metadata with location
        if let metadata = workout.metadata {
            // Look for location in various possible metadata keys
            // Some apps store location data in custom metadata
            // This is a simplified approach - in practice you'd need app-specific parsing
            
            // For now, we don't have a standard way to extract location from metadata
            // This could be enhanced in the future for specific fitness apps
            _ = metadata[HKMetadataKeyWorkoutBrandName] // Acknowledge we checked for brand name
        }
        return nil
    }
    
    /// Gets location from workout route if available
    private func getLocationFromWorkoutRoute(_ workout: HKWorkout, completion: @escaping (CLLocation?) -> Void) {
        // Query for workout routes associated with this workout
        let routePredicate = HKQuery.predicateForObjects(from: workout)
        
        let routeQuery = HKAnchoredObjectQuery(
            type: HKSeriesType.workoutRoute(),
            predicate: routePredicate,
            anchor: nil,
            limit: 1
        ) { [weak self] _, samples, _, _, error in
            guard let self = self,
                  let routes = samples as? [HKWorkoutRoute],
                  let route = routes.first else {
                completion(nil)
                return
            }
            
            // Get first location from the route
            let locationQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let firstLocation = locations?.first {
                    completion(firstLocation)
                } else if done {
                    completion(nil)
                }
            }
            
            self.healthStore.execute(locationQuery)
        }
        
        healthStore.execute(routeQuery)
    }
    
    /// Gets the appropriate timezone for a given location
    private func getTimeZone(for location: CLLocation) -> TimeZone {
        // For more accurate timezone detection, we could use a timezone database
        // For now, we'll use a simplified approach based on coordinate ranges
        
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        
        // Common timezone mappings (simplified)
        // Hawaii: UTC-10
        if longitude >= -161 && longitude <= -154 && latitude >= 18.9 && latitude <= 22.3 {
            return TimeZone(identifier: "Pacific/Honolulu") ?? TimeZone.current
        }
        
        // Pacific Time: UTC-8/-7
        if longitude >= -125 && longitude <= -114 {
            return TimeZone(identifier: "America/Los_Angeles") ?? TimeZone.current
        }
        
        // Mountain Time: UTC-7/-6
        if longitude >= -115 && longitude <= -104 {
            return TimeZone(identifier: "America/Denver") ?? TimeZone.current
        }
        
        // Central Time: UTC-6/-5
        if longitude >= -105 && longitude <= -87 {
            return TimeZone(identifier: "America/Chicago") ?? TimeZone.current
        }
        
        // Eastern Time: UTC-5/-4 (includes Philadelphia)
        if longitude >= -88 && longitude <= -67 {
            return TimeZone(identifier: "America/New_York") ?? TimeZone.current
        }
        
        // Fallback to current timezone
        return TimeZone.current
    }
    
    // Helper to calculate retroactive streak from workout data with timezone awareness
    private func calculateRetroactiveStreak(workoutsByDay: [Date: [HKWorkout]]) -> Int {
        log("[HealthKit] Calculating streak...")
        
        // CRITICAL: workoutsByDay is already timezone-corrected by groupWorkoutsWithTimezoneAwareness()
        // This ensures calendar and streak use IDENTICAL timezone logic - no duplicate corrections needed
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let correctedWorkoutsByDay = workoutsByDay // Already timezone-corrected!
        
        // Calculate streak with timezone-corrected data
        log("[HealthKit] Calculating qualifying workout days from timezone-corrected data...")
        let daysWithQualifyingWorkouts = correctedWorkoutsByDay.compactMap { (date, workouts) -> Date? in
            let totalMilesForDay = workouts.reduce(0.0) { total, workout in
                if let distance = workout.totalDistance {
                    return total + distance.doubleValue(for: HKUnit.mile())
                }
                return total
            }
            
            if totalMilesForDay >= 0.95 {
                return date
            } else {
                return nil
            }
        }.sorted(by: >)
        
        guard !daysWithQualifyingWorkouts.isEmpty else { 
            return 0 
        }
        
        // CALCULATE MOST MILES IN ONE DAY from timezone-corrected data
        var correctedMostMilesInDay: Double = 0.0
        var correctedMostMilesWorkouts: [HKWorkout] = []
        
        for (_, workouts) in correctedWorkoutsByDay {
            let totalMilesForDay = workouts.reduce(0.0) { total, workout in
                if let distance = workout.totalDistance {
                    return total + distance.doubleValue(for: HKUnit.mile())
                }
                return total
            }
            
            if totalMilesForDay > correctedMostMilesInDay {
                correctedMostMilesInDay = totalMilesForDay
                correctedMostMilesWorkouts = workouts
            }
        }
        
        // Update the mostMilesInOneDay with timezone-corrected value
        DispatchQueue.main.async {
            self.mostMilesInOneDay = correctedMostMilesInDay
            self.mostMilesWorkouts = correctedMostMilesWorkouts
            
            // Update calendar data with timezone-corrected workout grouping
            self.updateCalendarWithTimezoneCorrectedData(correctedWorkoutsByDay: correctedWorkoutsByDay)
        }
        
        // Calculate current streak
        var currentStreak = 0
        var checkDate = today
        
        // Check if today has qualifying workouts
        if daysWithQualifyingWorkouts.contains(today) {
            currentStreak += 1
        }
        
        // Check previous days
        checkDate = calendar.date(byAdding: .day, value: -1, to: today)!
        
        while true {
            if daysWithQualifyingWorkouts.contains(checkDate) {
                currentStreak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                break
            }
            
            // Safety break to avoid infinite loops
            if currentStreak > 1000 {
                break
            }
        }
        
        return currentStreak
    }
    
    // Function to fetch all workout data in one call
    func fetchAllWorkoutData() {
        #if !os(watchOS)
        // PHASE 1: Check if we need to build/update workout index
        Task {
            if workoutIndex == nil {
                // No index exists - build it (one-time, then cached forever)
                log("[HealthKit] 🏗️ No index found, building initial workout index...")
                await buildWorkoutIndex()
            } else {
                // Index exists - check for new workouts (fast, incremental)
                await updateIndexWithNewWorkouts()
            }
        }
        #endif
        
        // Always fetch today's data (fresh)
        fetchTodaysDistance()
        fetchRecentWorkouts()
        fetchTodaysSteps()
        fetchMonthlyStepsData()
        
        // Always calculate personal records to populate cachedWorkouts
        calculatePersonalRecords()
        
        // Smart caching: only fetch if we need new workout data
        if needsNewWorkoutFetch() {
            fetchWorkoutsSmartly()
        } else {
            // Data is already loaded from cache in init()
        }
    }
    
    /// Performs initial workout fetch to populate cachedWorkouts array
    private func performInitialWorkoutFetch() {
        guard isAuthorized else { return }
        
        #if !os(watchOS)
        // CRITICAL FIX: If index exists, use it instead of old calculation
        if let index = workoutIndex {
            log("[HealthKit] ✅ Index available, using pre-computed streak: \(index.currentStreak)")
            DispatchQueue.main.async {
                self.retroactiveStreak = index.currentStreak
                self.saveCachedData() // Save correct value immediately
            }
            return // Skip old calculation entirely
        }
        #endif
        
        log("[HealthKit] Starting initial workout fetch to populate cache...")
        
        // Look for both running and walking workouts
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: compoundPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self = self else { return }
            
            if let error = error {
                log("[HealthKit] ❌ Failed to populate workout cache: \(error.localizedDescription)")
                return
            }
            
            guard let workouts = samples as? [HKWorkout] else {
                return
            }
            
            // Update on main thread to avoid publishing changes from background threads
            DispatchQueue.main.async {
                // Populate cached workouts
                self.cachedWorkouts = workouts
                
                // Update latest workout date
                if let latestWorkout = workouts.max(by: { $0.endDate < $1.endDate }) {
                    self.cachedLatestWorkoutDate = latestWorkout.endDate
                }
                
                // Update workout count
                self.cachedWorkoutCount = workouts.count
                
                // Now recalculate all stats with the populated cache
                self.recalculateStatsWithAllWorkouts()
            }
        }
        
        healthStore.execute(query)
    }
    
    /// Smart workout fetching that only gets new workouts since last cache
    private     func fetchWorkoutsSmartly() {
        guard isAuthorized else { return }
        
        #if !os(watchOS)
        // CRITICAL FIX: If index exists, use it instead of old calculation
        if let index = workoutIndex {
            log("[HealthKit] ✅ Index available, using pre-computed streak: \(index.currentStreak)")
            DispatchQueue.main.async {
                self.retroactiveStreak = index.currentStreak
                self.saveCachedData() // Save correct value immediately
            }
            return // Skip old calculation entirely
        }
        #endif
        
        let startDate = getWorkoutFetchStartDate()
        let endDate = Date()
        
        
        // Look for both running and walking workouts
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        
        // Add date predicate if we have a start date
        var finalPredicate = compoundPredicate
        if let start = startDate {
            let datePredicate = HKQuery.predicateForSamples(withStart: start, end: endDate, options: .strictStartDate)
            finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [compoundPredicate, datePredicate])
        }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: finalPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self = self else { return }
            
            if let error = error {
                log("[HealthKit] ❌ Failed to fetch incremental workouts: \(error.localizedDescription)")
                return
            }
            
            guard let newWorkouts = samples as? [HKWorkout] else {
                return
            }
            
            // Update cached workout data
            self.updateCachedWorkoutData(with: newWorkouts)
            
            // Recalculate stats with all workouts (cached + new)
            self.recalculateStatsWithAllWorkouts()
        }
        
        healthStore.execute(query)
    }
    
    /// Updates cached workout data with new workouts
    /// Automatically deduplicates based on workout UUID
    private func updateCachedWorkoutData(with newWorkouts: [HKWorkout]) {
        var addedCount = 0
        var duplicateCount = 0
        
        // Add only unique new workouts
        for workout in newWorkouts {
            if !cachedWorkoutUUIDs.contains(workout.uuid) {
                cachedWorkouts.append(workout)
                cachedWorkoutUUIDs.insert(workout.uuid)
                addedCount += 1
            } else {
                duplicateCount += 1
            }
        }
        
        // Update latest workout date
        if let latestWorkout = newWorkouts.max(by: { $0.endDate < $1.endDate }) {
            if let currentLatest = cachedLatestWorkoutDate {
                cachedLatestWorkoutDate = max(currentLatest, latestWorkout.endDate)
            } else {
                cachedLatestWorkoutDate = latestWorkout.endDate
            }
        }
        
        // Update workout count
        cachedWorkoutCount = cachedWorkouts.count
        
        log("[HealthKit] Updated cached workout data - Added: \(addedCount), Duplicates skipped: \(duplicateCount), Total: \(cachedWorkoutCount)")
    }
    
    /// Recalculates all stats using cached + new workouts
    private func recalculateStatsWithAllWorkouts() {
        
        // Calculate total lifetime miles
        var totalMiles: Double = 0.0
        for workout in cachedWorkouts {
            if let distance = workout.totalDistance {
                let miles = distance.doubleValue(for: HKUnit.mile())
                totalMiles += miles
            }
        }
        
        // Calculate most miles in one day
        let workoutsByDay = groupWorkoutsByDeviceDay(workouts: cachedWorkouts)
        var mostMilesInDay: Double = 0.0
        var mostMilesWorkouts: [HKWorkout] = []
        
        for (_, dayWorkouts) in workoutsByDay {
            var totalMilesForDay: Double = 0.0
            for workout in dayWorkouts {
                if let distance = workout.totalDistance {
                    let miles = distance.doubleValue(for: HKUnit.mile())
                    totalMilesForDay += miles
                }
            }
            
            if totalMilesForDay > mostMilesInDay {
                mostMilesInDay = totalMilesForDay
                mostMilesWorkouts = dayWorkouts
            }
        }
        
        // Calculate streak
        let streak = calculateRetroactiveStreak(workoutsByDay: workoutsByDay)
        
        // Update main thread
        DispatchQueue.main.async {
            self.totalLifetimeMiles = totalMiles
            self.mostMilesInOneDay = mostMilesInDay
            self.mostMilesWorkouts = mostMilesWorkouts
            self.retroactiveStreak = streak
            
            // Save to cache
            self.saveCachedData()
            
            // Fetch fastest mile pace using cached workouts
            self.fetchFastestMilePaceSmartly()
        }
    }
    
    /// Recalculates streak using current timezone settings
    /// Call this after changing useLocationBasedTimezone to refresh calculations
    func recalculateStreakWithCurrentSettings() {
        timezoneDebugInfo = "Recalculating streak..."
        calculatePersonalRecords()
    }
    
    /// Debug method to analyze specific workout timezone handling
    func debugWorkoutTimezones() {
        // Look for ANY recent workouts (last 30 days) to debug
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let now = Date()
        
        getWorkoutsForDateRange(start: thirtyDaysAgo, end: now) { workouts in
            if workouts.isEmpty {
                // If no recent workouts, check all workouts
                self.getAllWorkouts { allWorkouts in
                    // Just analyze the 5 most recent ones
                    let recentFive = Array(allWorkouts.prefix(5))
                    for workout in recentFive {
                        self.analyzeWorkoutTimezone(workout)
                    }
                }
            } else {
                for workout in workouts {
                    self.analyzeWorkoutTimezone(workout)
                }
            }
        }
    }
    
    /// Analyzes a single workout's timezone information
    private func analyzeWorkoutTimezone(_ workout: HKWorkout) {
        // Try to determine workout's local timezone
        getLocalCalendar(for: workout) { calendar in
            // Show what day it falls on in each timezone
            let deviceDay = Calendar.current.startOfDay(for: workout.endDate)
            let localDay = calendar.startOfDay(for: workout.endDate)
            
            // Check if this affects streak calculation
            if deviceDay != localDay {
                // Timezone mismatch detected
            }
        }
    }
    
    // Format pace in minutes:seconds per mile
    func formatPace(minutesPerMile: TimeInterval) -> String {
        guard minutesPerMile > 0 else { return "N/A" }
        
        let totalSeconds = Int(minutesPerMile * 60)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
    
    // MARK: - Split Times Functionality
    
    /// Smart fastest mile pace calculation using cached workouts
    func fetchFastestMilePaceSmartly() {
        guard isAuthorized else { 
            return 
        }
        
        log("[HealthKit] Starting smart fastest mile pace calculation with \(cachedWorkouts.count) cached workouts...")
        
        // OPTIMIZATION: If we already have a cached fastest pace and it's been calculated recently,
        // only check NEW workouts (those after the last calculation)
        var fastestPace: TimeInterval = cachedFastestMilePace > 0 ? cachedFastestMilePace : .infinity
        var processedWorkouts = 0
        let dispatchGroup = DispatchGroup()
        
        // Determine which workouts to process
        var workoutsToProcess: [HKWorkout]
        
        if cachedFastestMilePace > 0, let lastUpdate = lastWorkoutCacheUpdate {
            // We have a cached pace - only process workouts added since last calculation
            workoutsToProcess = cachedWorkouts.filter { workout in
                guard let distance = workout.totalDistance else { return false }
                let miles = distance.doubleValue(for: HKUnit.mile())
                return miles >= 0.95 && workout.endDate > lastUpdate
            }
            
            if workoutsToProcess.isEmpty {
                log("[HealthKit] No new qualifying workouts since last calculation - using cached pace: \(formatPace(minutesPerMile: cachedFastestMilePace))")
                return
            }
            
            log("[HealthKit] INCREMENTAL: Processing only \(workoutsToProcess.count) NEW qualifying workouts (cached pace: \(formatPace(minutesPerMile: cachedFastestMilePace)))")
        } else {
            // No cached pace - process all qualifying workouts
            workoutsToProcess = cachedWorkouts.filter { workout in
                if let distance = workout.totalDistance {
                    let miles = distance.doubleValue(for: HKUnit.mile())
                    return miles >= 0.95
                }
                return false
            }
            
            log("[HealthKit] FULL CALCULATION: Processing all \(workoutsToProcess.count) qualifying workouts")
        }
        
        // Process each qualifying workout to get the fastest mile time
        for workout in workoutsToProcess {
            dispatchGroup.enter()
            
            self.calculateFastestMileTime(from: workout) { mileTime in
                defer { dispatchGroup.leave() }
                
                    if let mileTime = mileTime {
                        processedWorkouts += 1
                        if mileTime < fastestPace {
                            fastestPace = mileTime
                        }
                    }
            }
        }
        
        // Wait for all workout processing to complete
        dispatchGroup.notify(queue: .main) {
            let calculatedPace = fastestPace == .infinity ? 0.0 : fastestPace
            
            self.fastestMilePace = calculatedPace
            
            if calculatedPace > 0 {
                // Find workouts that achieved this fastest mile pace
                self.findFastestMileWorkouts()
            }
            
            // Save to cache after calculating fastest pace
            self.saveCachedData()
        }
    }
    
    /// Fetches workout splits by analyzing distance samples for a given workout
    /// Returns split times in minutes per mile, or nil if no splits available
    private func fetchWorkoutSplits(for workout: HKWorkout, completion: @escaping ([TimeInterval]?) -> Void) {
        guard let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            completion(nil)
            return
        }
        
        let workoutPredicate = HKQuery.predicateForObjects(from: workout)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        let query = HKSampleQuery(
            sampleType: distanceType,
            predicate: workoutPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, results, error in
            guard let self = self else {
                completion(nil)
                return
            }
            
            if let error = error {
                log("[HealthKit] ❌ Failed to fetch distance samples for splits: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let distanceSamples = results as? [HKQuantitySample], !distanceSamples.isEmpty else {
                completion(nil)
                return
            }
            
            // Calculate mile splits from distance samples
            var mileSplits: [TimeInterval] = []
            var accumulatedDistance: Double = 0.0
            var startTime: Date?
            let mileInMeters = 1609.34 // One mile in meters
            
            for sample in distanceSamples {
                let distance = sample.quantity.doubleValue(for: HKUnit.meter())
                
                if startTime == nil {
                    startTime = sample.startDate
                }
                
                accumulatedDistance += distance
                
                // Check if we've completed a mile
                if accumulatedDistance >= mileInMeters {
                    if let start = startTime {
                        let endTime = sample.endDate
                        let mileDuration = endTime.timeIntervalSince(start)
                        let minutesPerMile = mileDuration / 60.0
                        mileSplits.append(minutesPerMile)
                        
                        // Reset for next mile
                        accumulatedDistance -= mileInMeters
                        startTime = endTime
                    }
                }
            }
            
            completion(mileSplits.isEmpty ? nil : mileSplits)
        }
        
        healthStore.execute(query)
    }
    
    /// Calculates the fastest mile time from split times or falls back to average pace
    func calculateFastestMileTime(from workout: HKWorkout, completion: @escaping (TimeInterval?) -> Void) {
        
        // VALIDATION: Check workout has minimum required distance
        guard let distance = workout.totalDistance else {
            log("[HealthKit] ⚠️ Workout has no distance data")
            completion(nil)
            return
        }
        
        let miles = distance.doubleValue(for: HKUnit.mile())
        guard miles >= 0.95 else {
            log("[HealthKit] ⚠️ Workout distance \(String(format: "%.2f", miles)) miles is below 0.95 mile threshold")
            completion(nil)
            return
        }
        
        // First try to get split times
        fetchWorkoutSplits(for: workout) { [weak self] splitTimes in
            guard let self = self else {
                completion(nil)
                return
            }
            
            if let splitTimes = splitTimes, !splitTimes.isEmpty {
                let fastestSplit = splitTimes.min() ?? 0
                self.log("[HealthKit] ✅ Using fastest split time: \(self.formatPace(minutesPerMile: fastestSplit)) from \(splitTimes.count) splits")
                completion(fastestSplit)
                return
            } else {
                self.log("[HealthKit] No split times available, falling back to average pace")
            }
            
            // Fallback to average pace calculation
            let avgPaceMinutesPerMile = workout.duration / 60.0 / miles
            self.log("[HealthKit] ✅ Using average pace fallback: \(self.formatPace(minutesPerMile: avgPaceMinutesPerMile))")
            completion(avgPaceMinutesPerMile)
        }
    }
    
    // MARK: - Current Streak Stats Functions
    
    // Calculate current streak stats (total miles, most miles, fastest pace during current streak)
    func calculateCurrentStreakStats() -> (totalMiles: Double, mostMiles: Double, fastestPace: TimeInterval, streakDays: Int) {
        
        let currentStreakDays = retroactiveStreak
        guard currentStreakDays > 0 else {
            return (0.0, 0.0, 0.0, 0)
        }
        
        // Check if we can use cached data
        if canUseCurrentStreakCache(streakDays: currentStreakDays) {
            return cachedCurrentStreakStats
        }
        
        let streakWorkouts = getWorkoutsForCurrentStreak()
        
        // Calculate total miles and most miles (these are fast)
        let totalMiles = streakWorkouts.reduce(0.0) { total, workout in
            if let distance = workout.totalDistance {
                return total + distance.doubleValue(for: HKUnit.mile())
            }
            return total
        }
        
        let workoutsByDay = Dictionary(grouping: streakWorkouts) { workout in
            Calendar.current.startOfDay(for: workout.endDate)
        }
        
        var mostMiles = 0.0
        for (_, workouts) in workoutsByDay {
            let dayMiles = workouts.reduce(0.0) { total, workout in
                if let distance = workout.totalDistance {
                    return total + distance.doubleValue(for: HKUnit.mile())
                }
                return total
            }
            mostMiles = max(mostMiles, dayMiles)
        }
        
        // Smart fastest pace calculation
        let fastestPace = calculateSmartCurrentStreakFastestPace(streakWorkouts: streakWorkouts)
        
        let newStats = (totalMiles, mostMiles, fastestPace, currentStreakDays)
        
        // UPDATE: Ensure caching happens on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cachedCurrentStreakStats = newStats
            self.lastCurrentStreakStatsUpdate = Date()
            self.saveCachedData() // This should also be on main thread since it updates @Published properties
            
            // Find workouts that achieved this fastest mile pace
            self.findCurrentStreakFastestMileWorkouts()
        }
        
        return newStats
    }
    
    private func canUseCurrentStreakCache(streakDays: Int) -> Bool {
        // If streak days changed, we need to recalculate
        guard cachedCurrentStreakStats.streakDays == streakDays else {
            return false
        }
        
        // If cache is older than 1 hour, recalculate
        guard let lastUpdate = lastCurrentStreakStatsUpdate else {
            return false
        }
        
        let oneHourAgo = Date().addingTimeInterval(-3600)
        guard lastUpdate > oneHourAgo else {
            return false
        }
        
        // If we don't have the fastest mile workouts cached, we need to recalculate
        guard !currentStreakFastestMileWorkouts.isEmpty else {
            return false
        }
        
        return true
    }
    
    private func calculateSmartCurrentStreakFastestPace(streakWorkouts: [HKWorkout]) -> TimeInterval {
        // OPTIMIZATION 1: Check if All Time fastest mile is within current streak
        if findWorkoutWithAllTimeFastestMile(in: streakWorkouts) != nil {
            return fastestMilePace
        }
        
        // OPTIMIZATION 2: Check if we have a cached value that's still valid for this streak
        if cachedCurrentStreakFastestPace > 0 && cachedCurrentStreakStats.streakDays == retroactiveStreak {
            // Check if any new qualifying workouts have been added since last calculation
            if !hasNewQualifyingWorkoutsSinceLastStreakCalculation(streakWorkouts: streakWorkouts) {
                return cachedCurrentStreakFastestPace
            }
        }
        
        // FALLBACK: Calculate from scratch using actual split times
        return calculateFastestMileForWorkouts(streakWorkouts)
    }
    
    private func findWorkoutWithAllTimeFastestMile(in streakWorkouts: [HKWorkout]) -> HKWorkout? {
        // This is a heuristic - we look for workouts that could contain the all-time fastest mile
        // based on their average pace being close to the all-time fastest
        
        guard fastestMilePace > 0 else { return nil }
        
        let tolerance: TimeInterval = 0.5 // 30 seconds tolerance
        
        for workout in streakWorkouts {
            if let distance = workout.totalDistance {
                let miles = distance.doubleValue(for: HKUnit.mile())
                if miles >= 0.95 {
                    let avgPace = workout.duration / 60.0 / miles
                    // If average pace is close to all-time fastest, this workout likely contains it
                    if abs(avgPace - fastestMilePace) <= tolerance {
                        return workout
                    }
                }
            }
        }
        
        return nil
    }
    
    private func hasNewQualifyingWorkoutsSinceLastStreakCalculation(streakWorkouts: [HKWorkout]) -> Bool {
        guard let lastUpdate = lastCurrentStreakStatsUpdate else { return true }
        
        let newWorkouts = streakWorkouts.filter { workout in
            workout.endDate > lastUpdate
        }
        
        let newQualifyingWorkouts = newWorkouts.filter { workout in
            if let distance = workout.totalDistance {
                return distance.doubleValue(for: HKUnit.mile()) >= 0.95
            }
            return false
        }
        
        if !newQualifyingWorkouts.isEmpty {
            return true
        }
        
        return false
    }
    
    private func calculateFastestMileForWorkouts(_ workouts: [HKWorkout]) -> TimeInterval {
        let qualifyingWorkouts = workouts.filter { workout in
            if let distance = workout.totalDistance {
                return distance.doubleValue(for: HKUnit.mile()) >= 0.95
            }
            return false
        }
        
        guard !qualifyingWorkouts.isEmpty else { return 0.0 }
        
        var fastestPace: TimeInterval = .infinity
        let dispatchGroup = DispatchGroup()
        
        for workout in qualifyingWorkouts {
            dispatchGroup.enter()
            
            calculateFastestMileTime(from: workout) { mileTime in
                defer { dispatchGroup.leave() }
                
                if let mileTime = mileTime, mileTime < fastestPace {
                    fastestPace = mileTime
                }
            }
        }
        
        _ = dispatchGroup.wait(timeout: .now() + 10) // 10 second timeout
        return fastestPace == .infinity ? 0.0 : fastestPace
    }
    
    /// Find workouts that achieved the fastest mile pace
    func findFastestMileWorkouts() {
        guard fastestMilePace > 0 else {
            fastestMileWorkouts = []
            return
        }
        
        let qualifyingWorkouts = cachedWorkouts.filter { workout in
            if let distance = workout.totalDistance {
                return distance.doubleValue(for: HKUnit.mile()) >= 0.95
            }
            return false
        }
        
        var fastestWorkouts: [HKWorkout] = []
        let tolerance: TimeInterval = 0.1 // 6 seconds tolerance
        
        for workout in qualifyingWorkouts {
            calculateFastestMileTime(from: workout) { [weak self] mileTime in
                guard let self = self, let mileTime = mileTime else { return }
                
                // Check if this workout's fastest mile is close to the overall fastest
                if abs(mileTime - self.fastestMilePace) <= tolerance {
                    DispatchQueue.main.async {
                        if !fastestWorkouts.contains(where: { $0.uuid == workout.uuid }) {
                            fastestWorkouts.append(workout)
                            self.fastestMileWorkouts = fastestWorkouts
                        }
                    }
                }
            }
        }
    }
    
    /// Find workouts that achieved the current streak's fastest mile pace
    func findCurrentStreakFastestMileWorkouts() {
        let streakWorkouts = getWorkoutsForCurrentStreak()
        let currentStreakFastestPace = cachedCurrentStreakStats.fastestPace
        
        guard currentStreakFastestPace > 0 else {
            currentStreakFastestMileWorkouts = []
            return
        }
        
        let qualifyingWorkouts = streakWorkouts.filter { workout in
            if let distance = workout.totalDistance {
                return distance.doubleValue(for: HKUnit.mile()) >= 0.95
            }
            return false
        }
        
        var fastestWorkouts: [HKWorkout] = []
        let tolerance: TimeInterval = 0.1 // 6 seconds tolerance
        
        for workout in qualifyingWorkouts {
            calculateFastestMileTime(from: workout) { [weak self] mileTime in
                guard let self = self, let mileTime = mileTime else { return }
                
                // Check if this workout's fastest mile is close to the current streak's fastest
                if abs(mileTime - currentStreakFastestPace) <= tolerance {
                    DispatchQueue.main.async {
                        if !fastestWorkouts.contains(where: { $0.uuid == workout.uuid }) {
                            fastestWorkouts.append(workout)
                            self.currentStreakFastestMileWorkouts = fastestWorkouts
                        }
                    }
                }
            }
        }
    }
    
    // Get workouts for the current streak period using timezone-aware calculation
    func getWorkoutsForCurrentStreak() -> [HKWorkout] {
        guard retroactiveStreak > 0 else { return [] }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let streakStartDate = calendar.date(byAdding: .day, value: -retroactiveStreak, to: today) ?? today
        
        
        // If cachedWorkouts is empty, we need to fetch workouts directly
        if cachedWorkouts.isEmpty {
            // For now, return empty array and let the calling code handle this
            // In a production app, you might want to make this async and use a completion handler
            return []
        }
        
        // Filter cached workouts to current streak period
        let streakWorkouts = cachedWorkouts.filter { workout in
            let workoutDay = calendar.startOfDay(for: workout.endDate)
            return workoutDay >= streakStartDate && workoutDay <= today
        }
        
        return streakWorkouts
    }
    
    /// Fetches workouts for the current streak period directly from HealthKit
    /// This is a fallback method when cachedWorkouts is empty
    func fetchWorkoutsForCurrentStreakPeriod(completion: @escaping ([HKWorkout]) -> Void) {
        guard isAuthorized && retroactiveStreak > 0 else {
            completion([])
            return
        }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let streakStartDate = calendar.date(byAdding: .day, value: -retroactiveStreak, to: today) ?? today
        
        
        // Look for both running and walking workouts
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        
        // Add date predicate for streak period
        let datePredicate = HKQuery.predicateForSamples(withStart: streakStartDate, end: today, options: .strictStartDate)
        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [compoundPredicate, datePredicate])
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: finalPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self = self else {
                completion([])
                return
            }
            if let error = error {
                self.log("[HealthKit] ❌ Failed to fetch workouts for streak window: \(error.localizedDescription)")
                completion([])
                return
            }
            
            let workouts = samples as? [HKWorkout] ?? []
            completion(workouts)
        }
        
        healthStore.execute(query)
    }
    
    // MARK: - Step Counter Functions
    
    // Fetch today's step count
    func fetchTodaysSteps() {
        guard isAuthorized else { return }
        
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let sum = result?.sumQuantity() {
                    self.todaysSteps = Int(sum.doubleValue(for: HKUnit.count()))
                } else {
                    self.todaysSteps = 0
                }
            }
        }
        
        healthStore.execute(query)
    }
    
    // Update calendar data with timezone-corrected workout grouping
    private func updateCalendarWithTimezoneCorrectedData(correctedWorkoutsByDay: [Date: [HKWorkout]]) {
        
        // Target Hawaii dates to specifically track
        let calendar = Calendar.current
        let targetDates = ["8/1/25", "8/3/25", "8/7/25"]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d/yy"
        
        // Update dailyMileGoals with timezone-corrected data
        var updatedMileGoals: [Date: Bool] = [:]
        
        for (date, workouts) in correctedWorkoutsByDay {
            let totalMiles = workouts.reduce(0.0) { total, workout in
                if let distance = workout.totalDistance {
                    return total + distance.doubleValue(for: HKUnit.mile())
                }
                return total
            }
            
            updatedMileGoals[date] = totalMiles >= 0.95
            
            let dateString = dateFormatter.string(from: date)
            if totalMiles >= 0.95 {
                // Special logging for Hawaii target dates
                if targetDates.contains(dateString) {
                    // Hawaii target date found
                }
            } else if targetDates.contains(dateString) {
                // Hawaii target date not completed
            }
        }
        
        // Merge with existing calendar data (preserve days not affected by timezone corrections)
        for (date, goalReached) in self.dailyMileGoals {
            if updatedMileGoals[date] == nil {
                updatedMileGoals[date] = goalReached
            }
        }
        
        let originalCount = self.dailyMileGoals.filter { $0.value }.count
        self.dailyMileGoals = updatedMileGoals
        let newCount = updatedMileGoals.filter { $0.value }.count
        if originalCount != newCount {
            log("[HealthKit] 📈 Completed goal days updated: \(originalCount) → \(newCount)")
        }
        
        // Verify Hawaii target dates are now completed
        for targetDate in targetDates {
            if let date = dateFormatter.date(from: targetDate) {
                let startOfDay = calendar.startOfDay(for: date)
                let isCompleted = self.dailyMileGoals[startOfDay] ?? false
                log("[HealthKit] 🌺 Hawaii goal \(targetDate): \(isCompleted ? "completed" : "missing")")
            }
        }
    }
    
    // Fetch step data and mile goals for a specific month
    // CRITICAL FIX: Now uses timezone-corrected workout grouping to match streak calculation
    func fetchMonthlyStepsData(for month: Date = Date(), completion: (() -> Void)? = nil) {
        guard isAuthorized else { return }
        
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let calendar = Calendar.current
        
        // Get the date interval for the specified month
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return }
        
        let startOfMonth = monthInterval.start
        let endOfMonth = monthInterval.end
        
        log("[HealthKit] 📅 Fetching monthly data with timezone-aware workout grouping")
        
        var dailySteps: [Date: Int] = [:]
        let group = DispatchGroup()
        
        // Query for steps (one query per day)
        var currentDate = startOfMonth
        while currentDate < endOfMonth {
            let startOfDay = calendar.startOfDay(for: currentDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            
            group.enter()
            
            let stepPredicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
            
            let stepQuery = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: stepPredicate,
                options: .cumulativeSum
            ) { _, result, error in
                defer { group.leave() }
                
                let steps = result?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                dailySteps[startOfDay] = Int(steps)
            }
            
            healthStore.execute(stepQuery)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        // CRITICAL FIX: Fetch ALL workouts for the month and use timezone-aware grouping
        // This ensures calendar matches streak calculation exactly
        group.enter()
        
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        
        // Query with buffer days to catch timezone edge cases
        let queryStartDate = calendar.date(byAdding: .day, value: -2, to: startOfMonth) ?? startOfMonth
        let queryEndDate = calendar.date(byAdding: .day, value: 2, to: endOfMonth) ?? endOfMonth
        let datePredicate = HKQuery.predicateForSamples(withStart: queryStartDate, end: queryEndDate, options: .strictStartDate)
        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [compoundPredicate, datePredicate])
        
        let workoutQuery = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: finalPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [weak self] _, samples, error in
            defer { group.leave() }
            
            guard let self = self, let workouts = samples as? [HKWorkout] else { return }
            
            log("[HealthKit] 📅 Applying timezone-aware grouping to \(workouts.count) workouts for calendar")
            
            // Use the SAME timezone-aware grouping as streak calculation
            let workoutsByDay = self.groupWorkoutsWithTimezoneAwareness(workouts: workouts)
            
            // Convert to dailyMileGoals dictionary
            var dailyMileGoals: [Date: Bool] = [:]
            
            for (date, dayWorkouts) in workoutsByDay {
                let totalMiles = dayWorkouts.reduce(0.0) { total, workout in
                    if let distance = workout.totalDistance {
                        return total + distance.doubleValue(for: HKUnit.mile())
                    }
                    return total
                }
                
                // Use same threshold as streak (>= 0.95 miles)
                dailyMileGoals[date] = totalMiles >= 0.95
                
                // Debug logging for verification
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "M/d/yy"
                if totalMiles >= 0.95 {
                    self.log("[HealthKit] 📅 \(dateFormatter.string(from: date)): ✅ \(String(format: "%.2f", totalMiles)) miles")
                }
            }
            
            // Store in property for UI access
            DispatchQueue.main.async {
                self.dailyMileGoals = dailyMileGoals
                self.log("[HealthKit] 📅 Calendar updated with \(dailyMileGoals.filter { $0.value }.count) qualifying days")
            }
        }
        
        healthStore.execute(workoutQuery)
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.dailyStepsData = dailySteps
            self.log("[HealthKit] 📅 Monthly data fetch complete with timezone-aware grouping")
            
            completion?()
        }
    }
    
    /// CRITICAL METHOD: Groups workouts by day using timezone awareness with corrections
    /// This ensures calendar and streak use the SAME logic for consistency
    /// Applies timezone corrections for workouts done in different timezones
    private func groupWorkoutsWithTimezoneAwareness(workouts: [HKWorkout]) -> [Date: [HKWorkout]] {
        let calendar = Calendar.current
        
        // Start with device timezone grouping
        var workoutsByDay = groupWorkoutsByDeviceDay(workouts: workouts)
        
        // Apply timezone corrections for workouts at unusual hours
        // This handles ALL timezone scenarios (Hawaii, Pacific, etc.)
        var pendingCorrections: [(originalDate: Date, correctedDate: Date, workout: HKWorkout)] = []
        
        // Find workouts that need timezone correction
        for (deviceDate, dayWorkouts) in workoutsByDay {
            for workout in dayWorkouts {
                let workoutHour = calendar.component(.hour, from: workout.endDate)
                
                // If workout was recorded between 10 PM - 6 AM (device time), 
                // it's likely from a different timezone
                if workoutHour >= 22 || workoutHour <= 6 {
                    // Try common timezone corrections
                    let possibleOffsets = [-6, -5, -4, -3, -2, -1, 1, 2, 3, 4, 5, 6] // Hours
                    
                    for offset in possibleOffsets {
                        if let correctedDate = calendar.date(byAdding: .hour, value: offset, to: workout.endDate) {
                            let correctedDay = calendar.startOfDay(for: correctedDate)
                            let correctedHour = calendar.component(.hour, from: correctedDate)
                            
                            // Check if this results in a more reasonable workout time (6 AM - 10 PM local)
                            if correctedHour >= 6 && correctedHour <= 22 && correctedDay != deviceDate {
                                let dateFormatter = DateFormatter()
                                dateFormatter.dateFormat = "M/d/yy"
                                log("[HealthKit] 🌍 Timezone correction detected: \(dateFormatter.string(from: deviceDate)) → \(dateFormatter.string(from: correctedDay)) (offset: \(offset)h, workout at \(correctedHour):00 local time)")
                                
                                pendingCorrections.append((originalDate: deviceDate, correctedDate: correctedDay, workout: workout))
                                break // Use first valid correction
                            }
                        }
                    }
                }
            }
        }
        
        // Apply corrections (move workouts to corrected days)
        if !pendingCorrections.isEmpty {
            log("[HealthKit] 🌍 Applying \(pendingCorrections.count) timezone corrections...")
            
            for correction in pendingCorrections {
                // Remove from original date
                if var originalWorkouts = workoutsByDay[correction.originalDate] {
                    originalWorkouts.removeAll { $0.uuid == correction.workout.uuid }
                    if originalWorkouts.isEmpty {
                        workoutsByDay.removeValue(forKey: correction.originalDate)
                    } else {
                        workoutsByDay[correction.originalDate] = originalWorkouts
                    }
                }
                
                // Add to corrected date (ensuring no duplicates)
                if workoutsByDay[correction.correctedDate] == nil {
                    workoutsByDay[correction.correctedDate] = []
                }
                
                let exists = workoutsByDay[correction.correctedDate]?.contains { $0.uuid == correction.workout.uuid } ?? false
                if !exists {
                    workoutsByDay[correction.correctedDate]?.append(correction.workout)
                }
            }
            
            log("[HealthKit] ✅ Timezone corrections applied successfully")
        }
        
        return workoutsByDay
    }
    
    // MARK: - Data Synchronization (REMOVED - Now handled by WorkoutIndex)
    // synchronizeAllData() and validateDataConsistency() have been removed
    // The WorkoutIndex ensures data consistency automatically
    
    // Get workouts for a specific date using location-aware timezone calculation
    func getWorkoutsForDate(_ date: Date, completion: @escaping ([HKWorkout]) -> Void) {
        #if !os(watchOS)
        // PHASE 1 FIX: Use index if available for instant lookup
        if let index = workoutIndex {
            let targetDay = Calendar.current.startOfDay(for: date)
            let records = index.workouts(for: targetDay)
            
            if !records.isEmpty {
                print("[WorkoutIndex] ✅ Found \(records.count) workout(s) for \(dateKey(from: targetDay)) from index")
                
                // Convert WorkoutRecords back to UUIDs and fetch the actual HKWorkouts
                let workoutUUIDs = records.map { UUID(uuidString: $0.id)! }
                fetchWorkoutsByUUIDs(workoutUUIDs) { workouts in
                    completion(workouts)
                }
                return
            } else {
                print("[WorkoutIndex] No workouts found in index for \(dateKey(from: targetDay))")
                completion([])
                return
            }
        }
        #endif
        
        // FALLBACK: If no index, use old method
        print("[WorkoutIndex] ⚠️ Index not available, falling back to HealthKit query")
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: startOfDay)!
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: startOfDay)!
        
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        let datePredicate = HKQuery.predicateForSamples(withStart: dayBefore, end: dayAfter, options: .strictStartDate)
        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [compoundPredicate, datePredicate])
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: finalPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self = self, let allWorkouts = samples as? [HKWorkout] else {
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }
            
            // Filter to workouts that occurred on the requested date in their local timezone
            self.filterWorkoutsForSpecificDate(workouts: allWorkouts, targetDate: date) { filteredWorkouts in
                DispatchQueue.main.async {
                    completion(filteredWorkouts)
                }
            }
        }
        
        healthStore.execute(query)
    }
    
    /// Fetch HKWorkouts by their UUIDs (for index lookup)
    private func fetchWorkoutsByUUIDs(_ uuids: [UUID], completion: @escaping ([HKWorkout]) -> Void) {
        guard !uuids.isEmpty else {
            completion([])
            return
        }
        
        let predicates = uuids.map { HKQuery.predicateForObject(with: $0) }
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: compoundPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        ) { _, samples, error in
            DispatchQueue.main.async {
                let workouts = samples as? [HKWorkout] ?? []
                completion(workouts)
            }
        }
        
        healthStore.execute(query)
    }
    
    // Get workouts for a date range
    private func getWorkoutsForDateRange(start: Date, end: Date, completion: @escaping ([HKWorkout]) -> Void) {
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [compoundPredicate, datePredicate])
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: finalPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in
            DispatchQueue.main.async {
                let workouts = samples as? [HKWorkout] ?? []
                completion(workouts)
            }
        }
        
        healthStore.execute(query)
    }
    
    // Get all workouts for debugging
    private func getAllWorkouts(completion: @escaping ([HKWorkout]) -> Void) {
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: compoundPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { _, samples, error in
            DispatchQueue.main.async {
                let workouts = samples as? [HKWorkout] ?? []
                completion(workouts)
            }
        }
        
        healthStore.execute(query)
    }
    
    /// Public method to get local calendar for a workout (for UI extensions)
    func getLocalCalendarForWorkout(_ workout: HKWorkout, completion: @escaping (Calendar) -> Void) {
        getLocalCalendar(for: workout, completion: completion)
    }
    
    /// Public method to get split times for a workout (for UI display)
    func getWorkoutSplitTimes(for workout: HKWorkout, completion: @escaping ([TimeInterval]?) -> Void) {
        fetchWorkoutSplits(for: workout, completion: completion)
    }
    
    // MARK: - Workout Index Management (Phase 1 - Architectural Redesign)
    
    /// Build workout index from all workouts (one-time operation)
    /// This processes all workouts and caches timezone-corrected dates
    #if !os(watchOS)
    func buildWorkoutIndex(progressCallback: ((Int, Int) -> Void)? = nil) async {
        guard isAuthorized else {
            print("[WorkoutIndex] ❌ Not authorized to access HealthKit")
            return
        }
        
        guard !isIndexBuilding else {
            print("[WorkoutIndex] ⏳ Index build already in progress")
            return
        }
        
        isIndexBuilding = true
        print("[WorkoutIndex] 🏗️ Building workout index from all workouts...")
        
        // Fetch all workouts
        let allWorkouts = await withCheckedContinuation { continuation in
            getAllWorkouts { workouts in
                continuation.resume(returning: workouts)
            }
        }
        
        guard !allWorkouts.isEmpty else {
            print("[WorkoutIndex] ⚠️ No workouts found")
            isIndexBuilding = false
            return
        }
        
        print("[WorkoutIndex] Processing \(allWorkouts.count) workouts...")
        
        // Process workouts
        let allRecords = workoutProcessor.processWorkouts(allWorkouts)
        
        // Build index from records
        var index = WorkoutIndex()
        var workoutsByDate: [String: [WorkoutRecord]] = [:]
        
        for record in allRecords {
            let key = dateKey(from: record.localDate)
            if workoutsByDate[key] == nil {
                workoutsByDate[key] = []
            }
            workoutsByDate[key]?.append(record)
        }
        
        index.workoutsByDate = workoutsByDate
        
        // Calculate qualifying days
        var qualifyingDays: Set<String> = []
        for (dateKey, records) in workoutsByDate {
            let totalMiles = records.reduce(0) { $0 + $1.distance }
            if totalMiles >= 0.95 {
                qualifyingDays.insert(dateKey)
            }
        }
        index.qualifyingDays = qualifyingDays
        
        // Calculate streak
        index.currentStreak = workoutProcessor.calculateStreak(from: allRecords)
        
        // Set metadata and calculate total miles
        index.lastUpdated = Date()
        index.latestWorkoutDate = allWorkouts.first?.endDate
        index.latestWorkoutUUID = allWorkouts.first?.uuid.uuidString
        index.totalWorkouts = allRecords.count
        index.totalLifetimeMiles = allRecords.reduce(0.0) { $0 + $1.distance }
        
        // Save index
        index.save()
        
        // Capture values for MainActor.run to avoid concurrency issues
        let finalIndex = index
        let finalStreak = index.currentStreak
        let finalTotalWorkouts = index.totalWorkouts
        let finalQualifyingDays = index.qualifyingDays.count
        let finalWorkoutsByDate = workoutsByDate
        
        // Update published property
        await MainActor.run {
            self.workoutIndex = finalIndex
            self.retroactiveStreak = finalStreak
            self.totalLifetimeMiles = finalIndex.totalLifetimeMiles
            self.mostMilesInOneDay = finalIndex.mostMilesInOneDay
            
            // Update dailyMileGoals from index for calendar
            var goals: [Date: Bool] = [:]
            for (dateKey, records) in finalWorkoutsByDate {
                if let date = dateFromKey(dateKey) {
                    let totalMiles = records.reduce(0) { $0 + $1.distance }
                    goals[date] = totalMiles >= 0.95
                }
            }
            self.dailyMileGoals = goals
            
            self.saveCachedData()
            
            print("[WorkoutIndex] ✅ Index built successfully:")
            print("  - Total workouts: \(finalTotalWorkouts)")
            print("  - Qualifying days: \(finalQualifyingDays)")
            print("  - Current streak: \(finalStreak) days")
            print("  - Most miles in one day: \(finalIndex.mostMilesInOneDay)")
            
            // CRITICAL: Post notification that index is ready
            NotificationCenter.default.post(name: NSNotification.Name("WorkoutIndexReady"), object: nil)
        }
        
        isIndexBuilding = false
    }
    #endif
    
    #if !os(watchOS)
    /// Update index with new workouts (incremental, fast)
    func updateIndexWithNewWorkouts() async {
        guard let currentIndex = workoutIndex else {
            // No index exists - build full index
            print("[WorkoutIndex] No index found, building initial index...")
            await buildWorkoutIndex()
            return
        }
        
        guard isAuthorized else { return }
        
        let lastUpdate = currentIndex.lastUpdated
        print("[WorkoutIndex] 🔄 Checking for workouts since \(lastUpdate)...")
        
        // Query for workouts after last update
        let newWorkouts = await withCheckedContinuation { (continuation: CheckedContinuation<[HKWorkout], Never>) in
            let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
            let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
            let workoutTypePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
            
            let datePredicate = HKQuery.predicateForSamples(withStart: lastUpdate, end: Date(), options: .strictEndDate)
            let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [workoutTypePredicate, datePredicate])
            
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: compoundPredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                let workouts = samples as? [HKWorkout] ?? []
                continuation.resume(returning: workouts)
            }
            
            healthStore.execute(query)
        }
        
        guard !newWorkouts.isEmpty else {
            print("[WorkoutIndex] ✅ No new workouts found")
            return
        }
        
        print("[WorkoutIndex] 🆕 Found \(newWorkouts.count) new workouts, updating index...")
        
        // Process new workouts
        let newRecords = workoutProcessor.processWorkouts(newWorkouts)
        
        // Update index
        var updatedIndex = currentIndex
        
        for record in newRecords {
            let key = dateKey(from: record.localDate)
            if updatedIndex.workoutsByDate[key] == nil {
                updatedIndex.workoutsByDate[key] = []
            }
            updatedIndex.workoutsByDate[key]?.append(record)
            
            // Update qualifying days
            let totalMiles = updatedIndex.workoutsByDate[key]!.reduce(0) { $0 + $1.distance }
            if totalMiles >= 0.95 {
                updatedIndex.qualifyingDays.insert(key)
            }
        }
        
        // Recalculate streak (fast - only checks recent days)
        let allRecords = updatedIndex.workoutsByDate.values.flatMap { $0 }
        updatedIndex.currentStreak = workoutProcessor.calculateStreak(from: allRecords)
        
        // Update metadata and recalculate total miles
        updatedIndex.lastUpdated = Date()
        updatedIndex.latestWorkoutDate = newWorkouts.first?.endDate
        updatedIndex.latestWorkoutUUID = newWorkouts.first?.uuid.uuidString
        updatedIndex.totalWorkouts = allRecords.count
        updatedIndex.totalLifetimeMiles = allRecords.reduce(0.0) { $0 + $1.distance }
        
        // Save and publish
        updatedIndex.save()
        
        // Capture values for MainActor.run to avoid concurrency issues
        let finalUpdatedIndex = updatedIndex
        let finalUpdatedStreak = updatedIndex.currentStreak
        let finalUpdatedWorkoutsByDate = updatedIndex.workoutsByDate
        
        await MainActor.run {
            self.workoutIndex = finalUpdatedIndex
            self.retroactiveStreak = finalUpdatedStreak
            self.totalLifetimeMiles = finalUpdatedIndex.totalLifetimeMiles
            self.mostMilesInOneDay = finalUpdatedIndex.mostMilesInOneDay
            
            // Update dailyMileGoals from index
            var goals: [Date: Bool] = [:]
            for (dateKey, records) in finalUpdatedWorkoutsByDate {
                if let date = dateFromKey(dateKey) {
                    let totalMiles = records.reduce(0) { $0 + $1.distance }
                    goals[date] = totalMiles >= 0.95
                }
            }
            self.dailyMileGoals = goals
            
            self.saveCachedData()
            
            print("[WorkoutIndex] ✅ Index updated: \(finalUpdatedStreak) day streak, most miles in one day: \(finalUpdatedIndex.mostMilesInOneDay)")
            
            // Post notification that index was updated
            NotificationCenter.default.post(name: NSNotification.Name("WorkoutIndexReady"), object: nil)
        }
    }
    #endif
    
    // MARK: - Helper Methods for Index
    
    #if !os(watchOS)
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
    #endif
    
    /// Get the timezone-corrected local end time for a workout
    /// Returns the corrected time if workout is in index, otherwise returns workout's device time
    func getCorrectedLocalTime(for workout: HKWorkout) -> Date {
        #if !os(watchOS)
        guard let index = workoutIndex else {
            return workout.endDate // No index, return device time
        }
        
        // Find the workout record in the index
        for (_, records) in index.workoutsByDate {
            if let record = records.first(where: { $0.id == workout.uuid.uuidString }) {
                print("[WorkoutIndex] ✅ Found corrected time for workout (offset: \(record.timezoneOffset)h)")
                return record.localEndTime
            }
        }
        
        // Not found in index, return device time
        print("[WorkoutIndex] ⚠️ Workout not found in index, using device time")
        return workout.endDate
        #else
        return workout.endDate
        #endif
    }
} 