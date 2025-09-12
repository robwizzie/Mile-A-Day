import Foundation
import HealthKit
import WidgetKit
import CoreLocation

class HealthKitManager: ObservableObject {
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
        // Load preferences on initialization
        let prefs = AppPreferences.load()
        self.useLocationBasedTimezone = prefs.useLocationBasedTimezone
        
        // Load cached data on initialization
        loadCachedData()
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
        
        print("[HealthKit] Loaded cached data - Fastest pace: \(cachedFastestMilePace), Most miles: \(cachedMostMilesInOneDay), Total miles: \(cachedTotalLifetimeMiles), Streak: \(cachedRetroactiveStreak), Latest workout: \(cachedLatestWorkoutDate?.description ?? "None"), Workout count: \(cachedWorkoutCount)")
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
        
        print("[HealthKit] Saved cached data - Fastest pace: \(fastestMilePace), Most miles: \(mostMilesInOneDay), Total miles: \(totalLifetimeMiles), Streak: \(retroactiveStreak), Latest workout: \(cachedLatestWorkoutDate?.description ?? "None"), Workout count: \(cachedWorkoutCount)")
    }
    
    /// Checks if cache is still valid and if we need to fetch new workouts
    private func isCacheValid() -> Bool {
        guard let lastUpdate = lastWorkoutCacheUpdate else { return false }
        let oneHourAgo = Date().addingTimeInterval(-3600) // 1 hour
        return lastUpdate > oneHourAgo
    }
    
    /// Checks if we need to fetch new workouts based on latest workout date
    private func needsNewWorkoutFetch() -> Bool {
        // If no cached data, we need to fetch
        guard cachedLatestWorkoutDate != nil else { return true }
        
        // If cache is older than 3 days, we need to fetch (timezone buffer)
        guard let lastUpdate = lastWorkoutCacheUpdate else { return true }
        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 3600) // 3 days
        if lastUpdate < threeDaysAgo {
            print("[HealthKit] Cache is older than 3 days, need to fetch new workouts")
            return true
        }
        
        // If we have recent cache, we're good
        print("[HealthKit] Cache is recent, no need to fetch new workouts")
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
        let types: Set = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKSeriesType.workoutRoute()
        ]
        
        healthStore.requestAuthorization(toShare: nil, read: types) { success, error in
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
                print("[HealthKit] Background delivery enabled for workouts")
            } else {
                print("[HealthKit] Failed to enable background delivery: \(error?.localizedDescription ?? "Unknown error")")
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
                    // Get current goal from widget store or default to 1.0
                    let currentGoal = WidgetDataStore.load().goal
                    let safeGoal = currentGoal > 0 ? currentGoal : 1.0
                    
                    // Use unified progress calculation
                    WidgetDataStore.save(todayMiles: 0, goal: safeGoal)
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
            limit: 10,
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
            
            // Populate cached workouts for current streak calculations
            DispatchQueue.main.async {
                self.cachedWorkouts = workouts
                self.cachedWorkoutCount = workouts.count
                if let latestWorkout = workouts.max(by: { $0.endDate < $1.endDate }) {
                    self.cachedLatestWorkoutDate = latestWorkout.endDate
                }
                print("[HealthKit] Populated cachedWorkouts with \(workouts.count) workouts")
            }
            
            // Track most miles in a day
            let mostMilesInDay: Double = 0.0
            let mostMilesWorkouts: [HKWorkout] = []
            
            // Group workouts by day using location-aware time zones if enabled
            if self.useLocationBasedTimezone {
                // For large datasets, only process recent workouts with location-aware logic
                if workouts.count > 100 {
                    print("[HealthKit] Large dataset (\(workouts.count) workouts) - using hybrid approach")
                    
                    // Split into recent (last 30 days) and older workouts
                    let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                    let recentWorkouts = workouts.filter { $0.endDate >= thirtyDaysAgo }
                    let olderWorkouts = workouts.filter { $0.endDate < thirtyDaysAgo }
                    
                    print("[HealthKit] Processing \(recentWorkouts.count) recent workouts with location-aware timezone")
                    print("[HealthKit] Processing \(olderWorkouts.count) older workouts with device timezone")
                    
                    // TEMPORARY: Use device timezone for all until we fix the deadlock
                    print("[HealthKit] Temporarily using device timezone for all workouts to prevent deadlock")
                    let allWorkoutsByDay = self.groupWorkoutsByDeviceDay(workouts: workouts)
                    self.processWorkoutsByDay(allWorkoutsByDay, mostMilesInDay: mostMilesInDay, mostMilesWorkouts: mostMilesWorkouts)
                } else {
                    // TEMPORARY: Use device timezone even for small datasets to prevent deadlock
                    print("[HealthKit] Small dataset (\(workouts.count) workouts) - temporarily using device timezone")
                    let workoutsByDay = self.groupWorkoutsByDeviceDay(workouts: workouts)
                    self.processWorkoutsByDay(workoutsByDay, mostMilesInDay: mostMilesInDay, mostMilesWorkouts: mostMilesWorkouts)
                }
            } else {
                // Legacy behavior: group by device timezone (safer for large datasets)
                print("[HealthKit] Using device timezone grouping (\(workouts.count) workouts)")
                let workoutsByDay = self.groupWorkoutsByDeviceDay(workouts: workouts)
                self.processWorkoutsByDay(workoutsByDay, mostMilesInDay: mostMilesInDay, mostMilesWorkouts: mostMilesWorkouts)
            }
        }
        
        healthStore.execute(query)
    }
    
        // Fetch fastest mile pace from workout data (prioritizing split times over average pace)
    func fetchFastestMilePace() {
        // Use smart approach if we have cached workouts
        if !cachedWorkouts.isEmpty {
            print("[HealthKit] Using smart fastest mile calculation with cached workouts")
            fetchFastestMilePaceSmartly()
            return
        }
        
        // Fallback to full fetch if no cached workouts
        guard isAuthorized else { 
            print("[HealthKit] Not authorized for fastest mile calculation")
            return 
        }
        
        print("[HealthKit] Starting fastest mile pace calculation with split times priority...")
        
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
                print("[HealthKit] Self is nil in fastest mile calculation")
                return 
            }
            
            if let error = error {
                print("[HealthKit] Error fetching workouts for fastest mile: \(error.localizedDescription)")
                return
            }
            
            guard let workouts = samples as? [HKWorkout] else {
                print("[HealthKit] No workouts found for fastest mile calculation")
                return
            }
            
            print("[HealthKit] Found \(workouts.count) workouts to analyze for fastest mile")
            
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
            
            print("[HealthKit] Processing \(qualifyingWorkouts.count) qualifying workouts for fastest mile")
            
            // Process each qualifying workout to get the fastest mile time
            for workout in qualifyingWorkouts {
                dispatchGroup.enter()
                
                self.calculateFastestMileTime(from: workout) { mileTime in
                    defer { dispatchGroup.leave() }
                    
                    if let mileTime = mileTime {
                        processedWorkouts += 1
                        if mileTime < fastestPace {
                            fastestPace = mileTime
                            print("[HealthKit] New fastest mile time found: \(self.formatPace(minutesPerMile: mileTime)) from workout on \(workout.endDate)")
                        }
                    }
                }
            }
            
            // Wait for all workout processing to complete
            dispatchGroup.notify(queue: .main) {
                let calculatedPace = fastestPace == .infinity ? 0.0 : fastestPace
                
                print("[HealthKit] Updating fastestMilePace on main thread: \(calculatedPace)")
                self.fastestMilePace = calculatedPace
                
                if calculatedPace > 0 {
                    print("[HealthKit] Fastest mile pace calculated: \(self.formatPace(minutesPerMile: calculatedPace)) from \(processedWorkouts) qualifying workouts")
                    // Find workouts that achieved this fastest mile pace
                    self.findFastestMileWorkouts()
                } else {
                    print("[HealthKit] No qualifying workouts found for fastest mile pace calculation")
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
        print("[HealthKit] Processing workouts by day for statistics...")
        
        var finalMostMilesInDay = mostMilesInDay
        var finalMostMilesWorkouts = mostMilesWorkouts
        
        // Calculate most miles in a day WITH DEBUG INFO
        for (date, dayWorkouts) in workoutsByDay {
            var totalMilesForDay: Double = 0.0
            
            for workout in dayWorkouts {
                if let distance = workout.totalDistance {
                    let miles = distance.doubleValue(for: HKUnit.mile())
                    totalMilesForDay += miles
                }
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            
            // Log any day with unusually high mileage for debugging
            if totalMilesForDay > 10.0 {
                print("[HealthKit] ⚠️ HIGH MILEAGE DAY: \(dateFormatter.string(from: date)) = \(String(format: "%.2f", totalMilesForDay)) miles (\(dayWorkouts.count) workouts)")
                for (index, workout) in dayWorkouts.enumerated() {
                    if let distance = workout.totalDistance {
                        let miles = distance.doubleValue(for: HKUnit.mile())
                        print("[HealthKit]   Workout \(index + 1): \(String(format: "%.2f", miles)) miles at \(workout.endDate)")
                    }
                }
            }
            
            if totalMilesForDay > finalMostMilesInDay {
                finalMostMilesInDay = totalMilesForDay
                finalMostMilesWorkouts = dayWorkouts
                print("[HealthKit] New record day: \(dateFormatter.string(from: date)) with \(String(format: "%.2f", totalMilesForDay)) miles")
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
                print("[HealthKit] Updated most miles (device timezone): \(String(format: "%.2f", finalMostMilesInDay))")
            }
            self.retroactiveStreak = streak
            
            print("[HealthKit] Final stats - Most miles: \(String(format: "%.2f", finalMostMilesInDay)), Streak: \(streak)")
            
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
            // Get current goal from widget store or default to 1.0
            let currentGoal = WidgetDataStore.load().goal
            let safeGoal = currentGoal > 0 ? currentGoal : 1.0
            
            // Use unified progress calculation
            WidgetDataStore.save(todayMiles: totalMiles, goal: safeGoal)
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
        
        print("[HealthKit] Grouping \(workouts.count) workouts by local time zones...")
        
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
                        
                        // Log timezone info for debugging
                        let formatter = DateFormatter()
                        formatter.dateStyle = .medium
                        formatter.timeStyle = .short
                        formatter.timeZone = calendar.timeZone
                        
                        print("[HealthKit] Workout on \(workout.endDate) grouped to local date \(formatter.string(from: localDate)) (timezone: \(calendar.timeZone.identifier))")
                    } else {
                        print("[HealthKit] Warning: Could not create local date for workout on \(workout.endDate)")
                    }
                }
            }
        }
        
        // Use notify instead of wait to avoid blocking
        dispatchGroup.notify(queue: .main) {
            let debugInfo = "Grouped \(workouts.count) workouts into \(workoutsByDay.count) distinct days using location-aware timezones"
            print("[HealthKit] \(debugInfo)")
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
        
        print("[HealthKit] Found \(todaysWorkouts.count) workouts that occurred today (using device timezone for safety).")
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
        
        print("[HealthKit] Found \(targetDateWorkouts.count) workouts for target date (using device timezone for safety).")
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
            print("[HealthKit] Workout at unusual hour (\(workoutHour):00), but cannot determine alternate timezone without more data")
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
        print("[HealthKit] Calculating streak with timezone-aware adjustments...")
        
        // STEP 1: Apply timezone corrections for recent workouts (last 60 days)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sixtyDaysAgo = calendar.date(byAdding: .day, value: -60, to: today) ?? today
        
        var correctedWorkoutsByDay = workoutsByDay
        var pendingCorrections: [(originalDate: Date, correctedDate: Date, workouts: [HKWorkout])] = []
        
        // Find workouts that need timezone correction
        for (deviceDate, workouts) in workoutsByDay {
            // Only correct recent workouts to avoid processing too many
            if deviceDate >= sixtyDaysAgo {
                for workout in workouts {
                    // Check if this workout might have a timezone issue based on timing
                    let workoutHour = calendar.component(.hour, from: workout.endDate)
                    
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .short
                    dateFormatter.timeStyle = .short
                    print("[HealthKit] Checking workout on \(dateFormatter.string(from: deviceDate)) at hour \(workoutHour)")
                    
                    // If workout was at unusual hours (late night/early morning), it might be timezone shifted
                    if workoutHour <= 5 || workoutHour >= 22 {
                        print("[HealthKit] → Unusual hour \(workoutHour), checking for timezone correction...")
                        // Quick timezone check for Hawaii and other common travel destinations
                        let _ = 0.0 // We don't have exact location, but we can infer
                        let _ = 0.0
                        
                        // GENERAL TIMEZONE CORRECTION: Detect likely timezone shifts based on workout timing
                        
                        // EST to Hawaii (HST): 6 hour difference (EST is UTC-5, HST is UTC-10, but during daylight time EST is UTC-4 and HST stays UTC-10)
                        // So the actual difference is 6 hours during daylight time
                        
                        // If workout was recorded between 10 PM - 6 AM EST, it's likely from a western timezone
                        if workoutHour >= 22 || workoutHour <= 6 {
                            // Try Hawaii timezone correction (-6 hours)
                            if let hawaiiCorrectedDate = calendar.date(byAdding: .hour, value: -6, to: workout.endDate) {
                                let correctedDay = calendar.startOfDay(for: hawaiiCorrectedDate)
                                let hawaiiHour = calendar.component(.hour, from: hawaiiCorrectedDate)
                                
                                // Check if this results in a more reasonable workout time (6 AM - 10 PM HST)
                                if hawaiiHour >= 6 && hawaiiHour <= 22 && correctedDay != deviceDate {
                                    print("[HealthKit] ✅ Correcting HAWAII workout \(workout.endDate) from \(deviceDate) to \(correctedDay)")
                                    pendingCorrections.append((originalDate: deviceDate, correctedDate: correctedDay, workouts: [workout]))
                                }
                            }
                        }
                        
                        // Also check for Pacific timezone (-3 hours from EST)
                        else if workoutHour >= 1 && workoutHour <= 3 {
                            if let pacificCorrectedDate = calendar.date(byAdding: .hour, value: -3, to: workout.endDate) {
                                let correctedDay = calendar.startOfDay(for: pacificCorrectedDate)
                                let pacificHour = calendar.component(.hour, from: pacificCorrectedDate)
                                
                                // Check if this results in a reasonable workout time (6 AM - 10 PM PST)
                                if pacificHour >= 6 && pacificHour <= 22 && correctedDay != deviceDate {
                                    print("[HealthKit] ✅ Correcting PACIFIC workout \(workout.endDate) from \(deviceDate) to \(correctedDay)")
                                    pendingCorrections.append((originalDate: deviceDate, correctedDate: correctedDay, workouts: [workout]))
                                }
                            }
                        }
                    }
                }
            }
        }
        
        print("[HealthKit] Found \(pendingCorrections.count) workouts needing timezone correction")
        
        // Apply corrections SAFELY to prevent workout duplication
        for correction in pendingCorrections {
            let workoutToMove = correction.workouts[0] // Should only be one workout per correction
            
            // Remove from original date
            if var originalWorkouts = correctedWorkoutsByDay[correction.originalDate] {
                originalWorkouts.removeAll { existingWorkout in
                    existingWorkout.uuid == workoutToMove.uuid
                }
                if originalWorkouts.isEmpty {
                    correctedWorkoutsByDay.removeValue(forKey: correction.originalDate)
                    print("[HealthKit] Removed empty day: \(correction.originalDate)")
                } else {
                    correctedWorkoutsByDay[correction.originalDate] = originalWorkouts
                }
            }
            
            // Add to corrected date (ensuring no duplicates)
            if correctedWorkoutsByDay[correction.correctedDate] == nil {
                correctedWorkoutsByDay[correction.correctedDate] = []
            }
            
            // Check if workout is already in the corrected date (prevent duplicates)
            let existsInCorrectedDate = correctedWorkoutsByDay[correction.correctedDate]?.contains { existingWorkout in
                existingWorkout.uuid == workoutToMove.uuid
            } ?? false
            
            if !existsInCorrectedDate {
                correctedWorkoutsByDay[correction.correctedDate]?.append(workoutToMove)
                print("[HealthKit] Moved workout to \(correction.correctedDate)")
            } else {
                print("[HealthKit] ⚠️ Workout already exists in corrected date, skipping")
            }
        }
        
        // STEP 2: Calculate streak with corrected data
        print("[HealthKit] Calculating qualifying workout days from corrected data...")
        let daysWithQualifyingWorkouts = correctedWorkoutsByDay.compactMap { (date, workouts) -> Date? in
            let totalMilesForDay = workouts.reduce(0.0) { total, workout in
                if let distance = workout.totalDistance {
                    return total + distance.doubleValue(for: HKUnit.mile())
                }
                return total
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            
            if totalMilesForDay >= 0.95 {
                print("[HealthKit] ✅ \(dateFormatter.string(from: date)): \(String(format: "%.2f", totalMilesForDay)) miles (\(workouts.count) workouts)")
                return date
            } else {
                print("[HealthKit] ❌ \(dateFormatter.string(from: date)): \(String(format: "%.2f", totalMilesForDay)) miles (not qualifying)")
                return nil
            }
        }.sorted(by: >)
        
        guard !daysWithQualifyingWorkouts.isEmpty else { 
            print("[HealthKit] No qualifying workout days found")
            return 0 
        }
        
        // CALCULATE MOST MILES IN ONE DAY from timezone-corrected data
        var correctedMostMilesInDay: Double = 0.0
        var correctedMostMilesWorkouts: [HKWorkout] = []
        
        for (date, workouts) in correctedWorkoutsByDay {
            let totalMilesForDay = workouts.reduce(0.0) { total, workout in
                if let distance = workout.totalDistance {
                    return total + distance.doubleValue(for: HKUnit.mile())
                }
                return total
            }
            
            if totalMilesForDay > correctedMostMilesInDay {
                correctedMostMilesInDay = totalMilesForDay
                correctedMostMilesWorkouts = workouts
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .short
                print("[HealthKit] New corrected record day: \(dateFormatter.string(from: date)) with \(String(format: "%.2f", totalMilesForDay)) miles")
            }
        }
        
        // Update the mostMilesInOneDay with timezone-corrected value
        DispatchQueue.main.async {
            print("[HealthKit] 🔄 UPDATING mostMilesInOneDay from \(String(format: "%.2f", self.mostMilesInOneDay)) to \(String(format: "%.2f", correctedMostMilesInDay))")
            self.mostMilesInOneDay = correctedMostMilesInDay
            self.mostMilesWorkouts = correctedMostMilesWorkouts
            print("[HealthKit] ✅ mostMilesInOneDay updated. Current value: \(String(format: "%.2f", self.mostMilesInOneDay))")
            
            // Update calendar data with timezone-corrected workout grouping
            self.updateCalendarWithTimezoneCorrectedData(correctedWorkoutsByDay: correctedWorkoutsByDay)
        }
        
        print("[HealthKit] Found \(daysWithQualifyingWorkouts.count) days with qualifying workouts")
        print("[HealthKit] Recent qualifying days: \(daysWithQualifyingWorkouts.prefix(5).map { calendar.dateComponents([.month, .day], from: $0) })")
        
        // Calculate current streak
        var currentStreak = 0
        var checkDate = today
        
        // Check if today has qualifying workouts
        if daysWithQualifyingWorkouts.contains(today) {
            currentStreak += 1
            print("[HealthKit] Today (\(today)) has qualifying workout - streak: \(currentStreak)")
        }
        
        // Check previous days
        checkDate = calendar.date(byAdding: .day, value: -1, to: today)!
        
        while true {
            if daysWithQualifyingWorkouts.contains(checkDate) {
                currentStreak += 1
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .short
                print("[HealthKit] Day \(dateFormatter.string(from: checkDate)) has qualifying workout - streak: \(currentStreak)")
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .short
                print("[HealthKit] Day \(dateFormatter.string(from: checkDate)) has NO qualifying workout - streak ends at: \(currentStreak)")
                break
            }
            
            // Safety break to avoid infinite loops
            if currentStreak > 1000 {
                print("[HealthKit] Safety break - streak calculation exceeded 1000 days")
                break
            }
        }
        
        print("[HealthKit] Final calculated streak: \(currentStreak)")
        return currentStreak
    }
    
    // Function to fetch all workout data in one call
    func fetchAllWorkoutData() {
        // Always fetch today's data (fresh)
        fetchTodaysDistance()
        fetchRecentWorkouts()
        fetchTodaysSteps()
        fetchMonthlyStepsData()
        
        // Always calculate personal records to populate cachedWorkouts
        print("[HealthKit] Calculating personal records to populate cache...")
        calculatePersonalRecords()
        
        // Smart caching: only fetch if we need new workout data
        if needsNewWorkoutFetch() {
            print("[HealthKit] Need to fetch new workout data, starting smart fetch...")
            fetchWorkoutsSmartly()
        } else {
            print("[HealthKit] Using cached data for historical stats")
            // Data is already loaded from cache in init()
        }
    }
    
    /// Performs initial workout fetch to populate cachedWorkouts array
    private func performInitialWorkoutFetch() {
        guard isAuthorized else { return }
        
        print("[HealthKit] Starting initial workout fetch to populate cache...")
        
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
                print("[HealthKit] Error fetching initial workouts: \(error.localizedDescription)")
                return
            }
            
            guard let workouts = samples as? [HKWorkout] else {
                print("[HealthKit] No workouts found for initial fetch")
                return
            }
            
            print("[HealthKit] Found \(workouts.count) workouts for initial cache")
            
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
                
                print("[HealthKit] Initial cache populated with \(workouts.count) workouts")
                
                // Now recalculate all stats with the populated cache
                self.recalculateStatsWithAllWorkouts()
            }
        }
        
        healthStore.execute(query)
    }
    
    /// Smart workout fetching that only gets new workouts since last cache
    private func fetchWorkoutsSmartly() {
        guard isAuthorized else { return }
        
        let startDate = getWorkoutFetchStartDate()
        let endDate = Date()
        
        print("[HealthKit] Smart fetch: Getting workouts from \(startDate?.description ?? "beginning") to \(endDate.description)")
        
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
                print("[HealthKit] Error fetching new workouts: \(error.localizedDescription)")
                return
            }
            
            guard let newWorkouts = samples as? [HKWorkout] else {
                print("[HealthKit] No new workouts found")
                return
            }
            
            print("[HealthKit] Found \(newWorkouts.count) new workouts since last cache")
            
            // Update cached workout data
            self.updateCachedWorkoutData(with: newWorkouts)
            
            // Recalculate stats with all workouts (cached + new)
            self.recalculateStatsWithAllWorkouts()
        }
        
        healthStore.execute(query)
    }
    
    /// Updates cached workout data with new workouts
    private func updateCachedWorkoutData(with newWorkouts: [HKWorkout]) {
        // Add new workouts to cached workouts
        cachedWorkouts.append(contentsOf: newWorkouts)
        
        // Update latest workout date
        if let latestWorkout = newWorkouts.max(by: { $0.endDate < $1.endDate }) {
            cachedLatestWorkoutDate = latestWorkout.endDate
        }
        
        // Update workout count
        cachedWorkoutCount = cachedWorkouts.count
        
        print("[HealthKit] Updated cached workout data - Total workouts: \(cachedWorkoutCount), Latest: \(cachedLatestWorkoutDate?.description ?? "None")")
    }
    
    /// Recalculates all stats using cached + new workouts
    private func recalculateStatsWithAllWorkouts() {
        print("[HealthKit] Recalculating stats with \(cachedWorkouts.count) total workouts")
        
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
            
            print("[HealthKit] Updated stats - Total miles: \(totalMiles), Most miles: \(mostMilesInDay), Streak: \(streak)")
            
            // Save to cache
            self.saveCachedData()
            
            // Fetch fastest mile pace using cached workouts
            self.fetchFastestMilePaceSmartly()
        }
    }
    
    /// Recalculates streak using current timezone settings
    /// Call this after changing useLocationBasedTimezone to refresh calculations
    func recalculateStreakWithCurrentSettings() {
        print("[HealthKit] Recalculating streak with location-based timezone: \(useLocationBasedTimezone)")
        timezoneDebugInfo = "Recalculating streak..."
        calculatePersonalRecords()
    }
    
    /// Debug method to analyze specific workout timezone handling
    func debugWorkoutTimezones() {
        print("[HealthKit] === WORKOUT TIMEZONE DEBUG ===")
        
        // Look for ANY recent workouts (last 30 days) to debug
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let now = Date()
        
        getWorkoutsForDateRange(start: thirtyDaysAgo, end: now) { workouts in
            print("[HealthKit] Found \(workouts.count) workouts in last 30 days")
            
            if workouts.isEmpty {
                print("[HealthKit] No recent workouts found. Checking all workouts...")
                // If no recent workouts, check all workouts
                self.getAllWorkouts { allWorkouts in
                    print("[HealthKit] Found \(allWorkouts.count) total workouts")
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
        print("[HealthKit] --- Analyzing Workout ---")
        print("[HealthKit] Raw endDate: \(workout.endDate)")
        print("[HealthKit] Raw startDate: \(workout.startDate)")
        
        // Show in current device timezone
        let deviceFormatter = DateFormatter()
        deviceFormatter.dateStyle = .full
        deviceFormatter.timeStyle = .full
        deviceFormatter.timeZone = TimeZone.current
        print("[HealthKit] Device timezone (\(TimeZone.current.identifier)): \(deviceFormatter.string(from: workout.endDate))")
        
        // Try to determine workout's local timezone
        getLocalCalendar(for: workout) { calendar in
            let localFormatter = DateFormatter()
            localFormatter.dateStyle = .full
            localFormatter.timeStyle = .full
            localFormatter.timeZone = calendar.timeZone
            
            print("[HealthKit] Workout local timezone (\(calendar.timeZone.identifier)): \(localFormatter.string(from: workout.endDate))")
            
            // Show what day it falls on in each timezone
            let deviceDay = Calendar.current.startOfDay(for: workout.endDate)
            let localDay = calendar.startOfDay(for: workout.endDate)
            
            let dayFormatter = DateFormatter()
            dayFormatter.dateStyle = .medium
            dayFormatter.timeZone = TimeZone.current
            print("[HealthKit] Device timezone day: \(dayFormatter.string(from: deviceDay))")
            
            dayFormatter.timeZone = calendar.timeZone
            print("[HealthKit] Local timezone day: \(dayFormatter.string(from: localDay))")
            
            // Check if this affects streak calculation
            if deviceDay != localDay {
                print("[HealthKit] ⚠️ TIMEZONE MISMATCH! This workout appears on different days depending on timezone")
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
            print("[HealthKit] Not authorized for fastest mile calculation")
            return 
        }
        
        print("[HealthKit] Starting smart fastest mile pace calculation with \(cachedWorkouts.count) cached workouts...")
        
        var fastestPace: TimeInterval = .infinity
        var processedWorkouts = 0
        let dispatchGroup = DispatchGroup()
        
        // Process workouts that are at least 0.95 miles
        let qualifyingWorkouts = cachedWorkouts.filter { workout in
            if let distance = workout.totalDistance {
                let miles = distance.doubleValue(for: HKUnit.mile())
                return miles >= 0.95
            }
            return false
        }
        
        print("[HealthKit] Processing \(qualifyingWorkouts.count) qualifying workouts for fastest mile")
        
        // Process each qualifying workout to get the fastest mile time
        for workout in qualifyingWorkouts {
            dispatchGroup.enter()
            
            self.calculateFastestMileTime(from: workout) { mileTime in
                defer { dispatchGroup.leave() }
                
                if let mileTime = mileTime {
                    processedWorkouts += 1
                    if mileTime < fastestPace {
                        fastestPace = mileTime
                        print("[HealthKit] New fastest mile time found: \(self.formatPace(minutesPerMile: mileTime)) from workout on \(workout.endDate)")
                    }
                }
            }
        }
        
        // Wait for all workout processing to complete
        dispatchGroup.notify(queue: .main) {
            let calculatedPace = fastestPace == .infinity ? 0.0 : fastestPace
            
            print("[HealthKit] Updating fastestMilePace on main thread: \(calculatedPace)")
            self.fastestMilePace = calculatedPace
            
            if calculatedPace > 0 {
                print("[HealthKit] Fastest mile pace calculated: \(self.formatPace(minutesPerMile: calculatedPace)) from \(processedWorkouts) qualifying workouts")
                // Find workouts that achieved this fastest mile pace
                self.findFastestMileWorkouts()
            } else {
                print("[HealthKit] No qualifying workouts found for fastest mile pace calculation")
            }
            
            // Save to cache after calculating fastest pace
            self.saveCachedData()
        }
    }
    
    /// Fetches workout splits by analyzing distance samples for a given workout
    /// Returns split times in minutes per mile, or nil if no splits available
    private func fetchWorkoutSplits(for workout: HKWorkout, completion: @escaping ([TimeInterval]?) -> Void) {
        guard let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            print("[HealthKit] Distance type not available")
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
                print("[HealthKit] Error fetching distance samples: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let distanceSamples = results as? [HKQuantitySample], !distanceSamples.isEmpty else {
                print("[HealthKit] No distance samples found for workout")
                completion(nil)
                return
            }
            
            print("[HealthKit] Found \(distanceSamples.count) distance samples for workout")
            
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
                        
                        // Validate the split time (between 3:00 and 20:00 per mile)
                        if minutesPerMile >= 3.0 && minutesPerMile <= 20.0 {
                            mileSplits.append(minutesPerMile)
                            print("[HealthKit] Mile split: \(self.formatPace(minutesPerMile: minutesPerMile))")
                        }
                        
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
        print("[HealthKit] Calculating fastest mile time for workout on \(workout.endDate)")
        
        // First try to get split times
        fetchWorkoutSplits(for: workout) { [weak self] splitTimes in
            guard let self = self else {
                print("[HealthKit] Self is nil in calculateFastestMileTime")
                completion(nil)
                return
            }
            
            if let splitTimes = splitTimes, !splitTimes.isEmpty {
                // Use the fastest split time
                let fastestSplit = splitTimes.min() ?? 0
                print("[HealthKit] Using fastest split time: \(self.formatPace(minutesPerMile: fastestSplit)) from \(splitTimes.count) splits")
                completion(fastestSplit)
            } else {
                print("[HealthKit] No split times available, falling back to average pace")
                // Fallback to average pace calculation
                if let distance = workout.totalDistance {
                    let miles = distance.doubleValue(for: HKUnit.mile())
                    if miles >= 0.95 {
                        let avgPaceMinutesPerMile = workout.duration / 60.0 / miles
                        
                        // Validate the average pace (between 3:00 and 20:00 per mile)
                        if avgPaceMinutesPerMile >= 3.0 && avgPaceMinutesPerMile <= 20.0 {
                            print("[HealthKit] Using average pace fallback: \(self.formatPace(minutesPerMile: avgPaceMinutesPerMile))")
                            completion(avgPaceMinutesPerMile)
                        } else {
                            print("[HealthKit] Average pace \(avgPaceMinutesPerMile) is outside valid range (3.0-20.0)")
                            completion(nil)
                        }
                    } else {
                        print("[HealthKit] Workout distance \(miles) is below minimum (0.95 miles)")
                        completion(nil)
                    }
                } else {
                    print("[HealthKit] No distance data available for workout")
                    completion(nil)
                }
            }
        }
    }
    
    // MARK: - Current Streak Stats Functions
    
    // Calculate current streak stats (total miles, most miles, fastest pace during current streak)
    func calculateCurrentStreakStats() -> (totalMiles: Double, mostMiles: Double, fastestPace: TimeInterval, streakDays: Int) {
        print("[HealthKit] Calculating current streak stats...")
        
        let currentStreakDays = retroactiveStreak
        guard currentStreakDays > 0 else {
            print("[HealthKit] No current streak, returning zero stats")
            return (0.0, 0.0, 0.0, 0)
        }
        
        // Check if we can use cached data
        if canUseCurrentStreakCache(streakDays: currentStreakDays) {
            print("[HealthKit] Using cached current streak stats")
            return cachedCurrentStreakStats
        }
        
        print("[HealthKit] Cache invalid or streak changed, recalculating...")
        
        let streakWorkouts = getWorkoutsForCurrentStreak()
        print("[HealthKit] Found \(streakWorkouts.count) workouts in current streak")
        
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
        
        print("[HealthKit] Current streak stats calculated and cached")
        return newStats
    }
    
    private func canUseCurrentStreakCache(streakDays: Int) -> Bool {
        // If streak days changed, we need to recalculate
        guard cachedCurrentStreakStats.streakDays == streakDays else {
            print("[HealthKit] Streak days changed (\(cachedCurrentStreakStats.streakDays) -> \(streakDays)), need to recalculate")
            return false
        }
        
        // If cache is older than 1 hour, recalculate
        guard let lastUpdate = lastCurrentStreakStatsUpdate else {
            print("[HealthKit] No previous current streak cache, need to calculate")
            return false
        }
        
        let oneHourAgo = Date().addingTimeInterval(-3600)
        guard lastUpdate > oneHourAgo else {
            print("[HealthKit] Current streak cache is stale, need to recalculate")
            return false
        }
        
        // If we don't have the fastest mile workouts cached, we need to recalculate
        guard !currentStreakFastestMileWorkouts.isEmpty else {
            print("[HealthKit] No cached fastest mile workouts, need to recalculate")
            return false
        }
        
        print("[HealthKit] Current streak cache is valid")
        return true
    }
    
    private func calculateSmartCurrentStreakFastestPace(streakWorkouts: [HKWorkout]) -> TimeInterval {
        // OPTIMIZATION 1: Check if All Time fastest mile is within current streak
        if findWorkoutWithAllTimeFastestMile(in: streakWorkouts) != nil {
            print("[HealthKit] All Time fastest mile is within current streak, using cached value: \(formatPace(minutesPerMile: fastestMilePace))")
            return fastestMilePace
        }
        
        // OPTIMIZATION 2: Check if we have a cached value that's still valid for this streak
        if cachedCurrentStreakFastestPace > 0 && cachedCurrentStreakStats.streakDays == retroactiveStreak {
            // Check if any new qualifying workouts have been added since last calculation
            if !hasNewQualifyingWorkoutsSinceLastStreakCalculation(streakWorkouts: streakWorkouts) {
                print("[HealthKit] No new qualifying workouts since last streak calculation, using cached fastest pace: \(formatPace(minutesPerMile: cachedCurrentStreakFastestPace))")
                return cachedCurrentStreakFastestPace
            }
        }
        
        // FALLBACK: Calculate from scratch using actual split times
        print("[HealthKit] Calculating fastest mile for current streak from scratch using split times...")
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
                        print("[HealthKit] Found likely workout containing all-time fastest mile: \(workout.endDate)")
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
            print("[HealthKit] Found \(newQualifyingWorkouts.count) new qualifying workouts since last calculation")
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
            
            calculateFastestMileTime(from: workout) { [weak self] mileTime in
                defer { dispatchGroup.leave() }
                
                if let mileTime = mileTime, mileTime < fastestPace {
                    fastestPace = mileTime
                    print("[HealthKit] New fastest mile in current streak: \(self?.formatPace(minutesPerMile: mileTime) ?? "Unknown")")
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
        
        print("[HealthKit] Getting workouts for current streak from \(streakStartDate) to \(today)")
        
        // If cachedWorkouts is empty, we need to fetch workouts directly
        if cachedWorkouts.isEmpty {
            print("[HealthKit] No cached workouts available, need to fetch streak period workouts directly")
            // For now, return empty array and let the calling code handle this
            // In a production app, you might want to make this async and use a completion handler
            return []
        }
        
        // Filter cached workouts to current streak period
        let streakWorkouts = cachedWorkouts.filter { workout in
            let workoutDay = calendar.startOfDay(for: workout.endDate)
            return workoutDay >= streakStartDate && workoutDay <= today
        }
        
        print("[HealthKit] Found \(streakWorkouts.count) workouts in streak period")
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
        
        print("[HealthKit] Fetching workouts for current streak period from \(streakStartDate) to \(today)")
        
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
        ) { _, samples, error in
            if let error = error {
                print("[HealthKit] Error fetching streak period workouts: \(error.localizedDescription)")
                completion([])
                return
            }
            
            let workouts = samples as? [HKWorkout] ?? []
            print("[HealthKit] Fetched \(workouts.count) workouts for current streak period")
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
                print("[HealthKit] Today's steps: \(self.todaysSteps)")
            }
        }
        
        healthStore.execute(query)
    }
    
    // Update calendar data with timezone-corrected workout grouping
    private func updateCalendarWithTimezoneCorrectedData(correctedWorkoutsByDay: [Date: [HKWorkout]]) {
        print("[HealthKit] 📅 UPDATING CALENDAR with \(correctedWorkoutsByDay.count) workout days")
        
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
                print("[HealthKit] 📅 Calendar: \(dateString) = \(String(format: "%.2f", totalMiles)) miles ✅")
                
                // Special logging for Hawaii target dates
                if targetDates.contains(dateString) {
                    print("[HealthKit] 🏝️ HAWAII TARGET DATE FOUND: \(dateString) with \(String(format: "%.2f", totalMiles)) miles!")
                }
            } else if targetDates.contains(dateString) {
                print("[HealthKit] ⚠️ HAWAII TARGET DATE \(dateString) has only \(String(format: "%.2f", totalMiles)) miles")
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
        
        print("[HealthKit] 📅 Calendar update complete: \(originalCount) → \(newCount) qualifying days")
        
        // Verify Hawaii target dates are now completed
        for targetDate in targetDates {
            if let date = dateFormatter.date(from: targetDate) {
                let startOfDay = calendar.startOfDay(for: date)
                let isCompleted = self.dailyMileGoals[startOfDay] ?? false
                print("[HealthKit] 🎯 Final check - \(targetDate): \(isCompleted ? "✅ COMPLETED" : "❌ STILL MISSING")")
            }
        }
    }
    
    // Fetch step data and mile goals for a specific month
    func fetchMonthlyStepsData(for month: Date = Date(), completion: (() -> Void)? = nil) {
        guard isAuthorized else { return }
        
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let calendar = Calendar.current
        
        // Get the date interval for the specified month
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return }
        
        let startOfMonth = monthInterval.start
        let endOfMonth = monthInterval.end
        
        var dailySteps: [Date: Int] = [:]
        var dailyMileGoals: [Date: Bool] = [:]
        let group = DispatchGroup()
        
        // Create a date range query for each day in the month
        var currentDate = startOfMonth
        while currentDate < endOfMonth {
            let startOfDay = calendar.startOfDay(for: currentDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            
            group.enter()
            
            // Query for steps
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
            
            // Query for mile goal (running/walking workouts)
            group.enter()
            
            let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
            let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
            let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
            let workoutPredicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
            let finalWorkoutPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [compoundPredicate, workoutPredicate])
            
            let workoutQuery = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: finalWorkoutPredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                defer { group.leave() }
                
                if let workouts = samples as? [HKWorkout] {
                    let totalMiles = workouts.reduce(0.0) { total, workout in
                        if let distance = workout.totalDistance {
                            return total + distance.doubleValue(for: HKUnit.mile())
                        }
                        return total
                    }
                    // Check if mile goal was reached (assuming 1 mile goal)
                    // NOTE: This uses device timezone for calendar display
                    // TODO: Update to use timezone-corrected workout grouping for consistency
                    dailyMileGoals[startOfDay] = totalMiles >= 0.95
                } else {
                    dailyMileGoals[startOfDay] = false
                }
            }
            
            healthStore.execute(workoutQuery)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.dailyStepsData = dailySteps
            self?.dailyMileGoals = dailyMileGoals
            completion?()
        }
    }
    
    // Get workouts for a specific date using location-aware timezone calculation
    func getWorkoutsForDate(_ date: Date, completion: @escaping ([HKWorkout]) -> Void) {
        // Look for workouts within a broader time range to catch timezone edge cases
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
} 