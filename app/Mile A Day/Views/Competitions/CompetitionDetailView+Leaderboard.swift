import SwiftUI
import HealthKit

// MARK: - Leaderboard & Interval Content

extension CompetitionDetailView {

    // MARK: - Enhanced Leaderboard
    /// Unified leaderboard list — no separate podium block. The top three rows get
    /// a medal-colored rank badge and accent stripe inline so they still stand out
    /// without being disconnected from the rest of the rankings. Tap any row to
    /// expand a daily activity strip showing per-day progress.
    var enhancedLeaderboard: some View {
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        let rankedUsers = competition.users
            .filter { $0.invite_status == .accepted }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        let gradientColors = competition.type.gradient.map { Color(hex: $0) }

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
                    // Unified rows — every competitor in one connected list
                    VStack(spacing: 6) {
                        ForEach(Array(rankedUsers.enumerated()), id: \.element.id) { index, user in
                            let isMe = user.user_id == currentUserId
                            let rank = index + 1

                            leaderboardEntry(
                                rank: rank,
                                user: user,
                                isMe: isMe,
                                isExpanded: false
                            )
                            .opacity(leaderboardAnimated ? 1 : 0)
                            .offset(y: leaderboardAnimated ? 0 : 15)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.8)
                                    .delay(0.1 + Double(index) * 0.05),
                                value: leaderboardAnimated
                            )
                        }
                    }

                    // Comp-wide activity calendar — defaults to "viewing all", tap
                    // any leaderboard row to focus on that competitor, "Show all"
                    // pill on the calendar returns to aggregate. For streaks, the
                    // focused-user view also overlays life-loss / elimination cues
                    // so it doubles as the streak status calendar.
                    DailyActivityCalendar(
                        allUsers: rankedUsers,
                        competition: competition,
                        accent: gradientColors.first ?? MADTheme.Colors.madRed,
                        focusedUserId: $expandedLeaderboardUserId
                    )
                }
                .padding(MADTheme.Spacing.md)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    leaderboardAnimated = true
                }
            }
        }
    }

    /// One leaderboard row. Tapping it focuses the shared calendar on that
    /// competitor. Tapping the same row again clears focus (back to "all"). A
    /// medal-colored left rail runs through every row — wider when the row is
    /// the focused one, so the active selection is unmistakable.
    @ViewBuilder
    func leaderboardEntry(rank: Int, user: CompetitionUser, isMe: Bool, isExpanded: Bool) -> some View {
        let isFocused = expandedLeaderboardUserId == user.user_id

        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                if isFocused {
                    expandedLeaderboardUserId = nil
                } else {
                    expandedLeaderboardUserId = user.user_id
                }
            }
        } label: {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: medalRankGradient(rank),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: isFocused ? 5 : 3)
                    .padding(.vertical, 8)
                    .shadow(color: isFocused ? (medalRankGradient(rank).first ?? .white).opacity(0.5) : .clear, radius: 4)

                CompetitionLeaderboardRow(
                    rank: rank,
                    user: user,
                    competitionType: competition.type,
                    unit: competition.options.unit,
                    isCurrentUser: isMe,
                    totalLives: competition.type == .streaks ? competition.streakLives : 0
                )
            }
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(isFocused ? Color.white.opacity(0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    func medalRankGradient(_ rank: Int) -> [Color] {
        switch rank {
        case 1: return [.yellow, .orange]
        case 2: return [Color(white: 0.85), Color(white: 0.6)]
        case 3: return [Color(red: 0.85, green: 0.55, blue: 0.25), Color(red: 0.6, green: 0.35, blue: 0.15)]
        default: return [Color.white.opacity(0.22), Color.white.opacity(0.08)]
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
                AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: avatarSize)
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

            VStack(spacing: 3) {
                Text(intervalDateLabel)
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.white)

                if let range = intervalRangeLabel {
                    Text(range)
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.5))
                } else if !isToday {
                    Text(selectedIntervalDate.formatted(date: .abbreviated, time: .omitted))
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.white.opacity(0.5))
                }

                if competition.isCurrentInterval(selectedIntervalDate) {
                    intervalCountdown
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
            EmptyView()
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

                        AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 36)

                        Text(user.displayName)
                            .font(MADTheme.Typography.callout)
                            .foregroundColor(.white)

                        Spacer()

                        Text(competition.options.formatQuantityWithUnit(distance))
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
                        AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 36)

                        Text(user.displayName)
                            .font(MADTheme.Typography.callout)
                            .foregroundColor(.white)

                        Spacer()

                        Text(competition.options.formatQuantityWithUnit(distance))
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

                            AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 36)

                            Text(user.displayName)
                                .font(MADTheme.Typography.callout)
                                .foregroundColor(.white)

                            Spacer()

                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(competition.options.formatQuantity(distance))/\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
                                    .font(MADTheme.Typography.callout)
                                    .foregroundColor(hitTarget ? .green : .white.opacity(0.7))
                                if hitTarget && distance > goal {
                                    Text("+\(competition.options.formatQuantity(distance - goal)) over")
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
                                Text("\(competition.options.formatQuantity(distance))/\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(finished ? .green : .white.opacity(0.7))
                                if distance > goal {
                                    Text("+\(competition.options.formatQuantity(distance - goal)) over")
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
            return competition.weeklyIntervalKey(for: date)
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
            // Weeks are anchored to the competition's start date, so the label
            // reflects "Week N" of the comp rather than the calendar week. The
            // explicit Wed→Tue date range is shown separately in intervalRangeLabel.
            if competition.isCurrentInterval(selectedIntervalDate) {
                return "This Week"
            }
            if let startDate = competition.startDateFormatted {
                let window = competition.intervalWindow(for: selectedIntervalDate)
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: window.start).day ?? 0
                return "Week \(max(1, days / 7 + 1))"
            }
            return "Week"
        case .month:
            if calendar.isDate(Date(), equalTo: selectedIntervalDate, toGranularity: .month) {
                return "This Month"
            }
            return selectedIntervalDate.formatted(.dateTime.month(.wide).year())
        }
    }

    /// Explicit start→end day range for the selected interval (e.g. "Wed, May 21 –
    /// Tue, May 27"), so users can see exactly which days an anchored window covers.
    /// Returned only for week/month intervals — daily intervals are self-evident.
    var intervalRangeLabel: String? {
        let interval = competition.options.interval ?? .day
        guard interval != .day else { return nil }
        let window = competition.intervalWindow(for: selectedIntervalDate)
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        let plain = Date.FormatStyle.dateTime.month(.abbreviated).day()
        switch interval {
        case .week:
            return "\(window.start.formatted(style)) – \(window.end.formatted(style))"
        case .month:
            return "\(window.start.formatted(plain)) – \(window.end.formatted(plain))"
        case .day:
            return nil
        }
    }

    /// Live "Ends in 2d 4h" countdown until the current interval closes. Ticks each
    /// minute via TimelineView and clamps to the competition's own end date.
    @ViewBuilder
    var intervalCountdown: some View {
        let expiry = competition.intervalExpiry(for: selectedIntervalDate)
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let remaining = max(0, expiry.timeIntervalSince(context.date))
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 10, weight: .semibold))
                Text(remaining <= 0 ? "Interval ended" : "Ends in \(Self.countdownString(remaining))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundColor(MADTheme.Colors.madRed)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(MADTheme.Colors.madRed.opacity(0.14))
            )
        }
    }

    /// Compact "2d 4h" / "5h 12m" / "8m" remaining-time string.
    static func countdownString(_ total: TimeInterval) -> String {
        let secs = Int(total)
        let days = secs / 86_400
        let hours = (secs % 86_400) / 3_600
        let mins = (secs % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(max(1, mins))m"
    }

    func leaderboardScoreLabel(for user: CompetitionUser) -> String {
        let score = user.score ?? 0
        switch competition.type {
        case .streaks:
            return "\(Int(score))d"
        case .apex, .race:
            return competition.options.formatQuantityWithUnit(score)
        case .targets, .clash:
            return "\(Int(score)) pts"
        }
    }
}

// MARK: - Daily Activity Calendar
// Per-user, per-day activity breakdown shown inline below a tapped leaderboard
// row. Reads `user.intervals` (keyed by ISO date) and renders a real monthly
// calendar grid — much more glanceable than a horizontal scroll for multi-week
// competitions. Includes summary stats, month navigation for multi-month comps,
// a legend, and the comp's allowed-activity chips so users know which workout
// types feed each day's distance.

struct DailyActivityCalendar: View {
    /// Every accepted competitor — drives both the aggregate cell coloring
    /// (how many hit goal each day) and the per-day breakdown when a cell is tapped.
    let allUsers: [CompetitionUser]
    let competition: Competition
    let accent: Color
    /// When non-nil, the calendar renders that single user's data instead of the
    /// aggregate. Parent owns the binding so leaderboard rows can flip it.
    @Binding var focusedUserId: String?

    @State private var monthOffset: Int = 0
    @State private var selectedDay: Date?

    /// Convenience: the focused user object (if any).
    private var focusedUser: CompetitionUser? {
        guard let id = focusedUserId else { return nil }
        return allUsers.first(where: { $0.user_id == id })
    }

    /// True when the calendar is showing one competitor instead of the whole comp.
    private var isFocused: Bool { focusedUser != nil }

    /// Accent that adapts to the focused user's medal placement — gold/silver/
    /// bronze for ranks 1/2/3, otherwise the comp's default accent. `allUsers`
    /// is already sorted by score descending by both call sites.
    private var effectiveAccent: Color {
        guard let user = focusedUser,
              let rank = allUsers.firstIndex(where: { $0.user_id == user.user_id }) else {
            return accent
        }
        switch rank {
        case 0: return Color(red: 1.0, green: 0.78, blue: 0.0)        // gold
        case 1: return Color(white: 0.82)                              // silver
        case 2: return Color(red: 0.85, green: 0.55, blue: 0.25)       // bronze
        default: return accent
        }
    }

    private let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    private var goal: Double {
        switch competition.type {
        case .streaks, .targets, .race: return competition.options.goal
        default: return 0
        }
    }

    /// Per-day fill ratio in [0, 1]. In aggregate mode this is the share of
    /// competitors who hit goal that day; in focused mode it's just whether the
    /// focused user hit goal — scaled by progress for partial days.
    private func hitRatio(for date: Date) -> Double {
        let k = key(for: date)

        if let user = focusedUser {
            let d = user.intervals?[k] ?? 0
            if goal > 0 { return min(1.0, d / goal) }
            return d > 0 ? 1.0 : 0
        }

        guard !allUsers.isEmpty else { return 0 }
        let hits = allUsers.reduce(0) { count, u in
            let d = u.intervals?[k] ?? 0
            if goal > 0 { return count + (d >= goal ? 1 : 0) }
            return count + (d > 0 ? 1 : 0)
        }
        return Double(hits) / Double(allUsers.count)
    }

    /// Total summed distance — focused user's only when focused, otherwise comp-wide.
    private var aggregateTotalDistance: Double {
        if let user = focusedUser {
            return user.intervals?.values.reduce(0, +) ?? 0
        }
        return allUsers.reduce(0) { sum, u in
            sum + (u.intervals?.values.reduce(0, +) ?? 0)
        }
    }

    /// Days hit — focused user's goal-hit count when focused, otherwise comp-wide
    /// "days where someone was active".
    private var aggregateHitDays: Int {
        if let user = focusedUser {
            let vals: [Double] = user.intervals.map { Array($0.values) } ?? []
            if goal > 0 {
                return vals.filter { $0 >= goal }.count
            }
            return vals.filter { $0 > 0 }.count
        }
        let cal = Calendar.current
        guard let start = competition.startDateFormatted else { return 0 }
        let end = min(competition.endDateFormatted ?? Date(), Date())
        var count = 0
        var day = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: end)
        while day <= last {
            if hitRatio(for: day) > 0 { count += 1 }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    private var startDate: Date {
        competition.startDateFormatted ?? Date()
    }

    private var endDate: Date {
        min(competition.endDateFormatted ?? Date(), Date())
    }

    /// All month starts that overlap the comp's date range. Used to drive the
    /// month navigator — single-month comps show one page, multi-month comps
    /// get prev/next chevrons.
    private var months: [Date] {
        let cal = Calendar.current
        guard let firstMonth = cal.dateInterval(of: .month, for: startDate)?.start,
              let lastMonth = cal.dateInterval(of: .month, for: endDate)?.start else {
            return [startDate]
        }
        var result: [Date] = []
        var current = firstMonth
        while current <= lastMonth {
            result.append(current)
            guard let next = cal.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }
        // Default to the most-recent month so users land on "now" first.
        return result.isEmpty ? [firstMonth] : result
    }

    private var visibleMonth: Date {
        let idx = max(0, min(monthOffset, months.count - 1))
        return months[idx]
    }

    /// Cells for the visible month — padded with nils so the first day lands
    /// on its true weekday column and the trailing row is filled out.
    private var monthCells: [Date?] {
        let cal = Calendar.current
        let monthStart = visibleMonth
        guard let range = cal.range(of: .day, in: .month, for: monthStart) else { return [] }
        let firstWeekday = cal.component(.weekday, from: monthStart) // 1 = Sunday
        var cells: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        for day in range {
            if let date = cal.date(byAdding: .day, value: day - 1, to: monthStart) {
                cells.append(date)
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    /// Bucket key for a calendar cell — must dispatch on the competition's interval
    /// so weekly/monthly competitions map every day in a window to the same key the
    /// backend stored progress under. A pure daily key here would silently return 0
    /// for every cell in a week/month competition. Mirrors the parent view's
    /// `intervalKey(for:)`.
    private func key(for date: Date) -> String {
        switch competition.options.interval ?? .day {
        case .day:
            return isoDateFormatter.string(from: Calendar.current.startOfDay(for: date))
        case .week:
            return competition.weeklyIntervalKey(for: date)
        case .month:
            var comps = Calendar.current.dateComponents([.year, .month], from: date)
            comps.day = 1
            let monthStart = Calendar.current.date(from: comps) ?? date
            return isoDateFormatter.string(from: monthStart)
        }
    }

    private func isInRange(_ date: Date) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let start = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        return day >= start && day <= end
    }

    // MARK: - Streak helpers
    // Backend rule: each missed day decrements `remaining_lives`; once it hits 0
    // the user is eliminated. The backend doesn't expose elimination dates, so
    // we reconstruct per-day status by scanning `intervals` from the comp start.

    private var isStreakComp: Bool { competition.type == .streaks }

    /// Total lives at competition start. Zero for non-streaks comps.
    private var totalLives: Int { isStreakComp ? competition.streakLives : 0 }

    /// Ascending list of dates within [start, today) where the user missed goal.
    /// Today is excluded — backend doesn't decrement mid-day.
    private func missedDates(for user: CompetitionUser) -> [Date] {
        guard isStreakComp, goal > 0 else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var day = cal.startOfDay(for: startDate)
        if day > today { return [] }
        var result: [Date] = []
        while day < today {
            let k = key(for: day)
            let d = user.intervals?[k] ?? 0
            if d < goal { result.append(day) }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Lives the focused user has left now. Trusts `user.remaining_lives` when
    /// present (backend-authoritative); otherwise computes from misses.
    private var focusedLivesRemaining: Int {
        guard let user = focusedUser, isStreakComp else { return 0 }
        if let r = user.remaining_lives { return max(0, r) }
        return max(0, totalLives - missedDates(for: user).count)
    }

    /// True iff the focused user is already out of the competition.
    private var focusedIsEliminated: Bool {
        guard isStreakComp, let user = focusedUser else { return false }
        if let r = user.remaining_lives, r <= 0 { return true }
        return missedDates(for: user).count >= totalLives && totalLives > 0
    }

    enum FocusedDayStatus {
        case completed
        case today                     // today, no completion yet (no miss either)
        case lifeLost(livesLeftAfter: Int)
        case eliminated                // the day this user got eliminated
        case postElimination
    }

    // Shared streak palette — referenced by the focus bar, summary, legend, and
    // calendar cell so visuals stay aligned if colors ever change.
    static let streakHitColor = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let streakLifeLostColor = Color(red: 0.95, green: 0.62, blue: 0.18)
    static let streakEliminatedColor = Color(red: 0.92, green: 0.27, blue: 0.27)

    /// Streak-specific day status for the focused user. Nil when not focused on
    /// a streaks comp, or when the day falls outside the active window — the
    /// cell then renders its standard aggregate look.
    private func streakStatus(for date: Date) -> FocusedDayStatus? {
        guard isStreakComp, let user = focusedUser else { return nil }
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let start = cal.startOfDay(for: startDate)
        let today = cal.startOfDay(for: Date())
        if day < start || day > today { return nil }

        let d = user.intervals?[key(for: day)] ?? 0
        let hit = goal > 0 && d >= goal

        if cal.isDateInToday(day) {
            return hit ? .completed : .today
        }
        if hit { return .completed }

        // Past miss — figure out which miss-number this day is.
        let misses = missedDates(for: user)
        guard let idx = misses.firstIndex(where: { cal.isDate($0, inSameDayAs: day) }) else {
            return nil
        }
        let missNumber = idx + 1
        if totalLives <= 0 {
            return missNumber == 1 ? .eliminated : .postElimination
        }
        if missNumber < totalLives {
            return .lifeLost(livesLeftAfter: totalLives - missNumber)
        }
        if missNumber == totalLives {
            return .eliminated
        }
        return .postElimination
    }

    private var monthName: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: visibleMonth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            focusBar
            summaryHeader

            if months.count > 1 {
                monthNavigator
            } else {
                Text(monthName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            weekdayHeader
            calendarGrid
            legendRow

            if let selected = selectedDay {
                dayDetailPanel(for: selected)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .onAppear {
            // Land on the latest month so users see current activity first.
            monthOffset = max(0, months.count - 1)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    /// Sits at the top of the calendar so users always know what they're viewing,
    /// and how to switch back to the comp-wide view when they're focused on one
    /// player. When focused, the avatar + name leads and a "Show all" pill on the
    /// right is the one-tap escape hatch.
    @ViewBuilder
    private var focusBar: some View {
        if let user = focusedUser {
            HStack(spacing: 10) {
                AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 28)
                    .overlay(
                        Circle()
                            .strokeBorder(effectiveAccent.opacity(0.6), lineWidth: 1.5)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("VIEWING")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                        .foregroundColor(.white.opacity(0.5))
                    HStack(spacing: 6) {
                        Text(user.displayName)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if focusedIsEliminated {
                            Text("OUT")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .tracking(0.8)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(DailyActivityCalendar.streakEliminatedColor))
                        }
                    }
                    if isStreakComp && totalLives > 0 {
                        livesRow(remaining: focusedLivesRemaining)
                    }
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        focusedUserId = nil
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Show all")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(effectiveAccent)
                            .shadow(color: effectiveAccent.opacity(0.4), radius: 6, x: 0, y: 3)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Text("VIEWING ALL PLAYERS")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Text("Tap a player to focus")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }

    /// Heart row showing total lives at comp start, filled = remaining. Used in
    /// the focus bar for streaks comps so the cost of each missed day is always
    /// visible at the top of the calendar.
    private func livesRow(remaining: Int) -> some View {
        let cap = min(totalLives, 6) // Visual cap; "+N" overflow for big counts.
        return HStack(spacing: 3) {
            ForEach(0..<cap, id: \.self) { i in
                Image(systemName: i < remaining ? "heart.fill" : "heart")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(i < remaining ? DailyActivityCalendar.streakEliminatedColor : .white.opacity(0.25))
            }
            if totalLives > 6 {
                Text("+\(totalLives - 6)")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
            Text(focusedIsEliminated ? "Out of lives" : "\(remaining) left")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .padding(.leading, 2)
        }
    }

    private var summaryHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(isFocused ? "1" : "\(allUsers.count)")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(isFocused ? "PLAYER" : "PLAYERS")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.5))
            }

            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(aggregateHitDays)")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(streakStatsLabel)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.5))
            }

            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 28)

            // Third column: for streaks-focused, surface LIVES LEFT instead of
            // total distance — it's the metric players actually care about in
            // a streaks comp ("am I about to get knocked out?").
            if isStreakComp && isFocused && totalLives > 0 {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(focusedLivesRemaining)/\(totalLives)")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(focusedIsEliminated ? DailyActivityCalendar.streakEliminatedColor : .white)
                    Text("LIVES LEFT")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                        .foregroundColor(.white.opacity(0.5))
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(formattedTotalDistance)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(competition.options.unit.shortDisplayName.uppercased()) TOTAL")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.0)
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(competition.workouts, id: \.self) { activity in
                    Image(systemName: activity.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(activity.color)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(activity.backgroundColor))
                }
            }
        }
    }

    private var streakStatsLabel: String {
        if isStreakComp && isFocused { return "STREAK DAYS" }
        if isFocused { return goal > 0 ? "GOALS HIT" : "DAYS ACTIVE" }
        return "ACTIVE DAYS"
    }

    private var formattedTotalDistance: String {
        if aggregateTotalDistance >= 100 {
            return String(format: "%.0f", aggregateTotalDistance)
        }
        return String(format: "%.1f", aggregateTotalDistance)
    }

    private var monthNavigator: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    monthOffset = max(0, monthOffset - 1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(monthOffset > 0 ? 0.7 : 0.2))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .disabled(monthOffset == 0)
            .buttonStyle(.plain)

            Spacer()

            Text(monthName)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    monthOffset = min(months.count - 1, monthOffset + 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(monthOffset < months.count - 1 ? 0.7 : 0.2))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .disabled(monthOffset >= months.count - 1)
            .buttonStyle(.plain)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                Text(weekdayLabels[i])
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                if let date = date {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            if let current = selectedDay,
                               Calendar.current.isDate(current, inSameDayAs: date) {
                                selectedDay = nil
                            } else {
                                selectedDay = date
                            }
                        }
                    } label: {
                        DailyCalendarCell(
                            date: date,
                            hitRatio: hitRatio(for: date),
                            isInRange: isInRange(date),
                            isSelected: selectedDay.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false,
                            accent: effectiveAccent,
                            streakStatus: streakStatus(for: date)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isInRange(date))
                } else {
                    Color.clear
                        .frame(height: 36)
                }
            }
        }
    }

    /// Per-user activity for a specific day. Ranked by distance — hit-goal users
    /// surface to the top, then partial activity, then off-days.
    private func dayDetailPanel(for date: Date) -> some View {
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEEE, MMM d"
            return f
        }()
        let breakdown = allUsers
            .map { (u: CompetitionUser) -> (user: CompetitionUser, distance: Double) in
                let key = self.key(for: date)
                let d = u.intervals?[key] ?? 0
                return (u, d)
            }
            .sorted { $0.distance > $1.distance }
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(effectiveAccent)
                Text(formatter.string(from: date).uppercased())
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.75))

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selectedDay = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 5) {
                ForEach(breakdown, id: \.user.id) { entry in
                    DayDetailRow(
                        user: entry.user,
                        distance: entry.distance,
                        goal: goal,
                        unit: competition.options.unit,
                        accent: effectiveAccent,
                        isCurrentUser: entry.user.user_id == currentUserId
                    )
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var legendRow: some View {
        if isStreakComp && isFocused {
            // Streak-focused legend reads like a key for the life-loss visuals
            // so users instantly grok what each cell color means.
            HStack(spacing: 14) {
                streakLegendItem(color: DailyActivityCalendar.streakHitColor, icon: "checkmark", label: "Hit")
                if totalLives > 0 {
                    streakLegendItem(color: DailyActivityCalendar.streakLifeLostColor, icon: "heart.slash.fill", label: "Life lost")
                }
                streakLegendItem(color: DailyActivityCalendar.streakEliminatedColor, icon: "xmark", label: "Out")
                Spacer()
            }
        } else {
            HStack(spacing: 14) {
                if isFocused {
                    legendItem(state: .hit, label: goal > 0 ? "Goal hit" : "Active")
                    if goal > 0 {
                        legendItem(state: .partial, label: "Partial")
                    }
                    legendItem(state: .off, label: "Off")
                } else {
                    legendItem(state: .hit, label: "All hit")
                    legendItem(state: .partial, label: "Some")
                    legendItem(state: .off, label: "None")
                }
                Spacer()
                Text("Counts \(competition.workouts.map { $0.displayName.lowercased() }.joined(separator: " + "))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
    }

    private enum LegendState { case hit, partial, off }

    private func legendItem(state: LegendState, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(
                    state == .hit ? effectiveAccent :
                    state == .partial ? effectiveAccent.opacity(0.4) :
                    Color.white.opacity(0.08)
                )
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .strokeBorder(state == .off ? Color.white.opacity(0.18) : Color.clear, lineWidth: 1)
                )
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private func streakLegendItem(color: Color, icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                Image(systemName: icon)
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundColor(.white)
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.65))
        }
    }
}

private struct DailyCalendarCell: View {
    let date: Date
    /// 0...1 — fraction of competitors who hit goal (or had activity) on this day.
    let hitRatio: Double
    let isInRange: Bool
    let isSelected: Bool
    let accent: Color
    /// When set (streaks comp + focused user), trumps the aggregate hit-ratio
    /// rendering and shows life-loss / elimination state instead.
    var streakStatus: DailyActivityCalendar.FocusedDayStatus? = nil

    private var hasAnyHits: Bool { hitRatio > 0 }
    private var isAllHit: Bool { hitRatio >= 0.999 }
    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var dayNumber: Int { Calendar.current.component(.day, from: date) }

    /// Floor for visible fills — even 1/5 should be clearly visible.
    private var displayFill: Double {
        hitRatio > 0 ? max(0.3, hitRatio) : 0
    }

    var body: some View {
        if let status = streakStatus {
            streakBody(status)
        } else {
            aggregateBody
        }
    }

    private var aggregateBody: some View {
        ZStack {
            // Base
            Circle()
                .fill(Color.white.opacity(isInRange ? 0.04 : 0.01))

            // Aggregate fill — opacity scales with how many users hit goal
            if hasAnyHits && isInRange {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(displayFill),
                                accent.opacity(displayFill * 0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // Today ring (only when not selected)
            if isToday && !isSelected {
                Circle()
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
            }

            // Selected ring trumps everything for unmistakable focus.
            if isSelected {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .shadow(color: accent.opacity(0.6), radius: 4)
            }

            // Day number
            Text("\(dayNumber)")
                .font(.system(size: 11, weight: isAllHit || isSelected ? .black : .bold, design: .rounded))
                .foregroundColor(
                    !isInRange ? .white.opacity(0.18) :
                    isSelected ? .white :
                    hitRatio >= 0.5 ? .white :
                    hasAnyHits ? .white.opacity(0.9) :
                    .white.opacity(0.55)
                )
        }
        .frame(height: 36)
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Streak rendering
    // Solid green for completed days, orange-with-broken-heart for life-lost,
    // red-with-X for the elimination day, dim grey for post-elimination. The
    // selected ring + today ring still overlay on top so navigation cues stay
    // consistent with the aggregate cell.

    @ViewBuilder
    private func streakBody(_ status: DailyActivityCalendar.FocusedDayStatus) -> some View {
        ZStack {
            // Base + fill per status
            switch status {
            case .completed:
                Circle().fill(DailyActivityCalendar.streakHitColor)
            case .today:
                Circle().fill(Color.white.opacity(0.05))
            case .lifeLost:
                Circle().fill(DailyActivityCalendar.streakLifeLostColor.opacity(0.85))
            case .eliminated:
                Circle().fill(DailyActivityCalendar.streakEliminatedColor.opacity(0.92))
            case .postElimination:
                Circle().fill(Color.white.opacity(0.05))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }

            // Today ring (only when not selected) — also doubles as the "in
            // progress" indicator for `.today` since that case has no solid fill.
            if isToday && !isSelected {
                Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
            }

            // Selected ring trumps everything else.
            if isSelected {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .shadow(color: DailyActivityCalendar.streakHitColor.opacity(0.5), radius: 4)
            }

            // Glyph layer
            switch status {
            case .completed:
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
            case .today:
                Text("\(dayNumber)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            case .lifeLost:
                // Day number sits center, with a small broken-heart corner badge
                // to telegraph "you spent a life here". Keep day number visible
                // so users can still navigate by date.
                Text("\(dayNumber)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Image(systemName: "heart.slash.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(2)
                    .background(Circle().fill(Color.black.opacity(0.35)))
                    .offset(x: 11, y: -11)
            case .eliminated:
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
            case .postElimination:
                Text("\(dayNumber)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.28))
            }
        }
        .frame(height: 36)
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Single row in the per-day breakdown panel. Shows avatar + name + distance,
/// with a "YOU" badge for the current user and a checkmark seal when goal is hit.
private struct DayDetailRow: View {
    let user: CompetitionUser
    let distance: Double
    let goal: Double
    let unit: CompetitionUnit
    let accent: Color
    let isCurrentUser: Bool

    private var hitGoal: Bool { goal > 0 && distance >= goal }
    private var hasActivity: Bool { distance > 0 }

    private var distanceText: String {
        let formatted = distance >= 10
            ? String(format: "%.1f", distance)
            : String(format: "%.2f", distance)
        return "\(formatted) \(unit.shortDisplayName)"
    }

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(user.displayName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(hasActivity ? 1.0 : 0.55))
                        .lineLimit(1)
                    if isCurrentUser {
                        Text("YOU")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(MADTheme.Colors.madRed))
                    }
                }
                Text(hasActivity ? distanceText : "Off day")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(hasActivity ? accent : .white.opacity(0.35))
            }

            Spacer()

            if hitGoal {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14))
                    .foregroundColor(accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isCurrentUser
                        ? MADTheme.Colors.madRed.opacity(0.08)
                        : (hasActivity ? Color.white.opacity(0.04) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            hitGoal ? accent.opacity(0.4) : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                )
        )
    }
}
