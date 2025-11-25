import Foundation
import HealthKit
import CoreLocation

class WatchWorkoutManager: NSObject, ObservableObject {
    // Published properties for UI
    @Published var distance: Double = 0.0 // in miles
    @Published var elapsedTime: TimeInterval = 0
    @Published var currentHeartRate: Double = 0
    @Published var averageHeartRate: Double = 0
    @Published var calories: Double = 0

    // HealthKit properties
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    // Timing
    private var startDate: Date?
    private var timer: Timer?

    // Heart rate tracking
    private var heartRateSamples: [Double] = []

    override init() {
        super.init()
    }

    func startWorkout(activityType: HKWorkoutActivityType, locationType: HKWorkoutSessionLocationType) {
        // Request HealthKit authorization
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!
        ]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { [weak self] success, error in
            guard success else {
                print("HealthKit authorization failed: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            DispatchQueue.main.async {
                self?.setupWorkoutSession(activityType: activityType, locationType: locationType)
            }
        }
    }

    private func setupWorkoutSession(activityType: HKWorkoutActivityType, locationType: HKWorkoutSessionLocationType) {
        // Create workout configuration
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = locationType

        do {
            // Create workout session
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()

            // Set ourselves as delegate
            session?.delegate = self
            builder?.delegate = self

            // Setup data source
            builder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            // Start the workout session
            startDate = Date()
            session?.startActivity(with: startDate)
            builder?.beginCollection(withStart: startDate!) { success, error in
                if let error = error {
                    print("Failed to begin collection: \(error.localizedDescription)")
                    return
                }

                if success {
                    print("Workout collection started successfully")
                }
            }

            // Start timer for elapsed time
            startTimer()

        } catch {
            print("Failed to create workout session: \(error.localizedDescription)")
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startDate = self.startDate else { return }
            DispatchQueue.main.async {
                self.elapsedTime = Date().timeIntervalSince(startDate)
            }
        }
    }

    func endWorkout(completion: @escaping (Bool) -> Void) {
        // Stop timer
        timer?.invalidate()
        timer = nil

        // End the workout session
        session?.end()

        // Finish building the workout
        builder?.endCollection(withEnd: Date()) { [weak self] success, error in
            guard success, error == nil else {
                print("Failed to end collection: \(error?.localizedDescription ?? "Unknown error")")
                completion(false)
                return
            }

            self?.builder?.finishWorkout { workout, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Failed to finish workout: \(error.localizedDescription)")
                        completion(false)
                    } else {
                        print("Workout saved successfully to HealthKit")
                        // Calculate average heart rate
                        if let heartRateSamples = self?.heartRateSamples, !heartRateSamples.isEmpty {
                            self?.averageHeartRate = heartRateSamples.reduce(0, +) / Double(heartRateSamples.count)
                        }
                        completion(true)
                    }
                }
            }
        }
    }

    private func updateForStatistics(_ statistics: HKStatistics?) {
        guard let statistics = statistics else { return }

        DispatchQueue.main.async {
            switch statistics.quantityType {
            case HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning):
                let distanceUnit = HKUnit.meter()
                let value = statistics.sumQuantity()?.doubleValue(for: distanceUnit) ?? 0
                self.distance = value * 0.000621371 // Convert meters to miles

            case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                let energyUnit = HKUnit.kilocalorie()
                let value = statistics.sumQuantity()?.doubleValue(for: energyUnit) ?? 0
                self.calories = value

            case HKQuantityType.quantityType(forIdentifier: .heartRate):
                let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
                let value = statistics.mostRecentQuantity()?.doubleValue(for: heartRateUnit) ?? 0
                self.currentHeartRate = value
                if value > 0 {
                    self.heartRateSamples.append(value)
                }

            default:
                break
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate
extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async {
            switch toState {
            case .running:
                print("Workout session running")
            case .ended:
                print("Workout session ended")
            case .paused:
                print("Workout session paused")
            case .prepared:
                print("Workout session prepared")
            case .stopped:
                print("Workout session stopped")
            @unknown default:
                print("Workout session in unknown state")
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed with error: \(error.localizedDescription)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate
extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // Update statistics for collected data types
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = workoutBuilder.statistics(for: quantityType)
            updateForStatistics(statistics)
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events if needed
    }
}
