import SwiftUI

struct ProfileView: View {
    @Environment(\.appStateManager) var appStateManager
    @ObservedObject var userManager: UserManager
    @ObservedObject var healthManager: HealthKitManager

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

    // Friends count shown in the header (Instagram-style), tappable through to
    // the friends list. Owns one FriendService for the count + the list link.
    @StateObject private var friendService = FriendService()
    @State private var ownFriendCount: Int?

    // "You got hyped" — recent hypes received, surfaced on the profile so they
    // aren't push-only.
    @State private var receivedHypes: [ReceivedHype] = []
    @State private var hasLoadedHypes = false

    // Recent workouts for the rolling "Last 7 Days" chart on the Activity tab.
    // Same data + component the friend profile uses, so both read identically.
    @State private var ownWorkouts: [FriendWorkout] = []

    // Section tabs — mirrors UserProfileDetailView's structure so navigating
    // between own profile and friend profile feels consistent. Own profile
    // adds a 4th Settings tab since you can only manage your own account.
    @State private var profileTab: OwnProfileTab = .activity

    enum OwnProfileTab: Hashable {
        case activity, posts, stats, badges
    }

    enum ProfileSheetType: String, Identifiable {
        case totalMiles, fastestPace, mostMiles
        case usernameSetup, privacySettings
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            MADTabHeader(
                title: "Profile",
                actions: [
                    MADHeaderAction(id: "share", systemImage: "qrcode") {
                        showingShareProfile = true
                    },
                    MADHeaderAction(id: "edit", systemImage: "pencil") {
                        showingEditProfile = true
                    },
                    MADHeaderAction(id: "settings", systemImage: "gearshape.fill") {
                        showingSettings = true
                    }
                ]
            )

            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    // Profile Header (matches friend profile style)
                    profileHeader

                    // Tab picker — matches friend profile's 4-tab layout.
                    MADPillPicker(
                        selection: $profileTab,
                        options: [
                            .init(id: .activity, title: "Activity", systemImage: "flame.fill"),
                            .init(id: .posts, title: "Posts", systemImage: "square.grid.3x3.fill"),
                            .init(id: .stats, title: "Stats", systemImage: "chart.bar.fill"),
                            .init(id: .badges, title: "Badges", systemImage: "trophy.fill")
                        ]
                    )

                    Group {
                        switch profileTab {
                        case .activity: ownActivityTabContent
                        case .posts: ownPostsTabContent
                        case .stats: ownStatsTabContent
                        case .badges: ownBadgesTabContent
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: profileTab)
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.top, MADTheme.Spacing.sm)
                .padding(.bottom, 100)
            }
            .scrollContentBackground(.hidden)
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .toolbar(.hidden, for: .navigationBar)
        // Pushed in the tab's NavigationStack — consistent with the
        // no-slide-down direction for navigational destinations.
        .navigationDestination(isPresented: $showingShareProfile) {
            ShareProfileView()
        }
        .navigationDestination(isPresented: $showingSettings) {
            ProfileSettingsView(
                userManager: userManager,
                friendService: friendService,
                onLogout: { showingLogoutConfirmation = true },
                onDeleteAccount: { showingDeleteAccountConfirmation = true },
                onRecalibrateStreak: { Task { await recalibrateStreak() } },
                isRecalibratingStreak: isRecalibratingStreak,
                onPrivacySettings: { activeSheet = .privacySettings }
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
            case .privacySettings:
                PrivacySettingsView()
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
            await loadOwnWorkouts()
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
        .alert("Sign Out", isPresented: $showingLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                userManager.signOut()
                appStateManager.signOut()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Delete Account?", isPresented: $showingDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await performDeleteAccount() }
            }
        } message: {
            Text("This permanently deletes your account, workouts, streak history, friendships, and competition data. This cannot be undone.")
        }
        .alert(
            "Couldn't Delete Account",
            isPresented: Binding(
                get: { deleteAccountErrorMessage != nil },
                set: { if !$0 { deleteAccountErrorMessage = nil } }
            )
        ) {
            Button("OK") { deleteAccountErrorMessage = nil }
        } message: {
            Text(deleteAccountErrorMessage ?? "")
        }
        .alert(
            "Streak Recalibrated",
            isPresented: Binding(
                get: { recalibrateResultMessage != nil },
                set: { if !$0 { recalibrateResultMessage = nil } }
            )
        ) {
            Button("OK") { recalibrateResultMessage = nil }
        } message: {
            Text(recalibrateResultMessage ?? "")
        }
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
    }

    // MARK: - Profile Header

    // MARK: - Tab Content

    /// Today's snapshot — streak + goal completion. Mirrors the friend
    /// profile's Activity tab role: "what's happening right now".
    @ViewBuilder
    private var ownActivityTabContent: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            streakAndGoalRow
            OwnTodayChallengeCard(healthManager: healthManager, userManager: userManager)
            if !ownWorkouts.isEmpty {
                Last7DaysChart(workouts: ownWorkouts)
            }
            if !receivedHypes.isEmpty {
                recentHypesSection
            }
        }
    }

    /// "You got hyped" — recent 👏 reactions friends sent you.
    private var recentHypesSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack {
                Text("RECENT HYPES")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
            }

            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(receivedHypes.prefix(8)) { hype in
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
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.orange.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
                            )
                    )
                }
            }
        }
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

    /// Pulls the user's own recent workouts to feed the rolling 7-day chart.
    /// A limit of 20 comfortably covers the last week even for multi-run days.
    private func loadOwnWorkouts() async {
        guard let userId = userManager.currentUser.backendUserId else { return }
        do {
            let workouts = try await friendService.fetchRecentWorkouts(for: userId, limit: 20)
            await MainActor.run { ownWorkouts = workouts }
        } catch {
            print("[ProfileView] loadOwnWorkouts failed: \(error)")
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Red gradient banner
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
                    // Profile Image with edit overlay
                    Button {
                        showingEditProfile = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 128, height: 128)

                            if let image = currentProfileImage ?? getCustomProfileImage() ?? getAppleProfileImage() {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                            } else {
                                AvatarView(name: userManager.currentUser.name, imageURL: userManager.currentUser.profileImageUrl, size: 120)
                            }

                            // Camera edit badge
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Circle()
                                        .fill(MADTheme.Colors.madRed)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.white)
                                        )
                                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                                }
                            }
                            .frame(width: 120, height: 120)
                        }
                    }
                    .buttonStyle(.plain)
                    .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 5)
                    .padding(.top, 40)

                    // User Info
                    VStack(spacing: MADTheme.Spacing.sm) {
                        // Username (primary, large)
                        if let username = userManager.currentUser.username {
                            Text("@\(username)")
                                .font(MADTheme.Typography.title1)
                                .foregroundColor(MADTheme.Colors.primaryText)
                        }

                        // Display name
                        if let firstName = userManager.currentUser.firstName, !firstName.isEmpty {
                            let displayName = [firstName, userManager.currentUser.lastName].compactMap { $0 }.joined(separator: " ")
                            Text(displayName)
                                .font(MADTheme.Typography.body)
                                .foregroundColor(MADTheme.Colors.secondaryText)
                        }

                        // Bio with quote-style accent
                        if let bio = userManager.currentUser.bio, !bio.isEmpty {
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
                    // tappable through to the friends list / leaderboard.
                    ProfileStatsRow(
                        streak: userManager.currentUser.streak,
                        totalMiles: userManager.currentUser.totalMiles,
                        friendCount: ownFriendCount
                    ) {
                        FriendsListView(friendService: friendService)
                    }
                    .padding(.horizontal, MADTheme.Spacing.lg)

                    // Edit Profile Button
                    Button {
                        showingEditProfile = true
                    } label: {
                        HStack(spacing: MADTheme.Spacing.sm) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Edit Profile")
                                .font(MADTheme.Typography.headline)
                        }
                        .foregroundColor(MADTheme.Colors.madRed)
                        .padding(.horizontal, MADTheme.Spacing.xl)
                        .padding(.vertical, MADTheme.Spacing.sm + 2)
                        .background(
                            Capsule()
                                .fill(MADTheme.Colors.madRed.opacity(0.15))
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.horizontal, MADTheme.Spacing.lg)
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.lg)
            }
        }
        // Clip the inner LinearGradient banner to the card shape so it
        // doesn't bleed past the rounded top corners. Same fix as the
        // friend profile header — madLiquidGlass styles a rounded
        // background but doesn't clip the children.
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous))
        .madLiquidGlass()
        .onAppear {
            loadProfileImage()
        }
    }

    // MARK: - Streak & Goal Row

    private var streakAndGoalRow: some View {
        let hasCompletedToday = userManager.currentUser.isStreakActiveToday
        let streak = userManager.currentUser.streak
        let goalMiles = userManager.currentUser.goalMiles

        return HStack(spacing: MADTheme.Spacing.md) {
            // Streak Card
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                Text("STREAK")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(hasCompletedToday ? .green : .orange)
                    .tracking(1.5)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(streak)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("days")
                        .font(MADTheme.Typography.small)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 18))
                        .foregroundColor(hasCompletedToday ? .green : .orange)
                    Spacer()
                    if hasCompletedToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(MADTheme.Spacing.md)
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(
                        LinearGradient(
                            colors: hasCompletedToday
                                ? [Color.green.opacity(0.15), Color.green.opacity(0.05)]
                                : [Color.orange.opacity(0.15), Color.orange.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .stroke(
                                hasCompletedToday ? Color.green.opacity(0.2) : Color.orange.opacity(0.2),
                                lineWidth: 1
                            )
                    )
            )

            // Daily Goal Card
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                Text("DAILY GOAL")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .tracking(1.5)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", goalMiles))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("mi")
                        .font(MADTheme.Typography.small)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack {
                    Image(systemName: hasCompletedToday ? "checkmark.circle.fill" : "target")
                        .font(.system(size: 18))
                        .foregroundColor(hasCompletedToday ? .green : MADTheme.Colors.madRed)
                    Spacer()
                }
            }
            .padding(MADTheme.Spacing.md)
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .madLiquidGlass()
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
