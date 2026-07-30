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

    /// HKWorkout metadata key carrying the tracker's moving time (seconds).
    /// Written at save, read back by the sync (display pace divides by it) —
    /// Watch/third-party workouts simply don't have it.
    static let movingSecondsMetadataKey = "MAD_moving_seconds"

    private let locationManager = CLLocationManager()
    private let pedometer = CMPedometer()
    /// Motion-classifier second witness: catches a walk left tracking in a
    /// car, which SPEED can't (25 mph city driving implies ~11 m/s — under
    /// the on-foot teleport cap, with perfectly valid doppler).
    private let activityClassifier = CMMotionActivityManager()
    /// Latest classifier verdict at medium+ confidence. While true, nothing
    /// accrues and no route points are kept. Fail-open: stays false whenever
    /// the classifier is unavailable or silent.
    private var isConfidentlyAutomotive = false
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

    /// OUTDOOR pedometer odometer: the phone's per-user-calibrated pedometer
    /// distance across this tracking session (miles) — the same estimator
    /// Apple Fitness uses for phone-only walking/running distance. One of
    /// the two spans `liveDistance` takes the max of; nil until CoreMotion
    /// actually delivers. Published so the tracking UI refreshes on step
    /// progress while a GPS anchor holds.
    @Published private(set) var outdoorPedometerMiles: Double?
    /// When the cross-check odometer last gained ≥ ~2 m — the live "is the
    /// walker actually stepping?" witness the movement gate consults.
    private var lastPedometerProgressAt: Date?
    private var lastPedometerProgressMiles: Double = 0
    /// The cross-check reported an error (Motion denied mid-session, etc.).
    /// Every consumer of pedometer evidence must fail OPEN on this.
    private var pedometerErrored = false
    /// Session start — grace window for the movement gate while the first
    /// pedometer batch is still in flight.
    private var trackingStartedAt: Date?
    /// Seconds of witnessed movement this session — the DISPLAY-pace divisor
    /// (elapsed time stays the truth for records; a race clock doesn't
    /// pause). Sum of accepted segments' dt, capped per segment so a red
    /// light waited out at a held anchor doesn't ride in on the resume fix.
    private(set) var movingSeconds: TimeInterval = 0
    /// When distance last accrued — one of the auto-pause evidence sources.
    private var lastAccrualAt: Date?
    /// Last fix whose VALID doppler cleared the stationary bar while not
    /// classified automotive — the freshest "in motion" witness there is.
    /// Tracked apart from accrual because a held anchor stalls accrual while
    /// the walker is plainly moving (see isAutoPaused).
    private var lastMovingDopplerAt: Date?
    /// True while tracking outdoors with no movement EVIDENCE for 45s: no
    /// counted segment, no moving-doppler fix, no step progress (standing,
    /// sitting, riding, seated multipath drift). Accrual alone was the old
    /// trigger and it false-positives mid-walk: an out-and-back turnaround
    /// holds the anchor while displacement shrinks and regrows, so accrual
    /// legitimately stalls for up to ~3× the noise floor of real walking
    /// (60-100m in mediocre accuracy ≈ 45-70s) — which flashed AUTO-PAUSED
    /// at 0.99 mi on a user mid-stride. Someone stepping or carrying doppler
    /// speed is never "paused"; fresh evidence clears the chip immediately.
    @Published private(set) var isAutoPaused = false
    /// Distance carried into this session by a recovery (miles). The pedometer
    /// starts at resume time, so the estimator only compares the span BOTH
    /// instruments actually measured this session.
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
    /// THE workout distance — the one number every surface shows AND the one
    /// the finish saves. There is no separate finish-time reconciliation:
    /// what the user watches during the walk/run is exactly what persists.
    /// (The old design showed raw GPS accrual live and reconciled against
    /// the pedometer only at Finish, so a jitter-inflated walk read "100%"
    /// and then dropped to 80% the moment it saved.)
    ///
    /// Outdoors this is the ratcheted MAX of the two instruments' session
    /// spans — the jitter-gated GPS sum and the calibrated pedometer
    /// odometer:
    ///   - The pedometer term is the same estimator Apple's own Fitness app
    ///     uses for phone-only walking/running distance (steps × per-user
    ///     stride, OS-calibrated against GPS) — so MAD never reads SHORTER
    ///     than the Fitness app the user checks us against.
    ///   - The GPS term is what GPS-first apps (Strava et al.) show, and it
    ///     covers every real shape where ground outruns steps: stroller,
    ///     cart, GPS-healthy runs — and a pedometer that went silent.
    ///   - max() is the product rule made math: when two credible
    ///     estimators disagree, credit the FARTHER one — an undercounted
    ///     mile breaks a streak; a slightly generous one never hurt anyone.
    ///     Absurd GPS (seated drift, driving) never reaches this point: the
    ///     accrual gates (doppler-stationary skip, steps corroboration,
    ///     teleport cap, automotive suspension) kill it at the source.
    /// Both spans are monotonic, so their max is too; the outer ratchet
    /// keeps the displayed number monotonic across every remaining edge
    /// (mid-walk Motion grant, pedometer error fallback). Indoor sessions —
    /// and any session where the pedometer can't testify — remain raw
    /// accrual, exactly as before.
    @Published private(set) var liveDistance: Double = 0.0
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
        liveDistance = initialDistance
        sessionStartDistance = initialDistance
        outdoorPedometerMiles = nil
        lastPedometerProgressAt = nil
        lastPedometerProgressMiles = 0
        pedometerErrored = false
        trackingStartedAt = Date()
        movingSeconds = 0
        lastAccrualAt = nil
        lastMovingDopplerAt = nil
        isAutoPaused = false
        isConfidentlyAutomotive = false
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
                            self.refreshLiveDistance()
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
            startActivityClassifier()
        }
    }

    /// Movement-type second witness for outdoor sessions. Uses the same
    /// Motion & Fitness permission the pedometer already holds; when the
    /// classifier can't run (old hardware, denied), nothing arrives and the
    /// automotive gate simply never engages.
    private func startActivityClassifier() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activityClassifier.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            self.isConfidentlyAutomotive = activity.automotive && activity.confidence != .low
        }
    }

    private func startGPSTracking() {
        if authorizationStatus == .notDetermined {
            requestPermission()
        }
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
    }

    /// Run the pedometer ALONGSIDE outdoor GPS — the second span in
    /// `liveDistance`'s max(), covering everything GPS starves on.
    /// Deliberately left nil until CoreMotion actually delivers — nil means
    /// "can't testify", so a silently-dead pedometer simply contributes
    /// nothing instead of masquerading as a measured zero.
    private func startOutdoorPedometerCrossCheck() {
        guard CMPedometer.isDistanceAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] pedometerData, error in
            guard let self else { return }
            if error != nil {
                // Motion denied / CoreMotion failure: mark it so the movement
                // gate and the distance estimator both fail OPEN (back to raw
                // GPS accrual) instead of trusting a frozen zero. The refresh
                // re-derives liveDistance on the new fallback immediately;
                // the ratchet keeps the handoff from ever ticking down.
                DispatchQueue.main.async {
                    self.pedometerErrored = true
                    self.refreshLiveDistance()
                }
                return
            }
            guard let distance = pedometerData?.distance else { return }
            let miles = distance.doubleValue * 0.000621371
            DispatchQueue.main.async {
                // ≥ ~2 m of new step distance = the walker is actually
                // stepping right now. Feeds stepsCorroborateMovement.
                if miles - self.lastPedometerProgressMiles >= 0.0012 {
                    self.lastPedometerProgressMiles = miles
                    self.lastPedometerProgressAt = Date()
                }
                // Clamped monotonic: this span is displayed AND saved, so a
                // revised-down batch must never tick the workout backwards.
                self.outdoorPedometerMiles = max(self.outdoorPedometerMiles ?? 0, miles)
                self.refreshLiveDistance()
            }
        }
    }

    /// True while there is positive evidence the walker is moving on foot:
    /// step distance advanced within the last minute (with a startup grace
    /// window while the first pedometer batch is in flight). Fails OPEN
    /// whenever the pedometer can't testify — no hardware, no Motion
    /// permission, errored — so the gate can never brick tracking; those
    /// sessions just keep the doppler+floor gates alone.
    private var stepsCorroborateMovement: Bool {
        guard CMPedometer.isDistanceAvailable(),
              CMPedometer.authorizationStatus() == .authorized,
              !pedometerErrored,
              outdoorPedometerMiles != nil else { return true }
        let reference = lastPedometerProgressAt ?? trackingStartedAt ?? Date()
        return Date().timeIntervalSince(reference) < 60
    }

    func stopTracking() {
        guard isTracking else { return }
        isTracking = false

        // Pedometer runs in BOTH modes now (distance source indoors, cross-
        // check odometer outdoors) — always stop it.
        pedometer.stopUpdates()
        activityClassifier.stopActivityUpdates()
        // Location runs in both modes (distance source for GPS, keep-alive
        // for pedometer) — always stop it.
        locationManager.stopUpdatingLocation()
        lastLocation = nil
        lastRoutePoint = nil
        isAutoPaused = false
    }

    /// Re-derive `liveDistance` after either instrument moved (main thread
    /// only). This IS the save: the finish persists `liveDistance` verbatim,
    /// so everything here holds for the recap and HealthKit too.
    ///
    /// max(GPS span, pedometer span): each instrument misses real distance
    /// the other catches — GPS starves under tree cover and on un-warmed
    /// cold starts (lost fixes measure SHORT, never long); the pedometer
    /// misses ground covered without steps (stroller, cart) and can go
    /// silent. Their absurd-OVERcount shapes (seated multipath drift,
    /// driving) are killed at accrual time by the gates — doppler-stationary
    /// skip, steps corroboration, teleport cap, automotive suspension — not
    /// here. So the larger surviving span is the better estimate, and it's
    /// the generous one: in a streak app, never show LESS than a credible
    /// instrument measured. The outer ratchet keeps the number monotonic
    /// across the remaining edges (mid-walk Motion grant, pedometer error
    /// dropping its term): the count may briefly hold, never tick back.
    private func refreshLiveDistance() {
        guard !isUsingPedometer else {
            // Indoor: currentDistance already IS the pedometer.
            liveDistance = max(liveDistance, currentDistance)
            return
        }
        let pedometerTestifies = !pedometerErrored
            && CMPedometer.authorizationStatus() == .authorized
        let gpsSpan = max(0, currentDistance - sessionStartDistance)
        let pedometerSpan = pedometerTestifies ? (outdoorPedometerMiles ?? 0) : 0
        liveDistance = max(liveDistance, sessionStartDistance + max(gpsSpan, pedometerSpan))
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

            // Moving-doppler witness for the auto-pause chip. Dopplerless
            // (speed == -1) fixes deliberately don't count — seated multipath
            // drift is exactly that shape and must still read as paused.
            if newLocation.speed >= Self.stationarySpeed, !isConfidentlyAutomotive {
                lastMovingDopplerAt = Date()
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

        refreshAutoPauseState()
    }

    /// Visible movement-gate state — paused only when EVERY movement witness
    /// has gone quiet (see the property's rationale). Distance accrual is NOT
    /// consulted alone: held-anchor stalls (turnarounds) aren't stillness.
    private func refreshAutoPauseState() {
        guard isTracking, !isUsingPedometer else { return }
        let evidence = [lastAccrualAt, lastMovingDopplerAt, lastPedometerProgressAt, trackingStartedAt]
            .compactMap { $0 }
            .max() ?? Date()
        let paused = Date().timeIntervalSince(evidence) > 45
        if paused != isAutoPaused {
            DispatchQueue.main.async { self.isAutoPaused = paused }
        }
    }

    /// Add a fix's contribution to `currentDistance` — with the noise floor
    /// raw delta-summing lacked. Distance is a sum of segment lengths, so GPS
    /// jitter only ever ADDS (it never averages out); un-floored accrual is
    /// why phones on the same walk read different miles. Rules:
    ///   - Doppler says standing still → ignore the fix entirely (red lights,
    ///     mid-walk chats: jitter while stopped was the biggest inflater).
    ///   - Doppler INVALID (speed == -1) → only count while the pedometer
    ///     says steps are happening. Multipath (stadium bowls, urban canyons)
    ///     emits exactly these dopplerless fixes while the phone sits still,
    ///     and their slow drift beats any per-fix cap: sub-floor fixes hold
    ///     the anchor, so displacement accumulates over minutes and crosses
    ///     the floor at an implied 1-2 m/s — that's how sitting through a
    ///     3-hour ballgame banked 2.28 "miles". Re-anchor on the reject so
    ///     resumed walking doesn't inherit the parked drift as one segment.
    ///   - Implied speed over the on-foot cap → multipath jump / GPS re-lock:
    ///     take the new position, never count the jump.
    ///   - Displacement under the noise floor of EITHER endpoint → hold the
    ///     anchor and wait for real movement to accumulate past it (a
    ///     walker's 1.4 m/s still accrues every few seconds; the chord
    ///     under-counts corners by far less than jitter over-counted
    ///     everything). The floor must span both fixes: a hop out of a
    ///     40m-accuracy anchor into a sharp fix is still a 40m-uncertain hop.
    private func accrueDistance(to newLocation: CLLocation) {
        let doppler = newLocation.speed
        if doppler >= 0, doppler < Self.stationarySpeed {
            return
        }
        guard let anchor = lastLocation else {
            lastLocation = newLocation
            return
        }
        // Riding, not walking: the classifier is the only witness that can
        // tell city driving (~11 m/s, valid doppler) from a hard run.
        if isConfidentlyAutomotive {
            lastLocation = newLocation
            return
        }
        if doppler < 0, !stepsCorroborateMovement {
            lastLocation = newLocation
            return
        }
        let meters = newLocation.distance(from: anchor)
        let dt = newLocation.timestamp.timeIntervalSince(anchor.timestamp)
        if dt > 0, meters / dt > Self.maxPlausibleSpeed {
            lastLocation = newLocation
            return
        }
        let noiseFloor = max(8, (max(anchor.horizontalAccuracy, 0) + newLocation.horizontalAccuracy) * 0.5)
        guard meters >= noiseFloor else {
            return
        }
        let distanceInMiles = meters * 0.000621371
        // Backstop against anything the speed cap missed (e.g. huge dt gaps).
        if distanceInMiles < 0.1 {
            // Per-segment dt cap: accepted segments arrive every ~6-21s while
            // walking, so 20s covers them — but a resume fix after a held-
            // anchor wait (red light) can't ride the whole wait in as
            // "moving".
            movingSeconds += min(max(dt, 0), 20)
            lastAccrualAt = Date()
            DispatchQueue.main.async {
                self.currentDistance += distanceInMiles
                self.refreshLiveDistance()
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
        // Movement gate — the trace's version of accrueDistance's rule. A
        // stationary phone's jitter passes the displacement floor a few
        // meters at a time and draws the scribble ball (then walks the trace
        // onto the pitcher's mound after you sit down): only keep points
        // while doppler says moving, or the pedometer vouches for steps.
        if location.speed < Self.stationarySpeed, !stepsCorroborateMovement { return false }
        // A drive isn't path either.
        if isConfidentlyAutomotive { return false }

        guard let last = lastRoutePoint else { return true }
        let displacement = location.distance(from: last)
        // Minimum displacement scaled to the worse endpoint's uncertainty —
        // a stationary user's jitter (± accuracy) never becomes scribble.
        guard displacement >= max(4, max(location.horizontalAccuracy, last.horizontalAccuracy) * 0.35) else { return false }
        // Teleport cap: 12 m/s covers any run (and downhill cycling bursts);
        // multipath jumps are far faster.
        let dt = location.timestamp.timeIntervalSince(last.timestamp)
        if dt > 0, displacement / dt > 12 { return false }
        return true
    }

    /// Persist live distance straight to the recovery store from the background
    /// data callbacks, so distance survives app termination even when the
    /// foreground timer is suspended. Throttled; no-op when not tracking.
    /// Persists `liveDistance` — the displayed/saved figure — so the banner,
    /// recovery, and a post-kill resume all continue from exactly the number
    /// the user watched.
    private func persistDistanceThrottled() {
        guard isTracking else { return }
        let now = Date()
        guard now.timeIntervalSince(lastDistancePersist) >= distancePersistInterval else { return }
        lastDistancePersist = now
        InProgressWorkoutStore.updateDistance(liveDistance)
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
