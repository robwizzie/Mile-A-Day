import SwiftUI
import HealthKit
import UserNotifications

struct MainTabView: View {
    @Environment(\.appStateManager) var appStateManager
    @StateObject private var healthManager = HealthKitManager.shared
    @StateObject private var userManager = UserManager.shared
    @StateObject private var notificationService = MADNotificationService.shared
    @StateObject private var competitionService = CompetitionService()
    @StateObject private var friendService = FriendService()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var unreadNotificationCount = 0
    @State private var showNotificationInbox = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(
                    healthManager: healthManager,
                    userManager: userManager,
                    unreadNotificationCount: $unreadNotificationCount,
                    showNotificationInbox: $showNotificationInbox
                )
                    .environmentObject(notificationService)
                    .environmentObject(competitionService)
                    .environmentObject(friendService)
            }
            .tabItem {
                Label("Dashboard", systemImage: "house.fill")
            }
            .tag(0)

            NavigationStack {
                CompetitionsView(competitionService: competitionService)
            }
            .tabItem {
                Label("Compete", systemImage: "trophy.fill")
            }
            .tag(1)
            .badge(competitionService.invites.count)

            NavigationStack {
                FriendsListView(friendService: friendService)
            }
            .tabItem {
                Label("Friends", systemImage: "person.2.fill")
            }
            .tag(2)
            .badge(friendService.friendRequests.count)

            NavigationStack {
                ProfileView(userManager: userManager, healthManager: healthManager)
                    .environment(\.appStateManager, appStateManager)
            }
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
            .tag(3)
        }
        .tint(MADTheme.Colors.madRed)
        .safeAreaInset(edge: .bottom) {
            SyncStatusBanner()
        }
        .onAppear {
            initializeApp()
            handlePendingNotification()
            // Resume the initial workout sync if it never completed in a
            // previous session (e.g. user force-quit the app mid-upload).
            WorkoutSyncService.shared.startInitialSyncIfNeeded()
        }
        .task {
            await competitionService.refreshAllData()
            await friendService.refreshAllData()
            await refreshUnreadCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceivePushNotification)) { notification in
            guard let type = notification.userInfo?["type"] as? String else { return }
            Task {
                switch type {
                case "friend_request":
                    await friendService.refreshAllData()
                case "competition_invite":
                    await competitionService.refreshAllData()
                default:
                    break
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didTapPushNotification)) { notification in
            guard let type = notification.userInfo?["type"] as? String else { return }
            Task {
                switch type {
                case "friend_request", "friend_request_accepted":
                    await friendService.refreshAllData()
                    selectedTab = 2
                case "competition_invite", "competition_accepted", "competition_started",
                     "competition_finished", "competition_updates", "competition_nudge":
                    await competitionService.refreshAllData()
                    selectedTab = 1
                case "competition_flex", "competition_milestone", "friend_nudge",
                     "friend_activity", "streak_broken", "personal_best",
                     "lead_change", "clash_tie",
                     // badge_earned was previously unrouted — pushes landed
                     // silently. Route to Dashboard + open the inbox so the
                     // user actually sees the badge they earned.
                     "badge_earned", "friend_badge_earned",
                     "friend_challenge_completed", "friend_personal_best":
                    selectedTab = 0
                    showNotificationInbox = true
                default:
                    break
                }
                await refreshUnreadCount()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MAD_SwitchTab"))) { notification in
            if let tab = notification.userInfo?["tab"] as? Int {
                selectedTab = tab
            }
        }
        .onReceive(competitionService.$competitions) { competitions in
            syncCompetitionWidget(competitions)
        }
        .onChange(of: selectedTab) { _, newTab in
            // TabView keeps tab views alive, so their onAppear/.task don't re-fire
            // on tab switches — without this, Compete/Friends showed whatever was
            // fetched at launch until the app was backgrounded or killed. These
            // refreshes are silent: views keep content on screen while data swaps in.
            Task {
                switch newTab {
                case 1:
                    await competitionService.refreshAllData()
                case 2:
                    await friendService.refreshAllData()
                default:
                    break
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await competitionService.refreshAllData()
                    await friendService.refreshAllData()
                    await refreshUnreadCount()
                }
                // Refresh health data and re-evaluate the daily reminder
                // so "Mile still waiting" is cancelled if the user completed their mile
                healthManager.fetchTodaysDistance()
            }
        }
        .onChange(of: healthManager.todaysDistance) { _, newDistance in
            let isCompleted = newDistance >= userManager.currentUser.goalMiles
            notificationService.updateDailyReminder(
                isCompleted: isCompleted,
                currentMiles: newDistance,
                goalMiles: userManager.currentUser.goalMiles
            )
            // Keep widget data in sync so the willPresent check has fresh data
            WidgetDataStore.save(todayMiles: newDistance, goal: userManager.currentUser.goalMiles)
        }
    }

    // MARK: - Configuration

    private func initializeApp() {
        // One-time wipe of buggy v1 challenge data (pace predicate auto-completed on distance).
        ChallengeService.runLegacyCleanupIfNeeded(userManager: userManager)

        // Reset daily notification tracking for new day
        notificationService.resetDailyNotificationTracking()

        // Request HealthKit permissions when app launches
        healthManager.requestAuthorization { success in
            if success {
                healthManager.fetchAllWorkoutData()

                // Check for retroactive badges after data is loaded
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    userManager.checkForRetroactiveBadges()
                }
            }
        }

        // Request notification permissions and schedule smart daily reminder
        Task {
            await notificationService.requestAuthorization()

            // Use smart daily reminder with completion status
            let isCompleted = healthManager.todaysDistance >= userManager.currentUser.goalMiles
            notificationService.updateDailyReminder(
                isCompleted: isCompleted,
                currentMiles: healthManager.todaysDistance,
                goalMiles: userManager.currentUser.goalMiles
            )
        }

        // Sync widget data
        syncWidgetData()
    }

    private func handlePendingNotification() {
        guard let type = notificationService.pendingNotificationType else { return }
        // Mirror the live `.didTapPushNotification` handler so a cold-launch tap
        // routes to the same destination a warm tap would.
        //
        // NOTE: do NOT clear pendingNotificationType for friend_request /
        // competition_invite here — FriendsListView / CompetitionsListView read
        // the flag in their own `.task` to select the inner Requests/Invites
        // sub-tab, then clear it. Clearing it here would break that hand-off.
        Task {
            switch type {
            case "friend_request", "friend_request_accepted":
                await friendService.refreshAllData()
                selectedTab = 2
            case "competition_invite", "competition_accepted", "competition_started",
                 "competition_finished", "competition_updates", "competition_nudge":
                await competitionService.refreshAllData()
                selectedTab = 1
            case "competition_flex", "competition_milestone", "friend_nudge",
                 "friend_activity", "streak_broken", "personal_best",
                 "lead_change", "clash_tie":
                selectedTab = 0
                showNotificationInbox = true
                notificationService.pendingNotificationType = nil
            default:
                notificationService.pendingNotificationType = nil
            }
            await refreshUnreadCount()
        }
    }

    private func refreshUnreadCount() async {
        do {
            let count = try await friendService.getUnreadNotificationCount()
            await MainActor.run {
                unreadNotificationCount = count
            }
        } catch {
            // Silently fail
        }
    }

    private func syncWidgetData() {
        WidgetDataStore.save(todayMiles: healthManager.todaysDistance, goal: userManager.currentUser.goalMiles)
        WidgetDataStore.save(streak: userManager.currentUser.streak)
    }

    /// Mirror the most urgent active competition into the App Group for the
    /// Competition widget — same focus/sort logic as the dashboard cards.
    private func syncCompetitionWidget(_ competitions: [Competition]) {
        let active = competitions.filter { $0.status == .active }
        guard !active.isEmpty else {
            WidgetDataStore.clearCompetitionSummary()
            return
        }

        let userId = UserDefaults.standard.string(forKey: "backendUserId")
        guard let top = active.min(by: { a, b in
            TodayFocus.compute(for: a, currentUserId: userId).level.sortKey
                < TodayFocus.compute(for: b, currentUserId: userId).level.sortKey
        }) else { return }

        let focus = TodayFocus.compute(for: top, currentUserId: userId)

        let ranked = top.users
            .filter { $0.invite_status == .accepted }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        var rankText = ""
        if let uid = userId, let index = ranked.firstIndex(where: { $0.user_id == uid }) {
            let rank = index + 1
            let ordinal: String
            switch rank {
            case 1: ordinal = "1st"
            case 2: ordinal = "2nd"
            case 3: ordinal = "3rd"
            default: ordinal = "\(rank)th"
            }
            rankText = "\(ordinal) of \(ranked.count)"
        }

        let urgency: String
        switch focus.level {
        case .urgent: urgency = "urgent"
        case .behind: urgency = "behind"
        case .neutral: urgency = "neutral"
        case .winning: urgency = "winning"
        }

        WidgetDataStore.save(
            competitionId: top.competition_id,
            competitionName: top.competition_name,
            pill: focus.pill,
            detail: focus.detail,
            rankText: rankText,
            urgency: urgency
        )
    }
}

// MARK: - Stat Item (used by ProfileView)

struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    let iconColor: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    MainTabView()
}
