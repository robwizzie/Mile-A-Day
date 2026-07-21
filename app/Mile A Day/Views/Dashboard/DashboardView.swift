import SwiftUI
import HealthKit
import WidgetKit
import UIKit
import CoreLocation
import CoreMotion
import ActivityKit

// MARK: - iOS 26 Native Liquid Glass Navigation Bar
// Note: iOS 26 automatically applies Liquid Glass to native navigation bars.
// The system handles the glass effect when using .toolbarBackground(.automatic, for: .navigationBar)

struct DashboardView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    /// Bindings owned by MainTabView — the inbox bell + count moved into
    /// the new MADTabHeader on Dashboard, but MainTabView still drives
    /// cross-tab routing (push handlers can flip `showNotificationInbox`).
    @Binding var unreadNotificationCount: Int
    @Binding var showNotificationInbox: Bool
    @EnvironmentObject var notificationService: MADNotificationService
    @EnvironmentObject var competitionService: CompetitionService
    @EnvironmentObject var friendService: FriendService
    @StateObject private var workoutService = WorkoutService()
    @StateObject private var syncService = WorkoutSyncService.shared

    @State private var showConfetti = false
    @State private var showGoalSheet = false
    @State private var showDashboardSettings = false
    /// "See All" on the Recent Workouts card. Lives here, not on the card, so
    /// the destination is registered on the stack's root — a
    /// navigationDestination declared inside the scroll content can miss.
    @State private var showWorkouts = false
    @State private var newGoalMiles: Double = 1.0
    @State private var isRefreshing = false
    @State private var showWorkoutUploadAlert = false
    @StateObject private var celebrationManager = CelebrationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    /// Controls presentation of the in‑progress workout tracking UI.
    @State private var showWorkoutView = false
    /// Whether to show a compact "Resume workout" banner when an in‑progress workout exists
    /// but the full‑screen tracker is not currently visible.
    @State private var showInProgressBanner = false
    @State private var showForceResetAlert = false

    /// Controls presentation of the manual workout entry sheet.
    @State private var showManualWorkoutEntry = false

    /// Cached "is there an active in-progress workout?" flag. Reading
    /// `InProgressWorkoutStore.load()` decodes the full persisted workout
    /// (up to thousands of GPS points) — too expensive to do per render,
    /// so views read this flag and it's refreshed on appear / cover dismiss.
    @State private var hasActiveWorkout = false

    /// Competition opened directly from a Dashboard rivalry-hint row. Sheet
    /// presentation, not a tab switch — keeps the user on Dashboard in the
    /// back stack so dismiss returns them to where they tapped.
    @AppStorage("competitionsCollapsed") private var competitionsCollapsed: Bool = false

    /// User preference: "chart" (line chart) or "streak" (streak card)
    @AppStorage("weekViewStyle") private var weekViewStyle: String = "streak"

    /// Collapsible section state
    @AppStorage("statsCollapsed") private var statsCollapsed: Bool = true
    @AppStorage("workoutsCollapsed") private var workoutsCollapsed: Bool = true


    /// Navigation state for badges view from celebration
    @State private var navigateToBadgesFromCelebration = false

    /// Guards against launching multiple concurrent streak fetches when several
    /// observers trigger the goal-celebration check at the same time.
    @State private var isPreparingGoalCelebration = false

    // Ask-mode pending friend notifications (stash sheet). The celebration
    // embed handles the mile-completed pending; this sheet catches everything
    // else (walks, extra workouts, background syncs).
    @ObservedObject private var pendingService = PendingNotificationsService.shared
    @State private var showPendingSheet = false

    /// First-run welcome tour state. The flag persists so the full-screen
    /// tour only auto-plays once; users can replay it any time from the
    /// dashboard welcome banner or Help & Support.
    @AppStorage("hasSeenWelcomeTour") private var hasSeenWelcomeTour = false
    /// Master switch for the post-run photo prompt + auto-sharing the mile to the
    /// feed. On by default; users can turn the whole flow off in settings.
    @AppStorage("autoShareRunsToFeed") private var autoShareRunsToFeed = true
    /// Shared with InstructionsBanner — completing the tour hides the banner.
    @AppStorage("hasSeenInstructions") private var hasSeenInstructions = false
    @State private var showWelcomeTour = false

    /// Getting-started checklist dismissal. The card also auto-hides once all
    /// items are complete, so this only matters for users who close it early.
    @AppStorage("gettingStartedDismissed") private var gettingStartedDismissed = false
    /// Prevents the checklist from flashing on load for established users.
    /// Starts hidden and only becomes visible after async data (friends,
    /// competitions, badges) has loaded and we confirm items remain incomplete.
    @State private var gettingStartedReady = false

    /// Cached "a mid-run photo is waiting but the goal isn't done" flag, so the
    /// nudge renders without touching disk in `body` (MidRunPhotoStash.count
    /// enumerates the sandbox dir). Refreshed on appear + workout changes.
    @State private var midRunPhotoWaiting = false


    /// Build goal completion stats for the celebration
    private func buildGoalCompletionStats() -> GoalCompletionStats {
        GoalCompletionStats(
            todaysDistance: healthManager.todaysDistance,
            goalDistance: userManager.currentUser.goalMiles,
            currentStreak: userManager.currentUser.streak,
            totalLifetimeMiles: healthManager.totalLifetimeMiles,
            bestDayMiles: healthManager.cachedMostMilesInOneDay,
            todaysAveragePace: healthManager.todaysAveragePace,
            todaysFastestPace: healthManager.todaysFastestPace,
            personalBestPace: userManager.currentUser.fastestMilePace > 0 ? userManager.currentUser.fastestMilePace : nil,
            todaysTotalDuration: healthManager.todaysTotalDuration,
            todaysCalories: healthManager.todaysTotalCalories,
            todaysWorkoutCount: healthManager.todaysWorkoutCount,
            workoutBreakdowns: buildWorkoutBreakdowns(),
            latestWorkout: buildLatestWorkout()
        )
    }

    /// Re-play today's celebration so the user can re-watch and re-share at any time.
    /// Picks the right animation for the day: yearly milestone if the streak crossed a
    /// year boundary, otherwise the standard goal-completed celebration (which itself
    /// surfaces the matching streak milestone visuals).
    private func replayTodaysCelebration() {
        let streak = userManager.currentUser.streak
        if streak > 0 && streak % 365 == 0 {
            let years = streak / 365
            let startDate = Calendar.current.date(byAdding: .day, value: -streak, to: Date())
            let info = YearlyMilestoneInfo(
                years: years,
                totalMiles: healthManager.totalLifetimeMiles,
                totalStreakDays: streak,
                streakStartDate: startDate
            )
            celebrationManager.replayCelebration(.yearMilestone(info: info))
        } else {
            let stats = buildGoalCompletionStats()
            celebrationManager.replayCelebration(.goalCompleted(stats: stats))
        }
    }

    /// Group today's workouts by activity type into breakdowns
    private func buildWorkoutBreakdowns() -> [WorkoutBreakdown] {
        var byType: [HKWorkoutActivityType: (distance: Double, duration: TimeInterval)] = [:]
        for workout in healthManager.todaysWorkouts {
            let miles = workout.totalDistance?.doubleValue(for: .mile()) ?? 0
            let existing = byType[workout.workoutActivityType] ?? (0, 0)
            byType[workout.workoutActivityType] = (existing.distance + miles, existing.duration + workout.duration)
        }
        return byType.map { type, data in
            WorkoutBreakdown(
                type: workoutTypeString(type),
                distance: data.distance,
                duration: data.duration,
                displayName: workoutDisplayName(type),
                icon: workoutIconName(type)
            )
        }.sorted { $0.distance > $1.distance }
    }

    /// Get the most recent workout as a breakdown
    private func buildLatestWorkout() -> WorkoutBreakdown? {
        guard let latest = healthManager.todaysWorkouts.sorted(by: { $0.endDate > $1.endDate }).first else { return nil }
        let miles = latest.totalDistance?.doubleValue(for: .mile()) ?? 0
        return WorkoutBreakdown(
            type: workoutTypeString(latest.workoutActivityType),
            distance: miles,
            duration: latest.duration,
            displayName: workoutDisplayName(latest.workoutActivityType),
            icon: workoutIconName(latest.workoutActivityType)
        )
    }

    private func workoutTypeString(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .hiking: return "hiking"
        default: return "other"
        }
    }

    private func workoutDisplayName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Run"
        case .walking: return "Walk"
        case .cycling: return "Cycle"
        case .hiking: return "Hike"
        default: return "Workout"
        }
    }

    private func workoutIconName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "figure.outdoor.cycle"
        case .hiking: return "figure.hiking"
        default: return "figure.mixed.cardio"
        }
    }

    /// Check if goal is completed and show celebration if appropriate
    private func checkAndShowGoalCelebration() {
        // Only show if:
        // 1. Initial data has fully loaded (prevents premature celebration on cold launch)
        // 2. Goal is actually completed (distance >= goal)
        // 3. We have meaningful distance data (> 0)
        // Note: CelebrationManager handles duplicate prevention via date-based tracking
        guard healthManager.hasLoadedInitialData else {
            print("[Dashboard] ⏳ Skipping celebration check - initial data not yet loaded")
            return
        }
        // Celebrate only on a today's-distance we FRESHLY fetched this session.
        // hasLoadedInitialData can flip true off a locked-device query that ERRORED
        // (see fetchTodaysDistance), leaving todaysDistance at the value init cached
        // from last night — which re-fired the "mile complete / streak safe" screen
        // and photo prompt for yesterday's already-posted mile every morning until a
        // second launch refreshed it. The onChange(of: hasFreshTodaysDistance) below
        // re-runs this once the real fetch lands.
        guard healthManager.hasFreshTodaysDistance else {
            print("[Dashboard] ⏳ Skipping celebration check - today's distance not freshly fetched yet")
            return
        }
        // Defer while the workout tracker covers the dashboard — the celebration
        // overlay lives on this view, so it would play hidden behind the cover.
        // The cover's onDismiss re-runs this check once the dashboard is visible.
        guard !showWorkoutView else {
            print("[Dashboard] ⏸️ Deferring celebration check — workout tracker is on screen")
            return
        }
        guard currentState.isCompleted,
              healthManager.todaysDistance > 0 else {
            return
        }

        // Already shown today → nothing to do.
        guard !celebrationManager.hasShownGoalCelebrationToday else {
            return
        }

        // Avoid stacking redundant streak fetches when several observers fire at once.
        guard !isPreparingGoalCelebration else { return }
        isPreparingGoalCelebration = true

        // Sample the workout count NOW (goal-completion time) as the extra-mile
        // baseline, before the await below — a workout finishing during the fetch
        // must still count as an "extra mile", not silently raise the baseline past
        // itself and get skipped. Floor at 1 so the goal-completing effort always
        // counts even when today's distance came from a non-workout source.
        let goalCompletionWorkoutCount = max(healthManager.todaysWorkoutCount, 1)

        Task { @MainActor in
            defer { isPreparingGoalCelebration = false }

            // Pull the freshest streak before building the celebration. On cold launch
            // the cached streak hasn't yet counted today's mile, so without this the
            // counter shows a day stale (the value a manual refresh later corrects).
            await refreshStreakFromBackendForCelebration()

            // Re-validate after the await — state may have changed, or another trigger
            // may have shown the celebration while we were fetching.
            guard currentState.isCompleted,
                  healthManager.todaysDistance > 0,
                  !celebrationManager.hasShownGoalCelebrationToday else {
                return
            }

            // Baseline for extra-mile detection = workout count at goal completion.
            // Scoped to today (see CelebrationManager.lastPostGoalWorkoutCount) so it
            // neither suppresses tomorrow's extra mile nor spuriously fires on reopen.
            celebrationManager.lastPostGoalWorkoutCount = goalCompletionWorkoutCount

            print("[Dashboard] 🎉 Goal completion detected! Distance: \(healthManager.todaysDistance), Goal: \(userManager.currentUser.goalMiles)")
            let completionStats = buildGoalCompletionStats()
            celebrationManager.addCelebration(.goalCompleted(stats: completionStats))
            // Right after the fire/streak screen: show where you land on today's
            // friends leaderboard, animating your climb (Duolingo-style).
            celebrationManager.addCelebration(.leaderboardMoveUp(stats: completionStats))

            // Finale: BeReal-style "add a photo of your run" prompt for the mile
            // that just completed. Skipping still shares the run (route/stats).
            // Prefer the freshly-finished workout from `todaysWorkouts` (the same
            // source the extra-mile triggers and workout count read) over
            // WorkoutIndex.latestWorkoutUUID, whose incremental rebuild lags a
            // just-synced Watch run by a beat. Reading the stale index uuid here
            // reopened the SAME fresh window (no-op) and the per-uuid prompt
            // dedup swallowed the new walk's photo prompt — the "it never
            // re-prompted me at the end of this other walk" bug.
            let latestHK = healthManager.todaysWorkouts.first
            if let uuid = latestHK?.uuid.uuidString ?? healthManager.workoutIndex?.latestWorkoutUUID {
                // Open the 10-min fresh-post window on the goal-completing run
                // regardless of the auto-share prompt, so the feed countdown /
                // ring and "Fresh" reward work even when auto-share is off.
                FreshPostWindowManager.shared.open(workoutId: uuid)
                if autoShareRunsToFeed {
                    let hk = latestHK ?? healthManager.todaysWorkouts.first { $0.uuid.uuidString == uuid }
                    let wtype = hk?.workoutActivityType == .walking ? "walking" : "running"
                    celebrationManager.addCelebration(.postRunPhotoPrompt(workoutId: uuid, workoutType: wtype))
                }
            }
        }
    }

    /// Show encouragement when the user completes additional workouts after reaching their goal.
    /// Uses workout count to ensure it only fires when a new workout finishes (not mid-workout).
    private func checkAndShowPostGoalEncouragement() {
        // Same deferral as the goal celebration: don't play it behind the cover.
        guard !showWorkoutView,
              currentState.isCompleted,
              celebrationManager.hasShownGoalCelebrationToday,
              healthManager.todaysDistance > 0,
              healthManager.todaysWorkoutCount > celebrationManager.lastPostGoalWorkoutCount else {
            return
        }

        celebrationManager.lastPostGoalWorkoutCount = healthManager.todaysWorkoutCount
        let stats = buildGoalCompletionStats()
        // Every extra run/walk also re-runs the today's-miles leaderboard so you
        // see yourself climb with the added miles, then the extra-mile hype.
        celebrationManager.addCelebration(.leaderboardMoveUp(stats: stats))
        celebrationManager.addCelebration(.postGoalWorkout(stats: stats))

        // Every walk/run gets its own photo moment, not just the goal-crossing
        // one — same finale as the goal path. The celebration id is keyed by
        // workout uuid, so each new workout prompts exactly once.
        // Same fix as the goal-completion path: key the window + prompt off the
        // freshly-finished workout from `todaysWorkouts`, not the possibly-stale
        // WorkoutIndex uuid, so each extra walk/run actually earns its own
        // window + photo prompt instead of being deduped against the last one.
        let latestHK = healthManager.todaysWorkouts.first
        if let uuid = latestHK?.uuid.uuidString ?? healthManager.workoutIndex?.latestWorkoutUUID {
            // Each extra qualifying walk/run reopens a fresh 10-min window (a
            // new uuid resets it), regardless of the auto-share prompt.
            FreshPostWindowManager.shared.open(workoutId: uuid)
            if autoShareRunsToFeed {
                let hk = latestHK ?? healthManager.todaysWorkouts.first { $0.uuid.uuidString == uuid }
                let wtype = hk?.workoutActivityType == .walking ? "walking" : "running"
                celebrationManager.addCelebration(.postRunPhotoPrompt(workoutId: uuid, workoutType: wtype))
            }
        }
    }

    // Simplified state calculation
    private var currentState: (distance: Double, goal: Double, progress: Double, isCompleted: Bool) {
        let distance = healthManager.todaysDistance
        let goal = userManager.currentUser.goalMiles
        let progress = ProgressCalculator.calculateProgress(current: distance, goal: goal)
        let isCompleted = ProgressCalculator.isGoalCompleted(current: distance, goal: goal)

        return (distance, goal, progress, isCompleted)
    }

    /// Latest persisted in‑progress workout snapshot, if any.
    private var inProgressState: InProgressWorkoutState? {
        InProgressWorkoutStore.load()
    }

    var body: some View {
        // iOS 26: Simple ScrollView with background - no ZStack needed
        // NavigationStack is provided by MainTabView
        VStack(spacing: 0) {
            MADTabHeader(
                title: "Mile A Day",
                actions: dashboardHeaderActions
            )

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    // HealthKit permission gate — without auth, today's
                    // distance never loads and the app silently looks broken.
                    if !healthManager.isAuthorized {
                        healthKitDisabledBanner
                            .padding(.horizontal, MADTheme.Spacing.md)
                            .padding(.top, MADTheme.Spacing.md)
                    }

                    // Replay celebration card — only when today's mile is
                    // done and the celebration isn't currently on screen.
                    if currentState.isCompleted
                        && celebrationManager.hasShownGoalCelebrationToday
                        && !celebrationManager.isShowingCelebration {
                        replayTodaysCelebrationCard
                            .padding(.horizontal, MADTheme.Spacing.md)
                            .padding(.top, MADTheme.Spacing.sm)
                    }

                    // "Photo waiting" nudge — a mid-run snap is held but the
                    // goal isn't done yet. It does NOT unlock posting (the goal
                    // gate stands); it reassures the user the shot is kept and
                    // will be offered once they finish the mile.
                    if midRunPhotoWaiting {
                        photoWaitingBanner
                            .padding(.horizontal, MADTheme.Spacing.md)
                            .padding(.top, MADTheme.Spacing.sm)
                    }

                    // Week view: user can toggle between chart and dots
                    weekViewSection
                        .padding(.top, 8)
                        .padding(.bottom, 8)

                    dashboardContent
                        .frame(maxWidth: .infinity)
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollContentBackground(.hidden)
            .refreshable {
                await refreshDataAsync()
            }
            // Pin VStack width to the ScrollView so a child with intrinsic
            // width > screen (long names, wide rows) can't push the page
            // sideways and create horizontal overscroll.
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(MADTheme.Colors.appBackgroundGradient)
        // First-run welcome tour — a full-screen, paged walkthrough of every
        // feature and mode. Replaces the old spotlight overlay, which
        // mis-highlighted dashboard elements that were scrolled off-screen.
        .fullScreenCover(isPresented: $showWelcomeTour) {
            WelcomeTourView {
                showWelcomeTour = false
                hasSeenWelcomeTour = true
                // Completing the tour supersedes the welcome banner.
                hasSeenInstructions = true
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showNotificationInbox) {
            NotificationInboxView(competitionService: competitionService) { newCount in
                unreadNotificationCount = newCount
            }
        }
        .navigationDestination(isPresented: $showDashboardSettings) {
            DashboardSettingsView(
                userManager: userManager,
                currentGoal: userManager.currentUser.goalMiles,
                onSetGoal: { showGoalSheet = true }
            )
        }
        .navigationDestination(isPresented: $showWorkouts) {
            WorkoutsView(healthManager: healthManager)
        }
            .sheet(isPresented: $showManualWorkoutEntry) {
                ManualWorkoutEntryView()
            }
            // Always surface an in‑progress workout as the primary experience.
            .fullScreenCover(isPresented: $showWorkoutView, onDismiss: {
                // When the user dismisses the workout tracker while a workout is still active,
                // show a compact banner so they can easily resume.
                let hasActive = InProgressWorkoutStore.load()?.isActive == true
                hasActiveWorkout = hasActive
                showInProgressBanner = hasActive

                // Surface any celebration earned during the workout now that the
                // dashboard is visible again (checks are deferred while covered):
                // goal completion first, then the extra-mile encouragement.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    checkAndShowGoalCelebration()
                    checkAndShowPostGoalEncouragement()
                }
                // A workout just finished/synced — refresh ask-mode pendings.
                loadPendingNotifications()
                // A mid-run snap may have been taken (or the goal met) — refresh
                // the "photo waiting" nudge.
                refreshMidRunPhotoWaiting()
            }) {
                // One WorkoutTrackingView with stable structural identity. This was
                // an if/else between two WorkoutTrackingView initializers — when the
                // workout finished, finishCleanup() cleared the persisted state, the
                // branch flipped, and SwiftUI rebuilt the tracker from scratch: all
                // @State (including showRecap) was lost and the user landed back on
                // the activity-selection screen instead of the workout recap.
                let saved = InProgressWorkoutStore.load()
                let activeState = (saved?.isActive == true) ? saved : nil
                WorkoutTrackingView(
                    healthManager: healthManager,
                    userManager: userManager,
                    goalDistance: activeState?.goalDistance ?? currentState.goal,
                    startingDistance: activeState?.startingDistance ?? currentState.distance
                )
            }
            .onAppear {
                refreshData()
                refreshMidRunPhotoWaiting()
                // Sync widget data immediately
                syncWidgetData()
                // Load ask-mode pending notifications (cheap-guarded on settings).
                loadPendingNotifications()

                // Fetch fastest mile pace from backend database
                fetchFastestPaceFromBackend()

                // Goal celebration is now triggered by .onChange(of: healthManager.hasLoadedInitialData)
                // which fires when both today's distance and workout index have loaded

                // If there is a persisted in‑progress workout when the dashboard appears,
                // automatically surface it so the user can't "lose" their active workout.
                // Cache the flag so view bodies don't re-decode the (potentially large)
                // persisted workout JSON on every render.
                let active = InProgressWorkoutStore.load()?.isActive == true
                hasActiveWorkout = active
                if active {
                    showWorkoutView = true
                }

                // First-run welcome tour: wait a beat for layout to settle, and
                // stand down if a celebration or the workout tracker is on
                // screen — the flag stays unset so the tour tries again next
                // visit.
                if !hasSeenWelcomeTour {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        if !hasSeenWelcomeTour,
                           !celebrationManager.isShowingCelebration,
                           !showWorkoutView {
                            showWelcomeTour = true
                        }
                    }
                }
            }
            // Self-cleaning replacements for the old NotificationCenter.addObserver
            // calls in onAppear — those registered a fresh observer on every
            // appearance and never removed them, so each event re-ran the handler
            // (and reloaded widgets) once per past dashboard visit.
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("WorkoutIndexReady"))) { _ in
                print("[Dashboard] 🔔 Workout index ready, updating user data and syncing widgets")
                applyHealthDataToUserManager()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MAD_OpenWorkoutFromLiveActivity"))) { _ in
                showWorkoutView = true
            }
            .sheet(isPresented: $showGoalSheet) {
                GoalSettingSheet(
                    currentGoal: userManager.currentUser.goalMiles,
                    onSave: { newGoal in
                        userManager.setDailyGoal(miles: newGoal)
                        syncWidgetData()
                    }
                )
                .presentationDetents([.height(300)])
                    }
            .sheet(isPresented: $showPendingSheet) {
                PendingNotificationsSheet()
            }
            .alert("Workout Upload", isPresented: $showWorkoutUploadAlert) {
                Button("OK") { }
            } message: {
                if let status = workoutService.lastUploadStatus {
                    Text(status)
                } else if let error = workoutService.errorMessage {
                    Text("Error: \(error)")
                } else {
                    Text("Upload completed")
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    celebrationManager.onAppBecameActive()
                    // Re-check celebrations in case data changed while backgrounded
                    checkAndShowGoalCelebration()
                    // Pick up ask-mode pendings created while backgrounded.
                    loadPendingNotifications()
                    // A mid-run snap may have been taken in another surface.
                    refreshMidRunPhotoWaiting()
                } else if newPhase == .background || newPhase == .inactive {
                    celebrationManager.onAppResignedActive()
                }
            }
            .onChange(of: celebrationManager.isShowingCelebration) { wasShowing, isShowing in
                // When a celebration finishes, surface any leftover pendings the
                // embed didn't handle (other event types, or an un-acted mile).
                if wasShowing && !isShowing {
                    maybePresentPendingSheet()
                }
            }
            .onChange(of: healthManager.hasFreshTodaysDistance) { _, isFresh in
                // On a locked-device launch the initial fetch errors and the
                // celebration check bails; when the real fetch finally lands this
                // re-runs it against fresh data (fires a genuine completion, stays
                // silent for yesterday's already-handled mile).
                if isFresh { checkAndShowGoalCelebration() }
            }
            .onChange(of: healthManager.hasLoadedInitialData) { _, isLoaded in
                if isLoaded {
                    applyHealthDataToUserManager()
                    checkAndShowGoalCelebration()
                    // Defer checklist visibility until data has settled so
                    // established users never see a single-frame flash.
                    if !gettingStartedReady && !gettingStartedDismissed {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                gettingStartedReady = true
                            }
                        }
                    }
                }
            }
            .onChange(of: healthManager.retroactiveStreak) { _, _ in
                applyHealthDataToUserManager()
            }
            .onChange(of: currentState.isCompleted) { oldValue, newValue in
                if newValue && !oldValue {
                    triggerConfetti()
                    // Also check for goal celebration when completion status changes
                    checkAndShowGoalCelebration()
                }
                // Completing the goal clears the "photo waiting" state (the
                // post-run prompt now offers the snap directly).
                refreshMidRunPhotoWaiting()
            }
            .onChange(of: healthManager.todaysDistance) { oldValue, newValue in
                // Check for extra mile when distance increases after goal already celebrated
                if newValue > oldValue && newValue > 0 && celebrationManager.hasShownGoalCelebrationToday {
                    checkAndShowPostGoalEncouragement()
                }
            }
            .onChange(of: healthManager.todaysWorkouts.count) { oldValue, newValue in
                // When a new workout finishes (from Watch, Apple Workout, etc.), check for extra mile
                if newValue > oldValue && celebrationManager.hasShownGoalCelebrationToday {
                    checkAndShowPostGoalEncouragement()
                }
                // A workout finishing may leave a mid-run snap waiting.
                refreshMidRunPhotoWaiting()
            }
            .confetti(isShowing: $showConfetti)
            .overlay(
                CelebrationContainerView()
            )
            .navigationDestination(isPresented: $navigateToBadgesFromCelebration) {
                BadgesView(userManager: userManager, initialBadge: nil)
            }
            .onChange(of: celebrationManager.pendingAction) { _, newAction in
                if newAction == .viewBadges {
                    navigateToBadgesFromCelebration = true
                    celebrationManager.clearPendingAction()
                }
            }
    }

    private func syncWidgetData() {
        let state = currentState
        WidgetDataStore.save(todayMiles: state.distance, goal: state.goal)
        WidgetDataStore.save(streak: userManager.currentUser.streak)
        WidgetDataStore.save(weekCompletions: currentWeekCompletions(), weekMiles: currentWeekMiles())
        // No blanket reloadAllTimelines() here: the store reloads the right
        // widget kinds itself and skips no-op writes, which preserves the
        // per-day widget reload budget iOS enforces.
    }

    /// Sun–Sat goal-completion flags for the current week, for the medium
    /// streak widget's week-dots row.
    private func currentWeekCompletions() -> [Bool] {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        guard let startOfWeek = calendar.date(
            byAdding: .day, value: -(weekday - 1), to: calendar.startOfDay(for: today)
        ) else { return [] }

        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfWeek) else { return false }
            return healthManager.dailyMileGoals[calendar.startOfDay(for: day)] ?? false
        }
    }

    /// Total miles this week (Sun–today) from the local workout index, for
    /// the streak widget's status line.
    private func currentWeekMiles() -> Double {
        guard let index = healthManager.workoutIndex else { return 0 }
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        guard let startOfWeek = calendar.date(
            byAdding: .day, value: -(weekday - 1), to: calendar.startOfDay(for: today)
        ) else { return 0 }
        return index.workoutsByDate.values
            .flatMap { $0 }
            .filter { $0.localDate >= startOfWeek }
            .reduce(0) { $0 + $1.distance }
    }

    private func applyHealthDataToUserManager() {
        userManager.updateUserWithHealthKitData(
            retroactiveStreak: healthManager.retroactiveStreak,
            currentMiles: healthManager.todaysDistance,
            totalMiles: healthManager.totalLifetimeMiles,
            fastestPace: healthManager.fastestMilePace,
            mostMilesInDay: healthManager.mostMilesInOneDay
        )
        syncWidgetData()
    }

    private func refreshData() {
        isRefreshing = true
        healthManager.fetchAllWorkoutData()
        fetchFastestPaceFromBackend()
        // UI is driven by .onChange observers on healthManager — no artificial delay needed.
        // Apply whatever is already cached immediately; observers will re-fire as fresh data lands.
        applyHealthDataToUserManager()
        isRefreshing = false
    }

    private func refreshDataAsync() async {
        isRefreshing = true
        healthManager.fetchAllWorkoutData()
        fetchFastestPaceFromBackend()
        // The HealthKit fetches above are fire-and-forget; hold the
        // pull-to-refresh spinner briefly so fresh values have a chance to
        // land before it dismisses — previously it vanished instantly and
        // looked like the refresh did nothing.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        applyHealthDataToUserManager()
        isRefreshing = false
    }

    // MARK: - Ask-mode Pending Notifications

    /// Load ask-mode pending friend notifications, then maybe surface the stash
    /// sheet. Cheap-guarded: skips the network call entirely unless the user has
    /// at least one outgoing "ask" audience setting.
    private func loadPendingNotifications() {
        Task { @MainActor in
            await AudienceSettingsService.shared.loadIfNeeded()
            guard AudienceSettingsService.shared.hasAskSettings else { return }
            try? await pendingService.load()
            maybePresentPendingSheet()
        }
    }

    /// Present the standalone stash sheet when there are pendings the celebration
    /// embed won't handle. A fresh mile-only stash is left to the goal
    /// celebration (CelebrationManager owns presentation priority).
    private func maybePresentPendingSheet() {
        guard !pendingService.pending.isEmpty else { return }
        guard !celebrationManager.isShowingCelebration else { return }
        guard !showPendingSheet else { return }

        let onlyMile = pendingService.pending.allSatisfy {
            $0.eventType == AudienceEventType.mileCompleted.rawValue
        }
        // If the only pending is today's mile and the goal celebration hasn't run
        // yet, let the celebration's embed handle it instead of this sheet.
        if onlyMile && !celebrationManager.hasShownGoalCelebrationToday { return }

        showPendingSheet = true
    }

    /// Fetch fastest mile pace from backend database (authoritative source)
    private func fetchFastestPaceFromBackend() {
        guard let userId = UserDefaults.standard.string(forKey: "backendUserId") else { return }
        Task {
            do {
                let stats = try await workoutService.getUserStats(userId: userId)
                print("[Dashboard] 📡 Backend best_split_time = \(stats.bestSplitTimeSeconds?.description ?? "nil") sec/mi, streak = \(stats.streak)")
                await MainActor.run {
                    // Rescue the streak on first login / before HealthKit indexes locally.
                    // updateStreakFromBackend only raises the value, so it can't clobber a
                    // higher HealthKit-computed streak from a later refresh.
                    userManager.updateStreakFromBackend(stats.streak)
                    repairWorkoutIndexIfStale(backendStreak: stats.streak)
                    if let bestSplitSeconds = stats.bestSplitTimeSeconds, bestSplitSeconds > 0 {
                        let paceMinutesPerMile = bestSplitSeconds / 60.0
                        print("[Dashboard] ✅ Updating fastest pace from backend → \(paceMinutesPerMile) min/mi")
                        userManager.updateFastestPaceFromBackend(paceMinutesPerMile)
                    }
                }
            } catch {
                print("[Dashboard] ⚠️ Failed to fetch stats from backend: \(error)")
            }
        }
    }

    /// A backend streak ≥2 days ahead of the local HealthKit-derived one is the
    /// signature of a hole in the WorkoutIndex: a workout that reached HealthKit
    /// after the index's lastUpdated stamp was never indexed, so activeStreak()
    /// stops at that day. Every refresh then flashes the tiny local value (via
    /// applyHealthDataToUserManager's unconditional overwrite) before the backend
    /// rescue lands — "1 day streak" for a second, then the real number. Rebuild
    /// the index from full history to repair the hole; debounced to once per
    /// calendar day, and buildWorkoutIndex() itself no-ops while a build runs.
    private func repairWorkoutIndexIfStale(backendStreak: Int) {
        guard backendStreak > healthManager.retroactiveStreak + 1 else { return }
        let debounceKey = "lastStreakMismatchIndexRebuild"
        if let last = UserDefaults.standard.object(forKey: debounceKey) as? Date,
           Calendar.current.isDateInToday(last) { return }
        UserDefaults.standard.set(Date(), forKey: debounceKey)
        print("[Dashboard] 🔧 Backend streak \(backendStreak) ≫ local \(healthManager.retroactiveStreak) — rebuilding workout index to repair missed workouts")
        Task { await healthManager.buildWorkoutIndex() }
    }

    /// Pull the current streak from the backend (the authoritative source the manual
    /// refresh uses) and apply it before a streak celebration is built, so the counter
    /// isn't a day stale on cold launch. `updateStreakFromBackend` only raises the
    /// value, so a higher HealthKit-computed streak is never clobbered. Bounded by
    /// APIClient's 15s request timeout; on failure we fall back to the cached streak —
    /// no worse than before.
    @MainActor
    private func refreshStreakFromBackendForCelebration() async {
        guard let userId = UserDefaults.standard.string(forKey: "backendUserId") else { return }
        do {
            let stats = try await workoutService.getUserStats(userId: userId)
            print("[Dashboard] 🔄 Fresh streak for celebration = \(stats.streak)")
            userManager.updateStreakFromBackend(stats.streak)
        } catch {
            print("[Dashboard] ⚠️ Fresh streak fetch for celebration failed: \(error)")
        }
    }

    private func triggerConfetti() {
        showConfetti = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            showConfetti = false
        }
    }

    // MARK: - Workout Upload Test Functions
    private func uploadWorkouts() async {
        do {
            // Get recent workouts from HealthKit
            let workouts = healthManager.recentWorkouts

            if workouts.isEmpty {
                await MainActor.run {
                    workoutService.errorMessage = "No workouts found to upload"
                }
                return
            }

            // Upload workouts
            try await workoutService.uploadWorkouts(workouts)

            // Show success alert
            await MainActor.run {
                showWorkoutUploadAlert = true
            }

        } catch {
            await MainActor.run {
                workoutService.errorMessage = error.localizedDescription
            }
        }
    }

    private func uploadAllWorkouts() async {
        // Use WorkoutSyncService for batched upload with retry logic
        for await progress in syncService.performInitialSync() {
            if case .complete = progress.phase {
                await MainActor.run {
                    showWorkoutUploadAlert = true
                }
            } else if case .error(let message) = progress.phase {
                await MainActor.run {
                    workoutService.errorMessage = message
                }
            }
        }
    }

    // MARK: - Header Actions

    /// Curated 3-action header — bell (with unread count badge), + (manual
    /// workout), gear (goal/settings). Trophy / sparkles / admin / info
    /// were moved out of the header to match Friends/Compete/Profile (which
    /// each have 2-3 actions). Replay is now an inline card in the body
    /// when applicable; admin/info will get re-surfaced in Profile later.
    private var dashboardHeaderActions: [MADHeaderAction] {
        [
            MADHeaderAction(
                id: "bell",
                systemImage: "bell.fill",
                style: .notification(count: unreadNotificationCount)
            ) { showNotificationInbox = true },
            // `square.and.pencil` reads as "log/edit an entry" — distinct
            // from the Compete tab's `+` icon (which means "create a new
            // competition"). Both being plain `+` was confusing.
            MADHeaderAction(
                id: "add-workout",
                systemImage: "square.and.pencil",
                style: .cta
            ) { showManualWorkoutEntry = true },
            MADHeaderAction(
                id: "settings",
                systemImage: "gearshape.fill"
            ) { showDashboardSettings = true }
        ]
    }

    // MARK: - Replay Celebration Card

    /// Inline replacement for the old sparkles toolbar button. Only shown
    /// when today's goal has been completed and the celebration isn't
    /// currently on screen — sits right at the top of the dashboard content
    /// where the achievement is contextually relevant.
    private var replayTodaysCelebrationCard: some View {
        Button {
            replayTodaysCelebration()
        } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, MADTheme.Colors.madRed], startPoint: .top, endPoint: .bottom)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Replay today's celebration")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Re-watch or share your mile-a-day moment")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.yellow.opacity(0.4), MADTheme.Colors.madRed.opacity(0.3)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Nudge shown when a mid-run snap is waiting but today's goal isn't met.
    /// Tapping reopens the tracker so the user can finish their mile.
    private var photoWaitingBanner: some View {
        Button {
            showWorkoutView = true
        } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "camera.badge.clock")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, MADTheme.Colors.walkBlue], startPoint: .top, endPoint: .bottom)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Photo waiting")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Finish today's mile to share it")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .strokeBorder(MADTheme.Colors.walkBlue.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Cache whether a mid-run photo is waiting to be shared while today's goal
    /// is still unmet, so `photoWaitingBanner` never enumerates the sandbox dir
    /// from within `body`.
    private func refreshMidRunPhotoWaiting() {
        // Scope to snaps taken TODAY: a leftover from yesterday's workout (its
        // prompt never resolved, app reopened next day) must not nag "finish
        // today's mile to share it" against a fresh, untouched day.
        midRunPhotoWaiting = !currentState.isCompleted && MidRunPhotoStash.hasEntriesToday()
    }

    // MARK: - HealthKit Permission Banner

    /// Shown when HealthKit is denied or hasn't been requested yet. Tapping
    /// re-prompts the system dialog; if the user previously declined, iOS
    /// silently no-ops the re-prompt so we also include a deep-link to the
    /// app's Settings page where they can flip the toggle manually.
    private var healthKitDisabledBanner: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.red, .pink], startPoint: .top, endPoint: .bottom)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Apple Health")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Mile A Day needs Health access to count today's miles.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    healthManager.requestAuthorization { _ in }
                } label: {
                    Text("Continue")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                }
                .buttonStyle(.plain)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Week View (Chart or Dots toggle)

    @ViewBuilder
    private var weekViewSection: some View {
        VStack(spacing: 10) {
            // Segmented tab picker
            weekViewPicker

            // Content for selected tab
            if weekViewStyle == "chart" {
                WeeklyMileChartView(
                    healthManager: healthManager,
                    userManager: userManager
                )
                .padding(.horizontal, 16)
            } else if weekViewStyle == "trends" {
                WeeklyTrendCard(healthManager: healthManager, userManager: userManager)
                    .padding(.horizontal, 16)
            } else {
                streakSection
                    .padding(.horizontal, 16)
            }
        }
    }

    private var weekViewPicker: some View {
        let tabs: [(id: String, label: String, icon: String)] = [
            ("streak", "Streak", "flame.fill"),
            ("chart", "This Week", "chart.xyaxis.line"),
            ("trends", "Trends", "chart.line.uptrend.xyaxis"),
        ]

        return HStack(spacing: 4) {
            ForEach(tabs, id: \.id) { tab in
                let isSelected = weekViewStyle == tab.id
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        weekViewStyle = tab.id
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(tab.label)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.15) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Extracted dashboard sections to help Swift type‑check

    @ViewBuilder
    private var dashboardContent: some View {
        VStack(spacing: 16) {
            inProgressBannerSection
            competitionInvitesSection
            instructionsSection
            gettingStartedSection
            todayProgressSection
            // Cross-comp rivalries — surface "you're X behind Y in [comp]"
            // hints from every active competition so users see all their
            // The competitions dropdown (activeCompetitionSection) replaces
            // the standalone "Close to Passing" tile — each comp card now
            // surfaces its own focus signal, so a separate rivalries section
            // would just duplicate information.
            dailyChallengeSection
            friendActivitySection
            activeCompetitionSection
            stepsAndBadgesSection
            statsAndHistorySection
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 100) // Extra padding for tab bar
        .clipped() // Prevent content overflow from causing horizontal jitter
    }


    @ViewBuilder
    private var inProgressBannerSection: some View {
        if showInProgressBanner, let state = inProgressState, state.isActive {
            InProgressWorkoutBanner(
                state: state,
                onResume: {
                    // Re‑open the full‑screen workout tracker
                    showInProgressBanner = false
                    showWorkoutView = true
                }
            )
            .onLongPressGesture(minimumDuration: 2.0) {
                showForceResetAlert = true
            }
            .alert("Force Reset Workout?", isPresented: $showForceResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    // End any Live Activities
                    Task {
                        for activity in Activity<WorkoutActivityAttributes>.activities {
                            await activity.end(nil, dismissalPolicy: .immediate)
                        }
                    }
                    InProgressWorkoutStore.clear()
                    showInProgressBanner = false
                }
            } message: {
                Text("This will discard the stuck workout and clear all workout state. Use this if the workout is frozen or won't end properly.")
            }
        }
    }

    private var instructionsSection: some View {
        InstructionsBanner(onTakeTour: { showWelcomeTour = true })
    }

    // MARK: - Getting Started Checklist

    private var gettingStartedItems: [GettingStartedChecklistCard.Item] {
        [
            GettingStartedChecklistCard.Item(
                id: "first-mile",
                icon: "figure.run",
                title: "Do your first mile",
                subtitle: "Run or walk it — any workout counts",
                isDone: healthManager.totalLifetimeMiles >= 0.95
                    || userManager.currentUser.streak > 0
                    || currentState.isCompleted,
                action: { showWorkoutView = true }
            ),
            GettingStartedChecklistCard.Item(
                id: "add-friend",
                icon: "person.badge.plus",
                title: "Add your first friend",
                subtitle: "Streaks are easier together",
                isDone: !friendService.friends.isEmpty,
                action: {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MAD_SwitchTab"),
                        object: nil,
                        userInfo: ["tab": 3]
                    )
                }
            ),
            GettingStartedChecklistCard.Item(
                id: "first-medal",
                icon: "medal.fill",
                title: "Earn your first medal",
                subtitle: "Your first mile unlocks one",
                isDone: userManager.currentUser.badges.contains { !$0.isLocked },
                action: { navigateToBadgesFromCelebration = true }
            ),
            GettingStartedChecklistCard.Item(
                id: "join-competition",
                icon: "trophy.fill",
                title: "Join a competition",
                subtitle: "Challenge a friend to keep you honest",
                isDone: !competitionService.competitions.isEmpty,
                action: {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MAD_SwitchTab"),
                        object: nil,
                        userInfo: ["tab": 1]
                    )
                }
            )
        ]
    }

    @ViewBuilder
    private var gettingStartedSection: some View {
        // Hidden until `gettingStartedReady` flips — prevents a single-frame
        // flash for established users whose async data hasn't arrived yet.
        if gettingStartedReady, !gettingStartedDismissed {
            let items = gettingStartedItems
            if items.contains(where: { !$0.isDone }) {
                GettingStartedChecklistCard(items: items) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        gettingStartedDismissed = true
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var streakSection: some View {
        StreakCard(
            streak: userManager.currentUser.streak,
            isActiveToday: userManager.currentUser.isStreakActiveToday,
            isAtRisk: userManager.currentUser.isStreakAtRisk,
            user: userManager.currentUser,
            progress: currentState.progress,
            isGoalCompleted: currentState.isCompleted,
            isRefreshing: isRefreshing,
            currentDistance: currentState.distance,
            fastestPace: userManager.currentUser.fastestMilePace,
            mostMiles: healthManager.cachedCurrentStreakStats.mostMiles > 0 ? healthManager.cachedCurrentStreakStats.mostMiles : healthManager.mostMilesInOneDay,
            totalMiles: healthManager.totalLifetimeMiles,
            healthManager: healthManager,
            userManager: userManager
        )
    }

    private var todayProgressSection: some View {
        TodayProgressCard(
            currentDistance: currentState.distance,
            goalDistance: currentState.goal,
            progress: currentState.progress,
            didComplete: currentState.isCompleted,
            onRefresh: refreshData,
            isRefreshing: isRefreshing,
            user: userManager.currentUser,
            fastestPace: userManager.currentUser.fastestMilePace,
            mostMiles: healthManager.mostMilesInOneDay,
            totalMiles: healthManager.totalLifetimeMiles,
            hasActiveWorkout: hasActiveWorkout,
            healthManager: healthManager,
            userManager: userManager,
            showWorkoutView: $showWorkoutView
        )
    }

    // MARK: - Daily Challenge Section

    private var dailyChallengeSection: some View {
        NavigationLink {
            DailyChallengesView(healthManager: healthManager, userManager: userManager)
        } label: {
            DailyChallengeCard(healthManager: healthManager, userManager: userManager)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Friend Activity Section

    private var friendActivitySection: some View {
        FriendActivityStripView(friendService: friendService)
    }

    // MARK: - Competition Invites Section

    @ViewBuilder
    private var competitionInvitesSection: some View {
        if !competitionService.invites.isEmpty {
            CompetitionInviteBanner(inviteCount: competitionService.invites.count)
        }
    }

    // MARK: - Active Competition Section
    /// Surfaces every active competition the user is in, sorted by "what
    /// needs your attention right now" — streak-at-risk and tight clash
    /// races bubble to the top, comfortable leads fall to the bottom. Each
    /// row is a rich focus card showing today's actionable status so the
    /// user can decide where to put their next mile without tapping in.
    ///
    /// Wrapped in the shared `DashboardCollapsibleSection` so users who
    /// don't want a tall comp stack on the dashboard can fold it away.
    /// Collapse state persists via @AppStorage.

    @ViewBuilder
    private var activeCompetitionSection: some View {
        let active = competitionService.competitions.filter { $0.status == .active }
        if !active.isEmpty {
            let backendUserId = UserDefaults.standard.string(forKey: "backendUserId")
            let sorted = active.sorted { a, b in
                let fa = TodayFocus.compute(for: a, currentUserId: backendUserId)
                let fb = TodayFocus.compute(for: b, currentUserId: backendUserId)
                if fa.level.sortKey != fb.level.sortKey {
                    return fa.level.sortKey < fb.level.sortKey
                }
                // Tie-break: earlier-ending competition first (more time
                // pressure makes it more relevant today).
                let endA = a.endDateFormatted ?? .distantFuture
                let endB = b.endDateFormatted ?? .distantFuture
                return endA < endB
            }

            DashboardCollapsibleSection(
                title: sorted.count == 1
                    ? "Your Competitions"
                    : "Your Competitions (\(sorted.count))",
                icon: "trophy.fill",
                isCollapsed: $competitionsCollapsed,
                unified: true
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.competition_id) { index, comp in
                        ActiveCompetitionBannerCard(competition: comp, embedded: true)
                        if index < sorted.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 0.5)
                                .padding(.horizontal, 6)
                        }
                    }
                }
            }
        }
    }

    private var stepsAndBadgesSection: some View {
        VStack(spacing: 12) {
            CalendarPreviewCard(
                healthManager: healthManager,
                userManager: userManager
            )

            BadgesPreviewCard(
                userManager: userManager,
                healthManager: healthManager
            )
        }
    }

    private var statsAndHistorySection: some View {
        VStack(spacing: 12) {
            DashboardCollapsibleSection(title: "Your Stats", icon: "chart.bar.fill", isCollapsed: $statsCollapsed) {
                StatsGridView(user: userManager.currentUser, healthManager: healthManager)
            }

            // Recent Workouts now lives behind a clean preview card that opens
            // the full Workouts screen (calendar + history + swipeable detail).
            RecentWorkoutsPreviewCard(healthManager: healthManager, showWorkouts: $showWorkouts)
        }
    }
}
