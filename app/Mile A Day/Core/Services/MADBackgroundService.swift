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
        setupBackgroundDelivery()
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
    
    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        // Schedule the next background refresh
        scheduleBackgroundRefresh()
        
        // Set expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // Perform the background work
        Task { [weak self] in
            await self?.performBackgroundWork()
            task.setTaskCompleted(success: true)
        }
    }
    
    @MainActor
    private func handleNewWorkoutData() async {
        // Check authorization first
        guard await requestHealthKitAuthorizationIfNeeded() else {
            return
        }
        
        await performBackgroundWork()
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
        return await withCheckedContinuation { [weak self] continuation in
            guard let self = self else {
                continuation.resume(returning: false)
                return
            }
            
            if self.healthManager.isAuthorized {
                continuation.resume(returning: true)
                return
            }
            
            self.healthManager.requestAuthorization { success in
                continuation.resume(returning: success)
            }
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
        
        // Give HealthKit queries more time to complete (increased from 2.0 to 3.0 seconds)
        // This ensures the retroactiveStreak calculation finishes before we read it
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
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
        
        // Check if user just completed their goal
        if todaysDistance >= goalMiles {
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
            
            // Update daily reminder to congratulatory message
            notificationService.updateDailyReminder(
                isCompleted: true,
                currentMiles: todaysDistance,
                goalMiles: goalMiles
            )
        } else {
            // Update daily reminder to motivational message
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

        scheduleBackgroundRefresh()
    }
    
    /// Call this from App's sceneWillEnterForeground
    func appWillEnterForeground() {
        // Cancel any pending background tasks when app becomes active
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)

        // Perform immediate refresh when app becomes active
        Task { [weak self] in
            await self?.performBackgroundWork()

            // Also check for new workouts to sync on foreground
            await AppLaunchSyncHandler.shared.checkAndSyncOnForeground()
        }
    }
} 