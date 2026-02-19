import SwiftUI

// MARK: - Competition Type Card

struct CompetitionTypeCard: View {
    let type: CompetitionType
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                HStack {
                    Image(systemName: type.icon)
                        .font(.title)
                        .foregroundStyle(
                            LinearGradient(
                                colors: type.gradient.map { Color(hex: $0) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .background(
                            Circle()
                                .fill(Color(hex: type.gradient[0]).opacity(0.15))
                        )

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(MADTheme.Colors.primary)
                    }
                }

                Text(type.displayName)
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.white)

                Text(type.description)
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)
            }
            .padding(MADTheme.Spacing.lg)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(
                            isSelected
                                ? AnyShapeStyle(MADTheme.Colors.primary)
                                : AnyShapeStyle(LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .shadow(
                color: isSelected ? MADTheme.Colors.primary.opacity(0.3) : .black.opacity(0.1),
                radius: isSelected ? 12 : 8,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Competition Card

struct CompetitionCard: View {
    let competition: Competition
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                // Header with icon, type, and status
                HStack {
                    Image(systemName: competition.type.icon)
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: competition.type.gradient.map { Color(hex: $0) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color(hex: competition.type.gradient[0]).opacity(0.15))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(competition.competition_name)
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(competition.type.displayName)
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

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

                    if competition.isOwner {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }

                // Goal info
                HStack(spacing: MADTheme.Spacing.sm) {
                    Label(
                        "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)",
                        systemImage: "target"
                    )
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white.opacity(0.9))

                    Spacer()

                    Label(
                        "\(competition.acceptedUsersCount) participant\(competition.acceptedUsersCount == 1 ? "" : "s")",
                        systemImage: "person.2.fill"
                    )
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white.opacity(0.9))
                }

                // Time info based on status
                competitionTimeInfo
            }
            .padding(MADTheme.Spacing.lg)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: competition.type.gradient.map { Color(hex: $0) },
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4)
                    .padding(.vertical, MADTheme.Spacing.md)
                    .padding(.leading, 2)
            }
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    @ViewBuilder
    private var competitionTimeInfo: some View {
        switch competition.status {
        case .lobby:
            if let durationStr = competition.options.durationFormatted {
                HStack(spacing: MADTheme.Spacing.xs) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.orange.opacity(0.8))
                    Text("Duration: \(durationStr) \u{00B7} Waiting to start")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.orange.opacity(0.8))
                }
            } else {
                HStack(spacing: MADTheme.Spacing.xs) {
                    Image(systemName: "hourglass")
                        .font(.caption)
                        .foregroundColor(.orange.opacity(0.8))
                    Text("Open-ended \u{00B7} Waiting to start")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.orange.opacity(0.8))
                }
            }
        case .scheduled:
            if let startDate = competition.startDateFormatted {
                HStack(spacing: MADTheme.Spacing.xs) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundColor(.blue.opacity(0.8))
                    Text("Starts \(startDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.blue.opacity(0.8))
                }
            }
        case .active:
            if let endDate = competition.endDateFormatted {
                let remaining = endDate.timeIntervalSince(Date())
                if remaining > 0 {
                    let days = Int(remaining / 86400)
                    let hours = Int(remaining.truncatingRemainder(dividingBy: 86400) / 3600)
                    HStack(spacing: MADTheme.Spacing.xs) {
                        Image(systemName: "timer")
                            .font(.caption)
                            .foregroundColor(.green.opacity(0.9))
                        Text(days > 0 ? "\(days)d \(hours)h left" : "\(hours)h left")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.green.opacity(0.9))
                    }
                }
            } else {
                HStack(spacing: MADTheme.Spacing.xs) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(.green.opacity(0.9))
                    Text("In progress")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.green.opacity(0.9))
                }
            }
        case .finished:
            if let startDate = competition.startDateFormatted,
               let endDate = competition.endDateFormatted {
                HStack(spacing: MADTheme.Spacing.xs) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }
}

// MARK: - Invite Card

struct InviteCard: View {
    let competition: Competition
    let onAccept: () -> Void
    let onDecline: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            // Header
            HStack {
                Image(systemName: competition.type.icon)
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: competition.type.gradient.map { Color(hex: $0) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color(hex: competition.type.gradient[0]).opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(competition.competition_name)
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.white)

                    Text("from \(competition.owner)")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()
            }

            // Type and goal
            VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                Text(competition.type.displayName)
                    .font(MADTheme.Typography.subheadline)
                    .foregroundColor(.white.opacity(0.9))

                Text(competition.type.description)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)

                HStack(spacing: MADTheme.Spacing.sm) {
                    Label(
                        "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)",
                        systemImage: "target"
                    )
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(.white.opacity(0.9))
                }
            }

            // Action buttons
            HStack(spacing: MADTheme.Spacing.md) {
                Button(action: onDecline) {
                    Text("Decline")
                        .font(MADTheme.Typography.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(ScaleButtonStyle())

                Button(action: onAccept) {
                    Text("Accept")
                        .font(MADTheme.Typography.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .fill(MADTheme.Colors.primaryGradient)
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(MADTheme.Spacing.lg)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Lobby Participant Row

struct LobbyParticipantRow: View {
    let user: CompetitionUser
    let isOwner: Bool

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(user.displayName.prefix(1).uppercased())
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.white)
                )
                .overlay(
                    Circle()
                        .stroke(statusBorderColor, lineWidth: 2)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MADTheme.Spacing.xs) {
                    Text(user.displayName)
                        .font(MADTheme.Typography.callout)
                        .foregroundColor(.white)

                    if isOwner {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }

                Text(user.invite_status.displayName)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(statusColor)
            }

            Spacer()

            statusIcon
        }
    }

    private var statusColor: Color {
        switch user.invite_status {
        case .accepted: return .green
        case .pending: return .orange
        case .declined: return .red
        }
    }

    private var statusBorderColor: Color {
        switch user.invite_status {
        case .accepted: return .green.opacity(0.5)
        case .pending: return .orange.opacity(0.5)
        case .declined: return .red.opacity(0.5)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch user.invite_status {
        case .accepted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .pending:
            Image(systemName: "clock.fill")
                .foregroundColor(.orange)
        case .declined:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }
}

// MARK: - Competition Leaderboard Row

struct CompetitionLeaderboardRow: View {
    let rank: Int
    let user: CompetitionUser
    let competitionType: CompetitionType
    let unit: CompetitionUnit
    let isCurrentUser: Bool

    var medalColor: Color? {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .brown
        default: return nil
        }
    }

    var scoreText: String {
        let score = user.score ?? 0
        switch competitionType {
        case .streaks:
            return "\(Int(score)) day\(Int(score) == 1 ? "" : "s")"
        case .apex, .race:
            return String(format: "%.1f %@", score, unit.shortDisplayName)
        case .targets, .clash:
            return "\(Int(score)) pt\(Int(score) == 1 ? "" : "s")"
        }
    }

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            if let medal = medalColor {
                Image(systemName: "medal.fill")
                    .font(.title3)
                    .foregroundColor(medal)
                    .frame(width: 30)
            } else {
                Text("\(rank)")
                    .font(MADTheme.Typography.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 30)
            }

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(user.displayName.prefix(1).uppercased())
                        .font(MADTheme.Typography.callout)
                        .foregroundColor(.white)
                )
                .overlay(
                    Circle()
                        .stroke(
                            rank == 1
                                ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Color.white.opacity(0.2)),
                            lineWidth: rank <= 3 ? 2 : 1
                        )
                )

            Text(user.displayName)
                .font(MADTheme.Typography.headline)
                .foregroundColor(.white)

            Spacer()

            Text(scoreText)
                .font(MADTheme.Typography.callout)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(isCurrentUser ? 0.1 : (rank == 1 ? 0.05 : 0.0)))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(
                            isCurrentUser ? MADTheme.Colors.primary : Color.clear,
                            lineWidth: 2
                        )
                )
        )
    }
}

// MARK: - Activity Toggle

struct ActivityToggle: View {
    let activity: CompetitionActivity
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: activity.icon)
                    .font(.caption)

                Text(activity.displayName)
                    .font(MADTheme.Typography.callout)
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.7))
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.pill)
                    .fill(isSelected ? MADTheme.Colors.primaryGradient : LinearGradient(colors: [Color.white.opacity(0.1)], startPoint: .leading, endPoint: .trailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.pill)
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Tab Button

struct CompetitionTabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: MADTheme.Spacing.xs) {
                HStack(spacing: MADTheme.Spacing.xs) {
                    Text(title)
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(isSelected ? MADTheme.Colors.madRed : MADTheme.Colors.secondaryText)

                    if count > 0 {
                        Text("\(count)")
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, MADTheme.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(MADTheme.Colors.madRed)
                            )
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

// MARK: - Custom Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
