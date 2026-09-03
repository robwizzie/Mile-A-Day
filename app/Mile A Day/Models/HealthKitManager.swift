import Foundation
import HealthKit
import WidgetKit
import WatchConnectivity
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
        
        // The workout's real end instant, unshifted. Local formatters render it
        // in the device's timezone already; adding `timezoneOffset` hours on top
        // moved the displayed clock time by that offset a SECOND time.
        self.localEndTime = workout.endDate
        
        self.timezoneOffset = timezoneOffset
        self.distance = workout.madDistanceMiles
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
    
    /// The local calendar day a workout belongs to: the device calendar day of
    /// its START. Mirrors the iOS `WorkoutProcessor` (and the server's
    /// `local_date`) exactly — see that copy for why the old "unusual hour"
    /// offset search had to go. Second value stays for the persisted
    /// `timezoneOffset` field and is always 0.
    private func determineLocalDateWithOffset(for workout: HKWorkout) -> (Date, Int) {
        (calendar.startOfDay(for: workout.startDate), 0)
    }
}

#endif
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    
    let healthStore = HKHealthStore()
    
    @Published var isAuthorized = false
    @Published var todaysDistance: Double = 0.0 {
        didSet {
            #if os(iOS)
            // Sync the latest distance to the paired Apple Watch. Deferred to the
            // next runloop because this didSet fires inside HealthKitManager.init
            // (loadCachedData + workout-index hydration). pushSnapshotIfReady reads
            // HealthKitManager.shared; calling it synchronously during the
            // singleton's own static init re-enters dispatch_once and traps with
            // EXC_BREAKPOINT.
            DispatchQueue.main.async {
                MADWatchBridge.shared.pushSnapshotIfReady()
            }
            #endif
        }
    }
    @Published var todaysWorkouts: [HKWorkout] = []  // Only today's workouts (for stats)
    @Published var recentWorkouts: [HKWorkout] = []
    @Published var totalLifetimeMiles: Double = 0.0
    @Published var fastestMilePace: TimeInterval = 0.0
    @Published var mostMilesInOneDay: Double = 0.0
    @Published var retroactiveStreak: Int = 0 {
        didSet {
            #if os(iOS)
            // The iPhone has the authoritative streak (full HK history + workout
            // index); the watch only sees what HealthKit has synced locally, so
            // push every change so the watch can show the same number. Deferred
            // for the same reason as todaysDistance above — this fires during
            // HealthKitManager.shared static init and must not re-enter it.
            DispatchQueue.main.async {
                MADWatchBridge.shared.pushSnapshotIfReady()
            }
            #endif
        }
    }
    @Published var mostMilesWorkouts: [HKWorkout] = []
    @Published var todaysSteps: Int = 0
    @Published var dailyStepsData: [Date: Int] = [:]
    @Published var dailyMileGoals: [Date: Bool] = [:]
    /// Streak tokens currently held (0–3), mirrored from the iPhone via
    /// WatchConnectivity. Display-only on the watch — the phone owns all
    /// token logic; 0 (feature off) hides the watch's token pill.
    @Published var heldStreakTokens: Int = 0
    
    // Caching properties.
    // Only the ones actually read from views remain @Published — internal-cache
    // values are plain `var` so mutating them doesn't trigger SwiftUI invalidations.
    @Published var cachedWorkouts: [HKWorkout] = []
    var lastWorkoutCacheUpdate: Date?
    var cachedFastestMilePace: TimeInterval = 0.0
    @Published var cachedMostMilesInOneDay: Double = 0.0
    var cachedTotalLifetimeMiles: Double = 0.0
    var cachedRetroactiveStreak: Int = 0
    var cachedLatestWorkoutDate: Date?
    var cachedWorkoutCount: Int = 0
    @Published var fastestMileWorkouts: [HKWorkout] = []
    @Published var currentStreakFastestMileWorkouts: [HKWorkout] = []
    
    // Efficient deduplication tracking
    var cachedWorkoutUUIDs: Set<UUID> = []

    /// Guards celebration triggers: true only after BOTH fetchTodaysDistance()
    /// AND workout index (streak data) have completed at least once this session.
    @Published var hasLoadedInitialData: Bool = false
    var hasTodaysDistanceLoaded: Bool = false
    var hasIndexOrStreakLoaded: Bool = false

    /// True once fetchTodaysDistance() has actually SUCCEEDED this session — not
    /// merely been attempted. Distinct from `hasTodaysDistanceLoaded`, which flips
    /// true even when the query ERRORS (locked device) so `hasLoadedInitialData`
    /// never hangs. Celebrations gate on THIS: on a cold launch behind a locked
    /// screen the query errors, `todaysDistance` keeps the value `loadCachedData()`
    /// seeded from last night, and firing on it re-showed "mile complete / streak
    /// safe" + the photo prompt for yesterday's already-posted mile until a second
    /// launch refreshed the cache.
    @Published var hasFreshTodaysDistance: Bool = false
    @Published private(set) var todaysDistanceDayStamp: String?

    var hasFreshTodaysDistanceForCurrentDay: Bool {
        hasFreshTodaysDistance && todaysDistanceDayStamp == Self.localDayStamp()
    }

    /// True once fetchRecentWorkouts() has SUCCEEDED at least once this session.
    /// Lets the UI tell "still loading / query erroring" apart from a genuine
    /// empty list, so a locked-device launch stops flashing "No recent workouts".
    @Published var hasLoadedRecentWorkoutsOnce: Bool = false

    private static func localDayStamp(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

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

    #if os(watchOS)
    /// Timestamp of the most recent iPhone-pushed snapshot. The watch's local HK
    /// store is often missing workouts the iPhone has (3rd-party imports, older
    /// history), so when a recent snapshot exists we trust iPhone's numbers over
    /// the local fallback calc.
    var lastIOSSnapshotAt: Date?
    #endif

    func log(_ message: String) {}
    
    // Current streak caching properties.
    // cachedCurrentStreakStats is read from views; the others are internal cache.
    var cachedCurrentStreakFastestPace: TimeInterval = 0.0
    @Published var cachedCurrentStreakStats: (totalMiles: Double, mostMiles: Double, fastestPace: TimeInterval, streakDays: Int) = (0.0, 0.0, 0.0, 0)
    var lastCurrentStreakStatsUpdate: Date?
    
    init() {
        #if os(watchOS)
        // For watchOS, use simplified initialization
        loadCachedData()
        #else
        // PHASE 1: Try to load workout index first (instant)
        if let cachedIndex = WorkoutIndex.load() {
            self.workoutIndex = cachedIndex
            log("[HealthKit] ✅ Loaded workout index: \(cachedIndex.activeStreak()) day streak, \(cachedIndex.totalWorkouts) workouts")

            // Use index data immediately (no 72→161 jump!). Derive the streak as
            // of NOW rather than trusting the stored snapshot, which goes stale
            // once the calendar advances past the grace window with no new runs.
            self.retroactiveStreak = cachedIndex.activeStreak()
            self.hasIndexOrStreakLoaded = true
        } else {
            log("[HealthKit] 📋 No workout index found - will build on first data fetch")
        }

        // Load cached data on initialization
        loadCachedData()
        #endif

        // Activate the iPhone ⇄ Watch bridge on both platforms. The bridge
        // shuttles authoritative iOS data (streak, today's distance, goal,
        // name) to the watch so the two never disagree.
        MADWatchBridge.shared.activate()

        // Resolve real authorization immediately. Nothing else here does: the
        // flag is set by requestAuthorization, which only the UI calls, so a
        // background-launched process read HealthKit with it still false and
        // every query no-opped. This never prompts, and its callback is
        // deferred to the main queue, so it can't re-enter this init.
        refreshAuthorizationStatus()
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
        // Raise-only: on iOS, init already derived retroactiveStreak from the
        // workout index (activeStreak() as of now), which is fresher truth than
        // this snapshot — the cache may hold a transient low value saved while
        // the index had a hole (see UserManager.vettedHealthKitStreak).
        if cachedRetroactiveStreak > retroactiveStreak {
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
    
    /// The types we read from HealthKit. Shared by the authorization request and
    /// the non-prompting status check so the two can never drift apart.
    var healthKitReadTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            // Deliberately NOT here: bodyMass. It briefly was (to scale the
            // WorkoutEnergyEstimate calories), but asking for someone's weight
            // to show a walk's calories is a worse trade than a less
            // personalized estimate — the estimate now always uses the
            // typical-adult fallback. Re-adding ANY type here re-prompts every
            // existing install once (getRequestStatusForAuthorization flips
            // back to .shouldRequest), so grow this set only for features
            // worth that interruption.
            HKSeriesType.workoutRoute()
        ]
    }

    /// The types we write (for workout tracking). workoutRoute share access lets
    /// in-app GPS workouts save their route, which is what the feed's route maps
    /// are built from at sync time.
    // Not private: the Health Access screen reports on exactly these two sets,
    // and a screen that listed its own hand-written copy would drift the first
    // time a type is added here — telling the user everything is fine about a
    // permission the app is actually blocked on.
    var healthKitWriteTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKSeriesType.workoutRoute()
        ]
    }

    /// Resolve authorization WITHOUT prompting, so a process that never shows UI
    /// can still read HealthKit.
    ///
    /// `isAuthorized` only ever became true inside `requestAuthorization`'s
    /// completion — a UI path — which made it really mean "did someone ask
    /// during THIS process", not "is this app authorized". It starts false in
    /// every new process, and HealthKit's own background delivery launches this
    /// app with no UI constantly, so in those processes every read guarded on
    /// the flag silently no-opped: the index logged "❌ Not authorized" and
    /// `recentWorkouts` stayed empty even though the user had granted access
    /// long ago.
    ///
    /// `.unnecessary` means every type we use has already been answered for, so
    /// queries can run. That is exactly what `requestAuthorization`'s `success`
    /// already meant — neither reports whether READ access was *granted*, which
    /// Apple hides by design (a denied read just returns no samples).
    func refreshAuthorizationStatus(completion: ((Bool) -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion?(false)
            return
        }
        healthStore.getRequestStatusForAuthorization(
            toShare: healthKitWriteTypes,
            read: healthKitReadTypes
        ) { [weak self] status, _ in
            DispatchQueue.main.async {
                guard let self else {
                    completion?(false)
                    return
                }
                // Only ever promote to true — never clobber a live grant from an
                // in-flight requestAuthorization. Deliberately no other side
                // effects: this is a question, not a request. Background
                // delivery stays owned by requestAuthorization, which the UI
                // runs on every foreground launch.
                if status == .unnecessary && !self.isAuthorized {
                    self.isAuthorized = true
                }
                completion?(self.isAuthorized)
            }
        }
    }

    // Request authorization to access HealthKit data
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }

        healthStore.requestAuthorization(
            toShare: healthKitWriteTypes,
            read: healthKitReadTypes
        ) { success, error in
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

    /// Whether the user has explicitly turned OFF *write* access to Workouts for
    /// this app. Unlike reads (which Apple hides — a denied read just returns no
    /// samples), share-authorization status is reliable, so an in-app workout
    /// that fails to save can distinguish "user denied Health access"
    /// (actionable — send them to Settings) from a transient save failure.
    /// `.notDetermined` and `.sharingAuthorized` both return false: the former
    /// will prompt on the next save attempt, the latter is already fine.
    func isWorkoutSharingDenied() -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        return healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingDenied
    }

    /// Whether *active energy* write access is off, independently of Workouts.
    ///
    /// Checked before the estimated energy sample joins the workout's sample
    /// batch: `HKWorkoutBuilder.add` accepts or rejects a batch as a UNIT, so a
    /// sample for a denied type would take the distance sample down with it and
    /// save a workout with no distance at all — the exact silent failure the
    /// distance-rejection logging exists to catch. Share status is reliable
    /// (unlike reads), so this is answerable rather than guessed at.
    func isActiveEnergySharingDenied() -> Bool {
        guard HKHealthStore.isHealthDataAvailable(),
              let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else { return false }
        return healthStore.authorizationStatus(for: energyType) == .sharingDenied
    }

    /// Whether *route* write access is off, independently of Workouts.
    ///
    /// These are two separate switches in Settings > Health > Data Access, and a
    /// walk saves perfectly well with Workouts allowed and Route denied — it just
    /// arrives with no map, in Apple Fitness and in our own feed alike, with no
    /// error anywhere (`finishRoute` reports failure but nothing else can tell
    /// that apart from "this walk had no GPS"). Share status is reliable, unlike
    /// read status, so this is worth asking before blaming the trace.
    func isRouteSharingDenied() -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        return healthStore.authorizationStatus(for: HKSeriesType.workoutRoute()) == .sharingDenied
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
        let fetchDayStamp = Self.localDayStamp(for: now)
        
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
            guard let self = self else { return }

            // Query failed — most commonly because the device is locked when a
            // background refresh fires (HealthKit data is protected while locked,
            // so the query errors out). Treat this as "no answer", NOT "0 miles":
            // writing 0 here was randomly resetting the widgets to 0 mi / not
            // completed until the next foreground launch.
            if error != nil {
                DispatchQueue.main.async {
                    if !self.hasTodaysDistanceLoaded {
                        self.hasTodaysDistanceLoaded = true
                        self.checkInitialDataReady()
                    }
                }
                return
            }

            // Reached only on a SUCCESSFUL query (locked-device errors returned
            // above). `hasFreshTodaysDistance` is deliberately NOT flipped here:
            // it must land in the SAME main-queue block that publishes
            // todaysDistance/todaysWorkouts (below). Flipping it in its own
            // earlier block let the Dashboard's onChange run the celebration
            // check against the STALE cached values — the goal guard failed (or
            // read yesterday's workout uuid), and the flame/photo-prompt/fresh
            // window were skipped for a mile that genuinely completed.

            #if os(watchOS)
            let workouts = ((samples as? [HKWorkout]) ?? [])
            #else
            let workouts = ((samples as? [HKWorkout]) ?? [])
                .filter { !DeletedWorkoutRegistry.contains($0.uuid.uuidString) }
            #endif
            guard !workouts.isEmpty else {
                // Successful query, genuinely no workouts in the window — a real 0.
                DispatchQueue.main.async {
                    self.todaysDistance = 0.0
                    self.todaysWorkouts = []
                    self.todaysDistanceDayStamp = fetchDayStamp
                    self.hasFreshTodaysDistance = true
                    #if !os(watchOS)
                    // Get current goal from widget store or default to 1.0
                    let widgetData = WidgetDataStore.load()
                    let currentGoal = widgetData.goal
                    let safeGoal = currentGoal > 0 ? currentGoal : 1.0

                    // Use unified progress calculation
                    WidgetDataStore.save(todayMiles: 0, goal: safeGoal)
                    #endif
                    if !self.hasTodaysDistanceLoaded {
                        self.hasTodaysDistanceLoaded = true
                        self.checkInitialDataReady()
                    }
                }
                return
            }

            let todaysWorkouts = self.filterWorkoutsByDeviceToday(workouts: workouts)
            self.processTodaysWorkouts(todaysWorkouts, dayStamp: fetchDayStamp)
        }
        
        healthStore.execute(query)
    }
    
    /// Retries left for a `fetchRecentWorkouts` that errored out. A locked
    /// device is the common case and it resolves on its own, so a couple of
    /// spaced retries recover the list without waiting for the next refresh.
    private var recentWorkoutsRetriesLeft = 3

    // Fetch recent running/walking workouts (last 30 days, capped at 50).
    // The date predicate keeps HealthKit from scanning all-time history just to
    // pull the most recent samples — far cheaper for users with long histories.
    func fetchRecentWorkouts() {
        // print, not log(): log() is a no-op stub, so this path had no voice at
        // all — an empty Recent Workouts list looked identical whether the query
        // was skipped, errored, or genuinely returned nothing.
        guard isAuthorized else {
            print("[HealthKit] ⏭️ fetchRecentWorkouts skipped — isAuthorized == false")
            return
        }

        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let workoutTypePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast
        let datePredicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: nil, options: .strictEndDate)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [workoutTypePredicate, datePredicate])

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate,
            limit: 50,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self = self else { return }

            // Query failed — most commonly because the device is locked
            // (HealthKit data is protected while locked, so the query errors
            // rather than returning). Same rule as fetchTodaysDistance: this is
            // "no answer", NOT "no workouts". Keep the last good list and retry,
            // because swallowing the error left the list empty until something
            // else happened to call fetchAllWorkoutData again.
            guard error == nil, let workouts = samples as? [HKWorkout] else {
                print("[HealthKit] ⚠️ fetchRecentWorkouts failed: \(error?.localizedDescription ?? "nil samples") — will retry")
                self.retryFetchRecentWorkouts()
                return
            }

            // Successful query: trust the result, empty or not (a real zero).
            DispatchQueue.main.async {
                print("[HealthKit] ✅ fetchRecentWorkouts → \(workouts.count) workouts")
                self.recentWorkoutsRetriesLeft = 3
                self.recentWorkouts = workouts
                // Only NOW is an empty list meaningful — before the first success
                // the UI must show "loading", not "no recent workouts".
                self.hasLoadedRecentWorkoutsOnce = true
            }
        }

        healthStore.execute(query)
    }

    /// Re-run a failed recent-workouts query a few times, backing off, so a
    /// launch behind a locked screen still fills the list once it unlocks.
    private func retryFetchRecentWorkouts() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.recentWorkoutsRetriesLeft > 0 else { return }
            let attempt = 4 - self.recentWorkoutsRetriesLeft
            self.recentWorkoutsRetriesLeft -= 1
            let delay = Double(attempt) * 2.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.fetchRecentWorkouts()
            }
        }
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
            let miles = workout.madDistanceMiles
            if miles > 0 {
                totalDuration += workout.duration
                totalMiles += miles
            }
        }

        guard totalMiles > 0 else { return nil }
        let pace = (totalDuration / 60.0) / totalMiles
        // Sanity check: pace should be between 2:00/mi and 30:00/mi
        guard pace >= 2.0 && pace <= 30.0 else { return nil }
        return pace
    }

    /// Today's walking distance in miles (sum of walking-type workouts only).
    var todaysWalkingDistance: Double {
        todaysWorkouts.reduce(0.0) { sum, workout in
            guard workout.workoutActivityType == .walking else { return sum }
            return sum + workout.madDistanceMiles
        }
    }

    /// Today's fastest pace from individual workouts (best single workout pace today)
    var todaysFastestPace: TimeInterval? {
        var fastestPace: TimeInterval = .infinity

        for workout in todaysWorkouts {
            let miles = workout.madDistanceMiles
            if miles >= 0.3 { // Only consider workouts with meaningful distance
                let pace = (workout.duration / 60.0) / miles
                // Sanity check: pace should be between 2:00/mi and 30:00/mi
                if pace >= 2.0 && pace < fastestPace {
                    fastestPace = pace
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
        workout.madDistanceMiles
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
                totalMiles += workout.madDistanceMiles
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
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: workout.startDate)
            if let date = calendar.date(from: dateComponents) {
                if workoutsByDay[date] == nil {
                    workoutsByDay[date] = []
                }
                workoutsByDay[date]?.append(workout)
            }
        }
        
        return workoutsByDay
    }
    
    /// Filters workouts to those that belong to "today" in the device timezone.
    /// A workout is attributed to the day it STARTED — matching groupWorkoutsByDeviceDay,
    /// the timezone-aware streak grouping, the backend's `local_date` (= start date),
    /// and Apple Health's own daily totals. Keying off endDate instead pulled a workout
    /// that started before midnight but ended after it into today, adding that whole run
    /// to Today's Progress (a walk left "on as it crossed 12am") and falsely completing
    /// the daily goal — while the streak, backend, and Apple Health all counted it
    /// yesterday.
    func filterWorkoutsByDeviceToday(workouts: [HKWorkout]) -> [HKWorkout] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return workouts.filter { workout in
            let workoutDate = calendar.startOfDay(for: workout.startDate)
            return workoutDate == today
        }
    }
    
    /// Processes today's filtered workouts to calculate distance and update UI
    func processTodaysWorkouts(_ todaysWorkouts: [HKWorkout], dayStamp: String? = nil) {
        // Approve whatever was already writing before this build, once. Done
        // here rather than at launch because HealthKit answers nothing on a
        // locked device, and grandfathering an empty list would make every real
        // source look new — turning the consent prompt into noise exactly when
        // it needs to be trusted.
        // ...and only once the 30-day list has actually arrived. Today's
        // workouts are not the source list: an app that wrote yesterday but not
        // yet today doesn't appear in them, so drawing the line off that is the
        // same silent mile-loss as drawing it off nothing.
        WorkoutSourcePreferences.shared.grandfatherIfNeeded(
            existingBundleIds: recentWorkouts.map {
                $0.sourceRevision.source.bundleIdentifier
            } + todaysWorkouts.map { $0.sourceRevision.source.bundleIdentifier },
            listIsComplete: hasLoadedRecentWorkoutsOnce
        )
        // Counted ONCE per real activity. This used to be a plain sum over
        // every HealthKit workout, which double-counts the same walk whenever a
        // second app (Google Health, Strava, a watch platform) also wrote it —
        // a 1.02 mi walk read as 1.98. The backend already excluded those, but
        // this number never asked the backend, so nothing server-side could
        // ever move it. See WorkoutDedup: same rule, same thresholds.
        let totalMiles = WorkoutDedup.totalMiles(todaysWorkouts)

        DispatchQueue.main.async {
            #if os(watchOS)
            // The watch's HK store can be missing workouts the iPhone has (3rd-party
            // imports often sync to phone but not watch). Take the larger of the
            // two so we never visibly under-count today's miles.
            if let last = self.lastIOSSnapshotAt,
               Date().timeIntervalSince(last) < 24 * 60 * 60,
               self.todaysDistance > totalMiles {
                // Keep the iOS-pushed value; local query was lower.
            } else {
                self.todaysDistance = totalMiles
            }
            #else
            self.todaysDistance = totalMiles
            #endif
            self.todaysWorkouts = todaysWorkouts
            self.todaysDistanceDayStamp = dayStamp ?? Self.localDayStamp()
            // Same block as the data it vouches for: observers that fire on
            // this flag must see the values it describes (see fetchTodaysDistance).
            self.hasFreshTodaysDistance = true
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
            localDay(for: workout) == today
        }
        
        completion(todaysWorkouts)
    }
    
    /// Filters workouts to find those that occurred on a specific date in their local time zone
    func filterWorkoutsForSpecificDate(workouts: [HKWorkout], targetDate: Date, completion: @escaping ([HKWorkout]) -> Void) {
        // Use device timezone for now to avoid deadlocks
        let calendar = Calendar.current
        let targetDateStart = calendar.startOfDay(for: targetDate)
        
        let targetDateWorkouts = workouts.filter { workout in
            localDay(for: workout) == targetDateStart
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

    /// Whether the workout has ANY GPS route sample — a limit-1 existence probe
    /// that never enumerates route locations, unlike fetchAllRouteLocations.
    /// Use for cheap "offer the route toggle?" checks.
    func hasRouteData(for workout: HKWorkout) async -> Bool {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let query = HKAnchoredObjectQuery(
                type: HKSeriesType.workoutRoute(),
                predicate: predicate,
                anchor: nil,
                limit: 1
            ) { _, samples, _, _, _ in
                continuation.resume(returning: (samples?.isEmpty == false))
            }
            healthStore.execute(query)
        }
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
    // recalculateStatsWithAllWorkouts moved to HealthKitManager+DataFetching.swift

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
    
    /// The local calendar day a workout belongs to — the ONE rule every surface
    /// that buckets workouts into days must use.
    ///
    /// It is the device calendar day of the workout's START, which is exactly how
    /// the server derives `local_date` (WorkoutSyncService formats
    /// `workout.startDate` with `TimeZone.current`). Bucketing by END instead
    /// silently disagrees with the server for any walk that crosses midnight —
    /// the app draws an empty day while the server counts the mile and keeps the
    /// streak alive, which is indistinguishable from data loss to the user.
    func localDay(for workout: HKWorkout) -> Date {
        Calendar.current.startOfDay(for: workout.startDate)
    }


    #if os(watchOS)
    // MARK: - Watch Summary Refresh
    /// Refreshes today's distance and the current streak from HealthKit. The watch
    /// app can't rely on iOS pushing fresh values, so it queries HK directly each
    /// time the home screen appears or returns to the foreground.
    func refreshWatchSummary() {
        if !isAuthorized {
            requestAuthorization { [weak self] ok in
                guard ok else { return }
                self?.refreshWatchSummary()
            }
            return
        }

        fetchTodaysDistance()
        recalculateWatchStreak()
    }

    /// Fetches the last year of running/walking workouts and recomputes the streak
    /// in-line using the same threshold as iOS (>= 0.95 mi qualifies a day). Stays
    /// self-contained because the iOS streak-calculation extension isn't compiled
    /// into the watch target. Only used as a fallback when no recent iPhone
    /// snapshot is available — iPhone's value is authoritative.
    func recalculateWatchStreak() {
        guard isAuthorized else { return }

        // If iPhone pushed us a snapshot recently, trust it. Local HK on the
        // watch is often missing workouts the iPhone has (imports from Strava /
        // Garmin / Nike, older history that hasn't synced) so recomputing here
        // can produce a much smaller number than the truth.
        if let last = lastIOSSnapshotAt, Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }

        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])

        let oneYearAgo = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date.distantPast
        let datePredicate = HKQuery.predicateForSamples(withStart: oneYearAgo, end: Date(), options: .strictStartDate)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [typePredicate, datePredicate])

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, _ in
            guard let self = self else { return }
            let workouts = (samples as? [HKWorkout]) ?? []
            let byDay = self.groupWorkoutsByDeviceDay(workouts: workouts)

            // Per-day mile totals, then qualifying days (>= 0.95 mi).
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            var qualifying: Set<Date> = []
            for (date, dayWorkouts) in byDay {
                let miles = dayWorkouts.reduce(0.0) { sum, w in
                    sum + w.madDistanceMiles
                }
                if miles >= 0.95 { qualifying.insert(date) }
            }

            // Walk back from today counting consecutive qualifying days. If today
            // doesn't qualify yet, the streak still includes yesterday's chain —
            // matches iOS behavior, so the streak doesn't read 0 first thing in
            // the morning before the user has run.
            var streak = 0
            var probe = today
            if qualifying.contains(probe) {
                streak += 1
                probe = calendar.date(byAdding: .day, value: -1, to: probe) ?? probe
            } else {
                probe = calendar.date(byAdding: .day, value: -1, to: probe) ?? probe
            }
            while qualifying.contains(probe) {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: probe) else { break }
                probe = prev
                if streak > 1000 { break }
            }

            DispatchQueue.main.async {
                self.retroactiveStreak = streak
                self.cachedRetroactiveStreak = streak
                self.saveCachedData()
                if !self.hasIndexOrStreakLoaded {
                    self.hasIndexOrStreakLoaded = true
                    self.checkInitialDataReady()
                }
            }
        }

        healthStore.execute(query)
    }
    #endif
}

// MARK: - iPhone ⇄ Watch Bridge
// One small WCSession owner shared by both platforms. Lives in the same file as
// HealthKitManager because that file is already compiled into both targets.
//
// iOS side: pushes the authoritative HealthKit snapshot (streak + today's
// distance) plus profile bits (goal, first name) every time they change, using
// `updateApplicationContext` — the latest dict is held by the system and
// delivered to the watch on the next connection.
//
// Watch side: applies any received context to `HealthKitManager.shared` and
// `UserManager.shared`. On launch, it also pulls the last cached context out
// of `WCSession.receivedApplicationContext` so the watch shows the real
// numbers immediately, before any new push arrives.
final class MADWatchBridge: NSObject {
    static let shared = MADWatchBridge()

    private var isActivated = false
    private var lastPushedHash: Int = 0

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        if isActivated { return }
        isActivated = true
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    #if os(iOS)
    /// Push the current snapshot if WCSession is up and the watch app is
    /// installed. Safe to call from arbitrary update sites — coalesces by
    /// hashing so identical contexts don't re-transmit.
    func pushSnapshotIfReady() {
        guard isActivated else { return }
        guard WCSession.default.activationState == .activated else { return }
        guard WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }

        let hk = HealthKitManager.shared
        let user = UserManager.shared.currentUser

        var payload: [String: Any] = [
            // Display-grade streak: hk.retroactiveStreak can transiently hold an
            // unverified low value mid-recompute (WorkoutIndex hole). The user
            // model's streak is quarantine-protected (vettedHealthKitStreak), so
            // never push below it — the watch renders this number directly.
            "streak": max(hk.retroactiveStreak, user.streak),
            "todayMiles": hk.todaysDistance,
            "goalMiles": user.goalMiles > 0 ? user.goalMiles : 1.0,
            "firstName": user.firstName ?? "",
            "name": user.name,
            "ts": Date().timeIntervalSince1970
        ]

        // Carry the backend auth token + user id so the watch can upload
        // workouts directly. The watch never refreshes tokens — it relies on
        // these pushes, which is safe because access tokens last 30 days.
        //
        // Never ship a mismatched pair. The watch builds self-scoped upload
        // URLs from this id and authorizes with this token, so if they name
        // different accounts every upload 403s — and the watch has no refresh,
        // no sign-out and no auth UI to recover with. Withholding credentials
        // leaves it read-only until the phone resolves the mismatch (which
        // SessionIdentity does at launch/foreground or on the next 403).
        let identityAgrees = !SessionIdentity.isMismatched
        let authToken = identityAgrees ? UserDefaults.standard.string(forKey: "authToken") : nil
        let backendUserId = identityAgrees ? UserDefaults.standard.string(forKey: "backendUserId") : nil
        if let authToken { payload["authToken"] = authToken }
        if let backendUserId { payload["backendUserId"] = backendUserId }

        // Held streak tokens ride along so the watch can show the shield
        // count next to the streak. Reads the last-applied payload only —
        // no fetch; 0 (feature off) simply hides the watch pill.
        let tokensReady = StreakTokensState.shared.payload.map {
            [$0.double_down.held, $0.streak_save.held, $0.streak_assist.held]
                .filter { $0 }.count
        } ?? 0
        payload["tokensReady"] = tokensReady

        // Hash on the value-bearing fields only (not the timestamp) so we don't
        // re-send identical state. Token + id are included so a token change
        // forces a re-push.
        let stableHash = "\(payload["streak"] ?? 0)|\(payload["todayMiles"] ?? 0)|\(payload["goalMiles"] ?? 0)|\(payload["firstName"] ?? "")|\(payload["name"] ?? "")|\(authToken ?? "")|\(backendUserId ?? "")|\(tokensReady)".hashValue
        if stableHash == lastPushedHash { return }
        lastPushedHash = stableHash

        do {
            try WCSession.default.updateApplicationContext(payload)
        } catch {
            print("[MADWatchBridge] updateApplicationContext failed: \(error.localizedDescription)")
        }
    }
    #endif

    #if os(watchOS)
    /// Apply a snapshot from iOS to the local managers.
    fileprivate func apply(context: [String: Any]) {
        DispatchQueue.main.async {
            let hk = HealthKitManager.shared
            let userManager = UserManager.shared

            // Mark that we just heard from the iPhone so the local fallback
            // streak calc stays out of the way.
            hk.lastIOSSnapshotAt = Date()

            if let streak = context["streak"] as? Int {
                // Always trust iPhone's streak over any local HK calculation.
                hk.retroactiveStreak = streak
                hk.cachedRetroactiveStreak = streak
                hk.saveCachedData()
                if !hk.hasIndexOrStreakLoaded {
                    hk.hasIndexOrStreakLoaded = true
                    hk.checkInitialDataReady()
                }
            }
            if let miles = context["todayMiles"] as? Double, miles >= 0 {
                // Watch may have its own live workout-in-progress that's farther
                // along than iPhone's snapshot — keep the larger value so we
                // never visibly regress mid-workout.
                if miles > hk.todaysDistance {
                    hk.todaysDistance = miles
                }
            }
            if let goal = context["goalMiles"] as? Double, goal > 0 {
                userManager.currentUser.goalMiles = goal
            }
            if let first = context["firstName"] as? String, !first.isEmpty {
                userManager.currentUser.firstName = first
            }
            if let nm = context["name"] as? String, !nm.isEmpty {
                userManager.currentUser.name = nm
            }
            if let token = context["authToken"] as? String, !token.isEmpty {
                UserDefaults.standard.set(token, forKey: "authToken")
            }
            if let backendUserId = context["backendUserId"] as? String, !backendUserId.isEmpty {
                UserDefaults.standard.set(backendUserId, forKey: "backendUserId")
            }
            if let tokens = context["tokensReady"] as? Int {
                hk.heldStreakTokens = tokens
            }
            userManager.saveUserData()
        }
    }

    /// Hydrate from the last-cached iOS snapshot. Call on watch launch so the
    /// home screen displays the real streak immediately rather than 0.
    func hydrateFromCachedContext() {
        let ctx = WCSession.default.receivedApplicationContext
        if !ctx.isEmpty { apply(context: ctx) }
    }
    #endif
}

extension MADWatchBridge: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("[MADWatchBridge] activation error: \(error.localizedDescription)")
        }
        #if os(iOS)
        // Once activation finishes, send the initial snapshot so the watch is
        // immediately in sync without waiting for the next data change.
        DispatchQueue.main.async {
            self.pushSnapshotIfReady()
        }
        #else
        // On the watch, pick up whatever the iPhone last pushed.
        let ctx = session.receivedApplicationContext
        if !ctx.isEmpty {
            self.apply(context: ctx)
        }
        #endif
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) { }

    func sessionDidDeactivate(_ session: WCSession) {
        // Required when switching watches; re-activate to keep working with the
        // newly-paired device.
        WCSession.default.activate()
    }
    #endif

    #if os(watchOS)
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(context: applicationContext)
    }
    #endif
}

// MARK: - The number we showed you

/// A receipt for every workout this app's own tracker measured: the distance
/// that was on screen at the moment the user pressed Finish.
///
/// The tracker's number used to be handed to HealthKit and then thrown away.
/// From that point on, every surface re-derived the distance from HealthKit and
/// the on-device counting rules — a different pipeline with different failure
/// modes — so "0.34 while walking, 0.22 once it saved" had nothing standing in
/// its way. The write can fail silently (Workouts share access granted but
/// Walking + Running Distance denied, and `HKWorkoutBuilder.add`'s error was
/// discarded), the workout can miss a stale read cache, and the counting rules
/// can vote it out of a day's total.
///
/// So we keep the receipt. `HKWorkout.madDistanceMiles` never returns less than
/// it, which makes the invariant structural rather than a property of five
/// pipelines all behaving: what the tracker showed is the floor for what every
/// screen — and the server — is allowed to show afterwards.
///
/// The receipt only ever RAISES, and only for workouts this app measured
/// itself. A third-party recording is untouched, and a HealthKit value that is
/// somehow larger still wins. The single exception is the user typing a
/// distance on the edit screen: that is an answer rather than a floor, so it
/// wins in both directions and for any workout (`userOverride`).
///
/// Lives here rather than in its own file because `WorkoutDedup` below consults
/// it and both are compiled into the Watch target — see the note above
/// `WorkoutDedup`. Same rule: no dependencies beyond Foundation + HealthKit.
final class TrackedWorkoutLedger {
    static let shared = TrackedWorkoutLedger()

    /// How long a receipt is kept. Long enough to cover every screen that can
    /// still show the workout (the 30-day recent list, the month calendar),
    /// short enough that the store stays a few KB.
    private static let retention: TimeInterval = 90 * 24 * 60 * 60
    private static let storageKey = "com.mileaday.trackedWorkoutDistancesV1"

    private struct Entry: Codable {
        let miles: Double
        let recordedAt: Date
        /// Whether the tracker itself measured this workout. Optional because
        /// it is decoded from blobs written before an edit could mint an
        /// entry — every one of those came from the tracker, so nil is true.
        let tracked: Bool?
        /// The user typed this number on the edit screen. Authoritative in
        /// BOTH directions (see `resolvedMiles`); a tracker receipt is only
        /// ever a floor. Optional for the same decode reason.
        let userChosen: Bool?

        var isTrackerMeasured: Bool { tracked != false }
        var isUserChosen: Bool { userChosen == true }
    }

    private let defaults = UserDefaults.standard
    /// Read on every row render, so it stays in memory rather than re-decoding.
    /// Guarded by `lock`: the write lands on `finishWorkout`'s completion queue
    /// while the reads come from HealthKit's own query queues and the main
    /// thread, so an unsynchronised dictionary here is a data race, not a
    /// theoretical one.
    private var entries: [String: Entry]
    private let lock = NSLock()

    private init() {
        entries = Self.decode(defaults.data(forKey: Self.storageKey)) ?? [:]
    }

    private static func decode(_ data: Data?) -> [String: Entry]? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([String: Entry].self, from: data)
    }

    /// Stamp what the tracker showed. Monotonic per workout — a later write can
    /// only raise the receipt, so nothing downstream can be talked back down.
    func record(workoutId: String, miles: Double) {
        guard miles > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        // A number the user typed outranks the tracker's own, so a late
        // receipt must not raise it back to what was measured.
        if let existing = entries[workoutId] {
            guard !existing.isUserChosen, existing.miles < miles else { return }
        }
        entries[workoutId] = Entry(
            miles: miles, recordedAt: Date(), tracked: true, userChosen: nil)
        let cutoff = Date().addingTimeInterval(-Self.retention)
        entries = entries.filter { $0.value.recordedAt >= cutoff }
        persistLocked()
    }

    /// The number this workout is worth, given what HealthKit stores for it.
    ///
    /// A tracker receipt is a FLOOR — HealthKit winning when it is larger is
    /// the point (see the type's note). A number the USER typed is not a
    /// floor, it is the answer: it wins outright, including when it is
    /// smaller. Without that, correcting a treadmill walk downwards changed
    /// nothing — `max` handed back the recorded distance on every screen, and
    /// the next full sync re-uploaded it over the edit the server had
    /// accepted, so the mile stayed whatever it was before the edit.
    func resolvedMiles(forWorkoutId workoutId: String, healthKitMiles: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[workoutId] else { return healthKitMiles }
        if entry.isUserChosen { return entry.miles }
        return max(healthKitMiles, entry.miles)
    }

    /// What the tracker showed for this workout, if this app measured it.
    func miles(forWorkoutId workoutId: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return entries[workoutId]?.miles
    }

    /// Whether this app's own tracker measured this workout. The counting rules
    /// use it to make sure a walk the user watched being recorded can never be
    /// voted out of their own total by another app's copy of it.
    ///
    /// An edit-minted entry answers FALSE: editing someone else's recording
    /// supplies a number, not a measurement, and must not buy that recording
    /// the protection our own walks get from duplicate detection.
    func isTracked(_ workoutId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[workoutId]?.isTrackerMeasured == true
    }

    /// Whether this app holds a distance for the workout at all — tracked or
    /// typed. "Is there a number to show", where `isTracked` is "did we
    /// measure it".
    func hasDistance(_ workoutId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[workoutId] != nil
    }

    /// Record a number the USER chose — the one caller that may lower it. The
    /// monotonic rule exists to stop the PIPELINE talking the number down; a
    /// deliberate edit on the edit screen is the user talking it down, and the
    /// receipt fighting them (flooring the display back to the tracked value
    /// forever) would turn the safety net into a bug.
    ///
    /// Kept for workouts the tracker never measured too — the edit screen is
    /// reachable from any workout's detail, and a Watch treadmill run edited
    /// there has exactly the same claim to the user's number. `tracked` stays
    /// false for those, so an edit still never mints a measurement.
    func userOverride(workoutId: String, miles: Double) {
        guard miles > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        entries[workoutId] = Entry(
            miles: miles,
            recordedAt: Date(),
            tracked: entries[workoutId]?.isTrackerMeasured ?? false,
            userChosen: true)
        let cutoff = Date().addingTimeInterval(-Self.retention)
        entries = entries.filter { $0.value.recordedAt >= cutoff }
        persistLocked()
    }

    /// Caller must hold `lock`.
    private func persistLocked() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

extension HKWorkout {
    /// THE distance for this workout, in miles.
    ///
    /// Every surface that shows or sums a workout's distance goes through this
    /// rather than reading `totalDistance` itself. For anything this app didn't
    /// record it IS `totalDistance`; for a walk our own tracker measured it can
    /// never be less than the number the tracker showed while measuring it;
    /// and for one the user edited it is exactly what they typed.
    var madDistanceMiles: Double {
        let stored = totalDistance?.doubleValue(for: HKUnit.mile()) ?? 0
        return TrackedWorkoutLedger.shared.resolvedMiles(
            forWorkoutId: uuid.uuidString, healthKitMiles: stored)
    }
}

// MARK: - Counting each real walk once

/// Which apps are allowed to add to your miles.
///
/// Duplicate detection only catches a third-party recording that OVERLAPS one of
/// ours. It cannot catch the other failure: Fitbit and friends auto-detect
/// activity and write their own "Outdoor Walk" for a trip to the shops. Nothing
/// overlaps, so the app reads it as a genuine separate walk and counts a mile
/// the user never chose to log. That is "extra workouts added without them
/// knowing", and it needs consent rather than a cleverer threshold — no
/// timestamp comparison can tell an unwanted auto-detected walk from a real one.
///
/// **Nobody's existing total moves when this ships.** Sources already writing
/// are grandfathered as approved at first launch (`grandfatherIfNeeded`), the
/// same trick the backend's `dedupe_since` uses: the migration instant becomes
/// the line, so history is untouched and only what comes AFTER needs an answer.
/// A source that shows up later is `pending` — it does not count until asked,
/// because counting first and apologising later is the bug.
final class WorkoutSourcePreferences: ObservableObject {
    static let shared = WorkoutSourcePreferences()

    enum Decision: String {
        case counted
        case ignored
    }

    private static let decisionsKey = "workoutSourceDecisionsV1"
    private static let grandfatheredKey = "workoutSourceGrandfatheredV1"
    private static let grandfatheredAtKey = "workoutSourceGrandfatheredAtV1"
    private let defaults = UserDefaults.standard

    /// bundle id → the user's answer. Absent means never asked.
    @Published private(set) var decisions: [String: String]

    /// The instant this app started asking about new sources. Everything
    /// recorded before it counts, whatever we know about its source — see
    /// `countsWithoutAsking`. Nil until the line has been drawn.
    private(set) var grandfatheredAt: Date?

    private init() {
        decisions = defaults.dictionary(forKey: Self.decisionsKey) as? [String: String] ?? [:]
        grandfatheredAt = defaults.object(forKey: Self.grandfatheredAtKey) as? Date
        if grandfatheredAt == nil, defaults.bool(forKey: Self.grandfatheredKey) {
            // Grandfathered by the earlier build, which recorded no line. Draw
            // it now: everything already recorded counts (which un-does any
            // source that build missed and has been quietly subtracting since),
            // and only what arrives from here on has to be asked about.
            let line = Date()
            grandfatheredAt = line
            defaults.set(line, forKey: Self.grandfatheredAtKey)
        }
    }

    func decision(for bundleId: String) -> Decision? {
        decisions[bundleId].flatMap(Decision.init(rawValue:))
    }

    /// Whether a workout predates the moment this app started asking about new
    /// sources — in which case it counts, whatever we do or don't know about
    /// the app that wrote it. Consent governs what shows up from now on, never
    /// miles someone already banked.
    ///
    /// This is what makes the feature safe to be wrong about. Grandfathering by
    /// bundle id alone depends on having seen every source in the exact instant
    /// the flag was set — off a list filled by a separate async query that
    /// returns nothing on a locked device. Miss a source in that instant and it
    /// stayed `pending` forever, quietly subtracting itself from every daily
    /// total that had been counting it for months, with nothing on screen to
    /// explain the drop. A timestamp can't be missed. (Same line the backend's
    /// `dedupe_since` draws, for the same reason.)
    ///
    /// Before the line exists, everything is "before" it: nothing has been
    /// established as new yet, and counting is the only answer that can't lose
    /// a mile.
    func isBeforeGrandfatherLine(_ recordedAt: Date) -> Bool {
        guard let line = grandfatheredAt else { return true }
        return recordedAt < line
    }

    /// First-party sources never need approval — Mile A Day's own recordings and
    /// Apple's are the ones the user already expects to be there, and asking
    /// about them would turn consent into a nuisance nobody reads.
    func counts(bundleId: String) -> Bool {
        if WorkoutDedup.isFirstParty(bundleId: bundleId) { return true }
        return decision(for: bundleId) == .counted
    }

    /// True when we have never asked about this source, so it is neither
    /// counting nor refused — it is waiting on the user.
    func isPending(bundleId: String) -> Bool {
        !WorkoutDedup.isFirstParty(bundleId: bundleId) && decision(for: bundleId) == nil
    }

    func set(_ decision: Decision, for bundleId: String) {
        decisions[bundleId] = decision.rawValue
        defaults.set(decisions, forKey: Self.decisionsKey)
    }

    /// Approve every source already writing workouts, ONCE, so upgrading to this
    /// build never silently drops a mile someone already banked.
    ///
    /// Runs from the workout fetch, where the real source list is known. Doing
    /// it at launch instead would grandfather an empty list on a locked device
    /// (HealthKit queries error before first unlock) and then treat every real
    /// source as new — the exact false-positive that would make the prompt
    /// untrustworthy on the one occasion it matters.
    ///
    /// - Parameter listIsComplete: false while the 30-day recent-workouts query
    ///   still hasn't come back. Today's workouts alone are NOT the source list
    ///   — a source that wrote yesterday and not yet today is invisible in it —
    ///   so drawing the line off that partial answer is the same mistake as
    ///   drawing it off an empty one, just harder to notice.
    func grandfatherIfNeeded(existingBundleIds: [String], listIsComplete: Bool) {
        guard !defaults.bool(forKey: Self.grandfatheredKey) else { return }
        guard listIsComplete, !existingBundleIds.isEmpty else { return }
        for bundleId in existingBundleIds where decisions[bundleId] == nil {
            decisions[bundleId] = Decision.counted.rawValue
        }
        let line = Date()
        grandfatheredAt = line
        defaults.set(decisions, forKey: Self.decisionsKey)
        defaults.set(line, forKey: Self.grandfatheredAtKey)
        defaults.set(true, forKey: Self.grandfatheredKey)
    }
}

/// Workouts the user has told us to count or not count, overruling automatic
/// source consent + duplicate detection.
///
/// The rule below is a guess — a good one, but a guess about two recordings the
/// app can only see through timestamps and distances. Someone who walks a mile,
/// stops, and walks a near-identical mile an hour later is not doing anything
/// unusual, and no threshold can tell that apart from one walk written twice.
/// Google Health can also invent a workout that looks real enough to count.
/// So the verdict has to be reversible in BOTH directions, and the reversal has
/// to STICK: a sync, a relaunch or a recalibrate must not quietly re-apply a
/// decision the user already overruled.
///
/// Local, and deliberately so. `DuplicateDecisionService` records the same
/// choice server-side for streaks and the feed, but every distance this app
/// draws is summed on-device from HealthKit and never asks the server — so a
/// server-only override would leave the button looking broken, which is the
/// exact failure that made the on-device rule necessary in the first place.
/// Both are written; this is the one that moves the number on screen.
final class WorkoutDedupOverrides: ObservableObject {
    static let shared = WorkoutDedupOverrides()

    private static let countKey = "workoutDedupCountAnywayV1"
    private static let excludeKey = "workoutDedupExcludeAnywayV1"
    private let defaults = UserDefaults.standard

    /// HKWorkout UUID strings the user has restored to their total.
    @Published private(set) var countAnyway: Set<String>
    /// HKWorkout UUID strings the user has removed from their total.
    @Published private(set) var excludeAnyway: Set<String>

    private init() {
        countAnyway = Set(defaults.stringArray(forKey: Self.countKey) ?? [])
        excludeAnyway = Set(defaults.stringArray(forKey: Self.excludeKey) ?? [])
    }

    func isCountedAnyway(_ workoutId: String) -> Bool {
        countAnyway.contains(workoutId)
    }

    func isExcludedAnyway(_ workoutId: String) -> Bool {
        excludeAnyway.contains(workoutId)
    }

    func setCountAnyway(_ on: Bool, for workoutId: String) {
        if on {
            countAnyway.insert(workoutId)
            excludeAnyway.remove(workoutId)
        } else {
            countAnyway.remove(workoutId)
        }
        persist()
    }

    func setExcludeAnyway(_ on: Bool, for workoutId: String) {
        if on {
            excludeAnyway.insert(workoutId)
            countAnyway.remove(workoutId)
        } else {
            excludeAnyway.remove(workoutId)
        }
        persist()
    }

    func clearDecision(for workoutId: String) {
        countAnyway.remove(workoutId)
        excludeAnyway.remove(workoutId)
        persist()
    }

    private func persist() {
        defaults.set(Array(countAnyway), forKey: Self.countKey)
        defaults.set(Array(excludeAnyway), forKey: Self.excludeKey)
    }
}

/// The same walk, recorded by two apps, counted once.
///
/// Every third-party fitness platform — Google Health, Strava, Garmin, WHOOP —
/// reaches this app by writing into Apple Health. So the SAME walk arrives
/// twice with two UUIDs, and summing HealthKit naively counts it twice. A
/// 1.02 mi walk with Google Health also recording 0.96 mi of it reads as 1.98.
///
/// The backend already solves this (`duplicateExclusionStatements` in
/// workoutService.ts) and that fixes streaks, leaderboards and the feed. It does
/// NOT fix what this app displays, because every "today's distance" on screen is
/// summed on-device straight from HealthKit and never asks the server what
/// counts. That gap is why the dashboard, the Road view and Insights could each
/// show a different, inflated number for the same day.
///
/// So the rule lives here too, deliberately duplicated rather than fetched:
/// these sums run offline, on launch, and inside widget/background paths where a
/// round trip isn't available. The THRESHOLDS below are the contract — they must
/// stay identical to the server's constants or the two will disagree, which is
/// the exact failure this exists to end.
///
/// **Why it's in this file and not its own.** `HealthKitManager.swift` is shared
/// with the Watch target, and the Watch target is NOT a synchronized folder —
/// its membership lives in `project.pbxproj`, which is off-limits. A new file
/// under `app/Mile A Day/` therefore auto-joins the iPhone target ONLY, so the
/// iPhone built fine while the Watch failed with `Cannot find 'WorkoutDedup' in
/// scope` on the call below. Anything a dual-membership file needs must sit in a
/// dual-membership file. For the same reason this type must stay free of
/// main-app-only dependencies: no SwiftUI, no MADTheme, no FitnessSourceCatalog.
enum WorkoutDedup {
    // ─── Must match backend/src/services/workoutService.ts ───────────────
    /// Share of the SHORTER workout that must overlap before it's the same run.
    static let minOverlapRatio = 0.5
    /// How far two measurements of one route may disagree (fraction of longer).
    static let distanceTolerance = 0.2
    /// Absolute floor for the above, so short walks aren't held to a few feet.
    static let distanceFloor = 0.1
    /// How much of the shorter workout must sit inside the longer one before
    /// it's treated as a fragment of the same activity.
    static let containmentRatio = 0.9

    /// A walk Mile A Day or Apple itself recorded — the sources a user already
    /// expects to be there.
    ///
    /// Mirrors `FitnessSourceCatalog.isAppleSource`, which is a bare
    /// `com.apple.` prefix test; it can't be CALLED here because that catalog is
    /// iPhone-only (see the note above). `WorkoutAttribution` delegates to this
    /// so the UI and the arithmetic can't drift apart.
    static func isFirstParty(bundleId: String?) -> Bool {
        guard let bundleId, !bundleId.isEmpty else { return true }
        let lower = bundleId.lowercased()
        return lower.contains("mileaday") || lower.contains("mile-a-day")
            || lower.hasPrefix("com.apple.")
    }

    /// One workout, reduced to what the rule needs.
    private struct Candidate {
        let index: Int
        let uuid: String
        let bundleId: String
        let start: Date
        let end: Date
        let duration: TimeInterval
        let miles: Double
        /// Mile A Day's own recording. Preferred survivor: it's the copy that
        /// carries the GPS route, which is also the server's first tiebreak.
        let isFirstParty: Bool
        /// Measured by THIS app's tracker, with the user watching the number
        /// climb. Outranks everything and is never excluded — see `ranked`.
        let isTracked: Bool
    }

    /// Indices of workouts that should NOT be counted, because another workout
    /// in the same array already covers them.
    ///
    /// Returns indices rather than a filtered array so callers can both sum the
    /// survivors AND show the user what was left out — never removing a workout
    /// silently is a requirement, not a nicety.
    static func duplicateIndices(in workouts: [HKWorkout]) -> Set<Int> {
        Set(duplicateSources(in: workouts).keys)
    }

    /// Excluded index → the index of the workout that already covers it.
    ///
    /// The pairing is the whole point: "not counted" on its own is the app
    /// taking a walk away with no reason given. Naming the recording that
    /// covers it turns that into a statement the user can check against their
    /// own memory of the walk — and disagree with, if we got it wrong.
    /// - Parameter applyingOverrides: pass `false` to ask what the RULE thinks,
    ///   ignoring the user's decisions. The detail screen needs that to offer an
    ///   undo — once an override is in force the workout is no longer excluded,
    ///   so there'd otherwise be nothing left to explain what was undone.
    /// - Parameter skipping: indices already out of the total for a DIFFERENT
    ///   reason (an un-approved source). They take no part: a recording that
    ///   isn't counted must not be the "keeper" that knocks a counted one out,
    ///   or the walk leaves the total twice over and lands in it zero times.
    static func duplicateSources(
        in workouts: [HKWorkout], applyingOverrides: Bool = true,
        skipping: Set<Int> = []
    ) -> [Int: Int] {
        var excluded: [Int: Int] = [:]
        guard workouts.count > 1 else { return excluded }
        let restored = applyingOverrides ? WorkoutDedupOverrides.shared.countAnyway : []

        // Exact repeats first. Two entries with one UUID are one workout by
        // definition, whatever any distance rule says.
        var firstIndexByUUID: [String: Int] = [:]
        var candidates: [Candidate] = []
        for (index, workout) in workouts.enumerated() {
            guard !skipping.contains(index) else { continue }
            let uuid = workout.uuid.uuidString
            if let first = firstIndexByUUID[uuid] {
                excluded[index] = first
                continue
            }
            firstIndexByUUID[uuid] = index

            let duration = workout.duration
            guard duration > 0 else { continue }
            let bundle = workout.sourceRevision.source.bundleIdentifier
            candidates.append(
                Candidate(
                    index: index,
                    uuid: uuid,
                    bundleId: bundle,
                    start: workout.startDate,
                    end: workout.endDate,
                    duration: duration,
                    miles: workout.madDistanceMiles,
                    isFirstParty: isFirstParty(bundleId: bundle),
                    isTracked: TrackedWorkoutLedger.shared.isTracked(uuid)
                )
            )
        }

        // Preferred survivor sorts FIRST, so a later candidate is only ever
        // dropped in favour of a better one. A walk our own tracker measured
        // wins outright — the user watched that number being taken, and no
        // other app's copy of it may replace it in their own total. Then Mile A
        // Day's copy generally (it has the route); then the longer distance,
        // since a fragment can't be longer than the walk that contains it.
        let ranked = candidates.sorted {
            if $0.isTracked != $1.isTracked { return $0.isTracked }
            if $0.isFirstParty != $1.isFirstParty { return $0.isFirstParty }
            if $0.miles != $1.miles { return $0.miles > $1.miles }
            return $0.index < $1.index
        }

        for (position, candidate) in ranked.enumerated() {
            if excluded[candidate.index] != nil { continue }
            // Never drop a walk this app measured itself. Ranking first already
            // makes it the keeper in any pair; this is the belt to that braces,
            // so no future tiebreak can quietly make the tracked walk the loser.
            if candidate.isTracked { continue }
            // The user already looked at this one and said it was a separate
            // walk. That answer outranks the rule, permanently.
            if restored.contains(candidate.uuid) { continue }
            for keeper in ranked[..<position] {
                if excluded[keeper.index] != nil { continue }
                if isSameActivity(candidate, keeper) {
                    excluded[candidate.index] = keeper.index
                    break
                }
            }
        }
        return excluded
    }

    /// Two recordings of one real-world activity.
    ///
    /// Same-source pairs are never matched: one app segmenting its own walk is
    /// that app's business, and UUID equality already covers true repeats.
    private static func isSameActivity(_ a: Candidate, _ b: Candidate) -> Bool {
        guard a.bundleId != b.bundleId else { return false }

        let overlap = min(a.end, b.end).timeIntervalSince(max(a.start, b.start))
        guard overlap >= minOverlapRatio * min(a.duration, b.duration) else {
            return false
        }

        // Either both apps recorded the whole activity, so the distances
        // agree...
        let budget = max(distanceFloor, distanceTolerance * max(a.miles, b.miles))
        if abs(a.miles - b.miles) <= budget { return true }

        // ...or `a` is a FRAGMENT of `b`: its window sits almost entirely inside
        // and it covers no more ground. An app that starts tracking partway
        // through writes a short workout inside the long one, and 0.36 vs 1.84
        // fails every distance test while being unmistakably the same walk.
        return overlap >= containmentRatio * a.duration && a.miles <= b.miles
    }

    /// Why a workout isn't in the total. Nil means it is.
    ///
    /// One enum rather than two booleans because the two reasons need different
    /// words on screen — "we already counted this walk" and "you haven't let
    /// this app add walks" are not the same message, and showing the wrong one
    /// makes the app look like it's inventing rules.
    enum ExclusionReason: Equatable {
        /// Another recording on the same day already covers it.
        case duplicate
        /// The user said not to count this exact workout.
        case userExcluded
        /// The user turned this source off.
        case sourceIgnored
        /// We have never asked whether this source may add to their miles.
        case sourcePending
    }

    /// Workouts kept out of the total because of their SOURCE, by index.
    /// Nothing to do with duplicates — this is only "has the user let this app
    /// add to their miles yet".
    static func consentExclusions(in workouts: [HKWorkout]) -> [Int: ExclusionReason] {
        var out: [Int: ExclusionReason] = [:]
        let prefs = WorkoutSourcePreferences.shared
        let overrides = WorkoutDedupOverrides.shared
        for (index, workout) in workouts.enumerated() {
            let id = workout.uuid.uuidString
            if overrides.isExcludedAnyway(id) {
                out[index] = .userExcluded
                continue
            }
            if overrides.isCountedAnyway(id) { continue }
            let bundleId = workout.sourceRevision.source.bundleIdentifier
            if isFirstParty(bundleId: bundleId) { continue }
            switch prefs.decision(for: bundleId) {
            case .counted: continue
            // An explicit "don't count this app" applies to everything it ever
            // wrote — that answer is the user's, and it outranks the line.
            case .ignored: out[index] = .sourceIgnored
            case nil:
                // Never asked. Only what arrived AFTER we started asking waits
                // on an answer; anything older was already in their total and
                // must not quietly leave it.
                if prefs.isBeforeGrandfatherLine(workout.startDate) { continue }
                out[index] = .sourcePending
            }
        }
        return out
    }

    /// Why each workout is or isn't counted, AND what covers the ones that
    /// aren't — resolved together, because the two answers have to agree. Read
    /// them separately and the label can name a "keeper" that is itself out of
    /// the total.
    static func breakdown(
        in workouts: [HKWorkout]
    ) -> (reasons: [Int: ExclusionReason], coveredBy: [Int: Int]) {
        var reasons = consentExclusions(in: workouts)
        // Duplicate detection runs over what's LEFT — the array minus the
        // consent exclusions, not the whole array. It used to be handed
        // everything, so an un-approved copy could still be chosen as the
        // keeper: the approved recording was marked `.duplicate` of it, the
        // un-approved one stayed `.sourcePending`, and the walk vanished from
        // the day entirely. That is a daily total going DOWN for no reason a
        // user could see.
        let coveredBy = duplicateSources(in: workouts, skipping: Set(reasons.keys))
        for (index, _) in coveredBy where reasons[index] == nil {
            reasons[index] = .duplicate
        }
        return (reasons, coveredBy)
    }

    /// Why each workout in the array is or isn't counted, by index.
    static func exclusions(in workouts: [HKWorkout]) -> [Int: ExclusionReason] {
        breakdown(in: workouts).reasons
    }

    /// Total miles for a set of workouts, counting each real activity once.
    ///
    /// THE function for "how far did they go". Every surface that shows a day's
    /// distance should call this rather than summing the array itself — that's
    /// what stops the dashboard, the Road view and Insights from disagreeing.
    static func totalMiles(_ workouts: [HKWorkout]) -> Double {
        let excluded = exclusions(in: workouts)
        var total = 0.0
        for (index, workout) in workouts.enumerated() where excluded[index] == nil {
            total += workout.madDistanceMiles
        }
        return total
    }

    /// The workouts that actually count, in their original order.
    static func counting(_ workouts: [HKWorkout]) -> [HKWorkout] {
        let excluded = exclusions(in: workouts)
        guard !excluded.isEmpty else { return workouts }
        return workouts.enumerated()
            .filter { excluded[$0.offset] == nil }
            .map(\.element)
    }
}
