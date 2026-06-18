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
    @State private var userToUnfriend: BackendUser?
    @FocusState private var isSearchFocused: Bool

    // "People you may know" shown while the search field is empty.
    @State private var suggestions: [FriendSuggestion] = []
    @State private var isLoadingSuggestions = false
    @State private var hasLoadedSuggestions = false

    // In-app QR scanning.
    @State private var showingScanner = false
    @State private var scanError: String?
    @State private var isResolvingScan = false

    var body: some View {
        VStack(spacing: 0) {
            // Always-visible search bar — replaces the system .searchable
            // drawer, which stayed hidden until the user pulled down on the
            // content and was easy to miss entirely.
            searchBar
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.top, MADTheme.Spacing.sm)
                .padding(.bottom, MADTheme.Spacing.sm)

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
        }
        .background(MADTheme.Colors.appBackgroundGradient.ignoresSafeArea())
        .navigationTitle("Find Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel("Scan a friend's QR code")
            }
        }
        .task {
            await loadSuggestions()
        }
        .sheet(item: $selectedUser) { user in
            NavigationStack {
                UserProfileDetailView(user: user, friendService: friendService)
            }
        }
        .sheet(isPresented: $showingScanner) {
            QRScannerView { code in
                handleScannedCode(code)
            }
        }
        .overlay {
            if isResolvingScan {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.4)
                }
            }
        }
        .alert("Couldn't Open Profile", isPresented: Binding(
            get: { scanError != nil },
            set: { if !$0 { scanError = nil } }
        )) {
            Button("OK", role: .cancel) { scanError = nil }
        } message: {
            Text(scanError ?? "")
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
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))

            TextField(
                "",
                text: $searchText,
                prompt: Text("Search by username")
                    .foregroundColor(.white.opacity(0.4))
            )
            .font(MADTheme.Typography.body)
            .foregroundColor(.white)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Search Results View
    private var searchResultsView: some View {
        ScrollView {
            LazyVStack(spacing: MADTheme.Spacing.md) {
                ForEach(searchResults) { user in
                    UserProfileCard(
                        user: user,
                        subtitle: searchSubtitle(for: user),
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
        .scrollDismissesKeyboard(.interactively)
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

                Text("We couldn't find any users matching '\(searchText)'. Try a different search term.")
                    .font(MADTheme.Typography.body)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MADTheme.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MADTheme.Spacing.xl)
    }

    // MARK: - Recommendations View ("People You May Know" + invite)
    private var recommendationsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                inviteFriendsCard

                if isLoadingSuggestions && suggestions.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                        Spacer()
                    }
                    .padding(.top, MADTheme.Spacing.xl)
                } else if !suggestions.isEmpty {
                    Text("PEOPLE YOU MAY KNOW")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.4)
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 4)
                        .padding(.top, MADTheme.Spacing.sm)

                    ForEach(suggestions) { suggestion in
                        UserProfileCard(
                            user: suggestion.user,
                            subtitle: suggestion.reasonText.isEmpty ? nil : suggestion.reasonText,
                            showStats: false,
                            showBadges: false,
                            showDetails: false,
                            onTap: {
                                selectedUser = suggestion.user
                            },
                            actionButton: AnyView(
                                FriendActionButton(
                                    title: getActionButtonTitle(for: suggestion.user),
                                    style: getActionButtonStyle(for: suggestion.user),
                                    isLoading: false,
                                    action: {
                                        handleFriendAction(for: suggestion.user)
                                    }
                                )
                            )
                        )
                    }
                } else if hasLoadedSuggestions {
                    VStack(spacing: MADTheme.Spacing.sm) {
                        Image(systemName: "person.2.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(MADTheme.Colors.madRed)

                        Text("Discover Runners")
                            .font(MADTheme.Typography.title2)
                            .foregroundColor(MADTheme.Colors.primaryText)

                        Text("Search by username to find people you know")
                            .font(MADTheme.Typography.body)
                            .foregroundColor(MADTheme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, MADTheme.Spacing.xxl)
                }
            }
            .padding(MADTheme.Spacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Entry point to profile sharing — pushed so there's no extra sheet
    /// layered onto this screen.
    private var inviteFriendsCard: some View {
        NavigationLink {
            ShareProfileView()
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                Image(systemName: "qrcode")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(MADTheme.Colors.madRed)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(MADTheme.Colors.madRed.opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite Friends")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Share your profile link or QR code")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func loadSuggestions() async {
        guard !hasLoadedSuggestions else { return }
        isLoadingSuggestions = true
        do {
            suggestions = try await friendService.getSuggestions()
        } catch {
            // Suggestions are best-effort; the screen falls back to the
            // plain "search by username" hint.
            print("[FriendSearchView] ❌ Failed to load suggestions: \(error)")
        }
        isLoadingSuggestions = false
        hasLoadedSuggestions = true
    }

    // MARK: - QR Scan Handling

    /// Parses a scanned QR payload (mileaday://u/<username> or the web link),
    /// looks up the user, and presents their profile with an Add Friend button.
    private func handleScannedCode(_ code: String) {
        showingScanner = false

        guard let url = URL(string: code.trimmingCharacters(in: .whitespacesAndNewlines)),
              let username = DeepLinkRouter.shared.username(from: url) else {
            scanError = "That QR code isn't a Mile A Day profile."
            return
        }

        isResolvingScan = true
        Task {
            do {
                let users = try await friendService.searchUsers(byUsername: username)
                let match = users.first { $0.username?.lowercased() == username } ?? users.first
                await MainActor.run {
                    isResolvingScan = false
                    if let match {
                        selectedUser = match
                    } else {
                        scanError = "Couldn't find @\(username)."
                    }
                }
            } catch {
                await MainActor.run {
                    isResolvingScan = false
                    scanError = error.localizedDescription
                }
            }
        }
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
    
    /// Real name shown under the @username in search results, so name-based
    /// matches make sense (e.g. searching "rob" surfacing @runner42 · Rob Smith).
    /// Returns nil when there's no distinct real name to add.
    private func searchSubtitle(for user: BackendUser) -> String? {
        let name = user.displayName
        guard name != (user.username ?? ""), name != "Unknown User", !name.isEmpty else {
            return nil
        }
        return name
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

}

// MARK: - Preview
struct FriendSearchView_Previews: PreviewProvider {
    static var previews: some View {
        FriendSearchView(friendService: FriendService())
    }
}
