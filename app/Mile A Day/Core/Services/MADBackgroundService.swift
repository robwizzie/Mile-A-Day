import Foundation
import HealthKit
import BackgroundTasks
import WidgetKit
import UserNotifications

/// Service that handles background processing and HealthKit background delivery
/// Enables live tracking when the app is closed/backgrounded
final class MADBackgroundService: NSObject, ObservableObject {
    static let shared = MADBackgroundService()
    
    private let healthStore = HKHealthStore()
    private let healthManager = HealthKitManager()
    private let userManager = UserManager()
    private let notificationService = MADNotificationService.shared
    // Live workout functionality removed
    private func log(_ message: String) {}
    
    // Background task identifier
    private static let backgroundTaskIdentifier = "com.mileaday.background-refresh"
    
    private override init() {
        super.init()
        // Only set up HealthKit background delivery if user is authenticated
        if UserDefaults.standard.bool(forKey: "MAD_IsAuthenticated") {
            setupBackgroundDelivery()
        }
    }
    
    // MARK: - Public API
    
    /// Call this from AppDelegate to register background tasks
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    /// Call this when app enters background to schedule next refresh
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Failed to schedule background refresh
        }
    }
    
    // MARK: - HealthKit Background Delivery
    
    private func setupBackgroundDelivery() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        // Set up background delivery for workout data
        let workoutType = HKObjectType.workoutType()
        
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { [weak self] success, error in
            if success {
                Task { @MainActor in
                    self?.setupWorkoutObserver()
                }
            }
        }
    }
    
    @MainActor
    private func setupWorkoutObserver() {
        let workoutType = HKObjectType.workoutType()
        
        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { _, completionHandler, error in
            if let error {
                Task { @MainActor in
                    Self.handleWorkoutObserverError(error.localizedDescription)
                    completionHandler()
                }
                return
            }
            
            // Fetch the latest workout data in background
            Task { @MainActor in
                await Self.handleNewWorkoutDataStatic()
                completionHandler()
            }
        }
        
        healthStore.execute(query)
    }
    
    @MainActor
    private static func handleWorkoutObserverError(_ message: String) {
        shared.log("[MADBackgroundService] ❌ Workout observer error: \(message)")
    }
    
    @MainActor
    private static func handleNewWorkoutDataStatic() async {
        await shared.handleNewWorkoutData()
    }
    
    // MARK: - Background Processing
    
    /// Enable background delivery after user authenticates
    func enableBackgroundDeliveryAfterAuth() {
        setupBackgroundDelivery()
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        // Only process if user is authenticated
        guard UserDefaults.standard.bool(forKey: "MAD_IsAuthenticated") else {
            task.setTaskCompleted(success: true)
            return
        }

        // Schedule the next background refresh
        scheduleBackgroundRefresh()

        // Set expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Perform the background work
        Task { [weak self] in
            await self?.performBackgroundSync(reason: .bgAppRefreshTask)
            task.setTaskCompleted(success: true)
        }
    }

    @MainActor
    private func handleNewWorkoutData() async {
        // performBackgroundSync establishes authorization for every reason now,
        // so this path no longer needs its own check.
        await performBackgroundSync(reason: .healthKitObserver)
    }
    
    @MainActor
    private func performBackgroundWork() async {
        // Fetch latest workout data
        let success = await fetchLatestWorkoutData()

        if success {
            // Check if user completed their mile goal
            checkForMileCompletion()

            // Update widgets
            updateWidgets()

            // Sync workouts to backend (background mode)
            await syncWorkoutsInBackground()
        }
    }

    /// Unified entry point for background sync triggered by HealthKit, BGTask, silent push, or background launch.
    /// Caller is responsible for any iOS completion handler (BGTask, fetchCompletionHandler, etc.).
    /// Returns `true` if sync work was attempted, `false` if the call was skipped (e.g., user not authenticated).
    /// Callers reporting to iOS (`fetchCompletionHandler`) should map this to `.newData` / `.noData`
    /// so the system can tune future background wake-up frequency.
    @MainActor
    @discardableResult
    func performBackgroundSync(reason: BackgroundSyncReason) async -> Bool {
        print("[MADBackgroundService] performBackgroundSync(reason: \(reason))")

        // Only run if user has authenticated.
        guard UserDefaults.standard.bool(forKey: "MAD_IsAuthenticated") else {
            print("[MADBackgroundService] Skipping sync — user not authenticated")
            return false
        }

        // Establish HealthKit authorization BEFORE any read. Only the observer
        // path (handleNewWorkoutData) used to do this, so a background launch,
        // BGTask, or silent push ran the entire sync with `isAuthorized` still
        // false — every query returned instantly having done nothing, which is
        // the "❌ Not authorized to access HealthKit" a background launch logs.
        guard await requestHealthKitAuthorizationIfNeeded() else {
            print("[MADBackgroundService] Skipping sync — HealthKit not authorized")
            return false
        }

        await performBackgroundWork()
        return true
    }

    enum BackgroundSyncReason: String {
        case healthKitObserver
        case bgAppRefreshTask
        case silentPush
        case backgroundLaunch
    }

    /// Sync workouts to backend in background (limited batch size)
    @MainActor
    private func syncWorkoutsInBackground() async {
        // Only sync if user is authenticated
        guard UserDefaults.standard.string(forKey: "authToken") != nil,
              UserDefaults.standard.string(forKey: "backendUserId") != nil else {
            log("[Background] Skipping workout sync - user not authenticated")
            return
        }

        do {
            let syncService = WorkoutSyncService.shared
            let unsyncedCount = await syncService.getUnsyncedCount()

            guard unsyncedCount > 0 else {
                log("[Background] No workouts to sync")
                return
            }

            log("[Background] Syncing \(unsyncedCount) workouts in background...")

            // In background, only sync a small batch to avoid timeout
            // Background tasks have limited execution time (~30 seconds)
            try await syncService.syncNewWorkouts()

            log("[Background] ✅ Workout sync complete")

        } catch {
            log("[Background] ❌ Workout sync failed: \(error)")
            // Don't crash on sync failure - workouts will sync on next opportunity
        }
    }
    
    private func requestHealthKitAuthorizationIfNeeded() async -> Bool {
        if healthManager.isAuthorized { return true }

        // Resolve WITHOUT prompting first. This service holds its own
        // HealthKitManager, so its flag starts false in every process no matter
        // what the UI's instance already knows — and in a background launch
        // there's no UI to prompt with anyway. A user who granted access long
        // ago needs no prompt, just a fresh process asking the right question.
        let resolved = await withCheckedContinuation { continuation in
            healthManager.refreshAuthorizationStatus { continuation.resume(returning: $0) }
        }
        if resolved { return true }

        // Genuinely undetermined (first run) — fall back to the real request,
        // which prompts if there's UI to prompt with.
        return await withCheckedContinuation { continuation in
            healthManager.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
    
    private func fetchLatestWorkoutData() async -> Bool {
        return await withCheckedContinuation { continuation in
            // Fetch all workout data using static method to avoid sendable capture issues
            Task { @MainActor in
                let result = await Self.fetchLatestWorkoutDataStatic()
                continuation.resume(returning: result)
            }
        }
    }
    
    @MainActor
    private static func fetchLatestWorkoutDataStatic() async -> Bool {
        let service = shared

        // Fetch all workout data
        service.healthManager.fetchAllWorkoutData()

        // Wait (bounded) for HealthKit to actually finish loading instead of a
        // blind sleep. On a locked phone the queries error out (protected
        // data) and retroactiveStreak can still be 0 when read — writing that
        // through UserManager persisted streak=0 and pushed it into the
        // widget store, so widgets showed a 0 streak while the app (which
        // recomputes after unlock) was correct.
        var waited = 0
        while !service.healthManager.hasLoadedInitialData && waited < 10 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            waited += 1
        }
        guard service.healthManager.hasLoadedInitialData else {
            service.log("[Background] HealthKit data not ready (device likely locked) — skipping user/widget update")
            return false
        }

        service.log("[Background] Updating user with HealthKit data - Streak: \(service.healthManager.retroactiveStreak), Miles: \(service.healthManager.todaysDistance)")
        
        // Update user data with new HealthKit data
        // This now includes saveUserData() call to persist the streak
        service.userManager.updateUserWithHealthKitData(
            retroactiveStreak: service.healthManager.retroactiveStreak,
            currentMiles: service.healthManager.todaysDistance,
            totalMiles: service.healthManager.totalLifetimeMiles,
            fastestPace: service.healthManager.fastestMilePace,
            mostMilesInDay: service.healthManager.mostMilesInOneDay
        )
        
        service.log("[Background] User updated and saved - Current streak now: \(service.userManager.currentUser.streak)")
        
        return true
    }
    
    private func checkForMileCompletion() {
        let currentUser = userManager.currentUser
        let todaysDistance = healthManager.todaysDistance
        let goalMiles = currentUser.goalMiles

        let isCompleted = ProgressCalculator.isGoalCompleted(current: todaysDistance, goal: goalMiles)

        if isCompleted {
            // Send completion notification only if conditions are met
            if notificationService.shouldSendCompletionNotification(
                currentMiles: todaysDistance,
                goalMiles: goalMiles,
                previousMiles: 0.0 // We don't have previous value in background, let the method handle it
            ) {
                notificationService.sendMileCompletedNotification()
            }

            // Update user completion status
            userManager.completeRun(miles: todaysDistance)

            // Switch to congratulatory message
            notificationService.updateDailyReminder(
                isCompleted: true,
                currentMiles: todaysDistance,
                goalMiles: goalMiles
            )
        } else {
            // Re-evaluate the daily reminder with fresh data (one-shot, non-repeating)
            notificationService.updateDailyReminder(
                isCompleted: false,
                currentMiles: todaysDistance,
                goalMiles: goalMiles
            )
        }
    }
    
    private func updateWidgets() {
        // Update widget data store
        let user = userManager.currentUser
        let miles = healthManager.todaysDistance
        
        // Update widget data
        WidgetDataStore.save(todayMiles: miles, goal: user.goalMiles)
        WidgetDataStore.save(streak: user.streak)
    }
}

// MARK: - App Lifecycle Integration
extension MADBackgroundService {
    
    /// Call this from App's sceneDidEnterBackground
    func appDidEnterBackground() {
        // CRITICAL: Force save any active workout state before backgrounding
        // This ensures zero data loss if app is terminated by the system
        if let activeWorkout = InProgressWorkoutStore.load(), activeWorkout.isActive {
            print("🔄 App backgrounding with active workout - forcing state save")
            print("   Current distance: \(activeWorkout.currentDistance) miles")
            print("   Elapsed time: \(Int(activeWorkout.elapsedTime)) seconds")
            print("   Route points: \(activeWorkout.routePoints.count)")

            // State is already saved by updateLiveActivity() every second,
            // but we force synchronize here to ensure UserDefaults is flushed to disk
            UserDefaults.standard.synchronize()
            print("✅ Workout state synchronized to disk")
        }

        // Only schedule background refresh if user is authenticated
        if UserDefaults.standard.bool(forKey: "MAD_IsAuthenticated") {
            scheduleBackgroundRefresh()
        }
    }
    
    /// Call this from App's sceneWillEnterForeground
    func appWillEnterForeground() {
        // Cancel any pending background tasks when app becomes active
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)

        // Only fetch health data and sync if user is authenticated
        guard UserDefaults.standard.bool(forKey: "MAD_IsAuthenticated") else { return }

        // Perform immediate refresh when app becomes active
        Task { [weak self] in
            await self?.performBackgroundWork()

            // Also check for new workouts to sync on foreground
            await AppLaunchSyncHandler.shared.checkAndSyncOnForeground()
        }
    }
} 