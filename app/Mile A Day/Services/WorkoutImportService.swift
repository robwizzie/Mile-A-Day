import CoreLocation
import Foundation
import HealthKit

/// Import keys already written to Apple Health by a previous import.
///
/// Re-importing the same archive must be a no-op. Without this, a second import
/// writes a second copy of every run — and because both copies carry Mile A
/// Day's OWN bundle id, the server's cross-app duplicate detection can't see
/// them either (it only ever pairs workouts from *different* apps, by design,
/// since two workouts from one app are a legitimate double session). So local
/// idempotence is the only thing standing between a double-tap and doubled
/// lifetime miles.
struct ImportedWorkoutRegistry {
    private static let key = "com.mileaday.importedWorkoutKeys"

    static func mark(_ importKey: String) {
        var keys = all
        keys.insert(importKey)
        UserDefaults.standard.set(Array(keys), forKey: key)
    }

    static func markAll(_ importKeys: [String]) {
        var keys = all
        keys.formUnion(importKeys)
        UserDefaults.standard.set(Array(keys), forKey: key)
    }

    static func contains(_ importKey: String) -> Bool { all.contains(importKey) }

    static var all: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
}

/// Writes workouts recovered from a platform export into Apple Health.
///
/// **Why HealthKit and not straight to our backend:** the app's own streak is
/// computed locally from HealthKit (`WorkoutIndex`, `retroactiveStreak`), and
/// `UserManager.vettedHealthKitStreak` quarantines disagreement between the
/// local and server streaks. History that reached only the server would put the
/// app permanently in that "backend streak ≫ local" repair state. Writing real
/// backdated `HKWorkout`s instead means the existing pipeline — index, sync,
/// dedup, streak — picks them up with no special cases anywhere, and the user's
/// other apps get their history back too.
@Observable
final class WorkoutImportService {
    struct Progress: Equatable {
        var written: Int
        var total: Int
        var skippedAlreadyImported: Int
        var failed: Int

        var fraction: Double {
            total > 0 ? Double(written + failed) / Double(total) : 0
        }
    }

    enum State: Equatable {
        case idle
        case importing(Progress)
        case finished(Progress)
        case failed(String)
    }

    private(set) var state: State = .idle

    /// Stamped on every workout this app imports, so a re-import can be detected
    /// from HealthKit itself after the local registry is gone (reinstall, new
    /// device restored from a backup that didn't carry UserDefaults).
    static let importKeyMetadata = "MAD_import_key"
    static let importSourceMetadata = "MAD_import_source"

    private let healthStore = HealthKitManager.shared.healthStore

    /// Everything in `workouts` that hasn't already been imported.
    ///
    /// Checks the local registry first (cheap) and then HealthKit itself, so a
    /// user who reinstalled still can't double-import.
    func filterAlreadyImported(_ workouts: [ImportableWorkout]) async -> [ImportableWorkout] {
        let registry = ImportedWorkoutRegistry.all
        let candidates = workouts.filter { !registry.contains($0.id) }
        guard !candidates.isEmpty else { return [] }

        guard
            let earliest = candidates.map({ $0.start }).min(),
            let latest = candidates.map({ $0.end }).max()
        else { return candidates }

        let alreadyInHealth = await importKeysInHealthKit(from: earliest, to: latest)
        guard !alreadyInHealth.isEmpty else { return candidates }

        // Anything HealthKit already knows about is also folded back into the
        // registry, so the expensive probe isn't repeated next time.
        ImportedWorkoutRegistry.markAll(Array(alreadyInHealth))
        return candidates.filter { !alreadyInHealth.contains($0.id) }
    }

    /// Import keys this app previously wrote into HealthKit over a date range.
    private func importKeysInHealthKit(from start: Date, to end: Date) async -> Set<String> {
        let datePredicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: [])

        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: datePredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                // A failed probe returns empty, which only means "re-check the
                // registry" — the registry is still authoritative, so this can
                // never cause a double write on its own.
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }

        return Set(
            workouts.compactMap { $0.metadata?[Self.importKeyMetadata] as? String }
        )
    }

    /// Write the given workouts into Apple Health, reporting progress.
    ///
    /// Sequential on purpose: `HKWorkoutBuilder` is a multi-step async handshake
    /// per workout, and a few thousand of them in flight at once is a good way
    /// to get throttled. Slow and steady with a visible progress bar beats fast
    /// and half-written.
    @MainActor
    func run(_ workouts: [ImportableWorkout], platform: String) async {
        var progress = Progress(
            written: 0, total: workouts.count, skippedAlreadyImported: 0, failed: 0)
        state = .importing(progress)

        for workout in workouts {
            do {
                try await write(workout, platform: platform)
                ImportedWorkoutRegistry.mark(workout.id)
                progress.written += 1
            } catch {
                // One bad workout never aborts the rest of someone's history.
                progress.failed += 1
            }
            state = .importing(progress)
        }

        state = .finished(progress)
    }

    /// One workout, written through the same `HKWorkoutBuilder` chain the live
    /// tracker uses (`WorkoutTrackingView`, ~line 2322) — begin → add distance →
    /// metadata → end → finish → attach route. The only difference is that the
    /// dates are historical.
    ///
    /// Completion-handler APIs wrapped in continuations rather than the async
    /// variants, to stay on exactly the signatures the tracker already proves.
    private func write(_ workout: ImportableWorkout, platform: String) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workout.activityType.hkActivityType
        configuration.locationType = workout.route.isEmpty ? .unknown : .outdoor

        let builder = HKWorkoutBuilder(
            healthStore: healthStore, configuration: configuration, device: .local())

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            builder.beginCollection(withStart: workout.start) { _, error in
                if let error { continuation.resume(throwing: error) } else {
                    continuation.resume()
                }
            }
        }

        if workout.miles > 0 {
            let meters = workout.miles * WorkoutArchiveParser.metersPerMile
            let sample = HKQuantitySample(
                type: HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
                quantity: HKQuantity(unit: HKUnit.meter(), doubleValue: meters),
                start: workout.start,
                end: workout.end
            )
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                builder.add([sample]) { _, error in
                    if let error { continuation.resume(throwing: error) } else {
                        continuation.resume()
                    }
                }
            }
        }

        // NOT HKMetadataKeyWasUserEntered: that flag makes the app classify a
        // workout as hand-logged (see WorkoutRecord's init in WorkoutIndex),
        // and an imported run is a real recorded activity, not a manual entry.
        let metadata: [String: Any] = [
            Self.importKeyMetadata: workout.id,
            Self.importSourceMetadata: platform,
            HKMetadataKeyWorkoutBrandName: platform,
        ]
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            builder.addMetadata(metadata) { _, _ in continuation.resume() }
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            builder.endCollection(withEnd: workout.end) { _, error in
                if let error { continuation.resume(throwing: error) } else {
                    continuation.resume()
                }
            }
        }

        let saved: HKWorkout? = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<HKWorkout?, Error>) in
            builder.finishWorkout { finished, error in
                if let error { continuation.resume(throwing: error) } else {
                    continuation.resume(returning: finished)
                }
            }
        }
        guard let saved else { throw ImportError.saveFailed }

        // The GPS trace, when the archive carried one. Same ordering rule the
        // tracker follows: the route is attached AFTER the workout exists.
        // Best-effort — a missing map is never worth losing the workout.
        if !workout.route.isEmpty {
            await attachRoute(workout.route, to: saved)
        }
    }

    private func attachRoute(_ points: [ImportedRoutePoint], to workout: HKWorkout) async {
        let locations = points.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        guard !locations.isEmpty else { return }

        let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            routeBuilder.insertRouteData(locations) { inserted, _ in
                guard inserted else {
                    continuation.resume()
                    return
                }
                routeBuilder.finishRoute(with: workout, metadata: nil) { _, _ in
                    continuation.resume()
                }
            }
        }
    }

    enum ImportError: LocalizedError {
        case saveFailed
        var errorDescription: String? { "Couldn't save the workout to Apple Health." }
    }
}
