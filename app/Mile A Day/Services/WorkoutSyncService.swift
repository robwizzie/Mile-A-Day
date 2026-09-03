//
//  WorkoutSyncService.swift
//  Mile A Day
//
//  Handles automatic batch syncing of workouts to the backend
//  Supports initial sync, incremental sync, and background sync
//

import Foundation
import HealthKit
import CoreLocation

// MARK: - Sync Progress Models

/// Represents the current state of a sync operation
enum SyncPhase: Equatable {
    case idle
    case fetchingFromHealthKit
    case uploadingToBackend
    case complete
    /// Human-readable copy, never a raw `localizedDescription`. What the user
    /// can DO about it lives in `SyncProgress.failure`.
    case error(String)
}

/// Why a sync stopped, in terms the UI can act on.
///
/// This exists because the raw error text was being shown verbatim, and
/// HealthKit's own wording is actively misleading: `HKError` code 4 localizes
/// to "Authorization not determined", which a user reads as "my permissions
/// are wrong" even when every switch in Health is green and data is flowing.
/// Apple never reports READ authorization (a denied read and an empty history
/// are the same empty array — see HealthAccessMonitor), so that string can
/// never be a diagnosis. It only ever means "we asked before the permission
/// sheet had been answered", which is a retry, not a settings trip.
enum SyncFailure: Equatable {
    /// HealthKit hasn't been asked yet (or the sheet was still open). Fixable
    /// in-app by asking, then retrying — no Settings trip.
    case healthNotAsked
    /// The device can't do HealthKit at all (iPad, some regions).
    case healthUnavailable
    /// Session problem — the user has to be signed in.
    case notSignedIn
    /// Network / server. Retry is the whole answer.
    case connection
    /// Anything else.
    case unknown

    /// One line, in the user's language, that is true even when we're unsure.
    var message: String {
        switch self {
        case .healthNotAsked:
            return "Waiting on Apple Health access"
        case .healthUnavailable:
            return "Apple Health isn't available on this device"
        case .notSignedIn:
            return "You need to be signed in to import"
        case .connection:
            return "Couldn't reach Mile A Day"
        case .unknown:
            return "Something went wrong"
        }
    }

    /// What the user should do, if anything.
    var recovery: String {
        switch self {
        case .healthNotAsked:
            return "Tap retry and allow access when Apple Health asks."
        case .healthUnavailable:
            return "Your workouts will sync from another device."
        case .notSignedIn:
            return "Sign in again to pick up where you left off."
        case .connection:
            return "Check your connection and tap retry — nothing already imported is lost."
        case .unknown:
            return "Tap retry. Nothing already imported is lost."
        }
    }

    var isRetryable: Bool { self != .healthUnavailable }

    /// Classify without ever surfacing Apple's wording.
    init(_ error: Error) {
        if let syncError = error as? SyncError {
            switch syncError {
            case .healthKitNotAvailable: self = .healthUnavailable
            case .notAuthenticated: self = .notSignedIn
            case .invalidResponse, .serverError, .networkError: self = .connection
            }
            return
        }
        let nsError = error as NSError
        if nsError.domain == HKError.errorDomain {
            switch nsError.code {
            case HKError.errorAuthorizationNotDetermined.rawValue,
                 HKError.errorAuthorizationDenied.rawValue:
                self = .healthNotAsked
            case HKError.errorHealthDataUnavailable.rawValue,
                 HKError.errorHealthDataRestricted.rawValue:
                self = .healthUnavailable
            default:
                self = .unknown
            }
            return
        }
        if nsError.domain == NSURLErrorDomain {
            self = .connection
            return
        }
        self = .unknown
    }
}

/// Progress update for sync operations.
///
/// New fields are defaulted so every existing construction site keeps
/// compiling — the memberwise init is the only one.
struct SyncProgress: Equatable {
    let phase: SyncPhase
    let fetchedCount: Int
    let totalToFetch: Int
    let uploadedCount: Int
    let totalToUpload: Int
    let currentBatch: Int
    let totalBatches: Int
    /// Workouts whose HealthKit detail has been read and packed but not yet
    /// sent. This moves once per WORKOUT where `uploadedCount` moves once per
    /// BATCH OF 50 — and reading the splits is most of the wall time, so
    /// without it a progress bar sits perfectly still for a minute at a
    /// stretch and reads as frozen.
    var preparedCount: Int = 0
    /// True for the one-time historical import (thousands of workouts, minutes
    /// of work) as opposed to an ordinary catch-up sync.
    var isInitialImport: Bool = false
    /// When this run started, so the UI can estimate what's left.
    var startedAt: Date? = nil
    /// Workouts a PREVIOUS run of this import already finished. Counted into
    /// the totals so a resumed import picks up the bar at two thirds rather
    /// than appearing to start over, but excluded from the rate estimate —
    /// this run hasn't spent any time on them.
    var completedBeforeRun: Int = 0
    /// Set with `.error`; drives what the UI offers to do about it.
    var failure: SyncFailure? = nil

    /// Fraction actually DELIVERED. Unchanged semantics for existing callers.
    var overallProgress: Double {
        guard totalToUpload > 0 else { return 0 }
        return Double(uploadedCount) / Double(totalToUpload)
    }

    /// Fraction of the WORK done, counting preparation. Reading a workout's
    /// splits out of HealthKit is the slow half, so a bar driven purely by
    /// uploads understates progress badly and moves in 50-workout jumps.
    var displayProgress: Double {
        guard totalToUpload > 0 else { return 0 }
        let prepared = Double(min(preparedCount, totalToUpload)) / Double(totalToUpload)
        let uploaded = Double(min(uploadedCount, totalToUpload)) / Double(totalToUpload)
        return min(1, prepared * 0.7 + uploaded * 0.3)
    }

    var isComplete: Bool {
        if case .complete = phase {
            return true
        }
        return false
    }

    var isFailed: Bool { failure != nil }

    /// Rough seconds remaining, from the rate achieved so far. Nil until
    /// there's enough of a sample to be worth showing — a wrong estimate in
    /// the first two seconds is worse than none.
    var estimatedSecondsRemaining: TimeInterval? {
        guard let startedAt, totalToUpload > 0 else { return nil }
        let done = min(preparedCount, totalToUpload)
        // Rate comes from THIS run only; the remainder is everything left.
        let doneThisRun = done - completedBeforeRun
        guard doneThisRun >= 25 else { return nil }
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 5 else { return nil }
        let perWorkout = elapsed / Double(doneThisRun)
        let remaining = Double(totalToUpload - done) * perWorkout
        return remaining > 0 ? remaining : nil
    }
}

// MARK: - Workout Sync Service

/// Service for automatically syncing workouts to the backend in batches
@MainActor
class WorkoutSyncService: ObservableObject {

    // MARK: - Singleton
    static let shared = WorkoutSyncService()

    // MARK: - Published Properties
    @Published var currentProgress: SyncProgress?
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?
    /// True while the one-time historical backfill is running. Anything that
    /// draws a conclusion from the user's history — above all the streak
    /// reveal — must wait for this, or it announces a number computed from a
    /// third of their walks and then quietly disagrees with itself.
    @Published private(set) var isImportingHistory = false

    /// Monotonic id for the current sync attempt. A progress handler from an
    /// ABANDONED run must not be able to write to `currentProgress`: that is
    /// how a failure from a first attempt (asked before the Health permission
    /// sheet was answered) stayed pinned on screen as "Sync paused — tap to
    /// retry" for the entire duration of the successful import that followed.
    private var runId = 0

    // MARK: - Private Properties
    private let baseURL = AppConfig.baseURL
    private let batchSize = 50
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 2.0  // seconds

    private let healthStore = HKHealthStore()

    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: "backendUserId")
    }

    // MARK: - UserDefaults Keys
    private let lastSyncedWorkoutDateKey = "lastSyncedWorkoutDate"
    private let uploadedWorkoutIdsKey = "uploadedWorkoutIds"
    private let pendingUploadQueueKey = "pendingUploadQueue"
    private let pendingManualUploadsKey = "pendingManualWorkoutUploads"
    private let initialSyncStartedKey = "MAD_InitialSyncStarted"

    // MARK: - Initialization
    private init() {
        self.lastSyncDate = UserDefaults.standard.object(forKey: lastSyncedWorkoutDateKey) as? Date
    }

    // MARK: - Initial Sync Resume State

    /// True if an initial sync was started but never marked complete.
    /// Used on app launch/foreground to auto-resume after a crash or force-quit.
    func isInitialSyncIncomplete() -> Bool {
        let started = UserDefaults.standard.bool(forKey: initialSyncStartedKey)
        return started && lastSyncDate == nil
    }

    /// Should the initial sync run? True for genuine first-time users AND
    /// for users whose initial sync was interrupted last session.
    func shouldRunInitialSync() -> Bool {
        return isFirstTimeSync()
    }

    private func markInitialSyncStarted() {
        UserDefaults.standard.set(true, forKey: initialSyncStartedKey)
    }

    private func clearInitialSyncStarted() {
        UserDefaults.standard.removeObject(forKey: initialSyncStartedKey)
    }

    /// Signals that the initial (historical) sync finished. UserManager uses this
    /// to absorb retroactively-awarded badges WITHOUT celebrations — only badges
    /// earned after this point get unlock popups.
    private func postInitialSyncCompleted() {
        NotificationCenter.default.post(
            name: Notification.Name("MAD_InitialSyncCompleted"),
            object: nil
        )
    }

    // MARK: - Background Initial Sync

    /// Fire-and-forget initial sync that updates `currentProgress` as it runs.
    /// Safe to call repeatedly — no-ops if a sync is already in flight or has completed.
    func startInitialSyncIfNeeded() {
        guard shouldRunInitialSync() else { return }
        guard !isSyncing else { return }

        // Claim the slot synchronously on the main actor to prevent a second
        // call from spawning a parallel sync before the Task body runs.
        isSyncing = true
        isImportingHistory = true
        runId += 1
        let attempt = runId
        // Clear a previous attempt's failure the instant a new one starts, so
        // the banner can never show "paused" over a run that's under way.
        if currentProgress?.isFailed == true { currentProgress = nil }

        Task { [weak self] in
            guard let self else { return }
            // performInitialSyncInternal will set isSyncing=true again (no-op)
            // and clear it when done.
            await self.performInitialSyncInternal(progressHandler: { progress in
                Task { @MainActor in
                    self.publish(progress, from: attempt)
                }
            })
        }
    }

    /// Write a progress update, unless it came from an abandoned attempt.
    @MainActor
    private func publish(_ progress: SyncProgress, from attempt: Int) {
        guard attempt == runId else { return }
        currentProgress = progress
    }

    /// The banner's retry. Distinct from `startInitialSyncIfNeeded` because
    /// that one silently no-ops in exactly the two states a user taps retry in:
    /// while a sync is already running, and once `lastSyncDate` has been
    /// stamped. Returns false when there was nothing to start, so the caller
    /// can say "still working" rather than looking like a dead button.
    @discardableResult
    func retryFailedSync() -> Bool {
        guard !isSyncing else { return false }

        // A permission failure means we asked HealthKit before the sheet was
        // answered. Ask first — Apple only re-prompts for types that have
        // never been answered, so this is a no-op for anyone already granted —
        // then start regardless of what it reported, because `success` says
        // nothing about READ access either way.
        if currentProgress?.failure == .healthNotAsked {
            HealthKitManager.shared.requestAuthorization { [weak self] _ in
                Task { @MainActor in self?.beginRetry() }
            }
            return true
        }

        beginRetry()
        return true
    }

    @MainActor
    private func beginRetry() {
        guard !isSyncing else { return }
        currentProgress = nil
        if shouldRunInitialSync() {
            startInitialSyncIfNeeded()
        } else {
            Task { [weak self] in
                try? await self?.syncNewWorkouts()
            }
        }
    }

    // MARK: - Public API

    /// Perform initial sync for first-time users
    /// Returns an async stream of progress updates
    func performInitialSync() -> AsyncStream<SyncProgress> {
        return AsyncStream { continuation in
            guard !self.isSyncing else {
                print("[WorkoutSyncService] ⚠️ Sync already in progress")
                continuation.finish()
                return
            }
            self.isSyncing = true
            self.isImportingHistory = true
            self.runId += 1
            Task {
                await self.performInitialSyncInternal(progressHandler: { progress in
                    continuation.yield(progress)
                    if progress.isComplete || progress.isFailed {
                        continuation.finish()
                    }
                })
            }
        }
    }

    /// Sync new workouts since last sync (for returning users)
    func syncNewWorkouts() async throws {
        guard !isSyncing else {
            print("[WorkoutSyncService] ⚠️ Sync already in progress")
            return
        }

        isSyncing = true
        errorMessage = nil
        // CRITICAL: clear the in-flight flag on EVERY exit. This used to be a
        // plain assignment after the do/catch, which the catch's rethrow
        // skipped — so one failed sync (network blip, locked-device HealthKit
        // error) left isSyncing stuck true for the life of the process, and
        // every later trigger (observer, foreground, BGTask, launch) silently
        // no-op'd at the guard above. That's the "dashboard says mile done,
        // friends list says 0.00 until Sync Streak" wedge: recalibrateStreak
        // was the only upload path that didn't pass through this gate.
        defer { isSyncing = false }

        do {
            let unsyncedWorkouts = try await getUnsyncedWorkouts()

            if unsyncedWorkouts.isEmpty {
                print("[WorkoutSyncService] ✅ No new workouts to sync")
                // Still inside the isSyncing guard, so no other trigger can
                // overlap the sweep.
                await backfillMissingRoutes()
                return
            }

            print("[WorkoutSyncService] 📤 Syncing \(unsyncedWorkouts.count) new workouts")

            // Upload in batches
            try await uploadWorkoutsInBatches(unsyncedWorkouts)

            // Update last sync date
            if let latestWorkout = unsyncedWorkouts.first {
                updateLastSyncDate(latestWorkout.endDate)
            }

            print("[WorkoutSyncService] ✅ Sync complete")

            await backfillMissingRoutes()

        } catch {
            errorMessage = error.localizedDescription
            print("[WorkoutSyncService] ❌ Sync failed: \(error)")
            throw error
        }
    }

    /// Upload ONE workout by HealthKit UUID, route included, regardless of
    /// whether an earlier upload already marked it synced.
    ///
    /// This exists to lose a race gracefully: `builder.finishWorkout` writes
    /// the HKWorkout and the HealthKit OBSERVER fires on that write — often
    /// starting a sync BEFORE `HKWorkoutRouteBuilder.finishRoute` has
    /// attached the GPS trace. That first upload finds no route, the workout
    /// gets marked synced, and the feed never draws the map — while Apple
    /// Fitness (reading HealthKit directly, where the route lands a moment
    /// later) shows it fine. The in-app finish calls this AFTER the route
    /// write completes: the backend workout upsert is idempotent and
    /// `workout_routes` only updates when a payload HAS a route, so this
    /// re-push is safe no matter which upload won.
    func uploadWorkout(withId workoutId: UUID) async {
        guard currentUserId != nil else { return }
        do {
            guard let workout = try await fetchWorkout(byUUID: workoutId) else {
                print("[WorkoutSyncService] ⚠️ Targeted upload: workout \(workoutId) not found in HealthKit")
                return
            }
            // uploadBatchWithRetry(fullSync: false) fetches routes for
            // batches ≤ maxRouteFetchBatch — a single workout always
            // qualifies.
            try await uploadBatchWithRetry([workout])
            markWorkoutsAsSynced([workout.uuid.uuidString])
            updateLastSyncDate(workout.endDate)
            print("[WorkoutSyncService] ✅ Route-bearing upload complete for \(workoutId)")
        } catch {
            // Best-effort: the regular sync paths still cover the workout
            // itself; only the route enrichment is deferred to Sync Streak.
            print("[WorkoutSyncService] ⚠️ Targeted upload failed: \(error)")
        }
    }

    // MARK: - Route backfill

    private let routeBackfilledIdsKey = "routeBackfilledIdsV1"
    /// One batch per app session — healing history is a background courtesy,
    /// not a race.
    private var hasRunRouteBackfillThisSession = false

    /// Heals route-less history. The FIRST-RUN import uploads with
    /// `includeRoutes: false`, incremental batches over `maxRouteFetchBatch`
    /// skip routes too, and the uploaded-ids dedupe means neither ever
    /// retries — so an outdoor run synced either way sits routeless on the
    /// server forever, drawing the indoor-style card. This sweeps the last
    /// 180 days for workouts whose HealthKit record HAS a route, re-uploads
    /// up to one route-bearing batch, and remembers what's done. Safe by
    /// construction: the workout upsert is idempotent and `workout_routes`
    /// only updates when a payload HAS a route.
    private func backfillMissingRoutes() async {
        guard !hasRunRouteBackfillThisSession else { return }
        hasRunRouteBackfillThisSession = true
        let done = Set(UserDefaults.standard.array(forKey: routeBackfilledIdsKey) as? [String] ?? [])
        let since = Date().addingTimeInterval(-730 * 86400)
        guard let workouts = try? await fetchWorkoutsSince(since) else { return }

        // Probe bounded and CONCURRENT: the naive serial loop was up to a few
        // hundred back-to-back HealthKit round-trips inside the isSyncing
        // window, starving every other sync trigger for seconds (the same
        // reason workoutDetails went 6-wide). Limit-1 existence probes are
        // trivial individually, so a capped burst per session is plenty —
        // the registry makes the sweep resume where it left off next session.
        // Stealth walks are permanently routeless on the server BY DESIGN —
        // this sweep must never "heal" one. They're settled on sight so they
        // stop being re-probed, and their trace is never pushed.
        var stealthSettled: [String] = []
        let candidates = Array(
            workouts.filter { workout in
                let id = workout.uuid.uuidString
                guard !done.contains(id) else { return false }
                if StealthModeStore.shared.isStealth(workout) {
                    stealthSettled.append(id)
                    return false
                }
                return true
            }
            .prefix(Self.maxRouteBackfillProbes))
        var hasRoute = [Bool](repeating: false, count: candidates.count)
        await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, workout) in candidates.enumerated() {
                group.addTask {
                    (index, await HealthKitManager.shared.hasRouteData(for: workout))
                }
            }
            for await (index, flag) in group { hasRoute[index] = flag }
        }

        var routeBearing: [HKWorkout] = []
        var settled: [String] = []
        for (index, workout) in candidates.enumerated() {
            guard hasRoute[index] else {
                // No route in HealthKit. Watch routes can land late, so only
                // stop re-probing once the workout is old enough to be
                // settled.
                if workout.endDate < Date().addingTimeInterval(-3 * 86400) {
                    settled.append(workout.uuid.uuidString)
                }
                continue
            }
            routeBearing.append(workout)
        }

        var completed = settled + stealthSettled
        // Up to three route-capped batches per sweep (75 uploads) so a heavy
        // history heals in days, not weeks — each batch ≤ the route-fetch cap
        // so `uploadBatchWithRetry` actually attaches the routes.
        for chunkStart in stride(from: 0, to: min(routeBearing.count, Self.maxRouteFetchBatch * 3),
                                 by: Self.maxRouteFetchBatch) {
            let batch = Array(routeBearing[chunkStart..<min(chunkStart + Self.maxRouteFetchBatch,
                                                            routeBearing.count)])
            do {
                // fullSync: false ⇒ routes are fetched (batch ≤ the cap).
                try await uploadBatchWithRetry(batch)
                completed.append(contentsOf: batch.map { $0.uuid.uuidString })
                print("[WorkoutSyncService] ✅ Route backfill pushed \(batch.count) workout(s)")
            } catch {
                print("[WorkoutSyncService] ⚠️ Route backfill failed: \(error)")
                break
            }
        }
        if !completed.isEmpty {
            let merged = done.union(completed)
            UserDefaults.standard.set(Array(merged), forKey: routeBackfilledIdsKey)
        }
    }

    private func fetchWorkoutsSince(_ since: Date) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            guard HKHealthStore.isHealthDataAvailable() else {
                continuation.resume(returning: [])
                return
            }
            let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1000,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            self.healthStore.execute(query)
        }
    }

    /// Fetch a single workout by UUID from HealthKit.
    private func fetchWorkout(byUUID uuid: UUID) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { continuation in
            guard HKHealthStore.isHealthDataAvailable() else {
                continuation.resume(throwing: SyncError.healthKitNotAvailable)
                return
            }
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForObject(with: uuid),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout])?.first)
            }
            healthStore.execute(query)
        }
    }

    /// Check if this is a first-time sync (no previous sync date)
    func isFirstTimeSync() -> Bool {
        return lastSyncDate == nil
    }

    /// Get count of unsynced workouts
    func getUnsyncedCount() async -> Int {
        do {
            let unsynced = try await getUnsyncedWorkouts()
            return unsynced.count
        } catch {
            print("[WorkoutSyncService] ❌ Failed to get unsynced count: \(error)")
            return 0
        }
    }

    /// Clear sync history (for testing)
    func resetSyncState() {
        UserDefaults.standard.removeObject(forKey: lastSyncedWorkoutDateKey)
        UserDefaults.standard.removeObject(forKey: uploadedWorkoutIdsKey)
        UserDefaults.standard.removeObject(forKey: pendingUploadQueueKey)
        UserDefaults.standard.removeObject(forKey: pendingManualUploadsKey)
        UserDefaults.standard.removeObject(forKey: initialSyncStartedKey)
        lastSyncDate = nil
        currentProgress = nil
        uploadedIdCache = nil
        print("[WorkoutSyncService] 🗑️ Sync state reset")
    }

    // MARK: - Private Methods

    /// Internal initial sync with progress handler.
    /// Callers MUST guard against concurrent invocations — this routine assumes
    /// it owns the sync slot and unconditionally sets `isSyncing`.
    private func performInitialSyncInternal(progressHandler: @escaping (SyncProgress) -> Void) async
    {
        isSyncing = true
        isImportingHistory = true
        errorMessage = nil
        markInitialSyncStarted()

        // One clock for the whole import, so the ETA doesn't restart per batch.
        let startedAt = Date()
        // Survives into the catch so a failure can still say how far it got.
        var lastKnownTotal = 0

        do {
            // Phase 1: Fetch all workouts from HealthKit
            var progress = SyncProgress(
                phase: .fetchingFromHealthKit,
                fetchedCount: 0,
                totalToFetch: 0,
                uploadedCount: 0,
                totalToUpload: 0,
                currentBatch: 0,
                totalBatches: 0,
                isInitialImport: true,
                startedAt: startedAt
            )
            progressHandler(progress)

            let fetchedWorkouts = try await fetchAllWorkoutsFromHealthKit()
            print("[WorkoutSyncService] 📥 Fetched \(fetchedWorkouts.count) workouts from HealthKit")
            lastKnownTotal = fetchedWorkouts.count

            // Skip anything we've already uploaded in a previous (interrupted) run.
            let uploadedIds = getUploadedWorkoutIds()
            let allWorkouts = fetchedWorkouts.filter { !uploadedIds.contains($0.uuid.uuidString) }
            let alreadyUploaded = fetchedWorkouts.count - allWorkouts.count
            if alreadyUploaded > 0 {
                print("[WorkoutSyncService] ⏭️ Resuming — \(alreadyUploaded) workouts already uploaded")
            }

            guard !allWorkouts.isEmpty else {
                // Either no workouts in HealthKit or everything's already uploaded.
                if let latest = fetchedWorkouts.first {
                    updateLastSyncDate(latest.endDate)
                }
                clearInitialSyncStarted()
                postInitialSyncCompleted()
                progress = SyncProgress(
                    phase: .complete,
                    fetchedCount: fetchedWorkouts.count,
                    totalToFetch: fetchedWorkouts.count,
                    uploadedCount: fetchedWorkouts.count,
                    totalToUpload: fetchedWorkouts.count,
                    currentBatch: 0,
                    totalBatches: 0,
                    preparedCount: fetchedWorkouts.count,
                    isInitialImport: true,
                    startedAt: startedAt
                )
                progressHandler(progress)
                isSyncing = false
                isImportingHistory = false
                return
            }

            let totalBatches = (allWorkouts.count + batchSize - 1) / batchSize
            // Report against the WHOLE history, not just what's left. A resumed
            // import that restarts its bar at 0% of a shrinking total reads as
            // "it lost everything and is going again".
            let historyTotal = fetchedWorkouts.count

            // Update progress with total counts
            progress = SyncProgress(
                phase: .uploadingToBackend,
                fetchedCount: historyTotal,
                totalToFetch: historyTotal,
                uploadedCount: alreadyUploaded,
                totalToUpload: historyTotal,
                currentBatch: 0,
                totalBatches: totalBatches,
                preparedCount: alreadyUploaded,
                isInitialImport: true,
                startedAt: startedAt,
                completedBeforeRun: alreadyUploaded
            )
            progressHandler(progress)

            // Phase 2: Upload in batches
            let batches = allWorkouts.chunked(into: batchSize)

            var preparedSoFar = alreadyUploaded

            for (index, batch) in batches.enumerated() {
                print(
                    "[WorkoutSyncService] 📤 Uploading batch \(index + 1)/\(totalBatches) (\(batch.count) workouts)"
                )

                // Upload batch with retry logic. This is the initial account-setup
                // backfill, so flag it full-sync to suppress friend notifications.
                //
                // The per-workout callback is the ONLY progress signal with any
                // resolution: packing a batch means 50 HealthKit round-trips and
                // takes far longer than the POST that follows, so a bar driven
                // by batch completions alone stands still for a minute at a time
                // — which is what "it looks stuck" was.
                let batchBase = preparedSoFar
                try await uploadBatchWithRetry(batch, fullSync: true) { packedInBatch in
                    progressHandler(
                        SyncProgress(
                            phase: .uploadingToBackend,
                            fetchedCount: historyTotal,
                            totalToFetch: historyTotal,
                            uploadedCount: min(alreadyUploaded + index * self.batchSize, historyTotal),
                            totalToUpload: historyTotal,
                            currentBatch: index + 1,
                            totalBatches: totalBatches,
                            preparedCount: min(batchBase + packedInBatch, historyTotal),
                            isInitialImport: true,
                            startedAt: startedAt,
                            completedBeforeRun: alreadyUploaded
                        )
                    )
                }
                preparedSoFar = min(batchBase + batch.count, historyTotal)

                // Mark as synced
                markWorkoutsAsSynced(batch.map { $0.uuid.uuidString })

                // Daily steps are refreshed ONCE, after the loop — not per
                // batch. It's a forced (throttle-bypassing) request about
                // TODAY, and nothing a batch of 2019 workouts uploads can
                // change it; per-batch it was dozens of redundant calls fired
                // at the API during the heaviest minutes of the import.

                // Update progress
                let uploadedCount = alreadyUploaded + (index + 1) * batchSize
                progress = SyncProgress(
                    phase: .uploadingToBackend,
                    fetchedCount: historyTotal,
                    totalToFetch: historyTotal,
                    uploadedCount: min(uploadedCount, historyTotal),
                    totalToUpload: historyTotal,
                    currentBatch: index + 1,
                    totalBatches: totalBatches,
                    preparedCount: preparedSoFar,
                    isInitialImport: true,
                    startedAt: startedAt,
                    completedBeforeRun: alreadyUploaded
                )
                progressHandler(progress)

                // Breathe between batches so a thousand-workout import doesn't
                // read as a burst to the API. Short, because it's paid once per
                // batch across a run the user is watching.
                if index < batches.count - 1 {
                    try await Task.sleep(nanoseconds: 150_000_000)  // 0.15 seconds
                }
            }

            // Update last sync date — prefer the newest endDate across everything we know about
            // (including workouts that were already uploaded in a previous interrupted run).
            if let latestWorkout = fetchedWorkouts.first {
                updateLastSyncDate(latestWorkout.endDate)
            }
            clearInitialSyncStarted()
            postInitialSyncCompleted()

            // Now that the whole history is in, refresh today's steps once.
            Task {
                await DailyStepsSyncService.shared.syncNow(force: true)
            }

            // Complete
            progress = SyncProgress(
                phase: .complete,
                fetchedCount: historyTotal,
                totalToFetch: historyTotal,
                uploadedCount: historyTotal,
                totalToUpload: historyTotal,
                currentBatch: totalBatches,
                totalBatches: totalBatches,
                preparedCount: historyTotal,
                isInitialImport: true,
                startedAt: startedAt,
                completedBeforeRun: alreadyUploaded
            )
            progressHandler(progress)

            print(
                "[WorkoutSyncService] ✅ Initial sync complete: \(allWorkouts.count) workouts uploaded"
            )

        } catch {
            errorMessage = error.localizedDescription
            print("[WorkoutSyncService] ❌ Initial sync failed: \(error)")

            // Report the failure WITHOUT throwing away the counts: a run that
            // died at workout 900 of 1200 has imported 900 workouts, and
            // zeroing the totals here is what made the banner claim the whole
            // import had gone nowhere.
            let failure = SyncFailure(error)
            let done = getUploadedWorkoutIds().count
            let progress = SyncProgress(
                phase: .error(failure.message),
                fetchedCount: lastKnownTotal,
                totalToFetch: lastKnownTotal,
                uploadedCount: min(done, lastKnownTotal),
                totalToUpload: lastKnownTotal,
                currentBatch: 0,
                totalBatches: 0,
                preparedCount: min(done, lastKnownTotal),
                isInitialImport: true,
                startedAt: startedAt,
                failure: failure
            )
            progressHandler(progress)
        }

        isSyncing = false
        isImportingHistory = false
    }

    /// Fetch all workouts from HealthKit
    private func fetchAllWorkoutsFromHealthKit() async throws -> [HKWorkout] {
        return try await withCheckedThrowingContinuation { continuation in
            guard HKHealthStore.isHealthDataAvailable() else {
                continuation.resume(throwing: SyncError.healthKitNotAvailable)
                return
            }

            // The service's own long-lived store, never a fresh one: HealthKit
            // requires the store to outlive the query executed on it, and a
            // local `HKHealthStore()` is released the moment this closure
            // returns — the same "reports nothing, silently" trap as a dropped
            // workout builder (ios.md).

            // Query for running and walking workouts
            let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
            let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
            let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                runningPredicate, walkingPredicate,
            ])

            let sortDescriptor = NSSortDescriptor(
                key: HKSampleSortIdentifierEndDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: compoundPredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { query, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }

    /// Get workouts that haven't been synced yet
    private func getUnsyncedWorkouts() async throws -> [HKWorkout] {
        let allWorkouts = try await fetchAllWorkoutsFromHealthKit()

        guard let lastSync = lastSyncDate else {
            // First time sync - return all workouts
            return allWorkouts
        }

        // Look back 48h behind the watermark, not strictly past it: a Watch
        // workout can land in phone HealthKit MINUTES-TO-HOURS late with an
        // endDate already behind lastSyncDate, and a strict `endDate >
        // lastSync` filter would drop it forever (the same late-arrival trap
        // WorkoutIndex hit — see ios.md). The uploaded-ids set below is what
        // actually dedupes; the backend upsert is idempotent regardless.
        let cutoff = min(lastSync, Date().addingTimeInterval(-48 * 3600))
        let unsyncedWorkouts = allWorkouts.filter { $0.endDate > cutoff }

        // Skip everything this device already uploaded (partial failures,
        // and the 48h window re-surfacing already-synced workouts).
        let uploadedIds = getUploadedWorkoutIds()
        let filteredWorkouts = unsyncedWorkouts.filter { !uploadedIds.contains($0.uuid.uuidString) }

        return filteredWorkouts
    }

    /// Upload workouts in batches
    private func uploadWorkoutsInBatches(_ workouts: [HKWorkout]) async throws {
        let batches = workouts.chunked(into: batchSize)

        for (index, batch) in batches.enumerated() {
            print("[WorkoutSyncService] 📤 Uploading batch \(index + 1)/\(batches.count)")

            try await uploadBatchWithRetry(batch)
            markWorkoutsAsSynced(batch.map { $0.uuid.uuidString })

            // Refresh today's daily steps now that the backend has new workout data.
            Task {
                await DailyStepsSyncService.shared.syncNow(force: true)
            }

            // Small delay between batches
            if index < batches.count - 1 {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    /// Upload a single batch with retry logic.
    /// `fullSync` is true only for the one-time HealthKit backfill run at account
    /// setup / re-login; it tells the backend to skip friend-facing notifications
    /// so a historical import doesn't spam other users.
    private func uploadBatchWithRetry(
        _ workouts: [HKWorkout],
        fullSync: Bool = false,
        onPrepared: ((Int) -> Void)? = nil
    ) async throws {
        var lastError: Error?

        // Build the payload ONCE — it's deterministic, and the transform now
        // reads GPS routes from HealthKit, which must not be re-enumerated on
        // every network retry.
        let workoutData = try await transformWorkoutsForBackend(
            workouts, includeRoutes: !fullSync, onPrepared: onPrepared)

        for attempt in 1...maxRetries {
            do {
                try await uploadBatch(workoutData, count: workouts.count, fullSync: fullSync)
                return  // Success!
            } catch {
                lastError = error
                print("[WorkoutSyncService] ⚠️ Upload attempt \(attempt) failed: \(error)")

                if attempt < maxRetries {
                    let delay = retryDelay * pow(2.0, Double(attempt - 1))  // Exponential backoff
                    print("[WorkoutSyncService] ⏳ Retrying in \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        // All retries failed
        if let error = lastError {
            throw error
        }
    }

    /// Upload one pre-transformed batch to the backend.
    /// When `fullSync` is true the request carries ?fullSync=true so the backend
    /// suppresses friend-facing notifications for this historical backfill.
    private func uploadBatch(_ workoutData: [[String: Any]], count: Int, fullSync: Bool = false) async throws {
        guard let userId = currentUserId else {
            throw SyncError.notAuthenticated
        }

        // Make API request using fancyFetch
        let endpoint = fullSync ? "/workouts/\(userId)/upload?fullSync=true" : "/workouts/\(userId)/upload"
        let requestBody = try JSONSerialization.data(withJSONObject: workoutData)

        struct UploadedBadge: Codable {
            let badgeId: String
            let name: String
            let rarity: String
        }
        struct UploadedChallengeCompletion: Codable {
            let localDate: String
            let challengeKey: String
            let challengeTitle: String
        }
        struct UploadedRacePR: Codable {
            let distanceKey: String
            let durationSec: Double
        }
        struct UploadResponse: Codable {
            let message: String?
            let newlyEarnedBadges: [UploadedBadge]?
            let newChallengeCompletions: [UploadedChallengeCompletion]?
            let newRaceRecords: [UploadedRacePR]?
        }

        do {
            let response: UploadResponse = try await APIClient.fancyFetch(
                endpoint: endpoint,
                method: .POST,
                body: requestBody,
                responseType: UploadResponse.self
            )
            print("[WorkoutSyncService] ✅ Uploaded batch of \(count) workouts")

            let badgeCount = response.newlyEarnedBadges?.count ?? 0
            let completionCount = response.newChallengeCompletions?.count ?? 0
            if badgeCount > 0 || completionCount > 0 {
                print("[WorkoutSyncService] 🎉 Rewards — \(badgeCount) badges, \(completionCount) challenge completions")
            }

            // Pass the fresh completion details through so the celebration layer can
            // show a rewarding moment for the specific challenge that was completed.
            let completionPayload: [[String: String]] = (response.newChallengeCompletions ?? []).map {
                ["challengeKey": $0.challengeKey, "challengeTitle": $0.challengeTitle, "localDate": $0.localDate]
            }
            // Race PRs set by this upload (best time for 5K, 10K, etc.) so the
            // celebration layer can tell the user they just set a new PR.
            let racePRPayload: [[String: String]] = (response.newRaceRecords ?? []).map {
                ["distanceKey": $0.distanceKey, "durationSec": String($0.durationSec)]
            }
            await MainActor.run {
                NotificationCenter.default.post(
                    name: Notification.Name("MAD_WorkoutsUploaded"),
                    object: nil,
                    userInfo: [
                        "newBadgeCount": badgeCount,
                        "newChallengeCompletionCount": completionCount,
                        "newChallengeCompletions": completionPayload,
                        "newRaceRecords": racePRPayload
                    ]
                )
            }
        } catch let error as APIError {
            // Map APIError to SyncError
            switch error {
            case .invalidURL:
                throw SyncError.invalidResponse
            case .invalidResponse:
                throw SyncError.invalidResponse
            case .notAuthenticated:
                throw SyncError.notAuthenticated
            case .serverError(let code):
                throw SyncError.serverError(code)
            case .networkError(let message):
                throw SyncError.networkError(message)
            default:
                throw SyncError.networkError(error.localizedDescription)
            }
        } catch {
            throw SyncError.networkError(error.localizedDescription)
        }
    }

    /// Cap uploaded routes to a drawing-friendly polyline; the backend stores
    /// them verbatim and feeds them back to feed cards. 300 matches the
    /// server's MAX_ROUTE_POINTS — sending more triggers its uniform-stride
    /// backstop, which clips corners (exactly what the Douglas-Peucker
    /// downsample below exists to avoid).
    private static let maxRoutePoints = 300
    /// Don't fetch routes for oversized batches — that's a backfill, not a
    /// fresh run, and per-workout route queries would drag the whole upload.
    private static let maxRouteFetchBatch = 25
    /// How many unprobed candidates one backfill sweep examines — keeps the
    /// sweep's HealthKit burst bounded; the registry carries the rest to the
    /// next session.
    private static let maxRouteBackfillProbes = 120

    /// The workout's GPS trace as [[lat, lng], ...], downsampled to
    /// `maxRoutePoints` (corner-preserving Douglas-Peucker, never a uniform
    /// stride — see WorkoutRouteCleanup) and rounded to ~1m precision. Nil
    /// when the workout has no route (indoor/manual).
    private func simplifiedRoute(for workout: HKWorkout) async -> [[Double]]? {
        let locations = await HealthKitManager.shared.fetchAllRouteLocations(for: workout)
        guard locations.count >= 2 else { return nil }

        let sampled = WorkoutRouteCleanup.simplified(locations, toMaxPoints: Self.maxRoutePoints)
        return sampled.map { location in
            var point = [
                (location.coordinate.latitude * 100_000).rounded() / 100_000,
                (location.coordinate.longitude * 100_000).rounded() / 100_000,
            ]
            // Elevation groundwork: a third element the server now KEEPS.
            // Every consumer reads [0]/[1] and tolerates extras (the decode
            // guards are `count >= 2`), so this is additive on the wire —
            // shipped today so climb/elevation features have history to draw
            // on the day they exist. `verticalAccuracy <= 0` is CoreLocation's
            // "no valid altitude" — omit rather than store a lie.
            if location.verticalAccuracy > 0 {
                point.append((location.altitude * 10).rounded() / 10)
            }
            return point
        }
    }

    /// The HealthKit reads a single workout needs, gathered in one place so
    /// they can be run concurrently.
    private struct WorkoutDetail {
        let splits: [WorkoutSplit]
        let calories: Double
    }

    /// How many workouts to read from HealthKit at once. Each one is two
    /// queries, so this is really a window of ~12 in flight — enough to keep
    /// HealthKit busy without a thousand-query stampede on an old device.
    private static let detailConcurrency = 6

    /// Read every workout's splits and energy with bounded concurrency,
    /// reporting completions as they land.
    ///
    /// These were awaited strictly one workout at a time, which is the single
    /// biggest reason a decade of Apple Health history takes tens of minutes to
    /// import: the work is two independent reads of samples that are already on
    /// disk, and nothing about them is ordered. Results are slotted back by
    /// index, so the payload order is byte-identical to the sequential version.
    private func workoutDetails(
        for workouts: [HKWorkout],
        onPrepared: ((Int) -> Void)?
    ) async -> [WorkoutDetail] {
        guard !workouts.isEmpty else { return [] }

        var results = [WorkoutDetail?](repeating: nil, count: workouts.count)
        var completed = 0

        await withTaskGroup(of: (Int, WorkoutDetail).self) { group in
            var next = 0

            func schedule(_ index: Int) {
                let workout = workouts[index]
                group.addTask { [weak self] in
                    guard let self else {
                        return (index, WorkoutDetail(splits: [], calories: 0))
                    }
                    async let splits = self.getSplitTimes(for: workout)
                    async let calories = self.activeEnergyKilocalories(for: workout)
                    return (
                        index,
                        WorkoutDetail(splits: await splits, calories: await calories)
                    )
                }
            }

            while next < workouts.count && next < Self.detailConcurrency {
                schedule(next)
                next += 1
            }

            for await (index, detail) in group {
                results[index] = detail
                completed += 1
                onPrepared?(completed)
                if next < workouts.count {
                    schedule(next)
                    next += 1
                }
            }
        }

        return results.map { $0 ?? WorkoutDetail(splits: [], calories: 0) }
    }

    /// Transform HKWorkout objects to backend format
    private func transformWorkoutsForBackend(
        _ workouts: [HKWorkout],
        includeRoutes: Bool = false,
        onPrepared: ((Int) -> Void)? = nil
    ) async throws -> [[String: Any]]
    {
        var workoutData: [[String: Any]] = []
        let fetchRoutes = includeRoutes && workouts.count <= Self.maxRouteFetchBatch

        let details = await workoutDetails(for: workouts, onPrepared: onPrepared)

        for (index, workout) in workouts.enumerated() {
            let detail = details[index]

            // Convert splits to dictionaries for JSON serialization
            let splitsData = detail.splits.map { split -> [String: Any] in
                [
                    "splitNumber": split.splitNumber,
                    "distance": split.distance,
                    "duration": split.duration,
                    "pace": split.pace
                ]
            }

            let timezoneOffset = TimeZone.current.secondsFromGMT() / 60

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            let localDate = formatter.string(from: workout.startDate)

            let isoFormatter = ISO8601DateFormatter()
            let deviceEndDate = isoFormatter.string(from: workout.endDate)

            let workoutType = getWorkoutType(from: workout.workoutActivityType)
            let calories = detail.calories
            // `madDistanceMiles`, never the raw HealthKit total: the server
            // (and therefore the feed, streaks and every friend's screen) has to
            // agree with the number this phone showed while measuring the walk.
            let distance = workout.madDistanceMiles
            // Stealth Mode: nothing route-shaped may leave the device for a
            // walk recorded in stealth, and the server is told so it stamps
            // (and refuses any later route for) the workout itself.
            let isStealth = StealthModeStore.shared.isStealth(workout)

            var workoutDict: [String: Any] = [
                "workoutId": workout.uuid.uuidString,
                "distance": distance,
                "localDate": localDate,
                "date": localDate,
                "timezoneOffset": timezoneOffset,
                "workoutType": workoutType,
                "deviceEndDate": deviceEndDate,
                "calories": calories,
                "totalDuration": workout.duration,
                "splits": splitsData,
                "source": "healthkit",
                // WHICH app wrote this into HealthKit. The server needs it to
                // spot the same run arriving twice from two connected apps
                // (Garmin Connect and Strava both writing one workout is two
                // HKWorkout UUIDs, so UUID dedup can't see it) — without this
                // the miles, the daily goal and the leaderboards all double.
                "sourceBundleId": workout.sourceRevision.source.bundleIdentifier,
            ]

            // HealthKit's indoor flag — the server stores it additively
            // (COALESCE, so a payload without it never erases a recorded
            // answer) and the cards' indoor/outdoor chip reads it.
            if let indoor = (workout.metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber)?.boolValue {
                workoutDict["isIndoor"] = indoor
            }

            // Only ever asserted, never denied: the server ORs it with its own
            // window log and the stamp is sticky.
            if isStealth {
                workoutDict["stealth"] = true
            }

            // In-app tracked workouts carry their moving time as metadata —
            // the display-pace divisor server-side. Absent on Watch/third-
            // party workouts; the server treats null as "use elapsed".
            if let movingSeconds = workout.metadata?[WorkoutLocationManager.movingSecondsMetadataKey] as? Double,
               movingSeconds > 0 {
                workoutDict["movingSeconds"] = movingSeconds
            }

            // Ghost race, stamped by the tracker only when the ghost was
            // BEATEN — so sending it at all is the win. The server COALESCEs
            // these on re-upload, so a later route-less or fullSync push can't
            // erase a win this one recorded.
            if let ghostMargin = workout.metadata?[WorkoutLocationManager.ghostMarginMetadataKey] as? Double,
               let ghostTarget = workout.metadata?[WorkoutLocationManager.ghostTargetMetadataKey] as? Double,
               ghostMargin > 0, ghostTarget > 0 {
                workoutDict["ghostMarginSeconds"] = ghostMargin
                workoutDict["ghostTargetSeconds"] = ghostTarget
                // Only set when the ghost was a FRIEND's mile. The server
                // re-checks the friendship before telling them anything, so an
                // id here is a claim, not an authorization.
                if let ghostFriendId = workout.metadata?[
                    WorkoutLocationManager.ghostFriendMetadataKey] as? String,
                    !ghostFriendId.isEmpty {
                    workoutDict["ghostFriendUserId"] = ghostFriendId
                }
            }

            // Attach the simplified GPS path when the workout has one, so the
            // backend can store it and feed cards can draw the mile's route.
            if fetchRoutes, !isStealth, let route = await simplifiedRoute(for: workout) {
                workoutDict["route"] = route
            }

            workoutData.append(workoutDict)
        }

        return workoutData
    }

    private func getWorkoutType(from activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .running:
            return "running"
        case .walking:
            return "walking"
        case .cycling:
            return "cycling"
        case .hiking:
            return "hiking"
        default:
            return "other"
        }
    }

    private func activeEnergyKilocalories(for workout: HKWorkout) async -> Double {
        if #available(iOS 18.0, *) {
            guard HKHealthStore.isHealthDataAvailable(),
                let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
            else {
                return 0
            }

            return await withCheckedContinuation { continuation in
                let predicate = HKQuery.predicateForObjects(from: workout)
                let query = HKStatisticsQuery(
                    quantityType: energyType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, statistics, error in
                    if let error = error {
                        print(
                            "[WorkoutSyncService] ⚠️ Active energy query failed: \(error.localizedDescription)"
                        )
                    }

                    let value =
                        statistics?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
                    continuation.resume(returning: value)
                }

                healthStore.execute(query)
            }
        } else {
            return workout.totalEnergyBurned?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
        }
    }

    /// Get split data for a workout using the shared SplitCalculator.
    private func getSplitTimes(for workout: HKWorkout) async -> [WorkoutSplit] {
        return await SplitCalculator.calculateSplits(for: workout)
    }

    // MARK: - Tracking Methods

    private func updateLastSyncDate(_ date: Date) {
        // Monotonic: when the 48h lookback uploads a late-arriving OLD workout,
        // its endDate must not drag the watermark backwards.
        let advanced = max(date, lastSyncDate ?? .distantPast)
        lastSyncDate = advanced
        UserDefaults.standard.set(advanced, forKey: lastSyncedWorkoutDateKey)
    }

    private func markWorkoutsAsSynced(_ workoutIds: [String]) {
        var uploadedIds = getUploadedWorkoutIds()
        uploadedIds.formUnion(workoutIds)
        uploadedIdCache = uploadedIds

        // Store as array (Set isn't directly storable)
        UserDefaults.standard.set(Array(uploadedIds), forKey: uploadedWorkoutIdsKey)
    }

    /// In-memory mirror of the uploaded-id set.
    ///
    /// Read on every batch and on every incremental sync. Decoding it from
    /// UserDefaults each time is O(history) on the main actor, and during a
    /// backfill of a decade of workouts that decode happens once per 50-workout
    /// batch against a set that is itself growing to thousands. The write still
    /// goes through, so a kill mid-import resumes exactly as before.
    private var uploadedIdCache: Set<String>?

    private func getUploadedWorkoutIds() -> Set<String> {
        if let uploadedIdCache { return uploadedIdCache }
        let stored = UserDefaults.standard.array(forKey: uploadedWorkoutIdsKey) as? [String] ?? []
        let set = Set(stored)
        uploadedIdCache = set
        return set
    }

    // MARK: - Pending Manual Upload Queue

    /// A manually-entered workout is pushed to the backend the instant it's
    /// saved. If that POST fails (offline, or the app is killed mid-request) the
    /// workout would be lost server-side: it's backdated, so the endDate-based
    /// incremental sync in `getUnsyncedWorkouts()` can never re-pick it up. To
    /// prevent that, every manual workout is enqueued here *before* the upload is
    /// attempted and only removed once the server confirms it.
    /// `flushPendingManualUploads()` retries the queue on every app launch /
    /// foreground so a stuck workout eventually lands.

    /// Enqueue a manual workout payload (the backend-shaped dict) for durable
    /// retry. De-dupes by workoutId so repeated save attempts don't stack copies.
    func enqueueManualUpload(_ payload: [String: Any]) {
        guard let workoutId = payload["workoutId"] as? String else { return }
        var queue = pendingManualUploads()
        queue.removeAll { ($0["workoutId"] as? String) == workoutId }
        queue.append(payload)
        savePendingManualUploads(queue)
    }

    /// Remove a manual workout from the retry queue once the server has it.
    func removeManualUpload(workoutId: String) {
        var queue = pendingManualUploads()
        let before = queue.count
        queue.removeAll { ($0["workoutId"] as? String) == workoutId }
        if queue.count != before { savePendingManualUploads(queue) }
    }

    /// Best-effort retry of any manual workouts whose original upload didn't
    /// land. Never throws — a still-failing item simply stays queued for next
    /// time. No `fullSync` flag: the backend already suppresses notifications for
    /// workouts older than 24h, so a freshly-logged mile still hypes friends
    /// while a long-stuck backfill stays silent.
    func flushPendingManualUploads() async {
        let queue = pendingManualUploads()
        guard !queue.isEmpty, let userId = currentUserId else { return }

        print("[WorkoutSyncService] 🔁 Flushing \(queue.count) pending manual upload(s)")

        for payload in queue {
            guard let workoutId = payload["workoutId"] as? String else {
                continue
            }
            do {
                let requestBody = try JSONSerialization.data(withJSONObject: [payload])
                let _: ManualUploadAck = try await APIClient.fancyFetch(
                    endpoint: "/workouts/\(userId)/upload",
                    method: .POST,
                    body: requestBody,
                    responseType: ManualUploadAck.self
                )
                removeManualUpload(workoutId: workoutId)
                print("[WorkoutSyncService] ✅ Flushed pending manual workout \(workoutId)")
            } catch {
                print("[WorkoutSyncService] ⚠️ Pending manual workout \(workoutId) still failing: \(error)")
            }
        }
    }

    private func pendingManualUploads() -> [[String: Any]] {
        guard let data = UserDefaults.standard.data(forKey: pendingManualUploadsKey),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }
        return arr
    }

    private func savePendingManualUploads(_ queue: [[String: Any]]) {
        if queue.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingManualUploadsKey)
            return
        }
        if let data = try? JSONSerialization.data(withJSONObject: queue) {
            UserDefaults.standard.set(data, forKey: pendingManualUploadsKey)
        }
    }

    // MARK: - Recalibrate Streak

    /// Result of a recalibration: the freshly-recomputed server streak and how
    /// many local workouts were re-checked against the server.
    struct RecalibrateOutcome {
        let streak: Int
        let workoutsPushed: Int
    }

    /// Reconcile the server with the phone's HealthKit truth, then recompute the
    /// server streak. Fixes the case where a manual/backdated workout never
    /// reached the server (its upload failed and incremental sync can't re-pick
    /// up backdated workouts), leaving the server streak shorter than reality.
    /// `localStreakDays` scopes how far back to re-push — we cover the streak
    /// plus a buffer, with a sensible floor.
    func recalibrateStreak(localStreakDays: Int) async throws -> RecalibrateOutcome {
        guard let userId = currentUserId else { throw SyncError.notAuthenticated }

        // 1. Flush any manual workouts still stuck in the retry queue.
        await flushPendingManualUploads()

        // 2. Re-push the HealthKit workouts spanning the streak window. Uploads
        //    are idempotent on the backend (ON CONFLICT (workout_id) DO UPDATE),
        //    so re-sending already-synced workouts is harmless and just backfills
        //    any that are missing. fullSync=true keeps this bulk re-push silent.
        let lookbackDays = max(localStreakDays + 14, 60)
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let since = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: startOfToday) ?? startOfToday
        let workouts = try await fetchWorkouts(since: since)

        for batch in workouts.chunked(into: batchSize) {
            try await uploadBatchWithRetry(batch, fullSync: true)
            markWorkoutsAsSynced(batch.map { $0.uuid.uuidString })
        }

        // 3. Remove backend workouts that were deleted from Apple Health.
        //    Build the HK UUID set from what we just fetched, then compare
        //    against the backend's list for the same window.
        let hkUUIDs = Set(workouts.map { $0.uuid.uuidString })
        await removeOrphanedBackendWorkouts(since: since, hkUUIDs: hkUUIDs, userId: userId)

        // 4. Ask the backend to recompute the streak synchronously and return it.
        let response: RecalibrateStreakResponse = try await APIClient.fancyFetch(
            endpoint: "/workouts/\(userId)/recalibrate-streak",
            method: .POST,
            body: nil,
            responseType: RecalibrateStreakResponse.self
        )

        return RecalibrateOutcome(streak: response.streak, workoutsPushed: workouts.count)
    }

    /// Compare the backend's workout list against `hkUUIDs` (the set of HealthKit
    /// UUIDs for the recalibrate window) and soft-delete any backend workouts that
    /// no longer exist in Apple Health. Best-effort: per-workout failures are logged
    /// and skipped rather than surfaced to the caller.
    ///
    /// Manual workouts (source = "manual") are never auto-deleted — the user
    /// entered them explicitly and they may not have a matching HK entry.
    private func removeOrphanedBackendWorkouts(since: Date, hkUUIDs: Set<String>, userId: String) async {
        // An EMPTY HealthKit set is never evidence that the user deleted
        // everything. Apple never reports read authorization, so a denied
        // Workouts switch returns an empty array with NO error — indistinguishable
        // from a genuinely empty window — and taking it at face value would delete
        // the whole backend history of anyone who taps Recalibrate with reads off.
        // A real "I deleted them all" self-heals on the next recalibrate after one
        // new workout lands.
        guard !hkUUIDs.isEmpty else {
            print("[WorkoutSyncService] ⚠️ Orphan check skipped: HealthKit returned no workouts (denied read, or a genuinely empty window)")
            return
        }

        struct BackendWorkout: Decodable {
            let workoutId: String
            let deviceEndDate: String
            let source: String?
            enum CodingKeys: String, CodingKey {
                case workoutId = "workout_id"
                case deviceEndDate = "device_end_date"
                case source
            }
        }

        let backend: [BackendWorkout]
        do {
            backend = try await APIClient.fancyFetch(
                endpoint: "/workouts/\(userId)/recent?limit=500",
                method: .GET,
                responseType: [BackendWorkout].self
            )
        } catch {
            print("[WorkoutSyncService] ⚠️ Orphan check: couldn't fetch backend workouts: \(error)")
            return
        }

        // node-pg serializes timestamptz as "…Z" with milliseconds; try that first,
        // fall back to the no-fractional-seconds variant for any stored string values.
        let isoWithMs = ISO8601DateFormatter()
        isoWithMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        func parseDate(_ s: String) -> Date? { isoWithMs.date(from: s) ?? isoPlain.date(from: s) }

        let orphans = backend.filter { w in
            guard w.source != "manual" else { return false }
            guard let endDate = parseDate(w.deviceEndDate) else { return false }
            guard endDate >= since else { return false }
            return !hkUUIDs.contains(w.workoutId)
        }

        guard !orphans.isEmpty else { return }
        print("[WorkoutSyncService] 🗑️ \(orphans.count) workout(s) deleted from Apple Health — removing from backend")

        struct DeleteAck: Decodable { let message: String? }
        for orphan in orphans {
            do {
                let _: DeleteAck = try await APIClient.fancyFetch(
                    endpoint: "/workouts/\(userId)/workout/\(orphan.workoutId)",
                    method: .DELETE,
                    responseType: DeleteAck.self
                )
                DeletedWorkoutRegistry.markDeleted(orphan.workoutId)
                print("[WorkoutSyncService] ✅ Removed orphaned workout \(orphan.workoutId)")
            } catch {
                print("[WorkoutSyncService] ⚠️ Could not remove orphan \(orphan.workoutId): \(error)")
            }
        }
    }

    /// Fetch running + walking workouts ending on/after `since` from HealthKit.
    private func fetchWorkouts(since: Date) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            guard HKHealthStore.isHealthDataAvailable() else {
                continuation.resume(throwing: SyncError.healthKitNotAvailable)
                return
            }

            // Long-lived store — see fetchAllWorkoutsFromHealthKit.
            let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
            let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
            let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                runningPredicate, walkingPredicate,
            ])
            let datePredicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                typePredicate, datePredicate,
            ])
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }

            healthStore.execute(query)
        }
    }
}

// MARK: - Lightweight Response Models

/// Minimal decode target for an upload we don't need the rewards payload from.
private struct ManualUploadAck: Decodable {
    let message: String?
}

/// Response from POST /workouts/:userId/recalibrate-streak.
private struct RecalibrateStreakResponse: Decodable {
    let streak: Int
}

// MARK: - Helper Extensions

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Error Types

enum SyncError: LocalizedError {
    case healthKitNotAvailable
    case notAuthenticated
    case invalidResponse
    case serverError(Int)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .healthKitNotAvailable:
            return "HealthKit is not available"
        case .notAuthenticated:
            return "User not authenticated"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
