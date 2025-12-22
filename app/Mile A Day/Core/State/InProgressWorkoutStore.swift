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
        liveActivityID: String? = nil
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
    }
}

/// Represents a single location point in a workout route
struct WorkoutRoutePoint: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double

    init(from location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.timestamp = location.timestamp
        self.altitude = location.altitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.verticalAccuracy = location.verticalAccuracy
    }

    /// Convert back to CLLocation for processing
    func toCLLocation() -> CLLocation {
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
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
        guard state.isActive else {
            clear()
            return
        }

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
        UserDefaults.standard.removeObject(forKey: storageKey)
        releaseLock()
        UserDefaults.standard.synchronize()
        print("[InProgressWorkoutStore] 🗑️ Cleared workout state and lock")
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

    /// Add a route point to the current workout
    static func addRoutePoint(_ location: CLLocation) {
        guard var state = load() else {
            print("[InProgressWorkoutStore] ⚠️ Cannot add route point: no active workout")
            return
        }

        let point = WorkoutRoutePoint(from: location)
        state.routePoints.append(point)
        save(state)
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

    /// Mark workout as paused
    static func pause(pausedTime: TimeInterval) {
        guard var state = load() else { return }
        state.isPaused = true
        state.pausedTime = pausedTime
        save(state)
    }

    /// Mark workout as resumed
    static func resume(pausedTime: TimeInterval) {
        guard var state = load() else { return }
        state.isPaused = false
        state.pausedTime = pausedTime
        save(state)
    }
}


