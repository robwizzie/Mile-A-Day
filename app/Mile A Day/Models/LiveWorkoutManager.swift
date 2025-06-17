import Foundation
import HealthKit
import WidgetKit

/// Manages real-time workout tracking using periodic HealthKit queries
/// Provides live updates during active workouts for iOS apps
final class LiveWorkoutManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = LiveWorkoutManager()
    
    private let healthStore = HKHealthStore()
    
    // Live workout state
    @Published var isWorkoutActive = false
    @Published var currentWorkoutDistance: Double = 0.0
    @Published var currentWorkoutType: HKWorkoutActivityType?
    @Published var workoutStartTime: Date?
    
    // Monitoring timer
    private var monitoringTimer: Timer?
    private var lastKnownWorkoutCount = 0
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public API
    
    /// Initialize live workout monitoring
    func startLiveWorkoutMonitoring() {
        print("[LiveWorkout] Starting live workout monitoring...")
        startPeriodicChecking()
    }
    
    /// Stop live workout monitoring
    func stopLiveWorkoutMonitoring() {
        print("[LiveWorkout] Stopping live workout monitoring...")
        stopPeriodicChecking()
        Task { @MainActor in
            cleanupWorkoutSession()
        }
    }
    
    // MARK: - Timer-Based Monitoring
    
    private func startPeriodicChecking() {
        // Check every 10 seconds for new workouts
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { @Sendable [weak self] _ in
            Task {
                await self?.checkForActiveWorkouts()
            }
        }
        
        // Also check immediately
        Task {
            await checkForActiveWorkouts()
        }
    }
    
    private func stopPeriodicChecking() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    // MARK: - Workout Detection
    
    private func checkForActiveWorkouts() async {
        let now = Date()
        let fiveMinutesAgo = now.addingTimeInterval(-300)
        
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        let datePredicate = HKQuery.predicateForSamples(withStart: fiveMinutesAgo, end: now, options: .strictStartDate)
        let workoutPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [typePredicate, datePredicate])
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: workoutPredicate,
                limit: 5,
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
        // Look for workouts that started recently and might still be active
        let potentialActiveWorkouts = workouts.filter { workout in
            let timeSinceStart = currentTime.timeIntervalSince(workout.startDate)
            let timeSinceEnd = currentTime.timeIntervalSince(workout.endDate)
            
            // Consider active if started within 2 hours and ended within 30 seconds (still updating)
            return timeSinceStart < 7200 && timeSinceEnd < 30
        }
        
        if let activeWorkout = potentialActiveWorkouts.first {
            handleActiveWorkout(activeWorkout)
        } else if isWorkoutActive {
            // No active workout found, cleanup
            cleanupWorkoutSession()
        }
    }
    
    @MainActor
    private func handleActiveWorkout(_ workout: HKWorkout) {
        let wasActive = isWorkoutActive
        
        isWorkoutActive = true
        currentWorkoutType = workout.workoutActivityType
        workoutStartTime = workout.startDate
        
        if let distance = workout.totalDistance {
            currentWorkoutDistance = distance.doubleValue(for: HKUnit.mile())
        }
        
        if !wasActive {
            print("[LiveWorkout] Started tracking active \(workout.workoutActivityType.name) workout")
        }
        
        updateLiveWorkoutData()
    }
    
    @MainActor
    private func cleanupWorkoutSession() {
        let wasActive = isWorkoutActive
        
        isWorkoutActive = false
        currentWorkoutType = nil
        workoutStartTime = nil
        currentWorkoutDistance = 0.0
        
        if wasActive {
            print("[LiveWorkout] Workout session ended")
            // Clear live workout state from widgets
            WidgetDataStore.saveLiveWorkout(isActive: false, currentDistance: 0.0)
            
            // Final widget update
            WidgetCenter.shared.reloadTimelines(ofKind: "TodayProgressWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "StreakCountWidget")
        }
    }
    
    // MARK: - Live Data Updates
    
    @MainActor
    private func updateLiveWorkoutData() {
        // Calculate total miles for today (including current workout)
        let existingMiles = getTodaysCompletedMiles()
        let totalMilesForToday = existingMiles + currentWorkoutDistance
        
        print("[LiveWorkout] Updating live data - Current workout: \(currentWorkoutDistance), Total today: \(totalMilesForToday)")
        
        // Update widget data store with live data
        let goalMiles = WidgetDataStore.load().goal
        WidgetDataStore.save(todayMiles: totalMilesForToday, goal: goalMiles)
        WidgetDataStore.saveLiveWorkout(isActive: isWorkoutActive, currentDistance: currentWorkoutDistance)
        
        // Reload widgets to show live updates
        WidgetCenter.shared.reloadTimelines(ofKind: "TodayProgressWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "StreakCountWidget")
    }
    
    private func getTodaysCompletedMiles() -> Double {
        // Return a simple baseline - this will be refined by the HealthKitManager
        return WidgetDataStore.load().miles
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