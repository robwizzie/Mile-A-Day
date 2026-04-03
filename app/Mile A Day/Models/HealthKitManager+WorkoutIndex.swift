import Foundation
import HealthKit

extension HealthKitManager {

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

            if !self.hasIndexOrStreakLoaded {
                self.hasIndexOrStreakLoaded = true
                self.checkInitialDataReady()
            }
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
            // Still populate dailyMileGoals from the cached index so the
            // streak week-dots render correctly (the index was loaded from
            // disk at init, but dailyMileGoals is not persisted).
            await MainActor.run {
                var goals: [Date: Bool] = [:]
                for (dateKey, records) in currentIndex.workoutsByDate {
                    if let date = dateFromKey(dateKey) {
                        let totalMiles = records.reduce(0) { $0 + $1.distance }
                        goals[date] = totalMiles >= 0.95
                    }
                }
                self.dailyMileGoals = goals
            }
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

            if !self.hasIndexOrStreakLoaded {
                self.hasIndexOrStreakLoaded = true
                self.checkInitialDataReady()
            }
        }
    }
    #endif

    // MARK: - Workout Lookup Methods

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
    func fetchWorkoutsByUUIDs(_ uuids: [UUID], completion: @escaping ([HKWorkout]) -> Void) {
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
    func getWorkoutsForDateRange(start: Date, end: Date, completion: @escaping ([HKWorkout]) -> Void) {
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
    func getAllWorkouts(completion: @escaping ([HKWorkout]) -> Void) {
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

    // MARK: - Helper Methods for Index

    #if !os(watchOS)
    func dateKey(from date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                     components.year ?? 0,
                     components.month ?? 0,
                     components.day ?? 0)
    }

    func dateFromKey(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: key)
    }
    #endif
}
