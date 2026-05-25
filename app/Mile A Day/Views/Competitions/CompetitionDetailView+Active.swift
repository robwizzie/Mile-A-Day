import SwiftUI
import HealthKit

// MARK: - Active Content

extension CompetitionDetailView {

    // MARK: - Active Content
    // The detail view is now centered on a tabbed card (Today's Race /
    // Standings / Flex) that hosts the existing per-mode views without
    // duplicating logic. Above the tabbed card: the user's own past-7-day
    // ring strip (Apple-Fitness style) — taps drill into a per-day sheet.
    var activeContent: some View {
        VStack(spacing: MADTheme.Spacing.xl) {
            CompetitionMyDailyRings(competition: competition)

            mainTabbedCard
        }
        .overlay(alignment: .top) {
            if let feedback = actionFeedback {
                feedbackBanner(feedback)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .onAppear {
            // Pick the right default tab per mode the first time this view
            // appears. After that, respect whatever the user selected.
            if selectedMainTab == .standings {
                selectedMainTab = CompetitionDetailView.defaultMainTab(for: competition.type)
            }
        }
    }

    // MARK: - Hero Content Per Type (legacy helpers used as @ViewBuilder
    // fragments by other surfaces — keep them defined but referenced from
    // mainTabbedCard's standings tab if needed. Currently inlined via the
    // motivation callout, so these aren't on the hot path.

    func streakHeroContent(user: CompetitionUser?, todayDistance: Double, goal: Double, gradientColors: [Color]) -> some View {
        let streak = Int(user?.score ?? 0)
        let completed = todayDistance >= goal
        let remaining = max(0, goal - todayDistance)
        let totalLives = competition.streakLives

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
                Label("Done \u{2014} \(competition.options.formatQuantityWithUnit(todayDistance))", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
            } else {
                Label("\(competition.options.formatQuantityWithUnit(remaining)) to go", systemImage: "figure.run")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }

            if totalLives > 0, let user = user {
                let lives = user.remaining_lives ?? totalLives
                HStack(spacing: 4) {
                    ForEach(0..<min(totalLives, 6), id: \.self) { i in
                        Image(systemName: i < lives ? "heart.fill" : "heart")
                            .font(.system(size: 12))
                            .foregroundColor(i < lives ? .red : .white.opacity(0.15))
                    }
                    if totalLives > 6 {
                        Text("+\(totalLives - 6)")
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
                    Label("Leading by \(competition.options.formatQuantityWithUnit(diff))", systemImage: "crown.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                } else if diff < 0 {
                    Label("Behind by \(competition.options.formatQuantityWithUnit(abs(diff)))", systemImage: "arrow.up")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.orange.opacity(0.12)))
                } else {
                    Label("Tied at \(competition.options.formatQuantityWithUnit(myDistance))", systemImage: "equal")
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

                CountingText(value: heroAnimated ? totalScore : 0, format: "%.1f", suffix: "", formatter: competition.options.formatQuantity)
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
                    Label("+\(competition.options.formatQuantity(todayDistance)) today", systemImage: "figure.run")
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
                        Text("\(competition.options.formatQuantity(todayDistance))/\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
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
                    Text("\(competition.options.formatQuantity(totalDistance))/\(competition.options.goalFormatted) \(competition.options.unit.shortDisplayName)")
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

    // MARK: - Flex Section
    private var flexMotivationalMessages: [String] {
        [
            "Take the lead to flex on your opponents",
            "Get ahead and show them who's boss",
            "Outrun the competition to unlock flex",
            "Lace up and take first — then talk trash",
            "Lead the pack to earn bragging rights",
            "One good run away from flexing on everyone"
        ]
    }

    var flexSection: some View {
        let typeColor = Color(hex: competition.type.gradient[0])
        let currentUserId = UserDefaults.standard.string(forKey: "backendUserId")
        let acceptedUsers = competition.users.filter { $0.invite_status == .accepted && $0.user_id != currentUserId }
        let currentUser = competition.users.first(where: { $0.user_id == currentUserId })
        let myScore = currentUser?.score ?? 0

        // Filter to only users we're beating and haven't flexed on today
        let flexableUsers = acceptedUsers.filter { user in
            let theirScore = user.score ?? 0
            return myScore > theirScore && !FlexNudgeTracker.hasSentFlexToday(targetUserId: user.user_id)
        }

        let alreadyFlexed = acceptedUsers.filter { user in
            FlexNudgeTracker.hasSentFlexToday(targetUserId: user.user_id)
        }

        let canFlex = !flexableUsers.isEmpty

        // Pick a consistent motivational message based on competition ID (changes daily)
        let messageIndex: Int = {
            let daysSinceEpoch = Int(Date().timeIntervalSince1970 / 86400)
            let hash = abs(competition.competition_id.hashValue &+ daysSinceEpoch)
            return hash % flexMotivationalMessages.count
        }()

        return VStack(spacing: MADTheme.Spacing.sm) {
            if canFlex {
                // User is leading — show flex options
                VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                    HStack(spacing: MADTheme.Spacing.xs) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 13))
                            .foregroundColor(typeColor)
                        Text("Flex on opponents")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, MADTheme.Spacing.sm)

                    ForEach(flexableUsers, id: \.user_id) { user in
                        FlexUserRow(
                            user: user,
                            typeColor: typeColor,
                            competitionType: competition.type,
                            onFlex: { message, completion in
                                sendFlexToUser(user, message: message, completion: completion)
                            }
                        )
                    }
                }
            } else if !alreadyFlexed.isEmpty {
                // Already flexed on everyone
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green.opacity(0.5))
                    Text("Flexed on \(alreadyFlexed.count) \(alreadyFlexed.count == 1 ? "opponent" : "opponents") today")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.3))
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green.opacity(0.35))
                }
                .padding(MADTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .fill(Color.white.opacity(0.03))
                )
            } else {
                // Not leading — show motivational teaser
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 14))
                        .foregroundColor(typeColor.opacity(0.4))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Flex")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.35))
                        Text(flexMotivationalMessages[messageIndex])
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.25))
                    }

                    Spacer()

                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.15))
                }
                .padding(MADTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .fill(Color.white.opacity(0.02))
                        .overlay(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .stroke(typeColor.opacity(0.08), lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Flex Actions
    func sendFlexToUser(_ user: CompetitionUser, message: String?, completion: ((Bool) -> Void)? = nil) {
        isSendingAction = true
        Task {
            do {
                try await competitionService.sendFlex(
                    competitionId: competition.competition_id,
                    targetUserId: user.user_id,
                    message: message
                )
                await MainActor.run {
                    isSendingAction = false
                    FlexNudgeTracker.markFlexSent(targetUserId: user.user_id)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showActionFeedback(ActionFeedback(icon: "hand.raised.fill", message: "Flexed on \(user.displayName)!", isError: false))
                    completion?(true)
                }
            } catch {
                await MainActor.run {
                    isSendingAction = false
                    let msg = (error as? CompetitionServiceError)?.errorDescription ?? "Could not send flex"
                    showActionFeedback(ActionFeedback(icon: "xmark.circle", message: msg, isError: true))
                    completion?(false)
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

}
