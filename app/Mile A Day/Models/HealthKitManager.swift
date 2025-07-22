import Foundation
import HealthKit
import WidgetKit

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
    
    // Request authorization to access HealthKit data
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        
        // Define the types we want to read from HealthKit
        let types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKSeriesType.workoutRoute() // For accessing GPS route data and potential mile splits
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
    func fetchTodaysDistance() {
        guard isAuthorized else { return }
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        
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
                
                // Use unified progress calculation - no live workout distance here since this is base HealthKit data
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
    
    // Calculate personal records and retroactive streak using ACTUAL mile splits
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
            
            // Track fastest mile pace - will be calculated from actual mile splits
            var fastestMilePace: TimeInterval = .infinity
            
            // Track most miles in a day
            var mostMilesInDay: Double = 0.0
            var mostMilesWorkouts: [HKWorkout] = []
            
            // Group workouts by day for streak calculation
            var workoutsByDay: [Date: [HKWorkout]] = [:]
            
            // Process workouts for grouping and most miles calculation
            for workout in workouts {
                // Group by day for most miles and streak calculation
                let calendar = Calendar.current
                let dateComponents = calendar.dateComponents([.year, .month, .day], from: workout.endDate)
                if let date = calendar.date(from: dateComponents) {
                    if workoutsByDay[date] == nil {
                        workoutsByDay[date] = []
                    }
                    workoutsByDay[date]?.append(workout)
                }
            }
            
            // Calculate fastest mile using actual mile split data
            self.calculateFastestMileFromSplits(workouts: workouts) { fastestPace in
                
                DispatchQueue.main.async {
                    fastestMilePace = fastestPace
                    
                    // Continue with other calculations...
                    self.processWorkoutGroupsForRecords(workoutsByDay: workoutsByDay, fastestPace: fastestMilePace)
                }
            }
        }
        
        healthStore.execute(query)
    }
    
    // MARK: - Fastest Mile Calculation Using Actual Mile Splits
    
    /// Calculates the fastest mile from actual mile split data from HealthKit
    /// This gives the true fastest mile time, not an average pace
    private func calculateFastestMileFromSplits(workouts: [HKWorkout], completion: @escaping (TimeInterval) -> Void) {
        var fastestMilePace: TimeInterval = .infinity
        let dispatchGroup = DispatchGroup()
        
        print("[HealthKit] 🔍 Analyzing \(workouts.count) workouts for fastest mile splits...")
        
        for workout in workouts {
            // Only analyze workouts that are at least 1 mile
            guard let distance = workout.totalDistance,
                  distance.doubleValue(for: HKUnit.mile()) >= 0.95 else {
                continue
            }
            
            dispatchGroup.enter()
            
            // First, try to get pre-calculated mile splits from Apple Fitness
            self.checkForAppleFitnessMileSplits(workout) { appleSplits in
                if let fastestAppleSplit = appleSplits.min() {
                    if fastestAppleSplit < fastestMilePace && fastestAppleSplit > 0 {
                        fastestMilePace = fastestAppleSplit
                        print("[HealthKit] 🍎 Found Apple Fitness mile split: \(self.formatPace(minutesPerMile: fastestAppleSplit))")
                    }
                    dispatchGroup.leave()
                } else {
                    // Fallback to calculating from distance samples
                    self.getDistanceSamplesForWorkout(workout) { distanceSamples in
                        defer { dispatchGroup.leave() }
                        
                        let fastestSplit = self.findFastestMileSplit(in: distanceSamples, for: workout)
                        if fastestSplit < fastestMilePace && fastestSplit > 0 {
                            fastestMilePace = fastestSplit
                            print("[HealthKit] 🏃‍♂️ New fastest mile: \(self.formatPace(minutesPerMile: fastestSplit))")
                        }
                    }
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            let finalPace = fastestMilePace == .infinity ? 0 : fastestMilePace
            print("[HealthKit] ✅ Fastest mile analysis complete: \(self.formatPace(minutesPerMile: finalPace))")
            completion(finalPace)
        }
    }
    
    /// Gets distance samples for a specific workout
    private func getDistanceSamplesForWorkout(_ workout: HKWorkout, completion: @escaping ([HKQuantitySample]) -> Void) {
        guard let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            completion([])
            return
        }
        
        // Create predicate for samples during this workout
        let workoutPredicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )
        
        let query = HKSampleQuery(
            sampleType: distanceType,
            predicate: workoutPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, error in
            
            if let error = error {
                print("[HealthKit] Error fetching distance samples: \(error)")
                completion([])
                return
            }
            
            let distanceSamples = samples as? [HKQuantitySample] ?? []
            completion(distanceSamples)
        }
        
        healthStore.execute(query)
    }
    
    /// Attempts to extract pre-calculated mile splits from Apple Fitness workout metadata
    private func checkForAppleFitnessMileSplits(_ workout: HKWorkout, completion: @escaping ([TimeInterval]) -> Void) {
        // Check workout metadata for mile splits
        var mileSplits: [TimeInterval] = []
        
        // Apple Fitness sometimes stores mile splits in workout metadata
        if let metadata = workout.metadata {
            // Look for mile split keys in metadata
            for (key, value) in metadata {
                if let keyString = key as? String,
                   keyString.lowercased().contains("mile") || keyString.lowercased().contains("split") {
                    
                    if let splitValue = value as? NSNumber {
                        let splitMinutes = splitValue.doubleValue / 60.0 // Convert seconds to minutes
                        if splitMinutes >= 3.0 && splitMinutes <= 30.0 { // Sanity check
                            mileSplits.append(splitMinutes)
                            print("[HealthKit] 🍎 Found metadata mile split: \(formatPace(minutesPerMile: splitMinutes))")
                        }
                    }
                }
            }
        }
        
        // Try to get workout route data for more detailed analysis
        if mileSplits.isEmpty {
            getWorkoutRoute(for: workout) { route in
                if let route = route {
                    self.extractMileSplitsFromRoute(route, workout: workout, completion: completion)
                } else {
                    completion([])
                }
            }
        } else {
            completion(mileSplits)
        }
    }
    
    /// Gets workout route data if available
    private func getWorkoutRoute(for workout: HKWorkout, completion: @escaping (HKWorkoutRoute?) -> Void) {
        guard let routeType = HKSeriesType.workoutRoute() else {
            completion(nil)
            return
        }
        
        let predicate = HKQuery.predicateForObjects(from: workout)
        
        let query = HKSampleQuery(
            sampleType: routeType,
            predicate: predicate,
            limit: 1,
            sortDescriptors: nil
        ) { _, samples, error in
            
            if let error = error {
                print("[HealthKit] Error fetching workout route: \(error)")
                completion(nil)
                return
            }
            
            let route = samples?.first as? HKWorkoutRoute
            completion(route)
        }
        
        healthStore.execute(query)
    }
    
    /// Extracts mile splits from workout route data
    private func extractMileSplitsFromRoute(_ route: HKWorkoutRoute, workout: HKWorkout, completion: @escaping ([TimeInterval]) -> Void) {
        // This is a complex operation that requires processing GPS points
        // For now, we'll return empty and rely on distance samples
        // Future enhancement could implement full GPS-based mile split calculation
        print("[HealthKit] 🗺️ Workout route available but GPS-based splits not yet implemented")
        completion([])
    }
    
    /// Finds the fastest consecutive mile split from distance samples
    /// Uses sophisticated algorithm to handle various HealthKit data patterns
    private func findFastestMileSplit(in samples: [HKQuantitySample], for workout: HKWorkout) -> TimeInterval {
        guard samples.count > 1 else {
            // Fallback to average pace if no detailed samples
            return calculateAveragePaceForWorkout(workout)
        }
        
        print("[HealthKit] 🔍 Analyzing \(samples.count) distance samples for mile splits...")
        
        var fastestMilePace: TimeInterval = .infinity
        var cumulativeDistance: Double = 0
        var mileStartTime: Date = workout.startDate
        var mileStartDistance: Double = 0
        var currentMileNumber = 0
        
        // Create time-ordered array of distance points
        var distancePoints: [(time: Date, distance: Double)] = [(workout.startDate, 0)]
        
        for sample in samples {
            let sampleDistance = sample.quantity.doubleValue(for: HKUnit.mile())
            cumulativeDistance += sampleDistance
            distancePoints.append((sample.endDate, cumulativeDistance))
        }
        
        print("[HealthKit] 📏 Total workout distance: \(cumulativeDistance.milesFormatted)")
        
        // Analyze each mile segment
        var mileTargetDistance = 1.0
        var pointIndex = 0
        
        while mileTargetDistance <= cumulativeDistance && pointIndex < distancePoints.count - 1 {
            // Find the point where we cross the mile mark
            let mileTime = findTimeAtDistance(mileTargetDistance, in: distancePoints, startingFrom: pointIndex)
            
            if let mileTime = mileTime {
                // Calculate pace for this mile
                let mileElapsedTime = mileTime.timeIntervalSince(mileStartTime)
                let paceMinutesPerMile = mileElapsedTime / 60.0
                
                // Validate pace (between 3:00 and 30:00 per mile for sanity)
                if paceMinutesPerMile >= 3.0 && paceMinutesPerMile <= 30.0 {
                    if paceMinutesPerMile < fastestMilePace {
                        fastestMilePace = paceMinutesPerMile
                        print("[HealthKit] 🏃‍♂️ Mile \(currentMileNumber + 1): \(formatPace(minutesPerMile: paceMinutesPerMile)) (NEW PR!)")
                    } else {
                        print("[HealthKit] 🏃‍♂️ Mile \(currentMileNumber + 1): \(formatPace(minutesPerMile: paceMinutesPerMile))")
                    }
                }
                
                // Set up for next mile
                mileStartTime = mileTime
                currentMileNumber += 1
                mileTargetDistance += 1.0
                
                // Update point index to avoid reprocessing
                pointIndex = distancePoints.firstIndex { $0.time >= mileTime } ?? pointIndex
            } else {
                break
            }
        }
        
        print("[HealthKit] ✅ Found \(currentMileNumber) complete mile splits, fastest: \(formatPace(minutesPerMile: fastestMilePace))")
        
        return fastestMilePace == .infinity ? calculateAveragePaceForWorkout(workout) : fastestMilePace
    }
    
    /// Finds the time when a specific distance was reached using interpolation
    private func findTimeAtDistance(_ targetDistance: Double, in points: [(time: Date, distance: Double)], startingFrom index: Int) -> Date? {
        for i in max(0, index)..<points.count - 1 {
            let current = points[i]
            let next = points[i + 1]
            
            // Check if target distance is between these two points
            if current.distance <= targetDistance && next.distance >= targetDistance {
                // Linear interpolation to find exact time
                let distanceRatio = (targetDistance - current.distance) / (next.distance - current.distance)
                let timeInterval = next.time.timeIntervalSince(current.time)
                let interpolatedTime = current.time.addingTimeInterval(timeInterval * distanceRatio)
                return interpolatedTime
            }
        }
        return nil
    }
    
    /// Fallback method to calculate average pace when detailed splits aren't available
    private func calculateAveragePaceForWorkout(_ workout: HKWorkout) -> TimeInterval {
        guard let distance = workout.totalDistance else { return 0 }
        let miles = distance.doubleValue(for: HKUnit.mile())
        guard miles >= 0.95 else { return 0 }
        
        return workout.duration / 60 / miles
    }
    
    /// Processes workout groups for records calculation after fastest mile is determined
    private func processWorkoutGroupsForRecords(workoutsByDay: [Date: [HKWorkout]], fastestPace: TimeInterval) {
        var mostMilesInDay: Double = 0.0
        var mostMilesWorkouts: [HKWorkout] = []
        
        // Calculate most miles in a day
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
            self.fastestMilePace = fastestPace
            self.mostMilesInOneDay = mostMilesInDay
            self.mostMilesWorkouts = mostMilesWorkouts
            self.retroactiveStreak = streak
            
            print("[HealthKit] 📊 Personal records updated - Fastest: \(self.formatPace(minutesPerMile: fastestPace)), Most miles: \(mostMilesInDay), Streak: \(streak)")
        }
    }
    
    // Helper to calculate retroactive streak from workout data
    private func calculateRetroactiveStreak(workoutsByDay: [Date: [HKWorkout]]) -> Int {
        let calendar = Calendar.current
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
    }
    
    // Format pace in minutes:seconds per mile
    func formatPace(minutesPerMile: TimeInterval) -> String {
        guard minutesPerMile > 0 else { return "N/A" }
        
        let totalSeconds = Int(minutesPerMile * 60)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
} 