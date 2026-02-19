import SwiftUI

struct CompetitionDetailView: View {
    @State var competition: Competition
    @ObservedObject var competitionService: CompetitionService
    @Environment(\.dismiss) var dismiss
    @StateObject private var friendService = FriendService()

    @State private var showingInviteFriend = false
    @State private var isStarting = false
    @State private var isDeleting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea(.all)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: MADTheme.Spacing.xl) {
                    // Header (shared across all states)
                    headerSection

                    // Status-specific content
                    switch competition.status {
                    case .lobby, .scheduled:
                        lobbyContent
                    case .active:
                        activeContent
                    case .finished:
                        finishedContent
                    }
                }
                .padding(MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle(competition.competition_name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
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
        .confirmationDialog("Delete Competition?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteCompetition() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
        .task {
            await refreshCompetition()
        }
        .refreshable {
            await refreshCompetition()
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
                HStack(spacing: MADTheme.Spacing.sm) {
                    Text(competition.type.displayName)
                        .font(MADTheme.Typography.title3)
                        .foregroundColor(.white.opacity(0.7))

                    if competition.isOwner {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }

                    // Status badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(competition.status.color)
                            .frame(width: 6, height: 6)
                        Text(competition.status.displayName)
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(competition.status.color)
                    }
                    .padding(.horizontal, MADTheme.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(competition.status.color.opacity(0.15))
                    )
                }

                Text(competition.type.description)
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MADTheme.Spacing.xl)
            }
        }
    }

    // MARK: - Lobby Content
    private var lobbyContent: some View {
        VStack(spacing: MADTheme.Spacing.xl) {
            // Waiting indicator
            lobbyWaitingBanner

            // Competition settings summary
            infoSection

            // Participants with invite statuses
            lobbyParticipantsSection

            // Invite more friends button
            if competition.currentUserInviteStatus == .accepted {
                inviteButton
            }

            // Start button (owner only)
            if competition.isOwner {
                startCompetitionButton
            }
        }
    }

    private var lobbyWaitingBanner: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.orange)
                Text("\(competition.acceptedUsersCount) of \(competition.users.count) joined")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.white)
            }

            Text("Waiting for everyone to accept...")
                .font(MADTheme.Typography.callout)
                .foregroundColor(.white.opacity(0.6))

            ProgressView(
                value: Double(competition.acceptedUsersCount),
                total: Double(max(competition.users.count, 1))
            )
            .tint(.orange)
            .padding(.horizontal, MADTheme.Spacing.xl)
        }
        .padding(MADTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var lobbyParticipantsSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Challengers")
                .font(MADTheme.Typography.title3)
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(competition.users) { user in
                    LobbyParticipantRow(
                        user: user,
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
        }
    }

    private var startCompetitionButton: some View {
        let canStart = competition.acceptedUsersCount >= 2

        return Button {
            startCompetition()
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                Image(systemName: "flag.checkered")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Competition")
                        .font(MADTheme.Typography.headline)

                    if !canStart {
                        let needed = 2 - competition.acceptedUsersCount
                        Text("Need \(needed) more participant\(needed == 1 ? "" : "s")")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                if isStarting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.right")
                }
            }
            .foregroundColor(.white)
            .padding(MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(canStart ? MADTheme.Colors.primaryGradient : LinearGradient(colors: [.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
            )
        }
        .disabled(!canStart || isStarting)
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Active Content
    private var activeContent: some View {
        VStack(spacing: MADTheme.Spacing.xl) {
            // Time remaining countdown
            if let endDate = competition.endDateFormatted {
                timeRemainingBanner(endDate: endDate)
            }

            // Competition leaderboard
            competitionLeaderboard

            // Competition info
            infoSection
        }
    }

    private func timeRemainingBanner(endDate: Date) -> some View {
        let remaining = endDate.timeIntervalSince(Date())
        let days = Int(remaining / 86400)
        let hours = Int(remaining.truncatingRemainder(dividingBy: 86400) / 3600)
        let minutes = Int(remaining.truncatingRemainder(dividingBy: 3600) / 60)

        return HStack {
            Image(systemName: "timer")
                .foregroundColor(.green)

            if remaining <= 0 {
                Text("Competition ending...")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.white)
            } else if days > 0 {
                Text("\(days)d \(hours)h remaining")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.white)
            } else {
                Text("\(hours)h \(minutes)m remaining")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.white)
            }

            Spacer()
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var competitionLeaderboard: some View {
        let currentUserId = UserDefaults.standard.string(forKey: "user_id")
        let rankedUsers = competition.users
            .filter { $0.invite_status == .accepted }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Leaderboard")
                .font(MADTheme.Typography.title3)
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.sm)

            if rankedUsers.isEmpty {
                Text("No participants yet")
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(MADTheme.Spacing.lg)
            } else {
                VStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(Array(rankedUsers.enumerated()), id: \.element.id) { index, user in
                        CompetitionLeaderboardRow(
                            rank: index + 1,
                            user: user,
                            competitionType: competition.type,
                            unit: competition.options.unit,
                            isCurrentUser: user.user_id == currentUserId
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
                                        colors: competition.type.gradient.map { Color(hex: $0).opacity(0.3) } + [Color.clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
            }
        }
    }

    // MARK: - Finished Content
    private var finishedContent: some View {
        let rankedUsers = competition.users
            .filter { $0.invite_status == .accepted }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }

        return VStack(spacing: MADTheme.Spacing.xl) {
            // Winner announcement
            if let winner = rankedUsers.first {
                VStack(spacing: MADTheme.Spacing.md) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text("\(winner.displayName) Wins!")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(scoreLabel(for: winner))
                        .font(MADTheme.Typography.callout)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(MADTheme.Spacing.xl)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.yellow.opacity(0.4), Color.orange.opacity(0.2), Color.clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
            }

            // Final standings
            competitionLeaderboard

            // Competition info
            infoSection
        }
    }

    // MARK: - Info Section (shared)
    private var infoSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            // Goal (not shown for Clash - whoever goes furthest wins)
            if competition.type != .clash {
                InfoRow(
                    icon: "target",
                    title: "Goal",
                    value: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
                )
            }

            // Duration
            if let startDate = competition.startDateFormatted,
               let endDate = competition.endDateFormatted {
                InfoRow(
                    icon: "calendar",
                    title: "Duration",
                    value: "\(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))"
                )
            } else if let durationStr = competition.options.durationFormatted {
                InfoRow(
                    icon: "clock",
                    title: "Duration",
                    value: durationStr
                )
            } else {
                InfoRow(
                    icon: "infinity",
                    title: "Duration",
                    value: "Open-ended"
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

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if competition.isOwner {
                Menu {
                    if competition.status == .lobby || competition.status == .scheduled {
                        Button {
                            showingInviteFriend = true
                        } label: {
                            Label("Invite Friends", systemImage: "person.badge.plus")
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
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

    // MARK: - Actions
    private func refreshCompetition() async {
        do {
            competition = try await competitionService.loadCompetition(id: competition.competition_id)
        } catch {
            print("Error refreshing competition: \(error)")
        }
    }

    private func startCompetition() {
        isStarting = true
        Task {
            do {
                competition = try await competitionService.startCompetition(id: competition.competition_id)
                isStarting = false
            } catch {
                isStarting = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func deleteCompetition() {
        isDeleting = true
        Task {
            do {
                try await competitionService.deleteCompetition(id: competition.competition_id)
                dismiss()
            } catch {
                isDeleting = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func scoreLabel(for user: CompetitionUser) -> String {
        let score = user.score ?? 0
        switch competition.type {
        case .streaks:
            return "\(Int(score)) day streak"
        case .apex:
            return String(format: "%.1f %@", score, competition.options.unit.shortDisplayName)
        case .targets:
            return "\(Int(score)) point\(Int(score) == 1 ? "" : "s")"
        case .clash:
            return "\(Int(score)) win\(Int(score) == 1 ? "" : "s")"
        case .race:
            return String(format: "%.1f %@", score, competition.options.unit.shortDisplayName)
        }
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
                start_date: nil,
                end_date: nil,
                workouts: [.run],
                type: .streaks,
                options: CompetitionOptions(
                    goal: 1.0,
                    unit: .miles,
                    first_to: 5,
                    history: false,
                    interval: .day,
                    duration_hours: 168
                ),
                owner: "peter",
                users: [
                    CompetitionUser(
                        competition_id: "test123",
                        user_id: "peter",
                        invite_status: .accepted,
                        username: "peter",
                        score: nil,
                        intervals: nil
                    ),
                    CompetitionUser(
                        competition_id: "test123",
                        user_id: "mary",
                        invite_status: .pending,
                        username: "mj",
                        score: nil,
                        intervals: nil
                    )
                ]
            ),
            competitionService: CompetitionService()
        )
    }
}
