import SwiftUI
import HealthKit
import UserNotifications

/// The post a tapped push is ABOUT, when it's about one.
///
/// Anything that happened on a specific post opens that post directly. This
/// used to route to the notification inbox and make the user tap a second
/// time — and the row it landed on then only scrolled the feed, which found
/// nothing at all whenever the post was older than the loaded page.
///
/// Deliberate exclusions:
///  - `story_reaction` is about the viewer's own STORY, which has no feed
///    permalink; its existing handler replays the story viewer.
///  - a `friend_post` whose `kind` is "story" is the same case wearing a
///    different type.
///  - `friend_activity` is usually a raw workout with no post at all, and its
///    own handler already knows how to land on one.
func postTargetForPush(type: String, data: [String: String]) -> String? {
    let postTypes: Set<String> = [
        "mention", "post_comment", "coauthor_invite", "coauthor_accepted", "friend_post",
        // Both buddy-photo pushes open the walk's post directly — that card IS
        // the thing they're about, and landing in the inbox instead would make
        // "go see it" a two-tap instruction.
        "crew_photo", "crew_photo_nudge",
    ]
    guard postTypes.contains(type), data["kind"] != "story" else { return nil }
    guard let postId = data["post_id"], !postId.isEmpty else { return nil }
    return postId
}

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

    /// "Open this post" from a shared link or a notification tap. Presented
    /// here rather than inside a tab so it works from wherever the user is and
    /// survives a cold launch (the link may arrive before any tab is mounted).
    @StateObject private var postDeepLink = PostDeepLink.shared
    /// One-shot: stamped by the sheet's own Save (never on display), so a
    /// crash mid-sheet re-asks instead of silently applying nothing.
    @State private var showPrivacyOnboarding =
        !UserDefaults.standard.bool(forKey: PrivacyOnboardingView.seenKey)
    /// Streak-token state, for the two Assist sheets hosted at this root.
    @ObservedObject private var tokensState = StreakTokensState.shared

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
            let data = notification.userInfo?["data"] as? [String: String] ?? [:]
            if let postId = postTargetForPush(type: type, data: data) {
                postDeepLink.open(postId)
                Task { await refreshUnreadCount() }
                return
            }
            // A Head-to-Head lead change: the duel card is on the Dashboard,
            // so go straight there. Opening the inbox on top of it (what
            // `lead_change` otherwise does, since it's a competition type)
            // would hide the very thing the push is about.
            if type == "lead_change", data["challenge_key"] == "head_to_head" {
                selectedTab = 0
                Task { await refreshUnreadCount() }
                return
            }
            // Your own "mile complete" / "streak ended" — both land on the
            // Dashboard itself (celebration home, streak flame), not the inbox.
            if type == "goal_reached" || type == "streak_lost" {
                selectedTab = 0
                Task { await refreshUnreadCount() }
                return
            }
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
                case "weekly_challenge_new", "weekly_challenge_nudge",
                     "weekly_challenge_complete":
                    // The weekly challenge lives at the top of Compete. Refresh
                    // first so the card the user was just told about is the one
                    // they land on.
                    await WeeklyChallengeService.shared.refresh()
                    selectedTab = 1
                case "buddy_invite", "buddy_joined", "buddy_started":
                    // Park the session id so the Dashboard opens the lobby even
                    // on a cold launch, where DashboardView doesn't exist yet.
                    let data = notification.userInfo?["data"] as? [String: String]
                    if let sessionId = data?["session_id"], !sessionId.isEmpty {
                        DeepLinkRouter.shared.requestOpenBuddySession(sessionId: sessionId)
                    }
                    selectedTab = 0
                case "buddy_finished":
                    // The walk is already over — there's no lobby to return to,
                    // so the inbox row is the right landing spot.
                    selectedTab = 0
                    showNotificationInbox = true
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
                     "crew_photo", "crew_photo_nudge",
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
                // The posting window's expiry timer doesn't fire while
                // backgrounded, so a return from background could otherwise
                // show an unlocked composer for a window that has already
                // closed — and the server would refuse the post.
                FreshPostWindowManager.shared.refresh()
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
                // Re-mirror the streak/miles/style into the App Group on every
                // foreground, not just at launch. A warm return used to write
                // nothing unless some value happened to change, so a widget
                // that had drifted (missed reload, background sync that never
                // ran) stayed wrong until the app was cold-launched.
                syncWidgetData()
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
        // One-time privacy walkthrough: first open after signing in (existing
        // users see it once after updating). Hosted at root like celebrations
        // — a sheet on a tab the user isn't looking at never appears.
        .sheet(isPresented: $showPrivacyOnboarding, onDismiss: {
            // Now, not on Save: the Dashboard's What's New / monthly recap /
            // style chooser all wait for this sheet to be off screen, and
            // `onDismiss` is the one hook that fires after the animation
            // whether it was saved or swiped away.
            NotificationCenter.default.post(name: PrivacyOnboardingView.doneNotification, object: nil)
        }) {
            PrivacyOnboardingView {
                showPrivacyOnboarding = false
            }
        }
        // A Streak Assist waiting on this user's answer. Hosted HERE, not on
        // the Dashboard, for the same reason the celebrations are: a sheet
        // presented from a tab the user isn't looking at either never appears
        // or appears somewhere they didn't expect — and an offer dies with the
        // day it's trying to save.
        .sheet(
            isPresented: Binding(
                get: { !tokensState.pendingOffers.isEmpty },
                set: { if !$0 { tokensState.pendingOffers = [] } }
            )
        ) {
            StreakAssistOfferSheet(
                offers: tokensState.pendingOffers,
                onResolved: { offer in
                    tokensState.pendingOffers.removeAll { $0.offer_id == offer.offer_id }
                }
            )
        }
        // "You ran a spare mile and someone can use it" — once a day, on the
        // refresh right after the run that earned it.
        .sheet(
            isPresented: Binding(
                get: { tokensState.donationPrompt != nil },
                set: { if !$0 { tokensState.donationPrompt = nil } }
            )
        ) {
            DonateMileSheet()
        }
        .sheet(
            isPresented: Binding(
                get: { postDeepLink.pendingPostId != nil },
                set: { if !$0 { postDeepLink.pendingPostId = nil } }
            )
        ) {
            if let postId = postDeepLink.pendingPostId {
                PostDetailLoaderView(postId: postId,
                                     autoFlyover: postDeepLink.pendingWantsFlyover)
            }
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
        // Same rule as the warm path — the payload now survives a cold launch,
        // so a mention tapped from the lock screen lands on the post too.
        if let postId = postTargetForPush(
            type: type,
            data: notificationService.pendingNotificationData
        ) {
            notificationService.pendingNotificationType = nil
            postDeepLink.open(postId)
            Task { await refreshUnreadCount() }
            return
        }
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
            // Mirrors the live handler above — cold launch is a separate code
            // path and dropping it would break the push for a killed app.
            case "weekly_challenge_new", "weekly_challenge_nudge",
                 "weekly_challenge_complete":
                await WeeklyChallengeService.shared.refresh()
                selectedTab = 1
            case "buddy_invite", "buddy_joined", "buddy_started":
                // Only the type survives a cold launch — the session id isn't
                // stored — so land on the Dashboard and let its
                // refreshMySessions() surface the invite on the buddy pill.
                selectedTab = 0
                notificationService.pendingNotificationType = nil
            case "competition_flex", "competition_milestone", "friend_nudge",
                 "friend_activity", "streak_broken", "personal_best",
                 "lead_change", "clash_tie",
                 "friend_post", "story_reaction",
                 "buddy_finished",
                 "coauthor_invite", "coauthor_accepted", "mention", "post_comment",
                 "crew_photo", "crew_photo_nudge":
                selectedTab = 0
                showNotificationInbox = true
                notificationService.pendingNotificationType = nil
            case "goal_reached", "streak_lost":
                // Straight to the Dashboard — celebration home / streak flame
                // — with no inbox sheet covering it.
                selectedTab = 0
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
        WidgetDataStore.save(todaySteps: healthManager.todaysSteps)
        // Before the streak save — that one carries the reload for both.
        WidgetDataStore.save(longestStreak: userManager.currentUser.longestStreak ?? 0)
        WidgetDataStore.save(streak: userManager.currentUser.streak)
        // Backfill the flame widget's style for users who chose it before the
        // widget existed (the setter mirrors it going forward).
        WidgetDataStore.save(dashboardStyle: DashboardStylePreference.current.rawValue)
        // Those saves are no-ops when nothing changed, so they can't fix a
        // widget that's rendering an old timeline over correct stored values.
        // Throttled to 15 minutes, so repeated foregrounding stays cheap.
        WidgetDataStore.requestFullReload()
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
