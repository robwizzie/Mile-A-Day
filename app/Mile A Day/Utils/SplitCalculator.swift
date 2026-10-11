import CoreLocation
import Foundation
import HealthKit

/// Shared utility for calculating mile splits from HealthKit distance samples.
/// Filters out bad data (negative distance, inhumane pace) and uses
/// timestamp-based durations anchored to the workout start time. Workouts
/// whose distance is one long sample (our own tracker's) are timed from their
/// GPS route instead — see `splitsFromRoute`.
enum SplitCalculator {

    /// Maximum human running speed in meters per second (~2:00/mile, faster than Usain Bolt's 100m average).
    private static let maxHumanSpeed = 13.4

    /// One mile in meters.
    private static let mileInMeters = 1609.34

    /// ONE long-lived store for every split query.
    ///
    /// This used to be a fresh `HKHealthStore()` per workout. HealthKit
    /// requires the store to outlive the query executed on it, and a local one
    /// is released the instant `fetchDistanceSamples` returns — the same
    /// dropped-store trap that makes a workout save with no route (ios.md).
    /// It is also allocated once per workout, which during a historical import
    /// means thousands of stores in a few minutes.
    private static let healthStore = HKHealthStore()

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

        // A sample this long says nothing about pace INSIDE it: the loop below
        // spreads its time evenly, so every mile it covers comes out at the
        // workout's average pace. Our own tracker saves a whole walk as ONE
        // sample, which made every in-app walk's splits identical. Walk the
        // GPS route's clock instead; with no usable route, a whole mile inside
        // one sample is invented, so say nothing rather than show it.
        let longestMeters = validSamples
            .map { $0.quantity.doubleValue(for: HKUnit.meter()) }
            .max() ?? 0
        if longestMeters > mileInMeters / 2 {
            let route = await fetchRouteLocations(for: workout)
            if let routeSplits = splitsFromRoute(route, workout: workout) {
                return routeSplits
            }
            if longestMeters >= mileInMeters { return [] }
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

    // MARK: - Route splits

    /// Mile splits from the route's own timestamps, for a workout whose
    /// distance samples are too coarse to time a mile.
    ///
    /// Ground comes from the GPS trace, then is scaled to the workout's
    /// recorded distance (`madDistanceMiles`) so mile N here is the same mile N
    /// every other surface counts. Pause gaps (`RouteGaps`) and steps taken
    /// while paused add no ground, and paused time comes off each split's
    /// clock. Nil when the trace can't vouch for the distance.
    static func splitsFromRoute(_ locations: [CLLocation], workout: HKWorkout) -> [WorkoutSplit]? {
        guard locations.count >= 2 else { return nil }
        let officialMeters = workout.madDistanceMiles * mileInMeters
        guard officialMeters > 0 else { return nil }

        let paused = pausedIntervals(of: workout)
        let breaks = RouteGaps.breakIndices(
            coordinates: locations.map(\.coordinate),
            times: locations.map { $0.timestamp.timeIntervalSince1970 }
        )
        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(locations.count)
        for i in 1..<locations.count {
            let a = locations[i - 1], b = locations[i]
            let mid = a.timestamp.addingTimeInterval(b.timestamp.timeIntervalSince(a.timestamp) / 2)
            let walked = !breaks.contains(i - 1) && !paused.contains { $0.contains(mid) }
            cumulative.append(cumulative[i - 1] + (walked ? b.distance(from: a) : 0))
        }

        // A trace far off the recorded distance (GPS starved, or a stray
        // route) would put the mile marks in the wrong places.
        guard let gpsMeters = cumulative.last, gpsMeters > 0 else { return nil }
        let scale = officialMeters / gpsMeters
        guard scale >= 0.5, scale <= 2 else { return nil }

        func activeSeconds(from start: Date, to end: Date) -> TimeInterval {
            guard end > start else { return 0 }
            let window = DateInterval(start: start, end: end)
            let pausedInside = paused.reduce(0.0) { total, pause in
                total + (window.intersection(with: pause)?.duration ?? 0)
            }
            return max(0, window.duration - pausedInside)
        }

        var splits: [WorkoutSplit] = []
        var splitStart = workout.startDate
        for i in 1..<locations.count {
            let d0 = cumulative[i - 1] * scale
            let d1 = cumulative[i] * scale
            while d1 >= Double(splits.count + 1) * mileInMeters {
                let mark = Double(splits.count + 1) * mileInMeters
                let fraction = d1 > d0 ? (mark - d0) / (d1 - d0) : 1
                let t0 = locations[i - 1].timestamp
                let crossedAt = t0.addingTimeInterval(
                    locations[i].timestamp.timeIntervalSince(t0) * fraction
                )
                let seconds = activeSeconds(from: splitStart, to: crossedAt)
                splits.append(WorkoutSplit(
                    splitNumber: splits.count + 1,
                    distance: 1.0,
                    duration: seconds,
                    pace: seconds
                ))
                splitStart = crossedAt
            }
        }

        // The partial last mile runs to the workout's end. Under ~50 ft it is
        // standing at the finish, and a pace over it would be nonsense.
        let remainingMeters = officialMeters - Double(splits.count) * mileInMeters
        let remainingSeconds = activeSeconds(from: splitStart, to: workout.endDate)
        if remainingMeters >= 16, remainingSeconds > 0 {
            splits.append(WorkoutSplit(
                splitNumber: splits.count + 1,
                distance: remainingMeters / mileInMeters,
                duration: remainingSeconds,
                pace: remainingSeconds * mileInMeters / remainingMeters
            ))
        }

        return splits.isEmpty ? nil : splits
    }

    /// Paused stretches from the workout's pause/resume events (our tracker
    /// writes `.pause`/`.resume`; a Watch auto-pause writes the motion pair).
    /// A pause never resumed runs to the workout's end.
    static func pausedIntervals(of workout: HKWorkout) -> [DateInterval] {
        guard let events = workout.workoutEvents, !events.isEmpty else { return [] }
        var out: [DateInterval] = []
        var pausedAt: Date?
        for event in events.sorted(by: { $0.dateInterval.start < $1.dateInterval.start }) {
            switch event.type {
            case .pause, .motionPaused:
                if pausedAt == nil { pausedAt = event.dateInterval.start }
            case .resume, .motionResumed:
                if let start = pausedAt {
                    out.append(DateInterval(start: start, end: max(start, event.dateInterval.start)))
                    pausedAt = nil
                }
            default:
                break
            }
        }
        if let start = pausedAt, start < workout.endDate {
            out.append(DateInterval(start: start, end: workout.endDate))
        }
        return out
    }

    // MARK: - Private

    /// Every location in the workout's route(s), oldest first; empty when it
    /// has none (indoor, no GPS, or route sharing off).
    private static func fetchRouteLocations(for workout: HKWorkout) async -> [CLLocation] {
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: HKSeriesType.workoutRoute(),
                predicate: HKQuery.predicateForObjects(from: workout),
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, _, _ in
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            healthStore.execute(query)
        }

        var locations: [CLLocation] = []
        for route in routes {
            let batch: [CLLocation] = await withCheckedContinuation { continuation in
                var accumulated: [CLLocation] = []
                var finished = false
                let query = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
                    guard !finished else { return }
                    if let batch { accumulated.append(contentsOf: batch) }
                    // An error ends the query without a `done` batch.
                    if done || error != nil {
                        finished = true
                        continuation.resume(returning: accumulated)
                    }
                }
                healthStore.execute(query)
            }
            locations.append(contentsOf: batch)
        }
        return locations.sorted { $0.timestamp < $1.timestamp }
    }

    private static func fetchDistanceSamples(
        for workout: HKWorkout,
        distanceType: HKQuantityType
    ) async -> [HKQuantitySample] {
        await withCheckedContinuation { continuation in
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
