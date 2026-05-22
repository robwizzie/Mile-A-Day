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
            VStack(alignment: .leading, spacing: 14) {
                cardHeader
                statChipsRow
                // Rivalry hint — shown inline when the viewer is within
                // striking distance of overtaking the next person above
                // them. Tightly scoped to active comps with comparison-based
                // scoring (skips streaks).
                if let hint = competition.rivalryHint {
                    rivalryHintRow(hint)
                }
                cardFooter
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        // Subtle type-tinted color wash so the card reads as
                        // "this kind of competition" at a glance without the
                        // heavy left-edge strip that dominated visually.
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: competition.type.gradient[0]).opacity(0.10),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color(hex: competition.type.gradient[0]).opacity(0.35),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Header (icon + name + type + crown)

    private var cardHeader: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            // Type icon in a colored disc — the focal element.
            Image(systemName: competition.type.icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(typeGradient)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(Color(hex: competition.type.gradient[0]).opacity(0.14))
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: competition.type.gradient.map { Color(hex: $0).opacity(0.55) },
                                        startPoint: .top, endPoint: .bottom
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(competition.competition_name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(competition.type.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }

            Spacer(minLength: 4)

            if competition.isWinner {
                // Gold crown puck — matches the trophy-pill style used in
                // headers across the app. Reads as a flex, not an alert.
                Image(systemName: "crown.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.yellow.opacity(0.20), Color.orange.opacity(0.10)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .overlay(Circle().strokeBorder(Color.yellow.opacity(0.4), lineWidth: 1))
                    )
            }
        }
    }

    // MARK: - Stat chips (type-specific)

    @ViewBuilder
    private var statChipsRow: some View {
        // Horizontal scroll catches long chip rows (e.g., Targets with goal +
        // interval + duration) without truncating or wrapping awkwardly.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                switch competition.type {
                case .apex:
                    StatChip(icon: "ruler", text: competition.options.unit.shortDisplayName)
                    if let durationStr = competition.options.durationFormatted {
                        StatChip(icon: "clock", text: durationStr)
                    }

                case .streaks:
                    StatChip(
                        icon: "target",
                        text: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
                    )
                    if let interval = competition.options.interval {
                        StatChip(icon: "arrow.trianglehead.2.clockwise", text: interval.displayName)
                    }
                    let streakLives = competition.streakLives
                    if streakLives > 0 {
                        if let currentUserId = UserDefaults.standard.string(forKey: "backendUserId"),
                           let currentUser = competition.users.first(where: { $0.user_id == currentUserId }),
                           let lives = currentUser.remaining_lives {
                            LivesChip(remaining: lives, total: streakLives)
                        } else {
                            StatChip(
                                icon: "heart",
                                text: "\(streakLives) \(streakLives == 1 ? "life" : "lives")"
                            )
                        }
                    }

                case .targets:
                    StatChip(
                        icon: "target",
                        text: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
                    )
                    if let interval = competition.options.interval {
                        StatChip(icon: "arrow.trianglehead.2.clockwise", text: interval.displayName)
                    }
                    if let durationStr = competition.options.durationFormatted {
                        StatChip(icon: "clock", text: durationStr)
                    }

                case .clash:
                    StatChip(icon: "ruler", text: competition.options.unit.shortDisplayName)
                    if competition.options.first_to > 0 {
                        StatChip(
                            icon: "star",
                            text: "First to \(competition.options.first_to)"
                        )
                    }
                    if let interval = competition.options.interval {
                        StatChip(icon: "arrow.trianglehead.2.clockwise", text: interval.displayName)
                    }

                case .race:
                    StatChip(
                        icon: "target",
                        text: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
                    )
                }

                // Workout-type chips inline with stats so users see "you can do
                // this as running or walking" alongside the rules.
                ForEach(competition.workouts, id: \.self) { activity in
                    StatChip(icon: activity.icon, text: activity.displayName, accent: activity.color)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    // MARK: - Rivalry Hint Row

    /// Inline "you're X behind Y" badge surfaced on active comps when the
    /// viewer is close to overtaking. Designed to be a celebratory nudge —
    /// orange accent + arrow.up icon imply "push for it" rather than alarm.
    private func rivalryHintRow(_ hint: RivalryHint) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text(hint.gapText)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(.orange)

            Text(hint.actionSuffix)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.12))
                .overlay(Capsule().strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
        )
    }

    // MARK: - Footer (participants + status pill)

    private var cardFooter: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            // Positive spacing instead of overlapping — the previous -8
            // overlap required a black ring overlay to visually separate
            // adjacent avatars, but that overlay sat on top of each avatar's
            // status ring (green/orange/red) and corner status badge,
            // hiding both. With positive spacing the status colors do the
            // separation work themselves, and the badges are fully visible.
            HStack(spacing: 6) {
                ForEach(Array(competition.users.prefix(4)), id: \.id) { user in
                    ParticipantAvatar(user: user, isOwner: user.user_id == competition.owner)
                }
            }

            if competition.users.count > 4 {
                Text("+\(competition.users.count - 4)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                    )
            }

            Spacer()

            statusPill
        }
    }

    /// Status condensed to a single pill — dot + colored text on a tinted
    /// background. Same visual grammar as the leaderboard score pills.
    private var statusPill: some View {
        let accent = competition.status.color
        let label: String = {
            if competition.status == .finished, let winner = winnerName {
                return "🏆 \(winner) won"
            }
            return statusText
        }()
        return HStack(spacing: 5) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(accent)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(accent.opacity(0.12))
                .overlay(Capsule().strokeBorder(accent.opacity(0.3), lineWidth: 1))
        )
    }

    private var winnerName: String? {
        guard competition.status == .finished else { return nil }
        let accepted = competition.users.filter { $0.invite_status == .accepted }
        guard let winner = accepted.sorted(by: { ($0.score ?? 0) > ($1.score ?? 0) }).first,
              (winner.score ?? 0) > 0 else { return nil }
        return winner.displayName
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
            if let endDate = competition.endDateFormatted {
                return "Ended \(endDate.formatted(date: .abbreviated, time: .omitted))"
            }
            return "Completed"
        }
    }
}

// MARK: - Stat Chip

struct StatChip: View {
    let icon: String
    let text: String
    /// Optional accent color — when set, icon + border take this tint so
    /// chips can convey meaning (e.g., activity-type color coding) without
    /// breaking the otherwise-neutral chip aesthetic.
    var accent: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(accent ?? .white.opacity(0.7))
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, MADTheme.Spacing.sm)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(accent?.opacity(0.12) ?? Color.white.opacity(0.08))
                .overlay(
                    Capsule()
                        .strokeBorder(accent?.opacity(0.3) ?? Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

// MARK: - Lives Chip

struct LivesChip: View {
    let remaining: Int
    let total: Int

    private var isEliminated: Bool { remaining <= 0 }
    private var isLastLife: Bool { remaining == 1 && total > 1 }

    /// Color encodes danger level:
    /// - eliminated → red wash
    /// - last life → red accent (one slip and you're out)
    /// - otherwise → neutral pink/red on glass
    private var accent: Color {
        if isEliminated { return .red }
        if isLastLife { return .red }
        return Color(red: 0.95, green: 0.35, blue: 0.45)
    }

    var body: some View {
        HStack(spacing: 4) {
            if isEliminated {
                // OUT pill — no hearts, just the bad-news state.
                Image(systemName: "heart.slash.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("OUT")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.4)
            } else {
                // ♥ N — clear count with a single heart glyph. Better than
                // a row of tiny heart icons that read as decoration rather
                // than data (especially when total is 1).
                Image(systemName: "heart.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("\(remaining)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                if isLastLife {
                    Text("LAST")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .opacity(0.85)
                }
            }
        }
        .foregroundColor(accent)
        .padding(.horizontal, MADTheme.Spacing.sm)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(accent.opacity(isEliminated || isLastLife ? 0.18 : 0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(accent.opacity(isLastLife ? 0.5 : 0.3), lineWidth: 1)
                )
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
        case .pending: return "clock.fill"
        case .declined: return "xmark"
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 28)
                .overlay(
                    Circle()
                        .strokeBorder(statusColor.opacity(0.85), lineWidth: 2)
                )

            // Status badge positioned at the TOP of the avatar so it doesn't
            // collide with overlapping stacks (footer rows often pack avatars
            // tight and a bottom badge gets covered by the next avatar's
            // edge). Top placement is always visible.
            Image(systemName: statusIcon)
                .font(.system(size: 7, weight: .heavy))
                .foregroundColor(.white)
                .frame(width: 13, height: 13)
                .background(Circle().fill(statusColor))
                .overlay(Circle().strokeBorder(Color(white: 0.1), lineWidth: 1.5))
                .offset(x: 2, y: -2)
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
                    switch competition.type {
                    case .apex:
                        StatChip(icon: "ruler", text: competition.options.unit.shortDisplayName)
                        if let durationStr = competition.options.durationFormatted {
                            StatChip(icon: "clock", text: durationStr)
                        }

                    case .streaks:
                        StatChip(
                            icon: "target",
                            text: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
                        )
                        if let interval = competition.options.interval {
                            StatChip(icon: "arrow.trianglehead.2.clockwise", text: interval.displayName)
                        }
                        let streakLives = competition.streakLives
                        if streakLives > 0 {
                            StatChip(
                                icon: "heart",
                                text: "\(streakLives) \(streakLives == 1 ? "life" : "lives")"
                            )
                        }

                    case .targets:
                        StatChip(
                            icon: "target",
                            text: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
                        )
                        if let interval = competition.options.interval {
                            StatChip(icon: "arrow.trianglehead.2.clockwise", text: interval.displayName)
                        }
                        if let durationStr = competition.options.durationFormatted {
                            StatChip(icon: "clock", text: durationStr)
                        }

                    case .clash:
                        StatChip(icon: "ruler", text: competition.options.unit.shortDisplayName)
                        if competition.options.first_to > 0 {
                            StatChip(
                                icon: "star",
                                text: "First to \(competition.options.first_to)"
                            )
                        }
                        if let interval = competition.options.interval {
                            StatChip(icon: "arrow.trianglehead.2.clockwise", text: interval.displayName)
                        }

                    case .race:
                        StatChip(
                            icon: "target",
                            text: "\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)"
                        )
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
    var canRemove: Bool = false
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 44)
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

            if canRemove, let onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            } else {
                statusIcon
            }
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
                .font(.title3)
                .foregroundColor(.green)
        case .pending:
            Image(systemName: "clock.fill")
                .font(.title3)
                .foregroundColor(.orange)
        case .declined:
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
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
    /// Total streak lives for the competition. Ignored outside streak competitions.
    var totalLives: Int = 0

    private var isEliminated: Bool {
        guard competitionType == .streaks, totalLives > 0 else { return false }
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
            AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 40)
                .opacity(isEliminated ? 0.6 : 1.0)
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

                    if user.has_manual_workouts == true {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 7))
                            Text("MANUAL")
                                .font(.system(size: 7, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange))
                    }
                }

                // Lives indicator for streaks - clean heart icons instead of dots
                if competitionType == .streaks && totalLives > 0, let lives = user.remaining_lives {
                    HStack(spacing: 2) {
                        ForEach(0..<min(totalLives, 6), id: \.self) { i in
                            Image(systemName: i < lives ? "heart.fill" : "heart")
                                .font(.system(size: 7))
                                .foregroundColor(i < lives ? .red : .white.opacity(0.15))
                        }
                        if totalLives > 6 {
                            Text("+\(totalLives - 6)")
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
                    .fill(isSelected
                        ? LinearGradient(colors: [activity.color, activity.color.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [Color.white.opacity(0.1)], startPoint: .leading, endPoint: .trailing))
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
