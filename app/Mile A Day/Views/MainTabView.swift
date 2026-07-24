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

    // "Leave us a review" moment — gated to streak milestones by ReviewPromptManager.
    @StateObject private var reviewManager = ReviewPromptManager.shared

    // Celebrations (flame, leaderboard climb, photo prompt…) host HERE, above
    // the whole TabView — not inside DashboardView. The manager marks a
    // celebration consumed when it's dismissed, so the overlay must be visible
    // wherever the user is; hosted on the Dashboard tab it played invisibly
    // (and got spent) whenever a mile landed while another tab was selected.
    @StateObject private var celebrationManager = CelebrationManager.shared

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
                // `isActiveTab` lets the feed refresh itself on tab re-entry —
                // TabView keeps it alive, so its own .task can't (same reason
                // Compete/Friends refresh in the onChange below).
                SocialFeedView(isActiveTab: selectedTab == 2)
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
            // Sync explicitly, not just via onChange: if the badge is stale
            // from a previous session and the user has since resolved every
            // request elsewhere, the count stays 0 the whole launch, onChange
            // never fires, and the old number would sit there forever.
            await notificationService.setAppBadge(friendService.friendRequests.count)
            // Existing users already past a streak milestone get asked on this
            // first calm pass — the retroactive path.
            scheduleReviewEvaluation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceivePushNotification)) { notification in
            guard let type = notification.userInfo?["type"] as? String else { return }
            Task {
                switch type {
                case "friend_request", "friend_request_reminder":
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
                case "friend_request", "friend_request_reminder":
                    await friendService.refreshAllData()
                    // Park the intent so FriendsListView opens the sheet even
                    // if the Friends tab has never been visited this launch.
                    DeepLinkRouter.shared.requestOpenFriendRequests()
                    selectedTab = 3
                case "friend_request_accepted":
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
                     // deep-links to the exact post/story. Collab + mention +
                     // comment pushes follow the same route.
                     "friend_post", "story_reaction",
                     "coauthor_invite", "coauthor_accepted", "mention", "post_comment",
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
        // Single source of truth for the app icon badge. Every path that can
        // change the pending count — refreshAllData on launch/foreground/tab
        // switch/push, and the local array mutations in accept/decline — lands
        // here, so the badge can't drift the way four scattered call sites would.
        .onChange(of: friendService.friendRequests.count) { _, count in
            Task { await notificationService.setAppBadge(count) }
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
                    // Same reason as the launch sync above — covers a request
                    // resolved on another device while this one was backgrounded.
                    await notificationService.setAppBadge(friendService.friendRequests.count)
                    await syncLeaderboardWidget()
                }
                // Refresh health data and re-evaluate the daily reminder
                // so "Mile still waiting" is cancelled if the user completed their mile
                healthManager.fetchTodaysDistance()
                scheduleReviewEvaluation()
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

            // Full-app celebration takeover (flame, leaderboard, photo prompt).
            // Last child = above the tab bar, the workout banner, and the tour,
            // on whichever tab the user is actually looking at.
            CelebrationContainerView()
        }
        .onChange(of: celebrationManager.pendingAction) { _, action in
            // "View badges" from a badge celebration navigates on the Dashboard
            // stack — make sure the user is ON that tab to see it land.
            if action == .viewBadges {
                selectedTab = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MAD_StartGuidedTour"))) { _ in
            withAnimation(.easeIn(duration: 0.25)) {
                showGuidedTour = true
            }
        }
        .sheet(isPresented: $reviewManager.isPresented, onDismiss: handleReviewSheetDismiss) {
            ReviewPromptView(manager: reviewManager)
        }
        .onChange(of: userManager.currentUser.streak) { _, _ in
            scheduleReviewEvaluation()
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
                 "friend_post", "story_reaction",
                 "coauthor_invite", "coauthor_accepted", "mention", "post_comment":
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

    // MARK: - Review prompt

    /// Consider showing the review moment, but only when the screen is calm:
    /// on the Dashboard tab and with no celebration on-screen or queued (so it
    /// never stacks on top of a goal/badge celebration). Deferred briefly so it
    /// lands on a settled screen rather than mid-transition. Never shows during
    /// onboarding — this view only exists once setup is complete.
    private func scheduleReviewEvaluation() {
        guard selectedTab == 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let celebrations = CelebrationManager.shared
            guard !celebrations.isShowingCelebration, celebrations.celebrationQueue.isEmpty else { return }
            reviewManager.evaluate(streak: userManager.currentUser.streak, allowPresent: true)
        }
    }

    /// After the review sheet dismisses, if the user tapped the positive CTA,
    /// open the App Store review page. We deliberately do NOT use StoreKit's
    /// `requestReview` here: it's for unprompted moments, and Apple silently
    /// no-ops it once the user is over the ~3/year quota or has already rated —
    /// which made the button look broken. Our sheet IS the ask, so the tap is
    /// explicit intent and the deep link always lands. A short delay lets the
    /// sheet finish dismissing before we hand off to the App Store.
    private func handleReviewSheetDismiss() {
        guard reviewManager.pendingRateRequest else { return }
        reviewManager.pendingRateRequest = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let url = ReviewPromptManager.writeReviewURL else { return }
            _ = await UIApplication.shared.open(url)
        }
    }

    private func syncWidgetData() {
        WidgetDataStore.save(todayMiles: healthManager.todaysDistance, goal: userManager.currentUser.goalMiles)
        WidgetDataStore.save(streak: userManager.currentUser.streak)
        // Backfill the flame widget's style for users who chose it before the
        // widget existed (the setter mirrors it going forward).
        WidgetDataStore.save(dashboardStyle: DashboardStylePreference.current.rawValue)
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
