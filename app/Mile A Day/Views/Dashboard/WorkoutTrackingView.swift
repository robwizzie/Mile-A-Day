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
    /// Tells the presenter this cover adopted a buddy session mid-flight — the
    /// wizard's buddy card path, where setup and lobby run INSIDE the cover
    /// (see `BuddyWizardFlowModifier`) instead of the user being bounced out
    /// to the dashboard's sheets. The dashboard mirrors the id into
    /// `activeBuddySessionId`, which is what its dismiss handler reads to
    /// offer the group recap — and on the next render `buddySessionId` above
    /// arrives non-nil, making the adopted and handed-in paths
    /// indistinguishable from then on.
    var onBuddySessionAdopted: ((String) -> Void)? = nil
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
    /// Retained so Cancel can invalidate it — see `startCountdown`.
    @State private var countdownTimer: Timer?
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
    @State private var recapWorkoutId: String?
    @State private var recapWasIndoor = false
    /// Quarter splits vs the ghost, snapshotted before tracking tears down.
    @State private var recapRaceSplits: [BestEffortStore.RaceSplit] = []
    @State private var recapGhostName: String = "your ghost"
    /// Pause-excluded elapsed time frozen at Finish. `endLiveActivity()` runs
    /// from `finishCleanup`, i.e. AFTER `stopTracking()` has cleared the pause
    /// timeline — recomputing there would hand the ended Live Activity a
    /// wall-clock duration the recap and Health both disagree with.
    @State private var finalActiveElapsed: TimeInterval?
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
    /// Published coach lines, echoed on screen under the delta chip.
    @ObservedObject private var coach = GhostCoach.shared
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
    /// One completed race, held from the moment it's decided until the
    /// HealthKit metadata stamp carries it onto the saved workout (and from
    /// there to the server). Signed: positive won, negative lost.
    struct RaceStamp {
        let marginSeconds: Double
        let ghostSeconds: Double
        let friendUserId: String?
    }
    @State private var pendingRaceStamp: RaceStamp?
    /// Chosen target, per activity, remembered between sessions.
    @AppStorage("ghostTargetV1.running") private var runTargetStorage = ""
    @AppStorage("ghostTargetV1.walking") private var walkTargetStorage = ""
    /// Drops the NEW pill on the arming card until the race is first set up.
    @AppStorage("hasArmedGhostRaceOnce") private var hasArmedGhostRaceOnce = false
    /// Set in `BuddyLobbyView` — the only screen a buddy session passes
    /// through, since the hand-off below skips the whole pre-start wizard
    /// where the solo race steps live. Read once on the buddy hand-off.
    @AppStorage("buddyGhostArmedV1") private var buddyGhostArmed = false
    /// Drops the buddy card's NEW pill once it's been opened once.
    @AppStorage("hasOpenedBuddyStartOnce") private var hasOpenedBuddyStartOnce = false
    /// The buddy flow presented from INSIDE this cover (the wizard's buddy
    /// card). Bindings for `BuddyWizardFlowModifier`, which puts each on its
    /// own presentation node.
    @State private var showBuddyStartSheet = false
    @State private var showBuddyLobby = false
    /// Session adopted by the in-cover lobby hand-off. `buddySessionId` is the
    /// presenter's copy and only arrives non-nil a render after
    /// `onBuddySessionAdopted` fires — this one is set synchronously, so the
    /// hand-off can start tracking without waiting on that round trip.
    @State private var adoptedBuddySessionId: String?

    /// Non-nil while this workout is a buddy walk, whichever door it came in
    /// through: handed in by the presenter (the lobby ran over the dashboard)
    /// or adopted mid-cover (the lobby ran in here, over the wizard). Every
    /// buddy check in this file reads THIS, never `buddySessionId` raw.
    private var effectiveBuddySessionId: String? {
        buddySessionId ?? adoptedBuddySessionId
    }

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
        let finalDelta = ghost.seconds - myMileSeconds
        withAnimation(.spring(response: 0.4)) {
            raceFinalDelta = finalDelta
        }
        MADHaptics.action()
        GhostCoach.shared.finish(won: finalDelta > 0, marginSeconds: finalDelta)
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

    /// Wall time since the workout started, minus every manual pause.
    ///
    /// THE duration figure: the on-screen clock, the Live Activity, the buddy
    /// heartbeat and the recap all read it, and HealthKit independently
    /// derives the same number from the pause/resume events written at finish
    /// — so the card, the lock screen and Apple Health agree.
    ///
    /// Derived from `workoutStartDate` rather than accumulated on the tick, so
    /// it stays correct across a backgrounded (suspended) timer and across a
    /// relaunch, where `pausedSeconds` is rehydrated from the persisted
    /// pause intervals.
    private var activeElapsedTime: TimeInterval {
        guard let start = workoutStartDate else { return elapsedTime }
        return max(0, Date().timeIntervalSince(start) - locationManager.pausedSeconds)
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
                        .font(.system(size: 52))
                case .ghost:
                    GhostSprite(size: 56, glancesBack: true)
                }
            }
            .foregroundColor(.white)
            .frame(height: 62)

            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text(subtitle)
                .font(.title3)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                // Wraps rather than clips at large Dynamic Type sizes, where
                // `.title3` grows well past the width these questions assume.
                .fixedSize(horizontal: false, vertical: true)
        }
        // 24, matching the option cards' 20pt gutter closely enough to read as
        // one column — the header used to be inset a further 12pt on each side,
        // which is what pushed "Select how you'll complete your mile" onto
        // three lines on a small phone.
        .padding(.horizontal, 24)
    }

    /// Which pre-start step is on screen, derived from the flags so the
    /// wizard can be rendered as ONE scaffold instead of four screens.
    enum PreStartStep {
        case activity, location, mode, ghostOptions

        /// Which progress segment to fill. Ghost options is a SUB-step of the
        /// mode choice, not a fourth question, so it shares segment 3.
        var indicator: Int { self == .activity ? 1 : (self == .location ? 2 : 3) }
    }

    private var currentPreStartStep: PreStartStep? {
        if showActivitySelection { return .activity }
        if showLocationTypeSelection { return .location }
        if showRaceModeSelection { return .mode }
        if showGhostOptions { return .ghostOptions }
        return nil
    }

    /// The whole pre-start wizard, as one screen whose CONTENTS change.
    ///
    /// The gradient behind this never re-rendered, but the step content used to
    /// slide as a single block — back bar, progress dots, glyph and title
    /// included — so every answer looked like the entire screen being replaced.
    /// Now the chrome is rendered once and holds still: only the question
    /// crossfades and only the options slide, which is the part that actually
    /// changed.
    private func preStartWizard(_ step: PreStartStep) -> some View {
        VStack(spacing: 0) {
            // Persistent. The dots and the back action change, the bar doesn't.
            wizardTopBar(step: step.indicator) { goBack(from: step) }

            if step == .ghostOptions {
                ghostOptionsBody
                    .transition(wizardTransition)
            } else {
                // Centred when it fits, scrollable when it doesn't.
                //
                // The steps used to be Spacer-padded into a fixed frame, which
                // was fine at two option cards and is not at three: on a 375pt
                // phone the activity step's content is taller than the screen,
                // and a plain VStack answers that by silently clipping the
                // bottom card. `minHeight: geo.size.height` keeps the Spacers
                // doing the centring on every phone that has the room, and
                // hands the overflow to the ScrollView on the ones that don't.
                GeometryReader { geo in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 28) {
                            Spacer(minLength: 8)

                            // Both animated regions sit in a ZStack so the
                            // outgoing and incoming copies OVERLAP. In a VStack
                            // they'd each be allocated their own row
                            // mid-transition and everything below would jump —
                            // the exact thing this restructure is meant to stop.
                            ZStack {
                                // Crossfades in place rather than sliding: the
                                // question is part of the frame, so moving it is
                                // what made the whole screen feel like it
                                // swapped.
                                wizardHeader(
                                    glyph: glyph(for: step),
                                    title: title(for: step),
                                    subtitle: subtitle(for: step)
                                )
                                .id(step)
                                .transition(.opacity)
                            }

                            ZStack {
                                VStack(spacing: 16) { options(for: step) }
                                    .id(step)
                                    .transition(wizardTransition)
                            }
                            // 20, not 32. The option cards are the widest thing
                            // on this screen and the titles inside them are the
                            // tightest fit, so the gutter is the cheapest 24pt
                            // to give back.
                            .padding(.horizontal, 20)

                            Spacer(minLength: 8)
                        }
                        .frame(minHeight: geo.size.height)
                    }
                }
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

    // MARK: - Per-step content

    private func glyph(for step: PreStartStep) -> WizardGlyph {
        let activity = selectedActivityType == .running ? "figure.run" : "figure.walk"
        switch step {
        case .activity: return .symbol("figure.walk")
        case .location: return .symbol(activity)
        // NOT the ghost: racing is one of the two answers here, and putting its
        // mascot above the question pre-announces the winner.
        case .mode: return .symbol("stopwatch")
        case .ghostOptions: return .ghost
        }
    }

    private func title(for step: PreStartStep) -> String {
        switch step {
        case .activity: return "Choose Activity Type"
        case .location: return "Choose Location"
        case .mode: return "Choose Your Mode"
        case .ghostOptions: return "Ghost Race"
        }
    }

    private func subtitle(for step: PreStartStep) -> String {
        switch step {
        case .activity: return "Select how you'll complete your mile"
        case .location: return "Where will you be working out?"
        case .mode: return "Race a time, or just log the miles."
        case .ghostOptions: return "Pick a time to chase."
        }
    }

    private func goBack(from step: PreStartStep) {
        switch step {
        case .activity:
            dismiss()
        case .location:
            goBack(to: { showActivitySelection = true },
                   from: { showLocationTypeSelection = false })
        case .mode:
            goBack(to: { showLocationTypeSelection = true },
                   from: { showRaceModeSelection = false })
        case .ghostOptions:
            goBack(to: { showRaceModeSelection = true },
                   from: { showGhostOptions = false })
        }
    }

    @ViewBuilder
    private func options(for step: PreStartStep) -> some View {
        switch step {
        case .activity:
            workoutOptionButton(icon: "figure.run", title: "Run", subtitle: "Track as a running workout") {
                selectActivity(.running)
            }
            workoutOptionButton(icon: "figure.walk", title: "Walk", subtitle: "Track as a walking workout") {
                selectActivity(.walking)
            }
            buddyOptionButton

        case .location:
            workoutOptionButton(icon: "location.fill", title: "Outdoor", subtitle: "Uses GPS for accurate tracking") {
                selectLocationType(.outdoor)
            }
            workoutOptionButton(icon: indoorLocationIcon, title: "Indoor", subtitle: "Treadmill or indoors — uses motion sensors") {
                selectLocationType(.indoor)
            }

        case .mode:
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
                // No time here on purpose. The next screen is where the target
                // is chosen, and printing one before that reads as a decision
                // already made — for a first-time racer it's a number they've
                // never seen, attached to a choice they haven't made yet.
                accessory: { optionChevron }
            ) {
                chooseRaceMode(ghost: true)
            }

        case .ghostOptions:
            EmptyView()
        }
    }

    // MARK: - Step 4: Ghost options

    /// The picker, inline. Same content the buddy lobby shows as a sheet — it
    /// just gets the wizard's background instead of modal chrome.
    ///
    /// No top bar of its own: `preStartWizard` renders that once for every
    /// step, which is what keeps the frame still while the contents change.
    private var ghostOptionsBody: some View {
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

        // Every COMPLETED race is recorded, win or loss. `raceFinalDelta` is the
        // frozen verdict at the 1.0-mile crossing — the same number the chip
        // showed — and its sign is the result: positive won, negative lost.
        //
        // Losses used to vanish entirely, which meant the feature could only
        // ever show you your victories: no history, no "two seconds away", no
        // reason to come back. The stamp is separate from the celebration for
        // exactly that reason — one records, the other congratulates.
        if let ghost = raceGhost, let delta = raceFinalDelta {
            pendingRaceStamp = RaceStamp(
                marginSeconds: delta,
                ghostSeconds: ghost.seconds,
                // Whose ghost it was, when it was a friend's. Read from the
                // armed target rather than the resolved one — `ResolvedGhost`
                // deliberately keeps only a display name.
                friendUserId: raceTarget.friendUserId
            )
        }

        // Won: the popup. A LOSS stays silent here on purpose — the frozen chip
        // already told that story mid-workout and the ghost lives another day.
        if let ghost = raceGhost, let delta = raceFinalDelta, delta > 0 {
            CelebrationManager.shared.addCelebration(
                .ghostBeaten(
                    win: GhostRaceWin(
                        marginSeconds: delta,
                        mileSeconds: max(0, ghost.seconds - delta),
                        ghostSeconds: ghost.seconds,
                        ghostName: raceGhostName,
                        activityKey: raceActivityKey,
                        newRecordSeconds: recordSeconds,
                        friendUserId: raceTarget.friendUserId,
                        workoutId: nil
                    )
                )
            )
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

    /// Copy for the Ghost Race option.
    ///
    /// Deliberately names no specific ghost. This card used to print the exact
    /// time it would race, and a variant of it named the target ("Chase your
    /// best…") — both presume a choice that is made on the NEXT screen, where
    /// you can pick your best, your PR, a friend's mile, or any time you type.
    /// For a first-time racer the old version was a number they'd never seen
    /// attached to a decision they hadn't made.
    private var ghostRaceSubtitle: String {
        "Chase your best, a friend's, or any time you pick — live ahead/behind on screen."
    }

    // MARK: - Countdown

    private var countdownContent: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("\(countdownNumber)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .scaleEffect(countdownNumber > 0 ? 1.0 : 0.5)
                .opacity(countdownNumber > 0 ? 1.0 : 0.0)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: countdownNumber)

            Spacer()

            // The last exit before a workout exists. Tapping Run when you meant
            // Walk, or opening this by accident, otherwise costs a junk workout
            // that has to be deleted afterwards — and a deleted workout still
            // churns the day's feed roles and streak recompute. Nothing has
            // been created yet at this point, so cancelling here is clean.
            //
            // Deliberately large and low: it's on screen for three seconds and
            // the user is often already moving.
            Button {
                cancelCountdown()
            } label: {
                Text("Cancel")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .overlay(
                                Capsule().strokeBorder(
                                    Color.white.opacity(0.4), lineWidth: 1.5)
                            )
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 48)
            .padding(.bottom, 64)
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
                        if effectiveBuddySessionId != nil, let session = buddyService.session {
                            BuddyRosterStrip(
                                session: session,
                                currentUserId: buddyService.currentUserId
                            )
                            .padding(.horizontal, 20)
                        } else if isTracking {
                            // Not in a walk right now — offer the way IN, from
                            // the one screen someone is actually looking at
                            // mid-workout. Renders nothing when there's nobody
                            // to join and nothing to rejoin, so an ordinary
                            // solo run is untouched.
                            BuddyMidWalkJoinStrip { sessionId in
                                adoptedBuddySessionId = sessionId
                                onBuddySessionAdopted?(sessionId)
                            }
                            .padding(.horizontal, 20)
                        }

                        distanceDisplay

                        progressRing(diameter: ringDiameter(for: screen.size.height))

                        timeDisplay

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

                workoutControls
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

            // Floored, never rounded up: a "1.00" here before the ring hits
            // 100% and the celebration fires reads as the app refusing to
            // count a finished mile (0.995 used to render exactly that).
            Text(currentDistance.milesText)
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText())

            Text("miles")
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))

            if startingDistance > 0 {
                VStack(spacing: 4) {
                    Text("Daily Total: \(totalDailyDistance.milesText) mi")
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
        // Nothing here is actionable during a deliberate pause, and one of
        // them is actively wrong: pausing to step inside is exactly when fixes
        // dry up, so "No GPS signal — head for open sky" would shout at
        // someone who paused BECAUSE they went indoors. It all returns on
        // resume, when it matters again.
        guard !locationManager.isPaused else { return nil }
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
                .foregroundColor(locationManager.isPaused ? .orange : .white)
                .monospacedDigit()

            // Manual pause outranks the movement guess — showing both at once
            // would be nonsense, and this one is a fact rather than an
            // inference, so it gets the definite word.
            if locationManager.isPaused {
                HStack(spacing: 5) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("PAUSED")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
                .transition(.opacity.combined(with: .scale))
            }

            // The movement gate freezing distance is CORRECT behavior — this
            // chip is what keeps it from reading as "tracking broke" while
            // the user stands at a light or sits down mid-walk.
            if locationManager.isAutoPaused, !locationManager.isPaused {
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

            // Every coach line as text too. This is what makes the feature work
            // with the volume down, with the coach switched off, or before the
            // `audio` background mode lets it speak through a locked screen.
            if raceGhost != nil, let line = coach.lastLine {
                Text(line)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
                    .id(line)
            }
        }
        .animation(.spring(response: 0.3), value: locationManager.isAutoPaused)
        .animation(.spring(response: 0.3), value: locationManager.isPaused)
        .animation(.spring(response: 0.3), value: raceFinalDelta != nil)
        .animation(.easeInOut(duration: 0.25), value: coach.lastLine)
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

    /// Pause/resume beside Stop, mirroring the Watch's control row
    /// (`WorkoutView`), which has paired them since day one — the phone was
    /// the odd one out. Pinned outside the scroll area with Stop, so neither
    /// control can ever be scrolled off screen.
    private var workoutControls: some View {
        HStack(spacing: 14) {
            if !isStopping {
                pauseResumeButton
            }
            stopButton
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
        .animation(.spring(response: 0.3), value: locationManager.isPaused)
    }

    private var pauseResumeButton: some View {
        let paused = locationManager.isPaused
        return Button {
            if paused { resumeWorkout() } else { pauseWorkout() }
        } label: {
            Image(systemName: paused ? "play.fill" : "pause.fill")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(
                    Circle()
                        .fill((paused ? Color.green : Color.orange).opacity(0.3))
                        .overlay(
                            Circle().stroke(paused ? Color.green : Color.orange, lineWidth: 2)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(paused ? "Resume workout" : "Pause workout")
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
                    // Shrinks rather than truncates: the pause button now
                    // takes 64pt + spacing out of this row, and "Stop
                    // Workout" at large Dynamic Type on a small screen would
                    // otherwise clip to "Stop Work…". Never `.fixedSize` here
                    // — that publishes a minimum width no ancestor can shrink
                    // and pushes the overflow out to the screen gutter.
                    Text("Stop Workout")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
        .buttonStyle(PlainButtonStyle())
    }

    /// Freeze the workout. The manager owns every consequence (accrual, route,
    /// pedometer span, moving clock, watchdog, GPS power tier) and writes the
    /// pause through to disk itself — all this has to do is tell the Live
    /// Activity immediately rather than letting it sit on a stale ticking
    /// clock until the 30s cadence comes round.
    private func pauseWorkout() {
        guard isTracking, !isStopping else { return }
        locationManager.pause()
        MADHaptics.action()
        lastActivityPushDate = .distantPast
        updateLiveActivity()
    }

    private func resumeWorkout() {
        guard isTracking, !isStopping else { return }
        locationManager.resume()
        MADHaptics.action()
        lastActivityPushDate = .distantPast
        updateLiveActivity()
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

                Text("\(startingDistance.milesText) miles reached")
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

    /// Fixed so every card's title starts on the same x — including the buddy
    /// card, whose leading slot is a pile of faces rather than a symbol.
    ///
    /// 46, not the original 50: the text column on a 375pt phone is the tight
    /// dimension on this screen, and every point spent here is a point the
    /// titles don't get.
    static let optionGlyphWidth: CGFloat = 46

    private func optionGlyph(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 30))
            .frame(width: Self.optionGlyphWidth)
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
            HStack(spacing: 14) {
                leading()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        // The title is the one thing here that CANNOT wrap or
                        // clip: at 28pt "Just Track It" wants ~190pt and a
                        // 375pt phone leaves the text column ~189pt, so it was
                        // breaking to two lines (or truncating once the badge
                        // took its share). Scaling is the right trade — a
                        // title a few percent smaller reads fine, a title
                        // reading "Just Track…" does not.
                        Text(title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .allowsTightening(true)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .tracking(0.8)
                                .foregroundColor(.black.opacity(0.8))
                                .lineLimit(1)
                                // Safe here where `.fixedSize` normally isn't:
                                // every badge is a short literal ("NEW",
                                // "2 INVITES"), never open-ended data, so it
                                // can't publish a minimum width that starves
                                // the row.
                                .fixedSize()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.yellow))
                        }
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .opacity(0.9)
                        .multilineTextAlignment(.leading)
                        // Wraps to as many lines as it needs instead of
                        // truncating — which is why the subtitles were never
                        // the ones getting cut off.
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                accessory()
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
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

    /// The third card on the activity step: do this mile WITH someone.
    ///
    /// Featured, because it's the only option here that isn't just a HealthKit
    /// activity type. Live "friends out right now" belongs on the Friends tab,
    /// so the Dashboard keeps this as a generic buddy entry point plus invite
    /// count only.
    ///
    /// The whole flow stays INSIDE this cover: setup sheet and lobby present
    /// over the wizard (`BuddyWizardFlowModifier` on the body), so Cancel and
    /// Leave land back on this step and the countdown starts tracking in
    /// place — no bouncing out to the dashboard and back.
    @ViewBuilder
    private var buddyOptionButton: some View {
        // Hidden mid-buddy-walk — this tracker is already in one.
        if effectiveBuddySessionId == nil {
            workoutOptionButton(
                leading: { optionGlyph("figure.2") },
                title: "With a Buddy",
                subtitle: BuddyStartPrompt.subtitle(invites: buddyService.invites),
                featured: true,
                badge: BuddyStartPrompt.badge(
                    invites: buddyService.invites,
                    hasStartedOnce: hasOpenedBuddyStartOnce
                ),
                accessory: { optionChevron }
            ) {
                MADHaptics.tap()
                hasOpenedBuddyStartOnce = true
                // Mirrors BuddyFlowModifier's notification handler: a room
                // already waiting (an accepted invite, a live session) goes
                // straight to the lobby — there is nothing left to configure.
                // Re-enterable only: a session THIS user already finished must
                // never route back toward the lobby's instant hand-off.
                if buddyService.canReenterLiveSession {
                    showBuddyLobby = true
                } else {
                    showBuddyStartSheet = true
                }
            }
        }
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

            if let step = currentPreStartStep {
                // ONE branch for all four steps: the scaffold stays mounted
                // across them, so only what changed animates.
                preStartWizard(step)
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
                    healthManager: healthManager,
                    workoutId: recapWorkoutId,
                    isIndoor: recapWasIndoor,
                    raceSplits: recapRaceSplits,
                    raceGhostName: recapGhostName,
                    onDistanceAdjusted: { newDistance in
                        recapDistance = newDistance
                    },
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
                // Stamp the workout, not just this presentation — the @State
                // flag dies with the cover and re-entry would buzz again.
                InProgressWorkoutStore.markCelebrated(catchUp: true)

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
            //
            // At the FULL goal, deliberately — a raw compare, not the 0.95
            // scoring tolerance (product rule). The tolerance exists so a
            // near-miss never BREAKS a streak; it is a safety net, not the
            // finish line, and celebrating at 0.95 would teach users to stop
            // short of the goal they set. Displays are floored to 2 decimals
            // (`milesText`), so the screen can never contradict this by
            // showing a rounded-up "1.00" before the celebration fires.
            // Only show completion if:
            // 1. We haven't shown it yet
            // 2. The goal wasn't already completed when we started (startingDistance < goalDistance)
            // 3. We've now reached the goal with total daily distance
            if !hasShownCompletion && startingDistance < goalDistance && totalDailyDistance >= goalDistance {
                hasShownCompletion = true // Mark as shown so it doesn't loop
                // Stamp the workout, not just this presentation — see above.
                InProgressWorkoutStore.markCelebrated(completion: true)

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

            // Buddy Walk hand-off — see startBuddyWorkoutIfReady().
            //
            // Deliberately checked BEFORE the recovery branch's early return but
            // AFTER its guards: a recoverable workout on disk always wins, since
            // that's a workout already in progress and starting a second one
            // would fail the lock anyway.
            if startBuddyWorkoutIfReady() { return }

            guard let saved = InProgressWorkoutStore.load(), saved.isActive else { return }

            // Restore core state. The clock is settled AFTER tracking restarts
            // below, once `pausedSeconds` has been rehydrated — computing it
            // here would count every past pause as active time.
            workoutStartDate = saved.startTime

            // Restore activity + location type
            if saved.activityType == "Running" {
                selectedActivityType = .running
            } else if saved.activityType == "Walking" {
                selectedActivityType = .walking
            }
            if let locationType = HKWorkoutSessionLocationType(rawValue: saved.locationTypeRawValue) {
                selectedLocationType = locationType
            }

            // Celebrations are one-shot per WORKOUT, but their flags are
            // @State — one-shot per PRESENTATION. This view is destroyed
            // whenever the cover dismisses, so returning to a workout that had
            // already crossed the goal re-armed both, and the first distance
            // tick replayed the success haptic + overlay: a buzz on EVERY
            // return after 100%. Two restore sources, both required:
            //  1. The persisted stamps — written the instant each celebration
            //     fired, so they survive any lifecycle (this is the layer that
            //     actually guarantees once-per-workout).
            //  2. A derived fallback for pre-stamp blobs, compared against the
            //     LIVE manager distance, not just the store's: the manager
            //     keeps tracking while the cover is down and the store's
            //     throttled copy can lag it — seeding below the live value
            //     re-armed a milestone the next distance tick then "re-earned"
            //     (the buzz on every return the stamps exist to kill).
            let restoredDistance = max(saved.currentDistance, locationManager.liveDistance)
            hasReachedPreviousProgress = saved.celebratedCatchUp == true
                || (startingDistance > 0 && restoredDistance >= startingDistance)
            hasShownCompletion = saved.celebratedCompletion == true
                || startingDistance + restoredDistance >= goalDistance

            // The Live Activity's goal push is the THIRD one-shot and it was
            // missed by the two above: it buzzes the phone via
            // AlertConfiguration rather than MADHaptics, and `startLiveActivity`
            // pre-arms `hasSentGoalAlert` only on the branch that CREATES an
            // activity — a re-entry adopts the existing one and returns early,
            // so the flag stayed false and the next 1 Hz tick re-fired "Mile
            // complete!" with sound + vibration, on every return past the goal.
            // Stamp-first, like the others; the derived arm covers a goal
            // already met before this workout started (nothing left to cross,
            // so nothing is due) and blobs written by pre-stamp builds.
            hasSentGoalAlert = saved.alertedGoalComplete == true
                || (goalDistance > 0 && startingDistance >= goalDistance)

            // Jump directly into the tracking UI
            clearPreStartSteps()
            isTracking = true

            // Restore the snap chip (count + thumbnail) — mid-run photos
            // survive an app relaunch alongside the workout itself.
            refreshSnapState()

            // Resume tracking with the saved distance as the starting point.
            // For pedometer: new pedometer readings will ADD to saved.currentDistance.
            // For GPS: new GPS deltas will add to saved.currentDistance.
            //
            // The pause timeline rides along: an interval left OPEN means the
            // workout was paused when the app died, so it comes back paused.
            // Resuming it silently would start counting ground the user never
            // asked for, on a screen they haven't looked at yet.
            locationManager.startTracking(
                locationType: selectedLocationType,
                initialDistance: saved.currentDistance,
                pauseIntervals: saved.pauseIntervals ?? []
            )

            // Now that `pausedSeconds` is rehydrated, settle the clock.
            elapsedTime = activeElapsedTime

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
        .modifier(
            BuddyWizardFlowModifier(
                showStartSheet: $showBuddyStartSheet,
                showLobby: $showBuddyLobby,
                onStarted: { session in
                    adoptedBuddySessionId = session.id
                    onBuddySessionAdopted?(session.id)
                    startBuddyWorkoutIfReady()
                },
                // Lets the modifier keep the mid-walk join offer fresh without
                // adding another node to this already type-check-fragile chain.
                activeSessionId: effectiveBuddySessionId
            )
        )
    }

    /// The buddy hand-off: the lobby already ran the server-synced countdown,
    /// so there is nothing left to pick and nothing left to count down — start
    /// moving immediately.
    ///
    /// Reached from two places: `.onAppear`, for a session handed in by the
    /// presenter (the lobby ran over the dashboard), and the in-cover lobby's
    /// `onStarted`, for one adopted over the wizard. Both can fire for the
    /// same session — a dismissing cover re-runs `.onAppear` — which is what
    /// the one-shot flag is for.
    ///
    /// Ghost race: this hand-off skips the whole pre-start wizard, which is
    /// the only place the solo race steps live — so without reading the
    /// lobby's armed flag a buddy walk could never race, even though it
    /// already feeds BestEffortStore on finish. Everything downstream
    /// (resolvedGhost, the delta chip, the 1-mile freeze, the celebration)
    /// only ever needed raceArmed.
    @discardableResult
    private func startBuddyWorkoutIfReady() -> Bool {
        guard effectiveBuddySessionId != nil, !hasAutoStartedBuddyWorkout,
              !isStopping, !isTracking,
              // Defense in depth behind the lobby/entry-point guards: never
              // auto-start a mile for a session THIS user already finished.
              buddyService.session?.me(buddyService.currentUserId)?.status != .finished,
              InProgressWorkoutStore.load()?.isActive != true else { return false }
        hasAutoStartedBuddyWorkout = true
        selectedActivityType =
            (buddyService.session?.isRunning ?? false) ? .running : .walking
        // NOT hardcoded outdoor any more. This line picks the INSTRUMENT —
        // outdoor measures with GPS, which indoors never returns a fix that
        // clears the 50m accuracy gate — so a buddy walker on a treadmill
        // watched their distance sit at 0.00 for the whole session while
        // everyone else's climbed. The lobby asks each participant for
        // themselves (`BuddyLocationType`); this is where their answer lands.
        selectedLocationType =
            buddyService.myLocationType == .indoor ? .indoor : .outdoor
        clearPreStartSteps()
        raceArmed = buddyGhostArmed
        isTracking = true
        startWorkout()
        return true
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 12)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 12)
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

    /// The 3-2-1. Retained in `countdownTimer` so Cancel can actually stop it:
    /// as a bare `scheduledTimer` it outlived the view, so tearing the screen
    /// down still fired `startWorkout()` three seconds later.
    private func startCountdown() {
        // onAppear can run again (re-entering after a cancel) — never leave a
        // second timer racing the first.
        countdownTimer?.invalidate()

        // Haptic feedback for countdown
        let impact = UIImpactFeedbackGenerator(style: .heavy)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdownNumber > 1 {
                countdownNumber -= 1
                impact.impactOccurred()
            } else {
                timer.invalidate()
                countdownTimer = nil
                // Start workout
                withAnimation {
                    showCountdown = false
                    isTracking = true
                }
                startWorkout()
            }
        }
    }

    /// Back out before anything is created. Returns to the first step rather
    /// than dismissing, because the common reason to cancel is picking Run when
    /// you meant Walk — and from there Back still leaves.
    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        MADHaptics.tap()
        wizardGoingBack = true
        withAnimation(.easeInOut(duration: 0.28)) {
            showCountdown = false
            countdownNumber = 3
            showActivitySelection = true
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
        recapWorkoutId = nil
        recapWasIndoor = false
        // This view instance survives across sessions — a stale frozen clock
        // would be handed to the next workout's ended Live Activity.
        finalActiveElapsed = nil
        if raceArmed, let ghost = resolvedGhost {
            raceGhost = ghost.effort
            raceGhostName = ghost.shortName
            GhostCoach.shared.start(
                ghostName: ghost.shortName,
                isRun: selectedActivityType == .running,
                ghostSeconds: ghost.effort.seconds
            )
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
            guard workoutStartDate != nil else { return }
            // Don't persist state while we're in the middle of stopping
            guard !isStopping else { return }
            // Freezes on its own while manually paused — `pausedSeconds` grows
            // at exactly the rate wall time does for the length of the pause.
            elapsedTime = activeElapsedTime
            updateLiveActivity()

            // Ghost coach rides this tick rather than owning a timer. It reads
            // the SAME delta the chip renders, so the voice can never say
            // something the screen contradicts.
            if let ghost = raceGhost, let delta = raceDeltaSeconds {
                GhostCoach.shared.update(
                    GhostCoach.Sample(
                        distance: locationManager.liveDistance,
                        raceClock: locationManager.raceClockSeconds,
                        delta: delta,
                        ghostSeconds: ghost.seconds,
                        recentPace: locationManager.recentPaceSecondsPerMile
                    )
                )
            }
            // Foreground heartbeat driver (self-throttled to ~45s). The
            // background driver is the location/pedometer callback path.
            livePresence.tick()

            // Buddy Walk: piggyback on the tick that already exists rather than
            // adding a second timer. The service throttles this to one network
            // call every 5s, and that call's response carries the whole roster
            // back — so an actively-tracking client never polls separately.
            if effectiveBuddySessionId != nil {
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

        // Capture the pause timeline BEFORE `stopTracking()` below clears it.
        // Ending while still paused is legitimate (pause, decide you're done,
        // tap End), and leaves the last interval open — it gets closed at
        // `endDate` when the HealthKit events are built, so that final stretch
        // is excluded rather than silently counted.
        let pauseIntervals = locationManager.pauseIntervals
        let pausedSeconds = locationManager.pausedSeconds

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

        // Quarter splits vs the ghost, captured HERE because stopTracking()
        // below clears the effort curve — the recap renders after teardown, so
        // by the time it exists the raw material is gone.
        if let ghost = raceGhost {
            recapRaceSplits = BestEffortStore.raceSplits(
                rawCurve: locationManager.effortCurve,
                distanceScale: curveDistance > 0 ? finalDistance / curveDistance : 1.0,
                ghost: ghost
            )
            recapGhostName = raceGhostName
        } else {
            recapRaceSplits = []
        }

        // Freeze the recap stats now, before anything refreshes underneath us
        recapDistance = finalDistance
        // Pause-excluded, matching what HealthKit will compute from the events
        // written below and therefore what the backend stores as
        // `total_duration`. The recap must not be the one surface quoting a
        // wall-clock number nothing else agrees with.
        recapDuration = workoutStartDate
            .map { max(0, Date().timeIntervalSince($0) - pausedSeconds) } ?? elapsedTime
        finalActiveElapsed = recapDuration
        recapStartingDistance = startingDistance
        recapGoalDistance = goalDistance
        recapWasIndoor = selectedLocationType == .indoor

        // Buddy Walk: report the RECONCILED final distance (not the raw live
        // sum) and mark this participant done, so the standings everyone sees
        // match the number this phone is about to save to HealthKit. The
        // server later replaces even this with the synced HKWorkout.
        if effectiveBuddySessionId != nil {
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

        // The user has ENDED this workout — record that synchronously, before
        // the async HealthKit save. finishCleanup() clears the store only at
        // the end of that chain, and locking or swipe-killing the app right
        // after tapping End left `isActive` true — so the next launch
        // auto-presented the tracker and made the same mile get ended again.
        InProgressWorkoutStore.markEnded()

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
        let addCompletion: (Bool, Error?) -> Void = { added, addError in
            // The distance sample's fate used to be discarded here (`{ _, _ in`).
            // It can genuinely fail — Workouts share access granted while
            // "Walking + Running Distance" is denied is one tap apart in
            // Settings — and the workout then saved with NO distance at all,
            // silently, with the tracked number gone forever. It isn't gone
            // now: the ledger below is what every screen reads.
            if !added {
                print("[WorkoutTracking] ⚠️ Distance sample rejected: \(String(describing: addError)) — the tracked \(String(format: "%.2f", finalDistance)) mi stands via the ledger")
            }
            builder.endCollection(withEnd: endDate) { _, endError in
                if let endError {
                    print("[WorkoutTracking] ⚠️ endCollection failed: \(endError)")
                }
                builder.finishWorkout { workout, error in
                    let saved = (workout != nil && error == nil)
                    // THE receipt. Written before anything reads the workout
                    // back, so no surface — and no sync — can report a smaller
                    // number than the one the user watched being measured.
                    if let workout, saved {
                        TrackedWorkoutLedger.shared.record(
                            workoutId: workout.uuid.uuidString, miles: finalDistance)
                        DispatchQueue.main.async {
                            self.recapWorkoutId = workout.uuid.uuidString
                        }
                    }
                    let finalize = {
                        DispatchQueue.main.async {
                            self.finishCleanup(workoutSaved: saved)
                            if saved {
                                // Force the workout cache to refetch. It holds
                                // itself fresh for an hour, so the Workouts
                                // screen would otherwise show today WITHOUT the
                                // walk that just finished — a day total that
                                // visibly drops the moment you stop tracking.
                                self.healthManager.invalidateWorkoutCacheFreshness()
                                self.healthManager.fetchAllWorkoutData()
                            }
                        }
                    }
                    // Whatever HealthKit ended up storing, the server must hear
                    // the tracked number. The route branch below already
                    // re-uploads; this covers everything else (indoor sessions,
                    // a route that failed to write, a rejected distance sample)
                    // where the observer-raced first upload read HealthKit
                    // before this receipt existed.
                    if let workout, saved,
                       abs((workout.totalDistance?.doubleValue(for: .mile()) ?? 0) - finalDistance) > 0.005,
                       routeLocations.count < 2 {
                        let workoutId = workout.uuid
                        Task { await WorkoutSyncService.shared.uploadWorkout(withId: workoutId) }
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
        if let race = pendingRaceStamp {
            // Signed — a negative margin is a race that was lost, and it is
            // stored just as deliberately as a win.
            metadata[WorkoutLocationManager.ghostMarginMetadataKey] = race.marginSeconds
            metadata[WorkoutLocationManager.ghostTargetMetadataKey] = race.ghostSeconds
            // Only present when the ghost was a friend's — that's what lets
            // the server tell them they were caught (and only when it was a
            // win; the server re-checks the sign).
            if let friendId = race.friendUserId {
                metadata[WorkoutLocationManager.ghostFriendMetadataKey] = friendId
            }
        }
        let addMetadataThenSave = {
            if metadata.isEmpty {
                beginSave()
            } else {
                builder.addMetadata(metadata) { _, _ in
                    beginSave()
                }
            }
        }

        // Manual pauses become HealthKit pause/resume events, which is what
        // makes `HKWorkout.duration` come back pause-excluded — and that
        // property is the whole reason no backend change is needed: the sync
        // uploads `workout.duration` as `totalDuration` and the server stores
        // it unchanged. It also puts an in-app walk in line with the Watch and
        // with every third-party workout arriving through HealthKit, all of
        // which already carry pause-excluded durations.
        //
        // Built from the persisted intervals rather than events accumulated in
        // memory, so a workout paused before its builder finished authorizing
        // — or one that survived a relaunch — still records its pauses.
        var pauseEvents: [HKWorkoutEvent] = []
        for interval in pauseIntervals {
            // Clamp into the workout's own window; a pause outside it would be
            // rejected and take the whole batch with it.
            let pauseStart = min(max(interval.start, startDate), endDate)
            // An open interval means the user ended while paused — close it at
            // the workout end so the stretch is excluded, not left ambiguous.
            let pauseEnd = min(max(interval.end ?? endDate, pauseStart), endDate)
            guard pauseEnd > pauseStart else { continue }
            pauseEvents.append(
                HKWorkoutEvent(
                    type: .pause,
                    dateInterval: DateInterval(start: pauseStart, duration: 0),
                    metadata: nil
                )
            )
            pauseEvents.append(
                HKWorkoutEvent(
                    type: .resume,
                    dateInterval: DateInterval(start: pauseEnd, duration: 0),
                    metadata: nil
                )
            )
        }

        if pauseEvents.isEmpty {
            addMetadataThenSave()
        } else {
            // Sequenced rather than fired alongside: these must land before
            // `endCollection`, and concurrent builder mutations aren't ordered.
            builder.addWorkoutEvents(pauseEvents) { added, error in
                if !added {
                    print("[WorkoutTracking] ⚠️ Pause events rejected: \(String(describing: error)) — duration will read as elapsed")
                }
                addMetadataThenSave()
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
        pendingRaceStamp = nil
        GhostCoach.shared.stop()

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

        // Pause-excluded, like every other clock in the app. This path also
        // runs on recovery, where the workout may come back PAUSED — an
        // activity created with a live anchor there would tick away on the
        // lock screen over a frozen workout.
        let realTimeElapsed = activeElapsedTime
        let paused = locationManager.isPaused

        let initialState = WorkoutActivityAttributes.ContentState(
            distance: currentDistance,
            totalDailyDistance: totalDailyDistance,
            elapsedTime: realTimeElapsed,
            goalDistance: goalDistance,
            activityType: selectedActivityType == .running ? "Running" : "Walking",
            timerStartDate: paused ? nil : Date().addingTimeInterval(-realTimeElapsed),
            streak: userManager.currentUser.streak,
            movingSeconds: locationManager.movingSeconds,
            isAutoPaused: locationManager.isAutoPaused,
            ghostDeltaSeconds: raceDeltaSeconds,
            hypeCount: livePresence.sessionHypes.isEmpty ? nil : livePresence.sessionHypes.count,
            latestHypeName: livePresence.sessionHypes.last?.senderName,
            isPaused: paused
        )

        // If the goal was already met before this workout (post-goal extra
        // miles), don't fire the "mile complete" island alert mid-session.
        if goalDistance > 0 && totalDailyDistance >= goalDistance {
            hasSentGoalAlert = true
            InProgressWorkoutStore.markCelebrated(goalAlert: true)
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
        let realTimeElapsed = activeElapsedTime
        let paused = locationManager.isPaused

        // Update Live Activity (if we have one)
        if workoutActivity == nil {
            startLiveActivity()
        }
        if let activity = workoutActivity {
            // Goal crossed during THIS workout → one celebratory alert update
            // that briefly expands the Dynamic Island / lights up the watch.
            // freshTotalDaily rides the monotonic saved-verbatim estimator,
            // so this "streak safe" promise can never be walked back. At the
            // FULL goal, matching the on-screen celebration — the 0.95
            // tolerance is the server's never-break-a-streak safety net, not
            // the finish line.
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
                    // Stamp the WORKOUT, not just this presentation — the
                    // @State flag dies with the cover and re-entry would
                    // otherwise re-alert (sound + vibration) every time.
                    InProgressWorkoutStore.markCelebrated(goalAlert: true)
                }
                lastActivityPushDate = Date()
                lastPushedDistance = freshDistance

                let updatedState = WorkoutActivityAttributes.ContentState(
                    distance: freshDistance,
                    totalDailyDistance: freshTotalDaily,
                    elapsedTime: realTimeElapsed,
                    goalDistance: goalDistance,
                    activityType: selectedActivityType == .running ? "Running" : "Walking",
                    // No anchor while paused: `Text(timerInterval:)` is
                    // rendered by the SYSTEM and keeps ticking with no updates
                    // from us, which is exactly wrong on a frozen workout.
                    // Dropping the anchor falls the view back to the static
                    // pushed value — the same mechanism the ended activity
                    // already uses to show a final time.
                    timerStartDate: paused ? nil : Date().addingTimeInterval(-realTimeElapsed),
                    streak: userManager.currentUser.streak,
                    movingSeconds: locationManager.movingSeconds,
                    isAutoPaused: locationManager.isAutoPaused,
                    ghostDeltaSeconds: raceDeltaSeconds,
                    hypeCount: livePresence.sessionHypes.isEmpty ? nil : livePresence.sessionHypes.count,
                    latestHypeName: livePresence.sessionHypes.last?.senderName,
                    isPaused: paused
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
        // Frozen at Finish — see `finalActiveElapsed`. By the time this runs,
        // `stopTracking()` has already cleared the pause timeline.
        let realTimeElapsed = finalActiveElapsed ?? activeElapsedTime

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
            isAutoPaused: false,
            isPaused: false
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
