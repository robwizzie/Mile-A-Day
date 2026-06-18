import SwiftUI

/// Detailed view for displaying a user's profile information
struct UserProfileDetailView: View {
    let user: BackendUser
    let friendService: FriendService
    @ObservedObject private var userManager = UserManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var userStats: UserStats?
    @State private var userBadges: [Badge] = []
    @State private var catalogBadges: [Badge] = []
    @State private var hasLoadedBadges = false
    @State private var friendWorkouts: [FriendWorkout] = []
    @State private var isLoadingStats = false
    @State private var isPrivate = false
    @State private var actionInProgress = false
    @State private var workoutLimit = 10
    @State private var isLoadingMoreWorkouts = false
    @State private var hasLoadedInitial = false
    @State private var selectedWorkout: FriendWorkout?
    @State private var friendTodayChallenge: RemoteChallengeService.FriendTodayDTO?

    // Instagram-style friend count shown in the header, tappable to browse.
    @State private var friendCount: Int?
    // Mutual friends with the viewer ("X mutual friends"), non-self only.
    @State private var mutualCount: Int?

    // Nudge state — fetched on appear, only relevant when viewing a friend
    // who hasn't completed today and hasn't been nudged in the last 24h.
    @State private var nudgeStatus: NudgeStatusResponse?
    @State private var isNudging = false
    @State private var nudgeFeedback: NudgeFeedback?

    // Compete-together sheet — opens CreateCompetitionView with this friend
    // pre-selected. Sheet state lives here so the CTA can present the
    // standard NavigationStack-wrapped form modal.
    @State private var showCompeteSheet = false

    // Section tabs — break up the previously long vertical list into
    // focused views. Same tab grammar as own ProfileView so navigating
    // between profiles feels consistent.
    @State private var profileTab: FriendProfileTab = .activity

    enum FriendProfileTab: Hashable {
        case activity, stats, badges
    }

    private var canLoadMore: Bool {
        hasLoadedInitial && friendWorkouts.count >= workoutLimit
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    // Profile header stays above the tab picker — it's the
                    // identity surface and applies to every tab.
                    profileHeader

                    if isPrivate {
                        privateAccountView
                    } else {
                        // Tab picker — same pill-style grammar as Friends /
                        // Compete / Profile mode pickers.
                        MADPillPicker(
                            selection: $profileTab,
                            options: [
                                .init(id: .activity, title: "Activity", systemImage: "flame.fill"),
                                .init(id: .stats, title: "Stats", systemImage: "chart.bar.fill"),
                                .init(id: .badges, title: "Badges", systemImage: "trophy.fill")
                            ]
                        )

                        // Content for the selected tab.
                        Group {
                            switch profileTab {
                            case .activity: activityTabContent
                            case .stats: statsTabContent
                            case .badges: badgesTabContent
                            }
                        }
                        .animation(.easeInOut(duration: 0.18), value: profileTab)
                    }
                }
                .padding(.vertical, MADTheme.Spacing.md)
                .padding(.horizontal, MADTheme.Spacing.md)
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
            FriendWorkoutDetailSheet(workout: workout)
        }
        .sheet(isPresented: $showCompeteSheet) {
            CreateCompetitionView(
                onCreated: { _ in
                    showCompeteSheet = false
                },
                preselectedFriend: user
            )
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
            refreshFriendshipStatus()
        }
        .task {
            await loadFriendTodayChallenge()
        }
        .task {
            await loadBadges()
        }
        .task {
            await loadNudgeStatus()
        }
        .task {
            await loadFriendCount()
        }
        .task {
            await loadMutualCount()
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
    private var profileHeader: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Background gradient — clipped to the same rounded shape as
                // the parent card (set on the outer `.clipShape` below) so
                // the gradient doesn't bleed past the top-left / top-right
                // corners. Without the clip, the gradient renders to the
                // raw VStack bounds and the corners appear square.
                LinearGradient(
                    gradient: Gradient(colors: [
                        MADTheme.Colors.madRed.opacity(0.3),
                        Color.clear
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)

                VStack(spacing: MADTheme.Spacing.lg) {
                    // Profile Image
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 128, height: 128)

                        ProfileImageView(user: user, size: 120)
                    }
                    .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 5)
                    .padding(.top, 40)

                    // User Info
                    VStack(spacing: MADTheme.Spacing.sm) {
                        Text(user.username ?? "Unknown")
                            .font(MADTheme.Typography.title1)
                            .foregroundColor(MADTheme.Colors.primaryText)

                        if user.displayName != user.username {
                            Text(user.displayName)
                                .font(MADTheme.Typography.body)
                                .foregroundColor(MADTheme.Colors.secondaryText)
                        }

                        // Bio with quote-style design
                        if let bio = user.bio, !bio.isEmpty {
                            HStack(alignment: .top, spacing: MADTheme.Spacing.sm) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(MADTheme.Colors.madRed.opacity(0.5))
                                    .frame(width: 2)

                                Text(bio)
                                    .font(MADTheme.Typography.body)
                                    .foregroundColor(MADTheme.Colors.secondaryText)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.horizontal, MADTheme.Spacing.lg)
                            .padding(.top, MADTheme.Spacing.xs)
                        }
                    }

                    // Triple-stat row (Streak · Miles · Friends). Friends is
                    // tappable to browse and add more people.
                    profileStatsRow

                    if !isCurrentUser(), let mutualCount, mutualCount > 0 {
                        Text("\(mutualCount) mutual friend\(mutualCount == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.55))
                    }

                    // Friend status pill (friendship state + actions menu).
                    // Centered at natural size — used to be full-width which
                    // made it dominate the header.
                    HStack { friendActionButton }
                        .frame(maxWidth: .infinity)

                    // Action row — Nudge + Compete share a single horizontal
                    // row of equal-width pills. Previously each was a
                    // full-width stacked button; the new layout reads as one
                    // CTA region and takes one row instead of three. Hype
                    // stays out (context-dependent, lives on push events).
                    if !isCurrentUser(), friendService.isFriend(user) {
                        actionRow
                            .padding(.horizontal, MADTheme.Spacing.lg)
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.lg)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous))
        .madLiquidGlass()
    }

    // MARK: - Profile Stats Row

    private var profileStatsRow: some View {
        ProfileStatsRow(
            streak: userStats?.streak ?? 0,
            totalMiles: userStats?.totalMiles ?? 0,
            friendCount: friendCount
        ) {
            UserFriendsListView(
                userId: user.user_id,
                ownerName: user.username ?? user.displayName,
                friendService: friendService
            )
        }
    }

    // MARK: - Tab Content

    /// Today's snapshot + week chart + daily challenge + recent workouts.
    /// Default landing tab — the most time-sensitive info.
    @ViewBuilder
    private var activityTabContent: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            if !isCurrentUser(), friendService.isFriend(user) {
                friendTodayProgressCard
            }
            if !isCurrentUser(), !friendWorkouts.isEmpty {
                Last7DaysChart(workouts: friendWorkouts)
            }
            if let today = friendTodayChallenge {
                FriendTodayChallengeRow(today: today)
            }
            if !friendWorkouts.isEmpty {
                VStack(spacing: MADTheme.Spacing.md) {
                    FriendWorkoutsSection(
                        workouts: friendWorkouts,
                        onWorkoutTap: { workout in selectedWorkout = workout }
                    )
                    if canLoadMore && !isLoadingMoreWorkouts {
                        loadMoreButton
                    }
                }
            }
        }
    }

    /// Performance metrics (streak, total miles, best pace, best day, etc.)
    @ViewBuilder
    private var statsTabContent: some View {
        FriendStatsView(user: user, stats: userStats)
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

    // MARK: - Action Row (Nudge + Compete)

    /// Side-by-side pills for the two main actions you can take on a
    /// friend's profile. Nudge is hidden when the friend has already
    /// completed today; in that case Compete takes full width alone.
    @ViewBuilder
    private var actionRow: some View {
        let nudgeIsAvailable: Bool = {
            guard let status = nudgeStatus else { return false }
            return !status.has_completed_mile
        }()

        HStack(spacing: 8) {
            if nudgeIsAvailable {
                nudgeProfileButton
            }
            competeTogetherButton
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    // MARK: - Today Progress
    /// Today's distance + completion + streak. Renders only for friends (not
    /// self, not strangers) since the data comes from the nudge-status fetch
    /// which is gated on friendship.
    @ViewBuilder
    private var friendTodayProgressCard: some View {
        if let status = nudgeStatus {
            let today = status.today_miles ?? 0
            let goal: Double = 1.0
            let progress = min(today / goal, 1.0)
            let isComplete = status.has_completed_mile
            let streak = status.current_streak ?? 0
            let remaining = max(0, goal - today)

            HStack(spacing: MADTheme.Spacing.md) {
                // Progress ring with miles in the center.
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 5)
                        .frame(width: 72, height: 72)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            isComplete ? Color.green : Color.orange,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 72, height: 72)
                    VStack(spacing: 0) {
                        Text(String(format: today >= 10 ? "%.1f" : "%.2f", today))
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("mi")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                        .foregroundColor(.white.opacity(0.5))

                    HStack(spacing: 6) {
                        Text(isComplete ? "Goal complete" : String(format: "%.2f mi to go", remaining))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(isComplete ? .green : .white)
                            .lineLimit(1)
                        if streak > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("\(streak)")
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                            }
                            .foregroundColor(.orange)
                        }
                    }

                    Text(isComplete
                        ? String(format: "%.2f mi · Goal 1 mi", today)
                        : String(format: "%d%% of today's mile", Int(progress * 100)))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isComplete ? Color.green.opacity(0.3) : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            )
        } else {
            // Loading skeleton while nudge status fetches.
            HStack(spacing: MADTheme.Spacing.md) {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 60, height: 9)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 140, height: 13)
                }
                Spacer()
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
            if status.already_nudged_today {
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
                    FlexNudgeTracker.markFriendNudgeSent(friendId: user.user_id)
                    // Preserve existing miles/completion in the optimistic update.
                    nudgeStatus = NudgeStatusResponse(
                        can_nudge: false,
                        has_completed_mile: nudgeStatus?.has_completed_mile ?? false,
                        already_nudged_today: true,
                        today_miles: nudgeStatus?.today_miles,
                        current_streak: nudgeStatus?.current_streak
                    )
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showProfileNudgeFeedback(NudgeFeedback(
                        icon: "bell.badge.fill",
                        message: "Nudge sent to \(user.displayName)!",
                        isError: false
                    ))
                }
            } catch {
                await MainActor.run {
                    isNudging = false
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    showProfileNudgeFeedback(NudgeFeedback(
                        icon: "xmark.circle.fill",
                        message: "Couldn't send nudge",
                        isError: true
                    ))
                }
            }
        }
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

    // MARK: - Friend Action Button
    private var friendActionButton: some View {
        let title = getActionButtonTitle()
        let style = getActionButtonStyle()

        return FriendActionButton(
            title: title,
            style: style,
            isLoading: actionInProgress,
            action: isCurrentUser() ? {} : handleFriendAction
        )
    }

    // MARK: - Load More Button
    private var loadMoreButton: some View {
        Button {
            loadMoreWorkouts()
        } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                if isLoadingMoreWorkouts {
                    ProgressView()
                        .tint(MADTheme.Colors.madRed)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
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
        .disabled(isLoadingMoreWorkouts)
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
                    let hasCompletedGoalToday = todayMiles >= goalMiles && goalMiles > 0

                    userStats = UserStats(
                        streak: stats.streak,
                        totalMiles: stats.totalMiles,
                        fastestMilePace: fastestMilePace,
                        mostMilesInOneDay: mostMilesInOneDay,
                        hasCompletedGoalToday: hasCompletedGoalToday,
                        goalMiles: goalMiles
                    )

                    friendWorkouts = workouts
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

    private func refreshFriendshipStatus() {
        Task {
            await friendService.refreshAllData()
        }
    }

    private func getActionButtonTitle() -> String {
        if isCurrentUser() {
            return "Your Profile"
        } else if friendService.isFriend(user) {
            return "Friends"
        } else if friendService.hasPendingRequest(from: user) {
            return "Accept Request"
        } else if friendService.hasSentRequest(to: user) {
            return "Request Sent"
        } else {
            return "Add Friend"
        }
    }

    private func getActionButtonStyle() -> FriendActionStyle {
        if isCurrentUser() {
            return .secondary
        } else if friendService.isFriend(user) {
            return .success
        } else if friendService.hasPendingRequest(from: user) {
            return .primary
        } else if friendService.hasSentRequest(to: user) {
            return .secondary
        } else {
            return .primary
        }
    }

    private func isCurrentUser() -> Bool {
        guard let currentUserId = UserDefaults.standard.string(forKey: "backendUserId") else {
            return false
        }
        return user.user_id == currentUserId
    }

    private func handleFriendAction() {
        if isCurrentUser() { return }

        if friendService.isFriend(user) {
            return
        } else if friendService.hasPendingRequest(from: user) {
            handleAcceptRequest()
        } else if friendService.hasSentRequest(to: user) {
            return
        } else {
            handleSendRequest()
        }
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

    private func loadMoreWorkouts() {
        guard !isLoadingMoreWorkouts else { return }

        let newLimit = workoutLimit + 10
        isLoadingMoreWorkouts = true

        Task {
            do {
                let workouts = try await friendService.fetchRecentWorkouts(for: user.user_id, limit: newLimit)

                await MainActor.run {
                    withAnimation(MADTheme.Animation.standard) {
                        friendWorkouts = workouts
                        workoutLimit = newLimit
                    }
                    isLoadingMoreWorkouts = false
                }
            } catch {
                await MainActor.run {
                    print("[UserProfileDetailView] Failed to load more workouts: \(error)")
                    isLoadingMoreWorkouts = false
                }
            }
        }
    }
}

// MARK: - Friend Workout Detail Sheet

struct FriendWorkoutDetailSheet: View {
    let workout: FriendWorkout
    @Environment(\.dismiss) private var dismiss

    private var pace: String {
        guard workout.distance > 0, workout.totalDuration > 0 else { return "N/A" }
        let minutesPerMile = (workout.totalDuration / 60.0) / workout.distance
        let minutes = Int(minutesPerMile)
        let seconds = Int((minutesPerMile - Double(minutes)) * 60)
        return String(format: "%d:%02d /mi", minutes, seconds)
    }

    private var workoutColor: Color {
        switch workout.workoutType.lowercased() {
        case "running": return MADTheme.Colors.madRed
        case "walking": return .blue
        case "cycling": return .green
        case "hiking": return .orange
        default: return MADTheme.Colors.madRed
        }
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

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        // Hero card
                        VStack(spacing: MADTheme.Spacing.md) {
                            // Manual/edited warning banner
                            if workout.isManualOrEdited {
                                ManualWorkoutBanner(source: workout.source)
                            }

                            // Workout type badge
                            HStack(spacing: MADTheme.Spacing.sm) {
                                Image(systemName: workoutIcon)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(workout.workoutType.capitalized)
                                    .font(MADTheme.Typography.smallBold)
                            }
                            .foregroundColor(workoutColor)
                            .padding(.horizontal, MADTheme.Spacing.md)
                            .padding(.vertical, MADTheme.Spacing.xs + 2)
                            .background(
                                Capsule()
                                    .fill(workoutColor.opacity(0.15))
                            )

                            // Distance
                            Text(workout.formattedDistance)
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)

                            // Date
                            Text(workout.formattedDate)
                                .font(MADTheme.Typography.body)
                                .foregroundColor(.secondary)
                        }
                        .padding(MADTheme.Spacing.lg)
                        .frame(maxWidth: .infinity)
                        .madLiquidGlass()

                        // Stats row
                        HStack(spacing: MADTheme.Spacing.sm) {
                            DashboardStatBox(
                                title: "Duration",
                                value: workout.formattedDuration,
                                icon: "clock.fill",
                                color: .orange
                            )

                            DashboardStatBox(
                                title: "Pace",
                                value: pace,
                                icon: "speedometer",
                                color: .green
                            )

                            if let calories = workout.calories, calories > 0 {
                                DashboardStatBox(
                                    title: "Calories",
                                    value: "\(Int(calories))",
                                    icon: "flame.fill",
                                    color: MADTheme.Colors.madRed
                                )
                            }
                        }
                    }
                    .padding(MADTheme.Spacing.md)
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

    /// Look up the challenge metadata so we can show its name + icon instead
    /// of a generic "Completed / Not yet". Falls back to neutral styling when
    /// the backend returns a key the local catalog doesn't know.
    private var challenge: DailyChallenge? {
        guard let key = today.challengeKey else { return nil }
        return DailyChallengeCatalog.byKey(key)
    }

    var body: some View {
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
                if let challenge = challenge {
                    Text(challenge.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                } else {
                    Text("Today's challenge")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
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
        if let challenge = challenge { return challenge.icon }
        return today.completed ? "checkmark" : "hourglass"
    }

    private var iconGradient: [Color] {
        if let challenge = challenge {
            return challenge.gradient
        }
        return today.completed
            ? [.green, .green.opacity(0.8)]
            : [.white.opacity(0.2), .white.opacity(0.1)]
    }
}

// MARK: - Last 7 Days Mini Chart

/// Bar chart of the friend's last 7 days of miles. Aggregates from
/// `friendWorkouts` rather than fetching new data — instant render, no extra
/// request. Goal-hit days are green, partial days orange, zeros muted; today
/// is ringed so users orient themselves at a glance.
struct Last7DaysChart: View {
    let workouts: [FriendWorkout]

    private let goalMiles: Double = 1.0
    private let calendar = Calendar.current

    /// Selected day for the inline detail panel. Tapping a bar toggles
    /// selection — second tap on the same day closes the panel.
    @State private var selectedDay: Date?

    /// Map of date (start of day) → total miles for that day, drawn from
    /// the friend's recent workouts. Only includes the last 7 days.
    private var milesByDay: [Date: Double] {
        let cutoff = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: Date()) ?? Date())
        var result: [Date: Double] = [:]
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

    /// Tallest bar's value — used to scale the rest. Min of 1 mile so a
    /// week with one short run doesn't look like a wall.
    private var maxValue: Double {
        max(milesByDay.values.max() ?? 0, 1.0)
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
            .frame(height: 92)

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
        let didHit = miles >= goalMiles
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let color: Color = miles == 0
            ? Color.white.opacity(0.12)
            : (didHit ? .green : .orange)

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Second tap on the same bar closes the detail panel.
            if isSelected {
                selectedDay = nil
            } else {
                selectedDay = day
            }
        } label: {
            VStack(spacing: 6) {
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
    /// activity, surfaces a friendly "no miles" message instead.
    @ViewBuilder
    private func dayDetailPanel(for day: Date) -> some View {
        let dayWorkouts = workouts.compactMap { workout -> FriendWorkout? in
            guard let workoutDay = parseDay(workout.date) else { return nil }
            return calendar.isDate(workoutDay, inSameDayAs: day) ? workout : nil
        }
        let total = dayWorkouts.reduce(0.0) { $0 + $1.distance }
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
                    .foregroundColor(total >= goalMiles ? .green : (total > 0 ? .orange : .white.opacity(0.4)))
            }

            if dayWorkouts.isEmpty {
                Text("No miles logged")
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
        switch type.lowercased() {
        case "running": return .red
        case "walking": return .blue
        case "cycling": return .green
        case "hiking": return .brown
        default: return .gray
        }
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
