import SwiftUI

// MARK: - Lobby Content

extension CompetitionDetailView {

    // MARK: - Lobby Content
    // The countdown/waiting banner + competition settings are now rendered by the
    // unified Timeline / Quick Rules cards at the top of CompetitionDetailView,
    // so this only owns the lobby-specific actions and participant management.
    var lobbyContent: some View {
        VStack(spacing: MADTheme.Spacing.xl) {
            // Edit settings button (owner only, lobby only)
            if competition.isOwner && competition.status == .lobby {
                Button {
                    showingEditSettings = true
                } label: {
                    HStack(spacing: MADTheme.Spacing.sm) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.callout)
                        Text("Edit Settings")
                            .madFont(size: 16, design: .rounded)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(CompeteDesign.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: CompeteDesign.innerRadius, style: .continuous)
                            .fill(CompeteDesign.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CompeteDesign.innerRadius, style: .continuous)
                            .strokeBorder(CompeteDesign.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }

            // Participants with invite statuses
            lobbyParticipantsSection

            // Team setup — owner manages, members join when member-pick is on.
            // Renders nothing for non-owners until teams exist.
            CompetitionLobbyTeamsSection(
                competition: $competition,
                competitionService: competitionService
            )

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

    // MARK: - Lobby Waiting Banner
    var lobbyWaitingBanner: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.orange)
                Text("\(competition.acceptedUsersCount) of \(competition.users.count) joined")
                    .madFont(size: 17, weight: .semibold, design: .rounded)
                    .foregroundColor(.white)
            }

            Text("Waiting for everyone to accept...")
                .madFont(size: 16, design: .rounded)
                .foregroundColor(.white.opacity(0.6))

            ProgressView(
                value: Double(competition.acceptedUsersCount),
                total: Double(max(competition.users.count, 1))
            )
            .tint(.orange)
            .padding(.horizontal, MADTheme.Spacing.xl)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: CompeteDesign.radius, style: .continuous)
                .fill(CompeteDesign.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CompeteDesign.radius, style: .continuous)
                .strokeBorder(CompeteDesign.hairline, lineWidth: 1)
        )
    }

    // MARK: - Scheduled Countdown Banner
    var scheduledCountdownBanner: some View {
        let startDate = competition.startDateFormatted ?? Date()
        let remaining = startDate.timeIntervalSince(Date())
        let hours = max(0, Int(remaining / 3600))
        let minutes = max(0, Int(remaining.truncatingRemainder(dividingBy: 3600) / 60))

        return VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "calendar.badge.clock")
                .madFont(size: 32, maxScale: 1.5)
                .foregroundColor(.blue)

            Text("Competition Starts Soon")
                .madFont(size: 17, weight: .semibold, design: .rounded)
                .foregroundColor(.white)

            // Countdown display
            HStack(spacing: MADTheme.Spacing.lg) {
                VStack(spacing: 2) {
                    Text("\(hours)")
                        .madFont(size: 32, weight: .bold, design: .rounded)
                        .foregroundColor(.white)
                    Text("hours")
                        .madFont(size: 12, design: .rounded)
                        .foregroundColor(.white.opacity(0.5))
                }

                Text(":")
                    .madFont(size: 28, weight: .bold, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))

                VStack(spacing: 2) {
                    Text("\(minutes)")
                        .madFont(size: 32, weight: .bold, design: .rounded)
                        .foregroundColor(.white)
                    Text("min")
                        .madFont(size: 12, design: .rounded)
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            if let startDate = competition.startDateFormatted {
                Text("Begins \(startDate.formatted(date: .abbreviated, time: .omitted))")
                    .madFont(size: 16, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(MADTheme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(CompeteDesign.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Lobby Participants Section
    var lobbyParticipantsSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            CompeteHeader(
                eyebrow: "Competitors",
                trailingText: "\(competition.acceptedUsersCount) of \(competition.users.count) in"
            )
            .padding(.horizontal, 2)

            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(competition.users) { user in
                    LobbyParticipantRow(
                        user: user,
                        isOwner: user.user_id == competition.owner,
                        canRemove: competition.isOwner && user.user_id != competition.owner,
                        onRemove: {
                            removeUserFromCompetition(user)
                        }
                    )
                }
            }
            .padding(MADTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(CompeteDesign.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .strokeBorder(CompeteDesign.hairline, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Start Competition Button
    var startCompetitionButton: some View {
        let canStart = competition.acceptedUsersCount >= 2

        return Button {
            startCompetition()
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                Image(systemName: "flag.checkered")
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Competition")
                        .madFont(size: 17, weight: .semibold, design: .rounded)

                    if !canStart {
                        let needed = 2 - competition.acceptedUsersCount
                        Text("Need \(needed) more participant\(needed == 1 ? "" : "s")")
                            .madFont(size: 12, design: .rounded)
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        Text("Begins tomorrow at midnight")
                            .madFont(size: 12, design: .rounded)
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
            .foregroundColor(canStart ? .white : CompeteDesign.inkFaint)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: CompeteDesign.radius, style: .continuous)
                    .fill(canStart ? MADTheme.Colors.madRed : Color.white.opacity(0.06))
            )
        }
        .disabled(!canStart || isStarting)
        .buttonStyle(ScaleButtonStyle())
    }
}
