import SwiftUI

/// Main view for managing friends list
struct FriendsListView: View {
    @StateObject private var friendService = FriendService()
    @State private var selectedTab = 0
    @State private var showingSearch = false
    @State private var selectedUser: BackendUser?
    
    var body: some View {
        ZStack {
            // Gradient background
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea(.all)
            
            VStack(spacing: 0) {
                // Tab Selector
                tabSelector
                
                // Content
                TabView(selection: $selectedTab) {
                    // Friends Tab
                    friendsTab
                        .tag(0)
                    
                    // Requests Tab
                    requestsTab
                        .tag(1)
                    
                    // Sent Tab
                    sentTab
                        .tag(2)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackgroundVisibility(.automatic, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showingSearch) {
                FriendSearchView()
            }
            .sheet(item: $selectedUser) { user in
                NavigationStack {
                    UserProfileDetailView(user: user, friendService: friendService)
                }
            }
            .onAppear {
                Task {
                    await friendService.refreshAllData()
                }
            }
            .refreshable {
                await friendService.refreshAllData()
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
                    action: { withAnimation { selectedTab = 0 } }
                )
                
                TabButton(
                    title: "Requests",
                    count: friendService.friendRequests.count,
                    isSelected: selectedTab == 1,
                    action: { withAnimation { selectedTab = 1 } }
                )
                
                TabButton(
                    title: "Sent",
                    count: friendService.sentRequests.count,
                    isSelected: selectedTab == 2,
                    action: { withAnimation { selectedTab = 2 } }
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
                                    FriendActionButton(
                                        title: "Friends",
                                        style: .success,
                                        action: {}
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
                                    HStack(spacing: MADTheme.Spacing.sm) {
                                        FriendActionButton(
                                            title: "Accept",
                                            style: .primary,
                                            action: {
                                                handleAcceptRequest(request)
                                            }
                                        )
                                        
                                        FriendActionButton(
                                            title: "Decline",
                                            style: .destructive,
                                            action: {
                                                handleDeclineRequest(request)
                                            }
                                        )
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
