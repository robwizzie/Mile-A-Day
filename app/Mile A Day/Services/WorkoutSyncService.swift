//
//  WorkoutSyncService.swift
//  Mile A Day
//
//  Handles automatic batch syncing of workouts to the backend
//  Supports initial sync, incremental sync, and background sync
//

import Foundation
import HealthKit

// MARK: - Sync Progress Models

/// Represents the current state of a sync operation
enum SyncPhase: Equatable {
    case idle
    case fetchingFromHealthKit
    case uploadingToBackend
    case complete
    case error(String) // Store error description instead of Error for Equatable conformance
    
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
    private let baseURL = "https://mad.mindgoblin.tech"
    private let batchSize = 50
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 2.0 // seconds

    private let healthStore = HKHealthStore()

    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: "backendUserId")
    }

    // MARK: - UserDefaults Keys
    private let lastSyncedWorkoutDateKey = "lastSyncedWorkoutDate"
    private let uploadedWorkoutIdsKey = "uploadedWorkoutIds"
    private let pendingUploadQueueKey = "pendingUploadQueue"

    // MARK: - Initialization
    private init() {
        self.lastSyncDate = UserDefaults.standard.object(forKey: lastSyncedWorkoutDateKey) as? Date
    }

    // MARK: - Public API

    /// Perform initial sync for first-time users
    /// Returns an async stream of progress updates
    func performInitialSync() -> AsyncStream<SyncProgress> {
        return AsyncStream { continuation in
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
        lastSyncDate = nil
        print("[WorkoutSyncService] 🗑️ Sync state reset")
    }

    // MARK: - Private Methods

    /// Internal initial sync with progress handler
    private func performInitialSyncInternal(progressHandler: @escaping (SyncProgress) -> Void) async {
        guard !isSyncing else {
            print("[WorkoutSyncService] ⚠️ Sync already in progress")
            return
        }

        isSyncing = true
        errorMessage = nil

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

            let allWorkouts = try await fetchAllWorkoutsFromHealthKit()
            print("[WorkoutSyncService] 📥 Fetched \(allWorkouts.count) workouts from HealthKit")

            guard !allWorkouts.isEmpty else {
                progress = SyncProgress(
                    phase: .complete,
                    fetchedCount: 0,
                    totalToFetch: 0,
                    uploadedCount: 0,
                    totalToUpload: 0,
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
                print("[WorkoutSyncService] 📤 Uploading batch \(index + 1)/\(totalBatches) (\(batch.count) workouts)")

                // Upload batch with retry logic
                try await uploadBatchWithRetry(batch)

                // Mark as synced
                markWorkoutsAsSynced(batch.map { $0.uuid.uuidString })

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
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                }
            }

            // Update last sync date
            if let latestWorkout = allWorkouts.first {
                updateLastSyncDate(latestWorkout.endDate)
            }

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

            print("[WorkoutSyncService] ✅ Initial sync complete: \(allWorkouts.count) workouts uploaded")

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
            let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])

            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

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

            // Small delay between batches
            if index < batches.count - 1 {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    /// Upload a single batch with retry logic
    private func uploadBatchWithRetry(_ workouts: [HKWorkout]) async throws {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                try await uploadBatch(workouts)
                return // Success!
            } catch {
                lastError = error
                print("[WorkoutSyncService] ⚠️ Upload attempt \(attempt) failed: \(error)")

                if attempt < maxRetries {
                    let delay = retryDelay * pow(2.0, Double(attempt - 1)) // Exponential backoff
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

    /// Upload a single batch to the backend
    private func uploadBatch(_ workouts: [HKWorkout]) async throws {
        guard let userId = currentUserId else {
            throw SyncError.notAuthenticated
        }

        // Transform workouts to backend format
        let workoutData = try await transformWorkoutsForBackend(workouts)

        // Make API request using fancyFetch
        let endpoint = "/workouts/\(userId)/upload"
        let requestBody = try JSONSerialization.data(withJSONObject: workoutData)
        
        struct UploadResponse: Codable {
            let message: String?
        }
        
        do {
            let _: UploadResponse = try await APIClient.fancyFetch(
                endpoint: endpoint,
                method: .POST,
                body: requestBody,
                responseType: UploadResponse.self
            )
            print("[WorkoutSyncService] ✅ Uploaded batch of \(workouts.count) workouts")
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
                throw SyncError.networkError(error.localizedDescription ?? "Unknown error")
            }
        } catch {
            throw SyncError.networkError(error.localizedDescription)
        }
    }

    /// Transform HKWorkout objects to backend format
    private func transformWorkoutsForBackend(_ workouts: [HKWorkout]) async throws -> [[String: Any]] {
        var workoutData: [[String: Any]] = []

        for workout in workouts {
            // Get split data for this workout
            let splits = await getSplitTimes(for: workout)

            // Extract duration values for API (backend expects array of durations in seconds)
            let splitDurations = splits.map { $0.duration }

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

            let workoutDict: [String: Any] = [
                "workoutId": workout.uuid.uuidString,
                "distance": distance,
                "localDate": localDate,
                "date": localDate,
                "timezoneOffset": timezoneOffset,
                "workoutType": workoutType,
                "deviceEndDate": deviceEndDate,
                "calories": calories,
                "totalDuration": workout.duration,
                "splitTimes": splitDurations  // API expects array of durations
            ]

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
                  let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
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
                        print("[WorkoutSyncService] ⚠️ Active energy query failed: \(error.localizedDescription)")
                    }

                    let value = statistics?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
                    continuation.resume(returning: value)
                }

                healthStore.execute(query)
            }
        } else {
            return workout.totalEnergyBurned?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
        }
    }

    /// Get split data for a workout with detailed information about each split
    private func getSplitTimes(for workout: HKWorkout) async -> [WorkoutSplit] {
        return await withCheckedContinuation { continuation in
            guard HKHealthStore.isHealthDataAvailable() else {
                print("[WorkoutSyncService] ⚠️ HealthKit not available for split times")
                continuation.resume(returning: [])
                return
            }

            guard let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else {
                print("[WorkoutSyncService] ⚠️ Distance type not available for split times")
                continuation.resume(returning: [])
                return
            }

            let workoutPredicate = HKQuery.predicateForObjects(from: workout)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

            print("[WorkoutSyncService] 🔍 Starting split calculation for workout \(workout.uuid)")

            let query = HKSampleQuery(
                sampleType: distanceType,
                predicate: workoutPredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                if let error = error {
                    print("[WorkoutSyncService] ⚠️ Error fetching split times: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                    return
                }

                guard let distanceSamples = results as? [HKQuantitySample], !distanceSamples.isEmpty else {
                    print("[WorkoutSyncService] ℹ️ No distance samples found for workout \(workout.uuid)")
                    continuation.resume(returning: [])
                    return
                }

                print("[WorkoutSyncService] 📊 Found \(distanceSamples.count) distance samples")

                // Calculate mile splits from distance samples
                var splits: [WorkoutSplit] = []
                var accumulatedDistance: Double = 0.0
                var startTime: Date?
                let mileInMeters = 1609.34 // One mile in meters
                let mileInMiles = 1.0

                for sample in distanceSamples {
                    let distance = sample.quantity.doubleValue(for: HKUnit.meter())

                    if startTime == nil {
                        startTime = sample.startDate
                    }

                    accumulatedDistance += distance

                    // Check if we've completed a mile
                    if accumulatedDistance >= mileInMeters {
                        if let start = startTime {
                            let endTime = sample.endDate
                            let duration = endTime.timeIntervalSince(start)
                            let pace = duration / mileInMiles

                            let split = WorkoutSplit(
                                splitNumber: splits.count + 1,
                                distance: mileInMiles,
                                duration: duration,
                                pace: pace
                            )
                            splits.append(split)

                            print("[WorkoutSyncService] ✅ Split \(split.splitNumber): \(split.formattedPace)/mile (distance: \(String(format: "%.2f", split.distance)) mi, duration: \(String(format: "%.0f", split.duration))s)")

                            // Reset for next mile
                            accumulatedDistance -= mileInMeters
                            startTime = endTime
                        }
                    }
                }

                print("[WorkoutSyncService] ✅ Total splits calculated: \(splits.count)")
                continuation.resume(returning: splits)
            }

            healthStore.execute(query)
        }
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
}

// MARK: - Helper Extensions

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
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
