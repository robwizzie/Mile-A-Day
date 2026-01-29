import SwiftUI

/// View for managing blocked users
struct BlockedUsersView: View {
    @ObservedObject var friendService: FriendService
    @State private var blockedUsers: [BackendUser] = []
    @State private var isLoading = false
    @State private var showingUnblockAlert = false
    @State private var userToUnblock: BackendUser?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                loadingView
            } else if blockedUsers.isEmpty {
                emptyStateView
            } else {
                blockedUsersList
            }
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadBlockedUsers()
        }
        .refreshable {
            await loadBlockedUsers()
        }
        .alert("Unblock \(userToUnblock?.displayName ?? "User")?", isPresented: $showingUnblockAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Unblock") {
                if let user = userToUnblock {
                    handleUnblock(user)
                }
            }
        } message: {
            Text("This person will be able to see your profile and send you friend requests again.")
        }
    }

    // MARK: - Blocked Users List
    private var blockedUsersList: some View {
        ScrollView {
            LazyVStack(spacing: MADTheme.Spacing.md) {
                ForEach(blockedUsers) { user in
                    UserProfileCard(
                        user: user,
                        showStats: false,
                        showBadges: false,
                        onTap: {},
                        actionButton: AnyView(
                            FriendActionButton(
                                title: "Unblock",
                                style: .primary,
                                action: {
                                    userToUnblock = user
                                    showingUnblockAlert = true
                                }
                            )
                        )
                    )
                }
            }
            .padding(MADTheme.Spacing.md)
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))

            Text("Loading...")
                .font(MADTheme.Typography.body)
                .foregroundColor(MADTheme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        FriendEmptyStateView(
            title: "No Blocked Users",
            message: "You haven't blocked anyone. Blocked users can't see your profile or send you requests.",
            systemImage: "hand.raised.slash"
        )
    }

    // MARK: - Helper Methods
    private func loadBlockedUsers() async {
        isLoading = true
        do {
            blockedUsers = try await friendService.loadBlockedUsers()
        } catch {
            print("Failed to load blocked users: \(error)")
        }
        isLoading = false
    }

    private func handleUnblock(_ user: BackendUser) {
        Task {
            do {
                try await friendService.unblockUser(user)
                blockedUsers.removeAll { $0.user_id == user.user_id }
            } catch {
                print("Failed to unblock user: \(error)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        BlockedUsersView(friendService: FriendService())
    }
}
