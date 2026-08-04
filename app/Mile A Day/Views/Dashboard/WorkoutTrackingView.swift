import SwiftUI
import HealthKit
import UIKit
import CoreLocation
import CoreMotion
import ActivityKit

// MARK: - Workout Tracking View

struct WorkoutTrackingView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    let goalDistance: Double
    let startingDistance: Double
    /// Non-nil when this workout is part of a Buddy Walk.
    ///
    /// A buddy session DECORATES this tracker — it does not replace it. There is
    /// no second tracker, no second workout lock, and no second HealthKit save
    /// path, which is exactly why streaks, competitions and badges keep working
    /// untouched. When set, three things change: the activity/location pickers
    /// and the local 3-2-1 are skipped (the lobby already ran a server-synced
    /// countdown), the roster strip appears above the metrics, and the existing
    /// 1 Hz tick also reports progress to the backend.
    var buddySessionId: String? = nil
    @Environment(\.dismiss) var dismiss

    // Shared singleton — tracking keeps running when this view is dismissed
    // (e.g. user navigates back to the dashboard mid-workout).
    @ObservedObject private var locationManager = WorkoutLocationManager.shared
    // Pre-start wizard, in order: activity → location → race mode → ghost
    // options (only when the race is chosen) → presence consent (once ever) →
    // countdown. Each step owns exactly one question, and every one of these
    // flags must be cleared by anything that jumps straight to tracking (the
    // buddy hand-off and workout recovery both do).
    @State private var showActivitySelection = true
    @State private var showLocationTypeSelection = false
    @State private var showRaceModeSelection = false
    @State private var showGhostOptions = false
    /// Which way the next step transition should slide. Set immediately before
    /// the `withAnimation` that changes the step.
    @State private var wizardGoingBack = false
    @State private var selectedActivityType: HKWorkoutActivityType?
    @State private var selectedLocationType: HKWorkoutSessionLocationType = .outdoor
    @State private var countdownNumber = 3
    @State private var showCountdown = false
    @State private var isTracking = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var workoutStartDate: Date?
    @State private var showCompletion = false
    @State private var hasShownCompletion = false // Track if we've already shown completion
    @State private var showPreviousProgress = false // Show notification when reaching previous progress
    @State private var hasReachedPreviousProgress = false // Track if we've reached starting distance
    @State private var showRecap = false
    // Recap snapshots, frozen at the moment the workout ends. The recap can't
    // read live values: after the save, the dashboard re-feeds this view fresh
    // goal/startingDistance (which now INCLUDE the finished workout), so live
    // reads would double-count the daily total while the recap is on screen.
    @State private var recapDistance: Double = 0
    @State private var recapDuration: TimeInterval = 0
    @State private var recapStartingDistance: Double = 0
    @State private var recapGoalDistance: Double = 0
    @State private var showStopConfirmation = false // Confirmation before ending workout
    @State private var isStopping = false // Prevents double-stop and shows "Ending..." UI
    /// Whether the Live Activity goal-completed alert was already sent (or the
    /// goal was already met before this workout started, so no alert is due).
    @State private var hasSentGoalAlert = false
    /// Live Activity push throttling — the elapsed clock ticks natively via
    /// Text(timerInterval:), so pushes are only needed when distance moves.
    /// Pushing every second exhausted ActivityKit's update budget and the
    /// system started deferring updates (frozen activity on the lock screen).
    @State private var lastActivityPushDate: Date = .distantPast
    @State private var lastPushedDistance: Double = -1
    /// Live buddy roster, when this workout is part of a Buddy Walk.
    @ObservedObject private var buddyService = BuddySessionService.shared
    /// One-shot guard so the buddy auto-start can't fire twice if the view's
    /// onAppear runs again (it does when a sheet over it dismisses).
    @State private var hasAutoStartedBuddyWorkout = false
    @State private var showEndWorkoutError = false // Show error alert when starting fails (workout lock)
    @State private var endWorkoutErrorMessage = "" // Error message for the start-failure alert
    /// Health WRITE access is off — the save fails every time until re-enabled,
    /// so we offer an actionable path to Settings instead of a dead-end error.
    @State private var showHealthAccessAlert = false
    /// Quiet, non-blocking confirmation for a transient save failure where the
    /// mile still counts (Health access is fine) — no scary blocking alert.
    @State private var showSaveFallbackToast = false
    @State private var endWorkoutTimeoutTask: DispatchWorkItem? // Timeout for end workout flow
    @State private var trackingMetricsHeight: CGFloat = 0 // Measured height of the scrollable metrics area
    @State private var workoutSession: HKWorkoutSession?
    @State private var workoutBuilder: HKWorkoutBuilder?
    @State private var workoutActivity: Activity<WorkoutActivityAttributes>?
    // Mid-run photo capture: snap now, decide at the end of the run whether
    // it becomes the post. Shots are stashed in MidRunPhotoStash and offered
    // by the post-run photo prompt.
    @State private var showMidRunCamera = false
    @State private var midRunImage: UIImage?
    @State private var midRunSnapCount = 0
    /// Mid-run snap review tray (view + delete without touching tracking).
    @State private var showSnapTray = false
    /// Cheap downsampled thumb of the newest snap for the tray chip.
    @State private var lastSnapThumb: UIImage?
    @State private var showSnapSavedToast = false
    /// Import a photo taken on THIS walk from the library (time-windowed).
    @State private var showLibraryImport = false
    /// Transient result banner for a library import (message, success?).
    @State private var importToast: ImportToast?

    private struct ImportToast: Equatable {
        let text: String
        let ok: Bool
    }

    // Live presence: which friends are out right now + hypes that land
    // mid-walk. The consent interstitial runs ONCE (first tracked workout on
    // this build), between picking a location and the countdown.
    @ObservedObject private var livePresence = LivePresenceService.shared
    @State private var showFriendsOutSheet = false
    @State private var hypeToast: String?
    @AppStorage("hasAnsweredLivePresenceConsent") private var hasAnsweredLivePresenceConsent = false
    @State private var showPresenceConsent = false

    // Ghost race: opt-in per session from the pre-start card (never a
    // default). `raceGhost` is resolved once at startWorkout; nil = not
    // racing. The verdict freezes at the 1.0-mile crossing. Session-local by
    // design: recovery relaunches skip the pre-start flow, so a recovered
    // workout never races (its effort curve starts mid-distance anyway).
    //
    // WHAT is raced is the user's choice — recorded best, PR pace, or a time
    // they typed — held in `raceTarget` and picked on the ghost-options step.
    // It persists across sessions per activity, so a walker who races 12:00
    // gets 12:00 offered again next time rather than re-deciding every walk.
    @State private var raceArmed = false
    @State private var raceGhost: BestEffortStore.BestMileEffort?
    /// How to name the ghost in copy ("your best mile", "your target").
    @State private var raceGhostName = "your best mile"
    @State private var raceFinalDelta: TimeInterval?
    /// The win, from the moment it's decided until the HealthKit metadata
    /// stamp carries it onto the saved workout (and from there to the server
    /// and the feed).
    @State private var pendingGhostWin: GhostRaceWin?
    /// Chosen target, per activity, remembered between sessions.
    @AppStorage("ghostTargetV1.running") private var runTargetStorage = ""
    @AppStorage("ghostTargetV1.walking") private var walkTargetStorage = ""
    /// Drops the NEW pill on the arming card until the race is first set up.
    @AppStorage("hasArmedGhostRaceOnce") private var hasArmedGhostRaceOnce = false
    /// Set in `BuddyLobbyView` — the only screen a buddy session passes
    /// through, since the hand-off below skips the whole pre-start wizard
    /// where the solo race steps live. Read once on the buddy hand-off.
    @AppStorage("buddyGhostArmedV1") private var buddyGhostArmed = false

    private var raceActivityKey: String {
        selectedActivityType == .running ? "running" : "walking"
    }

    /// Seed pace for a run ghost — the backend fastest-mile PR (minutes/mile
    /// on the user model → seconds/mile).
    private var raceSeedPaceSeconds: Double? {
        let pace = userManager.currentUser.fastestMilePace
        guard pace > 0 else { return nil }
        return pace * 60
    }

    /// The stored target for the CURRENT activity, or the best default. Never
    /// nil: a custom time is always available, so every session can race.
    private var raceTarget: BestEffortStore.GhostTarget {
        let stored = raceActivityKey == "running" ? runTargetStorage : walkTargetStorage
        if let target = BestEffortStore.GhostTarget(storage: stored),
            BestEffortStore.resolve(
                target, activityKey: raceActivityKey,
                seedPaceSecondsPerMile: raceSeedPaceSeconds) != nil
        {
            return target
        }
        return BestEffortStore.defaultTarget(
            for: raceActivityKey, seedPaceSecondsPerMile: raceSeedPaceSeconds)
    }

    private func storeRaceTarget(_ target: BestEffortStore.GhostTarget) {
        if raceActivityKey == "running" {
            runTargetStorage = target.storage
        } else {
            walkTargetStorage = target.storage
        }
    }

    /// The armed target, resolved into something raceable.
    private var resolvedGhost: BestEffortStore.ResolvedGhost? {
        BestEffortStore.resolve(
            raceTarget, activityKey: raceActivityKey,
            seedPaceSecondsPerMile: raceSeedPaceSeconds)
    }

    /// Live ahead(+)/behind(−) seconds vs the ghost at the current distance,
    /// or the frozen verdict once the mile completes. Nil while not racing or
    /// in the first steps (no meaningful delta yet).
    private var raceDeltaSeconds: TimeInterval? {
        guard let ghost = raceGhost else { return nil }
        if let frozen = raceFinalDelta { return frozen }
        // Raced against the DISPLAYED distance (`liveDistance`), the same
        // figure the effort curve samples and Finish saves — reading raw GPS
        // accrual here would put the chip and the ring on different miles.
        let d = min(locationManager.liveDistance, 1.0)
        guard d > 0.02 else { return nil }
        return BestEffortStore.timeAtDistance(d, in: ghost) - locationManager.raceClockSeconds
    }

    /// Freeze the verdict the moment the live mile completes, using the
    /// interpolated crossing time from the effort curve — accurate no matter
    /// when the tick that notices runs.
    private func updateRaceFreezeIfNeeded() {
        guard let ghost = raceGhost, raceFinalDelta == nil,
            locationManager.liveDistance >= 1.0
        else { return }
        let curve = locationManager.effortCurve
        guard let crossing = curve.firstIndex(where: { $0.d >= 1.0 }) else { return }
        let b = curve[crossing]
        var myMileSeconds = b.t
        if crossing > 0 {
            let a = curve[crossing - 1]
            let span = b.d - a.d
            if span > 0 {
                myMileSeconds = a.t + (b.t - a.t) * ((1.0 - a.d) / span)
            }
        }
        withAnimation(.spring(response: 0.4)) {
            raceFinalDelta = ghost.seconds - myMileSeconds
        }
        MADHaptics.action()
    }

    // Workout distance only (starts at 0). `liveDistance` is THE number:
    // monotonic (never ticks down) and saved verbatim at Finish, so the
    // ring, the celebration, the recap, and HealthKit all agree by
    // construction. Showing raw GPS accrual here is how a jitter-inflated
    // walk read "100%" live and then dropped to 80% the moment Finish
    // reconciled it against the pedometer.
    private var currentDistance: Double {
        locationManager.liveDistance
    }

    // Total daily distance (starting + workout)
    private var totalDailyDistance: Double {
        startingDistance + currentDistance
    }

    private var progress: Double {
        min(totalDailyDistance / goalDistance, 1.0)
    }

    private var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Pre-start wizard chrome

    /// Back chevron + progress. Every pre-start step uses this so the three
    /// screens read as one flow rather than three views that happen to share a
    /// gradient. `step` is 1-based; the ghost-options screen passes 3 as well,
    /// because it's a sub-step of the race choice, not a fourth question.
    private func wizardTopBar(step: Int, onBack: @escaping () -> Void) -> some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Back")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    // contentShape expands the hit target to the full padded
                    // bounds so the first tap registers even on the gaps
                    // between the icon glyph and the text.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(index <= step ? 0.9 : 0.25))
                        .frame(width: 22, height: 4)
                }
            }
            .allowsHitTesting(false)
        }
        .padding(.top, 16)
    }

    /// What a step puts above its question. The ghost is drawn, not a symbol —
    /// SF Symbols has none that exists on the iOS 17 deployment target.
    enum WizardGlyph {
        case symbol(String)
        case ghost
    }

    /// Glyph + question, identical on every step.
    private func wizardHeader(glyph: WizardGlyph, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Group {
                switch glyph {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: 60))
                case .ghost:
                    GhostSprite(size: 62, glancesBack: true)
                }
            }
            .foregroundColor(.white)
            .frame(height: 72)

            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.title3)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    /// The shared layout of a "pick one of these" step.
    private func wizardStep<Options: View>(
        step: Int,
        glyph: WizardGlyph,
        title: String,
        subtitle: String,
        onBack: @escaping () -> Void,
        @ViewBuilder options: () -> Options
    ) -> some View {
        VStack(spacing: 0) {
            wizardTopBar(step: step, onBack: onBack)

            VStack(spacing: 40) {
                Spacer()
                wizardHeader(glyph: glyph, title: title, subtitle: subtitle)
                Spacer()
                VStack(spacing: 20) { options() }
                    .padding(.horizontal, 32)
                Spacer()
            }
        }
    }

    /// Forward slides in from the trailing edge, Back from the leading edge —
    /// so the wizard reads as depth rather than as unrelated crossfades.
    private var wizardTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: wizardGoingBack ? .leading : .trailing)
                .combined(with: .opacity),
            removal: .move(edge: wizardGoingBack ? .trailing : .leading)
                .combined(with: .opacity)
        )
    }

    // MARK: - Step 1: Activity

    private var activitySelectionContent: some View {
        wizardStep(
            step: 1,
            glyph: .symbol("figure.walk"),
            title: "Choose Activity Type",
            subtitle: "Select how you'll complete your mile",
            onBack: { dismiss() }
        ) {
            workoutOptionButton(icon: "figure.run", title: "Run", subtitle: "Track as a running workout") {
                selectActivity(.running)
            }
            workoutOptionButton(icon: "figure.walk", title: "Walk", subtitle: "Track as a walking workout") {
                selectActivity(.walking)
            }
        }
    }

    // MARK: - Step 2: Location

    private var locationTypeSelectionContent: some View {
        wizardStep(
            step: 2,
            glyph: .symbol(selectedActivityType == .running ? "figure.run" : "figure.walk"),
            title: "Choose Location",
            subtitle: "Where will you be working out?",
            onBack: { goBack(to: { showActivitySelection = true }, from: { showLocationTypeSelection = false }) }
        ) {
            workoutOptionButton(icon: "location.fill", title: "Outdoor", subtitle: "Uses GPS for accurate tracking") {
                selectLocationType(.outdoor)
            }
            workoutOptionButton(icon: indoorLocationIcon, title: "Indoor", subtitle: "Treadmill or indoors — uses motion sensors") {
                selectLocationType(.indoor)
            }
        }
    }

    // MARK: - Step 3: Race mode

    /// "Am I racing?" as a step of its own.
    ///
    /// It used to be a small card wedged under the Indoor/Outdoor buttons on a
    /// screen about something else, opening a modal sheet — which read as an
    /// add-on rather than a choice the flow cares about. Asking it here also
    /// means the activity is already locked in, so the target on offer is
    /// always the one for the activity being started.
    private var raceModeSelectionContent: some View {
        wizardStep(
            step: 3,
            glyph: .ghost,
            title: "Choose Your Mode",
            subtitle: "Race a time, or just log the miles.",
            onBack: { goBack(to: { showLocationTypeSelection = true }, from: { showRaceModeSelection = false }) }
        ) {
            workoutOptionButton(
                icon: selectedActivityType == .running ? "figure.run" : "figure.walk",
                title: "Just Track It",
                subtitle: "No clock to chase — every mile still counts."
            ) {
                chooseRaceMode(ghost: false)
            }

            workoutOptionButton(
                leading: {
                    GhostSprite(size: 34, glancesBack: true)
                        .frame(width: 50)
                },
                title: "Ghost Race",
                subtitle: ghostRaceSubtitle,
                featured: true,
                badge: hasArmedGhostRaceOnce ? nil : "NEW",
                accessory: {
                    if let ghost = resolvedGhost {
                        VStack(spacing: 0) {
                            Text(BestEffortStore.formatSeconds(ghost.effort.seconds))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .monospacedDigit()
                            Text("TO BEAT")
                                .font(.system(size: 8, weight: .black, design: .rounded))
                                .tracking(0.6)
                                .foregroundColor(.white.opacity(0.65))
                        }
                    } else {
                        optionChevron
                    }
                }
            ) {
                chooseRaceMode(ghost: true)
            }
        }
    }

    // MARK: - Step 4: Ghost options

    /// The picker, inline. Same content the buddy lobby shows as a sheet — it
    /// just gets the wizard's back bar and background instead of modal chrome.
    private var ghostOptionsContent: some View {
        VStack(spacing: 0) {
            wizardTopBar(step: 3) {
                goBack(to: { showRaceModeSelection = true }, from: { showGhostOptions = false })
            }

            GhostRaceOptionsContent(
                activityKey: raceActivityKey,
                seedPaceSeconds: raceSeedPaceSeconds,
                current: raceArmed ? raceTarget : nil,
                // White, not the workout color: this renders on the tracker's
                // red gradient, where a red CTA would vanish. Matches the
                // presence-consent step's primary button on the same screen.
                accent: .white,
                accentForeground: Color(red: 0.5, green: 0.15, blue: 0.2),
                declineTitle: "Skip the race",
                onRace: { armGhost($0) },
                onDecline: { chooseRaceMode(ghost: false) }
            )
        }
    }

    /// What to say about the finished mile.
    ///
    /// The win condition is BEATING THE GHOST YOU CHOSE, which is deliberately
    /// not the same thing as setting a record: someone chasing a 12:00 target
    /// who runs 11:20 has won their race even though their all-time best is
    /// 9:40. Keying the celebration off `.newBest` alone (as this did) left
    /// exactly that person with silence. A new record on top is extra credit,
    /// mentioned in the same breath.
    private func celebrateRaceOutcome(_ outcome: BestEffortStore.FinishOutcome) {
        let recordSeconds: Double? = {
            switch outcome {
            case .newBest(let seconds, _): return seconds
            case .baselineSet(let seconds): return seconds
            case .slower, .notAMile: return nil
            }
        }()

        // Raced and won: `raceFinalDelta` is the frozen verdict at the 1.0-mile
        // crossing — the same number the chip showed, so the popup can't
        // contradict what the user watched. Every figure below is derived from
        // that one frozen delta for the same reason.
        if let ghost = raceGhost, let delta = raceFinalDelta, delta > 0 {
            let win = GhostRaceWin(
                marginSeconds: delta,
                mileSeconds: max(0, ghost.seconds - delta),
                ghostSeconds: ghost.seconds,
                ghostName: raceGhostName,
                activityKey: raceActivityKey,
                newRecordSeconds: recordSeconds,
                // Whose ghost it was, when it was a friend's. Read from the
                // armed target rather than the resolved one — `ResolvedGhost`
                // deliberately keeps only a display name.
                friendUserId: raceTarget.friendUserId,
                workoutId: nil
            )
            // Held for the HealthKit metadata stamp further down this same
            // stop, which is what carries the win to the server.
            pendingGhostWin = win
            CelebrationManager.shared.addCelebration(.ghostBeaten(win: win))
            return
        }

        // Didn't race, or lost. A LOSS stays silent — the frozen chip already
        // told that story mid-workout and the ghost lives another day — but a
        // first-ever recorded mile is still worth naming, because it's what
        // makes the race available next time.
        guard raceGhost == nil, case .baselineSet = outcome, let seconds = recordSeconds else {
            return
        }
        CelebrationManager.shared.addCelebration(
            .milestone(
                title: "Baseline Mile Set",
                description:
                    "\(BestEffortStore.formatSeconds(seconds)) is your mile to beat. Race it from your next session.",
                icon: "stopwatch"
            ))
    }

    /// Copy for the Ghost Race option. `resolvedGhost` is what makes the
    /// promise concrete — the card shows the exact time it would race, so a
    /// repeat racer knows what tapping means before they tap.
    private var ghostRaceSubtitle: String {
        guard let ghost = resolvedGhost else {
            return "Chase your best mile, your PR, or a time you pick."
        }
        return "Chase \(ghost.shortName) for one mile — live ahead/behind on screen."
    }

    // MARK: - Countdown

    private var countdownContent: some View {
        VStack {
            Text("\(countdownNumber)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .scaleEffect(countdownNumber > 0 ? 1.0 : 0.5)
                .opacity(countdownNumber > 0 ? 1.0 : 0.0)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: countdownNumber)
        }
        .onAppear {
            startCountdown()
        }
    }

    // MARK: - Active Tracking

    private var activeTrackingContent: some View {
        // The two controls a user can never lose access to — the back button and,
        // critically, the Stop Workout button — are PINNED outside the scroll area
        // so they're always on screen regardless of device size or Dynamic Type.
        // Only the metrics in the middle scroll if they can't all fit, so nobody
        // ever has to scroll to find how to end their workout.
        GeometryReader { screen in
            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Dashboard")
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    Spacer()
                    // Mid-run snap: see something worth keeping, capture it in
                    // one tap, keep moving — the end-of-run prompt asks whether
                    // it becomes the post. Pinned in the top bar so it never
                    // crowds the metrics or the Stop button. Once snaps exist,
                    // a camera-app-style thumbnail chip opens the review tray.
                    if MADCameraView.isAvailable && !isStopping {
                        HStack(spacing: 10) {
                            if midRunSnapCount > 0 {
                                midRunTrayButton
                            }
                            midRunLibraryButton
                            midRunCameraButton
                        }
                        .padding(.trailing, 20)
                    }
                }
                .padding(.top, 16)

                // Scrollable metrics. The inner stack is pinned to at least the
                // viewport height (measured below) so the metrics stay vertically
                // centered when they fit, but collapse the Spacers and scroll when
                // they don't — without ever pushing the Stop button off-screen.
                // Spacing and ring size adapt to the screen height so compact
                // devices fit without scrolling while large ones keep the airy look.
                ScrollView {
                    VStack(spacing: metricSpacing(for: screen.size.height)) {
                        Spacer(minLength: 0)

                        // Health banner outranks the roster: "your tracking is
                        // broken" has to be the first thing read, or the user
                        // watches a crew scroll by while their own mile counts
                        // nothing.
                        trackingHealthBanner

                        // Buddy Walk roster sits ABOVE your own metrics: the
                        // crew is context, your distance is still the subject.
                        if buddySessionId != nil, let session = buddyService.session {
                            BuddyRosterStrip(
                                session: session,
                                currentUserId: buddyService.currentUserId
                            )
                            .padding(.horizontal, 20)
                        }

                        distanceDisplay

                        progressRing(diameter: ringDiameter(for: screen.size.height))

                        timeDisplay

                        friendsOutPulseRow

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: trackingMetricsHeight)
                    // Keep scrolled content from butting up against the pinned button.
                    .padding(.bottom, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { trackingMetricsHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, newValue in
                                trackingMetricsHeight = newValue
                            }
                    }
                )

                stopButton
            }
        }
        .opacity(showCompletion || showPreviousProgress ? 0 : 1)
        .overlay(previousProgressOverlay)
        .overlay(goalCompletionOverlay)
        .overlay(alignment: .top) { snapSavedToast }
        .overlay(alignment: .top) { importToastView }
        .overlay(alignment: .top) { saveFallbackToast }
        // Rendered HERE, not by the global banner: this view is a
        // fullScreenCover, which sits on top of MainTabView's InAppBanner
        // overlay — a hype toast anywhere else is invisible mid-workout.
        .overlay(alignment: .top) { hypeReceivedToast }
        .onChange(of: livePresence.sessionHypes.count) { oldCount, newCount in
            guard newCount > oldCount, let latest = livePresence.sessionHypes.last else { return }
            MADHaptics.action()
            withAnimation(.spring(response: 0.35)) {
                hypeToast = "\(latest.senderName) hyped you mid-\(selectedActivityType == .running ? "run" : "walk")!"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation { hypeToast = nil }
            }
            // Carry the hype onto the Live Activity right away — the 30s
            // cadence would otherwise sit on the moment.
            lastActivityPushDate = .distantPast
            updateLiveActivity()
        }
        .sheet(isPresented: $showFriendsOutSheet) {
            FriendsOutSheet(friends: livePresence.friendsOut)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    /// "🔥 Davey hyped you mid-walk!" — same quiet pattern as the snap toast.
    @ViewBuilder
    private var hypeReceivedToast: some View {
        if let text = hypeToast {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.orange)
                Text(text)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.75))
                    .overlay(Capsule().strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
            )
            .padding(.top, 72)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    // MARK: - Mid-Run Photo Capture

    /// Camera-app pattern: the newest snap as a thumbnail chip beside the
    /// shutter. Tapping it opens the review tray — a sheet OVER the tracking
    /// screen, so distance/time keep counting underneath — where shots can be
    /// checked full-size, saved, or deleted on the spot instead of waiting
    /// for the end-of-run prompt.
    private var midRunTrayButton: some View {
        Button {
            MADHaptics.tap()
            showSnapTray = true
        } label: {
            Group {
                if let thumb = lastSnapThumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.18))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                Text("\(midRunSnapCount)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.orange))
                    .offset(x: 5, y: -5)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showSnapTray) {
            SnapGalleryView(title: "Your snaps", onStashChanged: refreshSnapState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // Stop flow takes over the screen — the tray must not sit on top.
        .onChange(of: isStopping) { _, stopping in
            if stopping { showSnapTray = false }
        }
    }

    private func refreshSnapState() {
        midRunSnapCount = MidRunPhotoStash.count
        lastSnapThumb = MidRunPhotoStash.latestThumbnail()
    }

    /// Import a photo taken DURING this walk/run from the library. Camera-only
    /// authenticity is preserved by the time-window check in the picker — you
    /// can use a system-camera shot from this walk, but not an old photo.
    /// Shared look for the mid-run photo buttons so the camera and library
    /// controls are the exact same size and weight (they used to differ — 40 vs
    /// 44, icon 15 vs 17). Both read as one matched pair sitting in the top bar.
    private func midRunCircleIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
            )
    }

    private var midRunLibraryButton: some View {
        Button {
            MADHaptics.tap()
            showLibraryImport = true
        } label: {
            midRunCircleIcon("photo.badge.plus")
        }
        .buttonStyle(PlainButtonStyle())
        .fullScreenCover(isPresented: $showLibraryImport) {
            WorkoutPhotoImportPicker(
                window: importWindow,
                activityNoun: activityNoun
            ) { result in
                showLibraryImport = false
                handleImportResult(result)
            }
        }
        .onChange(of: isStopping) { _, stopping in
            if stopping { showLibraryImport = false }
        }
    }

    /// Accepted capture-time window: from just before the workout started
    /// (a photo snapped at the trailhead counts) through now, with a small
    /// forward buffer so a shot taken while browsing the picker still passes.
    private var importWindow: ClosedRange<Date> {
        let start = (workoutStartDate ?? Date()).addingTimeInterval(-5 * 60)
        let end = Date().addingTimeInterval(2 * 60)
        return start...max(start, end)
    }

    private func handleImportResult(_ result: WorkoutPhotoImportResult) {
        switch result {
        case .accepted(let image):
            Task.detached(priority: .utility) {
                guard let entry = MidRunPhotoStash.add(image) else { return }
                let count = MidRunPhotoStash.count
                let thumb = MidRunPhotoStash.latestThumbnail()
                await MainActor.run {
                    // Imported straight from the photo library — it already
                    // lives there, so mark it saved and never offer to re-save.
                    SavedPhotoLibraryLedger.shared.markSaved(entry.id)
                    midRunSnapCount = count
                    lastSnapThumb = thumb
                    showImportToast("Added to your \(activityNoun)", ok: true)
                }
            }
        case .failed:
            showImportToast("Couldn't load that photo", ok: false)
        case .cancelled:
            break
        }
    }

    /// "run"/"walk" for user-facing copy, matching the active workout type.
    private var activityNoun: String {
        selectedActivityType == .running ? "run" : "walk"
    }

    private func showImportToast(_ text: String, ok: Bool) {
        if ok { MADHaptics.success() }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            importToast = ImportToast(text: text, ok: ok)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeOut(duration: 0.25)) { importToast = nil }
        }
    }

    private var midRunCameraButton: some View {
        Button {
            MADHaptics.tap()
            showMidRunCamera = true
        } label: {
            midRunCircleIcon("camera.fill")
        }
        .buttonStyle(PlainButtonStyle())
        .fullScreenCover(isPresented: $showMidRunCamera) {
            // Camera-roll save is handled below, keyed to the stash id, so the
            // review gallery can show "Saved" and never duplicate the shot.
            MADCameraView(image: $midRunImage, autoSaveToPhotos: false)
        }
        .onChange(of: midRunImage) { _, newImage in
            guard let image = newImage else { return }
            midRunImage = nil
            // Downscale + JPEG-encode off the main thread — doing it inline
            // stutters the camera dismissal animation on big sensor images.
            Task.detached(priority: .utility) {
                let entry = MidRunPhotoStash.add(image)
                let count = MidRunPhotoStash.count
                let thumb = MidRunPhotoStash.latestThumbnail()
                await MainActor.run {
                    // Keep the user's own full-res copy in the camera roll no
                    // matter what (the camera no longer auto-saves this path).
                    // When it made it into the stash, key the save to that snap
                    // so the gallery shows "Saved" instead of a duplicate.
                    if let entry {
                        PhotoRollSaver.save(image, ledgerKey: entry.id)
                    } else {
                        PhotoRollSaver.save(image)
                    }
                    guard entry != nil else { return }
                    midRunSnapCount = count
                    lastSnapThumb = thumb
                    MADHaptics.success()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showSnapSavedToast = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation(.easeOut(duration: 0.25)) { showSnapSavedToast = false }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var snapSavedToast: some View {
        if showSnapSavedToast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.green)
                Text(midRunSnapCount >= MidRunPhotoStash.maxPhotos
                     ? "Saved — that's the max, oldest gets replaced"
                     : "Saved for your post")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.75))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            )
            .padding(.top, 72)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var importToastView: some View {
        if let toast = importToast {
            HStack(spacing: 8) {
                Image(systemName: toast.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(toast.ok ? .green : .orange)
                Text(toast.text)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.78))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            )
            .padding(.top, 72)
            .padding(.horizontal, MADTheme.Spacing.lg)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    /// Shown when the workout couldn't be written to Apple Health for a reason
    /// OTHER than denied access — the mile still counts via sync, so this is a
    /// calm reassurance rather than a blocking error.
    @ViewBuilder
    private var saveFallbackToast: some View {
        if showSaveFallbackToast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.green)
                Text("Your mile still counts — it'll sync on your next update.")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.78))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            )
            .padding(.top, 72)
            .padding(.horizontal, MADTheme.Spacing.lg)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    /// Deep-link to this app's Settings page, where the user can reach the
    /// Health access toggles for Mile A Day.
    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Vertical spacing between the metric blocks, tightened on shorter screens.
    private func metricSpacing(for screenHeight: CGFloat) -> CGFloat {
        guard screenHeight > 0 else { return 40 }
        return screenHeight < 700 ? 24 : 40
    }

    /// Progress-ring diameter, scaled to the screen so it shrinks on small devices
    /// (down to 150pt) and caps at the original 200pt on larger ones.
    private func ringDiameter(for screenHeight: CGFloat) -> CGFloat {
        guard screenHeight > 0 else { return 200 }
        return min(200, max(150, screenHeight * 0.26))
    }

    // MARK: - Tracking Sub-Views

    private var distanceDisplay: some View {
        VStack(spacing: 12) {
            Text("DISTANCE")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.7))
                .tracking(1.5)

            Text(String(format: "%.2f", currentDistance))
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText())

            Text("miles")
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))

            if startingDistance > 0 {
                VStack(spacing: 4) {
                    Text("Daily Total: \(String(format: "%.2f", totalDailyDistance)) mi")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.top, 4)
            }
        }
    }

    private func progressRing(diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 12)
                .frame(width: diameter, height: diameter)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: progress >= 1.0 ? [.green, .green] : [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: progress)

            VStack(spacing: 4) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("of goal")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    /// The reason GPS tracking is NOT working right now, when there is one.
    /// Nil = healthy (or indoor mode, where the pedometer needs none of it).
    /// Re-evaluated every second by the elapsed-time tick. The worst feeling
    /// in this app is finishing a mile and discovering nothing was tracked —
    /// each of these states used to be completely silent.
    private var trackingIssue: (icon: String, title: String, detail: String, showsSettings: Bool)? {
        guard isTracking, !locationManager.isUsingPedometer else { return nil }
        let auth = locationManager.authorizationStatus
        if auth == .denied || auth == .restricted {
            return (
                icon: "location.slash.fill",
                title: "Location access is off",
                detail: "Distance can't track without it. Tap to open Settings.",
                showsSettings: true
            )
        }
        // Approximate location (~5 km fixes) fails the accuracy gate on every
        // fix — the workout would sit at 0.00 forever while looking alive.
        if auth != .notDetermined, locationManager.accuracyAuthorization == .reducedAccuracy {
            return (
                icon: "location.circle",
                title: "Precise Location is off",
                detail: "Approximate location can't measure distance. Tap to open Settings.",
                showsSettings: true
            )
        }
        // Fixes stopped arriving (or never arrived): garage, tunnel, deep
        // indoors. Give GPS 30s to lock at start before declaring silence.
        let sinceStart = workoutStartDate.map { Date().timeIntervalSince($0) } ?? 0
        if let lastFix = locationManager.lastFixAt {
            if Date().timeIntervalSince(lastFix) > 60 {
                return (
                    icon: "antenna.radiowaves.left.and.right.slash",
                    title: "No GPS signal",
                    detail: "Nothing is being received right now — head for open sky.",
                    showsSettings: false
                )
            }
        } else if sinceStart > 30 {
            return (
                icon: "antenna.radiowaves.left.and.right.slash",
                title: "Waiting for GPS",
                detail: "No signal yet — distance starts counting once GPS locks.",
                showsSettings: false
            )
        }
        return nil
    }

    @ViewBuilder
    private var trackingHealthBanner: some View {
        if let issue = trackingIssue {
            Button {
                guard issue.showsSettings,
                      let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: issue.icon)
                        .font(.system(size: 18, weight: .bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                        Text(issue.detail)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .opacity(0.85)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    if issue.showsSettings {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .opacity(0.7)
                    }
                }
                .foregroundColor(.white)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.6), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var timeDisplay: some View {
        VStack(spacing: 8) {
            Text("TIME")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.7))
                .tracking(1.5)

            Text(formattedTime)
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()

            // The movement gate freezing distance is CORRECT behavior — this
            // chip is what keeps it from reading as "tracking broke" while
            // the user stands at a light or sits down mid-walk.
            if locationManager.isAutoPaused {
                HStack(spacing: 5) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("AUTO-PAUSED")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
                .transition(.opacity.combined(with: .scale))
            }

            if raceGhost != nil, let delta = raceDeltaSeconds {
                raceDeltaChip(delta: delta, frozen: raceFinalDelta != nil)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.spring(response: 0.3), value: locationManager.isAutoPaused)
        .animation(.spring(response: 0.3), value: raceFinalDelta != nil)
    }

    /// Ghost race readout: live ahead/behind while the mile is in progress,
    /// frozen verdict once it completes. Moving-time based, so auto-pauses
    /// can't cheat it.
    private func raceDeltaChip(delta: TimeInterval, frozen: Bool) -> some View {
        let ahead = delta >= 0
        let magnitude = Int(abs(delta).rounded())
        // Names the ghost the user actually chose. Hardcoding "your best" here
        // was a lie the moment a PR or a custom time could be raced.
        let name = raceGhostName
        let text: String
        if frozen {
            text = ahead ? "Beat \(name) by \(magnitude)s" : "\(magnitude)s off \(name)"
        } else if magnitude < 2 {
            text = "Even with \(name)"
        } else {
            text = ahead ? "\(magnitude)s ahead of \(name)" : "\(magnitude)s behind \(name)"
        }
        return HStack(spacing: 5) {
            // The ghost itself while the race is live — it glances back when
            // you're gaining on it, which is the whole feeling of the feature
            // in one glyph. The verdict swaps to a trophy/flag, because by
            // then the ghost is beside the point.
            if frozen {
                Image(systemName: ahead ? "trophy.fill" : "flag.checkered")
                    .font(.system(size: 9, weight: .bold))
            } else {
                GhostSprite(
                    size: 11,
                    color: ahead ? .green : .orange,
                    floats: false,
                    glancesBack: ahead
                )
            }
            Text(text)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.4)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundColor(ahead ? .green : .orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill((ahead ? Color.green : Color.orange).opacity(0.15)))
    }

    // MARK: - Live presence UI

    /// Subtle pulse when at least one friend is also out right now. Appears
    /// organically, disappears quietly; tap for the list + a Hype button per
    /// friend. Real-time presence is the feature — keep it calm, not loud.
    @ViewBuilder
    private var friendsOutPulseRow: some View {
        if !livePresence.friendsOut.isEmpty {
            Button {
                MADHaptics.action()
                showFriendsOutSheet = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.35))
                            .frame(width: 10, height: 10)
                            .scaleEffect(1.9)
                            .opacity(0.55)
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                    }
                    .pulseGlow(color: .green, maxScale: 1.6)

                    HStack(spacing: -8) {
                        ForEach(livePresence.friendsOut.prefix(3)) { friend in
                            AvatarView(
                                name: friend.displayName,
                                imageURL: friend.profile_image_url,
                                size: 28
                            )
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
                        }
                    }

                    Text(friendsOutLabel)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .overlay(Capsule().strokeBorder(Color.green.opacity(0.35), lineWidth: 1))
                )
                .padding(.horizontal, 32)
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .scale))
        }
    }

    private var friendsOutLabel: String {
        let friends = livePresence.friendsOut
        guard let first = friends.first else { return "" }
        if friends.count == 1 {
            return "\(first.firstNameOrUsername) is out right now"
        }
        return "\(first.firstNameOrUsername) + \(friends.count - 1) more are out"
    }

    private var stopButton: some View {
        Button(action: { showStopConfirmation = true }) {
            HStack(spacing: 12) {
                if isStopping {
                    ProgressView()
                        .tint(.white)
                    Text("Ending...")
                        .font(.title3)
                        .fontWeight(.semibold)
                } else {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                    Text("Stop Workout")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.red.opacity(isStopping ? 0.15 : 0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.red.opacity(isStopping ? 0.5 : 1.0), lineWidth: 2)
                    )
            )
        }
        .disabled(isStopping)
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private var previousProgressOverlay: some View {
        if showPreviousProgress {
            VStack(spacing: 20) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .scaleEffect(showPreviousProgress ? 1.0 : 0.5)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showPreviousProgress)

                Text("Back to where you were!")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("\(String(format: "%.2f", startingDistance)) miles reached")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
            }
            .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var goalCompletionOverlay: some View {
        if showCompletion {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 100))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(showCompletion ? 1.0 : 0.5)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showCompletion)

                Text("Goal Complete!")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("You did it! Keep going or finish your workout.")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Reusable Option Button

    /// Icon for the Indoor (treadmill) option. Prefers the treadmill glyph
    /// (`figure.run.treadmill` / `figure.walk.treadmill`, SF Symbols 6 / iOS 18+)
    /// so the option reads clearly as "treadmill," and falls back to a plain
    /// run/walk figure on iOS 17 — where that symbol doesn't exist and would
    /// otherwise render as a blank box. `UIImage(systemName:)` returns nil for a
    /// name the running OS doesn't ship, so this checks availability at runtime
    /// rather than guessing the version. Matches the chosen activity.
    private var indoorLocationIcon: String {
        let isWalk = selectedActivityType == .walking
        let treadmill = isWalk ? "figure.walk.treadmill" : "figure.run.treadmill"
        if UIImage(systemName: treadmill) != nil { return treadmill }
        return isWalk ? "figure.walk" : "figure.run"
    }

    private func workoutOptionButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        workoutOptionButton(
            leading: { optionGlyph(icon) },
            title: title, subtitle: subtitle,
            accessory: { optionChevron }, action: action)
    }

    private func optionGlyph(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 32))
            .frame(width: 50)
    }

    /// The wizard's option card.
    ///
    /// `featured` brightens the surface so one option can read as the special
    /// one, `badge` is the small pill beside the title (the ghost race's NEW
    /// flag), `leading` is the glyph slot (a drawn ghost, not just a symbol),
    /// and `accessory` replaces the trailing chevron with a readout. The plain
    /// overload above renders exactly what the Run/Walk and Indoor/Outdoor
    /// steps have always shown.
    ///
    /// Featuring is deliberately a BRIGHTNESS shift, not a hue one: this whole
    /// screen sits on the red gradient, and `MADTheme.workoutColor("running")`
    /// is that gradient's own top stop — a red-tinted border and glyph would
    /// go muddy on exactly the workout type most people pick.
    private func workoutOptionButton<Leading: View, Accessory: View>(
        @ViewBuilder leading: () -> Leading,
        title: String,
        subtitle: String,
        featured: Bool = false,
        badge: String? = nil,
        @ViewBuilder accessory: () -> Accessory,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                leading()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .tracking(0.8)
                                .foregroundColor(.black.opacity(0.8))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.yellow))
                        }
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .opacity(0.9)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                accessory()
            }
            .foregroundColor(.white)
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(featured ? 0.24 : 0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(featured ? 0.6 : 0.3), lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var optionChevron: some View {
        Image(systemName: "chevron.right")
            .font(.title2)
            .fontWeight(.semibold)
    }

    var body: some View {
        ZStack {
            // Red gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.25, blue: 0.35),
                    Color(red: 0.7, green: 0.2, blue: 0.3),
                    Color(red: 0.5, green: 0.15, blue: 0.2),
                    Color(red: 0.3, green: 0.1, blue: 0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if showActivitySelection {
                activitySelectionContent
                    .transition(wizardTransition)
            } else if showLocationTypeSelection {
                locationTypeSelectionContent
                    .transition(wizardTransition)
            } else if showRaceModeSelection {
                raceModeSelectionContent
                    .transition(wizardTransition)
            } else if showGhostOptions {
                ghostOptionsContent
                    .transition(wizardTransition)
            } else if showPresenceConsent {
                presenceConsentContent
            } else if showCountdown {
                countdownContent
            } else if showRecap {
                WorkoutRecapView(
                    distance: recapDistance,
                    duration: recapDuration,
                    activityName: selectedActivityType == .running ? "Run" : "Walk",
                    activityIcon: selectedActivityType == .running ? "figure.run" : "figure.walk",
                    startingDistance: recapStartingDistance,
                    goalDistance: recapGoalDistance,
                    streak: userManager.currentUser.streak,
                    onDismiss: { dismiss() }
                )
            } else {
                activeTrackingContent
            }
        }
        .onChange(of: currentDistance) { oldValue, newValue in
            // Check if we've reached the previous progress point
            if !hasReachedPreviousProgress && startingDistance > 0 && newValue >= startingDistance {
                hasReachedPreviousProgress = true

                // Show notification that they've reached where they were
                withAnimation {
                    showPreviousProgress = true
                }

                // Haptic feedback
                MADHaptics.success()

                // Hide notification after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showPreviousProgress = false
                    }
                }
            }

            // Check if we've reached the goal (using total daily distance).
            // `currentDistance` is monotonic and IS the saved number, so a
            // celebration fired here can never be taken back by the finish.
            // Only show completion if:
            // 1. We haven't shown it yet
            // 2. The goal wasn't already completed when we started (startingDistance < goalDistance)
            // 3. We've now reached the goal with total daily distance
            if !hasShownCompletion && startingDistance < goalDistance && totalDailyDistance >= goalDistance {
                hasShownCompletion = true // Mark as shown so it doesn't loop

                // Show completion celebration
                withAnimation {
                    showCompletion = true
                }

                // Haptic feedback
                MADHaptics.success()

                // Hide completion after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showCompletion = false
                    }
                }
            }
        }
        .onDisappear {
            // When the view disappears (e.g., user dismisses to dashboard),
            // do a final Live Activity update and state save so the Dynamic Island
            // shows current data while the view is gone.
            if isTracking && !isStopping {
                updateLiveActivity()
            }

            // Stop the timer to save battery. The workout state remains persisted
            // so we can restore it when the user comes back.
            timer?.invalidate()
            timer = nil
        }
        .alert("End Workout?", isPresented: $showStopConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End Workout", role: .destructive) {
                stopWorkout()
            }
        } message: {
            Text("Are you sure you want to end this workout? Your progress will be saved to HealthKit.")
        }
        .alert("Couldn't Start Workout", isPresented: $showEndWorkoutError) {
            Button("OK") {
                // Dismiss back to dashboard since the workout state is already cleared
                dismiss()
            }
        } message: {
            Text(endWorkoutErrorMessage)
        }
        .alert("Save Workouts to Apple Health?", isPresented: $showHealthAccessAlert) {
            Button("Open Settings") {
                openAppSettings()
                dismiss()
            }
            Button("Not Now", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Your mile still counts toward your streak. To also save your workouts to Apple Health, turn on Workouts access for Mile A Day in Settings.")
        }
        .onAppear {
            // Workout recovery: if there's a persisted in-progress workout, restore it.
            // Guard: skip if we're currently ending a workout or already tracking.
            guard !isStopping, !isTracking else { return }

            // Buddy Walk hand-off. The lobby already ran the server-synced
            // countdown, so there is nothing left to pick and nothing left to
            // count down — start moving immediately.
            //
            // Deliberately checked BEFORE the recovery branch's early return but
            // AFTER its guards: a recoverable workout on disk always wins, since
            // that's a workout already in progress and starting a second one
            // would fail the lock anyway.
            if buddySessionId != nil, !hasAutoStartedBuddyWorkout,
               InProgressWorkoutStore.load()?.isActive != true {
                hasAutoStartedBuddyWorkout = true
                selectedActivityType =
                    (buddyService.session?.isRunning ?? false) ? .running : .walking
                selectedLocationType = .outdoor
                clearPreStartSteps()
                // Ghost race, armed from the lobby. This branch skips the whole
                // pre-start wizard, which is the only place the solo race steps
                // live — so without this a buddy walk could never race, even
                // though it already feeds BestEffortStore on finish.
                // Everything downstream (resolvedGhost, the delta chip, the
                // 1-mile freeze, the celebration) only ever needed raceArmed.
                raceArmed = buddyGhostArmed
                isTracking = true
                startWorkout()
                return
            }

            guard let saved = InProgressWorkoutStore.load(), saved.isActive else { return }

            // Restore core state
            workoutStartDate = saved.startTime
            elapsedTime = max(0, Date().timeIntervalSince(saved.startTime))

            // Restore activity + location type
            if saved.activityType == "Running" {
                selectedActivityType = .running
            } else if saved.activityType == "Walking" {
                selectedActivityType = .walking
            }
            if let locationType = HKWorkoutSessionLocationType(rawValue: saved.locationTypeRawValue) {
                selectedLocationType = locationType
            }

            // Jump directly into the tracking UI
            clearPreStartSteps()
            isTracking = true

            // Restore the snap chip (count + thumbnail) — mid-run photos
            // survive an app relaunch alongside the workout itself.
            refreshSnapState()

            // Resume tracking with the saved distance as the starting point.
            // For pedometer: new pedometer readings will ADD to saved.currentDistance.
            // For GPS: new GPS deltas will add to saved.currentDistance.
            locationManager.startTracking(locationType: selectedLocationType, initialDistance: saved.currentDistance)

            // Restart HKWorkoutBuilder (non-blocking, best-effort)
            healthManager.requestAuthorization { authorized in
                guard authorized else { return }

                let configuration = HKWorkoutConfiguration()
                configuration.activityType = self.selectedActivityType ?? .walking
                configuration.locationType = self.selectedLocationType

                let healthStore = HKHealthStore()
                let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
                self.workoutBuilder = builder

                builder.beginCollection(withStart: saved.startTime) { _, _ in }
            }

            // Restart timer and Live Activity
            startWorkoutTimer()
            startLiveActivity()
        }
    }

    // MARK: - Pre-start navigation

    /// Every pre-start step off at once. Used by anything that jumps straight
    /// to tracking (the buddy hand-off, workout recovery) — a single call so a
    /// new step can never be forgotten in one of them.
    private func clearPreStartSteps() {
        showActivitySelection = false
        showLocationTypeSelection = false
        showRaceModeSelection = false
        showGhostOptions = false
        showPresenceConsent = false
        showCountdown = false
    }

    /// Forward one step: haptic, slide direction, animate.
    private func advance(_ change: @escaping () -> Void) {
        MADHaptics.action()
        wizardGoingBack = false
        withAnimation(.easeInOut(duration: 0.28)) { change() }
    }

    /// Back one step. `from` turns the current step off, `to` turns the
    /// previous one on — kept as two closures so call sites read in the
    /// direction the user is travelling.
    private func goBack(to: @escaping () -> Void, from: @escaping () -> Void) {
        MADHaptics.tap()
        wizardGoingBack = true
        withAnimation(.easeInOut(duration: 0.28)) {
            from()
            to()
        }
    }

    private func selectActivity(_ activityType: HKWorkoutActivityType) {
        selectedActivityType = activityType
        advance {
            showActivitySelection = false
            showLocationTypeSelection = true
        }
    }

    private func selectLocationType(_ locationType: HKWorkoutSessionLocationType) {
        selectedLocationType = locationType
        advance {
            showLocationTypeSelection = false
            showRaceModeSelection = true
        }
    }

    /// Step 3's answer. Choosing the race opens its options rather than arming
    /// anything — nothing is armed until a target is actually picked. Also the
    /// "Skip the race" exit from step 4, hence both flags being cleared.
    private func chooseRaceMode(ghost: Bool) {
        guard ghost else {
            raceArmed = false
            advance {
                showRaceModeSelection = false
                showGhostOptions = false
                proceedPastRaceChoice()
            }
            return
        }
        advance {
            showRaceModeSelection = false
            showGhostOptions = true
        }
    }

    /// Step 4's answer: arm this target and start.
    private func armGhost(_ target: BestEffortStore.GhostTarget) {
        storeRaceTarget(target)
        raceArmed = true
        hasArmedGhostRaceOnce = true
        advance {
            showGhostOptions = false
            proceedPastRaceChoice()
        }
    }

    /// The single door out of the race choice, so the once-ever presence
    /// question can't be skipped by whichever step happens to come last.
    /// Called from INSIDE an `advance` block — it flips flags, it doesn't
    /// animate.
    private func proceedPastRaceChoice() {
        // First tracked workout on this build: one explicit presence choice
        // before the countdown. Asked exactly once, ever — after that the
        // toggle lives in notification settings.
        guard hasAnsweredLivePresenceConsent else {
            showPresenceConsent = true
            return
        }
        showCountdown = true
        countdownNumber = 3 // Reset countdown
    }

    private func resolvePresenceConsent(share: Bool) {
        hasAnsweredLivePresenceConsent = true
        LivePresenceService.setSharePresence(share)
        MADHaptics.action()
        withAnimation {
            showPresenceConsent = false
            showCountdown = true
            countdownNumber = 3
        }
    }

    /// One-time interstitial between picking a location and the countdown:
    /// an explicit yes/no on live presence (5.1.1-friendly — no location is
    /// ever shared, and either answer proceeds straight into the workout).
    private var presenceConsentContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 96, height: 96)
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }

                Text("Share that you're out?")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("While you track a walk or run, friends who are also out see \u{201C}you're out right now\u{201D} — and their hypes land on your Live Activity mid-walk. Never your location, only that you're moving. You'll see them too either way.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 14) {
                Button {
                    resolvePresenceConsent(share: true)
                } label: {
                    Text("Share when I'm out")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.5, green: 0.15, blue: 0.2))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                }
                .buttonStyle(.plain)

                Button {
                    resolvePresenceConsent(share: false)
                } label: {
                    Text("Not now")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Text("Change any time in notification settings.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    private func startCountdown() {
        // Haptic feedback for countdown
        let impact = UIImpactFeedbackGenerator(style: .heavy)

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdownNumber > 1 {
                countdownNumber -= 1
                impact.impactOccurred()
            } else {
                timer.invalidate()
                // Start workout
                withAnimation {
                    showCountdown = false
                    isTracking = true
                }
                startWorkout()
            }
        }
    }

    private func startWorkout() {
        // Acquire workout lock to enforce single workout at a time
        guard InProgressWorkoutStore.acquireLock() else {
            endWorkoutErrorMessage = "Another Mile A Day workout is already active. Please finish or cancel that workout first."
            showEndWorkoutError = true
            return
        }

        workoutStartDate = Date()

        // Resolve the ghost the user armed on the location step (resolved
        // once, so a best set MID-session doesn't morph the target).
        raceFinalDelta = nil
        if raceArmed, let ghost = resolvedGhost {
            raceGhost = ghost.effort
            raceGhostName = ghost.shortName
        } else {
            raceGhost = nil
            raceGhostName = "your best mile"
        }

        // Live presence session (fire-and-forget; the share pref only gates
        // being SEEN — server-side — so this always starts).
        livePresence.startSession(
            workoutType: selectedActivityType == .running ? "running" : "walking"
        )

        // Fresh session: drop mid-run snaps left over from a previous workout
        // ONLY when today's goal was already met before this one. A workout on
        // an already-completed day is "extra", so a stale snap shouldn't hijack
        // its prompt. But when the goal ISN'T met yet, keep leftover snaps so a
        // photo taken on an earlier sub-goal effort survives into the workout
        // that finally finishes the mile (24h prune still bounds staleness).
        if startingDistance >= goalDistance {
            MidRunPhotoStash.clear()
            midRunSnapCount = 0
        } else {
            // Keep SAME-DAY leftover snaps (a photo from an earlier sub-goal
            // effort should survive into the workout that finishes the mile),
            // but drop any from a previous day so a fresh day's mile never
            // inherits — or re-shares — yesterday's snaps.
            MidRunPhotoStash.dropBeforeToday()
            midRunSnapCount = MidRunPhotoStash.count
        }

        // Immediately persist initial workout state
        let initialState = InProgressWorkoutState(
            isActive: true,
            isPaused: false,
            startTime: workoutStartDate!,
            elapsedTime: 0,
            pausedTime: 0,
            currentDistance: 0,
            startingDistance: startingDistance,
            totalDailyDistance: totalDailyDistance,
            goalDistance: goalDistance,
            activityType: selectedActivityType == .running ? "Running" : "Walking",
            locationTypeRawValue: selectedLocationType.rawValue,
            workoutUUID: UUID().uuidString,
            lastSaveTime: Date(),
            routePoints: [],
            isUsingPedometer: selectedLocationType == .indoor,
            liveActivityID: nil
        )
        InProgressWorkoutStore.save(initialState)

        // Start location/pedometer tracking (fresh workout, initialDistance = 0)
        locationManager.startTracking(locationType: selectedLocationType, initialDistance: 0)

        // Start Live Activity
        startLiveActivity()

        // Start the timer IMMEDIATELY — don't wait for HealthKit authorization.
        // The timer drives both the UI clock and periodic state persistence.
        startWorkoutTimer()

        // Set up HKWorkoutBuilder in the background (non-blocking).
        // If this fails, the workout still tracks distance; it just won't save to HealthKit.
        healthManager.requestAuthorization { authorized in
            guard authorized else { return }

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = self.selectedActivityType ?? .walking
            configuration.locationType = self.selectedLocationType

            let healthStore = HKHealthStore()
            let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
            self.workoutBuilder = builder

            builder.beginCollection(withStart: self.workoutStartDate ?? Date()) { _, _ in }
        }
    }

    /// Start (or restart) the workout timer that drives the UI clock and periodic state saves.
    private func startWorkoutTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            guard let startDate = workoutStartDate else { return }
            // Don't persist state while we're in the middle of stopping
            guard !isStopping else { return }
            elapsedTime = Date().timeIntervalSince(startDate)
            updateLiveActivity()
            // Foreground heartbeat driver (self-throttled to ~45s). The
            // background driver is the location/pedometer callback path.
            livePresence.tick()

            // Buddy Walk: piggyback on the tick that already exists rather than
            // adding a second timer. The service throttles this to one network
            // call every 5s, and that call's response carries the whole roster
            // back — so an actively-tracking client never polls separately.
            if buddySessionId != nil {
                let distance = currentDistance
                let elapsed = elapsedTime
                Task { @MainActor in
                    await BuddySessionService.shared.reportProgress(
                        distanceMiles: distance,
                        durationSeconds: elapsed
                    )
                }
            }
        }
    }

    private func stopWorkout() {
        guard !isStopping else { return }
        isStopping = true

        // Final distance IS the displayed distance — no finish-time
        // re-arbitration. `liveDistance` (ratcheted max of the jitter-gated
        // GPS span and the calibrated pedometer span; raw accrual indoors)
        // is the number the user watched, so it saves verbatim.
        let finalDistance = locationManager.liveDistance

        // Ghost race bookkeeping — runs for EVERY session (an unraced mile
        // still quietly becomes the baseline/best, keeping future ghosts
        // honest); racing only changes what gets celebrated. The curve already
        // samples `liveDistance`, so the scale is 1.0 in practice — it stays
        // as the guard for the last sample landing a hair short of the saved
        // number (the sampler throttles at 0.02 mi).
        let curveDistance = locationManager.effortCurve.last?.d ?? 0
        let raceOutcome = BestEffortStore.recordFinish(
            activityKey: raceActivityKey,
            rawCurve: locationManager.effortCurve,
            distanceScale: curveDistance > 0 ? finalDistance / curveDistance : 1.0,
            workoutId: nil
        )
        celebrateRaceOutcome(raceOutcome)

        // Freeze the recap stats now, before anything refreshes underneath us
        recapDistance = finalDistance
        recapDuration = workoutStartDate.map { Date().timeIntervalSince($0) } ?? elapsedTime
        recapStartingDistance = startingDistance
        recapGoalDistance = goalDistance

        // Buddy Walk: report the RECONCILED final distance (not the raw live
        // sum) and mark this participant done, so the standings everyone sees
        // match the number this phone is about to save to HealthKit. The
        // server later replaces even this with the synced HKWorkout.
        if buddySessionId != nil {
            let reportedDistance = finalDistance
            let reportedDuration = recapDuration
            Task { @MainActor in
                await BuddySessionService.shared.finish(
                    finalDistanceMiles: reportedDistance,
                    durationSeconds: reportedDuration
                )
            }
        }

        // Flush any buffered route points
        InProgressWorkoutStore.flushRoutePoints()

        // Capture the GPS trace NOW — finishCleanup() clears the store, and the
        // HealthKit route write below happens after that. Without this route,
        // in-app workouts never got an HKWorkoutRoute, so the sync (which reads
        // routes back from HealthKit) uploaded them route-less and the feed
        // could never draw their maps.
        // Cleaned once here — despiked, smoothed, simplified — because this
        // is the single point every route consumer flows through (HealthKit
        // route → backend sync → feed maps).
        let routeLocations = WorkoutRouteCleanup.cleaned(
            (InProgressWorkoutStore.load()?.routePoints ?? []).map { $0.toCLLocation() }
        )

        // Stop timer and location tracking
        timer?.invalidate()
        timer = nil
        locationManager.stopTracking()
        livePresence.endSession()

        // Safety timeout: if HealthKit callbacks never fire, force-cleanup after 10s
        let timeout = DispatchWorkItem { [self] in
            finishCleanup(workoutSaved: false)
        }
        endWorkoutTimeoutTask = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)

        // If we have no builder (e.g. HK auth failed), skip straight to cleanup
        guard let builder = workoutBuilder, let startDate = workoutStartDate else {
            finishCleanup(workoutSaved: false)
            return
        }

        // Clear references now (the local `builder` variable keeps the object alive for callbacks)
        workoutSession = nil
        workoutBuilder = nil

        let endDate = Date()

        // Async chain: add distance sample → end collection → finish workout →
        // attach GPS route → cleanup. Every step proceeds regardless of whether
        // the previous step failed.
        let addCompletion: (Bool, Error?) -> Void = { _, _ in
            builder.endCollection(withEnd: endDate) { _, _ in
                builder.finishWorkout { workout, error in
                    let saved = (workout != nil && error == nil)
                    let finalize = {
                        DispatchQueue.main.async {
                            self.finishCleanup(workoutSaved: saved)
                            if saved {
                                self.healthManager.fetchAllWorkoutData()
                            }
                        }
                    }
                    // Write the tracked GPS trace as the workout's
                    // HKWorkoutRoute, then re-upload THIS workout with the
                    // route attached. The HealthKit observer fires the moment
                    // finishWorkout writes the workout — usually BEFORE the
                    // route exists — so the observer-raced sync uploads it
                    // route-less and marks it synced, and the feed map never
                    // appears (while Apple Fitness, reading HealthKit
                    // directly, shows the route fine). The targeted re-push
                    // after finishRoute is what actually lands the map;
                    // best-effort: a failed route write still finalizes the
                    // workout itself.
                    guard let workout, saved, routeLocations.count >= 2 else {
                        finalize()
                        return
                    }
                    let routeBuilder = HKWorkoutRouteBuilder(
                        healthStore: HKHealthStore(), device: .local()
                    )
                    routeBuilder.insertRouteData(routeLocations) { inserted, insertError in
                        guard inserted else {
                            print("[WorkoutTracking] ⚠️ Route insert failed: \(String(describing: insertError))")
                            finalize()
                            return
                        }
                        routeBuilder.finishRoute(with: workout, metadata: nil) { route, finishError in
                            if route == nil {
                                print("[WorkoutTracking] ⚠️ Route finish failed: \(String(describing: finishError))")
                            } else {
                                let workoutId = workout.uuid
                                Task { await WorkoutSyncService.shared.uploadWorkout(withId: workoutId) }
                            }
                            finalize()
                        }
                    }
                }
            }
        }

        let beginSave = {
            if finalDistance > 0 {
                let distanceMeters = finalDistance / 0.000621371
                let distanceQuantity = HKQuantity(unit: HKUnit.meter(), doubleValue: distanceMeters)
                let sample = HKQuantitySample(
                    type: HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
                    quantity: distanceQuantity,
                    start: startDate,
                    end: endDate
                )
                builder.add([sample], completion: addCompletion)
            } else {
                addCompletion(true, nil)
            }
        }

        // Stamp the tracker's moving time (and a ghost win) on the workout
        // itself — the sync reads HKWorkouts back, so this is how the display
        // pace divisor and the race result travel. Best-effort: a metadata
        // failure still saves the workout.
        var metadata: [String: Any] = [:]
        let movingSeconds = locationManager.movingSeconds
        if movingSeconds > 0 {
            metadata[WorkoutLocationManager.movingSecondsMetadataKey] = movingSeconds
        }
        if let win = pendingGhostWin {
            metadata[WorkoutLocationManager.ghostMarginMetadataKey] = win.marginSeconds
            metadata[WorkoutLocationManager.ghostTargetMetadataKey] = win.ghostSeconds
            // Only present when the ghost was a friend's — that's what lets
            // the server tell them they were caught.
            if let friendId = win.friendUserId {
                metadata[WorkoutLocationManager.ghostFriendMetadataKey] = friendId
            }
        }
        if metadata.isEmpty {
            beginSave()
        } else {
            builder.addMetadata(metadata) { _, _ in
                beginSave()
            }
        }
    }

    /// Force-end a stuck workout without saving to HealthKit.
    private func forceEndWorkout() {
        endWorkoutTimeoutTask?.cancel()
        endWorkoutTimeoutTask = nil
        timer?.invalidate()
        timer = nil
        locationManager.stopTracking()
        endLiveActivity()
        InProgressWorkoutStore.clear()
        workoutSession = nil
        workoutBuilder = nil
        isStopping = false
        isTracking = false
        dismiss()
    }

    // MARK: - Workout Cleanup

    /// Final cleanup after a workout ends. Always clears persisted state to prevent zombie sessions.
    private func finishCleanup(workoutSaved: Bool) {
        // Guard against double-execution (timeout + normal callback both fire)
        guard isStopping else { return }

        // Cancel timeout (we got here normally)
        endWorkoutTimeoutTask?.cancel()
        endWorkoutTimeoutTask = nil

        // End Live Activity
        endLiveActivity()

        // ALWAYS clear persisted state. Leaving it active on failure was causing
        // permanent corruption that required reinstalling the app.
        InProgressWorkoutStore.clear()

        // Mark stopping as done BEFORE showing UI, so no timer/update callbacks can re-save state
        isStopping = false
        isTracking = false

        // Ghost race is opt-in PER SESSION: disarm so the next workout starts
        // clean (this view instance survives across sessions). The CHOSEN
        // target survives in @AppStorage — re-arming is one tap, and the
        // picker opens on what they raced last time.
        raceArmed = false
        raceGhost = nil
        raceGhostName = "your best mile"
        raceFinalDelta = nil
        pendingGhostWin = nil

        // Show result to user. The mile counts via GPS/pedometer sync whether
        // or not the HealthKit write succeeded, so a failed save is never a lost
        // workout — tailor the messaging to the cause instead of alarming.
        if workoutSaved {
            withAnimation { showRecap = true }
        } else if healthManager.isWorkoutSharingDenied() {
            // Health write access is turned off — this fails on EVERY workout
            // until the user re-enables it, so give them a way to fix it.
            showHealthAccessAlert = true
        } else {
            // Transient save failure with Health access intact. Don't block —
            // show a quiet toast and slip back to the dashboard.
            withAnimation { showSaveFallbackToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                dismiss()
            }
        }
    }

    // MARK: - Live Activity Management

    private func startLiveActivity() {
        // CRITICAL FIX: Check for existing Live Activities before creating a new one
        // This prevents creating multiple activities when app restarts

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities are not enabled")
            return
        }

        // First, check if we already have a reference to an active Live Activity
        if let existingActivity = workoutActivity {
            print("✅ Live Activity already exists in memory: \(existingActivity.id)")
            return
        }

        // Second, check for any running Live Activities (in case app was killed and restarted)
        let existingActivities = Activity<WorkoutActivityAttributes>.activities
        print("🔍 Found \(existingActivities.count) existing Live Activities")

        // Try to find an active Live Activity that matches our current workout
        if let matchingActivity = existingActivities.first(where: { activity in
            let timeDiff = abs(activity.attributes.startTime.timeIntervalSince(workoutStartDate ?? Date()))
            return timeDiff < 5.0 // Within 5 seconds of our workout start time
        }) {
            print("✅ Found matching Live Activity from previous session: \(matchingActivity.id)")
            workoutActivity = matchingActivity

            // Save the Live Activity ID to persistent storage
            if var state = InProgressWorkoutStore.load() {
                state.liveActivityID = matchingActivity.id
                InProgressWorkoutStore.save(state)
            }
            return
        }

        // Clean up any orphaned Live Activities that don't match our workout
        for orphanedActivity in existingActivities {
            let timeDiff = abs(orphanedActivity.attributes.startTime.timeIntervalSince(workoutStartDate ?? Date()))
            if timeDiff > 5.0 {
                print("🗑️ Ending orphaned Live Activity: \(orphanedActivity.id)")
                Task {
                    await orphanedActivity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }

        // No matching activity found, create a new one
        print("📱 Creating new Live Activity...")

        let attributes = WorkoutActivityAttributes(
            startTime: workoutStartDate ?? Date(),
            goalDistance: goalDistance
        )

        // Compute real-time elapsed time from start date
        let realTimeElapsed: TimeInterval
        if let startDate = workoutStartDate {
            realTimeElapsed = Date().timeIntervalSince(startDate)
        } else {
            realTimeElapsed = 0
        }

        let initialState = WorkoutActivityAttributes.ContentState(
            distance: currentDistance,
            totalDailyDistance: totalDailyDistance,
            elapsedTime: realTimeElapsed,
            goalDistance: goalDistance,
            activityType: selectedActivityType == .running ? "Running" : "Walking",
            timerStartDate: Date().addingTimeInterval(-realTimeElapsed),
            streak: userManager.currentUser.streak,
            movingSeconds: locationManager.movingSeconds,
            isAutoPaused: locationManager.isAutoPaused,
            ghostDeltaSeconds: raceDeltaSeconds,
            hypeCount: livePresence.sessionHypes.isEmpty ? nil : livePresence.sessionHypes.count,
            latestHypeName: livePresence.sessionHypes.last?.senderName
        )

        // If the goal was already met before this workout (post-goal extra
        // miles), don't fire the "mile complete" island alert mid-session.
        if goalDistance > 0 && totalDailyDistance >= goalDistance {
            hasSentGoalAlert = true
        }

        do {
            let activity = try Activity.request(
                attributes: attributes,
                // staleDate from the FIRST content: if iOS kills the app
                // before the first 30s update ever lands, the activity still
                // flips to its "tracking interrupted" rendering.
                content: .init(state: initialState, staleDate: Date().addingTimeInterval(180)),
                pushType: nil
            )
            workoutActivity = activity
            print("✅ Live Activity created: \(activity.id)")

            // CRITICAL: Save the Live Activity ID to persistent storage
            if var state = InProgressWorkoutStore.load() {
                state.liveActivityID = activity.id
                InProgressWorkoutStore.save(state)
                print("✅ Live Activity ID saved to persistent storage")
            }
        } catch {
            print("❌ Failed to start Live Activity: \(error)")
        }
    }

    /// Called once per second by the workout timer.
    /// Updates the Live Activity and persists current state for recovery.
    private func updateLiveActivity() {
        // CRITICAL: Never persist state while stopping — finishCleanup may have already cleared it.
        guard !isStopping else { return }

        // Ghost race: settle the verdict as soon as the mile completes, so
        // this update (and the on-screen chip) carry the frozen result.
        updateRaceFreezeIfNeeded()

        // The displayed figure — saved verbatim at Finish — so the lock
        // screen / Dynamic Island never outruns what will persist.
        let freshDistance = locationManager.liveDistance
        let freshTotalDaily = startingDistance + freshDistance
        let realTimeElapsed = workoutStartDate.map { Date().timeIntervalSince($0) } ?? elapsedTime

        // Update Live Activity (if we have one)
        if workoutActivity == nil {
            startLiveActivity()
        }
        if let activity = workoutActivity {
            // Goal crossed during THIS workout → one celebratory alert update
            // that briefly expands the Dynamic Island / lights up the watch.
            // freshTotalDaily rides the monotonic saved-verbatim estimator,
            // so this "streak safe" promise can never be walked back.
            let goalJustCompleted = goalDistance > 0
                && freshTotalDaily >= goalDistance
                && !hasSentGoalAlert

            // Throttle: push on goal-cross, when distance moved ≥ 0.01 mi, or
            // every 30s (keeps pace fresh and renews the staleDate). The
            // elapsed clock needs no pushes at all — it ticks natively.
            let shouldPush = goalJustCompleted
                || abs(freshDistance - lastPushedDistance) >= 0.01
                || Date().timeIntervalSince(lastActivityPushDate) >= 30

            if shouldPush {
                if goalJustCompleted {
                    hasSentGoalAlert = true
                }
                lastActivityPushDate = Date()
                lastPushedDistance = freshDistance

                let updatedState = WorkoutActivityAttributes.ContentState(
                    distance: freshDistance,
                    totalDailyDistance: freshTotalDaily,
                    elapsedTime: realTimeElapsed,
                    goalDistance: goalDistance,
                    activityType: selectedActivityType == .running ? "Running" : "Walking",
                    timerStartDate: Date().addingTimeInterval(-realTimeElapsed),
                    streak: userManager.currentUser.streak,
                    movingSeconds: locationManager.movingSeconds,
                    isAutoPaused: locationManager.isAutoPaused,
                    ghostDeltaSeconds: raceDeltaSeconds,
                    hypeCount: livePresence.sessionHypes.isEmpty ? nil : livePresence.sessionHypes.count,
                    latestHypeName: livePresence.sessionHypes.last?.senderName
                )
                // staleDate lets the system dim the activity if the app dies and
                // stops sending updates, instead of showing confident stale data.
                let content = ActivityContent(state: updatedState, staleDate: Date().addingTimeInterval(180))

                Task {
                    if goalJustCompleted {
                        await activity.update(
                            content,
                            alertConfiguration: AlertConfiguration(
                                title: "Mile complete! 🔥",
                                body: "Your streak is safe for today.",
                                sound: .default
                            )
                        )
                    } else {
                        await activity.update(content)
                    }
                }
            }
        }

        // Persist state for recovery (only update EXISTING state, never create new).
        InProgressWorkoutStore.flushRoutePoints()
        if var existingState = InProgressWorkoutStore.load() {
            existingState.elapsedTime = realTimeElapsed
            existingState.currentDistance = freshDistance
            existingState.totalDailyDistance = freshTotalDaily
            existingState.lastSaveTime = Date()
            existingState.liveActivityID = workoutActivity?.id
            InProgressWorkoutStore.save(existingState)
        }
    }

    private func endLiveActivity() {
        // End all Live Activities for this workout.
        // NOTE: This does NOT clear InProgressWorkoutStore — the caller is responsible
        // for clearing state after confirming HealthKit save status.
        print("🔚 Ending Live Activity...")

        // Use FRESH data for the final state (identical to what Finish saves)
        let freshDistance = locationManager.liveDistance
        let freshTotalDaily = startingDistance + freshDistance
        let realTimeElapsed = workoutStartDate.map { Date().timeIntervalSince($0) } ?? elapsedTime

        // Final state: no timerStartDate, so the ended activity shows the
        // frozen final time instead of a clock that keeps ticking.
        let finalState = WorkoutActivityAttributes.ContentState(
            distance: freshDistance,
            totalDailyDistance: freshTotalDaily,
            elapsedTime: realTimeElapsed,
            goalDistance: goalDistance,
            activityType: selectedActivityType == .running ? "Running" : "Walking",
            timerStartDate: nil,
            streak: userManager.currentUser.streak,
            movingSeconds: locationManager.movingSeconds,
            isAutoPaused: false
        )

        // Capture the ID before clearing the reference so the orphan cleanup can exclude it
        let endedActivityID = workoutActivity?.id

        // End the Live Activity we have a reference to
        if let activity = workoutActivity {
            Task {
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .after(.now + 5) // Keep visible for 5 seconds
                )
                print("✅ Ended Live Activity: \(activity.id)")
            }
            workoutActivity = nil
        }

        // Also end any orphaned Live Activities (e.g. from previous crashed sessions)
        Task {
            let allActivities = Activity<WorkoutActivityAttributes>.activities
            for orphanedActivity in allActivities {
                if orphanedActivity.id != endedActivityID {
                    print("🗑️ Cleaning up orphaned Live Activity: \(orphanedActivity.id)")
                    await orphanedActivity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }
}

