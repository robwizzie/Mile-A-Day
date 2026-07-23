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
    /// Anchor fix for distance accrual. Deliberately NOT advanced on sub-noise
    /// displacements — see accrueDistance.
    private var lastLocation: CLLocation?
    /// Last fix ACCEPTED into the route trace (stricter bar than distance).
    private var lastRoutePoint: CLLocation?
    private var isUsingPedometer = false
    /// Published so the app-wide "workout in progress" banner can appear/hide.
    @Published private(set) var isTracking = false

    /// Doppler speed below this = standing still. GPS jitter while stopped
    /// must never accrue: distance is a sum of segment LENGTHS, so noise is
    /// strictly additive and every phone inflates by a different amount —
    /// which is exactly how friends on the SAME walk end up out of sync.
    private static let stationarySpeed: CLLocationSpeed = 0.3
    /// Max plausible on-foot speed (m/s) — matches the route trace's teleport
    /// cap. A segment implying more is a multipath jump/GPS re-lock: accept
    /// the new position, never the jump.
    private static let maxPlausibleSpeed: Double = 12

    /// OUTDOOR cross-check odometer: the phone's per-user-calibrated pedometer
    /// distance across this tracking session (miles). The pedometer measures
    /// the WALKER (steps × calibrated stride), not satellite geometry, so it
    /// agrees across people walking together far better than raw GPS sums.
    /// Read at finish via reconciledFinalDistance(); nil when unavailable.
    private(set) var outdoorPedometerMiles: Double?
    /// Distance carried into this session by a recovery (miles). The pedometer
    /// cross-check starts at resume time, so reconciliation only compares the
    /// span BOTH instruments actually measured.
    private var sessionStartDistance: Double = 0

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
        sessionStartDistance = initialDistance
        outdoorPedometerMiles = nil
        lastLocation = nil
        lastRoutePoint = nil
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
            startOutdoorPedometerCrossCheck()
        }
    }

    private func startGPSTracking() {
        if authorizationStatus == .notDetermined {
            requestPermission()
        }
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
    }

    /// Run the pedometer ALONGSIDE outdoor GPS as a cross-check odometer.
    /// Costs nothing (same motion coprocessor indoor mode uses) and gives
    /// finish-time reconciliation a per-user-calibrated second opinion.
    private func startOutdoorPedometerCrossCheck() {
        guard CMPedometer.isDistanceAvailable() else { return }
        outdoorPedometerMiles = 0
        pedometer.startUpdates(from: Date()) { [weak self] pedometerData, error in
            guard let self, let distance = pedometerData?.distance, error == nil else { return }
            DispatchQueue.main.async {
                self.outdoorPedometerMiles = distance.doubleValue * 0.000621371
            }
        }
    }

    func stopTracking() {
        guard isTracking else { return }
        isTracking = false

        // Pedometer runs in BOTH modes now (distance source indoors, cross-
        // check odometer outdoors) — always stop it.
        pedometer.stopUpdates()
        // Location runs in both modes (distance source for GPS, keep-alive
        // for pedometer) — always stop it.
        locationManager.stopUpdatingLocation()
        lastLocation = nil
        lastRoutePoint = nil
    }

    /// The distance a finished workout should SAVE (miles). Raw GPS sums
    /// inflate differently on every phone — jitter is additive — while each
    /// person's pedometer is calibrated to their own stride. So for WALKS,
    /// meaningful disagreement resolves toward the pedometer and a group
    /// walking together converges on (nearly) the same number. RUNS keep GPS
    /// (pace/route fidelity at speed) unless it clearly starved under cover —
    /// lost fixes measure SHORT, never long. Falls back to the live figure
    /// whenever the cross-check has nothing (indoor mode, no motion
    /// permission, sub-noise sample).
    func reconciledFinalDistance(isWalk: Bool) -> Double {
        guard !isUsingPedometer,
              let pedometerSpan = outdoorPedometerMiles,
              pedometerSpan > 0.05 else {
            return currentDistance
        }
        let gpsSpan = max(0, currentDistance - sessionStartDistance)
        guard gpsSpan > 0 else { return sessionStartDistance + pedometerSpan }

        let ratio = pedometerSpan / gpsSpan
        let disagreement = abs(gpsSpan - pedometerSpan) / max(pedometerSpan, 0.01)
        let chosenSpan: Double
        if isWalk {
            // Walks: >10% apart — and the pedometer isn't itself pathological
            // (phone riding a stroller/cart barely steps) — the calibrated
            // odometer wins.
            chosenSpan = (disagreement > 0.10 && ratio > 0.6 && ratio < 1.4)
                ? pedometerSpan : gpsSpan
        } else {
            // Runs: rescue only clear GPS starvation.
            chosenSpan = gpsSpan < pedometerSpan * 0.75 ? pedometerSpan : gpsSpan
        }
        if chosenSpan != gpsSpan {
            print("[WorkoutLocationManager] 📏 Outdoor distance reconciled: GPS \(String(format: "%.3f", gpsSpan)) mi → pedometer \(String(format: "%.3f", pedometerSpan)) mi")
        }
        return sessionStartDistance + chosenSpan
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // In pedometer mode location is only a background keep-alive —
        // distance comes from CMPedometer and there's no meaningful route.
        guard !isUsingPedometer else { return }

        // Process EVERY delivered fix in order — background delivery batches
        // several fixes per callback, and taking only the last one flattened
        // curves into chords whenever the app was backgrounded.
        for newLocation in locations {
            // Quality gates shared by distance + route: plausible accuracy and
            // FRESH (cold-start replays deliver cached fixes seconds old whose
            // jump to the first real fix used to be counted as walked).
            guard newLocation.horizontalAccuracy > 0,
                  newLocation.horizontalAccuracy < 50,
                  abs(newLocation.timestamp.timeIntervalSinceNow) < 15 else {
                continue
            }

            accrueDistance(to: newLocation)

            // Route trace: a STRICTER quality bar than distance accrual —
            // waterside multipath yields 25-50m fixes that sit well off the
            // real path, and standing still sprays jitter clusters. Skipping a
            // bad fix here only straightens the drawn line between neighbors.
            if isRoutePointWorthKeeping(newLocation) {
                InProgressWorkoutStore.addRoutePoint(newLocation)
                lastRoutePoint = newLocation
            }
        }
    }

    /// Add a fix's contribution to `currentDistance` — with the noise floor
    /// raw delta-summing lacked. Distance is a sum of segment lengths, so GPS
    /// jitter only ever ADDS (it never averages out); un-floored accrual is
    /// why phones on the same walk read different miles. Rules:
    ///   - Doppler says standing still → ignore the fix entirely (red lights,
    ///     mid-walk chats: jitter while stopped was the biggest inflater).
    ///   - Implied speed over the on-foot cap → multipath jump / GPS re-lock:
    ///     take the new position, never count the jump.
    ///   - Displacement under the fix's own noise floor → hold the anchor and
    ///     wait for real movement to accumulate past it (a walker's 1.4 m/s
    ///     still accrues every ~3s; the chord under-counts corners by far
    ///     less than jitter over-counted everything).
    private func accrueDistance(to newLocation: CLLocation) {
        if newLocation.speed >= 0, newLocation.speed < Self.stationarySpeed {
            return
        }
        guard let anchor = lastLocation else {
            lastLocation = newLocation
            return
        }
        let meters = newLocation.distance(from: anchor)
        let dt = newLocation.timestamp.timeIntervalSince(anchor.timestamp)
        if dt > 0, meters / dt > Self.maxPlausibleSpeed {
            lastLocation = newLocation
            return
        }
        guard meters >= max(4, newLocation.horizontalAccuracy * 0.35) else {
            return
        }
        let distanceInMiles = meters * 0.000621371
        // Backstop against anything the speed cap missed (e.g. huge dt gaps).
        if distanceInMiles < 0.1 {
            DispatchQueue.main.async {
                self.currentDistance += distanceInMiles
                self.persistDistanceThrottled()
            }
        }
        lastLocation = newLocation
    }

    private func isRoutePointWorthKeeping(_ location: CLLocation) -> Bool {
        // Tight accuracy: reflections near water/buildings live in the
        // 25-50m band that distance accepts.
        guard location.horizontalAccuracy <= 25 else { return false }
        // No stale/cached fixes (cold-start replays land seconds old).
        guard abs(location.timestamp.timeIntervalSinceNow) < 10 else { return false }

        guard let last = lastRoutePoint else { return true }
        let displacement = location.distance(from: last)
        // Minimum displacement scaled to the fix's own uncertainty — a
        // stationary user's jitter (± accuracy) never becomes scribble.
        guard displacement >= max(4, location.horizontalAccuracy * 0.35) else { return false }
        // Teleport cap: 12 m/s covers any run (and downhill cycling bursts);
        // multipath jumps are far faster.
        let dt = location.timestamp.timeIntervalSince(last.timestamp)
        if dt > 0, displacement / dt > 12 { return false }
        return true
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
