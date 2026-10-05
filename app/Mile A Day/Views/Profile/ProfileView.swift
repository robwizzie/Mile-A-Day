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
    /// The Share Studio on the day — streak, Flamey, stats — from the one
    /// screen that is ABOUT your streak. The QR button beside it shares the
    /// PROFILE (a way to add you), which is a different thing.
    @State private var showingShareStudio = false
    @State private var showingRouteHeatmap = false
    /// Daily goal editor, reachable from the Activity tab's goal row — the
    /// same sheet Settings opens, so there is one place the number is set.
    /// Sender tapped in "Recent hypes" — opens their profile.
    @State private var hypeProfileUser: BackendUser?
    /// "See all" on Recent Hypes — the full received list.
    @State private var showingAllHypes = false
    /// How many hypes the Activity card shows before "See all".
    private static let hypePreviewCount = 3

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
    @State private var ownLast7RefreshTask: Task<Void, Never>?
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
                            streakDoneToday: ownGoalDoneToday,
                            streakSavedToday: ownSavedToday,
                            // The Miles tile owns lifetime miles now (the
                            // banner chip and the Performance card are gone),
                            // so it is also the door to the Total Miles screen.
                            onTapMiles: { activeSheet = .totalMiles }
                        ) {
                            FriendsListView(friendService: friendService)
                        }

                        // Token shelf — your minted set, right under the numbers
                        // it protects. Hidden until streak features are active.
                        if let tokens = tokensState.payload {
                            profileTokenShelf(tokens)
                        }

                        // Flamey's Closet is no longer a header row here: it is
                        // reached from Settings and the Fun hero's Closet pill.

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
            scheduleOwnLocalLast7Refresh()
        }
        .onChange(of: healthManager.todaysDistance) {
            scheduleOwnLocalLast7Refresh()
        }
        .onChange(of: dedupOverrides.countAnyway) {
            scheduleOwnLocalLast7Refresh()
        }
        .onChange(of: dedupOverrides.excludeAnyway) {
            scheduleOwnLocalLast7Refresh()
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
        .task {
            // The medal shelf above refreshes from the server; the lifetime
            // total those medals are MEASURED against has to land with it or
            // this screen contradicts itself — a 500 Mile Club medal over a
            // hero chip still counting "27 to go". The Dashboard and Friends
            // tabs already call this; the profile is the screen that actually
            // prints the number.
            await SelfStatsRefresher.refreshBackendStats(userManager: userManager)
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
            await RecalibrateMedals.refresh(userManager: userManager, newBadgeIds: outcome.newBadgeIds)

            let dayWord = outcome.streak == 1 ? "day" : "days"
            let workoutWord = outcome.workoutsPushed == 1 ? "workout" : "workouts"
            var message =
                "Your streak is now \(outcome.streak) \(dayWord). We re-checked \(outcome.workoutsPushed) recent \(workoutWord) and made sure they're all saved to your account."
            if let medals = RecalibrateMedals.sentence(for: outcome.newBadgeIds) {
                message += " " + medals
            }
            recalibrateResultMessage = message
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

    /// The recent record — the week, walks, streaks, hypes. Mirrors the
    /// friend profile's Activity tab role.
    @ViewBuilder
    private var ownActivityTabContent: some View {
        // Ordered by how close to NOW each block is: the week, then walks
        // with people, then streak history, then what friends said about it.
        // Today's goal and challenge are the Dashboard's — the avatar's goal
        // ring already carries the day here. Every card wears the same flat
        // chrome and caps label (`profileCard` / `ProfileCardLabel`).
        VStack(spacing: MADTheme.Spacing.md) {
            // First, when today is token-covered: the one screen where a
            // streak that went up sits beside a mile the owner knows they
            // haven't run, and the answer has to be in that same glance.
            if let saved = ownSavedToday {
                SavedTodayBanner(day: saved, isSelf: true) { showTokenSheet = true }
            }
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
            HStack {
                ProfileCardLabel(text: "RECENT HYPES")
                Spacer()
                if receivedHypes.count > Self.hypePreviewCount {
                    Button {
                        MADHaptics.tap()
                        showingAllHypes = true
                    } label: {
                        Text("See all")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(MADTheme.Colors.madRed)
                    }
                    .buttonStyle(.plain)
                }
            }

            hypeRows(Array(receivedHypes.prefix(Self.hypePreviewCount)))
        }
        .padding(MADTheme.Spacing.md)
        .profileCard()
        .sheet(item: $hypeProfileUser) { user in
            NavigationStack {
                UserProfileDetailView(user: user, friendService: friendService)
            }
        }
        .sheet(isPresented: $showingAllHypes) {
            allHypesSheet
        }
    }

    /// The full received list, same rows as the card. A row tap closes this
    /// sheet FIRST and then opens the sender's profile from the card's own
    /// sheet — two sheets can't be up on one node at once.
    private var allHypesSheet: some View {
        NavigationStack {
            ScrollView {
                hypeRows(receivedHypes, dismissFirst: true)
                    .padding(MADTheme.Spacing.md)
                    .profileCard()
                    .padding(MADTheme.Spacing.md)
                    .lockedToScrollWidth()
            }
            .scrollContentBackground(.hidden)
            .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
            .navigationTitle("Hypes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingAllHypes = false }
                }
            }
        }
    }

    private func hypeRows(_ hypes: [ReceivedHype], dismissFirst: Bool = false) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(hypes.enumerated()), id: \.element.id) { index, hype in
                Button {
                    MADHaptics.tap()
                    let user = BackendUser(
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
                    if dismissFirst {
                        showingAllHypes = false
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            hypeProfileUser = user
                        }
                    } else {
                        hypeProfileUser = user
                    }
                } label: {
                    recentHypeRow(hype)
                }
                .buttonStyle(.plain)
                if index < hypes.count - 1 {
                    Divider().overlay(Color.white.opacity(0.06)).padding(.leading, 52)
                }
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
        // Memoised parse (fractional, then whole seconds) — a formatter per
        // row per body pass was the cost here.
        guard let date = RelativeTime.date(from: iso) else { return "" }
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
            // Gear, not performance — but "how many miles on these" is a
            // stat, and this is the one tab that is only ever your own.
            ShoesProfileSection()
            routeHeatmapRow
        }
    }

    /// Entry point into the full-screen personal route heatmap — a slim row
    /// at the foot of the tab, not a card competing with the stats above it.
    private var routeHeatmapRow: some View {
        Button {
            MADHaptics.tap()
            showingRouteHeatmap = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "map.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MADTheme.Colors.madRed)
                    .accessibilityHidden(true)
                Text("Route Heatmap")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .profileCard()
            .contentShape(Rectangle())
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

    /// `todaysDistance` publishes every few seconds during a walk, and a
    /// workout landing moves several of these inputs at once — coalesce the
    /// burst into one rebuild.
    private func scheduleOwnLocalLast7Refresh() {
        ownLast7RefreshTask?.cancel()
        ownLast7RefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            refreshOwnLocalLast7Activity()
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
        // A workout's local day is the start of its START date, so anything
        // starting before the oldest day can't land in the window — skip it
        // before the registry/dedup work rather than walking all of history.
        let windowStart = days.first ?? today

        var grouped: [Date: [HKWorkout]] = [:]
        var seenIds = Set<String>()

        for workout in healthManager.cachedWorkouts where workout.startDate >= windowStart {
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
    /// ring and the streak tile, so they can't disagree.
    private var ownGoalDoneToday: Bool {
        let goal = userManager.currentUser.goalMiles
        return (goal > 0 && ProgressCalculator.isGoalCompleted(current: healthManager.todaysDistance, goal: goal))
            || userManager.currentUser.isStreakActiveToday
    }

    /// A token holding TODAY, from the server's own resolution of the user's
    /// local day (`today_covered`) — never re-derived here, because a device
    /// a timezone away from the one the server files `local_date` under would
    /// pick the wrong day. Suppressed once the mile is genuinely in: the
    /// server refunds the coverage on that upload, and until the next stats
    /// read lands the payload still carries it. ONE rule for the goal ring,
    /// the streak tile and the saved-today banner, like `ownGoalDoneToday`.
    private var ownSavedToday: CoveredDate? {
        guard !ownGoalDoneToday else { return nil }
        return tokensState.payload?.today_covered
    }

    /// Banner (photo or gradient preset) with the avatar in today's goal ring
    /// hanging off it, and the wordmark + share/edit buttons riding the
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
            goalSavedToday: ownSavedToday,
            topInset: topInset,
            onTapAvatar: { showingEditProfile = true }
        ) {
            ownAvatarImage
        } topBar: {
            HStack(alignment: .center) {
                ProfileWordmark()
                Spacer()
                // Two controls: Share (streak card or QR) and Edit. Settings
                // lives behind the Dashboard gear only — ONE door to one page.
                HStack(spacing: 8) {
                    ProfileBannerMenu(systemImage: "square.and.arrow.up", accessibilityLabel: "Share") {
                        Button {
                            MADHaptics.action()
                            showingShareStudio = true
                        } label: {
                            Label("Share my streak", systemImage: "flame")
                        }
                        Button {
                            showingShareProfile = true
                        } label: {
                            Label("My QR code", systemImage: "qrcode")
                        }
                    }
                    ProfileBannerButton(systemImage: "pencil", accessibilityLabel: "Edit profile") {
                        showingEditProfile = true
                    }
                }
            }
        }
        .onAppear {
            loadProfileImage()
        }
        .sheet(isPresented: $showingShareStudio) {
            EnhancedShareView(
                user: userManager.currentUser,
                currentDistance: healthManager.todaysDistance,
                progress: progress ?? 0,
                isGoalCompleted: complete,
                fastestPace: 0,
                mostMiles: 0
            )
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
                    title: "Active Days",
                    value: activeDayStats.map { $0.days.formatted(.number.grouping(.automatic)) } ?? "—",
                    icon: "calendar.badge.checkmark",
                    iconColor: .orange,
                    backgroundColor: .orange.opacity(0.1)
                )

                MADStatCard(
                    title: "Avg / Active Day",
                    value: activeDayStats.map { ($0.miles / Double($0.days)).distanceFormatted } ?? "—",
                    icon: "chart.bar.fill",
                    iconColor: .purple,
                    backgroundColor: .purple.opacity(0.1)
                )
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }


    /// Days with counted miles and the miles on them — see
    /// `HealthKitManager.activeDayStats`. Nil until the index exists.
    private var activeDayStats: (days: Int, miles: Double)? { healthManager.activeDayStats }

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

                // A 36pt disc: the glyph grows a little, the disc doesn't.
                Image(systemName: icon)
                    .madFont(size: 15, weight: .medium, maxScale: 1.3)
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Both are `String` properties, so `Text(_:)` would take them
                // verbatim; wrapping in a key looks each up in the String
                // Catalog and falls back to the text itself when it isn't
                // there (computed subtitles like "1.0 mi per day").
                //
                // MADTheme.Typography.body / .caption, scaled (Dynamic Type):
                // same size, weight and design at the default text size.
                Text(LocalizedStringKey(title))
                    .madFont(size: 17, weight: .medium, design: .rounded)
                    .foregroundColor(.primary)

                Text(LocalizedStringKey(subtitle))
                    .madFont(size: 12, weight: .regular, design: .rounded)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .madFont(size: 12, weight: .medium, maxScale: 1.5)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, MADTheme.Spacing.xs)
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
