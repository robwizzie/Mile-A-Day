import SwiftUI

// MARK: - Streak Active View

struct StreakActiveView: View {
    let competition: Competition
    let selectedIntervalDate: Date
    @ObservedObject var competitionService: CompetitionService
    @State private var showNudgeConfirm = false
    @State private var nudgeTargetUser: CompetitionUser?
    @State private var showFlexConfirm = false
    @State private var hasSentFlex = false
    @State private var isSendingAction = false
    @State private var actionFeedback: ActionFeedback?
    @State private var showEliminatedUsers = false

    private let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
    private let maxVisibleHearts = 6

    private var acceptedUsers: [CompetitionUser] {
        competition.users.filter { $0.invite_status == .accepted }
    }

    private var activeUsers: [CompetitionUser] {
        acceptedUsers.filter { !userIsEliminated($0) }
    }

    private var eliminatedUsers: [CompetitionUser] {
        acceptedUsers.filter { userIsEliminated($0) }
    }

    private var rankedUsers: [CompetitionUser] {
        activeUsers.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
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

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedIntervalDate)
    }

    var body: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            heroBanner
            calendarStrip
            if canFlex { flexButton }
            leaderboard
            if !eliminatedUsers.isEmpty { eliminatedSection }
        }
        .confirmationDialog("Flex on everyone?", isPresented: $showFlexConfirm, titleVisibility: .visible) {
            Button("Send Flex") { sendFlex() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Send a notification to all competitors that you've completed your goal. Once per day.")
        }
        .confirmationDialog("Send a nudge?", isPresented: $showNudgeConfirm, titleVisibility: .visible) {
            Button("Send Nudge") {
                if let user = nudgeTargetUser { sendNudge(to: user) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let user = nudgeTargetUser {
                Text("Send \(user.displayName) a reminder to get their run in. Once per person per day.")
            }
        }
        .overlay(alignment: .top) {
            if let feedback = actionFeedback {
                feedbackBanner(feedback)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        let currentUser = acceptedUsers.first(where: { $0.user_id == currentUserId })
        let streak = Int(currentUser?.score ?? 0)
        let distance = currentUser?.intervals?[intervalKey] ?? 0
        let completed = distance >= goal
        let remaining = max(0, goal - distance)

        return VStack(spacing: 12) {
            // Streak count
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)

                Text("\(streak)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("day streak")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.top, 16)
            }

            // Status
            if isToday {
                if completed {
                    Label("Done \u{2014} \(String(format: "%.1f", distance)) \(competition.options.unit.shortDisplayName)", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.green)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                } else {
                    Label("\(String(format: "%.1f", remaining)) \(competition.options.unit.shortDisplayName) to go", systemImage: "figure.run")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.orange.opacity(0.12)))
                }
            }

            // Lives
            if firstTo > 0, let currentUser = currentUser {
                livesRow(lives: currentUser.remaining_lives ?? firstTo)
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
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func livesRow(lives: Int) -> some View {
        let displayCount = min(firstTo, maxVisibleHearts)
        return HStack(spacing: 5) {
            ForEach(0..<displayCount, id: \.self) { i in
                Image(systemName: i < lives ? "heart.fill" : "heart")
                    .font(.system(size: 14))
                    .foregroundColor(i < lives ? .red : .white.opacity(0.15))
            }
            if firstTo > maxVisibleHearts {
                Text("+\(firstTo - maxVisibleHearts)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }

    // MARK: - Calendar Strip

    private var calendarStrip: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate = competition.startDateFormatted ?? calendar.date(byAdding: .day, value: -13, to: today) ?? today
        let dayCount = max(1, calendar.dateComponents([.day], from: startDate, to: today).day ?? 0) + 1
        let visibleDays = min(dayCount, 14)

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(0..<visibleDays, id: \.self) { offset in
                        let dayDate = calendar.date(byAdding: .day, value: -(visibleDays - 1 - offset), to: today) ?? today
                        let isSelected = calendar.isDate(dayDate, inSameDayAs: selectedIntervalDate)
                        dayDot(date: dayDate, isSelected: isSelected)
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

    private func dayDot(date: Date, isSelected: Bool) -> some View {
        let calendar = Calendar.current
        let isTodayDate = calendar.isDateInToday(date)
        let isFuture = date > Date()
        let currentUser = acceptedUsers.first(where: { $0.user_id == currentUserId })

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dayKey = formatter.string(from: calendar.startOfDay(for: date))
        let distance = currentUser?.intervals?[dayKey] ?? 0
        let completed = distance >= goal

        let color: Color = {
            if isFuture { return .white.opacity(0.08) }
            if completed { return .green }
            if isTodayDate { return .orange }
            return .red.opacity(0.4)
        }()

        let dayNum = calendar.component(.day, from: date)
        let dayLetter = String(calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1].prefix(1))

        return VStack(spacing: 3) {
            Text(dayLetter)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.3))

            ZStack {
                Circle()
                    .fill(color.opacity(isSelected ? 1 : 0.55))
                    .frame(width: 26, height: 26)

                if completed && !isFuture {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(dayNum)")
                        .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundColor(isFuture ? .white.opacity(0.12) : .white)
                }
            }

            Circle()
                .fill(isTodayDate ? .white : .clear)
                .frame(width: 3, height: 3)
        }
        .padding(.horizontal, 1)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? Color.orange.opacity(0.5) : .clear, lineWidth: 1.5)
                .padding(-2)
        )
    }

    // MARK: - Leaderboard

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack {
                Text(isToday ? "Standings" : "Day Results")
                    .font(MADTheme.Typography.title3)
                    .foregroundColor(.white)
                Spacer()
                Text("\(activeUsers.count) competing")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, MADTheme.Spacing.sm)

            VStack(spacing: 0) {
                ForEach(Array(rankedUsers.enumerated()), id: \.element.id) { index, user in
                    leaderboardRow(user: user, rank: index + 1)

                    if index < rankedUsers.count - 1 {
                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.horizontal, MADTheme.Spacing.md)
                    }
                }
            }
            .padding(.vertical, 6)
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

    private func leaderboardRow(user: CompetitionUser, rank: Int) -> some View {
        let isMe = user.user_id == currentUserId
        let streak = Int(user.score ?? 0)
        let distance = user.intervals?[intervalKey] ?? 0
        let completed = distance >= goal
        let lives = user.remaining_lives ?? firstTo

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Rank
                rankLabel(rank)

                // Avatar
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Text(user.displayName.prefix(1).uppercased())
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    )
                    .overlay(
                        Circle().stroke(rank == 1 ? Color.yellow.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1.5)
                    )

                // Name + lives
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(user.displayName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if isMe {
                            Text("YOU")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(MADTheme.Colors.madRed))
                        }
                    }

                    if firstTo > 0 {
                        miniLives(lives: lives)
                    }
                }

                Spacer()

                // Right side: streak + today status
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("\(streak)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }

                    todayStatus(distance: distance, completed: completed)
                }

                // Nudge affordance for others
                if !isMe && isToday && !completed {
                    Button {
                        nudgeTargetUser = user
                        showNudgeConfirm = true
                    } label: {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.orange.opacity(0.1)))
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                    .fill(isMe ? Color.white.opacity(0.04) : .clear)
            )
        }
    }

    private func rankLabel(_ rank: Int) -> some View {
        Group {
            if rank <= 3 {
                let color: Color = rank == 1 ? .yellow : (rank == 2 ? Color(white: 0.75) : Color(red: 0.75, green: 0.5, blue: 0.2))
                Text("\(rank)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .frame(width: 22)
            } else {
                Text("\(rank)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.25))
                    .frame(width: 22)
            }
        }
    }

    private func miniLives(lives: Int) -> some View {
        let count = min(firstTo, maxVisibleHearts)
        return HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
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

    @ViewBuilder
    private func todayStatus(distance: Double, completed: Bool) -> some View {
        if completed {
            Text("\(String(format: "%.1f", distance)) \(competition.options.unit.shortDisplayName)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.green)
        } else if isToday {
            Text("\(String(format: "%.1f", distance))/\(competition.options.goalFormatted)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.35))
        } else {
            Text("Missed")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.red.opacity(0.45))
        }
    }

    // MARK: - Eliminated

    private var eliminatedSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showEliminatedUsers.toggle()
                }
            } label: {
                HStack {
                    Text("\(eliminatedUsers.count) eliminated")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    Image(systemName: showEliminatedUsers ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.2))
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.vertical, MADTheme.Spacing.sm)
            }
            .buttonStyle(PlainButtonStyle())

            if showEliminatedUsers {
                VStack(spacing: 2) {
                    ForEach(eliminatedUsers.sorted(by: { ($0.score ?? 0) > ($1.score ?? 0) }), id: \.id) { user in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.white.opacity(0.04))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Text(user.displayName.prefix(1).uppercased())
                                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.25))
                                )

                            Text(user.displayName)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.25))
                                .strikethrough(color: .red.opacity(0.2))

                            Spacer()

                            Text("\(Int(user.score ?? 0))d")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.15))
                        }
                        .padding(.horizontal, MADTheme.Spacing.md)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.bottom, MADTheme.Spacing.sm)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.02))
        )
    }

    // MARK: - Flex Button

    private var canFlex: Bool {
        guard !hasSentFlex, isToday,
              let currentUser = acceptedUsers.first(where: { $0.user_id == currentUserId }) else {
            return false
        }
        let distance = currentUser.intervals?[intervalKey] ?? 0
        return distance >= goal && !userIsEliminated(currentUser)
    }

    private var flexButton: some View {
        Button { showFlexConfirm = true } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Flex on everyone")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Let them know you finished")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Feedback Banner

    private func feedbackBanner(_ feedback: ActionFeedback) -> some View {
        HStack(spacing: 6) {
            Image(systemName: feedback.icon)
                .font(.system(size: 12))
            Text(feedback.message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundColor(feedback.isError ? .red : .green)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(feedback.isError ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
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
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showFeedback(ActionFeedback(icon: "hand.raised.fill", message: "Flex sent!", isError: false))
                }
            } catch {
                await MainActor.run {
                    isSendingAction = false
                    let msg = (error as? CompetitionServiceError)?.errorDescription ?? "Could not send flex"
                    showFeedback(ActionFeedback(icon: "xmark.circle", message: msg, isError: true))
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
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showFeedback(ActionFeedback(icon: "bell.badge.fill", message: "Nudge sent to \(user.displayName)!", isError: false))
                }
            } catch {
                await MainActor.run {
                    isSendingAction = false
                    let msg = (error as? CompetitionServiceError)?.errorDescription ?? "Could not send nudge"
                    showFeedback(ActionFeedback(icon: "xmark.circle", message: msg, isError: true))
                }
            }
        }
    }

    private func showFeedback(_ feedback: ActionFeedback) {
        withAnimation(.easeInOut(duration: 0.2)) { actionFeedback = feedback }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.2)) { actionFeedback = nil }
        }
    }

    // MARK: - Helpers

    private func userIsEliminated(_ user: CompetitionUser) -> Bool {
        guard firstTo > 0, let lives = user.remaining_lives else { return false }
        return lives <= 0
    }
}

// MARK: - Supporting Types

struct ActionFeedback: Equatable {
    let icon: String
    let message: String
    let isError: Bool
}
