import SwiftUI

/// A browsable list of a given user's friends — the destination when you tap
/// the "Friends" count on a profile (Instagram-style). Each row opens that
/// person's profile and offers the right friend action (Add / Accept / Friends).
struct UserFriendsListView: View {
    let userId: String
    /// Display name of whose friends these are, for the title context.
    let ownerName: String
    @ObservedObject var friendService: FriendService

    @State private var friends: [BackendUser] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var selectedUser: BackendUser?

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                    .scaleEffect(1.3)
            } else if friends.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: MADTheme.Spacing.md) {
                        ForEach(friends) { user in
                            UserProfileCard(
                                user: user,
                                showStats: false,
                                showBadges: false,
                                onTap: { selectedUser = user },
                                actionButton: AnyView(actionButton(for: user))
                            )
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedUser) { user in
            NavigationStack {
                UserProfileDetailView(user: user, friendService: friendService)
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func actionButton(for user: BackendUser) -> some View {
        if isCurrentUser(user) {
            EmptyView()
        } else {
            FriendActionButton(
                title: actionTitle(for: user),
                style: actionStyle(for: user),
                isLoading: false,
                action: { handleAction(for: user) }
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.25))
            Text(loadFailed ? "Couldn't load friends" : "\(ownerName) has no friends yet")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(MADTheme.Spacing.xl)
    }

    // MARK: - Data

    private func load() async {
        do {
            let result = try await friendService.getFriendsList(for: userId)
            await MainActor.run {
                friends = result
                isLoading = false
            }
        } catch {
            print("[UserFriendsListView] load failed: \(error)")
            await MainActor.run {
                loadFailed = true
                isLoading = false
            }
        }
    }

    // MARK: - Friend action helpers (mirror FriendSearchView)

    private func isCurrentUser(_ user: BackendUser) -> Bool {
        UserDefaults.standard.string(forKey: "backendUserId") == user.user_id
    }

    private func actionTitle(for user: BackendUser) -> String {
        if friendService.isFriend(user) { return "Friends" }
        if friendService.hasPendingRequest(from: user) { return "Accept" }
        if friendService.hasSentRequest(to: user) { return "Sent" }
        return "Add Friend"
    }

    private func actionStyle(for user: BackendUser) -> FriendActionStyle {
        if friendService.isFriend(user) { return .success }
        if friendService.hasSentRequest(to: user) { return .secondary }
        return .primary
    }

    private func handleAction(for user: BackendUser) {
        Task {
            do {
                if friendService.isFriend(user) || friendService.hasSentRequest(to: user) {
                    return
                } else if friendService.hasPendingRequest(from: user) {
                    try await friendService.acceptFriendRequest(from: user)
                } else {
                    try await friendService.sendFriendRequest(to: user)
                }
                await friendService.refreshAllData()
            } catch {
                print("[UserFriendsListView] action failed: \(error)")
            }
        }
    }
}
