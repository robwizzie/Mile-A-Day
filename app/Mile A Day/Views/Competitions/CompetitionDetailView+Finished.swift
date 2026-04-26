import SwiftUI
import HealthKit

// MARK: - Finished Content

extension CompetitionDetailView {

    // MARK: - Finished Content
    var finishedContent: some View {
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

            // Full standings — all participants
            fullStandings(rankedUsers: rankedUsers, currentUserId: currentUserId)

            // Competition settings
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                Text("Settings")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.white)
                    .padding(.horizontal, MADTheme.Spacing.sm)

                infoSection
            }
        }
    }

    // MARK: - Podium View
    func podiumView(rankedUsers: [CompetitionUser], currentUserId: String?) -> some View {
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

    func podiumColumn(user: CompetitionUser, rank: Int, pedestalHeight: CGFloat, isCurrentUser: Bool) -> some View {
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
                AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: rank == 1 ? 56 : 44)
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
    func yourResultBanner(placement: Int, totalParticipants: Int) -> some View {
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
    func competitionRecap(rankedUsers: [CompetitionUser]) -> some View {
        let unit = competition.options.unit.shortDisplayName

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Recap")
                .font(MADTheme.Typography.title3)
                .foregroundColor(.white)
                .padding(.horizontal, MADTheme.Spacing.sm)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MADTheme.Spacing.md) {
                // Shared: participants & duration
                recapStatCard(
                    icon: "person.2.fill",
                    title: "Participants",
                    value: "\(rankedUsers.count)",
                    color: .blue
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

                // Type-specific stats
                switch competition.type {
                case .race, .apex:
                    let winnerScore = rankedUsers.first?.score ?? 0
                    let totalDistance = rankedUsers.reduce(0.0) { $0 + ($1.score ?? 0) }
                    let avgDistance = rankedUsers.isEmpty ? 0 : totalDistance / Double(rankedUsers.count)

                    recapStatCard(
                        icon: "trophy.fill",
                        title: competition.type == .race ? "Winner's Distance" : "Top Distance",
                        value: String(format: "%.1f %@", winnerScore, unit),
                        color: .yellow
                    )

                    recapStatCard(
                        icon: "chart.bar.fill",
                        title: "Avg Distance",
                        value: String(format: "%.1f %@", avgDistance, unit),
                        color: .green
                    )

                case .streaks:
                    let winnerStreak = Int(rankedUsers.first?.score ?? 0)
                    let avgStreak = rankedUsers.isEmpty ? 0 : rankedUsers.reduce(0.0) { $0 + ($1.score ?? 0) } / Double(rankedUsers.count)

                    recapStatCard(
                        icon: "flame.fill",
                        title: "Best Streak",
                        value: "\(winnerStreak) day\(winnerStreak == 1 ? "" : "s")",
                        color: .orange
                    )

                    recapStatCard(
                        icon: "chart.bar.fill",
                        title: "Avg Streak",
                        value: String(format: "%.0f day%@", avgStreak, avgStreak == 1 ? "" : "s"),
                        color: .green
                    )

                case .clash:
                    let winnerWins = Int(rankedUsers.first?.score ?? 0)
                    let totalRounds = rankedUsers.first?.intervals?.count ?? 0

                    recapStatCard(
                        icon: "bolt.fill",
                        title: "Winner's Wins",
                        value: "\(winnerWins)",
                        color: .yellow
                    )

                    recapStatCard(
                        icon: "number",
                        title: "Total Rounds",
                        value: "\(totalRounds)",
                        color: .cyan
                    )

                case .targets:
                    let winnerPoints = Int(rankedUsers.first?.score ?? 0)
                    let totalIntervals = rankedUsers.first?.intervals?.count ?? 0
                    let hitRate = totalIntervals > 0 ? Double(winnerPoints) / Double(totalIntervals) * 100 : 0

                    recapStatCard(
                        icon: "target",
                        title: "Winner's Points",
                        value: "\(winnerPoints)",
                        color: .yellow
                    )

                    recapStatCard(
                        icon: "percent",
                        title: "Goal Hit Rate",
                        value: String(format: "%.0f%%", hitRate),
                        color: .green
                    )
                }
            }
        }
    }

    func recapStatCard(icon: String, title: String, value: String, color: Color) -> some View {
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

    // MARK: - Full Standings
    func fullStandings(rankedUsers: [CompetitionUser], currentUserId: String?) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Standings")
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
                        totalLives: competition.type == .streaks ? competition.streakLives : 0
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
    func medalGradient(for placement: Int?) -> [Color] {
        switch placement {
        case 1: return [.yellow, .orange]
        case 2: return [Color(white: 0.85), Color(white: 0.6)]
        case 3: return [.brown, Color(red: 0.7, green: 0.4, blue: 0.2)]
        default: return [.white.opacity(0.7), .white.opacity(0.5)]
        }
    }

    // MARK: - Info Section (shared)
    var infoContent: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            // Type-specific settings
            switch competition.type {
            case .apex:
                InfoRow(icon: "ruler", title: "Unit", value: competition.options.unit.displayName)
                durationRow

            case .streaks:
                InfoRow(
                    icon: "target",
                    title: "Goal",
                    value: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
                )
                if let interval = competition.options.interval {
                    InfoRow(icon: "arrow.trianglehead.2.clockwise", title: "Interval", value: interval.displayName)
                }
                let streakLives = competition.streakLives
                if streakLives > 0 {
                    InfoRow(icon: "heart", title: "Lives", value: "\(streakLives)")
                }

            case .targets:
                InfoRow(
                    icon: "target",
                    title: "Goal",
                    value: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
                )
                if let interval = competition.options.interval {
                    InfoRow(icon: "arrow.trianglehead.2.clockwise", title: "Interval", value: interval.displayName)
                }
                durationRow

            case .clash:
                InfoRow(icon: "ruler", title: "Unit", value: competition.options.unit.displayName)
                if competition.options.first_to > 0 {
                    InfoRow(icon: "star", title: "Points to Win", value: "\(competition.options.first_to)")
                }
                if let interval = competition.options.interval {
                    InfoRow(icon: "arrow.trianglehead.2.clockwise", title: "Interval", value: interval.displayName)
                }

            case .race:
                InfoRow(
                    icon: "target",
                    title: "Goal",
                    value: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
                )
            }

            // Activities (all types) — colored pills
            ActivitiesInfoRow(activities: competition.workouts)
        }
    }

    var infoSection: some View {
        infoContent
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

    @ViewBuilder
    var durationRow: some View {
        if let startDate = competition.startDateFormatted,
           let endDate = competition.endDateFormatted {
            InfoRow(
                icon: "calendar",
                title: "Duration",
                value: "\(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))"
            )
        } else if let durationStr = competition.options.durationFormatted {
            InfoRow(icon: "clock", title: "Duration", value: durationStr)
        }
    }

    // MARK: - Invite Button
    var inviteButton: some View {
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
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
    func refreshCompetition() async {
        do {
            competition = try await competitionService.loadCompetition(id: competition.competition_id)
        } catch {
            print("Error refreshing competition: \(error)")
        }
    }

    func startCompetition() {
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

    func removeUserFromCompetition(_ user: CompetitionUser) {
        removeTargetUser = user
        showRemoveConfirmation = true
    }

    func confirmRemoveUser() {
        guard let user = removeTargetUser else { return }
        Task {
            do {
                try await competitionService.removeUser(
                    competitionId: competition.competition_id,
                    userId: user.user_id
                )
                competition = try await competitionService.loadCompetition(id: competition.competition_id)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            removeTargetUser = nil
        }
    }

    func deleteCompetition() {
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

    func scoreLabel(for user: CompetitionUser) -> String {
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
