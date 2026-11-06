import SwiftUI

// MARK: - Streak Active View

struct StreakActiveView: View {
    let competition: Competition
    let selectedIntervalDate: Date
    @ObservedObject var competitionService: CompetitionService
    @State private var showFlexConfirm = false
    @State private var isSendingAction = false
    @State private var actionFeedback: ActionFeedback?
    @State private var showEliminatedUsers = false

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

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
        Competition.ranked(activeUsers)
    }

    private var goal: Double { competition.options.goal }
    private var totalLives: Int { competition.streakLives }

    private var intervalKey: String {
        let calendar = Calendar.current
        let interval = competition.options.interval ?? .day

        switch interval {
        case .day:
            return Self.isoDateFormatter.string(from: calendar.startOfDay(for: selectedIntervalDate))
        case .week:
            return competition.weeklyIntervalKey(for: selectedIntervalDate)
        case .month:
            var components = calendar.dateComponents([.year, .month], from: selectedIntervalDate)
            components.day = 1
            let startOfMonth = calendar.date(from: components) ?? selectedIntervalDate
            return Self.isoDateFormatter.string(from: startOfMonth)
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
                    .madFont(size: 32, maxScale: 1.5)
                    .foregroundColor(.orange)

                Text("\(streak)")
                    .madFont(size: 44, weight: .bold, design: .rounded)
                    .foregroundColor(.white)

                Text("day streak")
                    .madFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.top, 16)
            }

            // Status
            if isToday {
                if completed {
                    Label("Done \u{2014} \(String(format: "%.1f", distance)) \(competition.options.unit.shortDisplayName)", systemImage: "checkmark.circle.fill")
                        .madFont(size: 13, weight: .semibold, design: .rounded)
                        .foregroundColor(.green)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                } else {
                    Label("\(String(format: "%.1f", remaining)) \(competition.options.unit.shortDisplayName) to go", systemImage: "figure.run")
                        .madFont(size: 13, weight: .semibold, design: .rounded)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.orange.opacity(0.12)))
                }
            }

            // Lives
            if totalLives > 0, let currentUser = currentUser {
                livesRow(lives: currentUser.remaining_lives ?? totalLives)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.lg)
        .padding(.horizontal, MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(CompeteDesign.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func livesRow(lives: Int) -> some View {
        let displayCount = min(totalLives, maxVisibleHearts)
        return HStack(spacing: 5) {
            ForEach(0..<displayCount, id: \.self) { i in
                Image(systemName: i < lives ? "heart.fill" : "heart")
                    .madFont(size: 14, maxScale: 1.5)
                    .foregroundColor(i < lives ? .red : .white.opacity(0.15))
            }
            if totalLives > maxVisibleHearts {
                Text("+\(totalLives - maxVisibleHearts)")
                    .madFont(size: 11, weight: .semibold, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
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

        let dayKey = Self.isoDateFormatter.string(from: calendar.startOfDay(for: date))
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
                .madFont(size: 11, weight: .medium, design: .rounded)
                .foregroundColor(.white.opacity(0.6))

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
                        .madFont(size: 11, weight: isSelected ? .bold : .medium, design: .rounded)
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
                    .competeFont(CompeteDesign.eyebrow)
                    .tracking(CompeteDesign.eyebrowTracking)
                    .textCase(.uppercase)
                    .foregroundColor(CompeteDesign.inkFaint)
                Spacer()
                Text("\(activeUsers.count) competing")
                    .madFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
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
                    .fill(CompeteDesign.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .stroke(CompeteDesign.hairline, lineWidth: 1)
                    )
            )
        }
    }

    private func leaderboardRow(user: CompetitionUser, rank: Int) -> some View {
        let isMe = user.user_id == currentUserId
        let streak = Int(user.score ?? 0)
        let distance = user.intervals?[intervalKey] ?? 0
        let completed = distance >= goal
        let lives = user.remaining_lives ?? totalLives

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Rank
                rankLabel(rank)

                // Avatar
                AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 34)
                    .overlay(
                        Circle().stroke(rank == 1 ? Color.yellow.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1.5)
                    )

                // Name + lives
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(user.displayName)
                            .madFont(size: 14, weight: .semibold, design: .rounded)
                            .foregroundColor(.white)
                            .madNameLines()

                        if isMe {
                            Text("YOU")
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .madFont(size: 11, weight: .bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(MADTheme.Colors.madRed))
                        }
                    }

                    if totalLives > 0 {
                        miniLives(lives: lives)
                    }
                }

                Spacer()

                // Right side: streak + today status
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .madFont(size: 10, maxScale: 1.5)
                            .foregroundColor(.orange)
                        Text("\(streak)")
                            .madFont(size: 16, weight: .bold, design: .rounded)
                            .foregroundColor(.white)
                    }

                    todayStatus(distance: distance, completed: completed)
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
                    .madFont(size: 12, weight: .bold, design: .rounded)
                    .foregroundColor(color)
                    .frame(minWidth: 22)
            } else {
                Text("\(rank)")
                    .madFont(size: 12, weight: .bold, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
                    .frame(minWidth: 22)
            }
        }
    }

    private func miniLives(lives: Int) -> some View {
        let count = min(totalLives, maxVisibleHearts)
        return HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i < lives ? Color.red : Color.white.opacity(0.1))
                    .frame(width: 5, height: 5)
            }
            if totalLives > maxVisibleHearts {
                Text("+\(totalLives - maxVisibleHearts)")
                    .madFont(size: 11, weight: .medium, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private func todayStatus(distance: Double, completed: Bool) -> some View {
        if completed {
            Text("\(String(format: "%.1f", distance)) \(competition.options.unit.shortDisplayName)")
                .madFont(size: 11, weight: .semibold, design: .rounded)
                .foregroundColor(.green)
        } else if isToday {
            Text("\(String(format: "%.1f", distance))/\(competition.options.goalFormatted)")
                .madFont(size: 11, weight: .medium, design: .rounded)
                .foregroundColor(.white.opacity(0.6))
        } else {
            Text("Missed")
                .madFont(size: 11, weight: .medium, design: .rounded)
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
                        .madFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Image(systemName: showEliminatedUsers ? "chevron.up" : "chevron.down")
                        .madFont(size: 9, weight: .semibold, maxScale: 1.5)
                        .foregroundColor(.white.opacity(0.2))
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.vertical, MADTheme.Spacing.sm)
            }
            .buttonStyle(PlainButtonStyle())

            if showEliminatedUsers {
                VStack(spacing: 2) {
                    ForEach(Competition.ranked(eliminatedUsers), id: \.id) { user in
                        HStack(spacing: 8) {
                            AvatarView(name: user.displayName, imageURL: user.profile_image_url, size: 24)
                                .opacity(0.4)

                            Text(user.displayName)
                                .madFont(size: 12, weight: .medium, design: .rounded)
                                .foregroundColor(.white.opacity(0.6))
                                .strikethrough(color: .red.opacity(0.2))

                            Spacer()

                            Text("\(Int(user.score ?? 0))d")
                                .madFont(size: 11, weight: .medium, design: .rounded)
                                .foregroundColor(.white.opacity(0.6))
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
        guard !FlexNudgeTracker.hasSentFlexToday(competitionId: competition.competition_id),
              isToday,
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
                    .madFont(size: 16, maxScale: 1.5)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Flex on everyone")
                        .madFont(size: 14, weight: .bold, design: .rounded)
                        .foregroundColor(.white)
                    Text("Let them know you finished")
                        .madFont(size: 11, design: .rounded)
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .madFont(size: 11, weight: .semibold, maxScale: 1.5)
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(CompeteDesign.surface)
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
                .madFont(size: 12, maxScale: 1.5)
            Text(feedback.message)
                .madFont(size: 12, weight: .medium, design: .rounded)
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
            let targets = acceptedUsers.filter {
                $0.user_id != currentUserId &&
                !FlexNudgeTracker.hasSentFlexToday(targetUserId: $0.user_id)
            }

            var successes = 0
            var lastError: Error?
            for target in targets {
                do {
                    try await competitionService.sendFlex(competitionId: competition.competition_id, targetUserId: target.user_id)
                    FlexNudgeTracker.markFlexSent(targetUserId: target.user_id)
                    successes += 1
                } catch {
                    lastError = error
                }
            }

            await MainActor.run {
                isSendingAction = false
                if successes > 0 {
                    FlexNudgeTracker.markFlexSent(competitionId: competition.competition_id)
                    MADHaptics.success()
                    let msg = successes == 1 ? "Flex sent!" : "Flex sent to \(successes)!"
                    showFeedback(ActionFeedback(icon: "hand.raised.fill", message: msg, isError: false))
                } else {
                    let msg = (lastError as? CompetitionServiceError)?.errorDescription ?? "Could not send flex"
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
        guard totalLives > 0, let lives = user.remaining_lives else { return false }
        return lives <= 0
    }
}
