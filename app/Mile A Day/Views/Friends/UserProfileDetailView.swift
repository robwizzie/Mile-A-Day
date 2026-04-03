import SwiftUI

/// Detailed view for displaying a user's profile information
struct UserProfileDetailView: View {
    let user: BackendUser
    let friendService: FriendService
    @Environment(\.dismiss) private var dismiss

    @State private var userStats: UserStats?
    @State private var userBadges: [Badge] = []
    @State private var friendWorkouts: [FriendWorkout] = []
    @State private var isLoadingStats = false
    @State private var isPrivate = false
    @State private var actionInProgress = false
    @State private var workoutLimit = 10
    @State private var isLoadingMoreWorkouts = false
    @State private var hasLoadedInitial = false
    @State private var selectedWorkout: FriendWorkout?

    private var canLoadMore: Bool {
        hasLoadedInitial && friendWorkouts.count >= workoutLimit
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    // Profile Header
                    profileHeader

                    // Stats Section
                    if !isPrivate {
                        FriendStatsView(user: user, stats: userStats)
                    } else {
                        privateAccountView
                    }

                    // Badges Section
                    if !isPrivate && !userBadges.isEmpty {
                        FriendBadgesView(badges: userBadges)
                    }

                    // Recent Workouts Section
                    if !isPrivate && !friendWorkouts.isEmpty {
                        VStack(spacing: MADTheme.Spacing.md) {
                            FriendWorkoutsSection(
                                workouts: friendWorkouts,
                                onWorkoutTap: { workout in
                                    selectedWorkout = workout
                                }
                            )

                            if canLoadMore && !isLoadingMoreWorkouts {
                                loadMoreButton
                            }
                        }
                    }
                }
                .padding(.vertical, MADTheme.Spacing.md)
                .padding(.horizontal, MADTheme.Spacing.md)
            }
        }
        .navigationTitle(user.username ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close") {
                    dismiss()
                }
                .foregroundColor(MADTheme.Colors.madRed)
            }
        }
        .sheet(item: $selectedWorkout) { workout in
            FriendWorkoutDetailSheet(workout: workout)
        }
        .onAppear {
            loadUserData()
            refreshFriendshipStatus()
        }
    }

    // MARK: - Profile Header
    private var profileHeader: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Background gradient
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

                    // Friend Action Button
                    friendActionButton
                        .padding(.horizontal, MADTheme.Spacing.lg)
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.lg)
            }
        }
        .madLiquidGlass()
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
                    userBadges = []
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
