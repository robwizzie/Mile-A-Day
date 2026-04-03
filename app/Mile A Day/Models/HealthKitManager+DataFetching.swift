import Foundation
import HealthKit

extension HealthKitManager {

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
    func performInitialWorkoutFetch() {
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
    func fetchWorkoutsSmartly() {
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

            // Update cached workout data and recalculate stats on main thread
            // (cachedWorkouts is @Published so all mutations must happen on main)
            DispatchQueue.main.async {
                self.updateCachedWorkoutData(with: newWorkouts)
                self.recalculateStatsWithAllWorkouts()
            }
        }

        healthStore.execute(query)
    }

    /// Updates cached workout data with new workouts
    /// Automatically deduplicates based on workout UUID
    /// Updates cached workout data with new workouts
    /// Must be called on the main thread (cachedWorkouts is @Published)
    func updateCachedWorkoutData(with newWorkouts: [HKWorkout]) {
        var addedCount = 0
        var duplicateCount = 0

        for workout in newWorkouts {
            if !cachedWorkoutUUIDs.contains(workout.uuid) {
                cachedWorkouts.append(workout)
                cachedWorkoutUUIDs.insert(workout.uuid)
                addedCount += 1
            } else {
                duplicateCount += 1
            }
        }

        if let latestWorkout = newWorkouts.max(by: { $0.endDate < $1.endDate }) {
            if let currentLatest = cachedLatestWorkoutDate {
                cachedLatestWorkoutDate = max(currentLatest, latestWorkout.endDate)
            } else {
                cachedLatestWorkoutDate = latestWorkout.endDate
            }
        }

        cachedWorkoutCount = cachedWorkouts.count

        log("[HealthKit] Updated cached workout data - Added: \(addedCount), Duplicates skipped: \(duplicateCount), Total: \(cachedWorkoutCount)")
    }

    /// Recalculates all stats using cached + new workouts
    func recalculateStatsWithAllWorkouts() {

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

            // Merge with existing dailyMileGoals (preserve days outside this month's query range,
            // e.g. Sunday of the current week when it falls in the previous month)
            DispatchQueue.main.async {
                var merged = self.dailyMileGoals
                for (date, goalReached) in dailyMileGoals {
                    merged[date] = goalReached
                }
                self.dailyMileGoals = merged
                self.log("[HealthKit] 📅 Calendar updated with \(merged.filter { $0.value }.count) qualifying days")
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

    // Update calendar data with timezone-corrected workout grouping
    func updateCalendarWithTimezoneCorrectedData(correctedWorkoutsByDay: [Date: [HKWorkout]]) {

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

    /// CRITICAL METHOD: Groups workouts by day using timezone awareness with corrections
    /// This ensures calendar and streak use the SAME logic for consistency
    /// Applies timezone corrections for workouts done in different timezones
    func groupWorkoutsWithTimezoneAwareness(workouts: [HKWorkout]) -> [Date: [HKWorkout]] {
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
}
