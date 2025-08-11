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
    
    // Calendar pinned to UTC to avoid streak resets due to local timezone changes while traveling
    private var utcCalendar: Calendar = {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
    
    // Cache workout timezone by workout UUID string -> timezone identifier
    private let timeZoneCacheKey = "workout_tz_cache"
    private var workoutTimeZoneCache: [String: String] = [:]
    private let cacheQueue = DispatchQueue(label: "com.mileaday.tzcache")
    
    private func loadTimeZoneCache() {
        if !workoutTimeZoneCache.isEmpty { return }
        if let data = UserDefaults.standard.data(forKey: timeZoneCacheKey),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            workoutTimeZoneCache = dict
        }
    }
    
    private func saveTimeZoneCache() {
        if let data = try? JSONEncoder().encode(workoutTimeZoneCache) {
            UserDefaults.standard.set(data, forKey: timeZoneCacheKey)
        }
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
                    self.loadTimeZoneCache()
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
    func fetchTodaysDistance() {
        guard isAuthorized else { return }
        
        let now = Date()
        let startOfDay = utcCalendar.startOfDay(for: now)
        
        // Always use current time for distance calculation
        let endTime = now
        
        // Look for both running and walking workouts
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        
        // Combine the predicates to find running or walking workouts from today
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        let todayPredicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endTime, options: .strictStartDate)
        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [compoundPredicate, todayPredicate])
        
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
            
            // Calculate total distance from all workouts
            var totalMiles: Double = 0.0
            
            for workout in workouts {
                if let distance = workout.totalDistance {
                    let miles = distance.doubleValue(for: HKUnit.mile())
                    totalMiles += miles
                }
            }
            
            DispatchQueue.main.async {
                self.todaysDistance = totalMiles
                self.recentWorkouts = workouts
                // Get current goal from widget store or default to 1.0
                let currentGoal = WidgetDataStore.load().goal
                let safeGoal = currentGoal > 0 ? currentGoal : 1.0
                
                // Use unified progress calculation
                WidgetDataStore.save(todayMiles: totalMiles, goal: safeGoal)
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
            
            // Group workouts by their local day (based on where the workout took place)
            self.groupWorkoutsByLocalDay(workouts) { workoutsByDay in
                // Calculate most miles in a day
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
                
                // Calculate retroactive streak
                let streak = self.calculateRetroactiveStreak(workoutsByDay: workoutsByDay)
                
                DispatchQueue.main.async {
                    self.mostMilesInOneDay = mostMilesInDay
                    self.mostMilesWorkouts = mostMilesWorkouts
                    self.retroactiveStreak = streak
                }
                
                // Now fetch the fastest mile pace separately using proper HealthKit speed data
                self.fetchFastestMilePace()
            }
        }
        
        healthStore.execute(query)
    }
    
        // Fetch fastest mile pace from workout data (average pace of fastest workout that's at least 1 mile)
    func fetchFastestMilePace() {
        guard isAuthorized else { 
            print("[HealthKit] Not authorized for fastest mile calculation")
            return 
        }
        
        print("[HealthKit] Starting fastest mile pace calculation...")
        
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
            var qualifyingWorkouts = 0
            
            // Find the fastest average pace from workouts that are at least 0.95 miles
            for workout in workouts {
                if let distance = workout.totalDistance {
                    let miles = distance.doubleValue(for: HKUnit.mile())
                    
                    // Only consider workouts that are at least 0.95 miles (accounts for GPS variance)
                    if miles >= 0.95 {
                        // Calculate average pace for this workout (minutes per mile)
                        let avgPaceMinutesPerMile = workout.duration / 60.0 / miles
                        
                        // Check for reasonable pace values (between 3:00 and 20:00 per mile)
                        if avgPaceMinutesPerMile >= 3.0 && avgPaceMinutesPerMile <= 20.0 {
                            qualifyingWorkouts += 1
                            if avgPaceMinutesPerMile < fastestPace {
                                fastestPace = avgPaceMinutesPerMile
                                print("[HealthKit] New fastest pace found: \(self.formatPace(minutesPerMile: avgPaceMinutesPerMile)) from workout on \(workout.endDate)")
                            }
                        }
                    }
                }
            }
            
            print("[HealthKit] Analyzed \(qualifyingWorkouts) qualifying workouts for fastest mile")
            
            DispatchQueue.main.async {
                let calculatedPace = fastestPace == .infinity ? 0.0 : fastestPace
                self.fastestMilePace = calculatedPace
                
                if calculatedPace > 0 {
                    print("[HealthKit] Fastest mile pace calculated: \(self.formatPace(minutesPerMile: calculatedPace))")
                } else {
                    print("[HealthKit] No qualifying workouts found for fastest mile pace calculation")
                }
            }
        }
        
        healthStore.execute(workoutQuery)
    }
    
    // Group workouts by local day (workout location timezone). Falls back to UTC if timezone cannot be resolved.
    private func groupWorkoutsByLocalDay(_ workouts: [HKWorkout], completion: @escaping ([Date: [HKWorkout]]) -> Void) {
        var workoutsByDay: [Date: [HKWorkout]] = [:]
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "com.mileaday.grouping")
        
        for workout in workouts {
            group.enter()
            resolveTimeZoneForWorkout(workout) { tz in
                let calendar: Calendar = {
                    var cal = self.utcCalendar
                    if let tz = tz {
                        cal.timeZone = tz
                    }
                    return cal
                }()
                let localDay = calendar.startOfDay(for: workout.endDate)
                // Normalize key to UTC midnight so all keys are comparable
                let key = self.utcCalendar.startOfDay(for: localDay)
                syncQueue.async {
                    if workoutsByDay[key] == nil { workoutsByDay[key] = [] }
                    workoutsByDay[key]?.append(workout)
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .global(qos: .userInitiated)) {
            completion(workoutsByDay)
        }
    }
    
    // Resolve the workout's timezone using its HKWorkoutRoute first location via reverse geocoding; cached by workout UUID.
    private func resolveTimeZoneForWorkout(_ workout: HKWorkout, completion: @escaping (TimeZone?) -> Void) {
        loadTimeZoneCache()
        let key = workout.uuid.uuidString
        // Use cache if present
        if let tzId = workoutTimeZoneCache[key], let tz = TimeZone(identifier: tzId) {
            completion(tz)
            return
        }
        
        // Fetch associated route sample
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)
        let routeQuery = HKSampleQuery(sampleType: routeType, predicate: predicate, limit: 1, sortDescriptors: nil) { [weak self] _, samples, error in
            guard let self = self else { completion(nil); return }
            if let route = (samples as? [HKWorkoutRoute])?.first {
                // Stream route locations; take the first location to infer time zone
                var resolved = false
                let routeLocationsQuery = HKWorkoutRouteQuery(route: route) { _, locationsOrNil, done, error in
                    if let locs = locationsOrNil, let first = locs.first, !resolved {
                        resolved = true
                        let geocoder = CLGeocoder()
                        geocoder.reverseGeocodeLocation(first) { placemarks, error in
                            if let tz = placemarks?.first?.timeZone {
                                self.cacheQueue.async {
                                    self.workoutTimeZoneCache[key] = tz.identifier
                                    self.saveTimeZoneCache()
                                }
                                completion(tz)
                            } else {
                                completion(nil)
                            }
                        }
                    }
                    if done && !resolved {
                        completion(nil)
                    }
                }
                self.healthStore.execute(routeLocationsQuery)
            } else {
                completion(nil)
            }
        }
        healthStore.execute(routeQuery)
    }
    
    // Helper to calculate retroactive streak from workout data
    private func calculateRetroactiveStreak(workoutsByDay: [Date: [HKWorkout]]) -> Int {
        let calendar = utcCalendar
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        
        // Get all days with qualifying workouts (at least 0.95 miles)
        let daysWithQualifyingWorkouts = workoutsByDay.filter { (date, workouts) in
            let totalMilesForDay = workouts.reduce(0.0) { total, workout in
                if let distance = workout.totalDistance {
                    return total + distance.doubleValue(for: HKUnit.mile())
                }
                return total
            }
            return totalMilesForDay >= 0.95
        }.keys.sorted(by: >)
        
        guard !daysWithQualifyingWorkouts.isEmpty else { return 0 }
        
        // Calculate current streak
        var currentStreak = 0
        var checkDate = yesterday // Start checking from yesterday
        
        // If we have completed today, include it in the streak
        if daysWithQualifyingWorkouts.contains(today) {
            currentStreak += 1
        }
        
        // Check previous days
        while true {
            if daysWithQualifyingWorkouts.contains(checkDate) {
                currentStreak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                // Break if we find a day without a qualifying workout
                break
            }
        }
        
        return currentStreak
    }
    
    // Function to fetch all workout data in one call
    func fetchAllWorkoutData() {
        fetchTodaysDistance()
        fetchRecentWorkouts()
        fetchTotalLifetimeMiles()
        calculatePersonalRecords()
        fetchTodaysSteps()
        fetchMonthlyStepsData()
    }
    
    // Format pace in minutes:seconds per mile
    func formatPace(minutesPerMile: TimeInterval) -> String {
        guard minutesPerMile > 0 else { return "N/A" }
        
        let totalSeconds = Int(minutesPerMile * 60)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
    
    // MARK: - Step Counter Functions
    
    // Fetch today's step count
    func fetchTodaysSteps() {
        guard isAuthorized else { return }
        
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let now = Date()
        let startOfDay = utcCalendar.startOfDay(for: now)
        
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
    
    // Fetch step data and mile goals for a specific month
    func fetchMonthlyStepsData(for month: Date = Date(), completion: (() -> Void)? = nil) {
        guard isAuthorized else { return }
        
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let calendar = utcCalendar
        
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
    
    // Get workouts for a specific date
    func getWorkoutsForDate(_ date: Date, completion: @escaping ([HKWorkout]) -> Void) {
        let calendar = utcCalendar
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        let datePredicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
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
} 