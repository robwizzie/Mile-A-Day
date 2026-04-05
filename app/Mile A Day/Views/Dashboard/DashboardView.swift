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
    @EnvironmentObject var notificationService: MADNotificationService
    @StateObject private var workoutService = WorkoutService()
    @StateObject private var syncService = WorkoutSyncService.shared

    @State private var showConfetti = false
    @State private var showGoalSheet = false
    @State private var newGoalMiles: Double = 1.0
    @State private var isRefreshing = false
    @State private var showInstructions = false
    @State private var showWorkoutUploadAlert = false
    @StateObject private var celebrationManager = CelebrationManager.shared
    /// Controls presentation of the in‑progress workout tracking UI.
    @State private var showWorkoutView = false
    /// Whether to show a compact "Resume workout" banner when an in‑progress workout exists
    /// but the full‑screen tracker is not currently visible.
    @State private var showInProgressBanner = false
    @State private var showForceResetAlert = false

    /// Controls presentation of the manual workout entry sheet.
    @State private var showManualWorkoutEntry = false

    /// User preference: "chart" (line chart) or "streak" (streak card)
    @AppStorage("weekViewStyle") private var weekViewStyle: String = "streak"

    /// Navigation state for badges view from celebration
    @State private var navigateToBadgesFromCelebration = false


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

    /// Build test stats for admin testing — uses real data if available, otherwise realistic placeholders
    private func buildTestGoalCompletionStats() -> GoalCompletionStats {
        let real = buildGoalCompletionStats()
        if real.todaysDistance > 0 { return real }
        return GoalCompletionStats(
            todaysDistance: 1.75,
            goalDistance: userManager.currentUser.goalMiles,
            currentStreak: max(userManager.currentUser.streak, 7),
            totalLifetimeMiles: max(healthManager.totalLifetimeMiles, 150),
            bestDayMiles: max(healthManager.cachedMostMilesInOneDay, 3.2),
            todaysAveragePace: 9.15,
            todaysFastestPace: 8.32,
            personalBestPace: 7.8,
            todaysTotalDuration: 1050,
            todaysCalories: 215,
            todaysWorkoutCount: 2,
            workoutBreakdowns: [
                WorkoutBreakdown(type: "running", distance: 1.25, duration: 750, displayName: "Run", icon: "figure.run"),
                WorkoutBreakdown(type: "walking", distance: 0.50, duration: 300, displayName: "Walk", icon: "figure.walk")
            ],
            latestWorkout: WorkoutBreakdown(type: "running", distance: 1.25, duration: 750, displayName: "Run", icon: "figure.run")
        )
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
        guard currentState.isCompleted,
              healthManager.todaysDistance > 0 else {
            return
        }

        let stats = buildGoalCompletionStats()

        // If goal celebration was already shown today, show post-goal encouragement instead
        if celebrationManager.hasShownGoalCelebrationToday {
            return
        }

        print("[Dashboard] 🎉 Goal completion detected! Distance: \(healthManager.todaysDistance), Goal: \(userManager.currentUser.goalMiles)")
        celebrationManager.addCelebration(.goalCompleted(stats: stats))
    }

    /// Show encouragement when the user completes additional workouts after reaching their goal.
    /// Uses workout count to ensure it only fires when a new workout finishes (not mid-workout).
    private func checkAndShowPostGoalEncouragement() {
        guard currentState.isCompleted,
              celebrationManager.hasShownGoalCelebrationToday,
              healthManager.todaysDistance > 0,
              healthManager.todaysWorkoutCount > celebrationManager.lastPostGoalWorkoutCount else {
            return
        }

        celebrationManager.lastPostGoalWorkoutCount = healthManager.todaysWorkoutCount
        let stats = buildGoalCompletionStats()
        celebrationManager.addCelebration(.postGoalWorkout(stats: stats))
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
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                // Week view: user can toggle between chart and dots
                weekViewSection
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                dashboardContent
                    .frame(maxWidth: .infinity)
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(MADTheme.Colors.appBackgroundGradient)
        .scrollContentBackground(.hidden)
        .refreshable {
            await refreshDataAsync()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Mile A Day")
        // iOS 26: Liquid Glass is automatic - no modifiers needed
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image("mad-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 28)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if userManager.hasNewBadges {
                    NavigationLink(destination: BadgesView(userManager: userManager, initialBadge: nil)) {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(.yellow)
                    }
                }

                // Admin celebration test menu
                if userManager.currentUser.role == "admin" {
                    Menu {
                        Button {
                            celebrationManager.resetDailyTracking()
                            celebrationManager.clearAll()
                            let stats = buildTestGoalCompletionStats()
                            celebrationManager.addCelebration(.goalCompleted(stats: stats))
                        } label: {
                            Label("Test Goal Completion", systemImage: "flame.fill")
                        }

                        Button {
                            celebrationManager.clearAll()
                            let stats = buildTestGoalCompletionStats()
                            celebrationManager.addCelebration(.postGoalWorkout(stats: stats))
                        } label: {
                            Label("Test Extra Mile", systemImage: "star.fill")
                        }

                        Button {
                            celebrationManager.clearAll()
                            if let badge = userManager.currentUser.badges.first {
                                celebrationManager.addCelebration(.badgeUnlocked(badge: badge))
                            }
                        } label: {
                            Label("Test Badge Unlock", systemImage: "trophy.fill")
                        }

                        Divider()

                        Button {
                            celebrationManager.resetDailyTracking()
                            celebrationManager.clearAll()
                            let stats = buildTestGoalCompletionStats()
                            celebrationManager.addCelebration(.goalCompleted(stats: stats))
                            celebrationManager.addCelebration(.postGoalWorkout(stats: stats))
                            if let badge = userManager.currentUser.badges.first {
                                celebrationManager.addCelebration(.badgeUnlocked(badge: badge))
                            }
                        } label: {
                            Label("Test All Celebrations", systemImage: "wand.and.stars")
                        }
                    } label: {
                        Image(systemName: "flask.fill")
                            .foregroundStyle(.purple)
                    }
                }

                Button {
                    showManualWorkoutEntry = true
                } label: {
                    Image(systemName: "plus.circle")
                }

                Button {
                    showInstructions = true
                } label: {
                    Image(systemName: "info.circle")
                }

                Button {
                    showGoalSheet = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
            .sheet(isPresented: $showManualWorkoutEntry) {
                ManualWorkoutEntryView()
            }
            // Always surface an in‑progress workout as the primary experience.
            .fullScreenCover(isPresented: $showWorkoutView, onDismiss: {
                // When the user dismisses the workout tracker while a workout is still active,
                // show a compact banner so they can easily resume.
                let hasActive = InProgressWorkoutStore.load()?.isActive == true
                showInProgressBanner = hasActive

                // If goal was already met, show encouragement for the extra effort
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    checkAndShowPostGoalEncouragement()
                }
            }) {
                if let state = InProgressWorkoutStore.load(), state.isActive {
                    WorkoutTrackingView(
                        healthManager: healthManager,
                        userManager: userManager,
                        goalDistance: state.goalDistance,
                        startingDistance: state.startingDistance
                    )
                } else {
                    WorkoutTrackingView(
                        healthManager: healthManager,
                        userManager: userManager,
                        goalDistance: currentState.goal,
                        startingDistance: currentState.distance
                    )
                }
            }
            .onAppear {
                refreshData()
                // Sync widget data immediately
                syncWidgetData()

                // PHASE 1: Listen for workout index completion
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("WorkoutIndexReady"),
                    object: nil,
                    queue: .main
                ) { [weak userManager, weak healthManager] _ in
                    guard let userManager = userManager, let healthManager = healthManager else { return }

                    print("[Dashboard] 🔔 Workout index ready, updating user data and syncing widgets")

                    // Update user manager with correct streak from index
                    userManager.updateUserWithHealthKitData(
                        retroactiveStreak: healthManager.retroactiveStreak,
                        currentMiles: healthManager.todaysDistance,
                        totalMiles: healthManager.totalLifetimeMiles,
                        fastestPace: healthManager.fastestMilePace,
                        mostMilesInDay: healthManager.mostMilesInOneDay
                    )

                    // Sync widgets with correct data
                    WidgetDataStore.save(todayMiles: healthManager.todaysDistance, goal: 1.0)
                    WidgetDataStore.save(streak: userManager.currentUser.streak)
                    WidgetCenter.shared.reloadAllTimelines()

                    print("[Dashboard] ✅ User data and widgets updated with streak: \(userManager.currentUser.streak)")
                }

                // Fetch fastest mile pace from backend database
                fetchFastestPaceFromBackend()

                // Goal celebration is now triggered by .onChange(of: healthManager.hasLoadedInitialData)
                // which fires when both today's distance and workout index have loaded

                // If there is a persisted in‑progress workout when the dashboard appears,
                // automatically surface it so the user can't "lose" their active workout.
                if let state = InProgressWorkoutStore.load(), state.isActive {
                    showWorkoutView = true
                }

                // Listen for Live Activity / deep‑link requests to open the workout.
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("MAD_OpenWorkoutFromLiveActivity"),
                    object: nil,
                    queue: .main
                ) { _ in
                    showWorkoutView = true
                }
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
            .sheet(isPresented: $showInstructions) {
                InstructionsView()
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
            .onChange(of: healthManager.hasLoadedInitialData) { _, isLoaded in
                if isLoaded {
                    checkAndShowGoalCelebration()
                }
            }
            .onChange(of: currentState.isCompleted) { oldValue, newValue in
                if newValue && !oldValue {
                    triggerConfetti()
                    // Also check for goal celebration when completion status changes
                    checkAndShowGoalCelebration()
                }
            }
            .onChange(of: healthManager.todaysDistance) { oldValue, newValue in
                // Check for goal completion when distance updates (e.g., after data loads)
                if newValue > oldValue && newValue > 0 {
                    checkAndShowGoalCelebration()
                    // Also check for extra mile when distance increases after goal already celebrated
                    if celebrationManager.hasShownGoalCelebrationToday {
                        checkAndShowPostGoalEncouragement()
                    }
                }
            }
            .onChange(of: healthManager.todaysWorkouts.count) { oldValue, newValue in
                // When a new workout finishes (from Watch, Apple Workout, etc.), check for extra mile
                if newValue > oldValue && celebrationManager.hasShownGoalCelebrationToday {
                    checkAndShowPostGoalEncouragement()
                }
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

        // Force widget updates
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refreshData() {
        isRefreshing = true

        // Fetch data in order to ensure consistency
        healthManager.fetchAllWorkoutData()

        // Refresh fastest pace from backend
        fetchFastestPaceFromBackend()

        // Use Task for better performance than DispatchQueue
        Task { @MainActor in
            // Reduced delay for faster UI responsiveness (from 2.5s to 1s)
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            // Update user manager with fresh HealthKit data
            userManager.updateUserWithHealthKitData(
                retroactiveStreak: healthManager.retroactiveStreak,
                currentMiles: healthManager.todaysDistance,
                totalMiles: healthManager.totalLifetimeMiles,
                fastestPace: healthManager.fastestMilePace,
                mostMilesInDay: healthManager.mostMilesInOneDay
            )

            syncWidgetData()

            // Shorter additional delay (from 3s total to 1.5s total)
            try? await Task.sleep(nanoseconds: 500_000_000)
            syncWidgetData()
            isRefreshing = false
        }
    }

    private func refreshDataAsync() async {
        isRefreshing = true
        healthManager.fetchAllWorkoutData()

        // Refresh fastest pace from backend
        fetchFastestPaceFromBackend()

        // Reduced delay for faster UI responsiveness (from 2.5s to 1s)
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Update user manager with fresh HealthKit data
        userManager.updateUserWithHealthKitData(
            retroactiveStreak: healthManager.retroactiveStreak,
            currentMiles: healthManager.todaysDistance,
            totalMiles: healthManager.totalLifetimeMiles,
            fastestPace: healthManager.fastestMilePace,
            mostMilesInDay: healthManager.mostMilesInOneDay
        )

        syncWidgetData()

        // Shorter additional delay (from 3s total to 1.5s total)
        try? await Task.sleep(nanoseconds: 500_000_000)
        syncWidgetData()
        isRefreshing = false
    }

    /// Fetch fastest mile pace from backend database (authoritative source)
    private func fetchFastestPaceFromBackend() {
        guard let userId = UserDefaults.standard.string(forKey: "backendUserId") else { return }
        Task {
            do {
                let stats = try await workoutService.getUserStats(userId: userId)
                if let bestSplitSeconds = stats.bestSplitTimeSeconds, bestSplitSeconds > 0 {
                    let paceMinutesPerMile = bestSplitSeconds / 60.0
                    await MainActor.run {
                        userManager.updateFastestPaceFromBackend(paceMinutesPerMile)
                    }
                }
            } catch {
                print("[Dashboard] ⚠️ Failed to fetch stats from backend: \(error)")
            }
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
            instructionsSection
            todayProgressSection
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
        InstructionsBanner(
            showInstructions: $showInstructions
        )
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
            healthManager: healthManager,
            userManager: userManager,
            showWorkoutView: $showWorkoutView
        )
    }

    private var stepsAndBadgesSection: some View {
        VStack(spacing: 12) {
            CalendarPreviewCard(
                healthManager: healthManager,
                userManager: userManager
            )

            BadgesPreviewCard(
                userManager: userManager
            )
        }
    }

    private var statsAndHistorySection: some View {
        VStack(spacing: 12) {
            StatsGridView(user: userManager.currentUser, healthManager: healthManager)

            RecentWorkoutsView(workouts: healthManager.recentWorkouts)
        }
    }
}
