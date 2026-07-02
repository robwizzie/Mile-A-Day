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
    case error(String)  // Store error description instead of Error for Equatable conformance

    init(_ error: Error) {
        self = .error(error.localizedDescription)
    }
}

/// Progress update for sync operations
struct SyncProgress: Equatable {
    let phase: SyncPhase
    let fetchedCount: Int
    let totalToFetch: Int
    let uploadedCount: Int
    let totalToUpload: Int
    let currentBatch: Int
    let totalBatches: Int

    var overallProgress: Double {
        guard totalToUpload > 0 else { return 0 }
        return Double(uploadedCount) / Double(totalToUpload)
    }

    var isComplete: Bool {
        if case .complete = phase {
            return true
        }
        return false
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

        Task { [weak self] in
            guard let self else { return }
            // performInitialSyncInternal will set isSyncing=true again (no-op)
            // and clear it when done.
            await self.performInitialSyncInternal(progressHandler: { progress in
                Task { @MainActor in
                    self.currentProgress = progress
                }
            })
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
            Task {
                await self.performInitialSyncInternal(progressHandler: { progress in
                    continuation.yield(progress)
                    if progress.isComplete {
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

        do {
            let unsyncedWorkouts = try await getUnsyncedWorkouts()

            if unsyncedWorkouts.isEmpty {
                print("[WorkoutSyncService] ✅ No new workouts to sync")
                isSyncing = false
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

        } catch {
            errorMessage = error.localizedDescription
            print("[WorkoutSyncService] ❌ Sync failed: \(error)")
            throw error
        }

        isSyncing = false
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
        print("[WorkoutSyncService] 🗑️ Sync state reset")
    }

    // MARK: - Private Methods

    /// Internal initial sync with progress handler.
    /// Callers MUST guard against concurrent invocations — this routine assumes
    /// it owns the sync slot and unconditionally sets `isSyncing`.
    private func performInitialSyncInternal(progressHandler: @escaping (SyncProgress) -> Void) async
    {
        isSyncing = true
        errorMessage = nil
        markInitialSyncStarted()

        do {
            // Phase 1: Fetch all workouts from HealthKit
            var progress = SyncProgress(
                phase: .fetchingFromHealthKit,
                fetchedCount: 0,
                totalToFetch: 0,
                uploadedCount: 0,
                totalToUpload: 0,
                currentBatch: 0,
                totalBatches: 0
            )
            progressHandler(progress)

            let fetchedWorkouts = try await fetchAllWorkoutsFromHealthKit()
            print("[WorkoutSyncService] 📥 Fetched \(fetchedWorkouts.count) workouts from HealthKit")

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
                    totalBatches: 0
                )
                progressHandler(progress)
                isSyncing = false
                return
            }

            let totalBatches = (allWorkouts.count + batchSize - 1) / batchSize

            // Update progress with total counts
            progress = SyncProgress(
                phase: .uploadingToBackend,
                fetchedCount: allWorkouts.count,
                totalToFetch: allWorkouts.count,
                uploadedCount: 0,
                totalToUpload: allWorkouts.count,
                currentBatch: 0,
                totalBatches: totalBatches
            )
            progressHandler(progress)

            // Phase 2: Upload in batches
            let batches = allWorkouts.chunked(into: batchSize)

            for (index, batch) in batches.enumerated() {
                print(
                    "[WorkoutSyncService] 📤 Uploading batch \(index + 1)/\(totalBatches) (\(batch.count) workouts)"
                )

                // Upload batch with retry logic. This is the initial account-setup
                // backfill, so flag it full-sync to suppress friend notifications.
                try await uploadBatchWithRetry(batch, fullSync: true)

                // Mark as synced
                markWorkoutsAsSynced(batch.map { $0.uuid.uuidString })

                // Refresh today's daily steps now that the backend has new workout data.
                Task {
                    await DailyStepsSyncService.shared.syncNow(force: true)
                }

                // Update progress
                let uploadedCount = (index + 1) * batchSize
                progress = SyncProgress(
                    phase: .uploadingToBackend,
                    fetchedCount: allWorkouts.count,
                    totalToFetch: allWorkouts.count,
                    uploadedCount: min(uploadedCount, allWorkouts.count),
                    totalToUpload: allWorkouts.count,
                    currentBatch: index + 1,
                    totalBatches: totalBatches
                )
                progressHandler(progress)

                // Small delay between batches to avoid rate limiting
                if index < batches.count - 1 {
                    try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
                }
            }

            // Update last sync date — prefer the newest endDate across everything we know about
            // (including workouts that were already uploaded in a previous interrupted run).
            if let latestWorkout = fetchedWorkouts.first {
                updateLastSyncDate(latestWorkout.endDate)
            }
            clearInitialSyncStarted()
            postInitialSyncCompleted()

            // Complete
            progress = SyncProgress(
                phase: .complete,
                fetchedCount: allWorkouts.count,
                totalToFetch: allWorkouts.count,
                uploadedCount: allWorkouts.count,
                totalToUpload: allWorkouts.count,
                currentBatch: totalBatches,
                totalBatches: totalBatches
            )
            progressHandler(progress)

            print(
                "[WorkoutSyncService] ✅ Initial sync complete: \(allWorkouts.count) workouts uploaded"
            )

        } catch {
            errorMessage = error.localizedDescription
            print("[WorkoutSyncService] ❌ Initial sync failed: \(error)")

            let progress = SyncProgress(
                phase: SyncPhase(error),
                fetchedCount: 0,
                totalToFetch: 0,
                uploadedCount: 0,
                totalToUpload: 0,
                currentBatch: 0,
                totalBatches: 0
            )
            progressHandler(progress)
        }

        isSyncing = false
    }

    /// Fetch all workouts from HealthKit
    private func fetchAllWorkoutsFromHealthKit() async throws -> [HKWorkout] {
        return try await withCheckedThrowingContinuation { continuation in
            guard HKHealthStore.isHealthDataAvailable() else {
                continuation.resume(throwing: SyncError.healthKitNotAvailable)
                return
            }

            let healthStore = HKHealthStore()

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

        // Filter workouts newer than last sync
        let unsyncedWorkouts = allWorkouts.filter { $0.endDate > lastSync }

        // Also check against uploaded IDs set (in case of partial failures)
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
    private func uploadBatchWithRetry(_ workouts: [HKWorkout], fullSync: Bool = false) async throws {
        var lastError: Error?

        // Build the payload ONCE — it's deterministic, and the transform now
        // reads GPS routes from HealthKit, which must not be re-enumerated on
        // every network retry.
        let workoutData = try await transformWorkoutsForBackend(workouts, includeRoutes: !fullSync)

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
        struct UploadResponse: Codable {
            let message: String?
            let newlyEarnedBadges: [UploadedBadge]?
            let newChallengeCompletions: [UploadedChallengeCompletion]?
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
            await MainActor.run {
                NotificationCenter.default.post(
                    name: Notification.Name("MAD_WorkoutsUploaded"),
                    object: nil,
                    userInfo: [
                        "newBadgeCount": badgeCount,
                        "newChallengeCompletionCount": completionCount,
                        "newChallengeCompletions": completionPayload
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
    /// them verbatim (with its own backstop) and feeds them back to feed cards.
    private static let maxRoutePoints = 150
    /// Don't fetch routes for oversized batches — that's a backfill, not a
    /// fresh run, and per-workout route queries would drag the whole upload.
    private static let maxRouteFetchBatch = 25

    /// The workout's GPS trace as [[lat, lng], ...], downsampled to
    /// `maxRoutePoints` and rounded to ~1m precision. Nil when the workout has
    /// no route (indoor/manual).
    private func simplifiedRoute(for workout: HKWorkout) async -> [[Double]]? {
        let locations = await HealthKitManager.shared.fetchAllRouteLocations(for: workout)
        guard locations.count >= 2 else { return nil }

        let sampled: [CLLocation]
        if locations.count > Self.maxRoutePoints {
            let stride = Double(locations.count - 1) / Double(Self.maxRoutePoints - 1)
            sampled = (0..<Self.maxRoutePoints).map { locations[Int((Double($0) * stride).rounded())] }
        } else {
            sampled = locations
        }
        return sampled.map { location in
            [
                (location.coordinate.latitude * 100_000).rounded() / 100_000,
                (location.coordinate.longitude * 100_000).rounded() / 100_000,
            ]
        }
    }

    /// Transform HKWorkout objects to backend format
    private func transformWorkoutsForBackend(
        _ workouts: [HKWorkout],
        includeRoutes: Bool = false
    ) async throws -> [[String: Any]]
    {
        var workoutData: [[String: Any]] = []
        let fetchRoutes = includeRoutes && workouts.count <= Self.maxRouteFetchBatch

        for workout in workouts {
            // Get split data for this workout
            let splits = await getSplitTimes(for: workout)

            // Convert splits to dictionaries for JSON serialization
            let splitsData = splits.map { split -> [String: Any] in
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
            let calories = await activeEnergyKilocalories(for: workout)
            let distance = workout.totalDistance?.doubleValue(for: HKUnit.mile()) ?? 0

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
            ]

            // Attach the simplified GPS path when the workout has one, so the
            // backend can store it and feed cards can draw the mile's route.
            if fetchRoutes, let route = await simplifiedRoute(for: workout) {
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
        lastSyncDate = date
        UserDefaults.standard.set(date, forKey: lastSyncedWorkoutDateKey)
    }

    private func markWorkoutsAsSynced(_ workoutIds: [String]) {
        var uploadedIds = getUploadedWorkoutIds()
        uploadedIds.formUnion(workoutIds)

        // Store as array (Set isn't directly storable)
        UserDefaults.standard.set(Array(uploadedIds), forKey: uploadedWorkoutIdsKey)
    }

    private func getUploadedWorkoutIds() -> Set<String> {
        if let array = UserDefaults.standard.array(forKey: uploadedWorkoutIdsKey) as? [String] {
            return Set(array)
        }
        return Set()
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

        // 3. Ask the backend to recompute the streak synchronously and return it.
        let response: RecalibrateStreakResponse = try await APIClient.fancyFetch(
            endpoint: "/workouts/\(userId)/recalibrate-streak",
            method: .POST,
            body: nil,
            responseType: RecalibrateStreakResponse.self
        )

        return RecalibrateOutcome(streak: response.streak, workoutsPushed: workouts.count)
    }

    /// Fetch running + walking workouts ending on/after `since` from HealthKit.
    private func fetchWorkouts(since: Date) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            guard HKHealthStore.isHealthDataAvailable() else {
                continuation.resume(throwing: SyncError.healthKitNotAvailable)
                return
            }

            let healthStore = HKHealthStore()
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
