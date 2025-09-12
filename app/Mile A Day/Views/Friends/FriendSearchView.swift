import SwiftUI

/// View for searching and adding friends
struct FriendSearchView: View {
    @StateObject private var friendService = FriendService()
    @State private var searchText = ""
    @State private var searchResults: [BackendUser] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedUser: BackendUser?
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Header
            searchHeader
            
            // Content
            if isLoading {
                loadingView
            } else if !searchResults.isEmpty {
                searchResultsView
            } else if !searchText.isEmpty && searchText.count >= 3 {
                noResultsView
            } else if searchText.isEmpty || searchText.count < 3 {
                recommendationsView
            }
        }
        .navigationTitle("Find Friends")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedUser) { user in
            NavigationStack {
                UserProfileDetailView(user: user, friendService: friendService)
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            handleSearchTextChange(newValue)
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }
    
    // MARK: - Search Header
    private var searchHeader: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(MADTheme.Colors.secondaryText)
                
                TextField("Search by username...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: clearSearch) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(MADTheme.Colors.secondaryText)
                    }
                }
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(MADTheme.Colors.secondaryBackground)
            )
        }
        .padding(MADTheme.Spacing.md)
        .background(MADTheme.Colors.primaryBackground)
    }
    
    // MARK: - Search Results View
    private var searchResultsView: some View {
        ScrollView {
            LazyVStack(spacing: MADTheme.Spacing.md) {
                ForEach(searchResults) { user in
                    UserProfileCard(
                        user: user,
                        showStats: false,
                        showBadges: false,
                        onTap: {
                            selectedUser = user
                        },
                        actionButton: AnyView(
                            FriendActionButton(
                                title: getActionButtonTitle(for: user),
                                style: getActionButtonStyle(for: user),
                                isLoading: false,
                                action: {
                                    handleFriendAction(for: user)
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
            
            Text("Searching...")
                .font(MADTheme.Typography.body)
                .foregroundColor(MADTheme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - No Results View
    private var noResultsView: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(MADTheme.Colors.secondaryText)
            
            VStack(spacing: MADTheme.Spacing.sm) {
                Text("No Results Found")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(MADTheme.Colors.primaryText)
                
                Text("We couldn't find any users matching '\(searchText)'. Try a different search term or check the suggestions below.")
                    .font(MADTheme.Typography.body)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            
            // Show some recommended users when no search results
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                Text("You might like")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(MADTheme.Colors.primaryText)
                
                LazyVStack(spacing: MADTheme.Spacing.md) {
                    ForEach(getRecommendedUsers().prefix(2)) { user in
                        UserProfileCard(
                            user: user,
                            showStats: false,
                            showBadges: false,
                            onTap: {
                                selectedUser = user
                            },
                            actionButton: AnyView(
                                FriendActionButton(
                                    title: getActionButtonTitle(for: user),
                                    style: getActionButtonStyle(for: user),
                                    isLoading: false,
                                    action: {
                                        handleFriendAction(for: user)
                                    }
                                )
                            )
                        )
                    }
                }
            }
            .padding(.top, MADTheme.Spacing.lg)
        }
        .padding(MADTheme.Spacing.xl)
    }
    
    // MARK: - Recommendations View
    private var recommendationsView: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.lg) {
                // Header
                VStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "person.2.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(MADTheme.Colors.madRed)
                    
                    Text("Discover Runners")
                        .font(MADTheme.Typography.title2)
                        .foregroundColor(MADTheme.Colors.primaryText)
                    
                    Text("Type at least 3 letters to search, or discover recommended users below")
                        .font(MADTheme.Typography.body)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(MADTheme.Spacing.lg)
                
                // Recommended Users (mock data for now)
                VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                    Text("Suggested for You")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(MADTheme.Colors.primaryText)
                        .padding(.horizontal, MADTheme.Spacing.md)
                    
                    LazyVStack(spacing: MADTheme.Spacing.md) {
                        ForEach(getRecommendedUsers()) { user in
                            UserProfileCard(
                                user: user,
                                showStats: false,
                                showBadges: false,
                                onTap: {
                                    selectedUser = user
                                },
                                actionButton: AnyView(
                                    FriendActionButton(
                                        title: getActionButtonTitle(for: user),
                                        style: getActionButtonStyle(for: user),
                                        isLoading: false,
                                        action: {
                                            handleFriendAction(for: user)
                                        }
                                    )
                                )
                            )
                        }
                    }
                }
            }
            .padding(MADTheme.Spacing.md)
        }
    }
    
    // MARK: - Helper Methods
    private func handleSearchTextChange(_ newValue: String) {
        let trimmedText = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Cancel any existing search task
        searchTask?.cancel()
        
        // Only search if we have at least 3 characters
        if trimmedText.count >= 3 {
            // Debounce the search by 300ms
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                
                if !Task.isCancelled {
                    await MainActor.run {
                        performSearch()
                    }
                }
            }
        } else {
            // Clear results if less than 3 characters
            searchResults = []
            isLoading = false
        }
    }
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // First try exact match
                do {
                    let user = try await friendService.searchUser(byUsername: searchText.trimmingCharacters(in: .whitespacesAndNewlines))
                    await MainActor.run {
                        searchResults = [user]
                        isLoading = false
                    }
                } catch {
                    // If exact match fails, try partial search
                    let users = try await friendService.searchUsersByPartialUsername(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
                    await MainActor.run {
                        searchResults = users
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    searchResults = []
                    isLoading = false
                }
            }
        }
    }
    
    private func getRecommendedUsers() -> [BackendUser] {
        // Mock recommended users - in a real app, this would come from your backend
        // based on mutual friends, similar interests, location, etc.
        return [
            BackendUser(
                user_id: "rec1",
                username: "papameags",
                email: "matthew@mfoobert.com",
                first_name: "Matthew",
                last_name: "Meagher",
                bio: "Hunting milfs and running a mile a day 🏃‍♂️",
                profile_image_url: nil,
                apple_id: nil,
                auth_provider: "apple"
            ),
            BackendUser(
                user_id: "rec2",
                username: "ishowspeed",
                email: "speed@ishow.com",
                first_name: "Darren",
                last_name: "Watkins Jr",
                bio: "Fastest streamer in the world",
                profile_image_url: nil,
                apple_id: nil,
                auth_provider: "apple"
            ),
            BackendUser(
                user_id: "rec3",
                username: "tyreek_hill",
                email: "tyreek@hill.com",
                first_name: "Tyreek",
                last_name: "Hill",
                bio: "Beating women and catching touchdowns",
                profile_image_url: nil,
                apple_id: nil,
                auth_provider: "apple"
            )
        ]
    }
    
    private func clearSearch() {
        searchText = ""
        searchResults = []
        errorMessage = nil
    }
    
    private func getActionButtonTitle(for user: BackendUser) -> String {
        if friendService.isFriend(user) {
            return "Friends"
        } else if friendService.hasPendingRequest(from: user) {
            return "Accept"
        } else if friendService.hasSentRequest(to: user) {
            return "Sent"
        } else {
            return "Add Friend"
        }
    }
    
    private func getActionButtonStyle(for user: BackendUser) -> FriendActionStyle {
        if friendService.isFriend(user) {
            return .success
        } else if friendService.hasPendingRequest(from: user) {
            return .primary
        } else if friendService.hasSentRequest(to: user) {
            return .secondary
        } else {
            return .primary
        }
    }
    
    private func handleFriendAction(for user: BackendUser) {
        Task {
            do {
                if friendService.isFriend(user) {
                    // Already friends, do nothing
                    return
                } else if friendService.hasPendingRequest(from: user) {
                    try await friendService.acceptFriendRequest(from: user)
                } else if friendService.hasSentRequest(to: user) {
                    // Request already sent, do nothing
                    return
                } else {
                    try await friendService.sendFriendRequest(to: user)
                }
                
                // Refresh the search results to update button states
                await MainActor.run {
                    performSearch()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Preview
struct FriendSearchView_Previews: PreviewProvider {
    static var previews: some View {
        FriendSearchView()
    }
}
