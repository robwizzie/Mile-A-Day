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
            print("[Background] Scheduled background refresh")
        } catch {
            print("[Background] Failed to schedule background refresh: \(error)")
        }
    }
    
    // MARK: - HealthKit Background Delivery
    
    private func setupBackgroundDelivery() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        // Set up background delivery for workout data
        let workoutType = HKObjectType.workoutType()
        
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { [weak self] success, error in
            if success {
                print("[Background] HealthKit background delivery enabled")
                self?.setupWorkoutObserver()
            } else {
                print("[Background] Failed to enable HealthKit background delivery: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    private func setupWorkoutObserver() {
        let workoutType = HKObjectType.workoutType()
        
        // Create observer query for new workouts
        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] query, completionHandler, error in
            
            if let error = error {
                print("[Background] Workout observer error: \(error)")
                completionHandler()
                return
            }
            
            print("[Background] New workout detected")
            
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
        print("[Background] Background refresh task started")
        
        // Schedule the next background refresh
        scheduleBackgroundRefresh()
        
        // Set expiration handler
        task.expirationHandler = {
            print("[Background] Background task expired")
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
            print("[Background] HealthKit not authorized")
            return
        }
        
        await performBackgroundWork()
    }
    
    @MainActor
    private func performBackgroundWork() async {
        print("[Background] Performing background work...")
        
        // Fetch latest workout data
        let success = await fetchLatestWorkoutData()
        
        if success {
            // Check if user completed their mile goal
            checkForMileCompletion()
            
            // Update widgets
            updateWidgets()
            
            print("[Background] Background work completed successfully")
        } else {
            print("[Background] Background work failed")
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
        
        // Check if user just completed their goal
        if todaysDistance >= currentUser.goalMiles && !currentUser.isStreakActiveToday {
            print("[Background] Mile goal completed! Sending notification...")
            
            // Send completion notification
            notificationService.sendMileCompletedNotification()
            
            // Update user completion status
            userManager.completeRun(miles: todaysDistance)
            
            // Update daily reminder to congratulatory message
            notificationService.updateDailyReminder(completed: true)
        }
    }
    
    private func updateWidgets() {
        // Update widget data store
        let user = userManager.currentUser
        let miles = healthManager.todaysDistance
        
        WidgetDataStore.save(todayMiles: miles, goal: user.goalMiles)
        WidgetDataStore.save(streak: user.streak)
        
        print("[Background] Widgets updated - Miles: \(miles), Goal: \(user.goalMiles), Streak: \(user.streak)")
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