import Foundation
import HealthKit
import CoreLocation

/// Lightweight, persistent representation of an in‑progress workout.
/// This ensures we can always restore the user's active workout UI/state
/// after app backgrounding, relaunch, or when opening from a Live Activity.
struct InProgressWorkoutState: Codable {
    var isActive: Bool
    var isPaused: Bool
    var startTime: Date
    var elapsedTime: TimeInterval
    var pausedTime: TimeInterval // Total time spent paused
    var currentDistance: Double
    var startingDistance: Double
    var totalDailyDistance: Double
    var goalDistance: Double
    var activityType: String // "Running" or "Walking"
    var locationTypeRawValue: Int // HKWorkoutSessionLocationType.rawValue
    var workoutUUID: String // Unique identifier for this workout session
    var lastSaveTime: Date // When this state was last persisted
    var routePoints: [WorkoutRoutePoint] // Location history for recovery
    var isUsingPedometer: Bool // Whether using pedometer vs GPS
    var liveActivityID: String? // Live Activity identifier for recovery
    // One-shot celebration stamps, set the moment each in-tracker celebration
    // (haptic + overlay) fires. The tracker view is destroyed on every cover
    // dismissal, so a view-lifetime flag re-arms on each return — these make
    // "already buzzed for this workout" a fact about the WORKOUT. Optional on
    // purpose: synthesized Decodable ignores property defaults, so a
    // non-optional addition would throw on the blob an older build persisted
    // mid-workout (ios.md Codable trap).
    var celebratedCatchUp: Bool?
    var celebratedCompletion: Bool?
    /// Same one-shot problem, different feedback channel: the goal-crossed
    /// Live Activity update carries an `AlertConfiguration`, which the system
    /// renders as a sound + vibration. Its view-lifetime flag re-armed on every
    /// return to the tracker, so a walk past the goal buzzed again on each
    /// re-entry even though the on-screen celebration correctly stayed quiet.
    var alertedGoalComplete: Bool?
    /// Every manual pause this workout has taken, open interval last. This —
    /// not `pausedTime` — is the source of truth: it survives a relaunch, it
    /// re-derives `pausedTime` for free, and it is what the HealthKit
    /// pause/resume events are built from at Finish (a builder created on
    /// recovery starts empty, so events held only in memory would be lost and
    /// the saved duration would silently include the pause). Optional for the
    /// usual persisted-Codable reason: synthesized Decodable ignores property
    /// defaults, so a non-optional addition would throw on the blob an older
    /// build persisted mid-workout.
    var pauseIntervals: [WorkoutPauseInterval]?
    /// Stealth Mode, LATCHED when the workout starts: the finish chain stamps
    /// `MAD_stealth` on the HKWorkout from this, so a toggle flipped off
    /// mid-walk can't un-hide a walk that began in stealth. Optional for the
    /// persisted-Codable reason above.
    var stealth: Bool?

    init(
        isActive: Bool = false,
        isPaused: Bool = false,
        startTime: Date = Date(),
        elapsedTime: TimeInterval = 0,
        pausedTime: TimeInterval = 0,
        currentDistance: Double = 0,
        startingDistance: Double = 0,
        totalDailyDistance: Double = 0,
        goalDistance: Double = 0,
        activityType: String = "Walking",
        locationTypeRawValue: Int = 0,
        workoutUUID: String = UUID().uuidString,
        lastSaveTime: Date = Date(),
        routePoints: [WorkoutRoutePoint] = [],
        isUsingPedometer: Bool = false,
        liveActivityID: String? = nil,
        celebratedCatchUp: Bool? = nil,
        celebratedCompletion: Bool? = nil,
        alertedGoalComplete: Bool? = nil,
        pauseIntervals: [WorkoutPauseInterval]? = nil,
        stealth: Bool? = nil
    ) {
        self.isActive = isActive
        self.isPaused = isPaused
        self.startTime = startTime
        self.elapsedTime = elapsedTime
        self.pausedTime = pausedTime
        self.currentDistance = currentDistance
        self.startingDistance = startingDistance
        self.totalDailyDistance = totalDailyDistance
        self.goalDistance = goalDistance
        self.activityType = activityType
        self.locationTypeRawValue = locationTypeRawValue
        self.workoutUUID = workoutUUID
        self.lastSaveTime = lastSaveTime
        self.routePoints = routePoints
        self.isUsingPedometer = isUsingPedometer
        self.liveActivityID = liveActivityID
        self.celebratedCatchUp = celebratedCatchUp
        self.celebratedCompletion = celebratedCompletion
        self.alertedGoalComplete = alertedGoalComplete
        self.pauseIntervals = pauseIntervals
        self.stealth = stealth
    }
}

/// One manual pause. `end` is nil while the pause is still open — which is
/// also how a relaunch knows to come back PAUSED rather than silently
/// resuming and counting ground the user never asked for.
struct WorkoutPauseInterval: Codable {
    let start: Date
    var end: Date?

    /// Seconds this pause has consumed, measured to `now` while still open.
    func seconds(asOf now: Date = Date()) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

extension Array where Element == WorkoutPauseInterval {
    /// Total paused seconds, including an open pause in flight.
    func totalPausedSeconds(asOf now: Date = Date()) -> TimeInterval {
        reduce(0) { $0 + $1.seconds(asOf: now) }
    }
}

/// Represents a single location point in a workout route.
///
/// Carries the MEASURED motion of the fix (`speed`/`course` and their
/// accuracies), not just where it was. A `CLLocation` rebuilt without them
/// reports `-1` on all four, which is CoreLocation's "invalid" — so a route
/// written from such points is a bare list of coordinates. Our own maps only
/// read `.coordinate` and drew fine, which is exactly why this stayed invisible;
/// Apple Fitness plots a route by its speed, and a series where every sample
/// says "speed unknown" gives it nothing to draw. The values are always
/// available at capture: `isRoutePointWorthKeeping` gates on `location.speed`,
/// so every point that reaches here had valid doppler in hand.
///
/// The four are Optional because this struct is persisted inside
/// `InProgressWorkoutState`: synthesized `Decodable` ignores property defaults,
/// so a non-optional addition would throw on the blob an in-flight workout saved
/// under the previous build and take the whole walk with it (ios.md Codable
/// trap). Absent ⇒ `-1` ⇒ byte-identical to the old behaviour.
struct WorkoutRoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let course: Double?
    let courseAccuracy: Double?
    let speed: Double?
    let speedAccuracy: Double?

    init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.timestamp = location.timestamp
        self.altitude = location.altitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.verticalAccuracy = location.verticalAccuracy
        self.course = location.course
        self.courseAccuracy = location.courseAccuracy
        self.speed = location.speed
        self.speedAccuracy = location.speedAccuracy
    }

    /// Convert back to CLLocation for processing.
    ///
    /// Uses the full initializer so course/speed survive the round trip. A point
    /// persisted before those fields existed decodes them as nil and gets `-1`,
    /// which is what CoreLocation itself means by "not measured".
    func toCLLocation() -> CLLocation {
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: course ?? -1,
            courseAccuracy: courseAccuracy ?? -1,
            speed: speed ?? -1,
            speedAccuracy: speedAccuracy ?? -1,
            timestamp: timestamp
        )
    }
}

enum InProgressWorkoutStore {
    private static let storageKey = "MAD_InProgressWorkoutState"
    private static let workoutLockKey = "MAD_WorkoutLock"
    private static let maxRoutePoints = 5000 // Prevent unbounded growth
    private static let maxStateStaleness: TimeInterval = 86400 // 24 hours

    // MARK: - Single Workout Enforcement

    /// Check if a workout is currently locked (active)
    static var isWorkoutLocked: Bool {
        return UserDefaults.standard.bool(forKey: workoutLockKey)
    }

    /// Acquire workout lock - returns true if successful, false if already locked
    @discardableResult
    static func acquireLock() -> Bool {
        if isWorkoutLocked {
            print("[InProgressWorkoutStore] ⚠️ Workout lock already held")
            return false
        }
        UserDefaults.standard.set(true, forKey: workoutLockKey)
        UserDefaults.standard.synchronize()
        print("[InProgressWorkoutStore] ✅ Workout lock acquired")
        return true
    }

    /// Release workout lock
    static func releaseLock() {
        UserDefaults.standard.set(false, forKey: workoutLockKey)
        UserDefaults.standard.synchronize()
        print("[InProgressWorkoutStore] ✅ Workout lock released")
    }

    // MARK: - State Persistence

    /// Save the current in‑progress workout snapshot with validation
    static func save(_ state: InProgressWorkoutState) {
        // Update last save time
        var updatedState = state
        updatedState.lastSaveTime = Date()

        // Trim route points if exceeding max
        if updatedState.routePoints.count > maxRoutePoints {
            let startIndex = updatedState.routePoints.count - maxRoutePoints
            updatedState.routePoints = Array(updatedState.routePoints[startIndex...])
            print("[InProgressWorkoutStore] ⚠️ Trimmed route points to \(maxRoutePoints)")
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(updatedState)
            UserDefaults.standard.set(data, forKey: storageKey)
            UserDefaults.standard.synchronize() // Force immediate flush
            print("[InProgressWorkoutStore] ✅ Saved workout state: \(updatedState.currentDistance) mi, \(updatedState.routePoints.count) points")
        } catch {
            print("[InProgressWorkoutStore] ❌ Failed to save state: \(error)")
        }
    }

    /// Load the last in‑progress workout snapshot with validation
    static func load() -> InProgressWorkoutState? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            print("[InProgressWorkoutStore] ℹ️ No saved workout state found")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(InProgressWorkoutState.self, from: data)

            // Validate state freshness
            let staleness = Date().timeIntervalSince(state.lastSaveTime)
            if staleness > maxStateStaleness {
                print("[InProgressWorkoutStore] ⚠️ State is stale (\(Int(staleness/3600))h old), clearing")
                clear()
                return nil
            }

            // Validate state integrity
            guard state.isActive else {
                print("[InProgressWorkoutStore] ⚠️ Loaded inactive state, clearing")
                clear()
                return nil
            }

            print("[InProgressWorkoutStore] ✅ Loaded workout state: \(state.currentDistance) mi, \(state.routePoints.count) points")
            return state
        } catch {
            print("[InProgressWorkoutStore] ❌ Failed to decode state: \(error)")
            clear() // Clear corrupted data
            return nil
        }
    }

    /// Clear any persisted in‑progress workout and release lock
    static func clear() {
        routePointBuffer.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
        releaseLock()
        UserDefaults.standard.synchronize()
        print("[InProgressWorkoutStore] 🗑️ Cleared workout state and lock")
    }

    /// Flip the persisted workout to ended WITHOUT dropping the payload.
    ///
    /// Called synchronously the moment the user commits to End Workout —
    /// BEFORE the async HealthKit save begins. `clear()` only runs in
    /// `finishCleanup`, at the far end of that async chain, and a user who
    /// ends a mile and immediately locks or swipe-kills the app never gets
    /// there: the store stayed `isActive`, so the next launch auto-presented
    /// the tracker with a workout they had already ended — and Ending it a
    /// second time could even double-save the walk to HealthKit when the
    /// first save had in fact landed. An ended-but-uncleared state is ignored
    /// by recovery and the launch auto-present (both key on `isActive`), and
    /// the staleness sweep disposes of it.
    static func markEnded() {
        guard var state = load() else { return }
        state.isActive = false
        save(state)
        print("[InProgressWorkoutStore] 🏁 Marked workout ended (payload kept for in-flight save)")
    }

    // MARK: - State Queries

    /// Check if there is a recoverable workout
    static func hasRecoverableWorkout() -> Bool {
        return load() != nil
    }

    /// Get the age of the saved workout state
    static func savedWorkoutAge() -> TimeInterval? {
        guard let state = load() else { return nil }
        return Date().timeIntervalSince(state.lastSaveTime)
    }

    // MARK: - Route Point Management

    /// In-memory buffer for route points to avoid encoding/decoding the full state on every GPS update.
    /// Flushed to persistent storage periodically via `flushRoutePoints()`.
    private(set) static var routePointBuffer: [WorkoutRoutePoint] = []
    private static var lastRouteFlush: Date = Date()
    private static let routeFlushInterval: TimeInterval = 10.0

    /// Add a route point to the in-memory buffer.
    /// Points are flushed to persistent storage periodically or on demand.
    static func addRoutePoint(_ location: CLLocation) {
        let point = WorkoutRoutePoint(from: location)
        routePointBuffer.append(point)

        // Auto-flush every routeFlushInterval seconds
        if Date().timeIntervalSince(lastRouteFlush) >= routeFlushInterval {
            flushRoutePoints()
        }
    }

    /// Flush buffered route points to persistent storage
    static func flushRoutePoints() {
        guard !routePointBuffer.isEmpty else { return }
        guard var state = load() else {
            print("[InProgressWorkoutStore] ⚠️ Cannot flush route points: no active workout")
            routePointBuffer.removeAll()
            return
        }

        let count = routePointBuffer.count
        state.routePoints.append(contentsOf: routePointBuffer)
        routePointBuffer.removeAll()
        lastRouteFlush = Date()
        save(state)
        print("[InProgressWorkoutStore] 📍 Flushed \(count) route points to disk")
    }

    /// Update distance without adding route points (for pedometer mode)
    static func updateDistance(_ distance: Double) {
        guard var state = load() else {
            print("[InProgressWorkoutStore] ⚠️ Cannot update distance: no active workout")
            return
        }

        state.currentDistance = distance
        save(state)
    }

    /// Update elapsed time (called periodically)
    static func updateElapsedTime(_ elapsedTime: TimeInterval) {
        guard var state = load() else { return }
        state.elapsedTime = elapsedTime
        save(state)
    }

    /// Stamp a fired celebration so no later presentation of the tracker can
    /// replay its haptic/overlay/alert. Write-through on fire: the buzz-on-
    /// every-return bug was a view-lifetime one-shot being re-armed by the next
    /// presentation of the cover. `goalAlert` covers the Live Activity's
    /// alert-configured goal push, which buzzes the phone the same way.
    static func markCelebrated(
        catchUp: Bool = false,
        completion: Bool = false,
        goalAlert: Bool = false
    ) {
        guard var state = load() else { return }
        if catchUp { state.celebratedCatchUp = true }
        if completion { state.celebratedCompletion = true }
        if goalAlert { state.alertedGoalComplete = true }
        save(state)
    }

    /// Write through the manual-pause state the instant it changes.
    ///
    /// Not left to the tracker's 1 Hz tick: that timer dies with the cover
    /// (`onDisappear` invalidates it), so a user who pauses and then backs out
    /// to the dashboard would have an unpersisted pause — and a termination
    /// there would resume the workout on relaunch with the whole pause counted
    /// as active time. `WorkoutLocationManager` is the singleton that outlives
    /// the view, so it owns the live intervals and calls this on every edge.
    static func savePauseState(isPaused: Bool, intervals: [WorkoutPauseInterval]) {
        guard var state = load() else { return }
        state.isPaused = isPaused
        state.pausedTime = intervals.totalPausedSeconds()
        state.pauseIntervals = intervals
        save(state)
    }
}


