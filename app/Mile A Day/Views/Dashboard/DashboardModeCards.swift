import SwiftUI
import HealthKit

struct DashboardStartMileButton: View {
    let hasActiveWorkout: Bool
    var prominent: Bool = false
    @Binding var showWorkoutView: Bool

    var body: some View {
        Button {
            showWorkoutView = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 32, height: 32)
                    Image(systemName: hasActiveWorkout ? "play.circle.fill" : "play.fill")
                        .font(.system(size: 14, weight: .black))
                        .offset(x: hasActiveWorkout ? 0 : 1)
                }

                Text(buttonTitle)
                    .font(.system(size: prominent ? 17 : 16, weight: .black, design: .rounded))
                    .tracking(prominent ? 1.2 : 0)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 0)

                Image(systemName: prominent ? "chevron.right" : "arrow.right")
                    .font(.system(size: prominent ? 18 : 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.72))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.leading, 16)
            .padding(.trailing, 18)
            .padding(.vertical, prominent ? 14 : 12)
            .background(
                RoundedRectangle(cornerRadius: prominent ? 16 : 20, style: .continuous)
                    .fill(prominent ? Color(red: 0.78, green: 0.13, blue: 0.30) : Color(red: 0.72, green: 0.12, blue: 0.26))
                    .overlay(
                        RoundedRectangle(cornerRadius: prominent ? 16 : 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .shadow(color: MADTheme.Colors.madRed.opacity(prominent ? 0.18 : 0.12), radius: prominent ? 10 : 8, x: 0, y: prominent ? 5 : 4)
        }
        .buttonStyle(.plain)
    }

    private var buttonTitle: String {
        if prominent {
            return hasActiveWorkout ? "RESUME WORKOUT" : "START MILE"
        }
        return hasActiveWorkout ? "Resume Workout" : "Start Mile"
    }
}

struct DashboardMilestoneBar: View {
    let streak: Int
    var title: String = "Next milestone"

    var body: some View {
        if let milestone = StreakMilestone.next(after: streak) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.56))
                    Spacer(minLength: 0)
                    Text(milestone.daysToGo == 1
                         ? "1 day to Day \(milestone.value)"
                         : "\(milestone.daysToGo) days to Day \(milestone.value)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.70))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.68, blue: 0.14),
                                        Color(red: 1.0, green: 0.34, blue: 0.16),
                                        MADTheme.Colors.madRed
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(5, milestone.progress * geometry.size.width))
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

struct WeekMileDaysRow: View {
    @ObservedObject var healthManager: HealthKitManager
    let statusColor: Color
    var showLabels: Bool = true

    private static let narrowDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f
    }()

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        guard let start = calendar.date(
            byAdding: .day,
            value: -(weekday - 1),
            to: calendar.startOfDay(for: today)
        ) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var completedCount: Int {
        let calendar = Calendar.current
        return weekDays.filter { healthManager.dailyMileGoals[calendar.startOfDay(for: $0)] ?? false }.count
    }

    var body: some View {
        VStack(spacing: 12) {
            if showLabels {
                HStack {
                    Text("Mile days")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(completedCount) of 7 this week")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.58))
                }
            }

            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { date in
                    let calendar = Calendar.current
                    let completed = healthManager.dailyMileGoals[calendar.startOfDay(for: date)] ?? false
                    let isToday = calendar.isDateInToday(date)
                    let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())

                    VStack(spacing: 6) {
                        Text(Self.narrowDayFormatter.string(from: date))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.46))

                        ZStack {
                            Circle()
                                .fill(completed ? Color.green.opacity(0.95) : Color.white.opacity(isFuture ? 0.07 : 0.12))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(Color.white.opacity(completed ? 0.18 : 0.08), lineWidth: 1))

                            if completed {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .black))
                                    .foregroundColor(.white)
                            }

                            if isToday {
                                Circle()
                                    .stroke(statusColor, lineWidth: 2.5)
                                    .frame(width: 39, height: 39)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct ModernDashboardBody: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    let hasActiveWorkout: Bool
    @Binding var showWorkoutView: Bool

    private var state: (distance: Double, goal: Double, progress: Double, completed: Bool) {
        let distance = healthManager.todaysDistance
        let goal = userManager.currentUser.goalMiles
        return (
            distance,
            goal,
            ProgressCalculator.calculateProgress(current: distance, goal: goal),
            ProgressCalculator.isGoalCompleted(current: distance, goal: goal)
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            ModernHeroCard(
                healthManager: healthManager,
                userManager: userManager,
                currentDistance: state.distance,
                goalDistance: state.goal,
                progress: state.progress,
                isGoalCompleted: state.completed,
                hasActiveWorkout: hasActiveWorkout,
                distanceIsFresh: healthManager.hasFreshTodaysDistance,
                showWorkoutView: $showWorkoutView
            )

            DashboardStartMileButton(hasActiveWorkout: hasActiveWorkout, prominent: true, showWorkoutView: $showWorkoutView)

            HStack(alignment: .top, spacing: 12) {
                ModernStepsTile(healthManager: healthManager, userManager: userManager)
                ModernBadgesTile(userManager: userManager, healthManager: healthManager)
            }

            NavigationLink {
                DailyChallengesView(healthManager: healthManager, userManager: userManager)
            } label: {
                ModernChallengeRow(healthManager: healthManager, userManager: userManager)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 100)
    }
}

struct FunDashboardBody: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @ObservedObject var friendService: FriendService
    let hasActiveWorkout: Bool
    @Binding var showWorkoutView: Bool

    private var state: (distance: Double, goal: Double, progress: Double, completed: Bool) {
        let distance = healthManager.todaysDistance
        let goal = userManager.currentUser.goalMiles
        return (
            distance,
            goal,
            ProgressCalculator.calculateProgress(current: distance, goal: goal),
            ProgressCalculator.isGoalCompleted(current: distance, goal: goal)
        )
    }

    var body: some View {
        VStack(spacing: 18) {
            FlameBuddyHeroCard(
                healthManager: healthManager,
                userManager: userManager,
                currentDistance: state.distance,
                goalDistance: state.goal,
                progress: state.progress,
                isGoalCompleted: state.completed,
                hasActiveWorkout: hasActiveWorkout,
                distanceIsFresh: healthManager.hasFreshTodaysDistance,
                showWorkoutView: $showWorkoutView
            )

            FunStartCard(
                trustedDone: state.completed && healthManager.hasFreshTodaysDistance,
                hasActiveWorkout: hasActiveWorkout,
                showWorkoutView: $showWorkoutView
            )

            HStack(alignment: .top, spacing: 12) {
                ModernStepsTile(healthManager: healthManager, userManager: userManager)
                ModernBadgesTile(userManager: userManager, healthManager: healthManager)
            }

            StreakTokensCard()

            NavigationLink {
                DailyChallengesView(healthManager: healthManager, userManager: userManager)
            } label: {
                DailyChallengeCard(healthManager: healthManager, userManager: userManager)
            }
            .buttonStyle(.plain)

            FriendActivityStripView(friendService: friendService)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 100)
    }

    private var statusColor: Color {
        if state.completed && healthManager.hasFreshTodaysDistance { return .green }
        if userManager.currentUser.isStreakAtRisk { return .red }
        return .orange
    }
}

private struct ModernHeroCard: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let isGoalCompleted: Bool
    let hasActiveWorkout: Bool
    let distanceIsFresh: Bool
    @Binding var showWorkoutView: Bool

    @State private var showTokens = false
    @State private var timeRemainingText = ""
    @State private var timer: Timer?
    @ObservedObject private var tokensState = StreakTokensState.shared

    private var trustedDone: Bool { isGoalCompleted && distanceIsFresh }
    private var flameHealth: FlameHealth {
        FlameHealth.forState(
            isCompleted: isGoalCompleted,
            distanceIsFresh: distanceIsFresh,
            isAtRisk: userManager.currentUser.isStreakAtRisk,
            secondsToReset: secondsUntilLocalMidnight,
            streak: userManager.currentUser.streak
        )
    }

    private var flamePhase: StreakFlamePhase {
        StreakFlamePhase.forState(
            isCompleted: isGoalCompleted,
            distanceIsFresh: distanceIsFresh,
            streak: userManager.currentUser.streak
        )
    }

    private var statusColor: Color {
        if trustedDone { return .green }
        if userManager.currentUser.isStreakAtRisk { return MADTheme.Colors.madRed }
        return .orange
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    ProfessionalFlameView(
                        phase: flamePhase,
                        health: flameHealth,
                        size: 166,
                        ringProgress: timeLeftRingProgress,
                        dayEnd: StreakFlameClock.nextLocalMidnight(),
                        coalWarmth: min(progress, 1)
                    )

                    VStack(spacing: 0) {
                        Text("\(userManager.currentUser.streak)")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.72), radius: 5, x: 0, y: 2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.60)
                        Text("DAYS")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .tracking(1.1)
                            .foregroundColor(.white.opacity(0.88))
                            .shadow(color: .black.opacity(0.72), radius: 4, x: 0, y: 2)
                    }
                    .offset(y: 39)
                }
                .frame(width: 172, height: 176)
                .layoutPriority(1)

                VStack(spacing: 0) {
                    ModernHeroStatLine(
                        icon: "figure.run",
                        value: String(format: "%.2f", currentDistance),
                        unit: "mi",
                        label: "Mileage",
                        tint: MADTheme.Colors.madRed
                    )
                    ModernHeroDivider()
                    ModernHeroStatLine(
                        icon: "shoeprints.fill",
                        value: healthManager.todaysSteps.formatted(),
                        unit: "steps",
                        label: "Steps",
                        tint: stepTint
                    )
                    ModernHeroDivider()
                    if let pace = healthManager.todaysFastestPace {
                        ModernHeroStatLine(
                            icon: "timer",
                            value: formatPace(pace),
                            unit: "/mi",
                            label: "Best pace",
                            tint: MADTheme.Colors.walkBlue
                        )
                    } else {
                        ModernHeroStatLine(
                            icon: "clock.fill",
                            value: formattedTimeOnly.isEmpty ? "--" : formattedTimeOnly,
                            unit: "left",
                            label: "Left today",
                            tint: statusColor
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }

            DashboardMilestoneBar(streak: userManager.currentUser.streak, title: "Next milestone")
        }
        .padding(18)
        .padding(.top, 20)
        .background(heroBackground)
        .overlay(alignment: .topTrailing) {
            tokensChip
                .padding(14)
        }
        .sheet(isPresented: $showTokens) {
            StreakTokensDetailView()
        }
        .onAppear {
            updateTimeRemaining()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in updateTimeRemaining() }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Image(systemName: trustedDone ? "checkmark.circle.fill" : userManager.currentUser.isStreakAtRisk ? "exclamationmark.triangle.fill" : "flame.fill")
                .font(.system(size: 12, weight: .bold))
            Text(statusText)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .lineLimit(1)
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(statusColor.opacity(0.13)))
        .overlay(Capsule().strokeBorder(statusColor.opacity(0.22), lineWidth: 1))
    }

    private var tokensChip: some View {
        Button {
            showTokens = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 11, weight: .bold))
                Text("\(readyTokens)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text(readyTokens == 1 ? "saver" : "savers")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.white.opacity(0.88))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.cyan.opacity(0.10)))
            .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(readyTokens) streak savers ready")
    }

    private var readyTokens: Int {
        guard let payload = tokensState.payload else { return 0 }
        return [payload.double_down.held, payload.streak_save.held, payload.streak_assist.held].filter { $0 }.count
    }

    private var statusText: String {
        if trustedDone { return "Done today" }
        if !distanceIsFresh { return "Syncing today" }
        if userManager.currentUser.isStreakAtRisk { return "Streak at risk" }
        return timeRemainingText.isEmpty ? "Today's mile" : "\(formattedTimeOnly) left"
    }

    private var formattedTimeOnly: String {
        let remaining = secondsUntilLocalMidnight
        let hours = Int(remaining) / 3600
        let minutes = Int(remaining) % 3600 / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func updateTimeRemaining() {
        timeRemainingText = trustedDone ? "" : userManager.currentUser.formattedTimeUntilReset
    }

    private var milestoneCaption: String {
        guard let next = StreakMilestone.next(after: userManager.currentUser.streak) else {
            return "Legend status"
        }
        return "\(next.daysToGo) to Day \(next.value)"
    }

    private var stepTint: Color {
        if healthManager.todaysSteps >= 10000 { return MADTheme.Colors.success }
        if healthManager.todaysSteps >= 7500 { return MADTheme.Colors.warning }
        if healthManager.todaysSteps >= 5000 { return .yellow }
        return .orange
    }

    private func formatPace(_ pace: TimeInterval) -> String {
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var modernProgressLine: some View {
        GeometryReader { geo in
            let next = StreakMilestone.next(after: userManager.currentUser.streak)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(statusColor)
                    .frame(width: max(5, geo.size.width * CGFloat(next?.progress ?? progress)))
            }
        }
        .frame(height: 5)
    }

    private var timeLeftRingProgress: Double {
        guard !trustedDone else { return 1.0 }
        let secondsInDay: TimeInterval = 24 * 60 * 60
        return max(0.025, min(secondsUntilLocalMidnight / secondsInDay, 1.0))
    }

    private var secondsUntilLocalMidnight: TimeInterval {
        let now = Date()
        guard let nextMidnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else {
            return userManager.currentUser.timeUntilStreakReset ?? 0
        }
        return max(0, nextMidnight.timeIntervalSince(now))
    }

    private var heroBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.095), lineWidth: 1)
            )
    }
}

private struct ModernHeroStatLine: View {
    let icon: String
    let value: String
    let unit: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.13)))

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.60)
                    Text(unit)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(1)
                }

                Text(label)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

private struct ModernHeroDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 38)
    }
}

private struct ModernMetricPill: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.42))
                Text(value)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.92))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
}

private struct ModernStepsTile: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager

    private var steps: Int { healthManager.todaysSteps }
    private var progress: Double { min(Double(steps) / 10000.0, 1) }
    private var tint: Color { steps >= 10000 ? .green : .orange }

    var body: some View {
        NavigationLink {
            StepsView(healthManager: healthManager, userManager: userManager)
        } label: {
            ModernTile(icon: "shoeprints.fill", title: "Steps", value: steps.formatted(), subtitle: "\(Int(progress * 100))% of 10k", tint: tint) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 5)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(tint)
                                .frame(width: max(5, geo.size.width * progress), height: 5)
                        }
                    }
            }
            .frame(height: 168, alignment: .topLeading)
        }
        .buttonStyle(.plain)
    }
}

private struct ModernBadgesTile: View {
    @ObservedObject var userManager: UserManager
    @ObservedObject var healthManager: HealthKitManager

    private var earned: Int {
        userManager.currentUser.badges.filter { !$0.isLocked }.count
    }

    private var total: Int {
        userManager.currentUser.getAllBadges().count
    }

    private var progress: Double {
        total > 0 ? Double(earned) / Double(total) : 0
    }

    private var remaining: Int {
        max(total - earned, 0)
    }

    private var recentUnlocked: [Badge] {
        userManager.currentUser.badges
            .filter { !$0.isLocked }
            .sorted { $0.dateAwarded > $1.dateAwarded }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        NavigationLink {
            BadgesView(userManager: userManager, initialBadge: nil)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    medalPreviewStrip
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.28))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Medals")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.48))
                    Text("\(earned)/\(total)")
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(Int(progress * 100))% unlocked")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(.yellow)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.10))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.84, blue: 0.22),
                                            Color(red: 1.0, green: 0.55, blue: 0.08)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, geo.size.width * progress))
                        }
                    }
                    .frame(height: 6)

                    Text(remaining == 0 ? "Collection complete" : "\(remaining) left to collect")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.46))
                    .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 168, maxHeight: 168, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var medalPreviewStrip: some View {
        HStack(spacing: -6) {
            if recentUnlocked.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                }
            } else {
                ForEach(Array(recentUnlocked.enumerated()), id: \.element.id) { index, badge in
                    MedalView(badge: badge, size: 38, showShimmer: index == 0)
                        .frame(width: 38, height: 38)
                        .zIndex(Double(3 - index))
                }
            }
        }
        .frame(height: 40)
        .accessibilityLabel(recentUnlocked.isEmpty ? "No medals unlocked yet" : "Recent unlocked medals")
    }
}

private struct ModernMilestoneCard: View {
    let streak: Int

    var body: some View {
        DashboardMilestoneBar(streak: streak, title: "Next milestone")
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            )
    }
}

private struct ModernTile<Accessory: View>: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let tint: Color
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tint.opacity(0.15)))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.28))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.48))
                Text(value)
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            accessory()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 168, maxHeight: 168, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        )
    }
}

private struct ModernChallengeRow: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @State private var todaysChallenge: DailyChallenge?
    @State private var tomorrowsChallenge: DailyChallenge?
    @State private var challengeProgressValue: Double = 0
    @State private var isCompleted = false
    @State private var opponent: ChallengeOpponent?

    private var primaryColor: Color {
        todaysChallenge?.gradient.first ?? .green
    }

    private var accentColor: Color {
        isCompleted ? .green : primaryColor
    }

    var body: some View {
        Group {
            if let challenge = todaysChallenge {
                challengeRow(challenge)
            } else {
                placeholderRow
            }
        }
        .task(id: userManager.currentUser.backendUserId) {
            guard let userId = userManager.currentUser.backendUserId else { return }
            await ChallengeService.refresh(userId: userId)
            refreshFromService()
        }
        .onReceive(NotificationCenter.default.publisher(for: ChallengeService.changedNotification)) { _ in
            refreshFromService()
        }
        .onAppear {
            refreshFromService()
        }
    }

    private func challengeRow(_ challenge: DailyChallenge) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                challengeIcon(challenge)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Challenge")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(accentColor)

                    Text(isCompleted ? "\(challenge.title) complete" : challenge.title)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(challenge.description)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.54))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.30))
            }

            progressRow

            if challenge.key == "head_to_head", let opponent {
                HeadToHeadStrip(opponent: opponent, accent: accentColor)
            }

            tomorrowRow
        }
        .padding(14)
        .background(rowBackground)
    }

    private var placeholderRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "flag.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.green)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.green.opacity(0.13)))

            VStack(alignment: .leading, spacing: 3) {
                Text("Daily Challenge")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Loading today's challenge")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.48))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.30))
        }
        .padding(14)
        .background(rowBackground)
    }

    private func challengeIcon(_ challenge: DailyChallenge) -> some View {
        Image(systemName: isCompleted ? "checkmark" : challenge.icon)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(accentColor)
            .frame(width: 38, height: 38)
            .background(Circle().fill(accentColor.opacity(0.14)))
            .overlay(Circle().strokeBorder(accentColor.opacity(0.20), lineWidth: 1))
    }

    private var progressRow: some View {
        let progress = min(challengeProgressValue, 1.0)
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(accentColor)
                        .frame(width: max(6, geo.size.width * progress))
                }
            }
            .frame(height: 6)

            HStack {
                Text(isCompleted ? "Locked in" : progressLabel(progress))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
                Spacer()
                Text("\(Int(round(progress * 100)))%")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.58))
            }
        }
    }

    @ViewBuilder
    private var tomorrowRow: some View {
        if let tomorrow = tomorrowsChallenge {
            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.42))
                Text("Tomorrow")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.48))
                HStack(spacing: 5) {
                    Image(systemName: tomorrow.icon)
                        .font(.system(size: 10, weight: .bold))
                    Text(tomorrow.title)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(tomorrow.gradient.first ?? .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill((tomorrow.gradient.first ?? .orange).opacity(0.13)))
                Spacer(minLength: 0)
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
            )
    }

    private func progressLabel(_ value: Double) -> String {
        if value <= 0 { return "Start today's effort" }
        if value < 0.5 { return "Building progress" }
        if value < 0.85 { return "Closing in" }
        return "Almost there"
    }

    private func refreshFromService() {
        if let remote = ChallengeService.shared as? RemoteChallengeService {
            todaysChallenge = remote.todayChallenge
            tomorrowsChallenge = remote.tomorrowChallenge
            challengeProgressValue = remote.todayProgress
            isCompleted = remote.todayCompleted
            opponent = remote.todayOpponent
        }
    }
}

private struct FlameBuddyHeroCard: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let isGoalCompleted: Bool
    let hasActiveWorkout: Bool
    let distanceIsFresh: Bool
    @Binding var showWorkoutView: Bool

    @State private var timeRemainingText = ""
    @State private var timer: Timer?
    @State private var showShareSheet = false
    @State private var showTokens = false
    @ObservedObject private var tokensState = StreakTokensState.shared

    private var trustedDone: Bool { isGoalCompleted && distanceIsFresh }
    private var health: FlameHealth {
        FlameHealth.forState(
            isCompleted: isGoalCompleted,
            distanceIsFresh: distanceIsFresh,
            isAtRisk: userManager.currentUser.isStreakAtRisk,
            secondsToReset: userManager.currentUser.timeUntilStreakReset,
            streak: userManager.currentUser.streak
        )
    }

    private var flamePhase: StreakFlamePhase {
        StreakFlamePhase.forState(
            isCompleted: isGoalCompleted,
            distanceIsFresh: distanceIsFresh,
            streak: userManager.currentUser.streak
        )
    }

    private var statusColor: Color {
        if trustedDone { return .green }
        if userManager.currentUser.isStreakAtRisk { return MADTheme.Colors.madRed }
        return .orange
    }

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                let leftWidth = geo.size.width * 0.48
                let rightWidth = geo.size.width - leftWidth - 12
                let buddySize = min(max(leftWidth * 1.14, 176), min(216, geo.size.height * 0.90))

                HStack(alignment: .top, spacing: 12) {
                    ZStack(alignment: .top) {
                        FlameBuddyView(
                            health: health,
                            size: buddySize,
                            phase: flamePhase,
                            dayEnd: StreakFlameClock.nextLocalMidnight(),
                            coalWarmth: min(progress, 1)
                        )
                        .frame(width: buddySize * 1.50, height: buddySize * 1.34)
                        .offset(y: -28)

                        FunHeroGround()
                            .frame(width: buddySize * 1.26, height: 28)
                            .offset(y: geo.size.height - 46)
                    }
                    .frame(width: leftWidth, height: geo.size.height, alignment: .top)

                    funStatRows
                        .padding(.top, 34)
                        .frame(width: rightWidth, height: geo.size.height, alignment: .top)
                }
            }
            .frame(height: 242)

            DashboardMilestoneBar(streak: userManager.currentUser.streak)
                .padding(.horizontal, 2)
        }
        .padding(18)
        .padding(.top, 18)
        .background(cardBackground)
        .overlay(alignment: .topTrailing) {
            tokensChip
                .padding(14)
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture {
            MADHaptics.action()
            showShareSheet = true
        }
        .sheet(isPresented: $showShareSheet) {
            EnhancedShareView(
                user: userManager.currentUser,
                currentDistance: currentDistance,
                progress: progress,
                isGoalCompleted: isGoalCompleted,
                fastestPace: bestFastestPace,
                mostMiles: healthManager.cachedCurrentStreakStats.mostMiles > 0
                    ? healthManager.cachedCurrentStreakStats.mostMiles
                    : healthManager.mostMilesInOneDay,
                totalMiles: healthManager.totalLifetimeMiles
            )
        }
        .sheet(isPresented: $showTokens) {
            StreakTokensDetailView()
        }
        .onAppear {
            updateTimeRemaining()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in updateTimeRemaining() }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var streakHeadline: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("\(userManager.currentUser.streak)")
                .font(.system(size: 35, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.40), radius: 4, x: 0, y: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Rectangle()
                .fill(statusColor.opacity(0.45))
                .frame(width: 1, height: 26)

            Text("Day Streak")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundColor(statusColor)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(statusColor.opacity(0.20), lineWidth: 1)
                )
        )
    }

    private var tokensChip: some View {
        Button {
            showTokens = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 11, weight: .bold))
                Text("\(readyTokens)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text(readyTokens == 1 ? "saver" : "savers")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.white.opacity(0.90))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.green.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Color.green.opacity(0.26), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(readyTokens) streak savers ready")
    }

    private var readyTokens: Int {
        guard let payload = tokensState.payload else { return 0 }
        return [payload.double_down.held, payload.streak_save.held, payload.streak_assist.held].filter { $0 }.count
    }

    private var heroStats: some View {
        VStack(spacing: 12) {
            if !trustedDone {
                statusBadge
            }

            VStack(spacing: 2) {
                Text("\(userManager.currentUser.streak)")
                    .font(.system(size: 70, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.50)
                Text("Day Streak")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundColor(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) { heroChips }
                VStack(spacing: 8) { heroChips }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var funStatRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            streakHeadline
                .padding(.bottom, 8)
            HStack {
                Spacer(minLength: 0)
                statusBadge
                Spacer(minLength: 0)
            }
            .padding(.bottom, 10)

            ModernHeroStatLine(
                icon: "figure.run",
                value: String(format: "%.2f", currentDistance),
                unit: "mi",
                label: trustedDone ? "Logged" : "Mileage",
                tint: MADTheme.Colors.madRed
            )
            ModernHeroDivider()
            ModernHeroStatLine(
                icon: trustedDone ? "checkmark.circle.fill" : "clock.fill",
                value: trustedDone ? "Done" : (formattedTimeOnly.isEmpty ? "--" : formattedTimeOnly),
                unit: trustedDone ? "" : "left",
                label: trustedDone ? "Safe" : "Left today",
                tint: statusColor
            )
        }
    }

    @ViewBuilder
    private var heroChips: some View {
        ModernMetricPill(
            icon: trustedDone ? "checkmark.circle.fill" : "figure.run",
            title: trustedDone ? "Logged" : "To go",
            value: trustedDone ? "\(String(format: "%.2f", currentDistance)) mi" : "\(String(format: "%.2f", max(goalDistance - currentDistance, 0))) mi",
            tint: trustedDone ? .green : statusColor
        )
        ModernMetricPill(
            icon: "clock.fill",
            title: trustedDone ? "Safe" : "Left today",
            value: trustedDone ? "Done" : (formattedTimeOnly.isEmpty ? "--" : formattedTimeOnly),
            tint: trustedDone ? .green : statusColor
        )
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: trustedDone ? "checkmark.circle.fill" : userManager.currentUser.isStreakAtRisk ? "exclamationmark.circle.fill" : "flame.fill")
                .font(.system(size: 12, weight: .bold))
            Text(statusText)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(statusColor.opacity(0.17)))
        .overlay(Capsule().strokeBorder(statusColor.opacity(0.26), lineWidth: 1))
    }

    private var statusText: String {
        if trustedDone { return "Streak safe" }
        if !distanceIsFresh { return "Syncing" }
        if userManager.currentUser.isStreakAtRisk { return "Streak at risk" }
        return "Keep it alive"
    }

    private var formattedTimeOnly: String {
        _ = timeRemainingText
        guard let remaining = userManager.currentUser.timeUntilStreakReset else { return "" }
        let hours = Int(remaining) / 3600
        let minutes = Int(remaining) % 3600 / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private var stepTint: Color {
        if healthManager.todaysSteps >= 10000 { return MADTheme.Colors.success }
        if healthManager.todaysSteps >= 7500 { return MADTheme.Colors.warning }
        if healthManager.todaysSteps >= 5000 { return .yellow }
        return .orange
    }

    private func updateTimeRemaining() {
        timeRemainingText = trustedDone ? "" : userManager.currentUser.formattedTimeUntilReset
    }

    private var bestFastestPace: TimeInterval {
        userManager.currentUser.fastestMilePace > 0 ? userManager.currentUser.fastestMilePace : healthManager.fastestMilePace
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.070, green: 0.065, blue: 0.070))

            FunHeroEmbers(tint: statusColor)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .opacity(0.45)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 18, x: 0, y: 10)
    }
}

private struct FunHeroGround: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.orange.opacity(0.22),
                            Color.black.opacity(0.34),
                            Color.black.opacity(0.02)
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 72
                    )
                )
                .blur(radius: 5)
                .frame(height: 18)
            HStack(alignment: .bottom, spacing: -4) {
                ForEach(0..<9, id: \.self) { index in
                    FunGroundRock(slant: CGFloat([-0.20, 0.28, -0.12, 0.18, -0.24, 0.20, -0.16, 0.26, -0.10][index]))
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(index.isMultiple(of: 2) ? 0.40 : 0.28),
                                Color(red: 0.16, green: 0.055, blue: 0.045).opacity(0.70)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: CGFloat([22, 16, 27, 18, 25, 15, 22, 17, 20][index]), height: CGFloat([18, 10, 23, 13, 20, 9, 17, 12, 15][index]))
                }
            }
        }
    }
}

private struct FunGroundRock: Shape {
    let slant: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topLeft = CGPoint(x: rect.minX + rect.width * max(0.08, 0.20 + slant), y: rect.minY)
        let topRight = CGPoint(x: rect.maxX - rect.width * max(0.08, 0.18 - slant), y: rect.minY + rect.height * 0.05)

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.minY + rect.height * 0.34))
        path.addQuadCurve(to: topLeft, control: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.08))
        path.addLine(to: topRight)
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.38), control: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct FunHeroEmbers: View {
    let tint: Color

    private let embers: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = [
        (0.11, 0.18, 3, 0.34),
        (0.24, 0.28, 2, 0.24),
        (0.38, 0.15, 3, 0.30),
        (0.68, 0.20, 2, 0.20),
        (0.84, 0.32, 2, 0.18)
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(embers.indices, id: \.self) { index in
                Capsule()
                    .fill(index.isMultiple(of: 2) ? Color.orange.opacity(0.84) : tint.opacity(0.72))
                    .frame(width: embers[index].size, height: embers[index].size * 2.4)
                    .blur(radius: 0.2)
                    .rotationEffect(.degrees(Double(index * 26 - 18)))
                    .opacity(embers[index].opacity)
                    .position(x: geo.size.width * embers[index].x, y: geo.size.height * embers[index].y)
            }
        }
    }
}

private struct FunStartCard: View {
    let trustedDone: Bool
    let hasActiveWorkout: Bool
    @Binding var showWorkoutView: Bool

    var body: some View {
        DashboardStartMileButton(hasActiveWorkout: hasActiveWorkout, prominent: true, showWorkoutView: $showWorkoutView)
    }
}
