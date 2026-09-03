import SwiftUI
import HealthKit

struct ProfileView: View {
    @Environment(\.appStateManager) var appStateManager
    @ObservedObject var userManager: UserManager
    @ObservedObject var healthManager: HealthKitManager
    /// Streak-token state — drives the Pure Flame (natural streak) seal and
    /// the profile token shelf.
    @ObservedObject private var tokensState = StreakTokensState.shared
    @ObservedObject private var dedupOverrides = WorkoutDedupOverrides.shared
    @State private var showTokenSheet = false
    @State private var showPureFlameInfo = false

    @State private var activeSheet: ProfileSheetType?
    @State private var showingEditProfile = false
    @State private var showingLogoutConfirmation = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?
    @State private var currentProfileImage: UIImage?
    @State private var showingManagePins = false
    @State private var pinnedBadgeForDetail: Badge?
    @State private var isShowingBadgeDetail = false
    @State private var isRecalibratingStreak = false
    @State private var recalibrateResultMessage: String?
    @State private var showingShareProfile = false
    @State private var showingSettings = false
    @State private var showingRouteHeatmap = false
    /// Daily goal editor, reachable from the Activity tab's goal row — the
    /// same sheet Settings opens, so there is one place the number is set.
    @State private var showGoalSheet = false
    /// Sender tapped in "Recent hypes" — opens their profile.
    @State private var hypeProfileUser: BackendUser?

    // Friends count shown in the header (Instagram-style), tappable through to
    // the friends list. Owns one FriendService for the count + the list link.
    @StateObject private var friendService = FriendService()
    @State private var ownFriendCount: Int?

    // "You got hyped" — recent hypes received, surfaced on the profile so they
    // aren't push-only.
    @State private var receivedHypes: [ReceivedHype] = []
    @State private var hasLoadedHypes = false

    // Counted local workouts for the rolling "Last 7 Days" chart on the
    // Activity tab. Friend profiles still use server rows; your own profile can
    // use richer HealthKit metadata to hide Google Health duplicate rows.
    @State private var ownWorkouts: [FriendWorkout] = []
    // Locally deduped per-day totals for the chart. The server can still hold
    // older Google Health duplicate rows, so your own profile should trust the
    // HealthKit-backed local dedupe path instead.
    @State private var ownDayTotals: [FriendDayMiles]?

    // Section tabs — mirrors UserProfileDetailView's structure so navigating
    // between own profile and friend profile feels consistent. Own profile
    // adds a 4th Settings tab since you can only manage your own account.
    @State private var profileTab: OwnProfileTab = .activity

    enum OwnProfileTab: Hashable {
        case activity, posts, stats, badges
    }

    enum ProfileSheetType: String, Identifiable {
        case totalMiles, fastestPace, mostMiles
        case usernameSetup
        var id: String { rawValue }
    }

    var body: some View {
        // The banner runs under the status bar, so the scroll ignores the top
        // safe area and the hero pads its own top bar by that inset.
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    profileHero(topInset: geo.safeAreaInsets.top)

                    VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                        ProfileIdentityBlock(
                            username: userManager.currentUser.username,
                            displayName: ownDisplayName,
                            bio: userManager.currentUser.bio,
                            // Pure Flame seal when the current streak is 100%
                            // natural (no token rescues). Server-gated: hidden
                            // until streak features are live for this user.
                            showsPureFlame: tokensState.payload?.natural_streak == true
                                && userManager.currentUser.streak > 0,
                            onPureFlame: { showPureFlameInfo = true }
                        )

                        // Streak · Miles · Friends. Friends is tappable through
                        // to the friends list / leaderboard.
                        ProfileStatTiles(
                            streak: userManager.currentUser.streak,
                            totalMiles: userManager.currentUser.totalMiles,
                            friendCount: ownFriendCount,
                            streakDoneToday: ownGoalDoneToday
                        ) {
                            FriendsListView(friendService: friendService)
                        }

                        // Token shelf — your minted set, right under the numbers
                        // it protects. Hidden until streak features are active.
                        if let tokens = tokensState.payload {
                            profileTokenShelf(tokens)
                        }

                        // Same four sections as a friend's profile, Activity first.
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
                    .padding(.horizontal, MADTheme.Spacing.screenGutter)
                    .padding(.top, 6)

                    Group {
                        switch profileTab {
                        case .activity: ownActivityTabContent
                        case .posts: ownPostsTabContent
                        case .stats: ownStatsTabContent
                        case .badges: ownBadgesTabContent
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: profileTab)
                    .padding(.horizontal, MADTheme.Spacing.screenGutter)
                    .padding(.top, MADTheme.Spacing.md)
                }
                .padding(.bottom, 100)
                .lockedToScrollWidth()
            }
            .ignoresSafeArea(edges: .top)
            .scrollContentBackground(.hidden)
        }
        .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
        .sheet(isPresented: $showPureFlameInfo) {
            PureFlameInfoSheet()
        }
        .task {
            // A banner or bio set on another phone shows up here.
            await userManager.refreshProfileFromBackend()
        }
        .toolbar(.hidden, for: .navigationBar)
        // Pushed in the tab's NavigationStack — consistent with the
        // no-slide-down direction for navigational destinations.
        .navigationDestination(isPresented: $showingShareProfile) {
            ShareProfileView()
        }
        .navigationDestination(isPresented: $showingSettings) {
            // ONE settings page, shared with the Dashboard's gear. It owns its
            // own confirmations and account actions: a modal attached to THIS
            // view can't present while that page is pushed on top, which is how
            // Sign Out came to look like a no-op until you hit Back.
            MADSettingsView(
                userManager: userManager,
                healthManager: healthManager,
                friendService: friendService
            )
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .totalMiles:
                TotalMilesDetailView(userManager: userManager, healthManager: healthManager)
            case .fastestPace:
                FastestPaceDetailView(healthManager: healthManager, userManager: userManager)
            case .mostMiles:
                MostMilesDetailView(miles: userManager.currentUser.mostMilesInOneDay, healthManager: healthManager)
            case .usernameSetup:
                UsernameSetupView()
                    .environmentObject(userManager)
            }
        }
        // Edit Profile is a real screen, not a form sheet.
        .fullScreenCover(isPresented: $showingEditProfile) {
            EditProfileView(userManager: userManager) {
                showingEditProfile = false
                currentProfileImage = getCustomProfileImage() ?? getAppleProfileImage()
            }
        }
        .sheet(isPresented: $showingManagePins) {
            ManagePinnedBadgesSheet(userManager: userManager)
        }
        .sheet(isPresented: $showingRouteHeatmap) {
            RouteHeatmapView()
        }
        .task {
            await loadOwnFriendCount()
        }
        .task {
            await loadReceivedHypes()
        }
        .task {
            refreshOwnLocalLast7Activity()
        }
        .onChange(of: healthManager.cachedWorkouts.count) {
            refreshOwnLocalLast7Activity()
        }
        .onChange(of: healthManager.todaysDistance) {
            refreshOwnLocalLast7Activity()
        }
        .onChange(of: dedupOverrides.countAnyway) {
            refreshOwnLocalLast7Activity()
        }
        .onChange(of: dedupOverrides.excludeAnyway) {
            refreshOwnLocalLast7Activity()
        }
        .navigationDestination(isPresented: $isShowingBadgeDetail) {
            // Match the BadgesView navigation-push presentation so tapping a
            // pinned badge feels identical to tapping one from the grid.
            if let badge = pinnedBadgeForDetail {
                BadgeDetailView(badge: badge, userManager: userManager)
            }
        }
        .task {
            await userManager.refreshBadgesFromServer()
        }
        // Sign Out / Delete Account / Recalibrate confirmations live on
        // ProfileSettingsView — every one of their buttons is over there, and a
        // modal attached to this view can't present while that page is pushed.
    }

    // MARK: - Recalibrate Streak

    /// Re-push the phone's local workouts to the server and recompute the streak.
    /// Recovers a streak that reads too low because a manual/backdated workout
    /// never reached the backend. Local HealthKit is the source of truth, so this
    /// only ever fills server gaps — it can't shorten a legitimately broken streak.
    private func recalibrateStreak() async {
        guard !isRecalibratingStreak else { return }
        isRecalibratingStreak = true
        defer { isRecalibratingStreak = false }

        do {
            let outcome = try await WorkoutSyncService.shared.recalibrateStreak(
                localStreakDays: healthManager.retroactiveStreak
            )
            userManager.updateStreakFromBackend(outcome.streak)

            let dayWord = outcome.streak == 1 ? "day" : "days"
            let workoutWord = outcome.workoutsPushed == 1 ? "workout" : "workouts"
            recalibrateResultMessage =
                "Your streak is now \(outcome.streak) \(dayWord). We re-checked \(outcome.workoutsPushed) recent \(workoutWord) and made sure they're all saved to your account."
        } catch {
            recalibrateResultMessage =
                "We couldn't finish recalibrating right now. Please check your connection and try again."
        }

        // Steps live in a separate daily_steps table that only ever finalizes
        // today (and yesterday once at rollover), so a day left partial by a late
        // Watch sync is never revisited. Re-post the recent window; the backend
        // keeps the GREATEST, so this back-corrects a stale day and never lowers a
        // good one. Best-effort and independent of the streak result above.
        await DailyStepsSyncService.shared.backfillRecentDays(30)
    }

    // MARK: - Profile Header

    // MARK: - Tab Content

    /// Today's snapshot — streak + goal completion. Mirrors the friend
    /// profile's Activity tab role: "what's happening right now".
    @ViewBuilder
    private var ownActivityTabContent: some View {
        // Ordered by how close to NOW each block is: today's goal and
        // challenge, then the week, then walks with people, then streak
        // history, then what friends said about it. Every card wears the same
        // flat chrome and caps label (`profileCard` / `ProfileCardLabel`).
        VStack(spacing: MADTheme.Spacing.md) {
            dailyGoalRow
            OwnTodayChallengeCard(healthManager: healthManager, userManager: userManager)
            if !ownWorkouts.isEmpty || !(ownDayTotals?.isEmpty ?? true) {
                Last7DaysChart(
                    workouts: ownWorkouts,
                    dayTotals: ownDayTotals,
                    coveredDays: tokensState.payload?.frozen_dates,
                    isSelf: true
                )
            }
            // Walks you've taken WITH people. On the Activity tab rather than
            // Stats because it's a record of what happened, not a performance
            // metric — and because it's the only place in the app outside the
            // start sheet that says what a buddy walk is.
            BuddyWalksSection()
            HallOfStreaksSection(
                userId: userManager.currentUser.backendUserId,
                isSelf: true
            )
            if !receivedHypes.isEmpty {
                recentHypesSection
            }
        }
    }

    /// "You got hyped" — recent 👏 reactions friends sent you. Each row opens
    /// the sender's profile, the way a likes list does.
    private var recentHypesSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            ProfileCardLabel(text: "RECENT HYPES")

            VStack(spacing: 0) {
                ForEach(Array(receivedHypes.prefix(8).enumerated()), id: \.element.id) { index, hype in
                    Button {
                        MADHaptics.tap()
                        hypeProfileUser = BackendUser(
                            user_id: hype.sender_id,
                            username: hype.username,
                            email: nil,
                            first_name: hype.first_name,
                            last_name: hype.last_name,
                            bio: nil,
                            profile_image_url: hype.profile_image_url,
                            apple_id: nil,
                            auth_provider: nil,
                            role: nil
                        )
                    } label: {
                        recentHypeRow(hype)
                    }
                    .buttonStyle(.plain)
                    if index < min(receivedHypes.count, 8) - 1 {
                        Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 52)
                    }
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .profileCard()
        .sheet(item: $hypeProfileUser) { user in
            NavigationStack {
                UserProfileDetailView(user: user, friendService: friendService)
            }
        }
    }

    private func recentHypeRow(_ hype: ReceivedHype) -> some View {
        HStack(spacing: 12) {
            AvatarView(
                name: hype.displayName,
                imageURL: hype.profile_image_url,
                size: 40
            )
            VStack(alignment: .leading, spacing: 2) {
                (Text(Image(systemName: "hands.clap.fill")).foregroundColor(.orange)
                    + Text("  ")
                    + Text(hype.displayName).fontWeight(.bold)
                    + Text(" \(hype.actionText)"))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
                Text(Self.relativeHypeTime(hype.created_at))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func loadReceivedHypes() async {
        guard !hasLoadedHypes else { return }
        do {
            receivedHypes = try await HypeService.received()
        } catch {
            print("[ProfileView] loadReceivedHypes failed: \(error)")
        }
        hasLoadedHypes = true
    }

    private static func relativeHypeTime(_ iso: String) -> String {
        let parse = ISO8601DateFormatter()
        parse.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parse.date(from: iso) ?? {
            parse.formatOptions = [.withInternetDateTime]
            return parse.date(from: iso)
        }()
        guard let date else { return "" }
        let secs = Date().timeIntervalSince(date)
        if secs < 60 { return "just now" }
        if secs < 3600 { return "\(Int(secs / 60))m ago" }
        if secs < 86400 { return "\(Int(secs / 3600))h ago" }
        return "\(Int(secs / 86400))d ago"
    }

    /// Performance metrics — same role as the friend profile's Stats tab.
    @ViewBuilder
    private var ownStatsTabContent: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            performanceSection
            RacePRsSection(userId: userManager.currentUser.backendUserId)
            // Beside the PRs rather than on its own screen: both answer "how
            // fast am I", and a race history buried a tap deeper is a race
            // history nobody reads. Self-scoped, so it's own-profile only.
            GhostRacesSection()
            routeHeatmapCard
        }
    }

    /// Entry point into the full-screen personal route heatmap.
    private var routeHeatmapCard: some View {
        Button {
            showingRouteHeatmap = true
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(MADTheme.Colors.madRed.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "map.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(MADTheme.Colors.madRed)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Route Heatmap")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.primary)
                    Text("Every walk and run, painted on one map")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        }
        .buttonStyle(ScaleButtonStyle())
    }

    /// Instagram-style grid of the user's own posts.
    @ViewBuilder
    private var ownPostsTabContent: some View {
        if let uid = userManager.currentUser.backendUserId {
            ProfilePostsGridView(userId: uid, isSelf: true)
        } else {
            Text("Sign in to see your posts.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, MADTheme.Spacing.xl)
        }
    }

    /// Pinned medals + manage button — friend profile's Badges tab shows
    /// a compare grid; own profile shows what's currently pinned with the
    /// ability to reorder / change selections.
    @ViewBuilder
    private var ownBadgesTabContent: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            PinnedBadgesShowcase(
                pinnedBadges: userManager.pinnedBadges,
                onManageTapped: { showingManagePins = true },
                onBadgeTapped: { badge in
                    pinnedBadgeForDetail = badge
                    isShowingBadgeDetail = true
                },
                ownerDisplayName: nil,
                onReorder: { from, to in
                    reorderPinnedBadges(from: from, to: to)
                }
            )
        }
    }


    private func loadOwnFriendCount() async {
        guard let userId = userManager.currentUser.backendUserId else { return }
        do {
            let list = try await friendService.getFriendsList(for: userId)
            await MainActor.run { ownFriendCount = list.count }
        } catch {
            print("[ProfileView] loadOwnFriendCount failed: \(error)")
        }
    }

    private func refreshOwnLocalLast7Activity() {
        let activity = makeOwnLocalLast7Activity()
        ownDayTotals = activity.dayTotals
        ownWorkouts = activity.workouts
    }

    private func makeOwnLocalLast7Activity() -> (dayTotals: [FriendDayMiles], workouts: [FriendWorkout]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
        let daysToInclude = Set(days)

        var grouped: [Date: [HKWorkout]] = [:]
        var seenIds = Set<String>()

        for workout in healthManager.cachedWorkouts {
            let id = workout.uuid.uuidString
            #if !os(watchOS)
            if DeletedWorkoutRegistry.contains(id) { continue }
            #endif
            guard seenIds.insert(id).inserted else { continue }

            let localDay = healthManager.localDay(for: workout)
            guard daysToInclude.contains(localDay) else { continue }
            grouped[localDay, default: []].append(workout)
        }

        var detailRows: [FriendWorkout] = []
        let userId = userManager.currentUser.backendUserId ?? userManager.currentUser.id.uuidString

        let dayTotals = days.map { day in
            let dayMiles: Double
            if let workouts = grouped[day], !workouts.isEmpty {
                let sorted = workouts.sorted { $0.endDate < $1.endDate }
                dayMiles = WorkoutDedup.totalMiles(sorted)
                detailRows.append(contentsOf: WorkoutDedup.counting(sorted).map { workout in
                    FriendWorkout(
                        id: workout.uuid.uuidString,
                        userId: userId,
                        date: Self.localDayFormatter.string(from: day),
                        distance: workout.madDistanceMiles,
                        totalDuration: workout.duration,
                        workoutType: Self.workoutTypeName(for: workout),
                        deviceEndDate: Self.isoFormatter.string(from: workout.endDate),
                        calories: nil,
                        source: nil,
                        hasRoute: false,
                        hasPhoto: false,
                        sourceBundleId: workout.sourceRevision.source.bundleIdentifier,
                        exclusionReason: nil,
                        duplicateDecision: nil
                    )
                })
            } else if calendar.isDateInToday(day), healthManager.hasFreshTodaysDistance {
                dayMiles = healthManager.todaysDistance
            } else {
                dayMiles = healthManager.workoutIndex?.totalMiles(for: day) ?? 0
            }

            return FriendDayMiles(
                date: Self.localDayFormatter.string(from: day),
                miles: dayMiles
            )
        }

        return (dayTotals, detailRows)
    }

    private static let localDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func workoutTypeName(for workout: HKWorkout) -> String {
        switch workout.workoutActivityType {
        case .running:
            return "running"
        case .walking:
            return "walking"
        case .cycling:
            return "cycling"
        case .hiking:
            return "hiking"
        default:
            return "other"
        }
    }

    /// "First Last" for the identity line, nil when the user hasn't set one.
    private var ownDisplayName: String? {
        let parts = [userManager.currentUser.firstName, userManager.currentUser.lastName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Is today's mile in? Clamp the goal first — the tolerance helper is
    /// vacuously true at 0. A locked device reads today's distance as 0, so
    /// the streak's own "done today" stamp also counts. ONE rule for the goal
    /// ring, the streak tile and the daily-goal row, so they can't disagree.
    private var ownGoalDoneToday: Bool {
        let goal = userManager.currentUser.goalMiles
        return (goal > 0 && ProgressCalculator.isGoalCompleted(current: healthManager.todaysDistance, goal: goal))
            || userManager.currentUser.isStreakActiveToday
    }

    /// Banner (photo or gradient preset) with the avatar in today's goal ring
    /// hanging off it, and the wordmark + QR/edit/settings buttons riding the
    /// top. Tapping the avatar opens Edit Profile, same as the pencil.
    private func profileHero(topInset: CGFloat) -> some View {
        let goal = userManager.currentUser.goalMiles
        let today = healthManager.todaysDistance
        let complete = ownGoalDoneToday
        let progress: Double? = goal > 0 ? min(today / goal, 1) : nil

        return ProfileHero(
            bannerURL: userManager.currentUser.profileBannerUrl,
            bannerStyle: ProfileBannerStyle.resolve(userManager.currentUser.profileBannerStyle),
            totalMiles: userManager.currentUser.totalMiles,
            // The next mile MEDAL, from the same badge list the Total Miles
            // screen reads — the chip and "Next Medal" can't disagree.
            milestoneThresholds: MileMilestones.thresholds(from: userManager.currentUser.getAllBadges()),
            goalProgress: progress,
            goalComplete: complete,
            topInset: topInset,
            onTapAvatar: { showingEditProfile = true }
        ) {
            ownAvatarImage
        } topBar: {
            HStack(alignment: .center) {
                ProfileWordmark()
                Spacer()
                HStack(spacing: 8) {
                    ProfileBannerButton(systemImage: "qrcode", accessibilityLabel: "Share profile") {
                        showingShareProfile = true
                    }
                    ProfileBannerButton(systemImage: "pencil", accessibilityLabel: "Edit profile") {
                        showingEditProfile = true
                    }
                    ProfileBannerButton(systemImage: "gearshape.fill", accessibilityLabel: "Settings") {
                        showingSettings = true
                    }
                }
            }
        }
        .onAppear {
            loadProfileImage()
        }
    }

    @ViewBuilder
    private var ownAvatarImage: some View {
        if let image = currentProfileImage ?? getCustomProfileImage() ?? getAppleProfileImage() {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            AvatarView(
                name: userManager.currentUser.name,
                imageURL: userManager.currentUser.profileImageUrl,
                size: 88
            )
        }
    }

    private func profileTokenShelf(_ tokens: StreakFeaturesPayload) -> some View {
        let ready = [
            tokens.double_down.held,
            tokens.streak_save.held,
            tokens.streak_assist.held,
        ].filter { $0 }.count

        return Button {
            showTokenSheet = true
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: -5) {
                    TokenMedallion(
                        kind: .doubleDown,
                        held: tokens.double_down.held,
                        progress: tokens.double_down.fraction,
                        size: 30
                    )
                    TokenMedallion(
                        kind: .save,
                        held: tokens.streak_save.held,
                        progress: tokens.streak_save.fraction,
                        size: 30
                    )
                    TokenMedallion(
                        kind: .assist,
                        held: tokens.streak_assist.held,
                        progress: tokens.streak_assist.fraction,
                        size: 30
                    )
                }
                .padding(.trailing, 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Streak Tokens")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(ready > 0 ? "\(ready) available" : "Building your safety net")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(ready > 0 ? 0.68 : 0.55))
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
        .sheet(isPresented: $showTokenSheet) {
            StreakTokensDetailView()
        }
    }

    // MARK: - Daily Goal Row

    /// The day's target and whether it's in. The streak number itself lives in
    /// the header tiles now, so this is only the goal — one compact row rather
    /// than the old two-card block.
    private var dailyGoalRow: some View {
        let done = ownGoalDoneToday
        let goalMiles = userManager.currentUser.goalMiles
        let remaining = max(0, goalMiles - healthManager.todaysDistance)
        // Remaining CEILs — never promise the goal is closer than it is.
        let remainingText = String(format: "%.2f to go", (remaining * 100).rounded(.up) / 100)
        let statusText = done ? "Done today" : remainingText
        let accent: Color = done ? .green : MADTheme.Colors.madRed

        return HStack(spacing: MADTheme.Spacing.md) {
            goalIcon(done: done, accent: accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("DAILY GOAL")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.5))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", goalMiles))
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                    Text("mi")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
            }

            Spacer()

            goalStatusPill(text: statusText, done: done)

            goalEditButton
        }
        .padding(14)
        .background(goalRowBackground)
        .sheet(isPresented: $showGoalSheet) {
            GoalSettingSheet(
                currentGoal: userManager.currentUser.goalMiles,
                onSave: { newGoal in
                    userManager.setDailyGoal(miles: newGoal)
                    // The widgets score today against the goal — mirror the
                    // App Group write Settings does, or the home screen keeps
                    // the old number.
                    WidgetDataStore.save(
                        todayMiles: healthManager.todaysDistance,
                        goal: newGoal
                    )
                }
            )
            .presentationDetents([.height(300)])
        }
    }

    /// Pencil that opens the goal editor. Lives on the row rather than behind
    /// Settings alone so the number is changeable where it's read.
    private var goalEditButton: some View {
        Button {
            MADHaptics.tap()
            showGoalSheet = true
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit daily goal")
    }

    private func goalIcon(done: Bool, accent: Color) -> some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.15))
                .frame(width: 40, height: 40)
            Image(systemName: done ? "checkmark" : "target")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(accent)
        }
    }

    private func goalStatusPill(text: String, done: Bool) -> some View {
        let fill: Color = done ? Color.green.opacity(0.12) : Color.white.opacity(0.06)
        let stroke: Color = done ? Color.green.opacity(0.3) : Color.white.opacity(0.12)
        return Text(text)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundColor(done ? .green : .white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
    }

    private var goalRowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }

    // MARK: - Performance Stats

    private var performanceSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("Performance")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MADTheme.Spacing.md) {
                Button {
                    activeSheet = .totalMiles
                } label: {
                    MADStatCard(
                        title: "Total Miles",
                        value: userManager.currentUser.totalMiles.milesFormatted,
                        icon: "map.fill",
                        iconColor: .blue,
                        backgroundColor: .blue.opacity(0.1)
                    )
                }
                .buttonStyle(ScaleButtonStyle())

                Button {
                    activeSheet = .fastestPace
                } label: {
                    MADStatCard(
                        title: "Best Pace",
                        value: formatPace(bestFastestMilePace),
                        icon: "timer",
                        iconColor: MADTheme.Colors.madRed,
                        backgroundColor: MADTheme.Colors.madRed.opacity(0.1)
                    )
                }
                .buttonStyle(ScaleButtonStyle())

                Button {
                    activeSheet = .mostMiles
                } label: {
                    MADStatCard(
                        title: "Best Day",
                        value: userManager.currentUser.mostMilesInOneDay.milesFormatted,
                        icon: "calendar",
                        iconColor: .green,
                        backgroundColor: .green.opacity(0.1)
                    )
                }
                .buttonStyle(ScaleButtonStyle())

                MADStatCard(
                    title: "Avg/Day",
                    value: String(format: "%.1f mi", userManager.currentUser.streak > 0 ? userManager.currentUser.totalMiles / Double(userManager.currentUser.streak) : 0),
                    icon: "chart.bar.fill",
                    iconColor: .purple,
                    backgroundColor: .purple.opacity(0.1)
                )
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }


    // MARK: - Helpers

    @MainActor
    private func performDeleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await userManager.deleteAccount()
            appStateManager.signOut()
        } catch {
            deleteAccountErrorMessage = error.localizedDescription
        }
    }

    /// Backend (workout_splits) is authoritative; HealthKit is fallback only.
    private var bestFastestMilePace: TimeInterval {
        if userManager.currentUser.fastestMilePace > 0 { return userManager.currentUser.fastestMilePace }
        return healthManager.fastestMilePace
    }

    /// Drag-to-reorder handler: moves the badge at `from` to position `to` in the
    /// current pinned list and persists by re-calling `setPinnedBadges`.
    private func reorderPinnedBadges(from: Int, to: Int) {
        var ids = userManager.pinnedBadges.map { $0.id }
        guard from >= 0, from < ids.count, to >= 0, to < ids.count, from != to else { return }
        let moved = ids.remove(at: from)
        ids.insert(moved, at: to)
        Task { @MainActor in
            await userManager.setPinnedBadges(ids)
        }
    }

    private func formatPace(_ pace: TimeInterval) -> String {
        guard pace > 0 else {
            return "N/A"
        }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func loadProfileImage() {
        if let urlPath = userManager.currentUser.profileImageUrl,
           let url = ProfileImageService.fullImageURL(for: urlPath) {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    await MainActor.run { currentProfileImage = image }
                } else {
                    await MainActor.run {
                        currentProfileImage = getCustomProfileImage() ?? getAppleProfileImage()
                    }
                }
            }
        } else {
            currentProfileImage = getCustomProfileImage() ?? getAppleProfileImage()
        }
    }

    private func getCustomProfileImage() -> UIImage? {
        if let data = UserDefaults.standard.data(forKey: "customProfileImage"),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }

    private func getAppleProfileImage() -> UIImage? {
        return userManager.getAppleProfileImage()
    }
}

// MARK: - Stat Card

struct MADStatCard: View {
    let title: String
    let value: String
    let icon: String
    let iconColor: Color
    let backgroundColor: Color
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
            }

            VStack(spacing: MADTheme.Spacing.xs) {
                Text(value)
                    .font(MADTheme.Typography.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(title)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(iconColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.md)
        .background(Color.white.opacity(0.05))
        .cornerRadius(MADTheme.CornerRadius.medium)
    }
}

// MARK: - Settings Row

struct MADSettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MADTheme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, MADTheme.Spacing.xs)
    }
}

// MARK: - Own Today's Challenge Card

/// Compact "today's daily challenge" status on your own profile — mirrors the
/// friend-profile row but adds a live progress bar and links into the full
/// Daily Challenges screen. Reads server-authoritative state from the service.
private struct OwnTodayChallengeCard: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager

    @State private var challenge: DailyChallenge?
    @State private var completed = false
    @State private var progress: Double = 0

    var body: some View {
        Group {
            if let challenge = challenge {
                NavigationLink {
                    DailyChallengesView(healthManager: healthManager, userManager: userManager)
                } label: {
                    card(challenge)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: ChallengeService.changedNotification)) { _ in
            refresh()
        }
    }

    private func card(_ challenge: DailyChallenge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: completed ? [.green, .green.opacity(0.8)] : challenge.gradient,
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: completed ? "checkmark" : challenge.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY'S CHALLENGE")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                        .foregroundColor(.white.opacity(0.5))
                    Text(challenge.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: completed ? "checkmark.circle.fill" : "hourglass")
                        .font(.system(size: 11, weight: .bold))
                    Text(completed ? "Done" : "In progress")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                }
                .foregroundColor(completed ? .green : .white.opacity(0.55))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(completed ? Color.green.opacity(0.12) : Color.white.opacity(0.06))
                        .overlay(Capsule().strokeBorder(
                            completed ? Color.green.opacity(0.3) : Color.white.opacity(0.12), lineWidth: 1))
                )
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: completed ? [.green, .green] : challenge.gradient,
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, min(progress, 1.0) * geo.size.width), height: 6)
                        .animation(.easeOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.1), lineWidth: 1))
        )
    }

    private func refresh() {
        guard let remote = ChallengeService.shared as? RemoteChallengeService else { return }
        challenge = remote.todayChallenge
        completed = remote.todayCompleted
        progress = remote.todayProgress
    }
}

#Preview {
    NavigationStack {
        ProfileView(
            userManager: UserManager(),
            healthManager: HealthKitManager()
        )
    }
    .environmentObject(AppStateManager())
}
