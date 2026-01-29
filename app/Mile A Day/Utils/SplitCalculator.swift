import Foundation
import HealthKit

/// Shared utility for calculating mile splits from HealthKit distance samples.
/// Filters out bad data (negative distance, inhumane pace) and uses
/// timestamp-based durations anchored to the workout start time.
enum SplitCalculator {

    /// Maximum human running speed in meters per second (~2:00/mile, faster than Usain Bolt's 100m average).
    private static let maxHumanSpeed = 13.4

    /// One mile in meters.
    private static let mileInMeters = 1609.34

    /// Calculate mile splits for a workout from its HealthKit distance samples.
    /// Returns `WorkoutSplit` objects with splitNumber, distance, duration, and pace.
    static func calculateSplits(for workout: HKWorkout) async -> [WorkoutSplit] {
        guard HKHealthStore.isHealthDataAvailable(),
              let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        else {
            return []
        }

        let samples = await fetchDistanceSamples(for: workout, distanceType: distanceType)

        guard !samples.isEmpty else {
            return []
        }

        // Filter out bad samples: negative distance or inhumane pace
        let validSamples = samples.filter { sample in
            let dist = sample.quantity.doubleValue(for: HKUnit.meter())
            let dur = sample.endDate.timeIntervalSince(sample.startDate)
            guard dist > 0, dur > 0 else { return false }
            return (dist / dur) <= maxHumanSpeed
        }

        guard !validSamples.isEmpty else {
            return []
        }

        let filteredCount = samples.count - validSamples.count
        if filteredCount > 0 {
            print("[SplitCalculator] Filtered out \(filteredCount) bad sample(s)")
        }

        // Use timestamp-based durations anchored to workout start
        var splits: [WorkoutSplit] = []
        var cumulativeDistance = 0.0
        var currentSplitDuration = 0.0
        var previousEndDate = workout.startDate

        for sample in validSamples {
            let sampleDistance = sample.quantity.doubleValue(for: HKUnit.meter())
            let sampleDuration = sample.endDate.timeIntervalSince(previousEndDate)
            cumulativeDistance += sampleDistance
            previousEndDate = sample.endDate

            var remainingDuration = sampleDuration

            // Handle samples that cross one or more mile boundaries
            while cumulativeDistance >= Double(splits.count + 1) * mileInMeters {
                let nextFullMile = Double(splits.count + 1) * mileInMeters
                let extraMeters = cumulativeDistance - nextFullMile
                let overflowRatio = sampleDistance > 0 ? extraMeters / sampleDistance : 0
                let durationForThisMile = remainingDuration - (sampleDuration * overflowRatio)
                currentSplitDuration += durationForThisMile
                remainingDuration = sampleDuration * overflowRatio

                splits.append(WorkoutSplit(
                    splitNumber: splits.count + 1,
                    distance: 1.0,
                    duration: currentSplitDuration,
                    pace: currentSplitDuration
                ))

                currentSplitDuration = 0
            }

            currentSplitDuration += remainingDuration
        }

        // Add incomplete final split if there's remaining time
        if currentSplitDuration > 0 {
            let remainingMeters = cumulativeDistance.truncatingRemainder(dividingBy: mileInMeters)
            let distanceInMiles = remainingMeters / mileInMeters
            let pace = distanceInMiles > 0 ? (mileInMeters / remainingMeters) * currentSplitDuration : 0

            splits.append(WorkoutSplit(
                splitNumber: splits.count + 1,
                distance: distanceInMiles,
                duration: currentSplitDuration,
                pace: pace
            ))
        }

        return splits
    }

    // MARK: - Private

    private static func fetchDistanceSamples(
        for workout: HKWorkout,
        distanceType: HKQuantityType
    ) async -> [HKQuantitySample] {
        await withCheckedContinuation { continuation in
            let healthStore = HKHealthStore()
            let predicate = HKQuery.predicateForObjects(from: workout)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

            let query = HKSampleQuery(
                sampleType: distanceType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error = error {
                    print("[SplitCalculator] Error fetching distance samples: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }

            healthStore.execute(query)
        }
    }
}
