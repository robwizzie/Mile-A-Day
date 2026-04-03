import SwiftUI
import HealthKit

// MARK: - Active Content

extension CompetitionDetailView {

    // MARK: - Active Content
    var activeContent: some View {
        VStack(spacing: MADTheme.Spacing.xl) {
            // 1. Compact hero status
            heroStatusSection

            // 2. Enhanced leaderboard (podium + rows with nudge)
            enhancedLeaderboard

            // 3. Flex action (if eligible)
            if canFlex {
                flexButton
            } else if FlexNudgeTracker.hasSentFlexToday(competitionId: competition.competition_id) {
                flexSentIndicator
            }

            // 4. Mode-specific content
            if competition.type != .race {
                intervalNavigator
                intervalContent
            } else {
                raceProgressView
            }

            // 5. Collapsible settings dropdown
            settingsDropdown
        }
        .confirmationDialog("Send a nudge?", isPresented: $showNudgeConfirm, titleVisibility: .visible) {
            Button("Send Nudge") {
                if let user = nudgeTargetUser { sendNudge(to: user) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let user = nudgeTargetUser {
                Text("Send \(user.displayName) a reminder to lace up and run. Once per person per day.")
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

    // MARK: - Hero Status Section
    var heroStatusSection: some View {
        let currentUser = competition.users.first(where: { $0.user_id == UserDefaults.standard.string(forKey: "backendUserId") })
        let todayKey = intervalKey(for: Date())
        let todayDistance = currentUser?.intervals?[todayKey] ?? 0
        let goal = competition.options.goal
        let gradientColors = competition.type.gradient.map { Color(hex: $0) }

        return VStack(spacing: MADTheme.Spacing.md) {
            // Type-specific hero content
            switch competition.type {
            case .streaks:
                streakHeroContent(user: currentUser, todayDistance: todayDistance, goal: goal, gradientColors: gradientColors)
            case .clash:
                clashHeroContent(user: currentUser, todayDistance: todayDistance, todayKey: todayKey, gradientColors: gradientColors)
            case .apex:
                apexHeroContent(user: currentUser, todayDistance: todayDistance, todayKey: todayKey, gradientColors: gradientColors)
            case .targets:
                targetsHeroContent(user: currentUser, todayDistance: todayDistance, goal: goal, gradientColors: gradientColors)
            case .race:
                raceHeroContent(user: currentUser, goal: goal, gradientColors: gradientColors)
            }

            // Compact tracked activities + time remaining
            HStack(spacing: MADTheme.Spacing.sm) {
                ForEach(competition.workouts, id: \.self) { activity in
                    HStack(spacing: 4) {
                        Image(systemName: activity.icon)
                            .font(.system(size: 10))
                        Text(activity.displayName)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }

                Spacer()

                if let endDate = competition.endDateFormatted {
                    let remaining = endDate.timeIntervalSince(Date())
                    let days = Int(remaining / 86400)
                    let hours = Int(remaining.truncatingRemainder(dividingBy: 86400) / 3600)
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                        Text(days > 0 ? "\(days)d \(hours)h" : "\(hours)h left")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.green.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.1)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(
                            LinearGradient(
                                colors: gradientColors.map { $0.opacity(0.3) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            heroAnimated = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.8)) {
                    heroAnimated = true
                }
            }
        }
    }

    // MARK: - Hero Content Per Type

    func streakHeroContent(user: CompetitionUser?, todayDistance: Double, goal: Double, gradientColors: [Color]) -> some View {
        let streak = Int(user?.score ?? 0)
        let completed = todayDistance >= goal
        let remaining = max(0, goal - todayDistance)
        let firstTo = competition.options.first_to

        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.orange)
                    .shadow(color: .orange.opacity(0.4), radius: 6)

                CountingText(value: heroAnimated ? Double(streak) : 0, format: "%.0f", suffix: "")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("day streak")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 14)
            }

            if completed {
                Label("Done \u{2014} \(String(format: "%.1f", todayDistance)) \(competition.options.unit.shortDisplayName)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
            } else {
                Label("\(String(format: "%.1f", remaining)) \(competition.options.unit.shortDisplayName) to go", systemImage: "figure.run")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }

            if firstTo > 0, let user = user {
                let lives = user.remaining_lives ?? firstTo
                HStack(spacing: 4) {
                    ForEach(0..<min(firstTo, 6), id: \.self) { i in
                        Image(systemName: i < lives ? "heart.fill" : "heart")
                            .font(.system(size: 12))
                            .foregroundColor(i < lives ? .red : .white.opacity(0.15))
                    }
                    if firstTo > 6 {
                        Text("+\(firstTo - 6)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }
        }
    }

    func clashHeroContent(user: CompetitionUser?, todayDistance: Double, todayKey: String, gradientColors: [Color]) -> some View {
        let acceptedUsers = competition.users.filter { $0.invite_status == .accepted }
        let myDistance = todayDistance
        let bestOpponentDistance = acceptedUsers.filter { $0.user_id != user?.user_id }.map { $0.intervals?[todayKey] ?? 0 }.max() ?? 0
        let isLeading = myDistance > 0 && myDistance >= bestOpponentDistance
        let points = Int(user?.score ?? 0)

        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom))

                CountingText(value: heroAnimated ? Double(points) : 0, format: "%.0f", suffix: "")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(points == 1 ? "win" : "wins")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 14)
            }

            if myDistance > 0 {
                let diff = myDistance - bestOpponentDistance
                if isLeading && diff > 0 {
                    Label("Leading by \(String(format: "%.1f", diff)) \(competition.options.unit.shortDisplayName)", systemImage: "crown.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                } else if diff < 0 {
                    Label("Behind by \(String(format: "%.1f", abs(diff))) \(competition.options.unit.shortDisplayName)", systemImage: "arrow.up")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.orange.opacity(0.12)))
                } else {
                    Label("Tied at \(String(format: "%.1f", myDistance)) \(competition.options.unit.shortDisplayName)", systemImage: "equal")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            } else {
                Label("No activity yet today", systemImage: "figure.run")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }
        }
    }

    func apexHeroContent(user: CompetitionUser?, todayDistance: Double, todayKey: String, gradientColors: [Color]) -> some View {
        let totalScore = user?.score ?? 0
        let acceptedUsers = competition.users.filter { $0.invite_status == .accepted }
        let myRank = acceptedUsers.sorted { ($0.score ?? 0) > ($1.score ?? 0) }.firstIndex(where: { $0.user_id == user?.user_id }).map { $0 + 1 } ?? 0

        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom))

                CountingText(value: heroAnimated ? totalScore : 0, format: "%.1f", suffix: "")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(competition.options.unit.shortDisplayName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 14)
            }

            HStack(spacing: MADTheme.Spacing.sm) {
                if myRank > 0 {
                    Label(rankOrdinal(myRank) + " of \(acceptedUsers.count)", systemImage: "trophy")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(myRank == 1 ? .yellow : .white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(myRank == 1 ? Color.yellow.opacity(0.12) : Color.white.opacity(0.06)))
                }

                if todayDistance > 0 {
                    Label("+\(String(format: "%.1f", todayDistance)) today", systemImage: "figure.run")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.green.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.green.opacity(0.1)))
                }
            }
        }
    }

    func targetsHeroContent(user: CompetitionUser?, todayDistance: Double, goal: Double, gradientColors: [Color]) -> some View {
        let points = Int(user?.score ?? 0)
        let completed = todayDistance >= goal
        let progress = min(todayDistance / max(goal, 0.1), 1.0)

        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 28))
                    .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom))

                CountingText(value: heroAnimated ? Double(points) : 0, format: "%.0f", suffix: "")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(points == 1 ? "point" : "points")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 14)
            }

            // Today's progress bar
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(completed
                                ? LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * (heroAnimated ? progress : 0), height: 8)
                            .animation(.easeOut(duration: 0.8).delay(0.3), value: heroAnimated)
                    }
                }
                .frame(height: 8)

                HStack {
                    if completed {
                        Label("Target hit!", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.green)
                    } else {
                        Text("\(String(format: "%.1f", todayDistance))/\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)
        }
    }

    func raceHeroContent(user: CompetitionUser?, goal: Double, gradientColors: [Color]) -> some View {
        let totalDistance = user?.score ?? 0
        let progress = min(totalDistance / max(goal, 0.1), 1.0)
        let percent = Int(progress * 100)
        let acceptedUsers = competition.users.filter { $0.invite_status == .accepted }
        let myRank = acceptedUsers.sorted { ($0.score ?? 0) > ($1.score ?? 0) }.firstIndex(where: { $0.user_id == user?.user_id }).map { $0 + 1 } ?? 0

        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom))

                CountingText(value: heroAnimated ? Double(percent) : 0, format: "%.0f", suffix: "%")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("complete")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 14)
            }

            // Progress bar
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * (heroAnimated ? progress : 0), height: 8)
                            .animation(.easeOut(duration: 0.8).delay(0.3), value: heroAnimated)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("\(String(format: "%.1f", totalDistance))/\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    if myRank > 0 {
                        Text(rankOrdinal(myRank) + " place")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(myRank == 1 ? .yellow : .white.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, MADTheme.Spacing.sm)
        }
    }

    // MARK: - Flex Button
    var flexButton: some View {
        let typeColor = Color(hex: competition.type.gradient[0])
        let subtitle: String = {
            switch competition.type {
            case .streaks: return "Let them know you finished"
            case .clash: return "Show off your lead"
            case .apex: return "They'll know you put in work"
            case .targets: return "You hit your target"
            case .race: return "You're making progress"
            }
        }()

        return Button { sendFlex() } label: {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 18))
                    .foregroundColor(typeColor)
                    .shadow(color: typeColor.opacity(0.4), radius: 4)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Flex on everyone")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer()

                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .stroke(typeColor.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Flex Sent Indicator
    var flexSentIndicator: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 14))
                .foregroundColor(.green.opacity(0.6))

            Text("Flex sent today")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.35))

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.green.opacity(0.4))
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.03))
        )
    }

    // MARK: - Nudge Eligibility
    func shouldShowNudge(for user: CompetitionUser, todayKey: String) -> Bool {
        let distance = user.intervals?[todayKey] ?? 0
        let goal = competition.options.goal

        switch competition.type {
        case .streaks, .targets:
            return distance < goal
        case .clash:
            return true // Can always nudge opponents in clash
        case .apex:
            return distance == 0 // Nudge if they haven't run today
        case .race:
            return distance == 0 // Nudge if they haven't run today
        }
    }

    // MARK: - Flex Eligibility
    var canFlex: Bool {
        guard !FlexNudgeTracker.hasSentFlexToday(competitionId: competition.competition_id) else {
            return false
        }

        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        guard let currentUser = competition.users.first(where: { $0.user_id == currentUserId }) else {
            return false
        }

        let todayKey = intervalKey(for: Date())
        let distance = currentUser.intervals?[todayKey] ?? 0
        let goal = competition.options.goal

        switch competition.type {
        case .streaks:
            return distance >= goal
        case .targets:
            return distance >= goal
        case .clash:
            let acceptedUsers = competition.users.filter { $0.invite_status == .accepted }
            let bestOpponent = acceptedUsers
                .filter { $0.user_id != currentUser.user_id }
                .map { $0.intervals?[todayKey] ?? 0 }
                .max() ?? 0
            return distance > 0 && distance >= bestOpponent
        case .apex:
            return distance > 0
        case .race:
            return distance > 0
        }
    }

    // MARK: - Flex/Nudge Actions
    func sendFlex() {
        isSendingAction = true
        Task {
            do {
                try await competitionService.sendFlex(competitionId: competition.competition_id)
                await MainActor.run {
                    isSendingAction = false
                    FlexNudgeTracker.markFlexSent(competitionId: competition.competition_id)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showActionFeedback(ActionFeedback(icon: "hand.raised.fill", message: "Flex sent!", isError: false))
                }
            } catch {
                await MainActor.run {
                    isSendingAction = false
                    let msg = (error as? CompetitionServiceError)?.errorDescription ?? "Could not send flex"
                    showActionFeedback(ActionFeedback(icon: "xmark.circle", message: msg, isError: true))
                }
            }
        }
    }

    func sendNudge(to user: CompetitionUser) {
        isSendingAction = true
        Task {
            do {
                try await competitionService.sendNudge(competitionId: competition.competition_id, targetUserId: user.user_id)
                await MainActor.run {
                    isSendingAction = false
                    FlexNudgeTracker.markNudgeSent(competitionId: competition.competition_id, targetUserId: user.user_id)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showActionFeedback(ActionFeedback(icon: "bell.badge.fill", message: "Nudge sent to \(user.displayName)!", isError: false))
                }
            } catch {
                await MainActor.run {
                    isSendingAction = false
                    let msg = (error as? CompetitionServiceError)?.errorDescription ?? "Could not send nudge"
                    showActionFeedback(ActionFeedback(icon: "xmark.circle", message: msg, isError: true))
                }
            }
        }
    }

    func showActionFeedback(_ feedback: ActionFeedback) {
        withAnimation(.easeInOut(duration: 0.2)) { actionFeedback = feedback }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.2)) { actionFeedback = nil }
        }
    }

    func feedbackBanner(_ feedback: ActionFeedback) -> some View {
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

    // MARK: - Collapsible Settings Dropdown
    var settingsDropdown: some View {
        VStack(spacing: 0) {
            // Tappable header
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
                Text("Competition Details")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Image(systemName: showSettings ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(MADTheme.Spacing.md)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSettings.toggle()
                }
            }

            if showSettings {
                infoSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.top, -MADTheme.Spacing.sm)
            }
        }
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
