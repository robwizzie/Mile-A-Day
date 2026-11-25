import Foundation
import HealthKit
import Observation
import WatchConnectivity

/// The live link between a run the iPhone records and the paired Watch
/// (Run Plans v2): the Watch is the heart-rate source and mirrors the plan
/// screen and its haptics; the phone stays the source of distance and pace
/// (GPS, pedometer or treadmill), of the plan coach, and of the SAVED
/// workout.
///
/// Apple's multi-device workout pattern (iOS 17 / watchOS 10, WWDC23 "Build
/// a multi-device workout app"):
/// 1. `runStarted` → `HKHealthStore.startWatchApp(with:)`. watchOS launches
///    the Watch app, whose `WKApplicationDelegate.handle(_:)` starts a
///    heart-rate-only `HKWorkoutSession` (`WatchWorkoutManager.startCompanion`)
///    and calls `startMirroringToCompanionDevice`.
/// 2. The mirrored session arrives in `workoutSessionMirroringStartHandler`,
///    set at launch (`install`, from `AppDelegate`) so it is never missed.
///    It can arrive again after a dropped connection, each time a new
///    session object.
/// 3. Both sides talk with `WorkoutMirrorMessage` (HealthKitManager.swift)
///    over `sendToRemoteWorkoutSession(data:)`. Pause/resume ride the
///    session itself: `pause()`/`resume()` on either side change both, and
///    each side follows the other's state change.
/// 4. The phone saves its workout exactly as before. The Watch's session
///    ends with `discardWorkout()`, so Health never gets a second,
///    Watch-sourced copy of the run.
///
/// Nothing here is required: no Watch, no Watch app, a Watch that never
/// answers — the run goes on with pace and feel, and the plan card says
/// "Watch not connected". Only plan runs start the Watch (not every walk).
///
/// HealthKit calls the delegate and the start handler on background queues;
/// every one hops to the main actor before touching state.
@Observable
final class WatchWorkoutLink: NSObject {
    static let shared = WatchWorkoutLink()

    enum LinkState: Equatable {
        /// No phone run asked for the Watch.
        case off
        /// Asked the Watch to start; waiting for its mirrored session.
        case starting
        /// The Watch's session is mirrored here.
        case connected
        /// No paired Watch with the app, it said no, or it never answered.
        case unavailable
    }

    /// What the plan card's heart-rate tile says when there's no bpm.
    private(set) var state: LinkState = .off

    /// Something the runner did on the Watch that the tracker must follow.
    enum RemoteCommand: Equatable {
        case pause
        case resume
        case end
    }

    /// Latest bpm from the Watch, nil once it's 20 s old (the coach's 15 s
    /// window then empties, and HR cues stop).
    var heartRate: Double? {
        guard let at = lastHeartRateAt, Date().timeIntervalSince(at) < 20 else { return nil }
        return lastHeartRate
    }

    @ObservationIgnored private var lastHeartRate: Double?
    @ObservationIgnored private var lastHeartRateAt: Date?
    @ObservationIgnored private var session: HKWorkoutSession?
    /// A phone run that wants the Watch is live.
    @ObservationIgnored private var runActive = false
    /// The phone ended the run (its own Stop): a session ending after this
    /// is ours, not the runner's on the Watch.
    @ObservationIgnored private var endRequested = false
    /// The pause state both sessions are known to be in. A state change that
    /// matches it is our own echo.
    @ObservationIgnored private var sentPaused = false
    @ObservationIgnored private var pendingCommand: RemoteCommand?
    @ObservationIgnored private var lastSentAt = Date.distantPast
    @ObservationIgnored private var installed = false
    @ObservationIgnored private var startAttempt = 0

    private override init() { super.init() }

    private var healthStore: HKHealthStore { HealthKitManager.shared.healthStore }

    // MARK: Launch

    /// From `application(_:didFinishLaunchingWithOptions:)`: HealthKit may
    /// launch the app in the background just to hand over a mirrored session.
    func install() {
        guard !installed, HKHealthStore.isHealthDataAvailable() else { return }
        installed = true
        healthStore.workoutSessionMirroringStartHandler = { mirrored in
            // Called on an arbitrary background queue. The session object is
            // only handed over, never used here.
            nonisolated(unsafe) let handed = mirrored
            Task { @MainActor in WatchWorkoutLink.shared.adopt(handed) }
        }
    }

    // MARK: Tracker hooks

    /// A plan run started on the phone (or a relaunched tracker restored
    /// one). Asks the paired Watch to start its heart-rate session.
    func runStarted(activityType: HKWorkoutActivityType, locationType: HKWorkoutSessionLocationType) {
        runActive = true
        endRequested = false
        pendingCommand = nil
        lastHeartRate = nil
        lastHeartRateAt = nil
        if session != nil {
            // The Watch is already mirrored (a relaunch it reconnected to).
            state = .connected
            return
        }
        guard Self.watchAppReachable else {
            state = .unavailable
            return
        }
        state = .starting
        startAttempt += 1
        let attempt = startAttempt
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = locationType
        healthStore.startWatchApp(with: configuration) { success, error in
            guard !success || error != nil else { return }
            let reason = error?.localizedDescription ?? "unknown"
            Task { @MainActor in WatchWorkoutLink.shared.startFailed(attempt: attempt, reason: reason) }
        }
        // The Watch may never answer (off the wrist, out of range, asleep
        // without the app): stop saying "connecting" after a while.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.runActive, self.startAttempt == attempt, self.state == .starting else { return }
            self.state = .unavailable
        }
    }

    /// Whatever the runner did on the Watch since the last tick (pause,
    /// resume, end). Take it BEFORE `tick`, so `tick` sees the tracker's
    /// new pause state and doesn't send the old one back.
    func takeRemoteCommand() -> RemoteCommand? {
        defer { pendingCommand = nil }
        return pendingCommand
    }

    /// The tracker's 1 Hz tick: follow the phone's pause on the Watch and
    /// send the run (every 2 s, at once with plan events).
    func tick(miles: Double, elapsed: Double, paused: Bool, events: [PlanRunEvent]) {
        guard runActive, let session else { return }
        if paused != sentPaused {
            sentPaused = paused
            if paused, session.state == .running {
                session.pause()
            } else if !paused, session.state == .paused {
                session.resume()
            }
        }
        guard !events.isEmpty || Date().timeIntervalSince(lastSentAt) >= 2 else { return }
        lastSentAt = Date()
        let coach = PlanRunCoachV2.shared
        send(.run(WorkoutMirrorRun(
            at: Date(), miles: miles, elapsed: elapsed, paused: paused,
            planDate: coach.day?.date, status: coach.status, pace: coach.pace,
            events: events)))
    }

    /// The phone run ended (Stop, force end, or cleanup). Tells the Watch,
    /// which ends and discards its session. Safe to call more than once.
    func runEnded() {
        guard runActive || session != nil else { return }
        runActive = false
        endRequested = true
        pendingCommand = nil
        if let ending = session {
            send(.ended)
            // Backstop for a Watch that missed the message: end the mirrored
            // session (that ends the Watch's too, which then discards).
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if ending.state != .ended { ending.end() }
            }
        }
        session = nil
        state = .off
        lastHeartRate = nil
        lastHeartRateAt = nil
    }

    // MARK: Internals

    /// A paired Watch with the Mile A Day app. `MADWatchBridge` activates the
    /// session at launch; before that answers, assume no Watch.
    private static var watchAppReachable: Bool {
        guard WCSession.isSupported() else { return false }
        let wc = WCSession.default
        return wc.activationState == .activated && wc.isPaired && wc.isWatchAppInstalled
    }

    private func startFailed(attempt: Int, reason: String) {
        print("[WatchWorkoutLink] startWatchApp failed: \(reason)")
        guard runActive, attempt == startAttempt, session == nil else { return }
        state = .unavailable
    }

    private func adopt(_ mirrored: HKWorkoutSession) {
        mirrored.delegate = self
        // No phone run wants it (the tracker ended while the Watch was
        // reconnecting, or this process died and nothing is active): tell
        // the Watch to stand down rather than leave it recording.
        let trackerActive = InProgressWorkoutStore.load()?.isActive == true
        guard runActive || trackerActive else {
            if let data = WorkoutMirrorMessage.ended.encoded {
                mirrored.sendToRemoteWorkoutSession(data: data) { _, _ in }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if mirrored.state != .ended { mirrored.end() }
            }
            return
        }
        session = mirrored
        sentPaused = mirrored.state == .paused
        state = .connected
        print("[WatchWorkoutLink] mirrored session connected")
        guard !runActive else { return }
        // Arrived before a relaunched tracker restored its run. If no plan
        // run claims it soon (the active workout isn't one), stand it down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self, !self.runActive, let held = self.session, held === mirrored else { return }
            self.runEnded()
        }
    }

    private func send(_ message: WorkoutMirrorMessage) {
        guard let session, let data = message.encoded else { return }
        session.sendToRemoteWorkoutSession(data: data) { _, error in
            if let error { print("[WatchWorkoutLink] send failed: \(error.localizedDescription)") }
        }
    }

    private func isCurrent(_ id: ObjectIdentifier) -> Bool {
        guard let session else { return false }
        return ObjectIdentifier(session) == id
    }

    private func sessionChanged(_ id: ObjectIdentifier, to toState: HKWorkoutSessionState) {
        guard isCurrent(id) else { return }
        switch toState {
        case .paused:
            if runActive, !sentPaused {
                sentPaused = true
                pendingCommand = .pause
            }
        case .running:
            if runActive, sentPaused {
                sentPaused = false
                pendingCommand = .resume
            }
        case .stopped, .ended:
            // The Watch's session is over. Only the runner's End on the Watch
            // (the `.ended` message) ends the phone run; a session watchOS
            // reclaimed or that failed only takes the heart rate away.
            dropSession()
        default:
            break
        }
    }

    private func received(_ data: [Data], from id: ObjectIdentifier) {
        guard isCurrent(id) else { return }
        for item in data {
            switch WorkoutMirrorMessage.decode(item) {
            case .heartRate(let bpm, let at)?:
                let when = min(at, Date())
                if when > (lastHeartRateAt ?? .distantPast) {
                    lastHeartRate = bpm
                    lastHeartRateAt = when
                }
            case .ended?:
                if runActive, !endRequested { pendingCommand = .end }
            default:
                break
            }
        }
    }

    private func dropSession() {
        session = nil
        lastHeartRate = nil
        lastHeartRateAt = nil
        state = runActive ? .unavailable : .off
    }

    fileprivate func disconnected(_ id: ObjectIdentifier, reason: String?) {
        guard isCurrent(id) else { return }
        if let reason { print("[WatchWorkoutLink] disconnected: \(reason)") }
        // The Watch reconnects on its own when it can; a new session then
        // arrives through the start handler.
        dropSession()
    }
}

// MARK: - HKWorkoutSessionDelegate (background queues → main actor)

extension WatchWorkoutLink: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        let id = ObjectIdentifier(workoutSession)
        Task { @MainActor in WatchWorkoutLink.shared.sessionChanged(id, to: toState) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let id = ObjectIdentifier(workoutSession)
        let reason = error.localizedDescription
        Task { @MainActor in WatchWorkoutLink.shared.disconnected(id, reason: reason) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let id = ObjectIdentifier(workoutSession)
        Task { @MainActor in WatchWorkoutLink.shared.received(data, from: id) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didDisconnectFromRemoteDeviceWithError error: Error?) {
        let id = ObjectIdentifier(workoutSession)
        let reason = error?.localizedDescription
        Task { @MainActor in WatchWorkoutLink.shared.disconnected(id, reason: reason) }
    }
}
