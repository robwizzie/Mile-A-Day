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

            // Full standings (everyone beyond podium)
            if rankedUsers.count > 3 {
                remainingStandings(rankedUsers: rankedUsers, currentUserId: currentUserId)
            }

            // Competition info
            infoSection
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

    // MARK: - Remaining Standings
    func remainingStandings(rankedUsers: [CompetitionUser], currentUserId: String?) -> some View {
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
    func medalGradient(for placement: Int?) -> [Color] {
        switch placement {
        case 1: return [.yellow, .orange]
        case 2: return [Color(white: 0.85), Color(white: 0.6)]
        case 3: return [.brown, Color(red: 0.7, green: 0.4, blue: 0.2)]
        default: return [.white.opacity(0.7), .white.opacity(0.5)]
        }
    }

    // MARK: - Info Section (shared)
    var infoSection: some View {
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
