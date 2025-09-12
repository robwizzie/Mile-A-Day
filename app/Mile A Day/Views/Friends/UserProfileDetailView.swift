import SwiftUI

/// Detailed view for displaying a user's profile information
struct UserProfileDetailView: View {
    let user: BackendUser
    let friendService: FriendService
    @Environment(\.dismiss) private var dismiss
    
    @State private var userStats: UserStats?
    @State private var userBadges: [Badge] = []
    @State private var isLoadingStats = false
    @State private var isPrivate = false
    @State private var actionInProgress = false
    
    var body: some View {
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
            }
            .padding(MADTheme.Spacing.md)
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
        VStack(spacing: MADTheme.Spacing.lg) {
            // Profile Image
            ProfileImageView(user: user, size: 120)
            
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
                
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(MADTheme.Typography.body)
                        .foregroundColor(MADTheme.Colors.primaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MADTheme.Spacing.lg)
                }
            }
            
            // Friend Action Button
            friendActionButton
        }
        .padding(MADTheme.Spacing.lg)
        .madCard()
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
        .madCard()
    }
    
    // MARK: - Helper Methods
    private func loadUserData() {
        // For now, we'll simulate loading stats and badges
        // In a real implementation, you'd make API calls to get this data
        isLoadingStats = true
        
        // Load data immediately without delay for better UX
        Task {
            // Simulate a brief loading state
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            await MainActor.run {
                // Mock data - replace with actual API calls
                userStats = UserStats(
                    streak: 15,
                    totalMiles: 45.2,
                    fastestMilePace: 7.5,
                    mostMilesInOneDay: 3.2
                )
                
                userBadges = [
                    Badge(id: "streak_7", name: "Week Warrior", description: "7 day streak!", dateAwarded: Date()),
                    Badge(id: "miles_50", name: "50 Mile Club", description: "Ran 50 total miles!", dateAwarded: Date())
                ]
                
                isLoadingStats = false
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
