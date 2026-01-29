import SwiftUI

/// Main view for managing friends list
struct FriendsListView: View {
    @StateObject private var friendService = FriendService()
    @State private var selectedTab = 0
    @State private var showingSearch = false
    @State private var selectedUser: BackendUser?
    @State private var showingUnfriendAlert = false
    @State private var showingBlockAlert = false
    @State private var userToUnfriend: BackendUser?
    @State private var userToBlock: BackendUser?
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Selector
            tabSelector

            // Content - Use conditional rendering for better performance
            Group {
                switch selectedTab {
                case 0:
                    friendsTab
                        .id("friends-tab")
                case 1:
                    requestsTab
                        .id("requests-tab")
                case 2:
                    sentTab
                        .id("sent-tab")
                default:
                    friendsTab
                        .id("friends-tab")
                }
            }
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        // iOS 26: Liquid Glass is automatic - no toolbar modifiers needed
            .sheet(isPresented: $showingSearch) {
                NavigationStack {
                    FriendSearchView(friendService: friendService)
                }
            }
            .sheet(item: $selectedUser) { user in
                NavigationStack {
                    UserProfileDetailView(user: user, friendService: friendService)
                }
            }
            .task {
                // Only load once when view first appears
                if friendService.friends.isEmpty && friendService.friendRequests.isEmpty && friendService.sentRequests.isEmpty {
                    await friendService.refreshAllData()
                }
            }
            .refreshable {
                await friendService.refreshAllData()
            }
            .alert("Unfriend \(userToUnfriend?.displayName ?? "User")?", isPresented: $showingUnfriendAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Unfriend", role: .destructive) {
                    if let user = userToUnfriend {
                        handleUnfriend(user)
                    }
                }
            } message: {
                Text("You will no longer be friends with this person.")
            }
            .alert("Block \(userToBlock?.displayName ?? "User")?", isPresented: $showingBlockAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Block", role: .destructive) {
                    if let user = userToBlock {
                        handleBlock(user)
                    }
                }
            } message: {
                Text("You will unfriend and block this person. They won't be able to see your profile or send you friend requests.")
            }
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack {
            HStack(spacing: 0) {
                TabButton(
                    title: "Friends",
                    count: friendService.friends.count,
                    isSelected: selectedTab == 0,
                    action: { selectedTab = 0 }
                )

                TabButton(
                    title: "Requests",
                    count: friendService.friendRequests.count,
                    isSelected: selectedTab == 1,
                    action: { selectedTab = 1 }
                )

                TabButton(
                    title: "Sent",
                    count: friendService.sentRequests.count,
                    isSelected: selectedTab == 2,
                    action: { selectedTab = 2 }
                )
            }
            
            Spacer()
            
            Button(action: { showingSearch = true }) {
                Image(systemName: "person.badge.plus")
                    .font(.title2)
                    .foregroundColor(MADTheme.Colors.madRed)
            }
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, MADTheme.Spacing.sm)
        .background(Color.clear)
    }
    
    // MARK: - Friends Tab
    private var friendsTab: some View {
        Group {
            if friendService.isLoading {
                loadingView
            } else if friendService.friends.isEmpty {
                FriendEmptyStateView(
                    title: "No Friends Yet",
                    message: "Start building your running community by adding friends!",
                    systemImage: "person.2",
                    actionTitle: "Add Friends",
                    action: { showingSearch = true }
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: MADTheme.Spacing.md) {
                        ForEach(friendService.friends) { friend in
                            UserProfileCard(
                                user: friend,
                                onTap: {
                                    selectedUser = friend
                                },
                                actionButton: AnyView(
                                    Menu {
                                        Button(role: .destructive) {
                                            userToUnfriend = friend
                                            showingUnfriendAlert = true
                                        } label: {
                                            Label("Unfriend", systemImage: "person.fill.xmark")
                                        }

                                        Button(role: .destructive) {
                                            userToBlock = friend
                                            showingBlockAlert = true
                                        } label: {
                                            Label("Block", systemImage: "hand.raised.fill")
                                        }
                                    } label: {
                                        HStack(spacing: MADTheme.Spacing.xs) {
                                            Text("Friends")
                                                .font(MADTheme.Typography.smallBold)
                                            Image(systemName: "chevron.down")
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.green)
                                        .padding(.horizontal, MADTheme.Spacing.md)
                                        .padding(.vertical, MADTheme.Spacing.sm)
                                        .background(
                                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                                                .fill(Color.green.opacity(0.1))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                                                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                )
                            )
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
        }
    }
    
    // MARK: - Requests Tab
    private var requestsTab: some View {
        Group {
            if friendService.isLoading {
                loadingView
            } else if friendService.friendRequests.isEmpty {
                FriendEmptyStateView(
                    title: "No Friend Requests",
                    message: "You don't have any pending friend requests at the moment.",
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: MADTheme.Spacing.md) {
                        ForEach(friendService.friendRequests) { request in
                            UserProfileCard(
                                user: request,
                                onTap: {
                                    selectedUser = request
                                },
                                actionButton: AnyView(
                                    HStack(spacing: MADTheme.Spacing.md) {
                                        // Accept button
                                        Button(action: {
                                            handleAcceptRequest(request)
                                        }) {
                                            HStack(spacing: MADTheme.Spacing.xs) {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 14, weight: .semibold))
                                                Text("Accept")
                                                    .font(MADTheme.Typography.smallBold)
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, MADTheme.Spacing.md)
                                            .padding(.vertical, MADTheme.Spacing.sm)
                                            .background(
                                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                                                    .fill(Color.green)
                                            )
                                        }
                                        .buttonStyle(.plain)

                                        // Decline button
                                        Button(action: {
                                            handleDeclineRequest(request)
                                        }) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white.opacity(0.8))
                                                .frame(width: 36, height: 36)
                                                .background(
                                                    Circle()
                                                        .fill(Color.red.opacity(0.2))
                                                        .overlay(
                                                            Circle()
                                                                .stroke(Color.red.opacity(0.4), lineWidth: 1)
                                                        )
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                )
                            )
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
        }
    }
    
    // MARK: - Sent Tab
    private var sentTab: some View {
        Group {
            if friendService.isLoading {
                loadingView
            } else if friendService.sentRequests.isEmpty {
                FriendEmptyStateView(
                    title: "No Sent Requests",
                    message: "You haven't sent any friend requests yet.",
                    systemImage: "paperplane"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: MADTheme.Spacing.md) {
                        ForEach(friendService.sentRequests) { request in
                            UserProfileCard(
                                user: request,
                                onTap: {
                                    selectedUser = request
                                },
                                actionButton: AnyView(
                                    FriendActionButton(
                                        title: "Cancel",
                                        style: .secondary,
                                        action: {
                                            handleCancelRequest(request)
                                        }
                                    )
                                )
                            )
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
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
    
    // MARK: - Helper Methods
    private func handleAcceptRequest(_ user: BackendUser) {
        Task {
            do {
                try await friendService.acceptFriendRequest(from: user)
            } catch {
                // Handle error
            }
        }
    }
    
    private func handleDeclineRequest(_ user: BackendUser) {
        Task {
            do {
                try await friendService.declineFriendRequest(from: user)
            } catch {
                // Handle error
            }
        }
    }
    
    private func handleCancelRequest(_ user: BackendUser) {
        Task {
            do {
                try await friendService.cancelFriendRequest(to: user)
            } catch {
                // Handle error
            }
        }
    }

    private func handleUnfriend(_ user: BackendUser) {
        Task {
            do {
                try await friendService.removeFriend(user)
            } catch {
                // Handle error
            }
        }
    }

    private func handleBlock(_ user: BackendUser) {
        Task {
            do {
                try await friendService.blockUser(user)
            } catch {
                // Handle error
            }
        }
    }
}

// MARK: - Tab Button Component
struct TabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: MADTheme.Spacing.xs) {
                HStack(spacing: MADTheme.Spacing.xs) {
                    Text(title)
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(isSelected ? MADTheme.Colors.madRed : MADTheme.Colors.secondaryText)
                    
                    if count > 0 {
                        Text("\(count)")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, MADTheme.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(MADTheme.Colors.madRed)
                            )
                    }
                }
                
                Rectangle()
                    .fill(isSelected ? MADTheme.Colors.madRed : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview
struct FriendsListView_Previews: PreviewProvider {
    static var previews: some View {
        FriendsListView()
    }
}
