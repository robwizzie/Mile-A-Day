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
    @Published var todaysWorkouts: [HKWorkout] = []  // Only today's workouts (for stats)
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
    var cachedWorkoutUUIDs: Set<UUID> = []

    /// Guards celebration triggers: true only after BOTH fetchTodaysDistance()
    /// AND workout index (streak data) have completed at least once this session.
    @Published var hasLoadedInitialData: Bool = false
    var hasTodaysDistanceLoaded: Bool = false
    var hasIndexOrStreakLoaded: Bool = false

    func checkInitialDataReady() {
        if hasTodaysDistanceLoaded && hasIndexOrStreakLoaded && !hasLoadedInitialData {
            hasLoadedInitialData = true
            print("[HealthKit] ✅ Initial data fully loaded - celebrations now permitted")
        }
    }

    // MARK: - NEW: Persistent Workout Index (Phase 1 - Architectural Redesign)
    /// Single source of truth for workout data - eliminates inconsistencies
    #if !os(watchOS)
    @Published var workoutIndex: WorkoutIndex? {
        didSet { _workoutsByUUID = nil }
    }
    let workoutProcessor = WorkoutProcessor()
    var isIndexBuilding = false

    /// O(1) UUID lookup cache — rebuilt lazily when workoutIndex changes
    private var _workoutsByUUID: [String: WorkoutRecord]?

    /// Non-mutating lookup of a workout record by UUID (safe to call from view body)
    func workoutRecord(forUUID uuid: String) -> WorkoutRecord? {
        if _workoutsByUUID == nil {
            guard let index = workoutIndex else { return nil }
            var dict = [String: WorkoutRecord]()
            dict.reserveCapacity(index.totalWorkouts)
            for (_, records) in index.workoutsByDate {
                for record in records {
                    dict[record.id] = record
                }
            }
            _workoutsByUUID = dict
        }
        return _workoutsByUUID?[uuid]
    }
    #endif
    
    func log(_ message: String) {}
    
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
            self.hasIndexOrStreakLoaded = true
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
    func saveCachedData() {
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
    func needsNewWorkoutFetch() -> Bool {
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
    func getWorkoutFetchStartDate() -> Date? {
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
                    self?.todaysWorkouts = []
                    #if !os(watchOS)
                    // Get current goal from widget store or default to 1.0
                    let widgetData = WidgetDataStore.load()
                    let currentGoal = widgetData.goal
                    let safeGoal = currentGoal > 0 ? currentGoal : 1.0

                    // Use unified progress calculation
                    WidgetDataStore.save(todayMiles: 0, goal: safeGoal)
                    #endif
                    if self?.hasTodaysDistanceLoaded == false {
                        self?.hasTodaysDistanceLoaded = true
                        self?.checkInitialDataReady()
                    }
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
    
    /// Today's total workout duration in seconds (uses todaysWorkouts for accuracy)
    var todaysTotalDuration: TimeInterval {
        return todaysWorkouts.reduce(0) { $0 + $1.duration }
    }

    /// Today's average pace in minutes per mile (calculated from today's workouts only)
    var todaysAveragePace: TimeInterval? {
        // Calculate from today's workouts directly for accuracy
        var totalDuration: TimeInterval = 0
        var totalMiles: Double = 0

        for workout in todaysWorkouts {
            if let distance = workout.totalDistance {
                let miles = distance.doubleValue(for: HKUnit.mile())
                if miles > 0 {
                    totalDuration += workout.duration
                    totalMiles += miles
                }
            }
        }

        guard totalMiles > 0 else { return nil }
        let pace = (totalDuration / 60.0) / totalMiles
        // Sanity check: pace should be between 2:00/mi and 30:00/mi
        guard pace >= 2.0 && pace <= 30.0 else { return nil }
        return pace
    }

    /// Today's fastest pace from individual workouts (best single workout pace today)
    var todaysFastestPace: TimeInterval? {
        var fastestPace: TimeInterval = .infinity

        for workout in todaysWorkouts {
            if let distance = workout.totalDistance {
                let miles = distance.doubleValue(for: HKUnit.mile())
                if miles >= 0.3 { // Only consider workouts with meaningful distance
                    let pace = (workout.duration / 60.0) / miles
                    // Sanity check: pace should be between 2:00/mi and 30:00/mi
                    if pace >= 2.0 && pace < fastestPace {
                        fastestPace = pace
                    }
                }
            }
        }

        return fastestPace == .infinity ? nil : fastestPace
    }

    /// Today's total calories burned (estimated from workouts)
    var todaysTotalCalories: Double {
        return todaysWorkouts.reduce(0) { total, workout in
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
        return todaysWorkouts.count
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
    
    // calculatePersonalRecords, fetchFastestMilePace, processWorkoutsByDay moved to HealthKitManager+PersonalRecords.swift
    
    /// Legacy method: groups workouts by device timezone (pre-location-aware behavior)
    func groupWorkoutsByDeviceDay(workouts: [HKWorkout]) -> [Date: [HKWorkout]] {
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
    func filterWorkoutsByDeviceToday(workouts: [HKWorkout]) -> [HKWorkout] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let _ = calendar.date(byAdding: .day, value: 1, to: today)!
        
        return workouts.filter { workout in
            let workoutDate = calendar.startOfDay(for: workout.endDate)
            return workoutDate == today
        }
    }
    
    /// Processes today's filtered workouts to calculate distance and update UI
    func processTodaysWorkouts(_ todaysWorkouts: [HKWorkout]) {
        var totalMiles: Double = 0.0
        
        for workout in todaysWorkouts {
            if let distance = workout.totalDistance {
                let miles = distance.doubleValue(for: HKUnit.mile())
                totalMiles += miles
            }
        }
        
        DispatchQueue.main.async {
            self.todaysDistance = totalMiles
            self.todaysWorkouts = todaysWorkouts
            #if !os(watchOS)
            // Get current goal from widget store or default to 1.0
            let widgetData = WidgetDataStore.load()
            let currentGoal = widgetData.goal
            let safeGoal = currentGoal > 0 ? currentGoal : 1.0

            // Use unified progress calculation
            WidgetDataStore.save(todayMiles: totalMiles, goal: safeGoal)
            #endif
            if !self.hasTodaysDistanceLoaded {
                self.hasTodaysDistanceLoaded = true
                self.checkInitialDataReady()
            }
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
    func filterWorkoutsForSpecificDate(workouts: [HKWorkout], targetDate: Date, completion: @escaping ([HKWorkout]) -> Void) {
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
    func getLocalCalendar(for workout: HKWorkout, completion: @escaping (Calendar) -> Void) {
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

    /// Fetches all GPS location points from the route associated with a workout.
    /// Returns an empty array if no route data exists (indoor/manual workouts).
    func fetchAllRouteLocations(for workout: HKWorkout) async -> [CLLocation] {
        // Step 1: Get all HKWorkoutRoute objects for this workout
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let query = HKAnchoredObjectQuery(
                type: HKSeriesType.workoutRoute(),
                predicate: predicate,
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, _, error in
                if let routes = samples as? [HKWorkoutRoute] {
                    continuation.resume(returning: routes)
                } else {
                    continuation.resume(returning: [])
                }
            }
            healthStore.execute(query)
        }

        guard !routes.isEmpty else { return [] }

        // Step 2: For each route, collect all location batches
        var allLocations: [CLLocation] = []

        for route in routes {
            let locations: [CLLocation] = await withCheckedContinuation { continuation in
                var accumulated: [CLLocation] = []
                let routeQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                    if let locations = locations {
                        accumulated.append(contentsOf: locations)
                    }
                    if done {
                        continuation.resume(returning: accumulated)
                    }
                }
                self.healthStore.execute(routeQuery)
            }
            allLocations.append(contentsOf: locations)
        }

        // Sort by timestamp to ensure correct order
        allLocations.sort { $0.timestamp < $1.timestamp }

        return allLocations
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
    
    // calculateRetroactiveStreak moved to HealthKitManager+StreakCalculation.swift
    
    // fetchAllWorkoutData moved to HealthKitManager+DataFetching.swift
    
    // performInitialWorkoutFetch, fetchWorkoutsSmartly, updateCachedWorkoutData,
    // recalculateStatsWithAllWorkouts, recalculateStreakWithCurrentSettings,
    // debugWorkoutTimezones moved to HealthKitManager+DataFetching.swift
    
    /// Analyzes a single workout's timezone information
    func analyzeWorkoutTimezone(_ workout: HKWorkout) {
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
    
    // fetchFastestMilePaceSmartly, fetchWorkoutSplits, calculateFastestMileTime moved to HealthKitManager+PersonalRecords.swift
    
    // Streak calculation methods moved to HealthKitManager+StreakCalculation.swift
    
    // Step counter functions moved to HealthKitManager+DataFetching.swift
    
    // updateCalendarWithTimezoneCorrectedData moved to HealthKitManager+DataFetching.swift
    
    // fetchMonthlyStepsData and groupWorkoutsWithTimezoneAwareness moved to HealthKitManager+DataFetching.swift
    
    // MARK: - Workout Lookup Methods (moved to HealthKitManager+WorkoutIndex.swift)
    
    // MARK: - Workout Index Management (moved to HealthKitManager+WorkoutIndex.swift)
    
    /// Get the timezone-corrected local end time for a workout
    /// Returns the corrected time if workout is in index, otherwise returns workout's device time
    func getCorrectedLocalTime(for workout: HKWorkout) -> Date {
        #if !os(watchOS)
        if let record = workoutRecord(forUUID: workout.uuid.uuidString) {
            return record.localEndTime
        }
        return workout.endDate
        #else
        return workout.endDate
        #endif
    }
} 