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
    /// Set alongside the two above when the ghost was a FRIEND's mile. This is
    /// what lets the server tell them they were caught — without it the win is
    /// recorded but anonymous.
    static let ghostFriendMetadataKey = "MAD_ghost_friend_id"

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
    /// Apple Fitness uses for phone-only walking/running distance, and one
    /// side of the two-instrument max behind `liveDistance`. Nil until
    /// CoreMotion actually delivers. Published so the tracking UI refreshes
    /// on step progress while a GPS anchor holds.
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

    // MARK: - Manual pause
    //
    // Deliberately NOT the same concept as `isAutoPaused`. Auto-pause is a
    // GUESS about movement, rendered as a chip, biased toward not-paused, and
    // it gates nothing. This is the user's explicit instruction and it gates
    // everything: accrual, the route, the pedometer span, the moving clock and
    // the saved duration. They never show at once — manual pause wins the
    // display and suppresses the auto chip (see `pause()`).
    //
    // There is no auto-RESUME on detected movement, on purpose. The movement
    // gate is lenient by design, and a false "you're moving" resume would
    // restart accrual from a stale anchor and quietly cost the walker distance.
    // Manual pause, manual resume.

    /// True while the user has explicitly paused. Published so the tracker,
    /// the banner and the Live Activity all read one flag.
    @Published private(set) var isPaused = false
    /// Every pause this session has taken, open interval last. Mirrored to
    /// `InProgressWorkoutStore` on each edge so a relaunch resumes PAUSED and
    /// the finish can build HealthKit pause/resume events from real timestamps.
    private(set) var pauseIntervals: [WorkoutPauseInterval] = []
    /// When tracking last resumed — the movement gate's grace window. Without
    /// it, every witness is stale the moment a long pause ends, so the first
    /// fresh fix (which clears `blind`) would flash AUTO-PAUSED at a walker
    /// who has just started moving again.
    private var lastResumeAt: Date?

    /// Total paused seconds, including a pause still in flight. Feeds the
    /// tracker's frozen clock, the recap duration and the indoor race clock.
    var pausedSeconds: TimeInterval { pauseIntervals.totalPausedSeconds() }

    /// Raw pedometer span since this session's pedometer start (miles),
    /// clamped monotonic. Held apart from the EXPOSED span because CMPedometer
    /// is an odometer: it keeps counting steps through a pause whether or not
    /// we are listening, so merely ignoring readings while paused would credit
    /// the whole pause on the first reading after resume. The exposed span is
    /// `raw - excludedPedometerMiles`.
    private var rawPedometerMiles: Double = 0
    /// Pedometer ground banked during pauses that have already ended.
    private var committedPausedPedometerMiles: Double = 0
    /// `rawPedometerMiles` at the moment the current pause began; nil while
    /// running. Makes the in-flight pause's exclusion live, so the exposed
    /// span is frozen during the pause rather than corrected after it.
    private var pauseAnchorPedometerMiles: Double?

    /// Pedometer distance that must never reach `liveDistance` — completed
    /// pauses plus the one currently open.
    private var excludedPedometerMiles: Double {
        committedPausedPedometerMiles
            + max(0, rawPedometerMiles - (pauseAnchorPedometerMiles ?? rawPedometerMiles))
    }

    /// The pedometer span this session is allowed to count.
    private var countablePedometerMiles: Double {
        max(0, rawPedometerMiles - excludedPedometerMiles)
    }

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
            // Manual pause must come out of the indoor clock explicitly.
            // Outdoors `movingSeconds` only advances inside `accrueDistance`,
            // which a pause blocks, so it freezes for free — but the treadmill
            // clock is wall time, and without this subtraction a racer could
            // beat their ghost by standing on the side rails.
            return max(0, Date().timeIntervalSince(start) - pausedSeconds)
        }
        return movingSeconds
    }

    /// Pace over roughly the last minute, in seconds per mile. Nil until the
    /// curve holds two samples far enough apart to mean anything.
    ///
    /// This is the app's ONLY non-cumulative pace: every other pace figure —
    /// the recap, the Live Activity, the splits — divides total time by total
    /// distance, which can't tell you that someone who started fast is now
    /// dying. The ghost coach needs the derivative to say "you're slipping"
    /// instead of only "you're behind".
    ///
    /// Derived rather than plumbed: `effortCurve` is already sampled on every
    /// odometer move, so this adds no timer, no state and nothing to the
    /// accrual path. Two honest limits, both inherited from the curve:
    ///
    ///  - It only appends when distance strictly INCREASES, so a stopped
    ///    runner produces no new points and this figure goes stale rather than
    ///    falling. Callers must treat a stale value as "unknown", which is why
    ///    the freshness check against `raceClockSeconds` is here and not
    ///    optional.
    ///  - Resolution is one sample per ~0.02 mi or ~10 s, so this is good for
    ///    "fading over the last quarter" and useless for stride-level feedback.
    var recentPaceSecondsPerMile: Double? {
        guard effortCurve.count >= 2 else { return nil }
        let now = raceClockSeconds
        let newest = effortCurve[effortCurve.count - 1]

        // Gone quiet: either standing still or the odometer has stalled. Either
        // way the last window no longer describes what's happening NOW.
        guard now - newest.t <= 30 else { return nil }

        // Walk back for a window of at least 45s / 0.08 mi — enough to average
        // out the curve's coarse sampling without smearing a whole quarter.
        var anchor = newest
        for index in stride(from: effortCurve.count - 2, through: 0, by: -1) {
            anchor = effortCurve[index]
            if newest.t - anchor.t >= 45 || newest.d - anchor.d >= 0.08 { break }
        }

        let seconds = newest.t - anchor.t
        let miles = newest.d - anchor.d
        guard seconds >= 20, miles >= 0.01 else { return nil }
        let pace = seconds / miles
        // A window this short can produce nonsense off one bad sample; bound it
        // to the same window a real mile lives in.
        guard pace >= BestEffortStore.GhostTarget.minPlausibleSeconds,
            pace <= BestEffortStore.GhostTarget.maxPlausibleSeconds
        else { return nil }
        return pace
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
    /// TWO instruments, ONE number: the ratcheted max of the noise-gated GPS
    /// span and Core Motion's calibrated pedometer span. Deliberately
    /// LENIENT — the product rule is that a walker must never come up short
    /// of ground they actually covered and lose a streak to our arithmetic,
    /// so whichever instrument credits more of the walk wins:
    ///   - a mis-calibrated stride (phone in the pocket, a slow walker)
    ///     undercounts the pedometer by 10-40% — GPS covers it, from the
    ///     first yard, with no threshold to cross;
    ///   - tree cover / urban canyons starve GPS while the walker is plainly
    ///     stepping — the pedometer covers it;
    ///   - a stroller or cart covers ground with no steps at all — GPS
    ///     covers it.
    /// This can read slightly ABOVE Apple Fitness (which is pedometer-only
    /// on the phone); that is the accepted cost of never reading below a
    /// real walk. It is NOT a return to raw GPS: every absurd-overcount
    /// shape dies at accrual (doppler-stationary skip, steps corroboration,
    /// teleport cap, automotive suspension), which is what makes the max
    /// safe. Ratcheted monotonic — a walked mile never ticks backwards, so
    /// a celebrated goal is final.
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
    ///   - pauseIntervals: Pauses carried in by a recovery. An open interval
    ///     (nil `end`) means the workout was paused when the app died, so it
    ///     comes back paused — resuming it silently would count ground the user
    ///     never asked for.
    func startTracking(
        locationType: HKWorkoutSessionLocationType = .outdoor,
        initialDistance: Double = 0.0,
        pauseIntervals: [WorkoutPauseInterval] = []
    ) {
        // Prevent double-start
        guard !isTracking else { return }
        isTracking = true

        currentDistance = initialDistance
        liveDistance = initialDistance
        sessionStartDistance = initialDistance
        outdoorPedometerMiles = nil
        lastPedometerProgressAt = nil
        lastPedometerProgressMiles = 0
        lastPedometerSampleAt = nil
        lastMotionPollAt = .distantPast
        pedometerErrored = false
        trackingStartedAt = Date()
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

        // Manual-pause state. A recovered session restarts the pedometer from
        // scratch, so the mileage exclusions reset with it — only the pause
        // TIMELINE carries over (it's what the recap duration and the
        // HealthKit events are built from).
        self.pauseIntervals = pauseIntervals
        // Written out rather than `last?.end == nil`: that chains to `Date??`,
        // where an OPEN pause is `.some(nil)` and compares UNEQUAL to nil — it
        // would report paused only when there were no pauses at all.
        isPaused = pauseIntervals.last.map { $0.end == nil } ?? false
        lastResumeAt = nil
        rawPedometerMiles = 0
        committedPausedPedometerMiles = 0
        // Recovering INTO a pause: anchor at zero so anything walked before
        // the user taps resume is excluded, exactly as a live pause would.
        pauseAnchorPedometerMiles = isPaused ? 0 : nil

        armTrackingWatchdog(force: !isPaused)

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
        applyLocationPowerProfile()
    }

    // MARK: - Manual pause / resume

    /// Freeze the workout at the user's request.
    ///
    /// Everything that could credit ground stops here — accrual, the route
    /// trace, the pedometer span, the moving clock — but the location stream
    /// itself deliberately keeps running. The `location` background mode is
    /// the ONLY reason this process survives a locked screen; calling
    /// `stopUpdatingLocation()` for the duration of a pause invites iOS to
    /// suspend and then terminate the app, and the user comes back to a dead
    /// workout instead of a paused one. So the fixes keep arriving and get
    /// thrown away, at the coarse accuracy indoor mode already uses as its
    /// keep-alive — a long pause costs about what indoor tracking costs.
    func pause() {
        guard isTracking, !isPaused else { return }
        isPaused = true
        pauseIntervals.append(WorkoutPauseInterval(start: Date(), end: nil))
        // Freeze the pedometer odometer where it stands. It keeps counting
        // through the pause regardless; this anchor is what keeps that ground
        // out of `liveDistance` (see `excludedPedometerMiles`).
        pauseAnchorPedometerMiles = rawPedometerMiles
        // Manual pause outranks the guess — two pause chips at once is
        // nonsense, and the auto one would flap underneath this anyway.
        isAutoPaused = false
        // The dead-man switch slides forward off location/pedometer callbacks.
        // A paused workout stops feeding it, so 5 minutes in it would ask "is
        // your workout still tracking?" about a workout the user just paused.
        cancelTrackingWatchdog()
        applyLocationPowerProfile()
        persistPauseState()
    }

    /// Resume from a manual pause.
    ///
    /// Every anchor is dropped on the way out. This is the load-bearing half:
    /// the accrual gate only rejects a segment implying more than 12 m/s, so a
    /// 10-minute pause spent walking 300 m to the car resolves to an implied
    /// 0.5 m/s — it clears every gate and silently lands in the mile. Same
    /// story for the route (a stale anchor draws a chord across the pause) and
    /// the fix-to-fix movement witness.
    func resume() {
        guard isTracking, isPaused else { return }
        isPaused = false
        if !pauseIntervals.isEmpty, pauseIntervals[pauseIntervals.count - 1].end == nil {
            pauseIntervals[pauseIntervals.count - 1].end = Date()
        }
        if let anchor = pauseAnchorPedometerMiles {
            committedPausedPedometerMiles += max(0, rawPedometerMiles - anchor)
            pauseAnchorPedometerMiles = nil
        }
        lastLocation = nil
        lastRoutePoint = nil
        evidenceAnchor = nil
        // Grace window for the movement gate: after a long pause every witness
        // is stale, so the first fresh fix would clear `blind` and flash
        // AUTO-PAUSED at someone who has just started walking again.
        lastResumeAt = Date()
        armTrackingWatchdog(force: true)
        applyLocationPowerProfile()
        persistPauseState()
    }

    /// GPS precision follows the pause state: full accuracy while the workout
    /// is live, the coarse keep-alive tier while paused (and always coarse in
    /// pedometer mode, where fixes are only ever a keep-alive).
    private func applyLocationPowerProfile() {
        locationManager.desiredAccuracy = (isPaused || isUsingPedometer)
            ? kCLLocationAccuracyHundredMeters
            : kCLLocationAccuracyBest
    }

    /// Mirror the pause timeline to disk on every edge. The tracker's 1 Hz
    /// tick can't be trusted with this — it dies with the cover — and a pause
    /// that never reached disk would come back RUNNING after a termination,
    /// with the whole pause counted as active time.
    private func persistPauseState() {
        InProgressWorkoutStore.savePauseState(isPaused: isPaused, intervals: pauseIntervals)
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
            // Live Activity freshness rides this heartbeat, NOT the tracker
            // view's timer — that one stops on lock and on dismiss, which is
            // exactly when the lock screen was flipping to TRACKING
            // INTERRUPTED over a workout that was accruing fine. Self-throttled
            // to ~60s.
            WorkoutLiveActivityKeepAlive.beat()
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
    /// This also keeps `outdoorPedometerMiles` — one side of the max behind
    /// `liveDistance` — actually advancing in the background, which is the
    /// part that was costing real distance.
    private func pollMotionWitnesses() {
        guard isTracking, let start = trackingStartedAt else { return }
        let now = Date()
        guard now.timeIntervalSince(lastMotionPollAt) >= Self.motionPollInterval,
              now > start else { return }
        lastMotionPollAt = now

        // Runs in BOTH modes: indoors this IS the distance source, outdoors
        // it's one side of the distance max plus the step witness.
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

    /// Run the pedometer ALONGSIDE outdoor GPS — one side of the distance
    /// max (see `liveDistance`); GPS accrues the other side and draws the
    /// route. Deliberately left nil until CoreMotion actually delivers —
    /// nil means "hasn't spoken", so a silently-dead pedometer contributes
    /// zero to the max (GPS carries the walk) rather than masquerading as a
    /// measured zero forever.
    private func startOutdoorPedometerCrossCheck() {
        guard CMPedometer.isDistanceAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] pedometerData, error in
            guard let self else { return }
            if error != nil {
                // Motion denied / CoreMotion failure: mark it so the step
                // witness fails OPEN instead of trusting a frozen zero. The
                // distance needs no fallback switch — the pedometer side of
                // the max simply stops advancing and gated GPS carries the
                // walk; the ratchet keeps the number from ever ticking down.
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
        // Keep ingesting through a pause rather than dropping readings: the
        // odometer counts regardless, so the only way to keep paused ground
        // out is to keep MEASURING it and subtract it. `countablePedometerMiles`
        // is frozen for the whole pause and steps forward again on resume.
        rawPedometerMiles = max(rawPedometerMiles, miles)
        currentDistance = max(currentDistance, pedometerOffset + countablePedometerMiles)
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
        // transient stream error no longer disables its evidence for the
        // session. Safe: `liveDistance` is a ratcheted max of both
        // instruments, so the pedometer coming back can only hold or raise
        // the number, and the step gate going strict again is correct once
        // CoreMotion answers.
        pedometerErrored = false
        // ≥ ~2 m of new step distance = the walker is actually
        // stepping right now. Feeds stepsCorroborateMovement.
        if miles - lastPedometerProgressMiles >= 0.0012 {
            lastPedometerProgressMiles = miles
            lastPedometerProgressAt = Date()
        }
        // Same rebase as indoors: the raw odometer keeps running through a
        // pause, so paused ground is measured and then subtracted rather than
        // ignored — ignoring it would credit the entire pause on the first
        // reading after resume, since each reading is a span from session
        // start, not a delta.
        rawPedometerMiles = max(rawPedometerMiles, miles)
        // Clamped monotonic: this span is displayed AND saved, so a
        // revised-down batch must never tick the workout backwards.
        outdoorPedometerMiles = max(outdoorPedometerMiles ?? 0, countablePedometerMiles)
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
        // A paused workout isn't a stalled one. Callbacks keep arriving (the
        // location stream stays up as the process keep-alive), so without this
        // the watchdog would keep re-arming and eventually fire only if the
        // app died — but `pause()` cancels it outright, and letting any
        // callback re-arm it would undo that.
        guard !isPaused else { return }
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
        // Manual-pause state is session-scoped. Callers that need the pause
        // timeline at finish (HealthKit events, the recap duration) capture it
        // BEFORE stopping — see `stopWorkout`.
        isPaused = false
        pauseIntervals = []
        lastResumeAt = nil
        rawPedometerMiles = 0
        committedPausedPedometerMiles = 0
        pauseAnchorPedometerMiles = nil
    }

    /// Re-derive `liveDistance` after either instrument moved (main thread
    /// only). This IS the save: the finish persists `liveDistance` verbatim,
    /// so everything here holds for the recap and HealthKit too.
    ///
    /// The span is the MAX of the two instruments — see the `liveDistance`
    /// doc for why lenient is the rule. This replaced a pedometer-primary
    /// design whose GPS handoff needed doppler miles to reach 1.5× the step
    /// span: a stride calibrated 10-40% short (phone in a pocket, a slow
    /// walker) undercounts steadily but never trips 1.5×, so the walker lost
    /// the difference for the whole session — the exact "0.34 became 0.22"
    /// class of complaint, structurally. With the max there is no threshold
    /// to cross and no handoff cliff: whichever instrument credited more of
    /// the real walk wins, per refresh, from the first yard.
    ///
    /// GPS's absurd-overcount shapes (seated multipath drift, driving) are
    /// killed at ACCRUAL by the gates — doppler-stationary skip, steps
    /// corroboration, teleport cap, automotive suspension — which is what
    /// makes its side of the max safe. The pedometer side is clamped
    /// monotonic at ingest. The outer ratchet holds the number monotonic
    /// across every edge (mid-walk Motion grant, pedometer error, recovery
    /// resume): the count may briefly hold, it never ticks backwards.
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
        liveDistance = max(liveDistance, sessionStartDistance + max(gpsSpan, pedometerSpan))
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

        // Manually paused: the stream stays up purely to keep this process
        // alive, so every fix is discarded. Nothing is anchored either —
        // `resume()` re-anchors from the first fix after the pause, which is
        // what stops the pause gap being counted as one long walked segment.
        guard !isPaused else { return }

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
        // Manual pause owns the display while it's on. `pause()` already
        // cleared the chip; this keeps the heartbeat from re-raising it.
        guard !isPaused else { return }
        let evidence = [
            lastAccrualAt,
            lastMovingDopplerAt,
            lastFixMovementAt,
            lastPedometerProgressAt,
            lastResumeAt,
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

    /// The state this banner is actually rendering — the reloaded copy once
    /// the tick timer has one, else what it was handed.
    private var current: InProgressWorkoutState { latestState ?? state }

    /// Elapsed time, pause-excluded, matching the tracker's clock. Read from
    /// the persisted intervals rather than the manager so the banner needs no
    /// dependency on it; the manager writes them through on every pause edge.
    private var realTimeElapsedSeconds: TimeInterval {
        let paused = current.pauseIntervals?.totalPausedSeconds(asOf: currentTime)
            ?? current.pausedTime
        return max(0, currentTime.timeIntervalSince(current.startTime) - paused)
    }

    private var isPaused: Bool { current.isPaused }

    private var formattedTime: String {
        let minutes = Int(realTimeElapsedSeconds) / 60
        let seconds = Int(realTimeElapsedSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var currentDistance: Double {
        current.currentDistance
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

                    // A paused workout must not wear a play glyph on a banner
                    // whose whole job is to say what's happening right now.
                    Image(systemName: isPaused ? "pause.fill" : "play.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .bold))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(isPaused ? "Workout paused" : "Workout in progress")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Text("\(currentDistance.milesText) mi • \(formattedTime)")
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
