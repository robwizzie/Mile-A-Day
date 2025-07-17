import Foundation
import HealthKit
import WidgetKit
import BackgroundTasks
import UIKit

/// Manages real-time workout tracking with perfect synchronization
/// Provides live updates across all app components and widgets
final class LiveWorkoutManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = LiveWorkoutManager()
    
    private let healthStore = HKHealthStore()
    
    // Live workout state
    @Published var isWorkoutActive = false
    @Published var currentWorkoutDistance: Double = 0.0
    @Published var currentWorkoutType: HKWorkoutActivityType?
    @Published var workoutStartTime: Date?
    @Published var liveProgress: Double = 0.0 // Real-time progress percentage
    @Published var isGoalReached: Bool = false // Real-time goal status
    
    // Real-time monitoring with increased frequency
    private var monitoringTimer: Timer?
    private var lastUpdateTime: Date = Date()
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
    
    private override init() {
        super.init()
        setupBackgroundNotifications()
    }
    
    // MARK: - Public API
    
    /// Start real-time workout monitoring with background support
    func startLiveWorkoutMonitoring() {
        print("[LiveWorkout] Starting REAL-TIME workout monitoring with background support...")
        startRealTimeMonitoring()
        requestBackgroundProcessing()
    }
    
    /// Stop live workout monitoring
    func stopLiveWorkoutMonitoring() {
        print("[LiveWorkout] Stopping real-time workout monitoring...")
        stopRealTimeMonitoring()
        endBackgroundTask()
        Task { @MainActor in
            cleanupWorkoutSession()
        }
    }
    
    // MARK: - Real-Time Monitoring (1-second intervals for maximum responsiveness)
    
    private func startRealTimeMonitoring() {
        // Check every 0.5 seconds for MAXIMUM real-time responsiveness
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { @Sendable [weak self] _ in
            Task {
                await self?.checkForActiveWorkouts()
            }
        }
        
        // Also check immediately
        Task {
            await checkForActiveWorkouts()
        }
        
        print("[LiveWorkout] 🚀 Real-time monitoring started with 0.5-second intervals")
    }
    
    private func stopRealTimeMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    // MARK: - Background Processing Support
    
    private func setupBackgroundNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        if isWorkoutActive {
            requestBackgroundProcessing()
        }
    }
    
    @objc private func appWillEnterForeground() {
        endBackgroundTask()
        if isWorkoutActive {
            startRealTimeMonitoring()
        }
    }
    
    private func requestBackgroundProcessing() {
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "LiveWorkoutTracking") {
            self.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskIdentifier != UIBackgroundTaskIdentifier.invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
        }
    }
    
    // MARK: - Enhanced Workout Detection
    
    private func checkForActiveWorkouts() async {
        let now = Date()
        let threeMinutesAgo = now.addingTimeInterval(-180) // Reduced window for more recent data
        
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        let datePredicate = HKQuery.predicateForSamples(withStart: threeMinutesAgo, end: now, options: .strictStartDate)
        let workoutPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [typePredicate, datePredicate])
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: workoutPredicate,
                limit: 3,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { @Sendable [weak self] _, samples, error in
                guard let self = self, let workouts = samples as? [HKWorkout] else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    self.processRecentWorkouts(workouts, currentTime: now)
                }
                
                continuation.resume()
            }
            
            healthStore.execute(query)
        }
    }
    
    @MainActor
    private func processRecentWorkouts(_ workouts: [HKWorkout], currentTime: Date) {
        // Look for workouts that are currently active (very recent end times)
        let activeWorkouts = workouts.filter { workout in
            let timeSinceStart = currentTime.timeIntervalSince(workout.startDate)
            let timeSinceEnd = currentTime.timeIntervalSince(workout.endDate)
            
            // Consider active if started within 3 hours and ended within 5 seconds (still updating)
            return timeSinceStart < 10800 && timeSinceEnd < 5
        }
        
        if let activeWorkout = activeWorkouts.first {
            handleActiveWorkout(activeWorkout)
        } else if isWorkoutActive {
            // No active workout found, cleanup
            cleanupWorkoutSession()
        }
    }
    
    @MainActor
    private func handleActiveWorkout(_ workout: HKWorkout) {
        let wasActive = isWorkoutActive
        let previousDistance = currentWorkoutDistance
        let previousProgress = liveProgress
        
        isWorkoutActive = true
        currentWorkoutType = workout.workoutActivityType
        workoutStartTime = workout.startDate
        
        if let distance = workout.totalDistance {
            currentWorkoutDistance = distance.doubleValue(for: HKUnit.mile())
        }
        
        // Calculate real-time progress and goal status
        let baseMiles = getTodaysBaseMiles()
        let totalDistance = baseMiles + currentWorkoutDistance
        let goal = getCurrentGoal()
        
        liveProgress = ProgressCalculator.calculateProgress(current: totalDistance, goal: goal)
        isGoalReached = ProgressCalculator.isGoalCompleted(current: totalDistance, goal: goal)
        
        // Log significant changes
        if !wasActive {
            print("[LiveWorkout] 🔴 LIVE MODE ACTIVATED - \(workout.workoutActivityType.name)")
            // Send workout start notification
            Task { @MainActor in
                MADNotificationService.shared.sendWorkoutStartNotification()
            }
        } else if abs(currentWorkoutDistance - previousDistance) > 0.005 || abs(liveProgress - previousProgress) > 0.01 {
            print("[LiveWorkout] 📊 REAL-TIME UPDATE - Distance: \(String(format: "%.3f", currentWorkoutDistance)), Progress: \(String(format: "%.1f", liveProgress * 100))%")
        }
        
        // Update all components in real-time
        updateAllComponentsRealTime()
    }
    
    @MainActor
    private func cleanupWorkoutSession() {
        let wasActive = isWorkoutActive
        
        isWorkoutActive = false
        currentWorkoutType = nil
        workoutStartTime = nil
        currentWorkoutDistance = 0.0
        liveProgress = 0.0
        isGoalReached = false
        
        if wasActive {
            print("[LiveWorkout] 🔴 LIVE MODE DEACTIVATED - Finalizing data")
            // Final update to clear live state
            updateAllComponentsRealTime()
        }
    }
    
    // MARK: - Real-Time Component Updates
    
    @MainActor
    private func updateAllComponentsRealTime() {
        let baseMiles = getTodaysBaseMiles()
        let goal = getCurrentGoal()
        
        // Validate data before updating
        let validDistance = max(0.0, currentWorkoutDistance)
        let validBaseMiles = max(0.0, baseMiles)
        let validGoal = max(0.1, goal) // Minimum reasonable goal
        
        // Update widget data store with validated real-time data
        WidgetDataStore.save(todayMiles: validBaseMiles, goal: validGoal, liveWorkoutDistance: validDistance)
        WidgetDataStore.saveLiveWorkout(isActive: isWorkoutActive, currentDistance: validDistance)
        
        // Force immediate widget timeline reloads during live tracking
        if isWorkoutActive {
            WidgetCenter.shared.reloadAllTimelines()
            print("[LiveWorkout] 🔄 Forced immediate widget reload for live tracking")
        }
        
        // Validate and repair widget data if needed
        let wasRepaired = WidgetDataStore.validateAndRepair()
        if wasRepaired {
            print("[LiveWorkout] ⚠️ Widget data was repaired during live update")
        }
        
        print("[LiveWorkout] 📱 Live update - Base: \(validBaseMiles), Live: \(validDistance), Goal: \(validGoal), Active: \(isWorkoutActive)")
        
        // Update last update time
        lastUpdateTime = Date()
    }
    
    private func getTodaysBaseMiles() -> Double {
        let data = WidgetDataStore.load()
        return max(0.0, data.miles) // Ensure non-negative
    }
    
    private func getCurrentGoal() -> Double {
        let data = WidgetDataStore.load()
        return max(0.1, data.goal) // Ensure minimum reasonable goal
    }
    
    // MARK: - Public State Access for Real-Time UI
    
    /// Get current total distance including live workout
    func getCurrentTotalDistance() -> Double {
        return getTodaysBaseMiles() + (isWorkoutActive ? currentWorkoutDistance : 0.0)
    }
    
    /// Get real-time progress percentage (0.0 to 1.0)
    func getCurrentProgress() -> Double {
        if isWorkoutActive {
            return liveProgress
        }
        let totalDistance = getCurrentTotalDistance()
        let goal = getCurrentGoal()
        return ProgressCalculator.calculateProgress(current: totalDistance, goal: goal)
    }
    
    /// Check if goal is currently completed
    func isCurrentGoalCompleted() -> Bool {
        if isWorkoutActive {
            return isGoalReached
        }
        let totalDistance = getCurrentTotalDistance()
        let goal = getCurrentGoal()
        return ProgressCalculator.isGoalCompleted(current: totalDistance, goal: goal)
    }
    
    /// Get live workout state for UI components
    func getLiveWorkoutState() -> (isActive: Bool, distance: Double, progress: Double, goalReached: Bool) {
        return (isWorkoutActive, currentWorkoutDistance, liveProgress, isGoalReached)
    }
    
    // MARK: - Cleanup
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopRealTimeMonitoring()
        endBackgroundTask()
    }
}

// MARK: - HKWorkoutActivityType Extension

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running:
            return "Running"
        case .walking:
            return "Walking"
        default:
            return "Workout"
        }
    }
} 