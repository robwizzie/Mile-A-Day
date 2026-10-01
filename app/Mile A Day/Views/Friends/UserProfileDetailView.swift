import SwiftUI
import CoreLocation

/// Detailed view for displaying a user's profile information
struct UserProfileDetailView: View {
    let user: BackendUser
    // Observed, not a plain `let`: the friendship gates below (today's
    // progress card, nudge/compete row, close-friend star) read
    // `friendService.isFriend(...)`, and when the profile opens from a
    // surface that passes a freshly-created service (the feed), the friends
    // list arrives AFTER first render — without observation the view never
    // re-evaluates and today's distance stays blank.
    @ObservedObject var friendService: FriendService
    @ObservedObject private var userManager = UserManager.shared
    @ObservedObject private var closeFriends = CloseFriendsService.shared
    @Environment(\.dismiss) private var dismiss

    // Close-friend switch (in the ••• menu, whose item subtitle carries the
    // "they're never told" explanation that used to be a one-time caption).
    @State private var closeFriendActionInProgress = false
    @State private var showUnfriendConfirm = false
    /// The friend's rescue state, fetched once here so the Save Streak chip
    /// can render ONLY when there is something to do (see `saveStreakChip`).
    @State private var rescueStatus: FriendRescueStatus?
    /// The viewer's dashboard style — half of FriendFlameyCard's own
    /// visibility rule, mirrored so the Nudge pill can step aside for it.
    @AppStorage(DashboardStylePreference.key) private var viewerDashboardStyle = DashboardStyle.modern.rawValue

    @State private var userStats: UserStats?
    /// Today's miles off the stats payload, for the goal ring. Held beside
    /// `userStats` because that is a locally-built view model, not the response.
    @State private var friendTodayMiles: Double?
    /// Pure Flame — true when this user's streak is 100% natural (from the
    /// gated streak_features payload; false for un-enrolled users).
    @State private var hasPureFlame = false
    @State private var showPureFlameInfo = false
    @State private var userBadges: [Badge] = []
    @State private var catalogBadges: [Badge] = []
    @State private var hasLoadedBadges = false
    @State private var friendWorkouts: [FriendWorkout] = []
    /// Server-exact per-day totals for the week chart (see Last7DaysChart —
    /// the capped workout list must not drive the bars).
    @State private var last7DayMiles: [FriendDayMiles]?
    /// Days a token carried, straight off the stats payload. Held here rather
    /// than on `userStats` because that is a locally-built view model, not the
    /// decoded response.
    @State private var friendCoveredDays: [CoveredDate]?

    /// A token holding THEIR day today.
    ///
    /// Two sources, in that order: the nudge status (batched, serves the
    /// friend's own local day resolved server-side) and, as a fallback, the
    /// covered-day list from their stats keyed on the viewer's calendar. The
    /// second is only right when the two of them share a day — which is the
    /// common case, and better than drawing an untouched ring over a streak
    /// that just went up. Suppressed once their mile is genuinely in.
    private var friendSavedToday: CoveredDate? {
        // Either completion signal settles it — the two arrive from different
        // fetches and can disagree for a second, and a covered chip drawn
        // over a finished day is the one direction that reads as a bug.
        guard userStats?.hasCompletedGoalToday != true,
              nudgeStatus?.has_completed_mile != true
        else { return nil }
        if let covered = nudgeStatus?.today_covered { return covered }
        return CoveredDateIndex(friendCoveredDays).today
    }
    @State private var isLoadingStats = false
    @State private var isPrivate = false
    @State private var actionInProgress = false
    /// How many workouts the profile fetches; the Activity tab previews
    /// `workoutPreviewCount` of them and "See all" pages the rest.
    private let workoutLimit = 10
    private let workoutPreviewCount = 3
    @State private var hasLoadedInitial = false
    @State private var selectedWorkout: FriendWorkout?
    @State private var friendTodayChallenge: RemoteChallengeService.FriendTodayDTO?
    /// The full user record from `GET /users/:id` — the `user` handed in came
    /// from a list/feed projection that carries neither bio nor banner.
    @State private var fullUser: BackendUser?

    // Instagram-style friend count shown in the header, tappable to browse.
    @State private var friendCount: Int?
    // Mutual friends with the viewer ("X mutual friends"), non-self only.
    @State private var mutualCount: Int?

    // Nudge state — fetched on appear, only relevant when viewing a friend
    // who hasn't completed today and hasn't been nudged in the last 24h.
    @State private var nudgeStatus: NudgeStatusResponse?
    @State private var isNudging = false
    @State private var nudgeFeedback: NudgeFeedback?
    /// A Flamey poke got 403 flamey_unavailable — no Flamey this visit.
    @State private var flameyUnavailable = false

    // Compete-together sheet — opens CreateCompetitionView with this friend
    // pre-selected. Sheet state lives here so the CTA can present the
    // standard NavigationStack-wrapped form modal.
    @State private var showCompeteSheet = false

    // Section tabs — break up the previously long vertical list into
    // focused views. Same tab grammar as own ProfileView so navigating
    // between profiles feels consistent.
    @State private var profileTab: FriendProfileTab = .activity

    enum FriendProfileTab: Hashable {
        case activity, posts, stats, badges
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Identity surface — applies to every tab.
                    profileHero

                    VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                        ProfileIdentityBlock(
                            username: user.username,
                            displayName: user.displayName,
                            bio: fullUser?.bio ?? user.bio,
                            showsPureFlame: hasPureFlame,
                            onPureFlame: { showPureFlameInfo = true }
                        )

                        if !isCurrentUser(), let mutualCount, mutualCount > 0 {
                            Text("\(mutualCount) mutual friend\(mutualCount == 1 ? "" : "s")")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.55))
                        }

                        // Streak · Miles · Friends. Friends is tappable to browse.
                        profileStatTiles

                        // ONE row of things to do: [Nudge] [Compete] [•••] for a
                        // friend (friendship + close friend live in the menu),
                        // the Add / Accept / Requested pill for anyone else.
                        if !isCurrentUser() {
                            relationshipRow
                        }

                        if isPrivate {
                            privateAccountView
                        } else {
                            ProfileTabBar(
                                selection: $profileTab,
                                items: [
                                    .init(id: .activity, title: "Activity"),
                                    .init(id: .posts, title: "Posts"),
                                    .init(id: .stats, title: "Stats"),
                                    .init(id: .badges, title: "Badges")
                                ]
                            )
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, MADTheme.Spacing.screenGutter)
                    .padding(.top, 6)

                    if !isPrivate {
                        // Content for the selected tab.
                        Group {
                            switch profileTab {
                            case .activity: activityTabContent
                            case .posts: ProfilePostsGridView(userId: user.user_id, isSelf: isCurrentUser())
                            case .stats: statsTabContent
                            case .badges: badgesTabContent
                            }
                        }
                        .animation(.easeInOut(duration: 0.18), value: profileTab)
                        .padding(.horizontal, MADTheme.Spacing.screenGutter)
                        .padding(.top, MADTheme.Spacing.md)
                    }
                }
                .padding(.bottom, MADTheme.Spacing.xl)
                .lockedToScrollWidth()
            }
            .refreshable {
                await refreshProfileData()
            }
        }
        .navigationTitle(user.username ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // `.cancellationAction` instead of `.navigationBarLeading` — the
            // semantic placement gives iOS responsibility for hit-targeting
            // and avoids first-tap-fail issues that show up when custom
            // placements collide with sheet drag gestures.
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
                .foregroundColor(MADTheme.Colors.madRed)
            }
        }
        .sheet(item: $selectedWorkout) { workout in
            FriendWorkoutDetailSheet(
                workout: workout,
                friendService: friendService,
                owner: RouteArtAvatar(name: user.displayName, imageURL: user.profile_image_url)
            )
        }
        .sheet(isPresented: $showCompeteSheet) {
            CreateCompetitionView(
                onCreated: { _ in
                    showCompeteSheet = false
                },
                preselectedFriend: user
            )
        }
        .sheet(isPresented: $showPureFlameInfo) {
            PureFlameInfoSheet()
        }
        .overlay(alignment: .top) {
            if let feedback = nudgeFeedback {
                profileNudgeBanner(feedback)
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .onAppear {
            loadUserData()
        }
        .task {
            await loadFriendTodayChallenge()
        }
        .task {
            await loadFullUser()
        }
        .task {
            await loadBadges()
        }
        .task {
            // Friendship data FIRST, nudge status second — loadNudgeStatus is
            // gated on isFriend, and a service passed in fresh (e.g. from the
            // feed) hasn't loaded its friends list yet. Running them in
            // parallel made the gate misread friends as strangers, so today's
            // distance never loaded.
            //
            // Only the three lists the relationship gates read — not
            // refreshAllData, whose trailing nudge-status sweep re-fetched every
            // friend's day and re-rendered the friends list under this screen
            // for a status this screen loads for one person below.
            let service = friendService
            await withTaskGroup(of: Void.self) { group in
                group.addTask { try? await service.loadFriends() }
                group.addTask { try? await service.loadFriendRequests() }
                group.addTask { try? await service.loadSentRequests() }
            }
            async let nudge: Void = loadNudgeStatus()
            async let rescue: Void = loadRescueStatus()
            _ = await (nudge, rescue)
        }
        .task {
            await closeFriends.loadIfNeeded()
        }
        .task {
            await loadFriendCount()
        }
        .task {
            await loadMutualCount()
        }
    }

    // MARK: - Relationship row

    /// A friend gets the action row; anyone else gets the one pill that
    /// moves the friendship forward (Add / Accept / Requested).
    @ViewBuilder
    private var relationshipRow: some View {
        if friendService.isFriend(user) {
            actionRow
        } else {
            friendStatusPill
        }
    }

    /// Only ever called for a NON-friend — a friend's status lives in the
    /// ••• menu (`moreMenu`), not as a disabled "Friends" pill.
    @ViewBuilder
    private var friendStatusPill: some View {
        if friendService.hasPendingRequest(from: user) {
            actionPill(icon: "person.badge.plus", title: "Accept Request", tint: MADTheme.Colors.madRed,
                       busy: actionInProgress, enabled: !actionInProgress) { handleAcceptRequest() }
        } else if friendService.hasSentRequest(to: user) {
            actionPill(icon: "clock", title: "Request Sent", tint: .white.opacity(0.5), busy: false, enabled: false) {}
        } else {
            actionPill(icon: "person.badge.plus", title: "Add Friend", tint: MADTheme.Colors.madRed,
                       busy: actionInProgress, enabled: !actionInProgress) { handleSendRequest() }
        }
    }

    /// The ••• pill: friendship status + Remove Friend, and the private
    /// close-friend switch (its explanation rides as the item's subtitle —
    /// the other user is never told). A yellow star on the pill keeps "they're
    /// a close friend" visible without a whole pill for it.
    private var moreMenu: some View {
        let isClose = closeFriends.isClose(user.user_id)
        return Menu {
            Section("You're friends") {
                Button {
                    handleCloseFriendToggle()
                } label: {
                    Label {
                        Text(isClose ? "Remove from Close Friends" : "Add to Close Friends")
                        Text("Close friends can get notifications others don't. They're never told.")
                    } icon: {
                        Image(systemName: isClose ? "star.slash" : "star")
                    }
                }
                .disabled(closeFriendActionInProgress)

                Button(role: .destructive) {
                    showUnfriendConfirm = true
                } label: {
                    Label("Remove Friend", systemImage: "person.badge.minus")
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 46, height: 34)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.05))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                    )
                if isClose {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.yellow)
                        .offset(x: -6, y: 5)
                }
            }
            .contentShape(Capsule())
        }
        .accessibilityLabel("More options for \(user.displayName)")
        .accessibilityValue(isClose ? "Close friend" : "Friend")
    }

    private func handleUnfriend() {
        Task {
            do {
                try await friendService.removeFriend(user)
            } catch {
                await MainActor.run {
                    showProfileNudgeFeedback(NudgeFeedback(
                        icon: "xmark.circle",
                        message: "Couldn't remove \(user.displayName). Try again.",
                        isError: true
                    ))
                }
            }
        }
    }

    /// The one pill metric every action on this screen uses.
    private func actionPill(
        icon: String,
        title: String,
        tint: Color,
        busy: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            MADHaptics.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                if busy {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(tint)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundColor(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(tint.opacity(0.08))
                    .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func handleCloseFriendToggle() {
        guard !closeFriendActionInProgress else { return }
        closeFriendActionInProgress = true
        MADHaptics.tap()
        Task {
            do {
                try await closeFriends.toggle(user)
            } catch {
                print("[UserProfile] close-friend toggle failed: \(error)")
                MADHaptics.error()
            }
            await MainActor.run { closeFriendActionInProgress = false }
        }
    }

    private func loadFriendCount() async {
        do {
            let list = try await friendService.getFriendsList(for: user.user_id)
            await MainActor.run { friendCount = list.count }
        } catch {
            print("[UserProfileDetailView] loadFriendCount failed: \(error)")
        }
    }

    private func loadMutualCount() async {
        guard !isCurrentUser() else { return }
        do {
            let count = try await friendService.getMutualFriendCount(with: user.user_id)
            await MainActor.run { mutualCount = count }
        } catch {
            print("[UserProfileDetailView] loadMutualCount failed: \(error)")
        }
    }

    private func loadBadges() async {
        // Loads for the current user too — tapping your own row (e.g. on the
        // leaderboard) opens this view, and skipping the load left the Badges
        // tab on its loading spinner forever.
        // Fetch in parallel but handle each independently — if one endpoint
        // fails the other can still populate, and the section stays visible
        // as long as the catalog loads (the grid needs it to render at all).
        async let earnedTask = BadgeAPIService.fetchUserBadges(userId: user.user_id)
        async let catalogTask = BadgeAPIService.fetchCatalog()

        var fetchedEarned: [Badge] = []
        var fetchedCatalog: [Badge] = []

        do {
            let dtos = try await earnedTask
            fetchedEarned = dtos.map { $0.toBadge() }
        } catch {
            print("[UserProfileDetailView] fetchUserBadges failed: \(error)")
        }

        do {
            let dtos = try await catalogTask
            fetchedCatalog = dtos.map { $0.toLockedBadge() }
        } catch {
            print("[UserProfileDetailView] fetchCatalog failed: \(error)")
        }

        await MainActor.run {
            self.userBadges = fetchedEarned
            self.catalogBadges = fetchedCatalog
            self.hasLoadedBadges = true
        }
    }

    private func loadFriendTodayChallenge() async {
        do {
            let today = try await RemoteChallengeService.fetchFriendToday(userId: user.user_id)
            await MainActor.run { self.friendTodayChallenge = today }
        } catch {
            print("[UserProfileDetailView] loadFriendTodayChallenge failed: \(error)")
        }
    }

    // MARK: - Profile Header

    /// Banner (their photo or gradient preset) with the avatar in today's goal
    /// ring hanging off it. Progress and the next-mile milestone come from the
    /// stats payload, so a profile that hasn't loaded (or isn't shared with
    /// the viewer) draws the bare track and no milestone rather than zeros.
    private var profileHero: some View {
        let goal = userStats?.goalMiles ?? 0
        let progress: Double? = {
            guard userStats != nil, let today = friendTodayMiles, goal > 0 else { return nil }
            return min(today / goal, 1)
        }()
        return ProfileHero(
            bannerURL: fullUser?.profile_banner_url ?? user.profile_banner_url,
            bannerStyle: ProfileBannerStyle.resolve(fullUser?.profile_banner_style ?? user.profile_banner_style),
            totalMiles: userStats?.totalMiles,
            // The catalog's mile-medal rungs, once the Badges fetch lands.
            milestoneThresholds: MileMilestones.thresholds(from: catalogBadges),
            goalProgress: progress,
            goalComplete: userStats?.hasCompletedGoalToday ?? false,
            goalSavedToday: friendSavedToday
        ) {
            AvatarView(
                name: user.displayName,
                imageURL: fullUser?.profile_image_url ?? user.profile_image_url,
                size: 88
            )
        } topBar: {
            EmptyView()
        }
    }

    /// The full record, for the bio and banner the list row didn't carry.
    private func loadFullUser() async {
        guard let remote = try? await APIClient.fancyFetch(
            endpoint: "/users/\(user.user_id)",
            responseType: BackendUser.self
        ) else { return }
        await MainActor.run { fullUser = remote }
    }

    // MARK: - Profile Stats

    private var profileStatTiles: some View {
        ProfileStatTiles(
            streak: userStats?.streak ?? 0,
            totalMiles: userStats?.totalMiles ?? 0,
            friendCount: friendCount,
            streakDoneToday: userStats?.hasCompletedGoalToday ?? false,
            streakSavedToday: friendSavedToday
        ) {
            UserFriendsListView(
                userId: user.user_id,
                ownerName: user.username ?? user.displayName,
                friendService: friendService
            )
        }
    }

    // MARK: - Tab Content

    /// Their Flamey, today's challenge, the week, a short workouts preview and
    /// walks together. Default landing tab — the most time-sensitive info.
    /// Today's DISTANCE is not repeated here: the hero ring, its label and the
    /// stat tiles already carry it (a TODAY card used to say it a third time).
    @ViewBuilder
    private var activityTabContent: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            // Their Flamey first: the friendliest thing on the page, and the
            // poke is the quickest thing to do for them. Renders only when
            // THEY are Fun (the server's `flamey` block) and so is the viewer
            // (checked inside the card).
            friendFlameyCard
            // TODAY, as one group, tight together (8pt) so it reads as one
            // thought: why their streak stands on a day with no miles on it
            // (worth saying in full to a VIEWER, who may well be the person
            // whose mile paid for it), then the challenge they were served.
            VStack(spacing: MADTheme.Spacing.sm) {
                if !isCurrentUser(), friendService.isFriend(user), let saved = friendSavedToday {
                    SavedTodayBanner(day: saved, isSelf: false)
                }
                if let today = friendTodayChallenge {
                    FriendTodayChallengeRow(
                        today: today,
                        ownerName: user.displayName,
                        ownerImageURL: user.profile_image_url
                    )
                }
            }
            // The week's shape, then the workouts inside it.
            if !isCurrentUser(), !friendWorkouts.isEmpty {
                Last7DaysChart(
                    workouts: friendWorkouts,
                    dayTotals: last7DayMiles,
                    goalMiles: userStats?.goalMiles ?? 1.0,
                    coveredDays: friendCoveredDays,
                    isSelf: false
                )
            }
            if !friendWorkouts.isEmpty {
                recentWorkoutsPreview
            }
            // "12 walks together" — the number is only interesting next to the
            // person it's about, and the row opens the history already filtered
            // to them. Friends only: buddy walks are a friends-only feature, so
            // offering one to a stranger's profile is a button that can't work.
            if !isCurrentUser(), friendService.isFriend(user) {
                BuddyWalksTogetherRow(
                    userId: user.user_id, displayName: user.displayName)
            }
        }
    }

    /// The newest few workouts in the profile card grammar, with "See all"
    /// pushing the full list (and its Load more) — ten rows here buried
    /// everything below them.
    private var recentWorkoutsPreview: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            ProfileCardLabel(text: "RECENT WORKOUTS")
            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(friendWorkouts.prefix(workoutPreviewCount)) { workout in
                    Button {
                        selectedWorkout = workout
                    } label: {
                        // Only the owner is told when one of their workouts
                        // isn't counting, and only the owner can overrule it.
                        FriendWorkoutRow(workout: workout, showChevron: true,
                                         isOwnProfile: isCurrentUser(), ownerUserId: user.user_id)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            if friendWorkouts.count > workoutPreviewCount {
                NavigationLink {
                    FriendAllWorkoutsView(
                        user: user,
                        friendService: friendService,
                        initialWorkouts: friendWorkouts,
                        initialLimit: workoutLimit,
                        isOwnProfile: isCurrentUser()
                    )
                } label: {
                    HStack(spacing: 6) {
                        Text("See all workouts")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .accessibilityHidden(true)
                    }
                    .foregroundColor(MADTheme.Colors.madRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(MADTheme.Spacing.md)
        .profileCard()
    }

    /// Mirrors FriendFlameyCard's OWN visibility: their server `flamey` block
    /// is enabled (only ever for a friend, only for a Fun target), no poke
    /// this visit learned it's unavailable, and the viewer is Fun too. When
    /// it's on screen the Flamey poke IS the nudge (same endpoint, same
    /// cooldown), so the Nudge pill steps aside — one nudge surface.
    private var friendFlameyVisible: Bool {
        !isCurrentUser()
            && !flameyUnavailable
            && viewerDashboardStyle == DashboardStyle.fun.rawValue
            && FriendFlameyFacts(
                block: fullUser?.flamey,
                ownerName: user.first_name ?? user.username ?? user.displayName) != nil
    }
    /// "Aaron's Flamey". Friends only (the block is only ever enabled for
    /// one), hidden for good this visit if a poke learns Flamey is
    /// unavailable (either side left Fun).
    @ViewBuilder
    private var friendFlameyCard: some View {
        if !isCurrentUser(), !flameyUnavailable,
           let facts = FriendFlameyFacts(
               block: fullUser?.flamey,
               ownerName: user.first_name ?? user.username ?? user.displayName) {
            FriendFlameyCard(
                friendId: user.user_id,
                facts: facts,
                streak: nudgeStatus?.current_streak ?? userStats?.streak ?? 0,
                todayMiles: nudgeStatus?.today_miles ?? friendTodayMiles,
                goalMiles: userStats?.goalMiles ?? 1.0,
                isDone: nudgeStatus?.has_completed_mile == true || userStats?.hasCompletedGoalToday == true,
                savedToday: friendSavedToday != nil,
                alreadyNudged: nudgeStatus.map { $0.nudgedToday && !$0.unlimitedNudges } ?? false,
                onNudged: { markNudgeSent() },
                onUnavailable: { withAnimation(.easeInOut(duration: 0.25)) { flameyUnavailable = true } },
                badges: userBadges,
                catalogBadges: catalogBadges
            )
        }
    }

    /// Performance (best pace, best day, 7-day average), then the streaks
    /// they've run — the long view back lives with the other numbers.
    @ViewBuilder
    private var statsTabContent: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            FriendStatsView(user: user, stats: userStats, last7DayMiles: last7DayMiles)
            HallOfStreaksSection(userId: user.user_id, isSelf: isCurrentUser())
        }
    }

    /// Badge collection — pinned showcase + side-by-side comparison grid.
    @ViewBuilder
    private var badgesTabContent: some View {
        if hasLoadedBadges && !catalogBadges.isEmpty {
            FriendBadgeCompareView(
                ownerDisplayName: user.username ?? user.displayName,
                earnedBadges: userBadges,
                catalogBadges: catalogBadges,
                viewerEarnedBadgeIds: Set(userManager.currentUser.badges.filter { !$0.isLocked }.map { $0.id })
            )
        } else if hasLoadedBadges {
            // Fetches finished but the catalog came back empty (network/API
            // failure) — say so instead of spinning forever.
            VStack(spacing: MADTheme.Spacing.md) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.25))
                Text("Couldn't load badges")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.xl)
        } else {
            VStack(spacing: MADTheme.Spacing.md) {
                ProgressView().tint(MADTheme.Colors.madRed)
                Text("Loading badges…")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.xl)
        }
    }

    // MARK: - Action Row (Nudge + Compete + •••, Save Streak beneath)

    /// ONE row for a friend: [Nudge] [Compete] [•••]. Nudge is hidden when
    /// they've already completed today, and when their Flamey card is on
    /// screen (the poke is the nudge). Friendship status, Remove Friend and
    /// the close-friend switch live in the ••• menu. The Save Streak CTA can't
    /// live in a Menu (it owns a confirmation dialog), so it renders under the
    /// row — but ONLY while a save is actually in play (`saveStreakChip`);
    /// the "can't be saved because…" captions it would otherwise print are
    /// left off this screen.
    @ViewBuilder
    private var actionRow: some View {
        let nudgeIsAvailable: Bool = {
            guard let status = nudgeStatus, !friendFlameyVisible else { return false }
            return !status.has_completed_mile
        }()

        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if nudgeIsAvailable {
                    nudgeProfileButton
                }
                competeTogetherButton
                moreMenu
            }
            saveStreakChip
        }
        .confirmationDialog(
            "Remove \(user.displayName) as a friend?",
            isPresented: $showUnfriendConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove Friend", role: .destructive) { handleUnfriend() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will no longer be friends with this person.")
        }
    }

    /// The Donate-a-Mile CTA, in its actionable states only: the live offer,
    /// the locked "run x mi further today" pill (closable this afternoon),
    /// and the in-flight / "Mile offered" result. Phases the CTA can only
    /// EXPLAIN (needs an update, no token, beyond rescue) draw nothing here.
    /// The status is fetched once and handed down as `preloaded`, so the
    /// view's own model doesn't fetch a second time.
    @ViewBuilder
    private var saveStreakChip: some View {
        if let rescue = rescueStatus,
           rescue.alreadyOffered
            || rescue.available
            || (!rescue.friendNotEnrolled && rescue.needsMoreMiles) {
            SaveFriendStreakView(
                friendId: user.user_id,
                friendName: user.username ?? user.displayName,
                style: .prominent,
                preloaded: rescue,
                onSaved: { restored in
                    showProfileNudgeFeedback(NudgeFeedback(
                        icon: "paperplane.fill",
                        message: "Mile offered — \(user.displayName) can use it to get back to \(restored) days.",
                        isError: false
                    ))
                    // Their flame should read the restored length
                    // immediately, not on the next cold open.
                    Task { await refreshProfileData() }
                    loadUserData()
                }
            )
        }
    }

    private func loadRescueStatus() async {
        guard !isCurrentUser(), friendService.isFriend(user) else { return }
        do {
            let status = try await StreakFeatureService.rescueStatus(friendId: user.user_id)
            await MainActor.run { rescueStatus = status }
        } catch {
            print("[UserProfile] loadRescueStatus failed: \(error)")
        }
    }

    // MARK: - Compete Together

    private var competeTogetherButton: some View {
        // Secondary-weight outlined pill — yellow border, faint fill, no
        // shadow. Nudge is the primary action when applicable; Compete is
        // an occasional thing, so it doesn't need to fight Nudge for
        // attention. Smaller text + tighter padding keeps it discoverable
        // without overwhelming the profile header.
        Button {
            MADHaptics.tap()
            showCompeteSheet = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Compete")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundColor(Color.yellow)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(Color.yellow.opacity(0.08))
                    .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.4), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Refresh

    /// Re-fetches today's nudge status, today's challenge, recent workouts,
    /// and badges. Wired to the ScrollView's `.refreshable` so pulling down
    /// the profile gives the user fresh data without closing the sheet.
    private func refreshProfileData() async {
        // Capture MainActor-isolated values into locals BEFORE entering the
        // TaskGroup. The closures passed to `group.addTask` are nonisolated,
        // so they can't read `isCurrentUser()` or `workoutLimit` directly
        // (Swift 6 error). Hoisting the reads gives the tasks plain values.
        let isCurrent = isCurrentUser()
        let limit = workoutLimit
        let userId = user.user_id

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadNudgeStatus() }
            group.addTask { await loadRescueStatus() }
            group.addTask { await loadFriendTodayChallenge() }
            group.addTask { await loadBadges() }
            group.addTask {
                if !isCurrent {
                    do {
                        let workouts = try await friendService.fetchRecentWorkouts(for: userId, limit: limit)
                        await MainActor.run { self.friendWorkouts = workouts }
                    } catch {
                        print("[UserProfile] refresh workouts failed: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Nudge Button
    /// Mirrors the row-style nudge in FriendsListView: prominent CTA when
    /// available, muted "Nudged" pill when used today, hidden otherwise.
    @ViewBuilder
    private var nudgeProfileButton: some View {
        if !isCurrentUser(),
           friendService.isFriend(user),
           let status = nudgeStatus,
           !status.has_completed_mile {
            if status.nudgedToday && status.unlimitedNudges {
                // Unlimited-nudge roles: one already went out today, but they
                // may send another — the distinct "Nudge again" pill IS the
                // awareness that this isn't the first.
                Button {
                    handleProfileNudge()
                } label: {
                    HStack(spacing: 5) {
                        if isNudging {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.orange)
                        } else {
                            Image(systemName: "bell.and.waves.left.and.right.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Nudge again")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(.orange.opacity(0.75))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                Capsule().strokeBorder(
                                    Color.orange.opacity(0.35),
                                    style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isNudging)
            } else if status.nudgedToday {
                HStack(spacing: 5) {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Nudged")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.35))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                )
            } else {
                // Outlined orange pill — matches the Compete button's
                // visual weight (12pt / 14pad / 9vpad, no gradient or
                // shadow) so the two CTAs sit side-by-side without one
                // dominating. Drop the username — was making the button
                // too wide; "Nudge" alone is unambiguous in context.
                Button {
                    handleProfileNudge()
                } label: {
                    HStack(spacing: 5) {
                        if isNudging {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.orange)
                        } else {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Nudge")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(Color.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.08))
                            .overlay(Capsule().strokeBorder(Color.orange.opacity(0.4), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isNudging)
            }
        }
    }

    private func handleProfileNudge() {
        isNudging = true
        Task {
            do {
                try await friendService.nudgeFriend(user.user_id)
                await MainActor.run {
                    isNudging = false
                    markNudgeSent()
                    MADHaptics.success()
                    showProfileNudgeFeedback(NudgeFeedback(
                        icon: "bell.badge.fill",
                        message: "Nudge sent to \(user.displayName)!",
                        isError: false
                    ))
                }
            } catch {
                await MainActor.run {
                    isNudging = false
                    MADHaptics.error()
                    showProfileNudgeFeedback(NudgeFeedback(
                        icon: "xmark.circle.fill",
                        message: "Couldn't send nudge",
                        isError: true
                    ))
                }
            }
        }
    }

    /// The optimistic "nudged today" state, shared by the Nudge pill and a
    /// Flamey poke (the two spend the same daily nudge).
    private func markNudgeSent() {
        FlexNudgeTracker.markFriendNudgeSent(friendId: user.user_id)
        // Preserve existing miles/completion in the optimistic update.
        // Unlimited nudgers keep "Nudge again" available.
        let unlimited = nudgeStatus?.unlimitedNudges ?? false
        nudgeStatus = NudgeStatusResponse(
            can_nudge: unlimited,
            has_completed_mile: nudgeStatus?.has_completed_mile ?? false,
            already_nudged_today: !unlimited,
            today_miles: nudgeStatus?.today_miles,
            current_streak: nudgeStatus?.current_streak,
            has_nudged_today: true,
            unlimited_nudges: nudgeStatus?.unlimited_nudges,
            // Sending a nudge doesn't change whether a token is
            // holding their day — carry it, or the banner blinks
            // out the moment the bell is tapped.
            today_covered: nudgeStatus?.today_covered
        )
    }

    private func loadNudgeStatus() async {
        guard !isCurrentUser(), friendService.isFriend(user) else { return }
        do {
            let status = try await friendService.checkNudgeStatus(for: user.user_id)
            await MainActor.run { self.nudgeStatus = status }
        } catch {
            print("[UserProfile] loadNudgeStatus failed: \(error)")
        }
    }

    private func showProfileNudgeFeedback(_ feedback: NudgeFeedback) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            nudgeFeedback = feedback
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                nudgeFeedback = nil
            }
        }
    }

    /// Same visual treatment as the floating toast in FriendsListView so the
    /// nudge confirmation reads as a consistent system event across surfaces.
    private func profileNudgeBanner(_ feedback: NudgeFeedback) -> some View {
        let accent: Color = feedback.isError ? .red : .green
        return HStack(spacing: MADTheme.Spacing.sm) {
            // Constrain stripe height — `Rectangle()` is greedy and grows
            // to fill the .overlay's full parent height (the entire screen)
            // otherwise. Locking to 28pt matches the icon next to it.
            Rectangle()
                .fill(accent)
                .frame(width: 4, height: 28)
                .cornerRadius(2)

            Image(systemName: feedback.icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(accent.opacity(0.18)))

            Text(feedback.message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(2)

            Spacer(minLength: 4)
        }
        .padding(.leading, 6)
        .padding(.trailing, MADTheme.Spacing.md)
        .padding(.vertical, MADTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        )
    }

    // MARK: - Private Account View
    private var privateAccountView: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("Private Account")
                .font(MADTheme.Typography.title3)
                .foregroundColor(MADTheme.Colors.primaryText)

            Text("This user has set their account to private. Only their username and profile picture are visible.")
                .font(MADTheme.Typography.body)
                .foregroundColor(MADTheme.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.xl)
        .madLiquidGlass()
    }

    // MARK: - Helper Methods
    private func loadUserData() {
        isLoadingStats = true

        Task {
            do {
                let stats = try await friendService.fetchFriendStats(for: user.user_id)

                let workouts: [FriendWorkout]
                if let recentWorkouts = stats.recentWorkouts, !recentWorkouts.isEmpty {
                    workouts = recentWorkouts
                } else {
                    workouts = try await friendService.fetchRecentWorkouts(for: user.user_id, limit: workoutLimit)
                }

                await MainActor.run {
                    let mostMilesInOneDay = stats.bestMilesDay?.totalDistance ?? 0.0

                    var fastestMilePace: TimeInterval = 0.0
                    if let bestSplitTime = stats.bestSplitTime,
                       let bestSplitSeconds = bestSplitTime.bestSplitTime,
                       bestSplitSeconds > 0 {
                        fastestMilePace = bestSplitSeconds / 60.0
                    }

                    let goalMiles = stats.goalMiles ?? 1.0
                    let todayMiles = stats.todayMiles ?? 0.0
                    let hasCompletedGoalToday = goalMiles > 0
                        && ProgressCalculator.isGoalCompleted(current: todayMiles, goal: goalMiles)

                    userStats = UserStats(
                        streak: stats.streak,
                        totalMiles: stats.totalMiles,
                        fastestMilePace: fastestMilePace,
                        mostMilesInOneDay: mostMilesInOneDay,
                        hasCompletedGoalToday: hasCompletedGoalToday,
                        goalMiles: goalMiles
                    )
                    hasPureFlame = stats.naturalStreak && stats.streak > 0
                    friendTodayMiles = stats.todayMiles

                    friendWorkouts = workouts
                    last7DayMiles = stats.last7DayMiles
                    friendCoveredDays = stats.coveredDays
                    hasLoadedInitial = true
                    isLoadingStats = false
                }

            } catch {
                await MainActor.run {
                    print("[UserProfileDetailView] Failed to load user data: \(error)")
                    isLoadingStats = false
                }
            }
        }
    }

    private func isCurrentUser() -> Bool {
        guard let currentUserId = UserDefaults.standard.string(forKey: "backendUserId") else {
            return false
        }
        return user.user_id == currentUserId
    }

    private func handleSendRequest() {
        actionInProgress = true
        Task {
            do {
                try await friendService.sendFriendRequest(to: user)
                await MainActor.run { actionInProgress = false }
            } catch {
                await MainActor.run { actionInProgress = false }
            }
        }
    }

    private func handleAcceptRequest() {
        actionInProgress = true
        Task {
            do {
                try await friendService.acceptFriendRequest(from: user)
                await MainActor.run { actionInProgress = false }
            } catch {
                await MainActor.run { actionInProgress = false }
            }
        }
    }
}

// MARK: - All Workouts (friend profile "See all")

/// The full workouts list behind the profile's three-row preview, with the
/// Load More paging the profile used to carry inline. Seeded with what the
/// profile already fetched so it opens instantly; owns its own paging state
/// from there.
struct FriendAllWorkoutsView: View {
    let user: BackendUser
    @ObservedObject var friendService: FriendService
    let initialWorkouts: [FriendWorkout]
    let initialLimit: Int
    var isOwnProfile: Bool = false

    @State private var workouts: [FriendWorkout] = []
    @State private var limit = 10
    @State private var didSeed = false
    @State private var isLoadingMore = false
    @State private var selectedWorkout: FriendWorkout?

    /// A full page back means there may be more.
    private var canLoadMore: Bool { workouts.count >= limit }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: MADTheme.Spacing.md) {
                    FriendWorkoutsSection(
                        workouts: workouts,
                        onWorkoutTap: { selectedWorkout = $0 },
                        isOwnProfile: isOwnProfile,
                        ownerUserId: user.user_id
                    )
                    if canLoadMore {
                        loadMoreButton
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.screenGutter)
                .padding(.vertical, MADTheme.Spacing.md)
                .lockedToScrollWidth()
            }
        }
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            guard !didSeed else { return }
            didSeed = true
            workouts = initialWorkouts
            limit = initialLimit
        }
        .sheet(item: $selectedWorkout) { workout in
            FriendWorkoutDetailSheet(
                workout: workout,
                friendService: friendService,
                owner: RouteArtAvatar(name: user.displayName, imageURL: user.profile_image_url)
            )
        }
    }

    private var loadMoreButton: some View {
        Button {
            loadMore()
        } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                if isLoadingMore {
                    ProgressView()
                        .tint(MADTheme.Colors.madRed)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Load More Workouts")
                        .font(MADTheme.Typography.headline)
                }
            }
            .foregroundColor(MADTheme.Colors.madRed)
            .frame(maxWidth: .infinity)
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isLoadingMore)
    }

    private func loadMore() {
        guard !isLoadingMore else { return }
        let newLimit = limit + 10
        isLoadingMore = true
        Task {
            do {
                let fetched = try await friendService.fetchRecentWorkouts(for: user.user_id, limit: newLimit)
                await MainActor.run {
                    withAnimation(MADTheme.Animation.standard) {
                        workouts = fetched
                        limit = newLimit
                    }
                    isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    print("[FriendAllWorkoutsView] Failed to load more workouts: \(error)")
                    isLoadingMore = false
                }
            }
        }
    }
}

// MARK: - Friend Workout Detail Sheet

struct FriendWorkoutDetailSheet: View {
    let workout: FriendWorkout
    /// Passed down rather than constructed here — FriendService has no shared
    /// instance, and a View struct is rebuilt constantly.
    @ObservedObject var friendService: FriendService
    /// The friend whose run this is — rides the route line on the art card.
    /// Optional so nothing breaks if a future presenter has no profile handy.
    var owner: RouteArtAvatar? = nil
    @Environment(\.dismiss) private var dismiss

    /// The run's post, so this shows the actual photo — not just a chip saying
    /// one exists. Same card the feed draws (and the same lock when today's
    /// photo hasn't been earned yet).
    @State private var linkedPost: PostItem?
    /// The run's GPS trace from the server — the owner's own detail gets this
    /// from HealthKit, which never holds someone else's runs.
    @State private var routeCoordinates: [CLLocationCoordinate2D]?
    /// The server trimmed this route's start & end for route privacy (hide
    /// start & end) — drawn fading in and out, no start pin.
    @State private var routeTrimmed = false
    /// Retained map snapshot so the route map's pinch-zoom can compose its
    /// floating copy on demand (same mechanism as the feed cards).
    @State private var routeSnapshot: RouteMapSnapshot?
    @State private var isLoadingRoute = false
    /// Art by default; flips to the real Apple map on request.
    @State private var showRealMap = false
    /// Item-based flyover launch (fullScreenCover rule in ios.md).
    @State private var flyoverLaunch: FlyoverLaunch?
    /// Laid-out card size, so the art zoom composite matches its aspect.
    @State private var routeArtSize: CGSize = .zero

    /// The same rule your own detail uses, sanity guard included.
    private var pace: String {
        workoutPaceText(distanceMiles: workout.distance, durationSeconds: workout.totalDuration)
    }

    /// The run's post, headed like your own detail's "On the Feed" section but
    /// without the owner's edit/delete/add-to-feed controls.
    private func linkedPostSection(_ post: PostItem) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            WorkoutDetailSectionHeader(icon: "photo.on.rectangle.angled", title: "On the Feed")
            PostCardView(
                post: post,
                storyPhotoURL: post.storyPhotoURL,
                onHype: {},
                onReport: {},
                onBlock: {},
                onDelete: {},
                // This screen is a sheet: dismiss before routing, or the tab
                // flips behind it and the chip reads as dead.
                onOpenCompetition: { competitionId in
                    dismiss()
                    DeepLinkRouter.shared.requestOpenCompetitionAfterDismiss(id: competitionId)
                }
            )
        }
    }

    @ViewBuilder
    private var routeMapSection: some View {
        if let routeCoordinates, !routeCoordinates.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                HStack {
                    WorkoutDetailSectionHeader(icon: "map.fill", title: "Route")
                    Spacer()
                    flyoverPill
                    routeFaceToggle
                }
                Group {
                    if showRealMap {
                        WorkoutRouteMapView(
                            coordinates: routeCoordinates,
                            routeColor: workoutColor,
                            onSnapshot: { routeSnapshot = $0 },
                            routeTrimmed: routeTrimmed
                        )
                    } else {
                        RouteArtView(
                            coordinates: routeCoordinates,
                            routeColor: workoutColor,
                            authorAvatar: owner,
                            // Same region + size as the map face's snapshot, so
                            // ONE cached value serves both faces' zooms.
                            onSnapshot: { routeSnapshot = $0 },
                            // Same time-of-day cast as your own detail sheet —
                            // the forked copy shipped without it and a friend's
                            // dusk run drew the daytime canvas.
                            paletteDate: BuddyDate.parse(workout.deviceEndDate),
                            routeTrimmed: routeTrimmed
                        )
                    }
                }
                .frame(height: 260)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { routeArtSize = geo.size }
                            .onChange(of: geo.size) { _, newSize in routeArtSize = newSize }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                // Pinch to zoom, same as the feed cards and your own workout detail.
                .instagramZoomable(imageProvider: { routeZoomComposite() })
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
            .fullScreenCover(item: $flyoverLaunch) { launch in
                RouteFlyoverPlayerView(launch: launch)
            }
        }
    }

    @ViewBuilder
    private var flyoverPill: some View {
        // Courtesy gate on the runner's flyover_visibility (nil = older
        // server ⇒ offered). The route itself is already consent-gated.
        if workout.flyoverAllowed != false {
            flyoverPillButton
        }
    }

    private var flyoverPillButton: some View {
        FlyoverChipButton(accent: workoutColor) {
            guard let coords = routeCoordinates, coords.count >= 2 else { return }
            flyoverLaunch = FlyoverLaunch(
                coordinates: coords,
                workoutType: workout.workoutType,
                stats: PostStats(
                    distance: workout.distance,
                    pace: workout.distance > 0 ? workout.totalDuration / workout.distance : nil,
                    duration: workout.totalDuration,
                    streak: nil,
                    date: nil,
                    calories: workout.calories,
                    steps: nil
                ),
                author: owner,
                officialDistanceMiles: workout.distance
            )
        }
    }

    /// Same art/map flip as your own workout detail. No privacy change: this
    /// sheet only ever holds a route the server already served the viewer.
    private var routeFaceToggle: some View {
        Button {
            withAnimation(MADTheme.Animation.quick) { showRealMap.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showRealMap ? "paintpalette.fill" : "map.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(showRealMap ? "Art" : "Map")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    /// Floating zoom copy, composed on demand — the art canvas by default,
    /// the real map (from its retained snapshot) when toggled. Bare route,
    /// no stats band.
    private func routeZoomComposite() -> UIImage? {
        guard let coords = routeCoordinates, coords.count >= 2 else { return nil }
        if showRealMap {
            guard let snapshot = routeSnapshot else { return nil }
            return WorkoutRouteMapView.zoomComposite(
                snapshot: snapshot,
                coordinates: coords,
                routeColor: workoutColor,
                routeTrimmed: routeTrimmed,
                // Derived from the card's own aspect so the lift is a pure
                // upscale — a fixed size that didn't match would crop the route.
                size: WorkoutRouteMapView.zoomSize(for: snapshot, targetWidth: 900)
            ) {
                EmptyView()
            }
        }
        let size = routeArtSize.width > 1
            ? CGSize(width: 900, height: (900 * routeArtSize.height / routeArtSize.width).rounded())
            : CGSize(width: 900, height: 650)
        return RouteArtView.zoomComposite(
            coordinates: coords,
            routeColor: workoutColor,
            authorAvatar: owner,
            underlay: routeSnapshot,
            paletteDate: BuddyDate.parse(workout.deviceEndDate),
            routeTrimmed: routeTrimmed,
            size: size
        ) {
            EmptyView()
        }
    }

    /// The run's post, found by workout id among the author's posts — the same
    /// lookup your own detail does, just for someone else's id. The server
    /// scopes it to your circle and applies the photo gate.
    private func loadLinkedPost() async {
        guard linkedPost == nil else { return }
        let post = try? await PostService.fetchOwnPostForWorkout(
            workoutId: workout.id, userId: workout.userId
        )
        await MainActor.run { linkedPost = post }
    }

    /// Only when the server said there's a route to draw — no point asking
    /// otherwise, and `has_route` is already consent-gated.
    private func loadRoute() async {
        guard workout.hasRoute == true, routeCoordinates == nil, !isLoadingRoute else { return }
        await MainActor.run { isLoadingRoute = true }
        let detail = try? await friendService.fetchWorkoutRouteDetail(
            for: workout.userId, workoutId: workout.id
        )
        await MainActor.run {
            routeCoordinates = decodeRouteCoordinates(detail?.route)
            routeTrimmed = detail?.route_trimmed ?? false
            isLoadingRoute = false
        }
    }

    private var workoutColor: Color {
        MADTheme.workoutColor(workout.workoutType)
    }

    private var workoutIcon: String {
        switch workout.workoutType.lowercased() {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "cycling": return "bicycle"
        case "hiking": return "figure.hiking"
        default: return "figure.run"
        }
    }

    /// End − duration, the same way FriendWorkoutRow derives it. Nil when the
    /// server has no device timestamp, which is the only reason the timeline
    /// card is ever missing here.
    private var startDate: Date? {
        guard let end = workout.deviceEndDate, let d = RelativeTime.date(from: end) else { return nil }
        return d.addingTimeInterval(-workout.totalDuration)
    }

    private var endDate: Date? {
        guard let end = workout.deviceEndDate else { return nil }
        return RelativeTime.date(from: end)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea()

                // Same sections, same order, same components as your own
                // WorkoutDetailView — a friend's run reads exactly like yours.
                // Splits, the route map and the post card are the only things
                // missing, because the server doesn't hand those over for
                // someone else's workout.
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        WorkoutHeroCard(
                            icon: workoutIcon,
                            typeLabel: workout.workoutType.capitalized,
                            color: workoutColor,
                            distanceText: workout.formattedDistance,
                            dateText: workout.formattedDate,
                            source: WorkoutSource(rawValue: workout.source ?? "") ?? .healthkit,
                            hasRoute: workout.hasRoute == true,
                            hasPhoto: workout.hasPhoto == true
                        )

                        // The run's post — the real photo, exactly as the feed
                        // renders it. Read-only: hyping and reporting live on
                        // the feed, and none of the owner actions apply here.
                        if let post = linkedPost {
                            linkedPostSection(post)
                        }

                        // The map, on the same rule as your own detail: hidden
                        // when the post card above already carries the run's
                        // visuals, so there's never a double map.
                        if linkedPost == nil {
                            routeMapSection
                        }

                        WorkoutStatsCard(
                            duration: workout.formattedDuration,
                            pace: pace,
                            calories: workout.calories.flatMap { $0 > 0 ? Int($0) : nil }
                        )

                        if let start = startDate, let end = endDate {
                            WorkoutTimelineCard(
                                startText: start.formattedTime,
                                endText: end.formattedTime
                            )
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                }
                .task {
                    await loadLinkedPost()
                    await loadRoute()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(MADTheme.Colors.madRed)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Friend Today-Challenge Row

/// Compact "did my friend finish today's challenge?" indicator for the profile screen.
/// Uses the server-side completion status from `/users/:userId/challenges/today`.
struct FriendTodayChallengeRow: View {
    let today: RemoteChallengeService.FriendTodayDTO
    let ownerName: String
    let ownerImageURL: String?

    /// Local-catalog fallback when the server didn't enrich the row (older builds).
    private var challenge: DailyChallenge? {
        guard let key = today.challengeKey else { return nil }
        return DailyChallengeCatalog.byKey(key)
    }

    /// Prefer the server-enriched title so new challenges (e.g. social ones not in
    /// the local catalog) render correctly; fall back to the catalog, then neutral.
    private var displayTitle: String? {
        if let t = today.challengeTitle, !t.isEmpty { return t }
        return challenge?.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: iconGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY'S CHALLENGE")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                        .foregroundColor(.white.opacity(0.5))
                    Text(displayTitle ?? "Today's challenge")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Spacer()

                // Status pill on the right — clear "Completed" / "In progress"
                // signal that doesn't compete with the challenge name.
                HStack(spacing: 4) {
                    Image(systemName: today.completed ? "checkmark.circle.fill" : "hourglass")
                        .font(.system(size: 11, weight: .bold))
                    Text(today.completed ? "Done" : "Not yet")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                }
                .foregroundColor(today.completed ? .green : .white.opacity(0.55))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(today.completed ? Color.green.opacity(0.12) : Color.white.opacity(0.06))
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    today.completed ? Color.green.opacity(0.3) : Color.white.opacity(0.12),
                                    lineWidth: 1
                                )
                        )
                )
            }

            if today.challengeKey == "head_to_head", let opponent = today.opponent {
                FriendHeadToHeadStrip(
                    ownerName: ownerName,
                    ownerImageURL: ownerImageURL,
                    opponent: opponent,
                    accent: iconGradient.first ?? .orange
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var iconName: String {
        if let icon = today.challengeIcon, !icon.isEmpty { return icon }
        if let challenge = challenge { return challenge.icon }
        return today.completed ? "checkmark" : "hourglass"
    }

    private var iconGradient: [Color] {
        if let start = today.gradientStart, let end = today.gradientEnd,
           !start.isEmpty, !end.isEmpty {
            return [Color(hex: start), Color(hex: end)]
        }
        if let challenge = challenge {
            return challenge.gradient
        }
        return today.completed
            ? [.green, .green.opacity(0.8)]
            : [.white.opacity(0.2), .white.opacity(0.1)]
    }
}

private struct FriendHeadToHeadStrip: View {
    let ownerName: String
    let ownerImageURL: String?
    let opponent: RemoteChallengeService.OpponentDTO
    let accent: Color

    private var rivalName: String { opponent.username ?? "Opponent" }
    private var tied: Bool { abs(opponent.myMiles - opponent.miles) < 0.01 }
    private var ownerLeading: Bool { opponent.myMiles > opponent.miles && !tied }
    private var statusColor: Color { tied ? .yellow : (ownerLeading ? .green : .orange) }

    private var statusText: String {
        if tied { return "Even at \(formatMiles(opponent.myMiles)) mi" }
        let diff = abs(opponent.myMiles - opponent.miles)
        if ownerLeading {
            return "\(ownerName) leads by \(formatMiles(diff)) mi"
        }
        return "\(rivalName) leads by \(formatMiles(diff)) mi"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                side(
                    name: ownerName,
                    image: ownerImageURL,
                    miles: opponent.myMiles,
                    highlight: ownerLeading,
                    color: accent
                )

                VStack(spacing: 3) {
                    Text("VS")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                    Image(systemName: tied ? "equal.circle.fill" : "arrowtriangle.up.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(statusColor)
                }
                .frame(width: 44)

                side(
                    name: rivalName,
                    image: opponent.profileImageUrl,
                    miles: opponent.miles,
                    highlight: !ownerLeading && !tied,
                    color: .orange
                )
            }

            Text(statusText)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(statusColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            // Live standings, not a verdict — the duel is a whole-day total
            // the server scores after midnight.
            Text("Winner decided at day's end")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(statusColor.opacity(0.28), lineWidth: 1)
                )
        )
    }

    private func side(name: String, image: String?, miles: Double, highlight: Bool, color: Color) -> some View {
        HStack(spacing: 8) {
            AvatarView(name: name, imageURL: image, size: 34)
                .overlay(Circle().strokeBorder(highlight ? color : .clear, lineWidth: 2))
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(formatMiles(miles)) mi")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(highlight ? color : .white.opacity(0.72))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatMiles(_ miles: Double) -> String {
        String(format: "%.2f", miles)
    }
}

// MARK: - Last 7 Days Mini Chart

/// Bar chart of the friend's last 7 days of miles. Totals come from the
/// stats payload's `last_7_day_miles` — the server's exact per-day series —
/// because the recent-workouts LIST is capped: a user logging several
/// workouts a day pushes the week's early days out of the cap, and a
/// 400-day streak read as an empty Fri-Sun. `workouts` stays as the
/// per-workout breakdown for the tap-detail panel, and as the totals
/// fallback until the server ships the field. Goal-hit days are green,
/// partial days orange, zeros muted; today is ringed so users orient
/// themselves at a glance.
///
/// "Hit" means `ProgressCalculator.isGoalCompleted` — the 0.95 tolerance the
/// server counts streaks with — NOT a raw `>= goal`. A 0.996-mile day is a
/// completed day everywhere else in the product, and it also RENDERS as
/// "1.00 mi" here, so a strict compare painted a day orange while the label
/// beside it read a full mile.
struct Last7DaysChart: View {
    let workouts: [FriendWorkout]
    /// Server-exact per-day totals (`FriendStats.last7DayMiles`); nil falls
    /// back to aggregating `workouts`.
    var dayTotals: [FriendDayMiles]? = nil
    /// The profile owner's own daily goal (`FriendStats.goalMiles`). Defaults
    /// to a mile so a caller without stats loaded still renders sanely — but
    /// a 2-mile-goal friend must not go green at 1.0.
    var goalMiles: Double = 1.0
    /// Days a streak token carried. Without this the chart paints a saved day
    /// exactly like a missed one — the 0.57 mi bar that made a correct Save
    /// Streak offer look like a lie.
    var coveredDays: [CoveredDate]? = nil
    /// Whose chart this is, so the saved-day copy uses the right voice.
    var isSelf: Bool = false

    private var covered: CoveredDateIndex { CoveredDateIndex(coveredDays) }

    private let calendar = Calendar.current

    /// Never let a zero/absent goal through: `isGoalCompleted(current:goal:)`
    /// is `current >= goal * 0.95`, which a goal of 0 makes vacuously true —
    /// that would paint an empty day green.
    private var goal: Double { goalMiles > 0 ? goalMiles : 1.0 }

    /// Selected day for the inline detail panel. Tapping a bar toggles
    /// selection — second tap on the same day closes the panel.
    @State private var selectedDay: Date?

    /// Map of date (start of day) → total miles for that day. Server series
    /// when available, else summed from the (capped) recent workouts.
    private var milesByDay: [Date: Double] {
        let cutoff = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: Date()) ?? Date())
        var result: [Date: Double] = [:]
        if let dayTotals, !dayTotals.isEmpty {
            for entry in dayTotals {
                guard let day = parseDay(entry.date) else { continue }
                guard day >= cutoff else { continue }
                result[day, default: 0] += entry.miles
            }
            return result
        }
        for workout in workouts {
            guard let day = parseDay(workout.date) else { continue }
            guard day >= cutoff else { continue }
            result[day, default: 0] += workout.distance
        }
        return result
    }

    /// 7 days ending today, oldest first.
    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
    }

    private var weekTotal: Double {
        milesByDay.values.reduce(0, +)
    }

    /// Tallest bar's value — used to scale the rest. Floored at the goal so a
    /// week with one short run doesn't look like a wall.
    private var maxValue: Double {
        max(milesByDay.values.max() ?? 0, goal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack {
                Text("LAST 7 DAYS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(String(format: "%.1f mi total", weekTotal))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days, id: \.self) { day in
                    barColumn(for: day)
                }
            }
            .frame(height: 108)

            if let selected = selectedDay {
                dayDetailPanel(for: selected)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: selectedDay)
    }

    private func barColumn(for day: Date) -> some View {
        let miles = milesByDay[day] ?? 0
        let progress = min(miles / maxValue, 1.0)
        let isToday = calendar.isDateInToday(day)
        let didHit = ProgressCalculator.isGoalCompleted(current: miles, goal: goal)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let savedBy = covered.day(for: day)
        // A saved day is NOT a miss and must never wear the miss colour, no
        // matter how few miles it holds — that equivalence is the whole bug.
        let color: Color = savedBy != nil
            ? SavedDayStyle.tint
            : (miles == 0
                ? Color.white.opacity(0.12)
                : (didHit ? .green : .orange))

        return Button {
            MADHaptics.tap()
            // Second tap on the same bar closes the detail panel.
            if isSelected {
                selectedDay = nil
            } else {
                selectedDay = day
            }
        } label: {
            VStack(spacing: 6) {
                // Token marker, so a saved day is legible without tapping it.
                // Always occupies its slot (hidden when absent) so bars keep a
                // common baseline.
                Image(systemName: SavedDayStyle.icon(for: savedBy?.kind ?? "streak_save"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SavedDayStyle.tint)
                    .opacity(savedBy != nil ? 1 : 0)
                    .frame(height: 10)

                // Bar
                GeometryReader { geo in
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: miles == 0 ? [color, color] : [color, color.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: max(geo.size.height * progress, miles > 0 ? 4 : 2))
                            .overlay(
                                // Selection ring on the bar — sits inside
                                // the bar so it doesn't change the layout
                                // when toggled on/off.
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color.white.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
                            )
                    }
                }
                .frame(maxWidth: .infinity)

                // Weekday + date. A 3-letter abbreviation ("Tue") plus the
                // day number removes the ambiguity of single letters — "T"
                // read as both Tue and Thu, "S" as both Sat and Sun — which
                // made it impossible to tell which bar was which day.
                VStack(spacing: 0) {
                    Text(weekdayAbbrev(for: day))
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                    Text(dayNumber(for: day))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .opacity(0.75)
                }
                .foregroundColor(isToday || isSelected ? .white : .white.opacity(0.45))
                .frame(width: 30, height: 30)
                .background(
                    Capsule()
                        .fill(
                            isSelected ? color.opacity(0.85) :
                            (isToday ? MADTheme.Colors.madRed : Color.clear)
                        )
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    /// Per-workout breakdown of the selected day — shows date, total miles,
    /// and each individual workout (type + distance). When the day has no
    /// activity, surfaces a friendly "no miles" message instead. The TOTAL
    /// comes from `milesByDay` (server-exact when available) — the workout
    /// rows are best-effort: days older than the capped recent-workouts list
    /// still show their true total, just without the per-workout lines.
    @ViewBuilder
    private func dayDetailPanel(for day: Date) -> some View {
        let dayWorkouts = workouts.compactMap { workout -> FriendWorkout? in
            guard let workoutDay = parseDay(workout.date) else { return nil }
            return calendar.isDate(workoutDay, inSameDayAs: day) ? workout : nil
        }
        let total = milesByDay[calendar.startOfDay(for: day)]
            ?? dayWorkouts.reduce(0.0) { $0 + $1.distance }
        let dateLabel: String = {
            if calendar.isDateInToday(day) { return "Today" }
            if calendar.isDateInYesterday(day) { return "Yesterday" }
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: day)
        }()

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dateLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(String(format: "%.2f mi", total))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(
                        covered.contains(day)
                            ? SavedDayStyle.tint
                            : (ProgressCalculator.isGoalCompleted(current: total, goal: goal)
                                ? .green
                                : (total > 0 ? .orange : .white.opacity(0.4)))
                    )
            }

            if let savedBy = covered.day(for: day) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: SavedDayStyle.icon(for: savedBy.kind))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SavedDayStyle.tint)
                    Text(SavedDayStyle.explanation(for: savedBy, isSelf: isSelf))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(SavedDayStyle.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }

            if dayWorkouts.isEmpty && total == 0 {
                Text(covered.contains(day) ? "No miles logged — the streak held anyway" : "No miles logged")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            } else if dayWorkouts.isEmpty {
                // Day is older than the capped recent-workouts list — the
                // total above is still exact (server series).
                Text("Workout details unavailable for this day")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                ForEach(dayWorkouts) { workout in
                    HStack(spacing: 8) {
                        Image(systemName: workoutTypeIcon(workout.workoutType))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(workoutTypeColor(workout.workoutType))
                            .frame(width: 20, height: 20)
                            .background(
                                Circle().fill(workoutTypeColor(workout.workoutType).opacity(0.15))
                            )
                        Text(workout.workoutType.capitalized)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text(String(format: "%.2f mi", workout.distance))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 4)
    }

    private func workoutTypeIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "cycling": return "figure.outdoor.cycle"
        case "hiking": return "figure.hiking"
        default: return "figure.run"
        }
    }

    private func workoutTypeColor(_ type: String) -> Color {
        MADTheme.workoutColor(type)
    }

    /// Three-letter localized weekday ("Sun", "Mon", "Tue"…). Unambiguous
    /// where a single letter is not.
    private func weekdayAbbrev(for date: Date) -> String {
        Self.weekdayFormatter.string(from: date)
    }

    /// Day of month ("1"…"31"), shown under the weekday so a specific date
    /// is identifiable at a glance.
    private func dayNumber(for date: Date) -> String {
        Self.dayNumberFormatter.string(from: date)
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    private func parseDay(_ string: String) -> Date? {
        // Workout dates come in two formats from the backend: a plain
        // `local_date` ("yyyy-MM-dd") or, rarely, a full ISO timestamp. Both
        // are fixed-format, so the formatters MUST use the POSIX locale —
        // otherwise a user on a non-Gregorian calendar (e.g. Buddhist) or an
        // unusual locale fails to parse and the day silently drops to zero.
        if let parsed = Self.dateOnlyFormatter.date(from: string) {
            return calendar.startOfDay(for: parsed)
        }
        if let parsed = Self.isoFormatter.date(from: string) {
            return calendar.startOfDay(for: parsed)
        }
        return nil
    }

    /// Plain `local_date` ("yyyy-MM-dd"). This is the format the backend
    /// actually sends for workout dates, so it's tried first.
    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Fallback ISO timestamp ("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return f
    }()
}

// MARK: - Preview
struct UserProfileDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let mockUser = BackendUser(
            user_id: "123",
            username: "johndoe",
            email: "john@example.com",
            first_name: "John",
            last_name: "Doe",
            bio: "Love running and staying active!",
            profile_image_url: nil,
            apple_id: nil,
            auth_provider: "apple",
            role: nil
        )

        UserProfileDetailView(user: mockUser, friendService: FriendService())
    }
}
