import Foundation
import HealthKit
import BackgroundTasks
import WidgetKit
import UserNotifications

/// Service that handles background processing and HealthKit background delivery
/// Enables live tracking when the app is closed/backgrounded
@MainActor
final class MADBackgroundService: NSObject, ObservableObject {
    static let shared = MADBackgroundService()
    
    private let healthStore = HKHealthStore()
    private let healthManager = HealthKitManager()
    private let userManager = UserManager()
    private let notificationService = MADNotificationService.shared
    // Live workout functionality removed
    
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
        
        // Create observer query for new workouts
        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] query, completionHandler, error in
            
            if let error = error {
                completionHandler()
                return
            }
            
            // Fetch the latest workout data in background
            Task { [weak self] in
                await self?.handleNewWorkoutData()
                completionHandler()
            }
        }
        
        healthStore.execute(query)
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
        return await withCheckedContinuation { [weak self] continuation in
            guard let self = self else {
                continuation.resume(returning: false)
                return
            }
            
            // Fetch all workout data
            self.healthManager.fetchAllWorkoutData()
            
            // Give HealthKit queries time to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }
                
                // Update user data with new HealthKit data
                self.userManager.updateUserWithHealthKitData(
                    retroactiveStreak: self.healthManager.retroactiveStreak,
                    currentMiles: self.healthManager.todaysDistance,
                    totalMiles: self.healthManager.totalLifetimeMiles,
                    fastestPace: self.healthManager.fastestMilePace,
                    mostMilesInDay: self.healthManager.mostMilesInOneDay
                )
                
                continuation.resume(returning: true)
            }
        }
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
        scheduleBackgroundRefresh()
    }
    
    /// Call this from App's sceneWillEnterForeground  
    func appWillEnterForeground() {
        // Cancel any pending background tasks when app becomes active
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        
        // Perform immediate refresh when app becomes active
        Task { [weak self] in
            await self?.performBackgroundWork()
        }
    }
} 