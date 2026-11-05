import SwiftUI

/// A browsable list of a given user's friends — the destination when you tap
/// the "Friends" tile on a profile (your own or someone else's). A plain,
/// searchable A–Z list on one flat surface: each row opens that person's
/// profile, and only people you're NOT already friends with get an action
/// (Add / Accept / Sent); a "Friends" pill on every row of your own list
/// said nothing.
struct UserFriendsListView: View {
    let userId: String
    /// Display name of whose friends these are, for the empty-state copy.
    let ownerName: String
    @ObservedObject var friendService: FriendService

    @State private var friends: [BackendUser] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var selectedUser: BackendUser?
    @State private var query = ""

    /// A–Z by the name the row leads with, filtered by the search field.
    private var shownFriends: [BackendUser] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = trimmed.isEmpty ? friends : friends.filter {
            ($0.username ?? "").localizedCaseInsensitiveContains(trimmed)
                || $0.displayName.localizedCaseInsensitiveContains(trimmed)
        }
        return matching.sorted {
            sortKey($0).localizedCaseInsensitiveCompare(sortKey($1)) == .orderedAscending
        }
    }

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
                    let rows = shownFriends
                    if rows.isEmpty {
                        Text("No friends match “\(query)”")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.top, MADTheme.Spacing.xl)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, user in
                                if index > 0 {
                                    Divider()
                                        .overlay(Color.white.opacity(0.06))
                                        .padding(.leading, 68)
                                }
                                row(user)
                            }
                        }
                        .padding(.vertical, 4)
                        .background(DashboardCardSurface(style: .fun))
                        .padding(MADTheme.Spacing.md)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search friends")
        .sheet(item: $selectedUser) { user in
            NavigationStack {
                UserProfileDetailView(user: user, friendService: friendService)
            }
        }
        .task { await load() }
    }

    // MARK: - Row

    private func row(_ user: BackendUser) -> some View {
        HStack(spacing: 12) {
            Button {
                MADHaptics.tap()
                selectedUser = user
            } label: {
                HStack(spacing: 12) {
                    AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.username.map { "@\($0)" } ?? user.displayName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if let username = user.username, user.displayName != username {
                            Text(user.displayName)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // A sibling of the row's button, never nested inside its label.
            if showsAction(for: user) {
                FriendActionButton(
                    title: actionTitle(for: user),
                    style: actionStyle(for: user),
                    isLoading: false,
                    action: { handleAction(for: user) }
                )
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, DashboardCardSurface.padding)
        .padding(.vertical, 10)
    }

    private func sortKey(_ user: BackendUser) -> String {
        if let username = user.username, !username.isEmpty { return username }
        return user.displayName
    }

    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.25))
                .accessibilityHidden(true)
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

    /// Yourself and existing friends get no button: the row's tap opens the
    /// profile, where the friendship's own controls live.
    private func showsAction(for user: BackendUser) -> Bool {
        // Your OWN list is all friends by definition, even when the service
        // handed in hasn't loaded its friends list (the profile's own one
        // only fetches the count).
        guard !isOwnList else { return false }
        return !isCurrentUser(user) && !friendService.isFriend(user)
    }

    private var isOwnList: Bool {
        UserDefaults.standard.string(forKey: "backendUserId") == userId
    }

    private func actionTitle(for user: BackendUser) -> String {
        if friendService.hasPendingRequest(from: user) { return "Accept" }
        if friendService.hasSentRequest(to: user) { return "Sent" }
        return "Add"
    }

    private func actionStyle(for user: BackendUser) -> FriendActionStyle {
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
