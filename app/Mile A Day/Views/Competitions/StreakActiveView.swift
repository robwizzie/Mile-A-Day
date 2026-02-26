import SwiftUI

// MARK: - Streak Active View
// The main active view for Streak competitions
// Merges progress + leaderboard into a single unified view
// Supports flex/nudge social actions and streak calendar

struct StreakActiveView: View {
    let competition: Competition
    let selectedIntervalDate: Date
    @ObservedObject var competitionService: CompetitionService
    @State private var heartsAnimated = false
    @State private var showNudgeConfirm = false
    @State private var nudgeTargetUser: CompetitionUser?
    @State private var showFlexConfirm = false
    @State private var hasSentFlex = false
    @State private var isSendingAction = false
    @State private var actionFeedback: ActionFeedback?
    @State private var expandedUserId: String?
    @State private var progressAnimated = false
    @State private var showCompletionBurst = false
    @State private var showEliminatedUsers = false

    private let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")

    // MARK: - Streak gradient colors (centralized)
    private let streakOrange = Color(hex: "FF6B6B")
    private let streakYellow = Color(hex: "FF8E53")

    private var streakGradient: LinearGradient {
        LinearGradient(colors: [streakOrange, streakYellow], startPoint: .leading, endPoint: .trailing)
    }

    private var acceptedUsers: [CompetitionUser] {
        competition.users.filter { $0.invite_status == .accepted }
    }

    private var activeUsers: [CompetitionUser] {
        acceptedUsers.filter { !userIsEliminated($0) }
    }

    private var eliminatedUsers: [CompetitionUser] {
        acceptedUsers.filter { userIsEliminated($0) }
    }

    private var goal: Double { competition.options.goal }
    private var firstTo: Int { competition.options.first_to }
    private let maxVisibleHearts = 6

    private var intervalKey: String {
        let calendar = Calendar.current
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let interval = competition.options.interval ?? .day

        switch interval {
        case .day:
            return formatter.string(from: calendar.startOfDay(for: selectedIntervalDate))
        case .week:
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedIntervalDate)
            components.weekday = calendar.firstWeekday
            let startOfWeek = calendar.date(from: components) ?? selectedIntervalDate
            return formatter.string(from: startOfWeek)
        case .month:
            var components = calendar.dateComponents([.year, .month], from: selectedIntervalDate)
            components.day = 1
            let startOfMonth = calendar.date(from: components) ?? selectedIntervalDate
            return formatter.string(from: startOfMonth)
        }
    }

    var body: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            // Streak Hero Banner
            streakHeroBanner

            // Streak Calendar Strip
            streakCalendarStrip

            // Flex button (only if completed today and not already flexed)
            if canFlex {
                flexButton
            }

            // Unified Leaderboard (merges progress + standings)
            unifiedLeaderboard

            // Collapsed eliminated section
            if !eliminatedUsers.isEmpty {
                eliminatedSection
            }
        }
        .confirmationDialog("Flex on everyone?", isPresented: $showFlexConfirm, titleVisibility: .visible) {
            Button("Send Flex") {
                sendFlex()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will send a notification to all competitors that you've completed your goal today. You can flex once per day.")
        }
        .confirmationDialog("Send a nudge?", isPresented: $showNudgeConfirm, titleVisibility: .visible) {
            Button("Send Nudge") {
                if let user = nudgeTargetUser {
                    sendNudge(to: user)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let user = nudgeTargetUser {
                Text("Send \(user.displayName) a friendly reminder to get their run in today. You can nudge each person once per day.")
            }
        }
        .overlay(alignment: .top) {
            if let feedback = actionFeedback {
                actionFeedbackBanner(feedback)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    progressAnimated = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation { heartsAnimated = true }
            }
        }
        .onChange(of: selectedIntervalDate) { _ in
            // Reset and re-animate progress bars when day changes
            progressAnimated = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    progressAnimated = true
                }
            }
        }
    }

    // MARK: - Streak Hero Banner
    private var streakHeroBanner: some View {
        let currentUser = acceptedUsers.first(where: { $0.user_id == currentUserId })
        let streak = Int(currentUser?.score ?? 0)
        let distance = currentUser?.intervals?[intervalKey] ?? 0
        let completed = distance >= goal
        let isToday = Calendar.current.isDateInToday(selectedIntervalDate)
        let remaining = max(0, goal - distance)
        let isMilestone = [7, 14, 30, 50, 100, 365].contains(streak)

        return ZStack {
            // Completion burst effect
            if showCompletionBurst && completed && isToday {
                BurstEffect(colors: [.green, streakOrange, streakYellow, .white], particleCount: 20)
                    .frame(width: 200, height: 200)
                    .allowsHitTesting(false)
            }

            VStack(spacing: MADTheme.Spacing.md) {
                // Flame + Streak Count
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(streakGradient)
                        .pulseGlow(color: streakOrange, maxScale: 1.06)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(streak)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .contentTransition(.numericText())

                            if isMilestone {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.yellow)
                                    .shadow(color: .yellow.opacity(0.5), radius: 4)
                            }
                        }
                        Text("day streak")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                // Today's status chip
                if isToday {
                    Group {
                        if completed {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                Text("Goal complete! \(String(format: "%.1f", distance)) \(competition.options.unit.shortDisplayName)")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.15))
                                    .overlay(Capsule().stroke(Color.green.opacity(0.3), lineWidth: 1))
                            )
                            .transition(.scale.combined(with: .opacity))
                            .onAppear {
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                                withAnimation(.spring(response: 0.4)) {
                                    showCompletionBurst = true
                                }
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "figure.run")
                                    .font(.system(size: 14))
                                Text("\(String(format: "%.1f", remaining)) \(competition.options.unit.shortDisplayName) to go")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                                    .overlay(Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 1))
                            )
                        }
                    }
                }

                // Lives display (capped)
                if firstTo > 0, let currentUser = currentUser {
                    let lives = currentUser.remaining_lives ?? firstTo
                    let displayCount = min(firstTo, maxVisibleHearts)

                    HStack(spacing: 6) {
                        ForEach(0..<displayCount, id: \.self) { i in
                            let alive = i < lives
                            Image(systemName: alive ? "heart.fill" : "heart")
                                .font(.system(size: 16))
                                .foregroundColor(alive ? .red : .white.opacity(0.15))
                                .shadow(color: alive ? .red.opacity(0.4) : .clear, radius: 4)
                                .scaleEffect(heartsAnimated ? 1.0 : 0.3)
                                .animation(
                                    .spring(response: 0.4, dampingFraction: 0.5)
                                    .delay(Double(i) * 0.08),
                                    value: heartsAnimated
                                )
                        }
                        if firstTo > maxVisibleHearts {
                            Text("+\(firstTo - maxVisibleHearts)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.lg)
        .padding(.horizontal, MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(
                            LinearGradient(
                                colors: [streakOrange.opacity(0.4), streakYellow.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Streak Calendar Strip
    private var streakCalendarStrip: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate = competition.startDateFormatted ?? calendar.date(byAdding: .day, value: -13, to: today) ?? today
        let dayCount = max(1, calendar.dateComponents([.day], from: startDate, to: today).day ?? 0) + 1
        // Show last 14 days max for the strip
        let visibleDays = min(dayCount, 14)

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack {
                Text("Streak History")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(0..<visibleDays, id: \.self) { offset in
                            let dayDate = calendar.date(byAdding: .day, value: -(visibleDays - 1 - offset), to: today) ?? today
                            let isSelected = calendar.isDate(dayDate, inSameDayAs: selectedIntervalDate)

                            streakDayDot(date: dayDate, isSelected: isSelected)
                                .id(offset)
                        }
                    }
                    .padding(.horizontal, MADTheme.Spacing.sm)
                }
                .onAppear {
                    proxy.scrollTo(visibleDays - 1, anchor: .trailing)
                }
            }
        }
    }

    private func streakDayDot(date: Date, isSelected: Bool) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > Date()
        let currentUser = acceptedUsers.first(where: { $0.user_id == currentUserId })

        // Calculate interval key for this specific date
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dayKey = formatter.string(from: calendar.startOfDay(for: date))
        let distance = currentUser?.intervals?[dayKey] ?? 0
        let completed = distance >= goal

        let dotColor: Color = {
            if isFuture { return .white.opacity(0.08) }
            if isToday && !completed { return .orange }
            if completed { return .green }
            return .red.opacity(0.5)
        }()

        let dayName = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        let dayNum = calendar.component(.day, from: date)

        return VStack(spacing: 4) {
            Text(dayName.prefix(1))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.35))

            ZStack {
                Circle()
                    .fill(isSelected ? dotColor : dotColor.opacity(0.6))
                    .frame(width: 28, height: 28)

                if completed && !isFuture {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(dayNum)")
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundColor(isFuture ? .white.opacity(0.15) : .white)
                }
            }

            if isToday {
                Circle()
                    .fill(.white)
                    .frame(width: 4, height: 4)
            } else {
                Spacer().frame(height: 4)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? streakOrange.opacity(0.6) : Color.clear, lineWidth: 2)
                .padding(-3)
        )
    }

    // MARK: - Unified Leaderboard
    private var unifiedLeaderboard: some View {
        let isToday = Calendar.current.isDateInToday(selectedIntervalDate)

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14))
                    .foregroundColor(streakOrange)
                Text(isToday ? "Standings" : "Day Results")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.white)

                Spacer()

                Text("\(activeUsers.count) competing")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: 2) {
                ForEach(Array(rankedActiveUsers.enumerated()), id: \.element.id) { index, user in
                    let rank = index + 1
                    unifiedRow(user: user, rank: rank)
                }
            }
            .padding(.vertical, MADTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }

    private var rankedActiveUsers: [CompetitionUser] {
        activeUsers.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
    }

    private func unifiedRow(user: CompetitionUser, rank: Int) -> some View {
        let isCurrentUser = user.user_id == currentUserId
        let isExpanded = expandedUserId == user.user_id
        let streak = Int(user.score ?? 0)
        let distance = user.intervals?[intervalKey] ?? 0
        let progress = min(distance / max(goal, 0.01), 1.0)
        let completed = distance >= goal
        let isToday = Calendar.current.isDateInToday(selectedIntervalDate)
        let lives = user.remaining_lives ?? firstTo

        return VStack(spacing: 0) {
            // Main row
            Button {
                if !isCurrentUser {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        expandedUserId = isExpanded ? nil : user.user_id
                    }
                }
            } label: {
                VStack(spacing: 8) {
                    HStack(spacing: MADTheme.Spacing.sm) {
                        // Rank badge
                        rankBadge(rank: rank)

                        // Avatar with status ring
                        ZStack(alignment: .bottomTrailing) {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text(user.displayName.prefix(1).uppercased())
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(
                                            rank == 1
                                                ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                : AnyShapeStyle(Color.white.opacity(0.12)),
                                            lineWidth: rank <= 3 ? 2 : 1
                                        )
                                )

                            // Completion indicator
                            if !isCurrentUser {
                                Image(systemName: completed ? "checkmark" : (isToday ? "ellipsis" : "xmark"))
                                    .font(.system(size: 5, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 12, height: 12)
                                    .background(
                                        Circle()
                                            .fill(completed ? Color.green : (isToday ? Color.orange : Color.red))
                                    )
                                    .overlay(Circle().stroke(Color(white: 0.1), lineWidth: 1))
                            }
                        }

                        // Name + mini lives
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(user.displayName)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                if isCurrentUser {
                                    Text("YOU")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(MADTheme.Colors.madRed))
                                }
                            }

                            // Mini lives row
                            if firstTo > 0 {
                                let displayHearts = min(firstTo, maxVisibleHearts)
                                HStack(spacing: 2) {
                                    ForEach(0..<displayHearts, id: \.self) { i in
                                        Circle()
                                            .fill(i < lives ? Color.red : Color.white.opacity(0.1))
                                            .frame(width: 5, height: 5)
                                    }
                                    if firstTo > maxVisibleHearts {
                                        Text("+\(firstTo - maxVisibleHearts)")
                                            .font(.system(size: 6, weight: .medium))
                                            .foregroundColor(.white.opacity(0.2))
                                    }
                                }
                            }
                        }

                        Spacer()

                        // Distance + streak
                        VStack(alignment: .trailing, spacing: 2) {
                            // Streak count
                            HStack(spacing: 3) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                                    .shadow(color: .orange.opacity(0.3), radius: 2)
                                Text("\(streak)")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }

                            // Today's distance
                            if completed {
                                HStack(spacing: 2) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .bold))
                                    Text(String(format: "%.1f %@", distance, competition.options.unit.shortDisplayName))
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(.green)
                            } else if isToday {
                                Text(String(format: "%.1f/%@ %@", distance, competition.options.goalFormatted, competition.options.unit.shortDisplayName))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.4))
                            } else {
                                Text("Missed")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(.red.opacity(0.5))
                            }
                        }

                        // Expand chevron (only for non-self)
                        if !isCurrentUser {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.25))
                                .frame(width: 16)
                        }
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 3)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    completed ?
                                        LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .leading, endPoint: .trailing) :
                                        streakGradient
                                )
                                .frame(width: geo.size.width * (progressAnimated ? progress : 0), height: 3)
                                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(rank) * 0.05), value: progressAnimated)
                        }
                    }
                    .frame(height: 3)
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.vertical, MADTheme.Spacing.sm)
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded actions
            if isExpanded && !isCurrentUser {
                expandedActions(for: user)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                        removal: .opacity
                    ))
            }

            // Separator
            if rank < rankedActiveUsers.count {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 1)
                    .padding(.horizontal, MADTheme.Spacing.md)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                .fill(isCurrentUser ? Color.white.opacity(0.05) : Color.clear)
        )
    }

    // MARK: - Eliminated Section (collapsed)
    private var eliminatedSection: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.3)) {
                    showEliminatedUsers.toggle()
                }
            } label: {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .font(.system(size: 13))
                        .foregroundColor(.red.opacity(0.5))
                    Text("\(eliminatedUsers.count) eliminated")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))

                    Spacer()

                    Image(systemName: showEliminatedUsers ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.25))
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.vertical, MADTheme.Spacing.sm)
            }
            .buttonStyle(PlainButtonStyle())

            if showEliminatedUsers {
                VStack(spacing: 4) {
                    ForEach(eliminatedUsers.sorted(by: { ($0.score ?? 0) > ($1.score ?? 0) }), id: \.id) { user in
                        eliminatedRow(user: user)
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(Color.red.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func eliminatedRow(user: CompetitionUser) -> some View {
        let isCurrentUser = user.user_id == currentUserId
        let streak = Int(user.score ?? 0)

        return HStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.red.opacity(0.3))
                .frame(width: 24)

            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(user.displayName.prefix(1).uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.3))
                )

            Text(user.displayName)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.3))
                .strikethrough(true, color: .red.opacity(0.3))

            if isCurrentUser {
                Text("YOU")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }

            Spacer()

            HStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.gray.opacity(0.3))
                Text("\(streak)d")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .padding(.vertical, 4)
        .opacity(0.6)
    }

    // MARK: - Rank Badge
    private func rankBadge(rank: Int) -> some View {
        Group {
            if rank <= 3 {
                let colors: [Color] = rank == 1 ? [.yellow, .orange] :
                    rank == 2 ? [Color(white: 0.85), Color(white: 0.6)] :
                    [Color(red: 0.8, green: 0.5, blue: 0.2), Color(red: 0.6, green: 0.35, blue: 0.15)]

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: colors.map { $0.opacity(0.2) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 26, height: 26)
                    Text("\(rank)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                        )
                }
            } else {
                Text("\(rank)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 26, height: 26)
            }
        }
    }

    // MARK: - Expanded Actions (Nudge)
    private func expandedActions(for user: CompetitionUser) -> some View {
        let distance = user.intervals?[intervalKey] ?? 0
        let completed = distance >= goal
        let isToday = Calendar.current.isDateInToday(selectedIntervalDate)

        return VStack(spacing: MADTheme.Spacing.sm) {
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 1)
                .padding(.horizontal, MADTheme.Spacing.md)

            HStack(spacing: MADTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    if isToday {
                        Text(completed ? "Completed today" : "Still running...")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(completed ? .green : .orange)
                        Text(String(format: "%.1f/%@ %@", distance, competition.options.goalFormatted, competition.options.unit.shortDisplayName))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                    } else {
                        Text(completed ? "Completed" : "Missed")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(completed ? .green : .red.opacity(0.7))
                    }
                }

                Spacer()

                // Nudge button (only if incomplete today)
                if isToday && !completed {
                    Button {
                        nudgeTargetUser = user
                        showNudgeConfirm = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bell.badge")
                                .font(.system(size: 12))
                            Text("Nudge")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.12))
                                .overlay(Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 1))
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.bottom, MADTheme.Spacing.sm)
        }
    }

    // MARK: - Flex Button
    private var canFlex: Bool {
        guard !hasSentFlex,
              Calendar.current.isDateInToday(selectedIntervalDate),
              let currentUser = acceptedUsers.first(where: { $0.user_id == currentUserId }) else {
            return false
        }
        let distance = currentUser.intervals?[intervalKey] ?? 0
        return distance >= goal && !userIsEliminated(currentUser)
    }

    private var flexButton: some View {
        Button {
            showFlexConfirm = true
        } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(streakGradient)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Flex on everyone")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Let them know you finished today")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .stroke(
                                LinearGradient(
                                    colors: [streakOrange.opacity(0.3), streakYellow.opacity(0.15)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .shimmer()
    }

    // MARK: - Action Feedback Banner
    private func actionFeedbackBanner(_ feedback: ActionFeedback) -> some View {
        HStack(spacing: 8) {
            Image(systemName: feedback.icon)
                .font(.system(size: 14))
            Text(feedback.message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
        .foregroundColor(feedback.isError ? .red : .green)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(feedback.isError ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(feedback.isError ? Color.red.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.top, 8)
    }

    // MARK: - Actions
    private func sendFlex() {
        isSendingAction = true
        Task {
            do {
                try await competitionService.sendFlex(competitionId: competition.competition_id)
                await MainActor.run {
                    isSendingAction = false
                    hasSentFlex = true
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    showFeedback(ActionFeedback(icon: "hand.raised.fill", message: "Flex sent!", isError: false))
                }
            } catch {
                await MainActor.run {
                    isSendingAction = false
                    let message = (error as? CompetitionServiceError)?.errorDescription ?? "Could not send flex"
                    showFeedback(ActionFeedback(icon: "xmark.circle", message: message, isError: true))
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
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    showFeedback(ActionFeedback(icon: "bell.badge.fill", message: "Nudge sent to \(user.displayName)!", isError: false))
                }
            } catch {
                await MainActor.run {
                    isSendingAction = false
                    let message = (error as? CompetitionServiceError)?.errorDescription ?? "Could not send nudge"
                    showFeedback(ActionFeedback(icon: "xmark.circle", message: message, isError: true))
                }
            }
        }
    }

    private func showFeedback(_ feedback: ActionFeedback) {
        withAnimation(.spring(response: 0.3)) {
            actionFeedback = feedback
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { actionFeedback = nil }
        }
    }

    // MARK: - Helpers
    private func userIsEliminated(_ user: CompetitionUser) -> Bool {
        guard firstTo > 0 else { return false }
        if let lives = user.remaining_lives {
            return lives <= 0
        }
        return false
    }
}

// MARK: - Supporting Types

struct ActionFeedback: Equatable {
    let icon: String
    let message: String
    let isError: Bool
}
