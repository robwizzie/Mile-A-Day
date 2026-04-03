import SwiftUI
import HealthKit

// MARK: - Leaderboard & Interval Content

extension CompetitionDetailView {

    // MARK: - Enhanced Leaderboard
    var enhancedLeaderboard: some View {
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
    func enhancedPodium(rankedUsers: [CompetitionUser], gradientColors: [Color], currentUserId: String?) -> some View {
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

    func enhancedPodiumSlot(user: CompetitionUser, rank: Int, colors: [Color], height: CGFloat, avatarSize: CGFloat, isCurrentUser: Bool) -> some View {
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

    // MARK: - Interval Navigator
    var intervalNavigator: some View {
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
    var intervalContent: some View {
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
    func clashIntervalView(key: String, users: [CompetitionUser], currentUserId: String?) -> some View {
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
    func streaksIntervalView(key: String, users: [CompetitionUser], currentUserId: String?) -> some View {
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
    func formatBreakDate(_ isoKey: String) -> String {
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
    func apexIntervalView(key: String, users: [CompetitionUser], currentUserId: String?) -> some View {
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
    func targetsIntervalView(key: String, users: [CompetitionUser], currentUserId: String?) -> some View {
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
    var raceProgressView: some View {
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
    func missedDates(for user: CompetitionUser) -> [String] {
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

    func missCount(for user: CompetitionUser) -> Int {
        return missedDates(for: user).count
    }

    // MARK: - Interval Helpers
    func intervalKey(for date: Date) -> String {
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

    func moveInterval(by amount: Int) {
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

    var intervalDateLabel: String {
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

    func leaderboardScoreLabel(for user: CompetitionUser) -> String {
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
}
