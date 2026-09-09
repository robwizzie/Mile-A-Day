import Foundation
import HealthKit

final class WatchWorkoutManager: NSObject, ObservableObject {
    // Published UI state
    @Published var distance: Double = 0.0 // miles
    @Published var elapsedTime: TimeInterval = 0
    @Published var currentHeartRate: Double = 0
    @Published var averageHeartRate: Double = 0
    @Published var calories: Double = 0
    @Published var isPaused: Bool = false
    @Published var sessionState: HKWorkoutSessionState = .notStarted

    /// Why the workout could not be STARTED (Health unavailable, Workouts
    /// sharing denied, the session wouldn't construct). Previously each of
    /// these only printed, so the countdown finished into a tracker that read
    /// 0.00 forever with nothing on screen to explain it.
    @Published var startupFailure: String?

    /// True from the moment Stop is tapped until HealthKit has answered, so the
    /// button can show that the tap landed. A stop that takes two seconds and a
    /// stop that is never going to finish looked identical before.
    @Published var isEnding: Bool = false

    /// The workout could not be written to HealthKit. The recap says so rather
    /// than implying the miles were banked.
    @Published var saveFailed: Bool = false

    /// The session ended without the user asking (the paired iPhone ended it,
    /// watchOS reclaimed it, or it failed). The tracker follows it to the recap
    /// instead of sitting on a screen whose numbers have stopped moving.
    @Published var endedWithoutRequest: Bool = false

    // HealthKit. The store must outlive every operation started on it — a
    // released store answers nothing, silently.
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    // Timing
    private var startDate: Date?
    private var timer: Timer?

    // Teardown bookkeeping. All of it is main-thread only.
    private var endCompletions: [(Bool) -> Void] = []
    private var didStartFinalize = false
    private var endWasUserRequested = false
    private var forceFinalizeWork: DispatchWorkItem?
    private var endDeadlineWork: DispatchWorkItem?

    /// Best effort before giving up on the session reaching `.ended`, and the
    /// hard deadline after which the UI moves on regardless.
    private let forceFinalizeAfter: TimeInterval = 8
    private let endDeadlineAfter: TimeInterval = 20

    // MARK: - Lifecycle

    func startWorkout(activityType: HKWorkoutActivityType, locationType: HKWorkoutSessionLocationType) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async {
                self.startupFailure = "Health isn't available on this watch."
            }
            return
        }

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

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { [weak self] _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                // `success` only means the sheet was ANSWERED — it is true for a
                // flat refusal — so it says nothing about whether we may write.
                // Write status is the one thing Apple reports exactly, and a
                // denied Workouts switch is the difference between a workout
                // that saves and one that evaporates at Stop.
                if self.healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingDenied {
                    self.startupFailure = "Mile A Day can't save workouts. Turn on Workouts in Watch Settings ▸ Health ▸ Data Access."
                    return
                }
                if let error, self.healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .notDetermined {
                    print("[Watch] HealthKit authorization failed: \(error.localizedDescription)")
                    self.startupFailure = "Mile A Day needs permission to record workouts."
                    return
                }
                self.setupWorkoutSession(activityType: activityType, locationType: locationType)
            }
        }
    }

    private func setupWorkoutSession(activityType: HKWorkoutActivityType, locationType: HKWorkoutSessionLocationType) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = locationType

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            self.session = session
            self.builder = builder

            session.delegate = self
            builder.delegate = self

            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            let start = Date()
            startDate = start
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { [weak self] success, error in
                guard success == false || error != nil else { return }
                print("[Watch] beginCollection failed: \(error?.localizedDescription ?? "unknown")")
                DispatchQueue.main.async {
                    // Nothing is being collected, so the distance would never
                    // move and Stop would have nothing to end. Say so now
                    // rather than at the end of a walk that recorded nothing.
                    self?.startupFailure = "Couldn't start recording this workout."
                }
            }

            startTimer()
        } catch {
            print("[Watch] Failed to create workout session: \(error.localizedDescription)")
            startupFailure = "Couldn't start this workout."
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                // The builder's own clock already excludes paused time, and it
                // is the clock of the workout HealthKit will actually save — so
                // the screen can't drift away from the saved duration the way
                // the hand-rolled pause arithmetic this replaced could.
                if let builder = self.builder {
                    self.elapsedTime = builder.elapsedTime
                } else if let start = self.startDate {
                    self.elapsedTime = Date().timeIntervalSince(start)
                }
            }
        }
    }

    func pauseWorkout() {
        guard !isPaused, session != nil else { return }
        isPaused = true // optimistic; the delegate confirms from the session
        session?.pause()
    }

    func resumeWorkout() {
        guard isPaused, session != nil else { return }
        isPaused = false
        session?.resume()
    }

    // MARK: - Ending

    /// Stop the workout and save it. `completion` runs exactly once, on the main
    /// thread, and is GUARANTEED to run — see `armEndDeadline`.
    func endWorkout(completion: @escaping (Bool) -> Void) {
        endCompletions.append(completion)

        // A second Stop tap joins the teardown already in flight. Starting a
        // second one would call `endCollection` on a builder that is already
        // ending, which fails — and that failure was what the user saw.
        guard !isEnding else { return }
        isEnding = true
        endWasUserRequested = true

        timer?.invalidate()
        timer = nil

        guard let session else {
            // The session never came up (denied permission, or it threw). There
            // is nothing to save and nothing to wait for.
            finishEnding(false)
            return
        }

        armEndDeadline()

        if session.state == .ended {
            finalizeBuilder(endingAt: Date())
        } else {
            // `end()` is ASYNCHRONOUS: it walks the session to .stopped and then
            // .ended, and the builder refuses to end its collection before it
            // gets there. Calling `endCollection` right here — which is what
            // this used to do — raced that walk, and the failure was not an
            // error handed back: HealthKit simply never invoked the completion.
            // The timer above was already dead by then, so Stop read as a
            // button that did nothing. Finalizing is now driven by the .ended
            // state transition below, with the deadline as the backstop.
            session.end()
        }
    }

    /// Nothing here may leave the user on a frozen tracking screen. The first
    /// stage tries the save anyway if the session never reached `.ended`; the
    /// second gives the UI an answer regardless.
    private func armEndDeadline() {
        forceFinalizeWork?.cancel()
        endDeadlineWork?.cancel()

        let force = DispatchWorkItem { [weak self] in
            guard let self, self.isEnding, !self.didStartFinalize else { return }
            print("[Watch] Session never reached .ended — finalizing anyway")
            self.finalizeBuilder(endingAt: Date())
        }
        forceFinalizeWork = force
        DispatchQueue.main.asyncAfter(deadline: .now() + forceFinalizeAfter, execute: force)

        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.isEnding else { return }
            print("[Watch] Timed out waiting for HealthKit to finish the workout")
            self.finishEnding(false)
        }
        endDeadlineWork = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + endDeadlineAfter, execute: deadline)
    }

    /// Main-thread only.
    private func finalizeBuilder(endingAt date: Date) {
        guard !didStartFinalize else { return }
        didStartFinalize = true
        forceFinalizeWork?.cancel()
        forceFinalizeWork = nil

        guard let builder else {
            finishEnding(false)
            return
        }

        builder.endCollection(withEnd: date) { [weak self] success, error in
            guard let self else { return }
            guard success, error == nil else {
                print("[Watch] endCollection failed: \(error?.localizedDescription ?? "unknown")")
                DispatchQueue.main.async { self.finishEnding(false) }
                return
            }
            builder.finishWorkout { [weak self] workout, error in
                guard let self else { return }
                DispatchQueue.main.async {
                    if let error {
                        print("[Watch] finishWorkout failed: \(error.localizedDescription)")
                        self.finishEnding(false)
                        return
                    }
                    // Read HealthKit's own totals once more: the last delegate
                    // callback can land before the final samples are folded in,
                    // and the recap should show the numbers that were saved.
                    self.applyFinalStatistics(from: builder)
                    self.finishEnding(true)

                    if let workout {
                        // Best effort, detached from the UI: the summary screen
                        // never waits on the network, and the iPhone's sync is
                        // the backstop.
                        Task { await WatchWorkoutUploader.upload(workout) }
                    }
                }
            }
        }
    }

    /// Main-thread only. Resolves every waiting caller exactly once.
    private func finishEnding(_ success: Bool) {
        guard isEnding else { return }
        isEnding = false
        forceFinalizeWork?.cancel()
        forceFinalizeWork = nil
        endDeadlineWork?.cancel()
        endDeadlineWork = nil

        timer?.invalidate()
        timer = nil

        saveFailed = !success
        if !endWasUserRequested { endedWithoutRequest = true }

        let waiting = endCompletions
        endCompletions = []
        for completion in waiting { completion(success) }
    }

    // MARK: - Statistics

    private func updateForStatistics(_ statistics: HKStatistics?) {
        guard let statistics else { return }
        DispatchQueue.main.async { self.applyStatistics(statistics) }
    }

    private func applyFinalStatistics(from builder: HKLiveWorkoutBuilder) {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .distanceWalkingRunning, .activeEnergyBurned, .heartRate
        ]
        for identifier in identifiers {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier),
                  let statistics = builder.statistics(for: type) else { continue }
            // Applied synchronously: `finishEnding` runs right after this and
            // reveals the recap, which reads these values.
            applyStatistics(statistics)
        }
    }

    /// Main-thread only.
    private func applyStatistics(_ statistics: HKStatistics) {
        switch statistics.quantityType {
        case HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning):
            let meters = statistics.sumQuantity()?.doubleValue(for: HKUnit.meter()) ?? 0
            distance = meters * 0.000621371

        case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
            calories = statistics.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? 0

        case HKQuantityType.quantityType(forIdentifier: .heartRate):
            let hrUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
            if let latest = statistics.mostRecentQuantity()?.doubleValue(for: hrUnit) {
                currentHeartRate = latest
            }
            // HealthKit's own average over the workout. The running mean this
            // replaced averaged one reading per delegate callback, so a minute
            // that produced three callbacks counted three times against a
            // minute that produced one.
            if let average = statistics.averageQuantity()?.doubleValue(for: hrUnit), average > 0 {
                averageHeartRate = average
            }

        default:
            break
        }
    }
}

// MARK: - HKWorkoutSessionDelegate
extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async {
            self.sessionState = toState
            // Follow the SESSION, not only our own button: watchOS can pause a
            // session on its own, and a pause nobody pressed used to leave the
            // screen insisting the workout was still running.
            if toState == .paused || toState == .running {
                self.isPaused = (toState == .paused)
            }

            guard toState == .ended else { return }
            // The only correct moment to end the builder's collection — and it
            // fires whether the user pressed Stop or the session ended on its
            // own, so a workout ended from the iPhone still gets saved.
            if !self.isEnding {
                self.isEnding = true
                self.armEndDeadline()
            }
            self.finalizeBuilder(endingAt: date)
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("[Watch] Workout session failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            // A failed session will never reach .ended, so nothing else would
            // ever resolve a Stop that is already waiting on it. Save what was
            // collected rather than dropping the walk.
            if !self.isEnding {
                self.isEnding = true
                self.armEndDeadline()
            }
            self.finalizeBuilder(endingAt: Date())
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate
extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            updateForStatistics(workoutBuilder.statistics(for: quantityType))
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
}
