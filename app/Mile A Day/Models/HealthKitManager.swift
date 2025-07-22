import Foundation
import HealthKit
import WidgetKit

class HealthKitManager: ObservableObject {
    let healthStore = HKHealthStore()
    
    @Published var isAuthorized = false
    @Published var todaysDistance: Double = 0.0
    @Published var recentWorkouts: [HKWorkout] = []
    @Published var totalLifetimeMiles: Double = 0.0
    @Published var fastestMilePace: TimeInterval = 0.0
    @Published var mostMilesInOneDay: Double = 0.0
    @Published var retroactiveStreak: Int = 0
    @Published var mostMilesWorkouts: [HKWorkout] = []
    
    // Request authorization to access HealthKit data
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        
        // Define the types we want to read from HealthKit
        let types: Set = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        
        healthStore.requestAuthorization(toShare: nil, read: types) { success, error in
            DispatchQueue.main.async {
                self.isAuthorized = success
                
                // Enable background delivery for workouts when authorized
                if success {
                    self.enableBackgroundDelivery()
                }
                
                completion(success)
            }
        }
    }
    
    // Enable background delivery for HealthKit data
    private func enableBackgroundDelivery() {
        let workoutType = HKObjectType.workoutType()
        
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { success, error in
            if success {
                print("[HealthKit] Background delivery enabled for workouts")
            } else {
                print("[HealthKit] Failed to enable background delivery: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    // Fetch today's running/walking distance from workouts only
    func fetchTodaysDistance() {
        guard isAuthorized else { return }
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        
        // Always use current time for distance calculation
        let endTime = now
        
        // Look for both running and walking workouts
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        
        // Combine the predicates to find running or walking workouts from today
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        let todayPredicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endTime, options: .strictStartDate)
        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [compoundPredicate, todayPredicate])
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: finalPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self = self, let workouts = samples as? [HKWorkout], !workouts.isEmpty else {
                DispatchQueue.main.async {
                    self?.todaysDistance = 0.0
                    // Get current goal from widget store or default to 1.0
                    let currentGoal = WidgetDataStore.load().goal
                    let safeGoal = currentGoal > 0 ? currentGoal : 1.0
                    
                    // Use unified progress calculation
                    WidgetDataStore.save(todayMiles: 0, goal: safeGoal, liveWorkoutDistance: 0.0)
                }
                return
            }
            
            // Calculate total distance from all workouts
            var totalMiles: Double = 0.0
            
            for workout in workouts {
                if let distance = workout.totalDistance {
                    let miles = distance.doubleValue(for: HKUnit.mile())
                    totalMiles += miles
                }
            }
            
            DispatchQueue.main.async {
                self.todaysDistance = totalMiles
                self.recentWorkouts = workouts
                // Get current goal from widget store or default to 1.0
                let currentGoal = WidgetDataStore.load().goal
                let safeGoal = currentGoal > 0 ? currentGoal : 1.0
                
                // Use unified progress calculation - no live workout distance here since this is base HealthKit data
                WidgetDataStore.save(todayMiles: totalMiles, goal: safeGoal, liveWorkoutDistance: 0.0)
            }
        }
        
        healthStore.execute(query)
    }
    
    // Fetch recent running/walking workouts
    func fetchRecentWorkouts() {
        guard isAuthorized else { return }
        
        // Look for both running and walking workouts
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: compoundPredicate,
            limit: 10,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] query, samples, error in
            guard let self = self, let workouts = samples as? [HKWorkout] else { return }
            
            DispatchQueue.main.async {
                self.recentWorkouts = workouts
            }
        }
        
        healthStore.execute(query)
    }
    
    // Helper method to check if user has completed their mile goal today
    // Includes a small offset (0.05 miles) for rounding
    func hasCompletedMileToday() -> Bool {
        return todaysDistance >= 0.95
    }
    
    // Get distance in miles from a workout
    func distanceInMiles(from workout: HKWorkout) -> Double {
        guard let distance = workout.totalDistance else { return 0 }
        return distance.doubleValue(for: HKUnit.mile())
    }
    
    // MARK: - New Methods for Enhanced Tracking
    
    // Fetch total lifetime miles from all running and walking workouts
    func fetchTotalLifetimeMiles() {
        guard isAuthorized else { return }
        
        // Look for both running and walking workouts
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: compoundPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [weak self] _, samples, error in
            guard let self = self, let workouts = samples as? [HKWorkout] else { return }
            
            var totalMiles: Double = 0.0
            
            for workout in workouts {
                if let distance = workout.totalDistance {
                    let miles = distance.doubleValue(for: HKUnit.mile())
                    totalMiles += miles
                }
            }
            
            DispatchQueue.main.async {
                self.totalLifetimeMiles = totalMiles
            }
        }
        
        healthStore.execute(query)
    }
    
    // Calculate personal records and retroactive streak
    func calculatePersonalRecords() {
        guard isAuthorized else { return }
        
        // Look for both running and walking workouts
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [runningPredicate, walkingPredicate])
        
        // Sort by date to calculate streak
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: compoundPredicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self = self, let workouts = samples as? [HKWorkout] else { return }
            
            // Track fastest mile pace
            var fastestPace: TimeInterval = .infinity
            
            // Track most miles in a day
            var mostMilesInDay: Double = 0.0
            var mostMilesWorkouts: [HKWorkout] = []
            
            // Group workouts by day for streak calculation
            var workoutsByDay: [Date: [HKWorkout]] = [:]
            
            for workout in workouts {
                // Calculate pace
                if let distance = workout.totalDistance {
                    let miles = distance.doubleValue(for: HKUnit.mile())
                    if miles >= 0.95 { // Only consider workouts at least a mile
                        let paceMinutesPerMile = workout.duration / 60 / miles
                        
                        if paceMinutesPerMile < fastestPace && paceMinutesPerMile > 0 {
                            fastestPace = paceMinutesPerMile
                        }
                    }
                }
                
                // Group by day for most miles and streak calculation
                let calendar = Calendar.current
                let dateComponents = calendar.dateComponents([.year, .month, .day], from: workout.endDate)
                if let date = calendar.date(from: dateComponents) {
                    if workoutsByDay[date] == nil {
                        workoutsByDay[date] = []
                    }
                    workoutsByDay[date]?.append(workout)
                }
            }
            
            // Calculate most miles in a day
            for (_, dayWorkouts) in workoutsByDay {
                var totalMilesForDay: Double = 0.0
                
                for workout in dayWorkouts {
                    if let distance = workout.totalDistance {
                        let miles = distance.doubleValue(for: HKUnit.mile())
                        totalMilesForDay += miles
                    }
                }
                
                if totalMilesForDay > mostMilesInDay {
                    mostMilesInDay = totalMilesForDay
                    mostMilesWorkouts = dayWorkouts
                }
            }
            
            // Calculate retroactive streak
            let streak = self.calculateRetroactiveStreak(workoutsByDay: workoutsByDay)
            
            DispatchQueue.main.async {
                self.fastestMilePace = fastestPace == .infinity ? 0 : fastestPace
                self.mostMilesInOneDay = mostMilesInDay
                self.mostMilesWorkouts = mostMilesWorkouts
                self.retroactiveStreak = streak
            }
        }
        
        healthStore.execute(query)
    }
    
    // Helper to calculate retroactive streak from workout data
    private func calculateRetroactiveStreak(workoutsByDay: [Date: [HKWorkout]]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        
        // Get all days with qualifying workouts (at least 0.95 miles)
        let daysWithQualifyingWorkouts = workoutsByDay.filter { (date, workouts) in
            let totalMilesForDay = workouts.reduce(0.0) { total, workout in
                if let distance = workout.totalDistance {
                    return total + distance.doubleValue(for: HKUnit.mile())
                }
                return total
            }
            return totalMilesForDay >= 0.95
        }.keys.sorted(by: >)
        
        guard !daysWithQualifyingWorkouts.isEmpty else { return 0 }
        
        // Calculate current streak
        var currentStreak = 0
        var checkDate = yesterday // Start checking from yesterday
        
        // If we have completed today, include it in the streak
        if daysWithQualifyingWorkouts.contains(today) {
            currentStreak += 1
        }
        
        // Check previous days
        while true {
            if daysWithQualifyingWorkouts.contains(checkDate) {
                currentStreak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                // Break if we find a day without a qualifying workout
                break
            }
        }
        
        return currentStreak
    }
    
    // Function to fetch all workout data in one call
    func fetchAllWorkoutData() {
        fetchTodaysDistance()
        fetchRecentWorkouts()
        fetchTotalLifetimeMiles()
        calculatePersonalRecords()
    }
    
    // Format pace in minutes:seconds per mile
    func formatPace(minutesPerMile: TimeInterval) -> String {
        guard minutesPerMile > 0 else { return "N/A" }
        
        let totalSeconds = Int(minutesPerMile * 60)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
} 