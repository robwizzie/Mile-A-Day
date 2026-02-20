import SwiftUI

struct CompetitionDetailView: View {
    @State var competition: Competition
    @ObservedObject var competitionService: CompetitionService
    @Environment(\.dismiss) var dismiss
    @StateObject private var friendService = FriendService()

    @State private var showingInviteFriend = false
    @State private var showingEditSettings = false
    @State private var isStarting = false
    @State private var isDeleting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showDeleteConfirmation = false
    @State private var selectedIntervalDate: Date = Date()
    @State private var showCelebration = false
    @State private var podiumAnimated = false

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
        .sheet(isPresented: $showingEditSettings) {
            EditCompetitionSettingsView(
                competition: $competition,
                competitionService: competitionService
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
            // Status banner - countdown if scheduled, waiting banner if lobby
            if competition.status == .scheduled {
                scheduledCountdownBanner
            } else {
                lobbyWaitingBanner
            }

            // Competition settings summary
            infoSection

            // Edit settings button (owner only, lobby only)
            if competition.isOwner && competition.status == .lobby {
                Button {
                    showingEditSettings = true
                } label: {
                    HStack(spacing: MADTheme.Spacing.sm) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.callout)
                        Text("Edit Settings")
                            .font(MADTheme.Typography.callout)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MADTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }

            // Participants with invite statuses
            lobbyParticipantsSection

            // Invite more friends button
            if competition.currentUserInviteStatus == .accepted {
                inviteButton
            }

            // Start button (owner only, lobby only - not if already scheduled)
            if competition.isOwner && competition.status == .lobby {
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

    private var scheduledCountdownBanner: some View {
        let startDate = competition.startDateFormatted ?? Date()
        let remaining = startDate.timeIntervalSince(Date())
        let hours = max(0, Int(remaining / 3600))
        let minutes = max(0, Int(remaining.truncatingRemainder(dividingBy: 3600) / 60))

        return VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 32))
                .foregroundColor(.blue)

            Text("Competition Starts Soon")
                .font(MADTheme.Typography.headline)
                .foregroundColor(.white)

            // Countdown display
            HStack(spacing: MADTheme.Spacing.lg) {
                VStack(spacing: 2) {
                    Text("\(hours)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("hours")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.5))
                }

                Text(":")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))

                VStack(spacing: 2) {
                    Text("\(minutes)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("min")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            if let startDate = competition.startDateFormatted {
                Text("Begins \(startDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(MADTheme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
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
                    } else {
                        Text("Begins tomorrow at midnight")
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
            // Time remaining countdown (for timed competitions)
            if let endDate = competition.endDateFormatted {
                timeRemainingBanner(endDate: endDate)
            }

            // Interval navigator + mode content (race has no intervals)
            if competition.type != .race {
                intervalNavigator
                intervalContent
            } else {
                raceProgressView
            }

            // Overall standings
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

    // MARK: - Interval Navigator
    private var intervalNavigator: some View {
        let isToday = Calendar.current.isDateInToday(selectedIntervalDate)
        let canGoForward = !isToday
        let canGoBack: Bool = {
            guard let startDate = competition.startDateFormatted else { return true }
            return selectedIntervalDate > startDate
        }()

        return HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    moveInterval(by: -1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(canGoBack ? .white : .white.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .disabled(!canGoBack)

            Spacer()

            VStack(spacing: 2) {
                Text(intervalDateLabel)
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.white)

                if !isToday {
                    Text(selectedIntervalDate.formatted(date: .abbreviated, time: .omitted))
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    moveInterval(by: 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(canGoForward ? .white : .white.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .disabled(!canGoForward)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, MADTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Interval Content (mode-specific)
    @ViewBuilder
    private var intervalContent: some View {
        let key = intervalKey(for: selectedIntervalDate)
        let acceptedUsers = competition.users.filter { $0.invite_status == .accepted }
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")

        switch competition.type {
        case .clash:
            clashIntervalView(key: key, users: acceptedUsers, currentUserId: currentUserId)
        case .streaks:
            streaksIntervalView(key: key, users: acceptedUsers, currentUserId: currentUserId)
        case .apex:
            apexIntervalView(key: key, users: acceptedUsers, currentUserId: currentUserId)
        case .targets:
            targetsIntervalView(key: key, users: acceptedUsers, currentUserId: currentUserId)
        case .race:
            EmptyView()
        }
    }

    // MARK: - Clash Interval View
    private func clashIntervalView(key: String, users: [CompetitionUser], currentUserId: String?) -> some View {
        let sortedUsers = users.sorted {
            ($0.intervals?[key] ?? 0) > ($1.intervals?[key] ?? 0)
        }

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Matchup")
                .font(MADTheme.Typography.title3)
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(Array(sortedUsers.enumerated()), id: \.element.id) { index, user in
                    let distance = user.intervals?[key] ?? 0
                    let isLeading = index == 0 && distance > 0

                    HStack(spacing: MADTheme.Spacing.md) {
                        if isLeading {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                                .frame(width: 24)
                        } else {
                            Text("\(index + 1)")
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 24)
                        }

                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text(user.displayName.prefix(1).uppercased())
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            )

                        Text(user.displayName)
                            .font(MADTheme.Typography.callout)
                            .foregroundColor(.white)

                        Spacer()

                        Text(String(format: "%.1f %@", distance, competition.options.unit.shortDisplayName))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(isLeading ? .green : .white.opacity(0.8))
                    }
                    .padding(MADTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .fill(Color.white.opacity(user.user_id == currentUserId ? 0.1 : (isLeading ? 0.05 : 0)))
                            .overlay(
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                    .stroke(user.user_id == currentUserId ? MADTheme.Colors.primary : Color.clear, lineWidth: 1)
                            )
                    )
                }
            }
            .padding(MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Streaks Interval View
    private func streaksIntervalView(key: String, users: [CompetitionUser], currentUserId: String?) -> some View {
        let goal = competition.options.goal

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Streak Status")
                .font(MADTheme.Typography.title3)
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(users, id: \.id) { user in
                    let distance = user.intervals?[key] ?? 0
                    let completed = distance >= goal
                    let isToday = Calendar.current.isDateInToday(selectedIntervalDate)

                    HStack(spacing: MADTheme.Spacing.md) {
                        Image(systemName: completed ? "checkmark.circle.fill" : (isToday ? "circle.dotted" : "xmark.circle.fill"))
                            .font(.title3)
                            .foregroundColor(completed ? .green : (isToday ? .orange : .red))
                            .frame(width: 28)

                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text(user.displayName.prefix(1).uppercased())
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .font(MADTheme.Typography.callout)
                                .foregroundColor(.white)

                            Text(completed
                                ? "Completed \u{00B7} \(String(format: "%.1f", distance)) \(competition.options.unit.shortDisplayName)"
                                : (isToday ? "\(String(format: "%.1f", distance))/\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)" : "Missed"))
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(completed ? .green.opacity(0.8) : .white.opacity(0.5))
                        }

                        Spacer()

                        VStack(spacing: 1) {
                            Text("\(Int(user.score ?? 0))")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("streak")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .fill(Color.white.opacity(user.user_id == currentUserId ? 0.1 : 0))
                            .overlay(
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                    .stroke(user.user_id == currentUserId ? MADTheme.Colors.primary : Color.clear, lineWidth: 1)
                            )
                    )
                }
            }
            .padding(MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Apex Interval View
    private func apexIntervalView(key: String, users: [CompetitionUser], currentUserId: String?) -> some View {
        let sortedUsers = users.sorted {
            ($0.intervals?[key] ?? 0) > ($1.intervals?[key] ?? 0)
        }
        let intervalLabel = competition.options.interval == .week ? "Weekly" : (competition.options.interval == .month ? "Monthly" : (Calendar.current.isDateInToday(selectedIntervalDate) ? "Today's" : "Daily"))

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("\(intervalLabel) Activity")
                .font(MADTheme.Typography.title3)
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(sortedUsers, id: \.id) { user in
                    let distance = user.intervals?[key] ?? 0

                    HStack(spacing: MADTheme.Spacing.md) {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text(user.displayName.prefix(1).uppercased())
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            )

                        Text(user.displayName)
                            .font(MADTheme.Typography.callout)
                            .foregroundColor(.white)

                        Spacer()

                        Text(String(format: "%.1f %@", distance, competition.options.unit.shortDisplayName))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(MADTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .fill(Color.white.opacity(user.user_id == currentUserId ? 0.1 : 0))
                    )
                }
            }
            .padding(MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Targets Interval View
    private func targetsIntervalView(key: String, users: [CompetitionUser], currentUserId: String?) -> some View {
        let goal = competition.options.goal
        let intervalLabel = competition.options.interval == .week ? "Weekly" : (competition.options.interval == .month ? "Monthly" : "Daily")

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("\(intervalLabel) Targets")
                .font(MADTheme.Typography.title3)
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(users, id: \.id) { user in
                    let distance = user.intervals?[key] ?? 0
                    let hitTarget = distance >= goal
                    let progress = min(distance / max(goal, 0.1), 1.0)

                    VStack(spacing: MADTheme.Spacing.sm) {
                        HStack(spacing: MADTheme.Spacing.md) {
                            Image(systemName: hitTarget ? "target" : "circle")
                                .font(.title3)
                                .foregroundColor(hitTarget ? .green : .white.opacity(0.4))
                                .frame(width: 28)

                            Circle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text(user.displayName.prefix(1).uppercased())
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                )

                            Text(user.displayName)
                                .font(MADTheme.Typography.callout)
                                .foregroundColor(.white)

                            Spacer()

                            Text(String(format: "%.1f/%@ %@", distance, competition.options.goalFormatted, competition.options.unit.shortDisplayName))
                                .font(MADTheme.Typography.callout)
                                .foregroundColor(hitTarget ? .green : .white.opacity(0.7))
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 6)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(hitTarget ? Color.green : MADTheme.Colors.madRed)
                                    .frame(width: geo.size.width * progress, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(MADTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .fill(Color.white.opacity(user.user_id == currentUserId ? 0.1 : 0))
                    )
                }
            }
            .padding(MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Race Progress View
    private var raceProgressView: some View {
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        let goal = competition.options.goal
        let sortedUsers = competition.users
            .filter { $0.invite_status == .accepted }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Race Progress")
                .font(MADTheme.Typography.title3)
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(sortedUsers, id: \.id) { user in
                    let distance = user.score ?? 0
                    let progress = min(distance / max(goal, 0.1), 1.0)

                    VStack(spacing: MADTheme.Spacing.sm) {
                        HStack(spacing: MADTheme.Spacing.md) {
                            Circle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text(user.displayName.prefix(1).uppercased())
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                )

                            Text(user.displayName)
                                .font(MADTheme.Typography.callout)
                                .foregroundColor(.white)

                            Spacer()

                            Text(String(format: "%.1f/%@ %@", distance, competition.options.goalFormatted, competition.options.unit.shortDisplayName))
                                .font(MADTheme.Typography.callout)
                                .foregroundColor(.white.opacity(0.7))
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 8)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: competition.type.gradient.map { Color(hex: $0) },
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * progress, height: 8)
                            }
                        }
                        .frame(height: 8)
                    }
                    .padding(MADTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .fill(Color.white.opacity(user.user_id == currentUserId ? 0.1 : 0))
                    )
                }
            }
            .padding(MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Interval Helpers
    private func intervalKey(for date: Date) -> String {
        let calendar = Calendar.current
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let interval = competition.options.interval ?? .day

        switch interval {
        case .day:
            return formatter.string(from: calendar.startOfDay(for: date))
        case .week:
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            components.weekday = calendar.firstWeekday
            let startOfWeek = calendar.date(from: components) ?? date
            return formatter.string(from: startOfWeek)
        case .month:
            var components = calendar.dateComponents([.year, .month], from: date)
            components.day = 1
            let startOfMonth = calendar.date(from: components) ?? date
            return formatter.string(from: startOfMonth)
        }
    }

    private func moveInterval(by amount: Int) {
        let calendar = Calendar.current
        let interval = competition.options.interval ?? .day

        switch interval {
        case .day:
            selectedIntervalDate = calendar.date(byAdding: .day, value: amount, to: selectedIntervalDate) ?? selectedIntervalDate
        case .week:
            selectedIntervalDate = calendar.date(byAdding: .weekOfYear, value: amount, to: selectedIntervalDate) ?? selectedIntervalDate
        case .month:
            selectedIntervalDate = calendar.date(byAdding: .month, value: amount, to: selectedIntervalDate) ?? selectedIntervalDate
        }

        // Don't go past today
        if selectedIntervalDate > Date() {
            selectedIntervalDate = Date()
        }
    }

    private var intervalDateLabel: String {
        let calendar = Calendar.current
        let interval = competition.options.interval ?? .day

        switch interval {
        case .day:
            if calendar.isDateInToday(selectedIntervalDate) {
                return "Today"
            } else if calendar.isDateInYesterday(selectedIntervalDate) {
                return "Yesterday"
            } else {
                return selectedIntervalDate.formatted(date: .abbreviated, time: .omitted)
            }
        case .week:
            if calendar.isDate(Date(), equalTo: selectedIntervalDate, toGranularity: .weekOfYear) {
                return "This Week"
            }
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedIntervalDate)
            components.weekday = calendar.firstWeekday
            let startOfWeek = calendar.date(from: components) ?? selectedIntervalDate
            let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek) ?? selectedIntervalDate
            return "\(startOfWeek.formatted(.dateTime.month(.abbreviated).day())) - \(endOfWeek.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            if calendar.isDate(Date(), equalTo: selectedIntervalDate, toGranularity: .month) {
                return "This Month"
            }
            return selectedIntervalDate.formatted(.dateTime.month(.wide).year())
        }
    }

    private var competitionLeaderboard: some View {
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
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
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        let myPlacement = rankedUsers.firstIndex(where: { $0.user_id == currentUserId }).map { $0 + 1 }

        return VStack(spacing: MADTheme.Spacing.xl) {
            // Celebration header with confetti
            ZStack {
                if showCelebration && myPlacement == 1 {
                    CompetitionConfettiView()
                }

                VStack(spacing: MADTheme.Spacing.md) {
                    Image(systemName: myPlacement == 1 ? "trophy.fill" : "flag.checkered")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: medalGradient(for: myPlacement),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(showCelebration ? 1.0 : 0.3)
                        .opacity(showCelebration ? 1.0 : 0)

                    Text("COMPETITION COMPLETE")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(3)

                    if let winner = rankedUsers.first {
                        Text("\(winner.displayName) Wins!")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text(scoreLabel(for: winner))
                            .font(MADTheme.Typography.callout)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                    showCelebration = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                        podiumAnimated = true
                    }
                }
            }

            // Podium (top 3)
            if rankedUsers.count >= 2 {
                podiumView(rankedUsers: rankedUsers, currentUserId: currentUserId)
            }

            // Your result banner (if below top 3)
            if let placement = myPlacement, placement > 3 {
                yourResultBanner(placement: placement, totalParticipants: rankedUsers.count)
            }

            // Competition recap
            competitionRecap(rankedUsers: rankedUsers)

            // Full standings (everyone beyond podium)
            if rankedUsers.count > 3 {
                remainingStandings(rankedUsers: rankedUsers, currentUserId: currentUserId)
            }

            // Competition info
            infoSection
        }
    }

    // MARK: - Podium View
    private func podiumView(rankedUsers: [CompetitionUser], currentUserId: String?) -> some View {
        let first = rankedUsers[0]
        let second = rankedUsers.count > 1 ? rankedUsers[1] : nil
        let third = rankedUsers.count > 2 ? rankedUsers[2] : nil

        return HStack(alignment: .bottom, spacing: MADTheme.Spacing.sm) {
            // 2nd place
            if let user = second {
                podiumColumn(user: user, rank: 2, pedestalHeight: 80, isCurrentUser: user.user_id == currentUserId)
            }

            // 1st place
            podiumColumn(user: first, rank: 1, pedestalHeight: 120, isCurrentUser: first.user_id == currentUserId)

            // 3rd place
            if let user = third {
                podiumColumn(user: user, rank: 3, pedestalHeight: 50, isCurrentUser: user.user_id == currentUserId)
            }
        }
        .padding(.horizontal, MADTheme.Spacing.md)
    }

    private func podiumColumn(user: CompetitionUser, rank: Int, pedestalHeight: CGFloat, isCurrentUser: Bool) -> some View {
        let medalColors: [Color] = {
            switch rank {
            case 1: return [.yellow, .orange]
            case 2: return [Color(white: 0.85), Color(white: 0.6)]
            case 3: return [.brown, Color(red: 0.7, green: 0.4, blue: 0.2)]
            default: return [.gray, .gray]
            }
        }()

        return VStack(spacing: 0) {
            // Medal icon
            Image(systemName: "medal.fill")
                .font(.system(size: rank == 1 ? 28 : 22))
                .foregroundStyle(
                    LinearGradient(colors: medalColors, startPoint: .top, endPoint: .bottom)
                )
                .padding(.bottom, MADTheme.Spacing.xs)

            // Avatar
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: rank == 1 ? 56 : 44, height: rank == 1 ? 56 : 44)
                    .overlay(
                        Text(user.displayName.prefix(1).uppercased())
                            .font(.system(size: rank == 1 ? 22 : 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(colors: medalColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: rank == 1 ? 3 : 2
                            )
                    )

                if isCurrentUser {
                    Text("YOU")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                        .offset(y: (rank == 1 ? 56 : 44) / 2 + 6)
                }
            }
            .padding(.bottom, MADTheme.Spacing.sm)

            // Name
            Text(user.displayName)
                .font(.system(size: rank == 1 ? 14 : 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            // Score
            Text(scoreLabel(for: user))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .padding(.bottom, MADTheme.Spacing.sm)

            // Pedestal
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(
                    LinearGradient(
                        colors: [medalColors[0].opacity(0.3), medalColors[1].opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: podiumAnimated ? pedestalHeight : 0)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(
                            LinearGradient(colors: medalColors.map { $0.opacity(0.4) }, startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )
                )
                .overlay(
                    Text("\(rank)")
                        .font(.system(size: rank == 1 ? 32 : 24, weight: .bold, design: .rounded))
                        .foregroundColor(medalColors[0].opacity(0.3))
                )
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Your Result Banner
    private func yourResultBanner(placement: Int, totalParticipants: Int) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Text("\(placement)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Your Placement")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.white)
                Text("out of \(totalParticipants) competitors")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Image(systemName: "person.fill")
                .font(.title3)
                .foregroundColor(MADTheme.Colors.madRed)
        }
        .padding(MADTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(MADTheme.Colors.madRed.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Competition Recap
    private func competitionRecap(rankedUsers: [CompetitionUser]) -> some View {
        let totalDistance = rankedUsers.reduce(0.0) { $0 + ($1.score ?? 0) }
        let avgScore = rankedUsers.isEmpty ? 0 : totalDistance / Double(rankedUsers.count)

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Recap")
                .font(MADTheme.Typography.title3)
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.sm)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MADTheme.Spacing.md) {
                recapStatCard(
                    icon: "person.2.fill",
                    title: "Participants",
                    value: "\(rankedUsers.count)",
                    color: .blue
                )

                recapStatCard(
                    icon: competition.type.icon,
                    title: "Type",
                    value: competition.type.displayName,
                    color: Color(hex: competition.type.gradient[0])
                )

                recapStatCard(
                    icon: "chart.bar.fill",
                    title: competition.type == .streaks ? "Avg Streak" : "Avg Score",
                    value: competition.type == .streaks || competition.type == .clash || competition.type == .targets
                        ? String(format: "%.0f", avgScore)
                        : String(format: "%.1f %@", avgScore, competition.options.unit.shortDisplayName),
                    color: .green
                )

                if let startDate = competition.startDateFormatted, let endDate = competition.endDateFormatted {
                    let days = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
                    recapStatCard(
                        icon: "calendar",
                        title: "Duration",
                        value: "\(max(1, days)) day\(days == 1 ? "" : "s")",
                        color: .purple
                    )
                }
            }
        }
    }

    private func recapStatCard(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(title)
                .font(MADTheme.Typography.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Remaining Standings
    private func remainingStandings(rankedUsers: [CompetitionUser], currentUserId: String?) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Full Standings")
                .font(MADTheme.Typography.title3)
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(Array(rankedUsers.dropFirst(3).enumerated()), id: \.element.id) { index, user in
                    CompetitionLeaderboardRow(
                        rank: index + 4,
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
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Medal Helpers
    private func medalGradient(for placement: Int?) -> [Color] {
        switch placement {
        case 1: return [.yellow, .orange]
        case 2: return [Color(white: 0.85), Color(white: 0.6)]
        case 3: return [.brown, Color(red: 0.7, green: 0.4, blue: 0.2)]
        default: return [.white.opacity(0.7), .white.opacity(0.5)]
        }
    }

    // MARK: - Info Section (shared)
    private var infoSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            // Goal (not shown for Clash or Apex - they don't have distance targets)
            if competition.type != .clash && competition.type != .apex {
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

                    if competition.status == .lobby {
                        Button {
                            showingEditSettings = true
                        } label: {
                            Label("Edit Settings", systemImage: "slider.horizontal.3")
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

// MARK: - Edit Competition Settings View
struct EditCompetitionSettingsView: View {
    @Binding var competition: Competition
    @ObservedObject var competitionService: CompetitionService
    @Environment(\.dismiss) var dismiss

    // Editable fields initialized from competition
    @State private var name: String = ""
    @State private var goal: Double = 1.0
    @State private var unit: CompetitionUnit = .miles
    @State private var interval: CompetitionInterval = .day
    @State private var firstTo: Int = 5
    @State private var durationHours: Int? = nil
    @State private var selectedWorkouts: Set<CompetitionActivity> = [.run]

    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var needsGoal: Bool {
        competition.type != .clash && competition.type != .apex
    }

    private var needsInterval: Bool {
        competition.type == .apex || competition.type == .targets || competition.type == .clash
    }

    private var needsFirstTo: Bool {
        competition.type == .streaks || competition.type == .clash
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea(.all)

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.xl) {
                        // Competition Name
                        settingsGroup(title: "Competition Name") {
                            TextField("Competition name", text: $name)
                                .foregroundColor(.white)
                                .font(MADTheme.Typography.body)
                                .padding(MADTheme.Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                        .fill(Color.white.opacity(0.08))
                                )
                        }

                        // Goal (not for Clash)
                        if needsGoal {
                            settingsGroup(title: "Goal") {
                                HStack(spacing: MADTheme.Spacing.lg) {
                                    Button {
                                        if goal > 1 { goal -= 1 }
                                    } label: {
                                        Image(systemName: "minus")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                            .background(Circle().fill(Color.white.opacity(0.1)))
                                    }

                                    TextField("", value: $goal, format: .number)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.center)
                                        .font(.system(size: 36, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(minWidth: 80)

                                    Button {
                                        goal += 1
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                            .background(Circle().fill(Color.white.opacity(0.1)))
                                    }
                                }

                                // Unit selector
                                HStack(spacing: MADTheme.Spacing.sm) {
                                    ForEach([CompetitionUnit.miles, .kilometers, .steps], id: \.self) { u in
                                        Button {
                                            unit = u
                                        } label: {
                                            Text(u == .steps ? "Steps" : u.rawValue.capitalized)
                                                .font(MADTheme.Typography.callout)
                                                .fontWeight(unit == u ? .semibold : .regular)
                                                .foregroundColor(unit == u ? .white : .white.opacity(0.5))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, MADTheme.Spacing.sm)
                                                .background(
                                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                                        .fill(unit == u ? MADTheme.Colors.primary.opacity(0.3) : Color.white.opacity(0.05))
                                                )
                                        }
                                    }
                                }
                            }
                        } else {
                            // Unit only for Clash
                            settingsGroup(title: "Distance Unit") {
                                HStack(spacing: MADTheme.Spacing.sm) {
                                    ForEach([CompetitionUnit.miles, .kilometers, .steps], id: \.self) { u in
                                        Button {
                                            unit = u
                                        } label: {
                                            Text(u == .steps ? "Steps" : u.rawValue.capitalized)
                                                .font(MADTheme.Typography.callout)
                                                .fontWeight(unit == u ? .semibold : .regular)
                                                .foregroundColor(unit == u ? .white : .white.opacity(0.5))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, MADTheme.Spacing.sm)
                                                .background(
                                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                                        .fill(unit == u ? MADTheme.Colors.primary.opacity(0.3) : Color.white.opacity(0.05))
                                                )
                                        }
                                    }
                                }
                            }
                        }

                        // Interval
                        if needsInterval {
                            settingsGroup(title: "Scoring Interval") {
                                HStack(spacing: MADTheme.Spacing.sm) {
                                    ForEach(CompetitionInterval.allCases, id: \.self) { i in
                                        Button {
                                            interval = i
                                        } label: {
                                            Text(i.displayName)
                                                .font(MADTheme.Typography.callout)
                                                .fontWeight(interval == i ? .semibold : .regular)
                                                .foregroundColor(interval == i ? .white : .white.opacity(0.5))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, MADTheme.Spacing.sm)
                                                .background(
                                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                                        .fill(interval == i ? MADTheme.Colors.primary.opacity(0.3) : Color.white.opacity(0.05))
                                                )
                                        }
                                    }
                                }
                            }
                        }

                        // First To
                        if needsFirstTo {
                            settingsGroup(title: competition.type == .streaks ? "Breaks to Lose" : "Points to Win") {
                                HStack(spacing: MADTheme.Spacing.lg) {
                                    Button {
                                        if firstTo > 1 { firstTo -= 1 }
                                    } label: {
                                        Image(systemName: "minus")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                            .background(Circle().fill(Color.white.opacity(0.1)))
                                    }

                                    Text("\(firstTo)")
                                        .font(.system(size: 36, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(minWidth: 60)

                                    Button {
                                        firstTo += 1
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                            .background(Circle().fill(Color.white.opacity(0.1)))
                                    }
                                }
                            }
                        }

                        // Activities
                        settingsGroup(title: "Allowed Activities") {
                            HStack(spacing: MADTheme.Spacing.md) {
                                ForEach(CompetitionActivity.allCases, id: \.self) { activity in
                                    ActivityToggle(
                                        activity: activity,
                                        isSelected: selectedWorkouts.contains(activity),
                                        action: {
                                            if selectedWorkouts.contains(activity) {
                                                if selectedWorkouts.count > 1 {
                                                    selectedWorkouts.remove(activity)
                                                }
                                            } else {
                                                selectedWorkouts.insert(activity)
                                            }
                                        }
                                    )
                                }
                            }
                        }

                        Spacer(minLength: MADTheme.Spacing.xxl)
                    }
                    .padding(MADTheme.Spacing.lg)
                }
            }
            .navigationTitle("Edit Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        saveSettings()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                                .foregroundColor(MADTheme.Colors.madRed)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                // Initialize state from current competition
                name = competition.competition_name
                goal = competition.options.goal
                unit = competition.options.unit
                interval = competition.options.interval ?? .day
                firstTo = competition.options.first_to
                durationHours = competition.options.duration_hours
                selectedWorkouts = Set(competition.workouts)
            }
        }
    }

    private func settingsGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text(title)
                .font(MADTheme.Typography.subheadline)
                .foregroundColor(.white.opacity(0.6))

            content()
        }
        .padding(MADTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private func saveSettings() {
        isSaving = true
        Task {
            do {
                let updated = try await competitionService.updateCompetition(
                    id: competition.competition_id,
                    name: name,
                    workouts: Array(selectedWorkouts),
                    goal: goal,
                    unit: unit,
                    firstTo: firstTo,
                    history: false,
                    interval: interval
                )
                await MainActor.run {
                    competition = updated
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Competition Confetti View
struct CompetitionConfettiView: View {
    @State private var animate = false
    private let colors: [Color] = [.yellow, .orange, .red, .green, .blue, .purple, .white, .yellow, .orange]
    private let particleCount = 30

    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { i in
                confettiPiece(index: i)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 2.5)) {
                animate = true
            }
        }
    }

    private func confettiPiece(index: Int) -> some View {
        let angle = Double(index) * (360.0 / Double(particleCount)) + Double(index * 37 % 40) - 20
        let distance: CGFloat = 80 + CGFloat(index * 17 % 140)
        let rotationAmount = Double(index * 73 % 720)
        let pieceWidth: CGFloat = 4 + CGFloat(index * 3 % 5)
        let delay = Double(index) * 0.03

        return RoundedRectangle(cornerRadius: 1)
            .fill(colors[index % colors.count])
            .frame(width: pieceWidth, height: pieceWidth * 2.5)
            .rotationEffect(.degrees(animate ? rotationAmount : 0))
            .offset(
                x: animate ? cos(angle * .pi / 180) * distance : 0,
                y: animate ? sin(angle * .pi / 180) * distance + 40 : -30
            )
            .opacity(animate ? 0 : 1)
            .scaleEffect(animate ? 0.3 : 1)
            .animation(.easeOut(duration: 2.0).delay(delay), value: animate)
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
