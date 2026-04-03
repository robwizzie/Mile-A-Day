import Foundation
import HealthKit

extension HealthKitManager {

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
    func processWorkoutsByDay(_ workoutsByDay: [Date: [HKWorkout]], mostMilesInDay: Double, mostMilesWorkouts: [HKWorkout]) {
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

    /// Fetches workout splits using the shared SplitCalculator.
    /// Returns split times in minutes per mile (only full-mile splits), or nil if no splits available.
    func fetchWorkoutSplits(for workout: HKWorkout, completion: @escaping ([TimeInterval]?) -> Void) {
        Task {
            let splits = await SplitCalculator.calculateSplits(for: workout)
            // Convert WorkoutSplit pace (seconds/mile) to minutes/mile, only for full-mile splits
            let mileSplits: [TimeInterval] = splits
                .filter { $0.distance >= 1.0 }
                .map { $0.pace / 60.0 }
            completion(mileSplits.isEmpty ? nil : mileSplits)
        }
    }
}
