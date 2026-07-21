import SwiftUI
import HealthKit

// MARK: - Dashboard Hero Card

/// THE dashboard card: today's mile and the streak, merged into one hero.
/// Replaces the old StreakCard + TodayProgressCard pair, which showed the
/// same metric twice across two cards.
///
/// State-aware by design:
/// - BEFORE the goal: the ring leads, the Start Mile button is right there —
///   the screen answers "what do I need to do?"
/// - AFTER the goal: the ring seals green, the button disappears, and the
///   streak celebrates — the screen answers "how am I doing?"
struct DashboardHeroCard: View {
    let streak: Int
    let isAtRisk: Bool
    let user: User
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let isGoalCompleted: Bool
    let hasActiveWorkout: Bool
    /// False until today's distance has been freshly fetched this session.
    /// A locked-device launch can serve yesterday's cached value — the card
    /// shows it dimmed as "syncing" instead of asserting a number (or a
    /// completion state) it doesn't actually know yet.
    let distanceIsFresh: Bool
    let fastestPace: TimeInterval
    let mostMiles: Double
    let totalMiles: Double
    @ObservedObject var healthManager: HealthKitManager
    @Binding var showWorkoutView: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateRing = false
    @State private var showingShareSheet = false
    /// Timer-refreshed so the countdown in the status line ticks each minute.
    @State private var timeRemainingText: String = ""
    @State private var timer: Timer?

    private static let narrowDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f
    }()

    private let milestones = [3, 5, 7, 10, 14, 21, 30, 50, 60, 75, 90, 100, 150, 200, 250, 365, 500, 1000]

    /// Backend (workout_splits) is authoritative; HealthKit is fallback only.
    private var bestFastestPace: TimeInterval {
        if fastestPace > 0 { return fastestPace }
        return healthManager.fastestMilePace
    }

    private var nextMilestone: (value: Int, progress: Double, daysToGo: Int)? {
        for milestone in milestones where streak < milestone {
            return (milestone, Double(streak) / Double(milestone), milestone - streak)
        }
        return nil
    }

    /// Completion the card is allowed to CLAIM: never assert "done" off a
    /// stale value (the cached distance can be yesterday's).
    private var trustedDone: Bool { isGoalCompleted && distanceIsFresh }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(eyebrowText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(statusColor.opacity(0.20))
                            .overlay(Capsule().strokeBorder(statusColor.opacity(0.24), lineWidth: 1))
                    )
                if trustedDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.green)
                }
                Spacer()
                // Quiet share affordance; the whole card taps to share.
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35))
            }

            // The two halves: today's ring + the streak.
            heroMainContent

            // Week at a glance.
            weekDotsRow

            // The action — present until the mile is done; "Resume" whenever
            // a workout is live (even post-goal, so it can't be orphaned).
            if !trustedDone || hasActiveWorkout {
                startButton
            }
        }
        .padding(16)
        .background(heroBackground)
        .shadow(color: statusColor.opacity(0.14), radius: 18, x: 0, y: 10)
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 7)
        .contentShape(Rectangle())
        .onTapGesture {
            MADHaptics.action()
            showingShareSheet = true
        }
        .sheet(isPresented: $showingShareSheet) {
            EnhancedShareView(
                user: user,
                currentDistance: currentDistance,
                progress: progress,
                isGoalCompleted: isGoalCompleted,
                fastestPace: bestFastestPace,
                mostMiles: mostMiles,
                totalMiles: totalMiles
            )
        }
        .onAppear {
            updateTimeRemaining()
            startTimer()
            if reduceMotion {
                animateRing = true
            } else {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.1)) {
                    animateRing = true
                }
            }
        }
        .onChange(of: isGoalCompleted) { _, _ in
            updateTimeRemaining()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: - Today ring

    private var todayRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 11)

            Circle()
                .trim(from: 0, to: animateRing ? min(max(progress, trustedDone ? 1 : 0.015), 1) : 0)
                .stroke(
                    LinearGradient(
                        colors: trustedDone
                            ? [Color.green, Color(red: 0.2, green: 0.75, blue: 0.4)]
                            : (isAtRisk
                                ? [Color.red, Color.orange]
                                : [Color(red: 217/255, green: 64/255, blue: 63/255), Color.orange]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: statusColor.opacity(0.35), radius: 7)

            VStack(spacing: 1) {
                Text(String(format: "%.2f", currentDistance))
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .monospacedDigit()
                    // Dimmed while the value is still last-known, not fresh.
                    .foregroundColor(.white.opacity(distanceIsFresh ? 1 : 0.45))
                    .contentTransition(.numericText())
                Text(String(format: "of %.1f mi", goalDistance))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .frame(width: 86, height: 86)
    }

    private var heroMainContent: some View {
        HStack(alignment: .center, spacing: 14) {
            todayRing
                .layoutPriority(1)
            streakBlock
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var streakBlock: some View {
        VStack(alignment: .center, spacing: 8) {
            streakNumber

            statusChips

            if let milestone = nextMilestone {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("Next milestone")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.48))
                        Spacer(minLength: 0)
                        Text(milestone.daysToGo == 1
                             ? "1 day to Day \(milestone.value)"
                             : "\(milestone.daysToGo) days to Day \(milestone.value)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.64))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.yellow, .orange, .red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, milestone.progress * geometry.size.width))
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var streakNumber: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(streak)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Image(systemName: "flame.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [.orange, statusColor], startPoint: .top, endPoint: .bottom)
                )
                .baselineOffset(-4)
        }
    }

    @ViewBuilder
    private var statusChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(statusChipItems.indices, id: \.self) { index in
                    let item = statusChipItems[index]
                    metricChip(icon: item.icon, text: item.text, tint: item.tint)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(statusChipItems.indices, id: \.self) { index in
                    let item = statusChipItems[index]
                    metricChip(icon: item.icon, text: item.text, tint: item.tint)
                }
            }
        }
    }

    private func metricChip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.13)))
    }

    private var statusChipItems: [(icon: String, text: String, tint: Color)] {
        if trustedDone {
            return [("checkmark.circle.fill", "Safe today", .green)]
        }
        if !distanceIsFresh {
            return [("arrow.triangle.2.circlepath", "Syncing today", .orange)]
        }

        let toGo = String(format: "%.2f mi", max(goalDistance - currentDistance, 0))
        let time = formattedTimeOnly
        if time.isEmpty {
            return [("figure.run", "\(toGo) to go", statusColor)]
        }
        return [
            ("figure.run", "\(toGo) to go", statusColor),
            ("clock.fill", "\(time) left", statusColor)
        ]
    }

    // MARK: - Week dots

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        guard let startOfWeek = calendar.date(
            byAdding: .day, value: -(weekday - 1), to: calendar.startOfDay(for: today)
        ) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    private var completedMileDaysThisWeek: Int {
        let calendar = Calendar.current
        return weekDays.filter { date in
            let dateKey = calendar.startOfDay(for: date)
            return healthManager.dailyMileGoals[dateKey] ?? false
        }.count
    }

    private var weekDotsRow: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)

            HStack(spacing: 6) {
                Text("Mile days")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.46))
                    .lineLimit(1)
                Spacer()
                Text("\(completedMileDaysThisWeek) of 7 mile days")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { date in
                    let calendar = Calendar.current
                    let dateKey = calendar.startOfDay(for: date)
                    let completed = healthManager.dailyMileGoals[dateKey] ?? false
                    let isToday = calendar.isDateInToday(date)
                    let isFuture = date > Date()

                    VStack(spacing: 4) {
                        Text(Self.narrowDayFormatter.string(from: date))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))

                        ZStack {
                            Circle()
                                .fill(
                                    completed ? completedMileDayColor :
                                    isFuture ? Color.white.opacity(0.08) :
                                    Color.white.opacity(0.13)
                                )
                                .frame(width: 29, height: 29)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(completed ? 0.16 : 0.05), lineWidth: 1)
                                )

                            if completed {
                                Image(systemName: "figure.run")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }

                            if isToday {
                                Circle()
                                    .stroke(statusColor, lineWidth: 2)
                                    .frame(width: 33, height: 33)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Start / Resume button

    private var startButton: some View {
        Button {
            showWorkoutView = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 32, height: 32)
                    Image(systemName: hasActiveWorkout ? "play.circle.fill" : "play.fill")
                        .font(.system(size: 15, weight: .black))
                        .offset(x: hasActiveWorkout ? 0 : 1)
                }

                Text(hasActiveWorkout ? "Resume Workout" : "Start Mile")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white.opacity(0.72))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.leading, 16)
            .padding(.trailing, 18)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 235/255, green: 68/255, blue: 72/255),
                                Color(red: 198/255, green: 47/255, blue: 53/255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
            .shadow(color: Color(red: 217/255, green: 64/255, blue: 63/255).opacity(0.28), radius: 12, x: 0, y: 7)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var heroBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                statusColor.opacity(0.11),
                                Color(red: 1.0, green: 0.60, blue: 0.20).opacity(trustedDone ? 0.03 : 0.06),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.24 : 0.32),
                                statusColor.opacity(0.16),
                                Color.white.opacity(0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }

    // MARK: - Status

    private var statusColor: Color {
        if trustedDone { return .green }
        if isAtRisk { return .red }
        return .orange
    }

    private var completedMileDayColor: Color {
        Color(red: 0.22, green: 0.74, blue: 0.36)
    }

    private var eyebrowText: String {
        if trustedDone { return "Done today" }
        if isAtRisk { return "Streak at risk" }
        return "Today's mile"
    }

    private var statusIconName: String {
        if trustedDone { return "checkmark.circle.fill" }
        if !distanceIsFresh { return "arrow.triangle.2.circlepath" }
        if isAtRisk { return "exclamationmark.triangle.fill" }
        return "clock.fill"
    }

    /// One merged status line. Reads `timeRemainingText` (the timer-refreshed
    /// @State) — nothing else in body does, and without that dependency
    /// SwiftUI would never re-render on the minute tick.
    private var statusLineText: String {
        if trustedDone { return "Streak safe — see you tomorrow" }
        // Never do arithmetic on a number we don't trust yet.
        if !distanceIsFresh { return "Syncing today's miles…" }
        let toGo = String(format: "%.2f", max(goalDistance - currentDistance, 0))
        let time = timeRemainingText.isEmpty ? "" : formattedTimeOnly
        return time.isEmpty
            ? "\(toGo) mi to go"
            : "\(toGo) mi to go · \(time) left"
    }

    private func updateTimeRemaining() {
        timeRemainingText = trustedDone ? "" : user.formattedTimeUntilReset
    }

    private var formattedTimeOnly: String {
        guard let timeRemaining = user.timeUntilStreakReset else { return "" }
        let hours = Int(timeRemaining) / 3600
        let minutes = Int(timeRemaining) % 3600 / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            updateTimeRemaining()
        }
    }
}
