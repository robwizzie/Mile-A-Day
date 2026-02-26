import SwiftUI

// MARK: - Streak Active View
// The main active view for Streak competitions - replaces the old streaksIntervalView
// Designed to be engaging, interactive, and scale from 2 to unlimited participants

struct StreakActiveView: View {
    let competition: Competition
    let selectedIntervalDate: Date
    @ObservedObject var competitionService: CompetitionService
    @State private var heartsAnimated = false
    @State private var flameAnimated = false
    @State private var showNudgeConfirm = false
    @State private var nudgeTargetUser: CompetitionUser?
    @State private var showFlexConfirm = false
    @State private var isSendingAction = false
    @State private var actionFeedback: ActionFeedback?
    @State private var expandedUserId: String?

    private let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")

    private var acceptedUsers: [CompetitionUser] {
        competition.users.filter { $0.invite_status == .accepted }
    }

    private var goal: Double { competition.options.goal }
    private var firstTo: Int { competition.options.first_to }

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
            // Streak Hero Banner - shows current user's streak prominently
            streakHeroBanner

            // Today's Progress Section
            todaysProgressSection

            // Flex button for current user (only if they completed today)
            if canFlex {
                flexButton
            }

            // All Participants List
            participantsSection
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
    }

    // MARK: - Streak Hero Banner
    private var streakHeroBanner: some View {
        let currentUser = acceptedUsers.first(where: { $0.user_id == currentUserId })
        let streak = Int(currentUser?.score ?? 0)
        let distance = currentUser?.intervals?[intervalKey] ?? 0
        let completed = distance >= goal
        let isToday = Calendar.current.isDateInToday(selectedIntervalDate)
        let remaining = goal - distance

        return VStack(spacing: MADTheme.Spacing.md) {
            // Flame + Streak Count
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "FF6B6B"), Color(hex: "FF8E53")],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .shadow(color: Color(hex: "FF6B6B").opacity(0.6), radius: flameAnimated ? 12 : 4)
                    .scaleEffect(flameAnimated ? 1.08 : 1.0)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(streak)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("day streak")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            // Today's status chip
            if isToday {
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
                            .overlay(
                                Capsule()
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
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
                            .overlay(
                                Capsule()
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }

            // Lives display
            if firstTo > 0, let currentUser = currentUser {
                let lives = currentUser.remaining_lives ?? firstTo

                HStack(spacing: 6) {
                    ForEach(0..<firstTo, id: \.self) { i in
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
                                colors: [Color(hex: "FF6B6B").opacity(0.4), Color(hex: "FF8E53").opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation { heartsAnimated = true }
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                flameAnimated = true
            }
        }
    }

    // MARK: - Today's Progress Section
    private var todaysProgressSection: some View {
        let isToday = Calendar.current.isDateInToday(selectedIntervalDate)

        return VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack {
                Text(isToday ? "Today's Progress" : "Day Progress")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.white)

                Spacer()

                if firstTo > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                        Text("\(firstTo) \(firstTo == 1 ? "life" : "lives") each")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            // Progress bars for all users - compact view
            VStack(spacing: 10) {
                ForEach(sortedUsersForProgress, id: \.id) { user in
                    streakProgressRow(user: user)
                }
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(
                                LinearGradient(
                                    colors: [Color(hex: "FF6B6B").opacity(0.25), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
    }

    private var sortedUsersForProgress: [CompetitionUser] {
        acceptedUsers.sorted { a, b in
            let aDistance = a.intervals?[intervalKey] ?? 0
            let bDistance = b.intervals?[intervalKey] ?? 0
            // Current user first, then by distance descending
            if a.user_id == currentUserId { return true }
            if b.user_id == currentUserId { return false }
            return aDistance > bDistance
        }
    }

    private func streakProgressRow(user: CompetitionUser) -> some View {
        let distance = user.intervals?[intervalKey] ?? 0
        let progress = min(distance / max(goal, 0.01), 1.0)
        let completed = distance >= goal
        let isToday = Calendar.current.isDateInToday(selectedIntervalDate)
        let isCurrentUser = user.user_id == currentUserId
        let isEliminated = userIsEliminated(user)

        return VStack(spacing: 6) {
            HStack(spacing: MADTheme.Spacing.sm) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(isEliminated ? 0.04 : 0.1))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(user.displayName.prefix(1).uppercased())
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(isEliminated ? 0.3 : 1.0))
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    completed ? Color.green.opacity(0.8) :
                                        (isEliminated ? Color.red.opacity(0.3) :
                                            (isToday ? Color.orange.opacity(0.5) : Color.red.opacity(0.5))),
                                    lineWidth: 2
                                )
                        )

                    // Status badge
                    if !isEliminated {
                        Image(systemName: completed ? "checkmark" : (isToday ? "ellipsis" : "xmark"))
                            .font(.system(size: 6, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 14, height: 14)
                            .background(
                                Circle()
                                    .fill(completed ? Color.green : (isToday ? Color.orange : Color.red))
                            )
                            .offset(x: 12, y: 12)
                    }
                }

                // Name + streak
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(user.displayName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(isEliminated ? 0.35 : 1.0))
                            .strikethrough(isEliminated, color: .red.opacity(0.4))

                        if isCurrentUser {
                            Text("YOU")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(MADTheme.Colors.madRed))
                        }

                        if isEliminated {
                            Text("OUT")
                                .font(.system(size: 7, weight: .heavy, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.red.opacity(0.4)))
                        }
                    }
                }

                Spacer()

                // Distance
                if !isEliminated {
                    if completed {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                            Text(String(format: "%.1f %@", distance, competition.options.unit.shortDisplayName))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.green)
                    } else if isToday {
                        Text(String(format: "%.1f/%@ %@", distance, competition.options.goalFormatted, competition.options.unit.shortDisplayName))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    } else {
                        Text("Missed")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.red.opacity(0.6))
                    }
                }

                // Streak flame
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11))
                        .foregroundColor(isEliminated ? .gray.opacity(0.3) : .orange)
                    Text("\(Int(user.score ?? 0))")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(isEliminated ? 0.3 : 1.0))
                }
            }

            // Progress bar
            if !isEliminated {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                completed ?
                                    LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .leading, endPoint: .trailing) :
                                    LinearGradient(
                                        colors: [Color(hex: "FF6B6B"), Color(hex: "FF8E53")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                            )
                            .frame(width: geo.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, MADTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                .fill(isCurrentUser ? Color.white.opacity(0.05) : Color.clear)
        )
        .opacity(isEliminated ? 0.5 : 1.0)
    }

    // MARK: - Participants Section (Expandable Cards)
    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "FF6B6B"))
                Text("Challengers")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.white)

                Spacer()

                Text("\(acceptedUsers.filter { !userIsEliminated($0) }.count) active")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: MADTheme.Spacing.sm) {
                ForEach(sortedUsersForLeaderboard, id: \.id) { user in
                    participantCard(user: user, rank: rankFor(user))
                }
            }
        }
    }

    private var sortedUsersForLeaderboard: [CompetitionUser] {
        acceptedUsers.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
    }

    private func rankFor(_ user: CompetitionUser) -> Int {
        let sorted = sortedUsersForLeaderboard
        guard let index = sorted.firstIndex(where: { $0.id == user.id }) else { return 0 }
        return index + 1
    }

    private func participantCard(user: CompetitionUser, rank: Int) -> some View {
        let isCurrentUser = user.user_id == currentUserId
        let isEliminated = userIsEliminated(user)
        let isExpanded = expandedUserId == user.user_id
        let streak = Int(user.score ?? 0)
        let lives = user.remaining_lives ?? firstTo

        return VStack(spacing: 0) {
            // Main row - always visible
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    expandedUserId = isExpanded ? nil : user.user_id
                }
            } label: {
                HStack(spacing: MADTheme.Spacing.md) {
                    // Rank badge
                    rankBadge(rank: rank, isEliminated: isEliminated)

                    // Avatar
                    Circle()
                        .fill(Color.white.opacity(isEliminated ? 0.04 : 0.1))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(user.displayName.prefix(1).uppercased())
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(isEliminated ? 0.3 : 1.0))
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    isEliminated
                                        ? AnyShapeStyle(Color.red.opacity(0.2))
                                        : (rank == 1
                                            ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            : AnyShapeStyle(Color.white.opacity(0.15))),
                                    lineWidth: rank <= 3 ? 2 : 1
                                )
                        )

                    // Name + lives
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(user.displayName)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(isEliminated ? 0.35 : 1.0))

                            if isCurrentUser {
                                Text("YOU")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(MADTheme.Colors.madRed))
                            }

                            if isEliminated {
                                Text("ELIMINATED")
                                    .font(.system(size: 7, weight: .heavy))
                                    .foregroundColor(.red.opacity(0.7))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.red.opacity(0.15)))
                            }
                        }

                        // Mini lives
                        if firstTo > 0 && !isEliminated {
                            HStack(spacing: 3) {
                                ForEach(0..<min(firstTo, 8), id: \.self) { i in
                                    Image(systemName: i < lives ? "heart.fill" : "heart")
                                        .font(.system(size: 7))
                                        .foregroundColor(i < lives ? .red : .white.opacity(0.12))
                                }
                                if firstTo > 8 {
                                    Text("+\(firstTo - 8)")
                                        .font(.system(size: 7, weight: .medium))
                                        .foregroundColor(.white.opacity(0.25))
                                }
                            }
                        }
                    }

                    Spacer()

                    // Streak count
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 14))
                                .foregroundColor(isEliminated ? .gray.opacity(0.2) : .orange)
                                .shadow(color: isEliminated ? .clear : .orange.opacity(0.3), radius: 3)
                            Text("\(streak)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(isEliminated ? 0.25 : 1.0))
                        }
                        Text("day\(streak == 1 ? "" : "s")")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(isEliminated ? 0.15 : 0.35))
                    }

                    // Expand indicator
                    if !isCurrentUser && !isEliminated {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .padding(MADTheme.Spacing.md)
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded content - nudge/flex actions
            if isExpanded && !isCurrentUser && !isEliminated {
                expandedActions(for: user)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(
                    isCurrentUser ? 0.07 : (rank == 1 ? 0.04 : 0.02)
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .stroke(
                            isEliminated ? Color.red.opacity(0.1) :
                                (isCurrentUser ? MADTheme.Colors.primary.opacity(0.4) :
                                    (rank == 1 ? Color.yellow.opacity(0.15) : Color.white.opacity(0.05))),
                            lineWidth: isCurrentUser ? 1.5 : 1
                        )
                )
        )
        .opacity(isEliminated ? 0.55 : 1.0)
    }

    // MARK: - Rank Badge
    private func rankBadge(rank: Int, isEliminated: Bool) -> some View {
        Group {
            if isEliminated {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.red.opacity(0.3))
                    .frame(width: 28, height: 28)
            } else if rank <= 3 {
                let colors: [Color] = rank == 1 ? [.yellow, .orange] :
                    rank == 2 ? [Color(white: 0.85), Color(white: 0.6)] :
                    [Color(red: 0.8, green: 0.5, blue: 0.2), Color(red: 0.6, green: 0.35, blue: 0.15)]

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: colors.map { $0.opacity(0.2) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 28, height: 28)
                    Text("\(rank)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                        )
                }
            } else {
                Text("\(rank)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(width: 28, height: 28)
            }
        }
    }

    // MARK: - Expanded Actions (Nudge / View)
    private func expandedActions(for user: CompetitionUser) -> some View {
        let distance = user.intervals?[intervalKey] ?? 0
        let completed = distance >= goal
        let isToday = Calendar.current.isDateInToday(selectedIntervalDate)

        return VStack(spacing: MADTheme.Spacing.sm) {
            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 1)

            HStack(spacing: MADTheme.Spacing.md) {
                // Today's status
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

                // Nudge button - only show if the other user hasn't completed today
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
                                .overlay(
                                    Capsule()
                                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.bottom, MADTheme.Spacing.sm)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Flex Button
    private var canFlex: Bool {
        guard Calendar.current.isDateInToday(selectedIntervalDate),
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
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "FF6B6B"), Color(hex: "FF8E53")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

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
                                    colors: [Color(hex: "FF6B6B").opacity(0.3), Color(hex: "FF8E53").opacity(0.15)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Action Feedback
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
        .offset(y: -60)
    }

    // MARK: - Actions
    private func sendFlex() {
        isSendingAction = true
        Task {
            do {
                try await competitionService.sendFlex(competitionId: competition.competition_id)
                await MainActor.run {
                    isSendingAction = false
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

