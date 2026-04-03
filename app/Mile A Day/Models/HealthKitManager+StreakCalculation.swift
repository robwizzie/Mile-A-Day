import Foundation
import HealthKit

extension HealthKitManager {

    // Helper to calculate retroactive streak from workout data with timezone awareness
    func calculateRetroactiveStreak(workoutsByDay: [Date: [HKWorkout]]) -> Int {
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

    func canUseCurrentStreakCache(streakDays: Int) -> Bool {
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

    func calculateSmartCurrentStreakFastestPace(streakWorkouts: [HKWorkout]) -> TimeInterval {
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

    func findWorkoutWithAllTimeFastestMile(in streakWorkouts: [HKWorkout]) -> HKWorkout? {
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

    func hasNewQualifyingWorkoutsSinceLastStreakCalculation(streakWorkouts: [HKWorkout]) -> Bool {
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

    func calculateFastestMileForWorkouts(_ workouts: [HKWorkout]) -> TimeInterval {
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
}
