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
    @State private var heartsAnimated = false
    @State private var raceAnimated = false

    // Flex/Nudge state
    @State private var showNudgeConfirm = false
    @State private var nudgeTargetUser: CompetitionUser?
    @State private var isSendingAction = false
    @State private var actionFeedback: ActionFeedback?

    // Settings dropdown
    @State private var showSettings = false

    // Leaderboard animation
    @State private var leaderboardAnimated = false

    // Hero count-up animation
    @State private var heroAnimated = false

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
            // Type icon (compact for active competitions since hero shows status)
            if competition.status != .active {
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
            }

            VStack(spacing: MADTheme.Spacing.sm) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    if competition.status == .active {
                        Image(systemName: competition.type.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: competition.type.gradient.map { Color(hex: $0) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

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

                if competition.status != .active {
                    Text(competition.type.description)
                        .font(MADTheme.Typography.callout)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MADTheme.Spacing.xl)
                }
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
            // 1. Compact hero status
            heroStatusSection

            // 2. Enhanced leaderboard (podium + rows with nudge)
            enhancedLeaderboard

            // 3. Flex action (if eligible)
            if canFlex {
                flexButton
            } else if FlexNudgeTracker.hasSentFlexToday(competitionId: competition.competition_id) {
                flexSentIndicator
            }

            // 4. Mode-specific content
            if competition.type != .race {
                intervalNavigator
                intervalContent
            } else {
                raceProgressView
            }

            // 5. Collapsible settings dropdown
            settingsDropdown
        }
        .confirmationDialog("Send a nudge?", isPresented: $showNudgeConfirm, titleVisibility: .visible) {
            Button("Send Nudge") {
                if let user = nudgeTargetUser { sendNudge(to: user) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let user = nudgeTargetUser {
                Text("Send \(user.displayName) a reminder to lace up and run. Once per person per day.")
            }
        }
        .overlay(alignment: .top) {
            if let feedback = actionFeedback {
                feedbackBanner(feedback)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
    }

    // MARK: - Hero Status Section
    private var heroStatusSection: some View {
        let currentUser = competition.users.first(where: { $0.user_id == UserDefaults.standard.string(forKey: "backendUserId") })
        let todayKey = intervalKey(for: Date())
        let todayDistance = currentUser?.intervals?[todayKey] ?? 0
        let goal = competition.options.goal
        let gradientColors = competition.type.gradient.map { Color(hex: $0) }

        return VStack(spacing: MADTheme.Spacing.md) {
            // Type-specific hero content
            switch competition.type {
            case .streaks:
                streakHeroContent(user: currentUser, todayDistance: todayDistance, goal: goal, gradientColors: gradientColors)
            case .clash:
                clashHeroContent(user: currentUser, todayDistance: todayDistance, todayKey: todayKey, gradientColors: gradientColors)
            case .apex:
                apexHeroContent(user: currentUser, todayDistance: todayDistance, todayKey: todayKey, gradientColors: gradientColors)
            case .targets:
                targetsHeroContent(user: currentUser, todayDistance: todayDistance, goal: goal, gradientColors: gradientColors)
            case .race:
                raceHeroContent(user: currentUser, goal: goal, gradientColors: gradientColors)
            }

            // Compact tracked activities + time remaining
            HStack(spacing: MADTheme.Spacing.sm) {
                ForEach(competition.workouts, id: \.self) { activity in
                    HStack(spacing: 4) {
                        Image(systemName: activity.icon)
                            .font(.system(size: 10))
                        Text(activity.displayName)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }

                Spacer()

                if let endDate = competition.endDateFormatted {
                    let remaining = endDate.timeIntervalSince(Date())
                    let days = Int(remaining / 86400)
                    let hours = Int(remaining.truncatingRemainder(dividingBy: 86400) / 3600)
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                        Text(days > 0 ? "\(days)d \(hours)h" : "\(hours)h left")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.green.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.1)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(
                            LinearGradient(
                                colors: gradientColors.map { $0.opacity(0.3) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            heroAnimated = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.8)) {
                    heroAnimated = true
                }
            }
        }
    }

    // MARK: - Hero Content Per Type

    private func streakHeroContent(user: CompetitionUser?, todayDistance: Double, goal: Double, gradientColors: [Color]) -> some View {
        let streak = Int(user?.score ?? 0)
        let completed = todayDistance >= goal
        let remaining = max(0, goal - todayDistance)
        let firstTo = competition.options.first_to

        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.orange)
                    .shadow(color: .orange.opacity(0.4), radius: 6)

                CountingText(value: heroAnimated ? Double(streak) : 0, format: "%.0f", suffix: "")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("day streak")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 14)
            }

            if completed {
                Label("Done \u{2014} \(String(format: "%.1f", todayDistance)) \(competition.options.unit.shortDisplayName)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
            } else {
                Label("\(String(format: "%.1f", remaining)) \(competition.options.unit.shortDisplayName) to go", systemImage: "figure.run")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }

            if firstTo > 0, let user = user {
                let lives = user.remaining_lives ?? firstTo
                HStack(spacing: 4) {
                    ForEach(0..<min(firstTo, 6), id: \.self) { i in
                        Image(systemName: i < lives ? "heart.fill" : "heart")
                            .font(.system(size: 12))
                            .foregroundColor(i < lives ? .red : .white.opacity(0.15))
                    }
                    if firstTo > 6 {
                        Text("+\(firstTo - 6)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }
        }
    }

    private func clashHeroContent(user: CompetitionUser?, todayDistance: Double, todayKey: String, gradientColors: [Color]) -> some View {
        let acceptedUsers = competition.users.filter { $0.invite_status == .accepted }
        let myDistance = todayDistance
        let bestOpponentDistance = acceptedUsers.filter { $0.user_id != user?.user_id }.map { $0.intervals?[todayKey] ?? 0 }.max() ?? 0
        let isLeading = myDistance > 0 && myDistance >= bestOpponentDistance
        let points = Int(user?.score ?? 0)

        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom))

                CountingText(value: heroAnimated ? Double(points) : 0, format: "%.0f", suffix: "")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(points == 1 ? "win" : "wins")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 14)
            }

            if myDistance > 0 {
                let diff = myDistance - bestOpponentDistance
                if isLeading && diff > 0 {
                    Label("Leading by \(String(format: "%.1f", diff)) \(competition.options.unit.shortDisplayName)", systemImage: "crown.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                } else if diff < 0 {
                    Label("Behind by \(String(format: "%.1f", abs(diff))) \(competition.options.unit.shortDisplayName)", systemImage: "arrow.up")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.orange.opacity(0.12)))
                } else {
                    Label("Tied at \(String(format: "%.1f", myDistance)) \(competition.options.unit.shortDisplayName)", systemImage: "equal")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            } else {
                Label("No activity yet today", systemImage: "figure.run")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }
        }
    }

    private func apexHeroContent(user: CompetitionUser?, todayDistance: Double, todayKey: String, gradientColors: [Color]) -> some View {
        let totalScore = user?.score ?? 0
        let acceptedUsers = competition.users.filter { $0.invite_status == .accepted }
        let myRank = acceptedUsers.sorted { ($0.score ?? 0) > ($1.score ?? 0) }.firstIndex(where: { $0.user_id == user?.user_id }).map { $0 + 1 } ?? 0

        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom))

                CountingText(value: heroAnimated ? totalScore : 0, format: "%.1f", suffix: "")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(competition.options.unit.shortDisplayName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 14)
            }

            HStack(spacing: MADTheme.Spacing.sm) {
                if myRank > 0 {
                    Label(rankOrdinal(myRank) + " of \(acceptedUsers.count)", systemImage: "trophy")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(myRank == 1 ? .yellow : .white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(myRank == 1 ? Color.yellow.opacity(0.12) : Color.white.opacity(0.06)))
                }

                if todayDistance > 0 {
                    Label("+\(String(format: "%.1f", todayDistance)) today", systemImage: "figure.run")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.green.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.green.opacity(0.1)))
                }
            }
        }
    }

    private func targetsHeroContent(user: CompetitionUser?, todayDistance: Double, goal: Double, gradientColors: [Color]) -> some View {
        let points = Int(user?.score ?? 0)
        let completed = todayDistance >= goal
        let progress = min(todayDistance / max(goal, 0.1), 1.0)

        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 28))
                    .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom))

                CountingText(value: heroAnimated ? Double(points) : 0, format: "%.0f", suffix: "")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(points == 1 ? "point" : "points")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 14)
            }

            // Today's progress bar
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(completed
                                ? LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * (heroAnimated ? progress : 0), height: 8)
                            .animation(.easeOut(duration: 0.8).delay(0.3), value: heroAnimated)
                    }
                }
                .frame(height: 8)

                HStack {
                    if completed {
                        Label("Target hit!", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.green)
                    } else {
                        Text("\(String(format: "%.1f", todayDistance))/\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)
        }
    }

    private func raceHeroContent(user: CompetitionUser?, goal: Double, gradientColors: [Color]) -> some View {
        let totalDistance = user?.score ?? 0
        let progress = min(totalDistance / max(goal, 0.1), 1.0)
        let percent = Int(progress * 100)
        let acceptedUsers = competition.users.filter { $0.invite_status == .accepted }
        let myRank = acceptedUsers.sorted { ($0.score ?? 0) > ($1.score ?? 0) }.firstIndex(where: { $0.user_id == user?.user_id }).map { $0 + 1 } ?? 0

        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom))

                CountingText(value: heroAnimated ? Double(percent) : 0, format: "%.0f", suffix: "%")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("complete")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 14)
            }

            // Progress bar
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * (heroAnimated ? progress : 0), height: 8)
                            .animation(.easeOut(duration: 0.8).delay(0.3), value: heroAnimated)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("\(String(format: "%.1f", totalDistance))/\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    if myRank > 0 {
                        Text(rankOrdinal(myRank) + " place")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(myRank == 1 ? .yellow : .white.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)
        }
    }

    private func rankOrdinal(_ rank: Int) -> String {
        switch rank {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(rank)th"
        }
    }

    // MARK: - Enhanced Leaderboard
    private var enhancedLeaderboard: some View {
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        let rankedUsers = competition.users
            .filter { $0.invite_status == .accepted }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        let gradientColors = competition.type.gradient.map { Color(hex: $0) }
        let todayKey = intervalKey(for: Date())

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            // Section header
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                    )
                Text("Leaderboard")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.white)

                Spacer()

                Text("\(rankedUsers.count) competing")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            if rankedUsers.isEmpty {
                Text("No participants yet")
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(MADTheme.Spacing.lg)
            } else {
                VStack(spacing: MADTheme.Spacing.md) {
                    // Podium for top 3
                    if rankedUsers.count >= 2 {
                        enhancedPodium(rankedUsers: Array(rankedUsers.prefix(3)), gradientColors: gradientColors, currentUserId: currentUserId)
                    }

                    // Ranked rows with nudge
                    VStack(spacing: MADTheme.Spacing.sm) {
                        ForEach(Array(rankedUsers.enumerated()), id: \.element.id) { index, user in
                            let isMe = user.user_id == currentUserId
                            let showNudge = !isMe && shouldShowNudge(for: user, todayKey: todayKey)
                            let nudgeDisabled = FlexNudgeTracker.hasSentNudgeToday(competitionId: competition.competition_id, targetUserId: user.user_id)

                            CompetitionLeaderboardRow(
                                rank: index + 1,
                                user: user,
                                competitionType: competition.type,
                                unit: competition.options.unit,
                                isCurrentUser: isMe,
                                firstTo: competition.options.first_to,
                                showNudge: showNudge,
                                nudgeDisabled: nudgeDisabled,
                                onNudge: {
                                    nudgeTargetUser = user
                                    showNudgeConfirm = true
                                }
                            )
                            .opacity(leaderboardAnimated ? 1 : 0)
                            .offset(y: leaderboardAnimated ? 0 : 15)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.8)
                                    .delay(0.15 + Double(index) * 0.06),
                                value: leaderboardAnimated
                            )
                        }
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
                                        colors: gradientColors.map { $0.opacity(0.3) } + [Color.clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
            }
        }
        .onAppear {
            leaderboardAnimated = false
            podiumAnimated = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    leaderboardAnimated = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) {
                    podiumAnimated = true
                }
            }
        }
    }

    // MARK: - Enhanced Podium
    private func enhancedPodium(rankedUsers: [CompetitionUser], gradientColors: [Color], currentUserId: String?) -> some View {
        let medalColors: [[Color]] = [
            [.yellow, .orange],
            [Color(white: 0.85), Color(white: 0.6)],
            [.brown, Color(red: 0.7, green: 0.4, blue: 0.2)]
        ]

        return HStack(alignment: .bottom, spacing: MADTheme.Spacing.md) {
            // 2nd place
            if rankedUsers.count > 1 {
                enhancedPodiumSlot(user: rankedUsers[1], rank: 2, colors: medalColors[1], height: 44, avatarSize: 36, isCurrentUser: rankedUsers[1].user_id == currentUserId)
            }

            // 1st place with glow
            ZStack {
                // Radial glow behind 1st place
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [medalColors[0][0].opacity(0.25), Color.clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)
                    .offset(y: -20)
                    .opacity(podiumAnimated ? 1 : 0)
                    .scaleEffect(podiumAnimated ? 1.0 : 0.5)

                enhancedPodiumSlot(user: rankedUsers[0], rank: 1, colors: medalColors[0], height: 56, avatarSize: 44, isCurrentUser: rankedUsers[0].user_id == currentUserId)
            }

            // 3rd place
            if rankedUsers.count > 2 {
                enhancedPodiumSlot(user: rankedUsers[2], rank: 3, colors: medalColors[2], height: 36, avatarSize: 36, isCurrentUser: rankedUsers[2].user_id == currentUserId)
            }
        }
        .padding(.vertical, MADTheme.Spacing.sm)
    }

    private func enhancedPodiumSlot(user: CompetitionUser, rank: Int, colors: [Color], height: CGFloat, avatarSize: CGFloat, isCurrentUser: Bool) -> some View {
        VStack(spacing: 3) {
            // Crown for 1st
            if rank == 1 {
                Image(systemName: "crown.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: .yellow.opacity(0.4), radius: 4)
            }

            // Medal icon
            Image(systemName: "medal.fill")
                .font(.system(size: rank == 1 ? 16 : 13))
                .foregroundStyle(
                    LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                )

            // Avatar with YOU badge below (fixed height container)
            VStack(spacing: 2) {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay(
                        Text(user.displayName.prefix(1).uppercased())
                            .font(.system(size: avatarSize * 0.38, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: rank == 1 ? 2.5 : 2
                            )
                    )

                if isCurrentUser {
                    Text("YOU")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                } else {
                    // Invisible spacer to keep layout consistent
                    Color.clear.frame(height: 12)
                }
            }

            Text(user.displayName)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: avatarSize + 20)

            Text(leaderboardScoreLabel(for: user))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))

            // Pedestal
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: colors.map { $0.opacity(0.2) },
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: podiumAnimated ? height : 0)
                .overlay(
                    Text("\(rank)")
                        .font(.system(size: height * 0.45, weight: .bold, design: .rounded))
                        .foregroundColor(colors[0].opacity(0.25))
                )
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Nudge Eligibility
    private func shouldShowNudge(for user: CompetitionUser, todayKey: String) -> Bool {
        let distance = user.intervals?[todayKey] ?? 0
        let goal = competition.options.goal

        switch competition.type {
        case .streaks, .targets:
            return distance < goal
        case .clash:
            return true // Can always nudge opponents in clash
        case .apex:
            return distance == 0 // Nudge if they haven't run today
        case .race:
            return distance == 0 // Nudge if they haven't run today
        }
    }

    // MARK: - Flex Eligibility
    private var canFlex: Bool {
        guard !FlexNudgeTracker.hasSentFlexToday(competitionId: competition.competition_id) else {
            return false
        }

        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        guard let currentUser = competition.users.first(where: { $0.user_id == currentUserId }) else {
            return false
        }

        let todayKey = intervalKey(for: Date())
        let distance = currentUser.intervals?[todayKey] ?? 0
        let goal = competition.options.goal

        switch competition.type {
        case .streaks:
            return distance >= goal
        case .targets:
            return distance >= goal
        case .clash:
            let acceptedUsers = competition.users.filter { $0.invite_status == .accepted }
            let bestOpponent = acceptedUsers
                .filter { $0.user_id != currentUser.user_id }
                .map { $0.intervals?[todayKey] ?? 0 }
                .max() ?? 0
            return distance > 0 && distance >= bestOpponent
        case .apex:
            return distance > 0
        case .race:
            return distance > 0
        }
    }

    // MARK: - Flex Button
    private var flexButton: some View {
        let typeColor = Color(hex: competition.type.gradient[0])
        let subtitle: String = {
            switch competition.type {
            case .streaks: return "Let them know you finished"
            case .clash: return "Show off your lead"
            case .apex: return "They'll know you put in work"
            case .targets: return "You hit your target"
            case .race: return "You're making progress"
            }
        }()

        return Button { sendFlex() } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 18))
                    .foregroundColor(typeColor)
                    .shadow(color: typeColor.opacity(0.4), radius: 4)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Flex on everyone")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer()

                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .stroke(typeColor.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Flex Sent Indicator
    private var flexSentIndicator: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 14))
                .foregroundColor(.green.opacity(0.6))

            Text("Flex sent today")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.35))

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.green.opacity(0.4))
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.03))
        )
    }

    // MARK: - Flex/Nudge Actions
    private func sendFlex() {
        isSendingAction = true
        Task {
            do {
                try await competitionService.sendFlex(competitionId: competition.competition_id)
                await MainActor.run {
                    isSendingAction = false
                    FlexNudgeTracker.markFlexSent(competitionId: competition.competition_id)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showActionFeedback(ActionFeedback(icon: "hand.raised.fill", message: "Flex sent!", isError: false))
                }
            } catch {
                await MainActor.run {
                    isSendingAction = false
                    let msg = (error as? CompetitionServiceError)?.errorDescription ?? "Could not send flex"
                    showActionFeedback(ActionFeedback(icon: "xmark.circle", message: msg, isError: true))
                }
            }
        }
    }

    private func sendNudge(to user: CompetitionUser) {
        isSendingAction = true
        Task {
            do {
                try await competitionService.sendNudge(competitionId: competition.competition_id, targetUserId: user.user_id)
                await MainActor.run {
                    isSendingAction = false
                    FlexNudgeTracker.markNudgeSent(competitionId: competition.competition_id, targetUserId: user.user_id)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showActionFeedback(ActionFeedback(icon: "bell.badge.fill", message: "Nudge sent to \(user.displayName)!", isError: false))
                }
            } catch {
                await MainActor.run {
                    isSendingAction = false
                    let msg = (error as? CompetitionServiceError)?.errorDescription ?? "Could not send nudge"
                    showActionFeedback(ActionFeedback(icon: "xmark.circle", message: msg, isError: true))
                }
            }
        }
    }

    private func showActionFeedback(_ feedback: ActionFeedback) {
        withAnimation(.easeInOut(duration: 0.2)) { actionFeedback = feedback }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.2)) { actionFeedback = nil }
        }
    }

    private func feedbackBanner(_ feedback: ActionFeedback) -> some View {
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
        .padding(.top, 8)
    }

    // MARK: - Collapsible Settings Dropdown
    private var settingsDropdown: some View {
        VStack(spacing: 0) {
            // Tappable header
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
                Text("Competition Details")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Image(systemName: showSettings ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(MADTheme.Spacing.md)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSettings.toggle()
                }
            }

            if showSettings {
                infoSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.top, -MADTheme.Spacing.sm)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
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

    // MARK: - Streaks Interval View
    private func streaksIntervalView(key: String, users: [CompetitionUser], currentUserId: String?) -> some View {
        let goal = competition.options.goal
        let firstTo = competition.options.first_to

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            // Section header
            HStack {
                Text("Streak Status")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.white)

                Spacer()

                if firstTo > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .shadow(color: .red.opacity(0.5), radius: 2)
                        Text("\(firstTo) \(firstTo == 1 ? "life" : "lives") each")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    )
                }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(users, id: \.id) { user in
                    let distance = user.intervals?[key] ?? 0
                    let completed = distance >= goal
                    let isToday = Calendar.current.isDateInToday(selectedIntervalDate)
                    let missed = missedDates(for: user)

                    // Use server-provided remaining_lives when available, fall back to local calculation
                    let heartsRemaining: Int = {
                        if let serverLives = user.remaining_lives {
                            return max(0, serverLives)
                        } else if firstTo > 0 {
                            return max(0, firstTo - min(missed.count, firstTo))
                        }
                        return 0
                    }()
                    let livesLost: Int = {
                        if firstTo > 0 {
                            if let serverLives = user.remaining_lives {
                                return max(0, firstTo - serverLives)
                            }
                            return min(missed.count, firstTo)
                        }
                        return 0
                    }()
                    let isEliminated: Bool = {
                        if firstTo > 0 {
                            if let serverLives = user.remaining_lives {
                                return serverLives <= 0
                            }
                            return missed.count >= firstTo
                        }
                        return false
                    }()

                    VStack(spacing: MADTheme.Spacing.sm) {
                        // Main user info row
                        HStack(spacing: MADTheme.Spacing.md) {
                            // Avatar with status ring
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(isEliminated ? 0.05 : 0.12))
                                    .frame(width: 42, height: 42)
                                    .overlay(
                                        Text(user.displayName.prefix(1).uppercased())
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white.opacity(isEliminated ? 0.3 : 1.0))
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    colors: isEliminated ? [Color.red.opacity(0.3), Color.red.opacity(0.1)] :
                                                        (completed ? [Color.green.opacity(0.8), Color.green.opacity(0.4)] :
                                                        (isToday ? [Color.orange.opacity(0.6), Color.yellow.opacity(0.3)] :
                                                        [Color.red.opacity(0.6), Color.red.opacity(0.3)])),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 2.5
                                            )
                                    )

                                // Small status badge
                                if !isEliminated {
                                    ZStack {
                                        Circle()
                                            .fill(completed ? Color.green : (isToday ? Color.orange : Color.red))
                                            .frame(width: 16, height: 16)
                                        Image(systemName: completed ? "checkmark" : (isToday ? "figure.run" : "xmark"))
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    .offset(x: 15, y: 15)
                                }
                            }

                            // Name + status text
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: MADTheme.Spacing.xs) {
                                    Text(user.displayName)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white.opacity(isEliminated ? 0.4 : 1.0))

                                    if isEliminated {
                                        Text("OUT")
                                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                                            .foregroundColor(.white.opacity(0.8))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule()
                                                    .fill(Color.red.opacity(0.5))
                                            )
                                    }
                                }

                                if !isEliminated {
                                    if completed {
                                        HStack(spacing: 4) {
                                            Text("\(String(format: "%.1f", distance)) \(competition.options.unit.shortDisplayName)")
                                                .foregroundColor(.green)
                                            if distance > goal {
                                                Text("+\(String(format: "%.1f", distance - goal))")
                                                    .foregroundColor(.green.opacity(0.5))
                                            }
                                        }
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                    } else if isToday {
                                        HStack(spacing: 4) {
                                            Text("\(String(format: "%.1f", distance))/\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                                .foregroundColor(.white.opacity(0.6))
                                        }
                                    } else {
                                        Text("Missed")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(.red.opacity(0.6))
                                    }
                                } else {
                                    if !missed.isEmpty {
                                        Text("Eliminated \(formatBreakDate(missed.last!))")
                                            .font(.system(size: 11, design: .rounded))
                                            .foregroundColor(.white.opacity(0.25))
                                    }
                                }
                            }

                            Spacer()

                            // Streak counter - more prominent
                            VStack(spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 15))
                                        .foregroundColor(isEliminated ? .gray.opacity(0.3) : .orange)
                                        .shadow(color: isEliminated ? .clear : .orange.opacity(0.4), radius: 4)
                                    Text("\(Int(user.score ?? 0))")
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                        .foregroundColor(.white.opacity(isEliminated ? 0.3 : 1.0))
                                }
                                Text("day streak")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(isEliminated ? 0.2 : 0.35))
                            }
                        }

                        // Lives row - clean capsule style
                        if firstTo > 0 {
                            HStack(spacing: 5) {
                                ForEach(0..<firstTo, id: \.self) { i in
                                    let isAlive = i < heartsRemaining

                                    Image(systemName: isAlive ? "heart.fill" : "heart")
                                        .font(.system(size: 14))
                                        .foregroundColor(isAlive ? .red : .white.opacity(0.15))
                                        .shadow(color: isAlive ? .red.opacity(0.3) : .clear, radius: 3)
                                        .scaleEffect(heartsAnimated ? 1.0 : 0.1)
                                        .opacity(heartsAnimated ? 1.0 : 0)
                                        .animation(
                                            .spring(response: 0.35, dampingFraction: isAlive ? 0.55 : 0.3)
                                            .delay(Double(i) * 0.07),
                                            value: heartsAnimated
                                        )
                                }

                                Spacer()

                                if isEliminated {
                                    Text("No lives remaining")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(.red.opacity(0.4))
                                } else if livesLost > 0 {
                                    Text("\(heartsRemaining) remaining")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(.white.opacity(0.3))
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .fill(Color.white.opacity(
                                isEliminated ? 0.02 : (user.user_id == currentUserId ? 0.08 : 0.03)
                            ))
                            .overlay(
                                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                    .stroke(
                                        isEliminated
                                            ? LinearGradient(
                                                colors: [Color.red.opacity(0.15), Color.red.opacity(0.05)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                              )
                                            : (user.user_id == currentUserId
                                                ? LinearGradient(colors: [MADTheme.Colors.primary.opacity(0.6), MADTheme.Colors.primary.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                                : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing)),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .opacity(isEliminated ? 0.55 : 1.0)
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
        .onAppear {
            heartsAnimated = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    heartsAnimated = true
                }
            }
        }
    }

    /// Formats an ISO8601 date key (e.g. "2026-02-20") into a readable label (e.g. "Feb 20")
    private func formatBreakDate(_ isoKey: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]
        isoFormatter.timeZone = TimeZone(identifier: "UTC")!
        guard let date = isoFormatter.date(from: isoKey) else { return isoKey }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM d"
        displayFormatter.timeZone = TimeZone(identifier: "UTC")!
        return displayFormatter.string(from: date)
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

                            VStack(alignment: .trailing, spacing: 1) {
                                Text(String(format: "%.1f/%@ %@", distance, competition.options.goalFormatted, competition.options.unit.shortDisplayName))
                                    .font(MADTheme.Typography.callout)
                                    .foregroundColor(hitTarget ? .green : .white.opacity(0.7))
                                if hitTarget && distance > goal {
                                    Text("+\(String(format: "%.1f", distance - goal)) over")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(.green.opacity(0.7))
                                }
                            }
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

    // MARK: - Race Progress View
    private var raceProgressView: some View {
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        let goal = competition.options.goal
        let sortedUsers = competition.users
            .filter { $0.invite_status == .accepted }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        let gradientColors = competition.type.gradient.map { Color(hex: $0) }

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack {
                Text("Race Progress")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.white)

                Spacer()

                // Finish line indicator
                HStack(spacing: 4) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: MADTheme.Spacing.md) {
                ForEach(Array(sortedUsers.enumerated()), id: \.element.id) { index, user in
                    let distance = user.score ?? 0
                    let progress = min(distance / max(goal, 0.1), 1.0)
                    let isCurrentUser = user.user_id == currentUserId
                    let finished = distance >= goal

                    VStack(spacing: MADTheme.Spacing.sm) {
                        // User info row
                        HStack(spacing: MADTheme.Spacing.sm) {
                            // Position badge
                            ZStack {
                                Circle()
                                    .fill(
                                        index == 0
                                            ? LinearGradient(colors: gradientColors.map { $0.opacity(0.3) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                                            : LinearGradient(colors: [Color.white.opacity(0.12)], startPoint: .top, endPoint: .bottom)
                                    )
                                    .frame(width: 32, height: 32)

                                Text("\(index + 1)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(index == 0 ? gradientColors.first ?? .white : .white.opacity(0.6))
                            }

                            Text(user.displayName)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)

                            Spacer()

                            VStack(alignment: .trailing, spacing: 1) {
                                Text(String(format: "%.1f/%@ %@", distance, competition.options.goalFormatted, competition.options.unit.shortDisplayName))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(finished ? .green : .white.opacity(0.7))
                                if distance > goal {
                                    Text("+\(String(format: "%.1f", distance - goal)) over")
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundColor(.green.opacity(0.7))
                                }
                            }
                        }

                        // Animated Race Track
                        GeometryReader { geo in
                            let trackWidth = geo.size.width
                            let runnerX = raceAnimated ? trackWidth * progress : 0

                            ZStack(alignment: .leading) {
                                // Track background
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 6)
                                    .offset(y: 8)

                                // Track distance markers
                                ForEach(1..<4, id: \.self) { i in
                                    Rectangle()
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: 1, height: 10)
                                        .offset(x: trackWidth * CGFloat(i) / 4, y: 6)
                                }

                                // Progress trail with gradient
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: gradientColors,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(runnerX, 0), height: 6)
                                    .offset(y: 8)

                                // Finish flag at the end of track
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: gradientColors.map { $0.opacity(0.5) },
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .offset(x: trackWidth - 10, y: -2)

                                // Running man that animates to position
                                Image(systemName: finished ? "figure.run.circle.fill" : "figure.run")
                                    .font(.system(size: finished ? 20 : 16, weight: .medium))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: finished ? [.green, gradientColors.last ?? .green] : gradientColors,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: (gradientColors.first ?? .purple).opacity(raceAnimated ? 0.5 : 0), radius: 6)
                                    .offset(x: max(runnerX - 8, 0), y: -4)
                            }
                            .animation(
                                .easeOut(duration: 1.0).delay(0.3 + Double(index) * 0.15),
                                value: raceAnimated
                            )
                        }
                        .frame(height: 28)
                    }
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.vertical, MADTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .fill(Color.white.opacity(isCurrentUser ? 0.08 : 0))
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
        .onAppear {
            raceAnimated = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut(duration: 0.8)) {
                    raceAnimated = true
                }
            }
        }
    }

    // MARK: - Streak Helpers

    /// Returns the ISO8601 date keys for days where the user failed to meet the goal.
    /// Only counts completed past days — the current day is never included.
    private func missedDates(for user: CompetitionUser) -> [String] {
        guard let startDateStr = competition.start_date else { return [] }
        let intervals = user.intervals ?? [:]
        let goal = competition.options.goal

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")!

        guard let startDate = formatter.date(from: startDateStr) else { return [] }

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        let todayUTC = utcCalendar.startOfDay(for: Date())
        var currentDate = utcCalendar.startOfDay(for: startDate)
        var missed: [String] = []

        // Only check completed past days — stop before today
        while currentDate < todayUTC {
            let key = formatter.string(from: currentDate)
            let distance = intervals[key] ?? 0
            if distance < goal {
                missed.append(key)
            }
            guard let nextDate = utcCalendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        return missed
    }

    private func missCount(for user: CompetitionUser) -> Int {
        return missedDates(for: user).count
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

    private func leaderboardScoreLabel(for user: CompetitionUser) -> String {
        let score = user.score ?? 0
        switch competition.type {
        case .streaks:
            return "\(Int(score))d"
        case .apex, .race:
            return String(format: "%.1f %@", score, competition.options.unit.shortDisplayName)
        case .targets, .clash:
            return "\(Int(score)) pts"
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
                showCelebration = false
                podiumAnimated = false
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
                        isCurrentUser: user.user_id == currentUserId,
                        firstTo: competition.options.first_to
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
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
        }

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

// MARK: - Flex/Nudge Tracker
struct FlexNudgeTracker {
    private static let flexPrefix = "flex_sent_"
    private static let nudgePrefix = "nudge_sent_"

    static func hasSentFlexToday(competitionId: String) -> Bool {
        UserDefaults.standard.bool(forKey: flexPrefix + competitionId + "_" + todayKey())
    }

    static func markFlexSent(competitionId: String) {
        UserDefaults.standard.set(true, forKey: flexPrefix + competitionId + "_" + todayKey())
    }

    static func hasSentNudgeToday(competitionId: String, targetUserId: String) -> Bool {
        UserDefaults.standard.bool(forKey: nudgePrefix + competitionId + "_" + targetUserId + "_" + todayKey())
    }

    static func markNudgeSent(competitionId: String, targetUserId: String) {
        UserDefaults.standard.set(true, forKey: nudgePrefix + competitionId + "_" + targetUserId + "_" + todayKey())
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Action Feedback
struct ActionFeedback: Equatable {
    let icon: String
    let message: String
    let isError: Bool
}

// MARK: - Counting Text (Animatable number display)
struct CountingText: View, Animatable {
    var value: Double
    let format: String
    let suffix: String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(String(format: format, value) + suffix)
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
