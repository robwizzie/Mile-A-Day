import SwiftUI

struct CompetitionDetailView: View {
    let competition: Competition
    @ObservedObject var competitionService: CompetitionService
    @Environment(\.dismiss) var dismiss
    @StateObject private var friendService = FriendService()

    @State private var showingInviteFriend = false
    @State private var selectedFriend: BackendUser?
    @State private var isInviting = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea(.all)

            ScrollView {
                VStack(spacing: MADTheme.Spacing.xl) {
                    // Header
                    headerSection

                    // Competition Info
                    infoSection

                    // Participants
                    participantsSection

                    // Invite Button (if user is accepted participant)
                    if competition.currentUserInviteStatus == .accepted {
                        inviteButton
                    }
                }
                .padding(MADTheme.Spacing.md)
            }
        }
        .navigationTitle(competition.competition_name)
        .navigationBarTitleDisplayMode(.inline)
        // iOS 26: Liquid Glass is automatic - no toolbar modifiers needed
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if competition.isOwner {
                    Menu {
                        Button(role: .destructive) {
                            // Handle delete
                        } label: {
                            Label("Delete Competition", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .sheet(isPresented: $showingInviteFriend) {
            InviteFriendView(
                competition: competition,
                competitionService: competitionService,
                friendService: friendService
            )
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            Task {
                await friendService.refreshAllData()
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            // Type icon
            Image(systemName: competition.type.icon)
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: competition.type.gradient.map { Color(hex: $0) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .background(
                    Circle()
                        .fill(Color(hex: competition.type.gradient[0]).opacity(0.15))
                )

            VStack(spacing: MADTheme.Spacing.sm) {
                HStack {
                    Text(competition.type.displayName)
                        .font(MADTheme.Typography.title3)
                        .foregroundColor(.white.opacity(0.7))

                    if competition.isOwner {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }

                Text(competition.type.description)
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MADTheme.Spacing.xl)
            }
        }
    }

    // MARK: - Info Section
    private var infoSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            // Goal
            InfoRow(
                icon: "target",
                title: "Goal",
                value: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
            )

            // Duration
            if let startDate = competition.startDateFormatted,
               let endDate = competition.endDateFormatted {
                InfoRow(
                    icon: "calendar",
                    title: "Duration",
                    value: "\(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))"
                )
            }

            // Workouts
            InfoRow(
                icon: "figure.run",
                title: "Activities",
                value: competition.workouts.map { $0.displayName }.joined(separator: ", ")
            )

            // Interval (if applicable)
            if let interval = competition.options.interval {
                InfoRow(
                    icon: "clock",
                    title: "Interval",
                    value: interval.displayName
                )
            }

            // First to (if applicable)
            if competition.type == .streaks || competition.type == .clash {
                InfoRow(
                    icon: "number",
                    title: competition.type == .streaks ? "Breaks to Lose" : "Wins to Win",
                    value: "\(competition.options.first_to)"
                )
            }

            // History
            if let history = competition.options.history {
                InfoRow(
                    icon: "clock.arrow.circlepath",
                    title: "Historical Data",
                    value: history ? "Included" : "Not Included"
                )
            }
        }
        .padding(MADTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    // MARK: - Participants Section
    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Participants (\(competition.acceptedUsersCount) accepted)")
                .font(MADTheme.Typography.title3)
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(competition.users) { user in
                    ParticipantRow(
                        userId: user.user_id,
                        status: user.invite_status,
                        isOwner: user.user_id == competition.owner
                    )
                }
            }
            .padding(MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.2), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
    }

    // MARK: - Invite Button
    private var inviteButton: some View {
        Button(action: {
            showingInviteFriend = true
        }) {
            HStack {
                Image(systemName: "person.badge.plus")
                    .font(.title3)

                Text("Invite Friends")
                    .font(MADTheme.Typography.callout)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(MADTheme.Colors.primaryGradient)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(MADTheme.Colors.madRed)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.7))

                Text(value)
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white)
            }

            Spacer()
        }
    }
}

// MARK: - Participant Row
struct ParticipantRow: View {
    let userId: String
    let status: InviteStatus
    let isOwner: Bool

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            // Avatar placeholder
            Circle()
                .fill(MADTheme.Colors.primaryGradient)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(userId.prefix(1).uppercased())
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MADTheme.Spacing.xs) {
                    Text(userId)
                        .font(MADTheme.Typography.callout)
                        .foregroundColor(.white)

                    if isOwner {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }

                Text(status.displayName)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(statusColor)
            }

            Spacer()

            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
    }

    private var statusColor: Color {
        switch status {
        case .accepted:
            return .green
        case .pending:
            return .orange
        case .declined:
            return .red
        }
    }
}

// MARK: - Invite Friend View
struct InviteFriendView: View {
    let competition: Competition
    @ObservedObject var competitionService: CompetitionService
    @ObservedObject var friendService: FriendService
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var isInviting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false

    var filteredFriends: [BackendUser] {
        if searchText.isEmpty {
            return friendService.friends.filter { friend in
                !competition.users.contains { $0.user_id == friend.user_id }
            }
        } else {
            return friendService.friends.filter { friend in
                !competition.users.contains { $0.user_id == friend.user_id } &&
                (friend.username?.lowercased().contains(searchText.lowercased()) ?? false ||
                 friend.displayName.lowercased().contains(searchText.lowercased()))
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea(.all)

                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.5))

                        TextField("Search friends...", text: $searchText)
                            .foregroundColor(.white)
                    }
                    .padding(MADTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .fill(.ultraThinMaterial)
                    )
                    .padding(MADTheme.Spacing.md)

                    // Friends list
                    if filteredFriends.isEmpty {
                        VStack(spacing: MADTheme.Spacing.md) {
                            Image(systemName: "person.2.slash")
                                .font(.system(size: 50))
                                .foregroundColor(.white.opacity(0.5))

                            Text(searchText.isEmpty ? "All friends are already invited" : "No friends found")
                                .font(MADTheme.Typography.body)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: MADTheme.Spacing.sm) {
                                ForEach(filteredFriends) { friend in
                                    FriendInviteRow(
                                        friend: friend,
                                        onInvite: {
                                            inviteFriend(friend)
                                        }
                                    )
                                }
                            }
                            .padding(MADTheme.Spacing.md)
                        }
                    }
                }
            }
            .navigationTitle("Invite Friends")
            .navigationBarTitleDisplayMode(.inline)
            // iOS 26: Liquid Glass is automatic - no toolbar modifiers needed
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Success!", isPresented: $showSuccess) {
                Button("OK") { }
            } message: {
                Text("Friend invited successfully!")
            }
        }
    }

    private func inviteFriend(_ friend: BackendUser) {
        isInviting = true

        Task {
            do {
                try await competitionService.inviteUser(
                    competitionId: competition.competition_id,
                    userId: friend.user_id
                )

                await MainActor.run {
                    isInviting = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isInviting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Friend Invite Row
struct FriendInviteRow: View {
    let friend: BackendUser
    let onInvite: () -> Void

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            // Avatar
            Circle()
                .fill(MADTheme.Colors.primaryGradient)
                .frame(width: 50, height: 50)
                .overlay(
                    Text(friend.displayName.prefix(1).uppercased())
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white)

                if let username = friend.username {
                    Text("@\(username)")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Spacer()

            Button(action: onInvite) {
                Text("Invite")
                    .font(MADTheme.Typography.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, MADTheme.Spacing.lg)
                    .padding(.vertical, MADTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.pill)
                            .fill(MADTheme.Colors.primaryGradient)
                    )
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

#Preview {
    NavigationStack {
        CompetitionDetailView(
            competition: Competition(
                competition_id: "test123",
                competition_name: "Summer Challenge",
                start_date: "2025-06-01",
                end_date: "2025-08-31",
                workouts: [.run],
                type: .streaks,
                options: CompetitionOptions(
                    goal: 1.0,
                    unit: .miles,
                    first_to: 5,
                    history: false,
                    interval: .day
                ),
                owner: "peter",
                users: [
                    CompetitionUser(
                        competition_id: "test123",
                        user_id: "peter",
                        invite_status: .accepted
                    )
                ]
            ),
            competitionService: CompetitionService()
        )
    }
}
