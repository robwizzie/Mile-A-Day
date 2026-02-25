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

    private var typeGradient: LinearGradient {
        LinearGradient(
            colors: competition.type.gradient.map { Color(hex: $0) },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var ownerUsername: String? {
        competition.users.first(where: { $0.user_id == competition.owner })?.username
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Type color accent on left edge
                RoundedRectangle(cornerRadius: 2)
                    .fill(typeGradient)
                    .frame(width: 4)
                    .padding(.vertical, MADTheme.Spacing.md)

                VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                    // Header: Icon + Name + Owner badge
                    HStack(spacing: MADTheme.Spacing.md) {
                        Image(systemName: competition.type.icon)
                            .font(.title3)
                            .foregroundStyle(typeGradient)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Color(hex: competition.type.gradient[0]).opacity(0.12))
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(competition.competition_name)
                                .font(MADTheme.Typography.headline)
                                .foregroundColor(.white)
                                .lineLimit(1)

                            HStack(spacing: MADTheme.Spacing.xs) {
                                Text(competition.type.displayName)
                                    .font(MADTheme.Typography.caption)
                                    .foregroundColor(.white.opacity(0.5))

                                Text("\u{00B7}")
                                    .foregroundColor(.white.opacity(0.3))

                                Label(
                                    "\(competition.acceptedUsersCount)",
                                    systemImage: "person.2"
                                )
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(.white.opacity(0.5))
                            }
                        }

                        Spacer()

                        if competition.isOwner {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }

                    // Stats chips
                    HStack(spacing: MADTheme.Spacing.sm) {
                        // Goal chip (not for Clash or Apex)
                        if competition.type != .clash && competition.type != .apex {
                            StatChip(
                                icon: "target",
                                text: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
                            )
                        }

                        // Points chip (Clash) or Lives chip (Streaks)
                        if competition.type == .clash && competition.options.first_to > 0 {
                            StatChip(
                                icon: "star",
                                text: "First to \(competition.options.first_to)"
                            )
                        }

                        if competition.type == .streaks && competition.options.first_to > 0 {
                            if let currentUserId = UserDefaults.standard.string(forKey: "backendUserId"),
                               let currentUser = competition.users.first(where: { $0.user_id == currentUserId }),
                               let lives = currentUser.remaining_lives {
                                LivesChip(remaining: lives, total: competition.options.first_to)
                            } else {
                                StatChip(
                                    icon: "heart",
                                    text: "\(competition.options.first_to) \(competition.options.first_to == 1 ? "life" : "lives")"
                                )
                            }
                        }

                        if let durationStr = competition.options.durationFormatted {
                            StatChip(icon: "clock", text: durationStr)
                        }

                        if let interval = competition.options.interval {
                            StatChip(icon: "arrow.trianglehead.2.clockwise", text: interval.displayName)
                        }

                        Spacer()
                    }

                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)

                    competitionStatusFooter
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.vertical, MADTheme.Spacing.md)
            }
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    @ViewBuilder
    private var competitionStatusFooter: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            // Participant avatars with status indicators
            HStack(spacing: MADTheme.Spacing.sm) {
                ForEach(Array(competition.users.prefix(6)), id: \.id) { user in
                    ParticipantAvatar(user: user, isOwner: user.user_id == competition.owner)
                }

                if competition.users.count > 6 {
                    Text("+\(competition.users.count - 6)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                }

                Spacer()

                // Status label
                HStack(spacing: 5) {
                    Circle()
                        .fill(competition.status.color)
                        .frame(width: 6, height: 6)

                    Text(statusText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(competition.status.color)
                }
            }
        }
    }

    private var statusText: String {
        switch competition.status {
        case .lobby:
            return "\(competition.acceptedUsersCount)/\(competition.users.count) joined"
        case .scheduled:
            if let startDate = competition.startDateFormatted {
                return "Starts \(startDate.formatted(date: .abbreviated, time: .omitted))"
            }
            return "Scheduled"
        case .active:
            if let endDate = competition.endDateFormatted {
                let remaining = endDate.timeIntervalSince(Date())
                if remaining > 0 {
                    let days = Int(remaining / 86400)
                    let hours = Int(remaining.truncatingRemainder(dividingBy: 86400) / 3600)
                    return days > 0 ? "\(days)d \(hours)h left" : "\(hours)h left"
                }
            }
            return "In progress"
        case .finished:
            return "Completed"
        }
    }
}

// MARK: - Stat Chip

struct StatChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundColor(.white.opacity(0.7))
        .padding(.horizontal, MADTheme.Spacing.sm)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
    }
}

// MARK: - Lives Chip

struct LivesChip: View {
    let remaining: Int
    let total: Int

    private var isEliminated: Bool { remaining <= 0 }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { i in
                let alive = i < remaining
                Image(systemName: alive ? "heart.fill" : "heart.slash.fill")
                    .font(.system(size: 8))
                    .foregroundColor(alive ? .red : .gray.opacity(0.4))
                    .shadow(color: alive ? .red.opacity(0.3) : .clear, radius: 1)
            }

            if isEliminated {
                Text("OUT")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(.horizontal, MADTheme.Spacing.sm)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(isEliminated ? Color.red.opacity(0.1) : Color.white.opacity(0.08))
        )
    }
}

// MARK: - Participant Avatar

struct ParticipantAvatar: View {
    let user: CompetitionUser
    let isOwner: Bool

    private var statusColor: Color {
        switch user.invite_status {
        case .accepted: return .green
        case .pending: return .orange
        case .declined: return .red
        }
    }

    private var statusIcon: String {
        switch user.invite_status {
        case .accepted: return "checkmark"
        case .pending: return "clock"
        case .declined: return "xmark"
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(user.displayName.prefix(1).uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                )
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.8), lineWidth: 2)
                )

            // Status badge
            Image(systemName: statusIcon)
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 12, height: 12)
                .background(
                    Circle()
                        .fill(statusColor)
                )
                .overlay(
                    Circle()
                        .stroke(Color(white: 0.1), lineWidth: 1)
                )
                .offset(x: 2, y: 2)
        }
    }
}

// MARK: - Invite Card

struct InviteCard: View {
    let competition: Competition
    let onAccept: () -> Void
    let onDecline: () -> Void

    private var typeGradient: LinearGradient {
        LinearGradient(
            colors: competition.type.gradient.map { Color(hex: $0) },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var ownerUsername: String? {
        competition.users.first(where: { $0.user_id == competition.owner })?.username
    }

    var body: some View {
        HStack(spacing: 0) {
            // Type color accent on left edge
            RoundedRectangle(cornerRadius: 2)
                .fill(typeGradient)
                .frame(width: 4)
                .padding(.vertical, MADTheme.Spacing.md)

            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                // Header: Icon + Name + From
                HStack(spacing: MADTheme.Spacing.md) {
                    Image(systemName: competition.type.icon)
                        .font(.title3)
                        .foregroundStyle(typeGradient)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color(hex: competition.type.gradient[0]).opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(competition.competition_name)
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)

                        HStack(spacing: MADTheme.Spacing.xs) {
                            Text(competition.type.displayName)
                                .font(MADTheme.Typography.caption)
                                .foregroundColor(.white.opacity(0.5))

                            Text("\u{00B7}")
                                .foregroundColor(.white.opacity(0.3))

                            HStack(spacing: 2) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 9))
                                Text("from \(ownerUsername ?? "someone")")
                            }
                            .font(MADTheme.Typography.caption)
                            .foregroundColor(.white.opacity(0.5))
                        }
                    }

                    Spacer()
                }

                // Stats chips
                HStack(spacing: MADTheme.Spacing.sm) {
                    if competition.type != .clash {
                        StatChip(
                            icon: "target",
                            text: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
                        )
                    }

                    if let durationStr = competition.options.durationFormatted {
                        StatChip(icon: "clock", text: durationStr)
                    }

                    Spacer()
                }

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)

                // Action buttons
                HStack(spacing: MADTheme.Spacing.md) {
                    Button(action: onDecline) {
                        HStack(spacing: MADTheme.Spacing.xs) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Decline")
                                .font(MADTheme.Typography.callout)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())

                    Button(action: onAccept) {
                        HStack(spacing: MADTheme.Spacing.xs) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Accept")
                                .font(MADTheme.Typography.callout)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .fill(MADTheme.Colors.primaryGradient)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.md)
        }
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
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
    var firstTo: Int = 0

    private var isEliminated: Bool {
        guard competitionType == .streaks, firstTo > 0 else { return false }
        guard let lives = user.remaining_lives else { return false }
        return lives <= 0
    }

    var rankGradient: [Color] {
        switch rank {
        case 1: return [.yellow, .orange]
        case 2: return [Color(white: 0.85), Color(white: 0.6)]
        case 3: return [Color(red: 0.8, green: 0.5, blue: 0.2), Color(red: 0.6, green: 0.35, blue: 0.15)]
        default: return []
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
            // Rank badge
            if rank <= 3 {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: rankGradient.map { $0.opacity(0.2) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                    Text("\(rank)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: rankGradient,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            } else {
                Text("\(rank)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 30)
            }

            // Avatar
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(user.displayName.prefix(1).uppercased())
                        .font(MADTheme.Typography.callout)
                        .foregroundColor(.white.opacity(isEliminated ? 0.4 : 1.0))
                )
                .overlay(
                    Circle()
                        .stroke(
                            isEliminated
                                ? AnyShapeStyle(Color.red.opacity(0.3))
                                : (rank <= 3
                                    ? AnyShapeStyle(LinearGradient(colors: rankGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                                    : AnyShapeStyle(Color.white.opacity(0.15))),
                            lineWidth: rank <= 3 ? 2 : 1
                        )
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: MADTheme.Spacing.xs) {
                    Text(user.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(isEliminated ? 0.4 : 1.0))

                    if isCurrentUser {
                        Text("YOU")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(MADTheme.Colors.madRed))
                    }

                    if isEliminated {
                        Text("OUT")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red.opacity(0.4)))
                    }
                }

                // Lives indicator for streaks - clean heart icons instead of dots
                if competitionType == .streaks && firstTo > 0, let lives = user.remaining_lives {
                    HStack(spacing: 2) {
                        ForEach(0..<min(firstTo, 6), id: \.self) { i in
                            Image(systemName: i < lives ? "heart.fill" : "heart")
                                .font(.system(size: 7))
                                .foregroundColor(i < lives ? .red : .white.opacity(0.15))
                        }
                        if firstTo > 6 {
                            Text("+\(firstTo - 6)")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                }
            }

            Spacer()

            // Score with icon
            HStack(spacing: 4) {
                if competitionType == .streaks {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11))
                        .foregroundColor(isEliminated ? .gray.opacity(0.3) : .orange)
                }
                Text(scoreText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(isEliminated ? 0.4 : 0.9))
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(isCurrentUser ? 0.08 : (rank == 1 ? 0.04 : 0.0)))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(
                            isEliminated
                                ? Color.red.opacity(0.1)
                                : (isCurrentUser
                                    ? MADTheme.Colors.primary.opacity(0.5)
                                    : (rank == 1 ? rankGradient.first?.opacity(0.15) ?? Color.clear : Color.clear)),
                            lineWidth: isCurrentUser ? 1.5 : 1
                        )
                )
        )
        .opacity(isEliminated ? 0.6 : 1.0)
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
