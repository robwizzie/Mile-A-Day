import SwiftUI
import HealthKit
import CoreLocation
import CoreMotion

// MARK: - Workout Location Manager

// Location Manager for tracking distance during workouts.
//
// Distance tracking modes:
//   - Outdoor (GPS): Incremental — each location update adds a delta to currentDistance.
//   - Indoor (Pedometer): Cumulative — pedometer reports total distance since its start.
//     We add a `pedometerOffset` so recovered workouts don't lose prior distance.
//
// The key invariant: currentDistance must NEVER be overwritten with a smaller value
// by the tracking system itself. Only stopTracking() and explicit reset can clear it.
class WorkoutLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// App-level singleton so tracking survives leaving the tracking screen.
    /// Previously this was a per-view `@StateObject`, so navigating back to the
    /// dashboard deallocated it and silently stopped GPS/pedometer mid-workout.
    static let shared = WorkoutLocationManager()

    private let locationManager = CLLocationManager()
    private let pedometer = CMPedometer()
    private var lastLocation: CLLocation?
    private var isUsingPedometer = false
    /// Published so the app-wide "workout in progress" banner can appear/hide.
    @Published private(set) var isTracking = false

    // For indoor pedometer mode: the pedometer reports cumulative distance from its
    // start date. When recovering a workout, we set this offset to the previously
    // accumulated distance so the pedometer's new readings ADD to it instead of
    // replacing it. For GPS mode this is unused (GPS is incremental).
    private var pedometerOffset: Double = 0.0

    // Direct-to-disk persistence of live distance from the background callbacks.
    // The foreground timer normally saves state, but it's suspended in the
    // background — without this, distance accrued while backgrounded is lost if
    // iOS terminates the app. Throttled to limit UserDefaults writes.
    private var lastDistancePersist = Date.distantPast
    private let distancePersistInterval: TimeInterval = 2.0

    @Published var currentDistance: Double = 0.0 // Distance in miles
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = locationManager.authorizationStatus
    }

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Start tracking distance.
    ///
    /// - Parameters:
    ///   - locationType: `.outdoor` for GPS, `.indoor` for pedometer.
    ///   - initialDistance: Distance already accumulated in a prior session (0 for new workouts).
    ///     For GPS mode, this becomes the starting value that incremental updates add to.
    ///     For pedometer mode, this becomes the offset added to the pedometer's readings.
    func startTracking(locationType: HKWorkoutSessionLocationType = .outdoor, initialDistance: Double = 0.0) {
        // Prevent double-start
        guard !isTracking else { return }
        isTracking = true

        currentDistance = initialDistance
        lastLocation = nil
        isUsingPedometer = (locationType == .indoor)
        pedometerOffset = initialDistance

        if locationType == .indoor {
            if CMPedometer.isDistanceAvailable() {
                pedometer.startUpdates(from: Date()) { [weak self] pedometerData, error in
                    guard let self = self, let data = pedometerData, error == nil else { return }

                    if let distance = data.distance {
                        let distanceInMiles = distance.doubleValue * 0.000621371
                        let newTotal = self.pedometerOffset + distanceInMiles
                        DispatchQueue.main.async {
                            self.currentDistance = newTotal
                            self.persistDistanceThrottled()
                        }
                    }
                }
                // Keep-alive: pedometer updates are suspended with the app when
                // the phone locks (CoreMotion batches them until foreground),
                // which froze the Live Activity for indoor workouts. Running
                // low-accuracy location updates keeps the app alive via the
                // `location` background mode; distance from these fixes is
                // ignored in pedometer mode (see didUpdateLocations).
                locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                locationManager.startUpdatingLocation()
            } else {
                isUsingPedometer = false
                startGPSTracking()
            }
        } else {
            startGPSTracking()
        }
    }

    private func startGPSTracking() {
        if authorizationStatus == .notDetermined {
            requestPermission()
        }
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
    }

    func stopTracking() {
        guard isTracking else { return }
        isTracking = false

        if isUsingPedometer {
            pedometer.stopUpdates()
        }
        // Location runs in both modes (distance source for GPS, keep-alive
        // for pedometer) — always stop it.
        locationManager.stopUpdatingLocation()
        lastLocation = nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // In pedometer mode location is only a background keep-alive —
        // distance comes from CMPedometer and there's no meaningful route.
        guard !isUsingPedometer else { return }

        guard let newLocation = locations.last else { return }

        // Only use accurate locations
        guard newLocation.horizontalAccuracy > 0 && newLocation.horizontalAccuracy < 50 else {
            return
        }

        // Calculate distance if we have a previous location
        if let lastLocation = lastLocation {
            let distance = newLocation.distance(from: lastLocation) // meters
            let distanceInMiles = distance * 0.000621371

            // Only add distance if it's reasonable (not a GPS jump)
            if distanceInMiles < 0.1 {
                DispatchQueue.main.async {
                    self.currentDistance += distanceInMiles
                    self.persistDistanceThrottled()
                }
            }
        }

        lastLocation = newLocation

        // Persist route point for recovery
        InProgressWorkoutStore.addRoutePoint(newLocation)
    }

    /// Persist live distance straight to the recovery store from the background
    /// data callbacks, so distance survives app termination even when the
    /// foreground timer is suspended. Throttled; no-op when not tracking.
    private func persistDistanceThrottled() {
        guard isTracking else { return }
        let now = Date()
        guard now.timeIntervalSince(lastDistancePersist) >= distancePersistInterval else { return }
        lastDistancePersist = now
        InProgressWorkoutStore.updateDistance(currentDistance)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[WorkoutLocationManager] Error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}

// MARK: - In‑Progress Workout Banner

/// Compact banner shown on the dashboard when there is an in‑progress workout
/// but the full‑screen tracker has been dismissed. Tapping it resumes the workout.
struct InProgressWorkoutBanner: View {
    let state: InProgressWorkoutState
    let onResume: () -> Void

    @State private var currentTime = Date()
    @State private var latestState: InProgressWorkoutState?
    @State private var tickTimer: Timer?

    // Compute real-time elapsed time based on start time
    private var realTimeElapsedSeconds: TimeInterval {
        if let latest = latestState {
            return currentTime.timeIntervalSince(latest.startTime)
        }
        return currentTime.timeIntervalSince(state.startTime)
    }

    private var formattedTime: String {
        let minutes = Int(realTimeElapsedSeconds) / 60
        let seconds = Int(realTimeElapsedSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var currentDistance: Double {
        latestState?.currentDistance ?? state.currentDistance
    }

    var body: some View {
        Button(action: onResume) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 0.25, blue: 0.35),
                                    Color(red: 0.7, green: 0.2, blue: 0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: "play.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .bold))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Workout in progress")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Text("\(String(format: "%.2f", currentDistance)) mi • \(formattedTime)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            // Start a timer to update the time display every second. Stored so
            // it can be invalidated on disappear — this banner now appears on
            // every tab, so an un-invalidated timer would pile up on each switch.
            tickTimer?.invalidate()
            tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                currentTime = Date()
                // Reload the latest state to get updated distance
                if let updated = InProgressWorkoutStore.load(), updated.isActive {
                    latestState = updated
                }
            }
        }
        .onDisappear {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }
}
