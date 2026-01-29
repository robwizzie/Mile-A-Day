import SwiftUI

/// View for searching and adding friends
struct FriendSearchView: View {
    @ObservedObject var friendService: FriendService
    @State private var searchText = ""
    @State private var searchResults: [BackendUser] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedUser: BackendUser?
    @State private var searchTask: Task<Void, Never>?
    @State private var showingUnfriendAlert = false
    @State private var showingBlockAlert = false
    @State private var userToUnfriend: BackendUser?
    @State private var userToBlock: BackendUser?
    
    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if !searchResults.isEmpty {
                searchResultsView
            } else if !searchText.isEmpty && searchText.count >= 3 {
                noResultsView
            } else {
                recommendationsView
            }
        }
        .navigationTitle("Find Friends")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search by username")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
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
                            Group {
                                if friendService.isFriend(user) {
                                    // Show dropdown menu for friends
                                    Menu {
                                        Button(role: .destructive) {
                                            userToUnfriend = user
                                            showingUnfriendAlert = true
                                        } label: {
                                            Label("Unfriend", systemImage: "person.fill.xmark")
                                        }

                                        Button(role: .destructive) {
                                            userToBlock = user
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
                                } else {
                                    // Show regular action button for non-friends
                                    FriendActionButton(
                                        title: getActionButtonTitle(for: user),
                                        style: getActionButtonStyle(for: user),
                                        isLoading: false,
                                        action: {
                                            handleFriendAction(for: user)
                                        }
                                    )
                                }
                            }
                        )
                    )
                }
            }
            .padding(MADTheme.Spacing.md)
        }
        .background(MADTheme.Colors.appBackgroundGradient)
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
        .background(MADTheme.Colors.appBackgroundGradient)
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

                Text("We couldn't find any users matching '\(searchText)'. Try a different search term.")
                    .font(MADTheme.Typography.body)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MADTheme.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MADTheme.Spacing.xl)
        .background(MADTheme.Colors.appBackgroundGradient)
    }

    // MARK: - Recommendations View
    private var recommendationsView: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            Spacer()

            VStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(MADTheme.Colors.madRed)

                Text("Discover Runners")
                    .font(MADTheme.Typography.title2)
                    .foregroundColor(MADTheme.Colors.primaryText)

                Text("Type at least 3 letters to search for users")
                    .font(MADTheme.Typography.body)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MADTheme.Spacing.lg)
        .background(MADTheme.Colors.appBackgroundGradient)
    }
    
    // MARK: - Helper Methods
    private func handleSearchTextChange(_ newValue: String) {
        let trimmedText = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Cancel any existing search task
        searchTask?.cancel()
        
        // Only search if we have at least 3 characters
        if trimmedText.count >= 3 {
            // Debounce the search by 150ms for faster response
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                
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
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            isLoading = false
            return
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[FriendSearchView] 🔍 Starting search for: '\(trimmedSearch)'")

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let users = try await friendService.searchUsers(byUsername: trimmedSearch)
                print("[FriendSearchView] ✅ Search successful, found \(users.count) user(s)")

                // Only update if this search is still relevant
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    searchResults = users
                    isLoading = false
                }
            } catch {
                guard !Task.isCancelled else { return }

                print("[FriendSearchView] ❌ Search failed with error: \(error)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    searchResults = []
                    isLoading = false
                }
            }
        }
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

    private func handleUnfriend(_ user: BackendUser) {
        Task {
            do {
                try await friendService.removeFriend(user)
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

    private func handleBlock(_ user: BackendUser) {
        Task {
            do {
                try await friendService.blockUser(user)
                // Remove from search results
                await MainActor.run {
                    searchResults.removeAll { $0.user_id == user.user_id }
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
        FriendSearchView(friendService: FriendService())
    }
}
