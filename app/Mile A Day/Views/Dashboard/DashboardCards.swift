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
        VStack(spacing: 16) {
            // Eyebrow — one state word for the whole card.
            HStack(spacing: 6) {
                Text(eyebrowText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(1.2)
                    .foregroundColor(statusColor)
                if trustedDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                Spacer()
                // Quiet share affordance; the whole card taps to share.
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35))
            }

            // The two halves: today's ring + the streak.
            HStack(spacing: 20) {
                todayRing

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(streak)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .contentTransition(.numericText())
                        Image(systemName: "flame.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(statusColor)
                    }

                    Text("DAY STREAK")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundColor(.white.opacity(0.5))

                    // One status line — distance-to-go and time-left merged.
                    HStack(spacing: 5) {
                        Image(systemName: statusIconName)
                            .font(.system(size: 11, weight: .bold))
                        Text(statusLineText)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundColor(statusColor)

                    // Slim milestone row.
                    if let milestone = nextMilestone {
                        HStack(spacing: 8) {
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

                            Text("Day \(milestone.value) in \(milestone.daysToGo)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                                .layoutPriority(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Week at a glance.
            weekDotsRow

            // The action — present until the mile is done; "Resume" whenever
            // a workout is live (even post-goal, so it can't be orphaned).
            if !trustedDone || hasActiveWorkout {
                startButton
            }
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [statusColor.opacity(0.05), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.2 : 0.3),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
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
                .stroke(Color.white.opacity(0.10), lineWidth: 9)

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
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text(String(format: "%.2f", currentDistance))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    // Dimmed while the value is still last-known, not fresh.
                    .foregroundColor(.white.opacity(distanceIsFresh ? 1 : 0.45))
                    .contentTransition(.numericText())
                Text(String(format: "of %.1f mi", goalDistance))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .frame(width: 104, height: 104)
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

    private var weekDotsRow: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)

            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { date in
                    let calendar = Calendar.current
                    let dateKey = calendar.startOfDay(for: date)
                    let completed = healthManager.dailyMileGoals[dateKey] ?? false
                    let isToday = calendar.isDateInToday(date)
                    let isFuture = date > Date()

                    VStack(spacing: 4) {
                        Text(Self.narrowDayFormatter.string(from: date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))

                        ZStack {
                            Circle()
                                .fill(
                                    completed ? Color.green.opacity(0.8) :
                                    isFuture ? Color.white.opacity(0.08) :
                                    Color.white.opacity(0.15)
                                )
                                .frame(width: 26, height: 26)

                            if completed {
                                Image(systemName: "figure.run")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }

                            if isToday {
                                Circle()
                                    .stroke(statusColor, lineWidth: 2)
                                    .frame(width: 30, height: 30)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Start / Resume button

    private var startButton: some View {
        Button {
            showWorkoutView = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: hasActiveWorkout ? "play.circle.fill" : "play.fill")
                    .font(.title3)
                Text(hasActiveWorkout ? "Resume Workout" : "Start Mile")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 217/255, green: 64/255, blue: 63/255),
                                Color(red: 180/255, green: 50/255, blue: 50/255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: Color(red: 217/255, green: 64/255, blue: 63/255).opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Status

    private var statusColor: Color {
        if trustedDone { return .green }
        if isAtRisk { return .red }
        return .orange
    }

    private var eyebrowText: String {
        if trustedDone { return "DONE FOR TODAY" }
        if isAtRisk { return "STREAK AT RISK" }
        return "TODAY'S MILE"
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
