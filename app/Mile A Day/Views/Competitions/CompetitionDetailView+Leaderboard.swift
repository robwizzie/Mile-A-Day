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

                    // Ranked rows
                    VStack(spacing: MADTheme.Spacing.sm) {
                        ForEach(Array(rankedUsers.enumerated()), id: \.element.id) { index, user in
                            let isMe = user.user_id == currentUserId

                            CompetitionLeaderboardRow(
                                rank: index + 1,
                                user: user,
                                competitionType: competition.type,
                                unit: competition.options.unit,
                                isCurrentUser: isMe,
                                totalLives: competition.type == .streaks ? competition.streakLives : 0
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

    // MARK: - Streak Month View
    var streakCalendarStrip: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let acceptedUsers = competition.users.filter { $0.invite_status == .accepted }
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        let currentUser = acceptedUsers.first(where: { $0.user_id == currentUserId })
        let goal = competition.options.goal
        // Parse start_date as a local calendar date (not UTC) to avoid timezone shift
        let compStart: Date = {
            guard let dateStr = competition.start_date else { return today }
            let parts = dateStr.prefix(10).split(separator: "-")
            guard parts.count == 3,
                  let year = Int(parts[0]),
                  let month = Int(parts[1]),
                  let day = Int(parts[2]) else { return today }
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = day
            return calendar.date(from: comps) ?? today
        }()

        let monthStart: Date = {
            var comps = calendar.dateComponents([.year, .month], from: streakCalendarMonth)
            comps.day = 1
            return calendar.date(from: comps) ?? today
        }()

        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        let formatter: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withFullDate]
            return f
        }()

        let monthName = monthStart.formatted(.dateTime.month(.wide).year())
        let weekdaySymbols = calendar.veryShortWeekdaySymbols
        let reorderedWeekdays: [String] = {
            let start = calendar.firstWeekday - 1
            return Array(weekdaySymbols[start...]) + Array(weekdaySymbols[..<start])
        }()

        // Can navigate back if comp started before this month
        let compStartMonth: Date = {
            var comps = calendar.dateComponents([.year, .month], from: compStart)
            comps.day = 1
            return calendar.date(from: comps) ?? compStart
        }()
        let canGoBack = monthStart > compStartMonth

        // Can navigate forward only if not already showing the current month
        let todayMonth: Date = {
            var comps = calendar.dateComponents([.year, .month], from: today)
            comps.day = 1
            return calendar.date(from: comps) ?? today
        }()
        let canGoForward = monthStart < todayMonth

        return VStack(spacing: MADTheme.Spacing.md) {
            // Month header with navigation arrows
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        streakCalendarMonth = calendar.date(byAdding: .month, value: -1, to: streakCalendarMonth) ?? streakCalendarMonth
                        selectedStreakDay = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(canGoBack ? .white.opacity(0.6) : .white.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)

                Spacer()

                Text(monthName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        streakCalendarMonth = calendar.date(byAdding: .month, value: 1, to: streakCalendarMonth) ?? streakCalendarMonth
                        selectedStreakDay = nil
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(canGoForward ? .white.opacity(0.6) : .white.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canGoForward)
            }

            // Weekday headers + day grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(reorderedWeekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.3))
                        .frame(height: 16)
                }

                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 32)
                }

                ForEach(1...daysInMonth, id: \.self) { day in
                    let date: Date = {
                        var comps = calendar.dateComponents([.year, .month], from: monthStart)
                        comps.day = day
                        return calendar.date(from: comps) ?? today
                    }()
                    let isTodayDate = calendar.isDateInToday(date)
                    let isFuture = date > today
                    let isBeforeComp = date < compStart
                    let isInCompRange = !isBeforeComp && !isFuture
                    let dayKey = formatter.string(from: calendar.startOfDay(for: date))
                    let distance = currentUser?.intervals?[dayKey] ?? 0
                    let completed = distance >= goal
                    let missed = isInCompRange && !isTodayDate && !completed
                    let isSelected = selectedStreakDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false

                    Button {
                        if isInCompRange || isTodayDate {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if isSelected {
                                    selectedStreakDay = nil
                                } else {
                                    selectedStreakDay = date
                                }
                            }
                        }
                    } label: {
                        ZStack {
                            if isBeforeComp || isFuture {
                                Text("\(day)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.1))
                            } else if completed {
                                Circle()
                                    .fill(Color.green.opacity(isSelected ? 0.9 : 0.65))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                            } else if isTodayDate {
                                Circle()
                                    .fill(Color.orange.opacity(isSelected ? 0.9 : 0.7))
                                    .frame(width: 28, height: 28)
                                Text("\(day)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            } else if missed {
                                Circle()
                                    .fill(Color.red.opacity(isSelected ? 0.4 : 0.25))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.red.opacity(0.7))
                            } else {
                                Text("\(day)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        .frame(height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.white.opacity(0.4) : (isTodayDate ? Color.orange.opacity(0.5) : .clear), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isBeforeComp || isFuture)
                }
            }

            // Day detail panel
            if let selected = selectedStreakDay {
                streakDayDetail(date: selected, users: acceptedUsers, goal: goal, formatter: formatter)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Legend
            HStack(spacing: MADTheme.Spacing.lg) {
                legendItem(color: .green, label: "Completed")
                legendItem(color: .orange, label: "Today")
                legendItem(color: .red, label: "Missed")
            }
            .padding(.top, MADTheme.Spacing.xs)
        }
        .padding(MADTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Day Detail Panel
    func streakDayDetail(date: Date, users: [CompetitionUser], goal: Double, formatter: ISO8601DateFormatter) -> some View {
        let calendar = Calendar.current
        let dayKey = formatter.string(from: calendar.startOfDay(for: date))
        let isTodayDate = calendar.isDateInToday(date)
        let dateLabel = isTodayDate ? "Today" : date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())

        return VStack(spacing: MADTheme.Spacing.sm) {
            // Date header
            HStack {
                Text(dateLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("Goal: \(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
            }

            // Each user's status for this day
            ForEach(users, id: \.id) { user in
                let distance = user.intervals?[dayKey] ?? 0
                let completed = distance >= goal

                HStack(spacing: MADTheme.Spacing.sm) {
                    AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 26)
                        .overlay(
                            Circle().stroke(completed ? Color.green.opacity(0.6) : Color.red.opacity(0.3), lineWidth: 1.5)
                        )

                    Text(user.displayName)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)

                    Spacer()

                    if completed {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            Text("\(String(format: "%.1f", distance)) \(competition.options.unit.shortDisplayName)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.green)
                        }
                    } else if isTodayDate && distance > 0 {
                        Text("\(String(format: "%.1f", distance))/\(competition.options.goalFormatted)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.orange)
                    } else if isTodayDate {
                        Text("Not yet")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.3))
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.red.opacity(0.6))
                            if distance > 0 {
                                Text("\(String(format: "%.1f", distance)) \(competition.options.unit.shortDisplayName)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.red.opacity(0.6))
                            } else {
                                Text("Missed")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.red.opacity(0.5))
                            }
                        }
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    func legendItem(color: Color, icon: String? = nil, label: String) -> some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundColor(color.opacity(0.7))
            } else {
                Circle()
                    .fill(color.opacity(0.65))
                    .frame(width: 8, height: 8)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
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

                            AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 36)

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
