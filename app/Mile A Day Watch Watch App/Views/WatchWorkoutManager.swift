import Foundation
import HealthKit
import CoreLocation

final class WatchWorkoutManager: NSObject, ObservableObject {
    // Published UI state
    @Published var distance: Double = 0.0 // miles
    @Published var elapsedTime: TimeInterval = 0
    @Published var currentHeartRate: Double = 0
    @Published var averageHeartRate: Double = 0
    @Published var calories: Double = 0
    @Published var isPaused: Bool = false
    @Published var sessionState: HKWorkoutSessionState = .notStarted

    // HealthKit
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    // Timing
    private var startDate: Date?
    private var timer: Timer?
    private var pausedTime: TimeInterval = 0
    private var pauseStartDate: Date?

    // Heart rate samples for averaging
    private var heartRateSamples: [Double] = []

    // MARK: - Lifecycle

    func startWorkout(activityType: HKWorkoutActivityType, locationType: HKWorkoutSessionLocationType) {
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
                print("HealthKit authorization failed: \(error?.localizedDescription ?? "unknown")")
                return
            }
            DispatchQueue.main.async {
                self?.setupWorkoutSession(activityType: activityType, locationType: locationType)
            }
        }
    }

    private func setupWorkoutSession(activityType: HKWorkoutActivityType, locationType: HKWorkoutSessionLocationType) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = locationType

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()

            session?.delegate = self
            builder?.delegate = self

            builder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            let start = Date()
            startDate = start
            session?.startActivity(with: start)
            builder?.beginCollection(withStart: start) { _, error in
                if let error = error {
                    print("beginCollection failed: \(error.localizedDescription)")
                }
            }

            startTimer()
        } catch {
            print("Failed to create workout session: \(error.localizedDescription)")
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startDate = self.startDate else { return }
            // While paused, freeze the displayed time at the moment of pause.
            // While running, subtract all accumulated paused time.
            DispatchQueue.main.async {
                if self.isPaused, let pauseStart = self.pauseStartDate {
                    self.elapsedTime = pauseStart.timeIntervalSince(startDate) - self.pausedTime
                } else {
                    self.elapsedTime = Date().timeIntervalSince(startDate) - self.pausedTime
                }
            }
        }
    }

    func pauseWorkout() {
        guard !isPaused else { return }
        isPaused = true
        pauseStartDate = Date()
        session?.pause()
    }

    func resumeWorkout() {
        guard isPaused else { return }
        isPaused = false
        if let pauseStart = pauseStartDate {
            pausedTime += Date().timeIntervalSince(pauseStart)
        }
        pauseStartDate = nil
        session?.resume()
    }

    func endWorkout(completion: @escaping (Bool) -> Void) {
        timer?.invalidate()
        timer = nil

        // Compute average HR up front so the UI has it even if HK save fails.
        if !heartRateSamples.isEmpty {
            averageHeartRate = heartRateSamples.reduce(0, +) / Double(heartRateSamples.count)
        }

        guard let session = session, let builder = builder else {
            completion(false)
            return
        }

        session.end()

        builder.endCollection(withEnd: Date()) { [weak self] success, error in
            guard success, error == nil else {
                print("endCollection failed: \(error?.localizedDescription ?? "unknown")")
                DispatchQueue.main.async { completion(false) }
                return
            }
            builder.finishWorkout { workout, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("finishWorkout failed: \(error.localizedDescription)")
                        completion(false)
                    } else {
                        // Refresh average HR one more time in case samples arrived late.
                        if let samples = self?.heartRateSamples, !samples.isEmpty {
                            self?.averageHeartRate = samples.reduce(0, +) / Double(samples.count)
                        }
                        completion(true)
                        // Best-effort direct upload from the watch. Detached from
                        // the UI completion above so the summary screen never
                        // waits on the network. The iPhone sync is the backstop.
                        if let workout {
                            Task { await WatchWorkoutUploader.upload(workout) }
                        }
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
                let meters = statistics.sumQuantity()?.doubleValue(for: HKUnit.meter()) ?? 0
                self.distance = meters * 0.000621371

            case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                self.calories = statistics.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? 0

            case HKQuantityType.quantityType(forIdentifier: .heartRate):
                let hrUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
                let hr = statistics.mostRecentQuantity()?.doubleValue(for: hrUnit) ?? 0
                self.currentHeartRate = hr
                if hr > 0 {
                    self.heartRateSamples.append(hr)
                }
                if let avg = statistics.averageQuantity()?.doubleValue(for: hrUnit), avg > 0 {
                    self.averageHeartRate = avg
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
            self.sessionState = toState
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error.localizedDescription)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate
extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = workoutBuilder.statistics(for: quantityType)
            updateForStatistics(statistics)
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
}
