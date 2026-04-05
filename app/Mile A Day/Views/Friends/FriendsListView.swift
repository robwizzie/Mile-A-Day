import SwiftUI

/// Main view for managing friends list
struct FriendsListView: View {
    @ObservedObject var friendService: FriendService
    @State private var selectedTab = 0
    @State private var showingSearch = false
    @State private var selectedUser: BackendUser?
    @State private var showingUnfriendAlert = false
    @State private var showingBlockAlert = false
    @State private var userToUnfriend: BackendUser?
    @State private var userToBlock: BackendUser?

    // Nudge state
    @State private var nudgeStatuses: [String: NudgeStatusResponse] = [:]
    @State private var nudgingFriendId: String?
    @State private var nudgeFeedback: NudgeFeedback?

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
                // Handle cold-launch deep link
                if MADNotificationService.shared.pendingNotificationType == "friend_request" {
                    selectedTab = 1
                    MADNotificationService.shared.pendingNotificationType = nil
                }
                // Load nudge statuses for friends
                await loadNudgeStatuses()
            }
            .refreshable {
                await friendService.refreshAllData()
                await loadNudgeStatuses()
            }
            .onReceive(NotificationCenter.default.publisher(for: .didTapPushNotification)) { notification in
                guard let type = notification.userInfo?["type"] as? String else { return }
                if type == "friend_request" {
                    selectedTab = 1
                }
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
            .overlay(alignment: .top) {
                if let feedback = nudgeFeedback {
                    nudgeFeedbackBanner(feedback)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                        .padding(.top, 8)
                }
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
                    showCountAsNotification: false,
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
                    showCountAsNotification: false,
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
                            friendRow(friend: friend)
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
        }
    }

    // MARK: - Friend Row with Nudge
    private func friendRow(friend: BackendUser) -> some View {
        let status = nudgeStatuses[friend.user_id]
        let canNudge = status?.can_nudge ?? false
        let hasCompletedMile = status?.has_completed_mile ?? false
        let alreadyNudged = status?.already_nudged_today ?? false

        return UserProfileCard(
            user: friend,
            onTap: {
                selectedUser = friend
            },
            actionButton: AnyView(
                HStack(spacing: MADTheme.Spacing.sm) {
                    // Nudge button
                    nudgeButton(
                        friend: friend,
                        canNudge: canNudge,
                        hasCompletedMile: hasCompletedMile,
                        alreadyNudged: alreadyNudged
                    )

                    // Friend menu
                    friendMenu(friend: friend)
                }
            )
        )
    }

    // MARK: - Nudge Button
    private func nudgeButton(friend: BackendUser, canNudge: Bool, hasCompletedMile: Bool, alreadyNudged: Bool) -> some View {
        Group {
            if hasCompletedMile {
                // Friend completed their mile - show checkmark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.green.opacity(0.1))
                    )
            } else if alreadyNudged {
                // Already nudged today - show disabled bell
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.04))
                    )
            } else {
                // Can nudge - show nudge button
                Button {
                    handleNudge(friend)
                } label: {
                    ZStack {
                        if nudgingFriendId == friend.user_id {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.orange)
                        } else {
                            Image(systemName: "bell.badge")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.orange.opacity(0.12))
                            .overlay(
                                Circle()
                                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(nudgingFriendId != nil)
            }
        }
    }

    // MARK: - Friend Menu
    private func friendMenu(friend: BackendUser) -> some View {
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
    }

    // MARK: - Nudge Feedback Banner
    private func nudgeFeedbackBanner(_ feedback: NudgeFeedback) -> some View {
        HStack(spacing: 6) {
            Image(systemName: feedback.icon)
                .font(.system(size: 12))
            Text(feedback.message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundColor(feedback.isError ? .red : .green)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(feedback.isError ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
        )
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
                                showDetails: false,
                                onTap: {
                                    selectedUser = request
                                },
                                actionButton: AnyView(
                                    VStack(spacing: MADTheme.Spacing.sm) {
                                        // Accept button
                                        Button(action: {
                                            handleAcceptRequest(request)
                                        }) {
                                            HStack(spacing: MADTheme.Spacing.xs) {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .semibold))
                                                Text("Accept")
                                                    .font(MADTheme.Typography.smallBold)
                                            }
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
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
                                            HStack(spacing: MADTheme.Spacing.xs) {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 12, weight: .semibold))
                                                Text("Decline")
                                                    .font(MADTheme.Typography.smallBold)
                                            }
                                            .foregroundColor(.white.opacity(0.7))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, MADTheme.Spacing.sm)
                                            .background(
                                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                                                    .fill(Color.red.opacity(0.2))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                                                            .stroke(Color.red.opacity(0.4), lineWidth: 1)
                                                    )
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .frame(width: 90)
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

    // MARK: - Nudge Methods
    private func loadNudgeStatuses() async {
        let friendIds = friendService.friends.map { $0.user_id }
        guard !friendIds.isEmpty else { return }

        do {
            let statuses = try await friendService.checkNudgeStatusBatch(friendIds: friendIds)
            await MainActor.run {
                self.nudgeStatuses = statuses
            }
        } catch {
            // Silently fail - nudge buttons just won't show
        }
    }

    private func handleNudge(_ friend: BackendUser) {
        nudgingFriendId = friend.user_id
        Task {
            do {
                try await friendService.nudgeFriend(friend.user_id)
                await MainActor.run {
                    nudgingFriendId = nil
                    FlexNudgeTracker.markFriendNudgeSent(friendId: friend.user_id)
                    // Update local status
                    nudgeStatuses[friend.user_id] = NudgeStatusResponse(
                        can_nudge: false,
                        has_completed_mile: false,
                        already_nudged_today: true
                    )
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showNudgeFeedback(NudgeFeedback(
                        icon: "bell.badge.fill",
                        message: "Nudge sent to \(friend.displayName)!",
                        isError: false
                    ))
                }
            } catch {
                await MainActor.run {
                    nudgingFriendId = nil
                    showNudgeFeedback(NudgeFeedback(
                        icon: "xmark.circle",
                        message: error.localizedDescription,
                        isError: true
                    ))
                }
            }
        }
    }

    private func showNudgeFeedback(_ feedback: NudgeFeedback) {
        withAnimation(.easeInOut(duration: 0.2)) { nudgeFeedback = feedback }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.2)) { nudgeFeedback = nil }
        }
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

// MARK: - Nudge Feedback Model
private struct NudgeFeedback: Equatable {
    let icon: String
    let message: String
    let isError: Bool
}

// MARK: - Tab Button Component
struct TabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    var showCountAsNotification: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: MADTheme.Spacing.xs) {
                HStack(spacing: MADTheme.Spacing.xs) {
                    Text(title)
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(isSelected ? MADTheme.Colors.madRed : MADTheme.Colors.secondaryText)

                    if count > 0 {
                        if showCountAsNotification {
                            Text("\(count)")
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, MADTheme.Spacing.sm)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(MADTheme.Colors.madRed)
                                )
                        } else {
                            Text("(\(count))")
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(isSelected ? MADTheme.Colors.madRed.opacity(0.7) : MADTheme.Colors.secondaryText.opacity(0.7))
                        }
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
        FriendsListView(friendService: FriendService())
    }
}
