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
    
    // Helper to determine if more workouts can be loaded
    private var canLoadMore: Bool {
        hasLoadedInitial && friendWorkouts.count >= workoutLimit
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Profile Header
                profileHeader
                    .padding(.horizontal, MADTheme.Spacing.md)
                
                // Stats Section
                if !isPrivate {
                    FriendStatsView(user: user, stats: userStats)
                        .padding(.horizontal, MADTheme.Spacing.md)
                } else {
                    privateAccountView
                        .padding(.horizontal, MADTheme.Spacing.md)
                }
                
                // Badges Section
                if !isPrivate && !userBadges.isEmpty {
                    FriendBadgesView(badges: userBadges)
                        .padding(.horizontal, MADTheme.Spacing.md)
                }

                // Recent Workouts Section
                if !isPrivate && !friendWorkouts.isEmpty {
                    VStack(spacing: MADTheme.Spacing.md) {
                        FriendWorkoutsSection(workouts: friendWorkouts)
                        
                        // Load More button - show if we have workouts and there might be more
                        if canLoadMore && !isLoadingMoreWorkouts {
                            loadMoreButton
                                .padding(.horizontal, MADTheme.Spacing.md)
                        }
                    }
                }
            }
            .padding(.vertical, MADTheme.Spacing.md)
        }
        .navigationTitle(user.username ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close") {
                    dismiss()
                }
            }
        }
        .onAppear {
            loadUserData()
            refreshFriendshipStatus()
        }
    }
    
    // MARK: - Profile Header
    private var profileHeader: some View {
        VStack(spacing: 0) {
            // Background gradient
            ZStack(alignment: .top) {
                LinearGradient(
                    gradient: Gradient(colors: [
                        MADTheme.Colors.madRed.opacity(0.3),
                        MADTheme.Colors.primaryBackground.opacity(0.1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                
                VStack(spacing: MADTheme.Spacing.lg) {
                    // Profile Image with shadow
                    ZStack {
                        Circle()
                            .fill(MADTheme.Colors.primaryBackground)
                            .frame(width: 128, height: 128)
                            .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: 5)
                        
                        ProfileImageView(user: user, size: 120)
                    }
                    .padding(.top, 40)
                    
                    // User Info
                    VStack(spacing: MADTheme.Spacing.sm) {
                        Text(user.username ?? "Unknown")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(MADTheme.Colors.primaryText)
                        
                        if user.displayName != user.username {
                            Text(user.displayName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(MADTheme.Colors.secondaryText)
                        }
                        
                        if let bio = user.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.system(size: 15))
                                .foregroundColor(MADTheme.Colors.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, MADTheme.Spacing.lg)
                                .padding(.top, 4)
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
        .background(MADTheme.Colors.primaryBackground)
        .cornerRadius(MADTheme.CornerRadius.large)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
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
            HStack {
                if isLoadingMoreWorkouts {
                    ProgressView()
                        .tint(MADTheme.Colors.madRed)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 20))
                    Text("Load More Workouts")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundColor(MADTheme.Colors.madRed)
            .frame(maxWidth: .infinity)
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(MADTheme.Colors.secondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .stroke(MADTheme.Colors.madRed.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .disabled(isLoadingMoreWorkouts)
    }
    
    // MARK: - Private Account View
    private var privateAccountView: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundColor(MADTheme.Colors.secondaryText)
            
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
        .background(MADTheme.Colors.primaryBackground)
        .cornerRadius(MADTheme.CornerRadius.large)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
    
    // MARK: - Helper Methods
    private func loadUserData() {
        isLoadingStats = true

        Task {
            do {
                // Fetch friend stats from API
                let stats = try await friendService.fetchFriendStats(for: user.user_id)

                // Fetch recent workouts from API (use workouts from stats if available, otherwise fetch separately)
                let workouts: [FriendWorkout]
                if let recentWorkouts = stats.recentWorkouts, !recentWorkouts.isEmpty {
                    workouts = recentWorkouts
                } else {
                    workouts = try await friendService.fetchRecentWorkouts(for: user.user_id, limit: workoutLimit)
                }

                await MainActor.run {
                    // Extract most miles in one day from bestMilesDay
                    let mostMilesInOneDay = stats.bestMilesDay?.totalDistance ?? 0.0
                    
                    // Extract fastest mile pace from bestSplitTime (convert seconds to minutes per mile)
                    var fastestMilePace: TimeInterval = 0.0
                    if let bestSplitTime = stats.bestSplitTime,
                       let bestSplitSeconds = bestSplitTime.bestSplitTime,
                       bestSplitSeconds > 0 {
                        // Convert seconds to minutes per mile
                        fastestMilePace = bestSplitSeconds / 60.0
                    }
                    
                    // Get goal miles and today miles from API response
                    let goalMiles = stats.goalMiles ?? 1.0
                    let todayMiles = stats.todayMiles ?? 0.0
                    let hasCompletedGoalToday = todayMiles >= goalMiles && goalMiles > 0
                    
                    // Convert FriendStats to UserStats using actual API data
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

                    // Mock badges for now - replace with actual badge API when available
                    userBadges = []

                    isLoadingStats = false
                }

            } catch {
                await MainActor.run {
                    print("[UserProfileDetailView] ❌ Failed to load user data: \(error)")
                    // If loading fails, keep mock data or show error
                    isLoadingStats = false
                }
            }
        }
    }
    
    private func refreshFriendshipStatus() {
        // Refresh the friend service data to ensure we have the latest friendship status
        Task {
            await friendService.refreshAllData()
        }
    }
    
    private func getActionButtonTitle() -> String {
        // Check if this is the current user
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
        // Check if this is the current user
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
        // Don't allow friend actions on current user
        if isCurrentUser() {
            return
        }
        
        if friendService.isFriend(user) {
            // Already friends, do nothing
            return
        } else if friendService.hasPendingRequest(from: user) {
            handleAcceptRequest()
        } else if friendService.hasSentRequest(to: user) {
            // Request already sent, do nothing
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
                await MainActor.run {
                    actionInProgress = false
                }
            } catch {
                await MainActor.run {
                    actionInProgress = false
                    // Handle error
                }
            }
        }
    }
    
    private func handleAcceptRequest() {
        actionInProgress = true
        
        Task {
            do {
                try await friendService.acceptFriendRequest(from: user)
                await MainActor.run {
                    actionInProgress = false
                }
            } catch {
                await MainActor.run {
                    actionInProgress = false
                    // Handle error
                }
            }
        }
    }
    
    private func loadMoreWorkouts() {
        guard !isLoadingMoreWorkouts else { 
            print("[UserProfileDetailView] ⚠️ Already loading workouts, skipping")
            return 
        }
        
        let newLimit = workoutLimit + 10
        print("[UserProfileDetailView] 📥 Loading more workouts - current: \(friendWorkouts.count), new limit: \(newLimit)")
        
        isLoadingMoreWorkouts = true
        
        Task {
            do {
                let workouts = try await friendService.fetchRecentWorkouts(for: user.user_id, limit: newLimit)
                print("[UserProfileDetailView] ✅ Loaded \(workouts.count) workouts")
                
                await MainActor.run {
                    friendWorkouts = workouts
                    workoutLimit = newLimit
                    isLoadingMoreWorkouts = false
                    print("[UserProfileDetailView] 📊 Updated state - workouts: \(friendWorkouts.count), limit: \(workoutLimit)")
                }
            } catch {
                await MainActor.run {
                    print("[UserProfileDetailView] ❌ Failed to load more workouts: \(error)")
                    isLoadingMoreWorkouts = false
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
            auth_provider: "apple"
        )
        
        UserProfileDetailView(user: mockUser, friendService: FriendService())
    }
}
