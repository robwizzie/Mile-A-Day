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

    // App-wide "workout in progress" banner — tracking now runs in a shared
    // singleton, so we surface a live, tappable banner above the tab bar on
    // every tab (except Dashboard, which has its own inline banner) so users
    // never lose where their walk/run is.
    @StateObject private var trackingManager = WorkoutLocationManager.shared
    @State private var activeWorkoutForBanner: InProgressWorkoutState?
    @State private var showGuidedTour = false

    var body: some View {
        ZStack(alignment: .bottom) {
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
                SocialFeedView()
            }
            .tabItem {
                Label("Feed", systemImage: "square.stack.fill")
            }
            .tag(2)

            NavigationStack {
                FriendsListView(friendService: friendService)
            }
            .tabItem {
                Label("Friends", systemImage: "person.2.fill")
            }
            .tag(3)
            .badge(friendService.friendRequests.count)

            NavigationStack {
                ProfileView(userManager: userManager, healthManager: healthManager)
                    .environment(\.appStateManager, appStateManager)
            }
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
            .tag(4)
        }
        .tint(MADTheme.Colors.madRed)
        .safeAreaInset(edge: .bottom) {
            SyncStatusBanner()
        }
        .overlay(alignment: .top) {
            // Foreground notification banner — floats above all tabs/nav bars.
            InAppNotificationBanner()
                .padding(.top, 4)
        }
        .onChange(of: trackingManager.isTracking) { _, tracking in
            activeWorkoutForBanner = tracking ? InProgressWorkoutStore.load() : nil
        }
        .onAppear {
            initializeApp()
            handlePendingNotification()
            // Resume the initial workout sync if it never completed in a
            // previous session (e.g. user force-quit the app mid-upload).
            WorkoutSyncService.shared.startInitialSyncIfNeeded()
        }
        .task {
            // Cold launch from a profile universal link: the onOpenURL
            // MAD_SwitchTab post fired before this view existed, so read the
            // parked deep link directly. FriendsListView resolves + presents.
            if DeepLinkRouter.shared.pendingProfileUsername != nil {
                selectedTab = 3
            }
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
                    selectedTab = 3
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
                     // challenge_won = the overnight Head-to-Head verdict; the
                     // completion already sits in the history by the time the
                     // push arrives, so Dashboard + inbox shows the full story.
                     "challenge_won",
                     // Post/story pushes carry no payload data through the
                     // cold path, so land in the inbox — its row tap then
                     // deep-links to the exact post/story.
                     "friend_post", "story_reaction",
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
                case 3:
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
                    await syncLeaderboardWidget()
                }
                // Refresh health data and re-evaluate the daily reminder
                // so "Mile still waiting" is cancelled if the user completed their mile
                healthManager.fetchTodaysDistance()
            }
        }
        .onChange(of: healthManager.todaysDistance) { _, newDistance in
            let isCompleted = ProgressCalculator.isGoalCompleted(
                current: newDistance, goal: userManager.currentUser.goalMiles)
            notificationService.updateDailyReminder(
                isCompleted: isCompleted,
                currentMiles: newDistance,
                goalMiles: userManager.currentUser.goalMiles
            )
            // Keep widget data in sync so the willPresent check has fresh data
            WidgetDataStore.save(todayMiles: newDistance, goal: userManager.currentUser.goalMiles)
        }

            // Floating in-app workout banner — sits ABOVE the tab bar instead of
            // over it. (safeAreaInset on a TabView renders on top of the bar, so
            // it covered the tab buttons.) Padded up by ~one tab-bar height; the
            // home indicator is handled by the safe area.
            if trackingManager.isTracking, selectedTab != 0, let state = activeWorkoutForBanner {
                InProgressWorkoutBanner(state: state) {
                    // Reuse the Dashboard's resume path so starting/goal
                    // distance are computed correctly.
                    selectedTab = 0
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MAD_OpenWorkoutFromLiveActivity"),
                        object: nil
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 52)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Guided app tour overlay — sits above everything, switches
            // tabs underneath, and shows coach-mark cards.
            if showGuidedTour {
                AppGuidedTourView {
                    withAnimation(.easeOut(duration: 0.25)) {
                        showGuidedTour = false
                    }
                }
                .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MAD_StartGuidedTour"))) { _ in
            withAnimation(.easeIn(duration: 0.25)) {
                showGuidedTour = true
            }
        }
        .animation(.easeInOut(duration: 0.25), value: trackingManager.isTracking)
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
            let isCompleted = ProgressCalculator.isGoalCompleted(
                current: healthManager.todaysDistance, goal: userManager.currentUser.goalMiles)
            notificationService.updateDailyReminder(
                isCompleted: isCompleted,
                currentMiles: healthManager.todaysDistance,
                goalMiles: userManager.currentUser.goalMiles
            )
        }

        // Sync widget data
        syncWidgetData()
        Task { await syncLeaderboardWidget() }
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
                selectedTab = 3
            case "competition_invite", "competition_accepted", "competition_started",
                 "competition_finished", "competition_updates", "competition_nudge":
                await competitionService.refreshAllData()
                selectedTab = 1
            case "competition_flex", "competition_milestone", "friend_nudge",
                 "friend_activity", "streak_broken", "personal_best",
                 "lead_change", "clash_tie",
                 "friend_post", "story_reaction":
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

        // Top players (me always included) as a mini-leaderboard for the
        // widget — same score grammar as the in-app competition rows.
        func scoreText(_ user: CompetitionUser) -> String {
            let score = user.score ?? 0
            switch top.type {
            case .streaks:
                return "\(Int(score))d"
            case .apex, .race:
                return String(format: "%.1f %@", score, top.options.unit.shortDisplayName)
            case .targets, .clash:
                return "\(Int(score)) pt\(Int(score) == 1 ? "" : "s")"
            }
        }
        var standings: [WidgetDataStore.StandingRow] = ranked.prefix(3).map { user in
            WidgetDataStore.StandingRow(
                name: user.displayName,
                valueText: scoreText(user),
                isMe: user.user_id == userId
            )
        }
        if let uid = userId,
           !standings.contains(where: { $0.isMe }),
           let me = ranked.first(where: { $0.user_id == uid }) {
            standings[standings.count - 1] = WidgetDataStore.StandingRow(
                name: me.displayName, valueText: scoreText(me), isMe: true
            )
        }

        WidgetDataStore.save(
            competitionId: top.competition_id,
            competitionName: top.competition_name,
            pill: focus.pill,
            detail: focus.detail,
            rankText: rankText,
            urgency: urgency,
            standings: standings
        )
    }

    /// Mirror today's friends leaderboard into the App Group for the Daily
    /// Leaderboard widget — the same standings the post-mile celebration
    /// shows. Failed fetches keep the last good snapshot.
    private func syncLeaderboardWidget() async {
        let myId = UserDefaults.standard.string(forKey: "backendUserId")
        guard myId != nil else { return }
        guard let items = try? await friendService.fetchFriendsActivityToday() else { return }

        var rows: [WidgetDataStore.LeaderboardRow] = items
            .filter { $0.user_id != myId }
            .map {
                WidgetDataStore.LeaderboardRow(
                    name: $0.displayName,
                    miles: $0.today_miles,
                    isMe: false,
                    completed: $0.completed_today
                )
            }
        let user = userManager.currentUser
        rows.append(WidgetDataStore.LeaderboardRow(
            name: user.username ?? user.name,
            miles: healthManager.todaysDistance,
            isMe: true,
            completed: ProgressCalculator.isGoalCompleted(
                current: healthManager.todaysDistance, goal: user.goalMiles
            )
        ))
        rows.sort { $0.miles > $1.miles }
        WidgetDataStore.save(leaderboardRows: rows)
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
