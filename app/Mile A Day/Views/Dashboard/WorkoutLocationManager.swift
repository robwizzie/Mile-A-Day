import SwiftUI
import HealthKit
import CoreLocation
import CoreMotion
import UserNotifications

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
    /// Ghost race, stamped only when the ghost was BEATEN. Same travel path as
    /// moving seconds: HKWorkout metadata → sync → a `workouts` column, which
    /// is what lets the server count wins for medals. Absent on every workout
    /// that wasn't raced or wasn't won, so "present" means "won".
    static let ghostMarginMetadataKey = "MAD_ghost_margin_seconds"
    static let ghostTargetMetadataKey = "MAD_ghost_target_seconds"

    private let locationManager = CLLocationManager()
    private let pedometer = CMPedometer()
    /// Motion-classifier second witness: catches a walk left tracking in a
    /// car, which SPEED can't (25 mph city driving implies ~11 m/s — under
    /// the on-foot teleport cap, with perfectly valid doppler).
    private let activityClassifier = CMMotionActivityManager()
    /// Latest classifier verdict at medium+ confidence, and when it landed.
    /// Read through `isConfidentlyAutomotive`, never directly — the raw flag
    /// LATCHES, and `startActivityUpdates` is background-batched exactly like
    /// the pedometer, so a verdict stamped while the app was foreground
    /// (drove to the trailhead, opened the app, locked the phone) would
    /// otherwise suppress accrual, the route AND every movement witness for
    /// the whole walk.
    private var automotiveVerdict = false
    private var automotiveVerdictAt: Date?
    /// Fail-open TTL on the automotive latch: a verdict older than this means
    /// the classifier has gone quiet, not that the user is still driving.
    /// `pollMotionWitnesses` re-queries well inside this window, so a real
    /// drive keeps the latch refreshed.
    private static let automotiveVerdictTTL: TimeInterval = 90

    /// The automotive gate, with the staleness fail-open applied.
    private var isConfidentlyAutomotive: Bool {
        guard automotiveVerdict, let at = automotiveVerdictAt else { return false }
        return Date().timeIntervalSince(at) < Self.automotiveVerdictTTL
    }
    /// Anchor fix for distance accrual. Deliberately NOT advanced on sub-noise
    /// displacements — see accrueDistance.
    private var lastLocation: CLLocation?
    /// Last fix ACCEPTED into the route trace (stricter bar than distance).
    private var lastRoutePoint: CLLocation?
    private(set) var isUsingPedometer = false
    /// Published so the app-wide "workout in progress" banner can appear/hide.
    @Published private(set) var isTracking = false

    /// When ANY location fix last arrived (before quality gates) — the
    /// tracking screen's "no GPS signal" banner keys off this going quiet.
    private(set) var lastFixAt: Date?
    /// Precise vs approximate location. Approximate fixes (~5 km) fail the
    /// accuracy gate EVERY time, so tracking reads 0.00 forever while looking
    /// alive — the screen must tell the user to flip Precise Location on.
    var accuracyAuthorization: CLAccuracyAuthorization {
        locationManager.accuracyAuthorization
    }

    /// Dead-man switch: a local notification ~5 minutes out, pushed forward
    /// every minute by live callbacks (location fixes, pedometer batches).
    /// While the app is alive it never fires; if iOS terminates the app
    /// mid-workout (long lock under memory pressure — likelier in Low Power
    /// Mode, and unrecoverable with when-in-use permission), the pending
    /// notification outlives the process and tells the user their workout
    /// stopped tracking instead of letting them discover it a mile later.
    /// Tapping it opens the app, where the recovery banner offers resume.
    private static let watchdogNotificationId = "MAD_tracking_watchdog"
    private var lastWatchdogArm = Date.distantPast

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
    /// Apple Fitness uses for phone-only walking/running distance, and THE
    /// odometer behind `liveDistance` (GPS only stands in when Core Motion
    /// can't measure). Nil until CoreMotion actually delivers. Published so
    /// the tracking UI refreshes on step progress while a GPS anchor holds.
    @Published private(set) var outdoorPedometerMiles: Double?
    /// When the cross-check odometer last gained ≥ ~2 m — the live "is the
    /// walker actually stepping?" witness the movement gate consults.
    private var lastPedometerProgressAt: Date?
    private var lastPedometerProgressMiles: Double = 0
    /// When CoreMotion last ANSWERED at all (progress or not). Distinct from
    /// `lastPedometerProgressAt`, which is "the walker stepped": a batched or
    /// dead pedometer reports neither, and conflating the two is what let a
    /// silent sampler read as "standing still" — the step gate must fail OPEN
    /// on a stale sampler and stay strict on a live one that says zero.
    private var lastPedometerSampleAt: Date?
    /// Throttle for `pollMotionWitnesses`.
    private var lastMotionPollAt = Date.distantPast
    private static let motionPollInterval: TimeInterval = 10
    /// The cross-check reported an error (Motion denied mid-session, etc.).
    /// Every consumer of pedometer evidence must fail OPEN on this.
    private var pedometerErrored = false
    /// Session start — grace window for the movement gate while the first
    /// pedometer batch is still in flight.
    private var trackingStartedAt: Date?
    /// Miles accrued from fixes whose VALID doppler said "moving" — evidence
    /// that GPS distance was real locomotion: a phone riding a stroller/cart
    /// covers ground with doppler speed but no steps, while a phone sitting
    /// through a ballgame drifts with NO doppler. This is what hands the
    /// odometer to GPS (`gpsOwnsSession`) when steps can't tell the story.
    private(set) var dopplerMovingMiles: Double = 0
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
    /// Rolling anchor for the fix-to-fix movement witness, advanced roughly
    /// every `evidenceAnchorSpan` seconds. Deliberately SEPARATE from
    /// `lastLocation`: the accrual anchor is held through sub-floor
    /// displacement (that's the jitter defence), so on an out-and-back
    /// turnaround it measures ~0 displacement while the walker is plainly
    /// covering ground. This one always advances, so "did the walker move in
    /// the last ~10s?" stays answerable even while accrual is stalled.
    private var evidenceAnchor: CLLocation?
    /// When the fix-to-fix witness last saw real displacement.
    private var lastFixMovementAt: Date?
    /// When a fix last cleared the (loose) evidence quality bar. Being BLIND
    /// is not the same as being stopped — see `refreshAutoPauseState`.
    private var lastFixAcceptedAt: Date?
    /// Spacing for the fix-to-fix witness. Fixes arrive ~1/s and a walker
    /// covers only ~1.4 m in that time — under any sane jitter floor — so the
    /// witness compares against a fix ~10s old, where a walker's ~14m is
    /// comfortably clear of the floor.
    private static let evidenceAnchorSpan: TimeInterval = 10
    /// How long EVERY witness must be silent before the chip shows. Was 45s,
    /// which a single mediocre-accuracy turnaround could burn through on its
    /// own. The chip is cosmetic; a false positive mid-stride reads as
    /// "tracking broke", so this is deliberately lenient.
    private static let movementEvidenceWindow: TimeInterval = 120
    /// Staleness bar for the step witness (`stepsCorroborateMovement`).
    private static let stepWitnessWindow: TimeInterval = 90
    /// Re-evaluates the chip (and re-polls the motion witnesses) without
    /// waiting on a location callback — `didUpdateLocations` used to be the
    /// ONLY caller of `refreshAutoPauseState`, so once fixes stopped clearing
    /// the bar the chip could never come back down.
    private var pauseHeartbeat: Timer?

    /// True while tracking outdoors with no movement EVIDENCE for
    /// `movementEvidenceWindow`: no counted segment, no moving-doppler fix,
    /// no fix-to-fix displacement, no step progress (standing, sitting,
    /// riding, seated multipath drift). Accrual alone was the original
    /// trigger and it false-positives mid-walk: an out-and-back turnaround
    /// holds the anchor while displacement shrinks and regrows, so accrual
    /// legitimately stalls for up to ~3× the noise floor of real walking
    /// (60-100m in mediocre accuracy ≈ 45-70s) — which flashed AUTO-PAUSED
    /// at 0.99 mi on a user mid-stride. Adding witnesses wasn't enough on its
    /// own, because on a locked-screen walk they ALL go quiet at once: the
    /// pedometer and the activity classifier are batched by CoreMotion until
    /// foreground, and the doppler witness drops out under tree cover. Hence
    /// the background polling (`pollMotionWitnesses`), the fix-to-fix witness
    /// that survives a held anchor, and the blind-≠-stopped rule.
    /// Someone stepping, displacing, or carrying doppler speed is never
    /// "paused"; fresh evidence clears the chip immediately.
    @Published private(set) var isAutoPaused = false
    /// Distance carried into this session by a recovery (miles). The pedometer
    /// starts at resume time, so the estimator only compares the span BOTH
    /// instruments actually measured this session.
    private var sessionStartDistance: Double = 0

    /// Cumulative (raceClockSeconds, miles) samples for the ghost race —
    /// appended on accrual, throttled to every ≥0.02 mi or ≥10 s. Session-
    /// local; consumed at finish by BestEffortStore.recordFinish. Seeded with
    /// the session's starting distance so a recovered workout's curve visibly
    /// starts mid-distance (recordFinish refuses those — no time history).
    private(set) var effortCurve: [(t: TimeInterval, d: Double)] = []
    private var lastEffortSample: (t: TimeInterval, d: Double) = (0, 0)

    /// The ghost-race clock: witnessed-movement seconds outdoors (auto-pauses
    /// can't cheat the race), wall elapsed indoors — the treadmill pedometer
    /// doesn't witness segments, and a treadmill session rarely pauses.
    var raceClockSeconds: TimeInterval {
        if isUsingPedometer {
            guard let start = trackingStartedAt else { return 0 }
            return Date().timeIntervalSince(start)
        }
        return movingSeconds
    }

    /// Append an effort-curve point when enough distance or time has passed.
    /// Called on the main queue from `refreshLiveDistance` — i.e. from every
    /// path that moves the odometer, indoor and outdoor alike.
    ///
    /// It samples `liveDistance`, NOT raw GPS accrual: that's the number on
    /// the ring and the number Finish saves verbatim, so the 1.0-mile crossing
    /// the race verdict freezes on is the same crossing the user watched.
    private func sampleEffortCurve() {
        let t = raceClockSeconds
        let d = liveDistance
        guard d > lastEffortSample.d else { return }
        guard d - lastEffortSample.d >= 0.02 || t - lastEffortSample.t >= 10 else { return }
        lastEffortSample = (t, d)
        effortCurve.append((t, d))
    }

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
    /// ONE source of truth: Core Motion's calibrated distance — the exact
    /// pipeline behind Apple Fitness's phone-only walking/running distance
    /// (steps × per-user stride, OS-calibrated against GPS) — is the
    /// odometer for every outdoor session; GPS's job is the route map. So a
    /// mile reads the same on our tracker, in the recap, in HealthKit, and
    /// in Apple's own Fitness app, and it is immune to the additive GPS
    /// jitter that inflated live numbers. GPS substitutes as the odometer
    /// ONLY when Core Motion cannot measure the session (see
    /// `refreshLiveDistance`), and the value is ratcheted monotonic — a
    /// walked mile never ticks backwards, so a celebrated goal is final.
    @Published private(set) var liveDistance: Double = 0.0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// One-way handoff: GPS has taken over as the session's odometer because
    /// Core Motion can't measure it — ground covered without steps
    /// (stroller, cart) or a pedometer gone silent, witnessed by
    /// doppler-verified GPS miles reaching 1.5× the step span. One-way so
    /// the handoff can only ever step the number UP, never claw it back.
    private var gpsOwnsSession = false

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
        gpsOwnsSession = false
        outdoorPedometerMiles = nil
        lastPedometerProgressAt = nil
        lastPedometerProgressMiles = 0
        lastPedometerSampleAt = nil
        lastMotionPollAt = .distantPast
        pedometerErrored = false
        trackingStartedAt = Date()
        dopplerMovingMiles = 0
        movingSeconds = 0
        effortCurve = [(0, initialDistance)]
        lastEffortSample = (0, initialDistance)
        lastAccrualAt = nil
        lastMovingDopplerAt = nil
        lastFixMovementAt = nil
        lastFixAcceptedAt = nil
        evidenceAnchor = nil
        isAutoPaused = false
        automotiveVerdict = false
        automotiveVerdictAt = nil
        lastLocation = nil
        lastRoutePoint = nil
        lastFixAt = nil
        isUsingPedometer = (locationType == .indoor)
        pedometerOffset = initialDistance
        armTrackingWatchdog(force: true)

        if locationType == .indoor {
            if CMPedometer.isDistanceAvailable() {
                pedometer.startUpdates(from: Date()) { [weak self] pedometerData, error in
                    guard let self = self, let data = pedometerData, error == nil else { return }

                    if let distance = data.distance {
                        let distanceInMiles = distance.doubleValue * 0.000621371
                        DispatchQueue.main.async {
                            self.ingestIndoorPedometerDistance(distanceInMiles)
                        }
                    }
                }
                // Keep-alive: pedometer updates are suspended with the app when
                // the phone locks (CoreMotion batches them until foreground),
                // which froze the Live Activity for indoor workouts. Running
                // low-accuracy location updates keeps the app alive via the
                // `location` background mode; distance from these fixes is
                // ignored in pedometer mode (see didUpdateLocations).
                // The keep-alive only buys us a live PROCESS — the pedometer
                // STREAM is still batched, so the heartbeat's
                // `queryPedometerData` poll is what actually keeps indoor
                // distance moving while the phone is locked.
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

        startPauseHeartbeat()
    }

    /// Keeps the movement witnesses fresh and the chip honest without
    /// depending on a location callback. Fires in the background too: the
    /// `location` background mode keeps the app (and this run loop) alive for
    /// the whole outdoor session.
    private func startPauseHeartbeat() {
        pauseHeartbeat?.invalidate()
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pollMotionWitnesses()
            self.refreshAutoPauseState()
        }
        // .common, not the default mode: a default-mode timer stalls while the
        // tracking screen is being scrolled, which is exactly when the user is
        // looking at the chip.
        RunLoop.main.add(timer, forMode: .common)
        pauseHeartbeat = timer
    }

    /// Pull CoreMotion's state instead of waiting to be pushed it.
    ///
    /// `CMPedometer.startUpdates` and `CMMotionActivityManager
    /// .startActivityUpdates` are both SUSPENDED once the phone locks —
    /// CoreMotion batches them and delivers on foreground. On a real outdoor
    /// walk that is the entire session, so both live streams are dead exactly
    /// when they're needed: the step witness freezes (chip sticks, and
    /// `stepsCorroborateMovement` fails closed, killing dopplerless accrual
    /// AND the route), and a stale automotive verdict can suppress everything.
    /// The historical queries have no such restriction, so poll them.
    ///
    /// This also keeps `outdoorPedometerMiles` — the odometer behind
    /// `liveDistance` — actually advancing in the background, which is the
    /// part that was costing real distance.
    private func pollMotionWitnesses() {
        guard isTracking, let start = trackingStartedAt else { return }
        let now = Date()
        guard now.timeIntervalSince(lastMotionPollAt) >= Self.motionPollInterval,
              now > start else { return }
        lastMotionPollAt = now

        // Runs in BOTH modes: indoors this IS the distance source, outdoors
        // it's the odometer plus the step witness.
        if CMPedometer.isDistanceAvailable(), CMPedometer.authorizationStatus() == .authorized {
            let indoor = isUsingPedometer
            pedometer.queryPedometerData(from: start, to: now) { [weak self] data, error in
                guard let self, error == nil, let distance = data?.distance else { return }
                let miles = distance.doubleValue * 0.000621371
                DispatchQueue.main.async {
                    if indoor {
                        self.ingestIndoorPedometerDistance(miles)
                    } else {
                        self.ingestPedometerDistance(miles)
                    }
                }
            }
        }

        // The classifier only gates outdoor GPS accrual/route.
        if !isUsingPedometer, CMMotionActivityManager.isActivityAvailable() {
            let since = now.addingTimeInterval(-Self.motionPollInterval * 3)
            activityClassifier.queryActivityStarting(from: since, to: now, to: .main) { [weak self] activities, _ in
                guard let self, let latest = activities?.last else { return }
                self.ingestActivityVerdict(latest)
            }
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
            self.ingestActivityVerdict(activity)
        }
    }

    /// Single entry point for classifier verdicts (live stream + poll), so the
    /// latch always carries a timestamp and can therefore expire.
    private func ingestActivityVerdict(_ activity: CMMotionActivity) {
        automotiveVerdict = activity.automotive && activity.confidence != .low
        automotiveVerdictAt = Date()
        refreshAutoPauseState()
    }

    private func startGPSTracking() {
        if authorizationStatus == .notDetermined {
            requestPermission()
        }
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
    }

    /// Run the pedometer ALONGSIDE outdoor GPS — this is the session's
    /// odometer (see `liveDistance`); GPS draws the route. Deliberately left
    /// nil until CoreMotion actually delivers — nil means "hasn't spoken",
    /// so a silently-dead pedometer reads as zero span until the doppler
    /// handoff gives GPS the odometer, rather than masquerading as a
    /// measured zero forever.
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
                self.ingestPedometerDistance(miles)
            }
        }
    }

    /// Single entry point for INDOOR pedometer readings (live stream +
    /// `pollMotionWitnesses`). Main thread only. `miles` is the pedometer's
    /// own span since its start; the offset carries a recovered workout's
    /// prior distance.
    ///
    /// Clamped monotonic — the live stream and the poll can land out of order,
    /// and the class invariant is that the tracking system never overwrites
    /// `currentDistance` with a smaller value.
    private func ingestIndoorPedometerDistance(_ miles: Double) {
        lastPedometerSampleAt = Date()
        currentDistance = max(currentDistance, pedometerOffset + miles)
        refreshLiveDistance()
        persistDistanceThrottled()
        // Liveness rides the data callbacks, not a view timer: a delivered
        // reading proves the process is alive, so slide the dead-man watchdog
        // forward and beat the presence heartbeat (both self-throttled).
        armTrackingWatchdog()
        LivePresenceService.shared.tick()
    }

    /// Single entry point for outdoor pedometer readings (live stream +
    /// `pollMotionWitnesses`). Main thread only.
    private func ingestPedometerDistance(_ miles: Double) {
        // CoreMotion ANSWERED — distinct from "the walker stepped". The step
        // gate fails open on a stale sampler, so this stamp is what keeps it
        // strict while the sampler is genuinely alive.
        lastPedometerSampleAt = Date()
        // A successful reading proves the pedometer CAN measure, so a
        // transient stream error no longer disables it for the session. Safe
        // in both directions: `liveDistance` is ratcheted and `gpsOwnsSession`
        // is one-way, so recovering the odometer can only hold the number, and
        // the step gate going strict again is correct once CoreMotion answers.
        pedometerErrored = false
        // ≥ ~2 m of new step distance = the walker is actually
        // stepping right now. Feeds stepsCorroborateMovement.
        if miles - lastPedometerProgressMiles >= 0.0012 {
            lastPedometerProgressMiles = miles
            lastPedometerProgressAt = Date()
        }
        // Clamped monotonic: this span is displayed AND saved, so a
        // revised-down batch must never tick the workout backwards.
        outdoorPedometerMiles = max(outdoorPedometerMiles ?? 0, miles)
        refreshLiveDistance()
        // The poll now advances the odometer in the background, where the
        // foreground timer is suspended — persist so a termination mid-walk
        // recovers the distance the user actually covered.
        persistDistanceThrottled()
        refreshAutoPauseState()
        // Second liveness source: keeps the watchdog honest through GPS dead
        // zones while the walker is still stepping.
        armTrackingWatchdog()
    }

    /// True while there is positive evidence the walker is moving on foot:
    /// step distance advanced within `stepWitnessWindow` (with a startup grace
    /// window while the first pedometer batch is in flight). Fails OPEN
    /// whenever the pedometer can't testify — no hardware, no Motion
    /// permission, errored, or the sampler has gone QUIET — so the gate can
    /// never brick tracking; those sessions just keep the doppler+floor gates
    /// alone.
    ///
    /// The staleness clause is load-bearing: `startUpdates` is batched by
    /// CoreMotion once the phone locks, so on a locked-screen walk this used
    /// to go false 60s in and stay there, rejecting every dopplerless fix for
    /// the rest of the session — no distance under tree cover, no route. It
    /// stays STRICT while `pollMotionWitnesses` is getting answers, which is
    /// what preserves the seated-multipath defence (a live sampler reporting
    /// no steps still closes the gate — that's the 3h-ballgame case).
    private var stepsCorroborateMovement: Bool {
        guard CMPedometer.isDistanceAvailable(),
              CMPedometer.authorizationStatus() == .authorized,
              !pedometerErrored,
              outdoorPedometerMiles != nil,
              let sampledAt = lastPedometerSampleAt,
              Date().timeIntervalSince(sampledAt) < Self.stepWitnessWindow else { return true }
        let reference = lastPedometerProgressAt ?? trackingStartedAt ?? Date()
        return Date().timeIntervalSince(reference) < Self.stepWitnessWindow
    }

    /// (Re-)arm the dead-man notification. Called from every live data
    /// callback, throttled to once a minute; `force` skips the throttle at
    /// session start. Same identifier = each add REPLACES the pending one,
    /// so the fire date keeps sliding forward while the app is alive.
    private func armTrackingWatchdog(force: Bool = false) {
        guard isTracking || force else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastWatchdogArm) >= 60 else { return }
        lastWatchdogArm = now

        let content = UNMutableNotificationContent()
        content.title = "Is your workout still tracking?"
        content.body = "iOS may have stopped Mile A Day in the background. Open the app to check — your progress is saved and can resume."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: Self.watchdogNotificationId,
                content: content,
                trigger: trigger
            )
        )
    }

    private func cancelTrackingWatchdog() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.watchdogNotificationId]
        )
    }

    func stopTracking() {
        guard isTracking else { return }
        isTracking = false
        cancelTrackingWatchdog()

        // Pedometer runs in BOTH modes now (distance source indoors, cross-
        // check odometer outdoors) — always stop it.
        pedometer.stopUpdates()
        activityClassifier.stopActivityUpdates()
        pauseHeartbeat?.invalidate()
        pauseHeartbeat = nil
        // Location runs in both modes (distance source for GPS, keep-alive
        // for pedometer) — always stop it.
        locationManager.stopUpdatingLocation()
        lastLocation = nil
        lastRoutePoint = nil
        evidenceAnchor = nil
        isAutoPaused = false
        automotiveVerdict = false
        automotiveVerdictAt = nil
    }

    /// Re-derive `liveDistance` after either instrument moved (main thread
    /// only). This IS the save: the finish persists `liveDistance` verbatim,
    /// so everything here holds for the recap and HealthKit too.
    ///
    /// Core Motion's calibrated distance is the odometer; GPS's job is the
    /// route. GPS takes the odometer over ONLY when Core Motion cannot
    /// measure the session:
    ///   - hard unavailability — Motion permission denied/restricted or the
    ///     pedometer stream errored (fail OPEN, never trust a frozen zero);
    ///   - ground covered without steps — stroller, cart, or a pedometer
    ///     gone silent — witnessed by doppler-verified GPS miles reaching
    ///     1.5× the step span. One-way (`gpsOwnsSession`): once GPS owns
    ///     the session it keeps it, so the handoff steps the number UP and
    ///     never claws it back.
    /// GPS's absurd-overcount shapes (seated multipath drift, driving) are
    /// killed at accrual time by the gates — doppler-stationary skip, steps
    /// corroboration, teleport cap, automotive suspension — which is what
    /// makes it a safe stand-in. The outer ratchet keeps the number
    /// monotonic across the handoff edges (mid-walk Motion grant, pedometer
    /// error): the count may briefly hold, it never ticks backwards.
    private func refreshLiveDistance() {
        // Every odometer move is a ghost-race sample point (both modes) — the
        // curve tracks the displayed number, so it can't disagree with it.
        defer { sampleEffortCurve() }
        guard !isUsingPedometer else {
            // Indoor: currentDistance already IS the pedometer.
            liveDistance = max(liveDistance, currentDistance)
            return
        }
        let gpsSpan = max(0, currentDistance - sessionStartDistance)
        let pedometerSpan = outdoorPedometerMiles ?? 0
        if !gpsOwnsSession, dopplerMovingMiles >= max(0.1, pedometerSpan * 1.5) {
            gpsOwnsSession = true
            print("[WorkoutLocationManager] 📏 GPS took the odometer (doppler \(String(format: "%.2f", dopplerMovingMiles)) mi vs steps \(String(format: "%.2f", pedometerSpan)) mi)")
        }
        let pedometerCanMeasure = !pedometerErrored
            && CMPedometer.authorizationStatus() == .authorized
        let span = (gpsOwnsSession || !pedometerCanMeasure) ? gpsSpan : pedometerSpan
        liveDistance = max(liveDistance, sessionStartDistance + span)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Liveness bookkeeping runs in BOTH modes: any delivered fix proves
        // the app is alive (slide the watchdog forward) and feeds the
        // no-signal banner.
        lastFixAt = Date()
        armTrackingWatchdog()
        // Presence heartbeat rides the same callback: view timers suspend in
        // the background, delegate callbacks don't. Self-throttled to ~45s.
        LivePresenceService.shared.tick()

        // In pedometer mode location is only a background keep-alive —
        // distance comes from CMPedometer and there's no meaningful route.
        guard !isUsingPedometer else { return }

        // Process EVERY delivered fix in order — background delivery batches
        // several fixes per callback, and taking only the last one flattened
        // curves into chords whenever the app was backgrounded.
        for newLocation in locations {
            // Freshness is non-negotiable for every consumer: cold-start
            // replays deliver cached fixes seconds old whose jump to the first
            // real fix used to be counted as walked.
            guard newLocation.horizontalAccuracy > 0,
                  abs(newLocation.timestamp.timeIntervalSinceNow) < 15 else {
                continue
            }

            // Evidence runs on a LOOSER accuracy bar than accrual. A 70m fix
            // is far too vague to add to the mile, but a walker displacing
            // 60m across it is still unambiguously moving — and holding
            // evidence to the accrual bar is what let a bad-signal stretch
            // read as "stopped".
            noteMovementEvidence(from: newLocation)

            // Accrual + route keep the strict bar.
            guard newLocation.horizontalAccuracy < 50 else { continue }

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

        pollMotionWitnesses()
        refreshAutoPauseState()
    }

    /// Movement witnesses that don't depend on distance ACCRUING.
    ///
    /// Two independent signals:
    ///   - valid doppler above the stationary bar — the freshest "in motion"
    ///     witness there is. Dopplerless (speed == -1) fixes deliberately
    ///     don't count here: seated multipath drift is exactly that shape.
    ///   - fix-to-fix displacement across ~10s, measured from `evidenceAnchor`
    ///     rather than the accrual anchor. THIS is the turnaround fix: an
    ///     out-and-back holds `lastLocation` while displacement round-trips
    ///     under the noise floor, but the walker is still covering ~14m every
    ///     10s, which no jitter floor mistakes for standing still.
    private func noteMovementEvidence(from fix: CLLocation) {
        guard fix.horizontalAccuracy < 120 else { return }
        lastFixAcceptedAt = Date()

        if fix.speed >= Self.stationarySpeed, !isConfidentlyAutomotive {
            lastMovingDopplerAt = Date()
        }

        guard let anchor = evidenceAnchor else {
            evidenceAnchor = fix
            return
        }
        let dt = fix.timestamp.timeIntervalSince(anchor.timestamp)
        guard dt >= Self.evidenceAnchorSpan else { return }
        let displacement = fix.distance(from: anchor)
        // Scaled to the worse endpoint so a stationary phone's jitter can't
        // masquerade as a walk, and capped so a multipath teleport can't either.
        let floor = max(6, max(anchor.horizontalAccuracy, fix.horizontalAccuracy) * 0.5)
        if displacement >= floor,
           displacement / dt <= Self.maxPlausibleSpeed,
           !isConfidentlyAutomotive {
            lastFixMovementAt = Date()
        }
        evidenceAnchor = fix
    }

    /// Visible movement-gate state — paused only when EVERY movement witness
    /// has gone quiet (see the property's rationale). Distance accrual is NOT
    /// consulted alone: held-anchor stalls (turnarounds) aren't stillness.
    private func refreshAutoPauseState() {
        guard isTracking, !isUsingPedometer else { return }
        let evidence = [
            lastAccrualAt,
            lastMovingDopplerAt,
            lastFixMovementAt,
            lastPedometerProgressAt,
            trackingStartedAt
        ]
        .compactMap { $0 }
        .max() ?? Date()
        let quiet = Date().timeIntervalSince(evidence) > Self.movementEvidenceWindow
        // Blind is not stopped. If no usable fix has arrived in the window we
        // have no standing to claim the walker stopped — a tunnel, a dense
        // canyon or a paused location stream is silence ABOUT movement, not
        // evidence OF stillness. Erring toward "not paused" is the whole
        // point: the chip is cosmetic, but showing it mid-stride reads as
        // "tracking broke".
        let blind = lastFixAcceptedAt.map {
            Date().timeIntervalSince($0) > Self.movementEvidenceWindow
        } ?? true
        let paused = quiet && !blind
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
            if doppler >= Self.stationarySpeed {
                dopplerMovingMiles += distanceInMiles
            }
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
