import Foundation
import HealthKit
import CoreLocation
import UIKit

/// A finished in-app walk that HealthKit has not yet confirmed saving.
///
/// The tracker's finish chain is the ONLY thing that turns a tracked walk into
/// an `HKWorkout`, and every number the app and the server count reads
/// HKWorkouts back. When that chain failed (no builder, a HealthKit error) or
/// simply ran out the 10s safety timeout — a long walk on a main thread busy
/// re-encoding its route was enough — `InProgressWorkoutStore` was already
/// cleared, so the walk existed nowhere. The user got a toast promising it
/// would "sync on your next update" and the mile never counted, because there
/// was nothing left to sync.
///
/// Now the finish STAGES the walk here, synchronously, before the async save
/// starts, and resolves it only when HealthKit hands back a workout. Anything
/// still staged is re-saved (backdated — `HKWorkoutBuilder` accepts a past
/// start) by `PendingWorkoutSaver.retryIfNeeded()` on the next foreground or
/// unlocked background wake. Every save — first attempt and retry alike —
/// stamps `sessionMetadataKey`, and a retry probes HealthKit for it first, so a
/// first attempt that landed AFTER its timeout can never be saved twice.
struct PendingWorkoutSave: Codable {
    /// `InProgressWorkoutState.workoutUUID` — the walk's identity across tries.
    let sessionId: String
    let startDate: Date
    let endDate: Date
    let distanceMiles: Double
    /// `HKWorkoutActivityType.rawValue`.
    let activityTypeRaw: UInt
    /// `HKWorkoutSessionLocationType.rawValue`.
    let locationTypeRaw: Int
    /// Pause-excluded seconds, for the energy estimate.
    let activeSeconds: TimeInterval
    let movingSeconds: Double?
    let pauseIntervals: [WorkoutPauseInterval]
    let stealth: Bool
    /// Already cleaned (`WorkoutRouteCleanup.cleaned`) by the finish.
    let routePoints: [WorkoutRoutePoint]
    let stagedAt: Date
    /// Optional for the persisted-Codable reason (ios.md).
    var attempts: Int?

    /// Metadata key carrying `sessionId` on the saved `HKWorkout`.
    static let sessionMetadataKey = "MAD_tracked_session"
}

/// Disk-backed list of staged walks. A file rather than UserDefaults because a
/// long walk's route is ~1 MB of JSON. Encoded with the DEFAULT date strategy
/// (a Double) on purpose: `.iso8601` drops fractional seconds, two route points
/// inside one second come back equal, and `insertRouteData` rejects the batch.
enum PendingWorkoutSaveStore {
    private static let queue = DispatchQueue(label: "mad.pending-workout-saves")

    private static var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("PendingWorkoutSaves.json")
    }

    static func all() -> [PendingWorkoutSave] {
        queue.sync { readUnlocked() }
    }

    /// Synchronous on purpose: the finish calls this before handing off to
    /// HealthKit, and it must be on disk before anything can kill the process.
    static func stage(_ save: PendingWorkoutSave) {
        queue.sync {
            var saves = readUnlocked().filter { $0.sessionId != save.sessionId }
            saves.append(save)
            writeUnlocked(saves)
        }
    }

    static func resolve(sessionId: String) {
        queue.sync {
            let saves = readUnlocked()
            let remaining = saves.filter { $0.sessionId != sessionId }
            if remaining.count != saves.count { writeUnlocked(remaining) }
        }
    }

    static func update(_ save: PendingWorkoutSave) {
        queue.sync {
            var saves = readUnlocked()
            guard let index = saves.firstIndex(where: { $0.sessionId == save.sessionId }) else { return }
            saves[index] = save
            writeUnlocked(saves)
        }
    }

    private static func readUnlocked() -> [PendingWorkoutSave] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PendingWorkoutSave].self, from: data)) ?? []
    }

    private static func writeUnlocked(_ saves: [PendingWorkoutSave]) {
        guard let url = fileURL else { return }
        if saves.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(saves) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Re-saves staged walks into HealthKit. See `PendingWorkoutSave`.
@MainActor
final class PendingWorkoutSaver {
    static let shared = PendingWorkoutSaver()

    /// A staged walk younger than this may still be mid-way through its FIRST
    /// save (the finish holds a background task for it), so it is left alone.
    private static let minimumAge: TimeInterval = 60
    /// HealthKit keeps refusing (Workouts write access off, say): stop trying
    /// eventually, but only after weeks — this is somebody's walk.
    private static let maximumAge: TimeInterval = 30 * 24 * 60 * 60

    private var isRetrying = false
    private var healthManager: HealthKitManager { HealthKitManager.shared }
    private var healthStore: HKHealthStore { HealthKitManager.shared.healthStore }

    private init() {}

    var hasPending: Bool { !PendingWorkoutSaveStore.all().isEmpty }

    /// Re-saves every staged walk old enough to be orphaned. Safe to call
    /// freely (foreground, background wakes): it no-ops while locked, while a
    /// pass is running, and when nothing is staged.
    func retryIfNeeded() async {
        guard !isRetrying else { return }
        let now = Date()
        let due = PendingWorkoutSaveStore.all().filter { now.timeIntervalSince($0.stagedAt) >= Self.minimumAge }
        guard !due.isEmpty else { return }
        // HealthKit's store is protected while the device is locked; a write
        // attempt there only burns an attempt.
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }

        isRetrying = true
        defer { isRetrying = false }

        var savedAny = false
        for save in due {
            if now.timeIntervalSince(save.stagedAt) > Self.maximumAge {
                print("[PendingWorkoutSaver] ⚠️ Giving up on walk \(save.sessionId) staged \(save.stagedAt) after \(save.attempts ?? 0) attempts")
                PendingWorkoutSaveStore.resolve(sessionId: save.sessionId)
                continue
            }
            if await attempt(save) {
                savedAny = true
            } else {
                var failed = save
                failed.attempts = (save.attempts ?? 0) + 1
                PendingWorkoutSaveStore.update(failed)
            }
        }

        if savedAny {
            healthManager.invalidateWorkoutCacheFreshness()
            healthManager.fetchAllWorkoutData()
            healthManager.fetchTodaysDistance()
        }
    }

    // MARK: - One walk

    private func attempt(_ save: PendingWorkoutSave) async -> Bool {
        // Authorization resolves per process; a cold background launch starts
        // with the manager's flag false no matter what was granted. Resolved
        // WITHOUT prompting — a background wake has no UI to prompt on, and a
        // walk the user already granted access for needs no sheet.
        if !healthManager.isAuthorized {
            let authorized = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                healthManager.refreshAuthorizationStatus { continuation.resume(returning: $0) }
            }
            guard authorized else { return false }
        }

        // The first attempt may have landed after its timeout: never save twice.
        if let existing = await existingWorkout(for: save) {
            print("[PendingWorkoutSaver] Walk \(save.sessionId) is already in HealthKit — resolving")
            await landed(existing, save: save)
            return true
        }

        guard let workout = await saveWorkout(save) else { return false }
        print("[PendingWorkoutSaver] ✅ Re-saved walk \(save.sessionId): \(String(format: "%.2f", save.distanceMiles)) mi")
        await landed(workout, save: save)
        return true
    }

    /// Receipt, route, upload — the same tail the tracker's own finish runs.
    private func landed(_ workout: HKWorkout, save: PendingWorkoutSave) async {
        TrackedWorkoutLedger.shared.record(workoutId: workout.uuid.uuidString, miles: save.distanceMiles)
        PendingWorkoutSaveStore.resolve(sessionId: save.sessionId)
        if save.routePoints.count >= 2 {
            await attachRoute(save, to: workout)
        }
        await WorkoutSyncService.shared.uploadWorkout(withId: workout.uuid)
    }

    private func existingWorkout(for save: PendingWorkoutSave) async -> HKWorkout? {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: PendingWorkoutSave.sessionMetadataKey,
            allowedValues: [save.sessionId]
        )
        return await withCheckedContinuation { (continuation: CheckedContinuation<HKWorkout?, Never>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout])?.first)
            }
            healthStore.execute(query)
        }
    }

    private func saveWorkout(_ save: PendingWorkoutSave) async -> HKWorkout? {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = HKWorkoutActivityType(rawValue: save.activityTypeRaw) ?? .walking
        configuration.locationType = HKWorkoutSessionLocationType(rawValue: save.locationTypeRaw) ?? .unknown
        // The app's ONE long-lived store — a scoped `HKHealthStore()` is
        // released before HealthKit answers and the save silently never lands.
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())

        let began = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            builder.beginCollection(withStart: save.startDate) { ok, error in
                if let error { print("[PendingWorkoutSaver] beginCollection failed: \(error)") }
                continuation.resume(returning: ok)
            }
        }
        guard began else { return nil }

        // Distance + estimated energy in ONE batch, exactly as the tracker
        // does (see its finish): `add` is all-or-nothing, so a sample for a
        // denied type is never included.
        let meters = save.distanceMiles / 0.000621371
        var samples: [HKSample] = []
        if save.distanceMiles > 0,
           let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            samples.append(HKQuantitySample(
                type: distanceType,
                quantity: HKQuantity(unit: .meter(), doubleValue: meters),
                start: save.startDate,
                end: save.endDate
            ))
        }
        if !healthManager.isActiveEnergySharingDenied(),
           let energy = WorkoutEnergyEstimate.sample(
               meters: meters,
               activeSeconds: save.activeSeconds,
               bodyMassKilograms: nil,
               start: save.startDate,
               end: save.endDate
           ) {
            samples.append(energy)
        }
        if !samples.isEmpty {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                builder.add(samples) { added, error in
                    if !added { print("[PendingWorkoutSaver] ⚠️ Sample batch rejected: \(String(describing: error)) — the ledger still carries the distance") }
                    continuation.resume()
                }
            }
        }

        let events = Self.pauseEvents(save)
        if !events.isEmpty {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                builder.addWorkoutEvents(events) { _, _ in continuation.resume() }
            }
        }

        var metadata: [String: Any] = [
            PendingWorkoutSave.sessionMetadataKey: save.sessionId,
            HKMetadataKeyIndoorWorkout: save.locationTypeRaw == HKWorkoutSessionLocationType.indoor.rawValue
        ]
        if let moving = save.movingSeconds, moving > 0 {
            metadata[WorkoutLocationManager.movingSecondsMetadataKey] = moving
        }
        if save.stealth {
            metadata[StealthModeStore.metadataKey] = true
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            builder.addMetadata(metadata) { _, _ in continuation.resume() }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            builder.endCollection(withEnd: save.endDate) { _, error in
                if let error { print("[PendingWorkoutSaver] endCollection failed: \(error)") }
                continuation.resume()
            }
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<HKWorkout?, Never>) in
            builder.finishWorkout { workout, error in
                if let error { print("[PendingWorkoutSaver] finishWorkout failed: \(error)") }
                continuation.resume(returning: workout)
            }
        }
    }

    private func attachRoute(_ save: PendingWorkoutSave, to workout: HKWorkout) async {
        let locations = WorkoutRouteCleanup.strictlyAscending(save.routePoints.map { $0.toCLLocation() })
        guard locations.count >= 2 else { return }
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        let inserted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            routeBuilder.insertRouteData(locations) { ok, error in
                if !ok { print("[PendingWorkoutSaver] ⚠️ Route insert failed: \(String(describing: error))") }
                continuation.resume(returning: ok)
            }
        }
        guard inserted else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            routeBuilder.finishRoute(with: workout, metadata: nil) { route, error in
                if route == nil { print("[PendingWorkoutSaver] ⚠️ Route finish failed: \(String(describing: error))") }
                continuation.resume()
            }
        }
    }

    /// Same construction as the tracker's finish: each pause clamped into the
    /// workout's window, an open one closed at the end.
    private static func pauseEvents(_ save: PendingWorkoutSave) -> [HKWorkoutEvent] {
        var events: [HKWorkoutEvent] = []
        for interval in save.pauseIntervals {
            let pauseStart = min(max(interval.start, save.startDate), save.endDate)
            let pauseEnd = min(max(interval.end ?? save.endDate, pauseStart), save.endDate)
            guard pauseEnd > pauseStart else { continue }
            events.append(HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: pauseStart, duration: 0), metadata: nil))
            events.append(HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: pauseEnd, duration: 0), metadata: nil))
        }
        return events
    }
}
