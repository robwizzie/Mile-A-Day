import SwiftUI
import HealthKit

// MARK: - Updated Card Components

struct StreakCard: View {
    let streak: Int
    let isActiveToday: Bool
    let isAtRisk: Bool
    let user: User
    let progress: Double
    let isGoalCompleted: Bool
    let isRefreshing: Bool
    let currentDistance: Double
    let fastestPace: TimeInterval
    let mostMiles: Double
    let totalMiles: Double
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateStreak = false
    @State private var animateFire = false
    @State private var animateUrgency = false
    @State private var showingShareSheet = false
    @State private var timeRemainingText: String = ""
    @State private var timer: Timer?

    private static let narrowDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f
    }()

    // Streak milestone milestones
    private let milestones = [3, 5, 7, 10, 14, 21, 30, 50, 60, 75, 90, 100, 150, 200, 250, 365, 500, 1000]

    /// Backend (workout_splits) is authoritative; HealthKit is fallback only
    private var bestFastestPace: TimeInterval {
        if fastestPace > 0 { return fastestPace }
        return healthManager.fastestMilePace
    }

    private var nextMilestone: (value: Int, progress: Double, daysToGo: Int)? {
        for milestone in milestones {
            if streak < milestone {
                let progressToMilestone = Double(streak) / Double(milestone)
                let daysToGo = milestone - streak
                return (milestone, progressToMilestone, daysToGo)
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 16) {
            // Top section: Streak info and fire icon
            HStack(spacing: 20) {
                // Left side: Streak info
                VStack(alignment: .leading, spacing: 8) {
                    // CURRENT STREAK header
                    Text("CURRENT STREAK")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(statusColor)
                        .tracking(1.2)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(streak)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .contentTransition(.numericText())

                        Text(streak == 1 ? "day" : "days")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    // One status line — completion, distance-to-go, and
                    // time-left merged into a single caption instead of
                    // three stacked fragments (calm-pass density cut).
                    HStack(spacing: 5) {
                        Image(systemName: statusIconName)
                            .font(.system(size: 12, weight: .bold))
                        Text(statusLineText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundColor(statusColor)
                }

                Spacer()

                // Right side: Flame icon - consistent colors based on status
                ZStack {
                    if isGoalCompleted {
                        // Flat completed state: one tinted disc + a gently
                        // breathing flame. The old animated radial glow ring
                        // was pure ornament — cut in the calm pass.
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        statusColor.opacity(0.5),
                                        statusColor.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 70, height: 70)

                        Image(systemName: "flame.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [statusColor, statusColor.opacity(0.8), statusColor.opacity(0.6)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .scaleEffect(animateFire ? 1.08 : 1.0)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: animateFire)
                            .shadow(color: statusColor.opacity(0.5), radius: animateFire ? 9 : 6)
                    } else if isAtRisk {
                        let countdownProgress: Double = {
                            guard let remaining = user.timeUntilStreakReset else { return 0 }
                            // 6 hours = 21600 seconds (from 6pm to midnight)
                            return min(remaining / 21600, 1.0)
                        }()

                        // At-risk: countdown ring around the flame. The time
                        // itself lives in the status line on the left now —
                        // no duplicate label under the ring.
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.1))
                                .frame(width: 70, height: 70)

                            Circle()
                                .trim(from: 0, to: countdownProgress)
                                .stroke(
                                    LinearGradient(
                                        colors: [.red, .orange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                )
                                .frame(width: 74, height: 74)
                                .rotationEffect(.degrees(-90))

                            Image(systemName: "flame.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.red.opacity(0.8))
                                .scaleEffect(animateUrgency ? 1.05 : 0.95)
                                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animateUrgency)
                        }
                    } else {
                        // Default: not completed, not at risk
                        Circle()
                            .fill(statusColor.opacity(0.1))
                            .frame(width: 70, height: 70)

                        Image(systemName: "flame.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }

            // Milestone — one slim row (bar + tiny caption) instead of the
            // old two-line header + thick bar block.
            if let milestone = nextMilestone {
                HStack(spacing: 10) {
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
                                .frame(width: max(5, milestone.progress * geometry.size.width))
                                .animation(.easeOut(duration: 0.8), value: milestone.progress)
                        }
                    }
                    .frame(height: 5)

                    Text("Day \(milestone.value) in \(milestone.daysToGo)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .layoutPriority(1)
                }
            }

            // Compact week-at-a-glance row
            compactWeekRow
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .background(
            ZStack {
                // Liquid glass background
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)

                // Gradient overlay - consistent with status color
                LinearGradient(
                    colors: [
                        statusColor.opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Glass border
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
        .overlay(alignment: .topTrailing) {
            // Quiet share affordance — replaces the old check/clock cluster
            // (both merged into the status line) and the full-width
            // "Tap to share" hint row.
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
                .padding(.top, 20)
                .padding(.trailing, 20)
        }
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .onAppear {
            updateTimeRemaining()
            startTimer()
            // Start fire animation only if goal is completed (and the user
            // hasn't asked the system for reduced motion).
            if isGoalCompleted && !reduceMotion {
                animateFire = true
            } else {
                animateFire = false
            }
            // Start urgency pulse if at risk.
            // Deferred one runloop tick so the layout shift from setting
            // `timeRemainingText` above has rendered first — otherwise the
            // `.animation(_:value:)` on the flame Image catches the position
            // change and oscillates the flame diagonally forever.
            if isAtRisk && !isGoalCompleted && !reduceMotion {
                DispatchQueue.main.async {
                    animateUrgency = true
                }
            }
        }
        .onChange(of: isGoalCompleted) { oldValue, newValue in
            updateTimeRemaining()
            if newValue && !oldValue && !reduceMotion {
                // Start fire animation when goal completed
                animateFire = true
            } else if !newValue {
                // Stop animation when goal not completed
                animateFire = false
            }
        }
        .onChange(of: user.formattedTimeUntilReset) { _, _ in
            updateTimeRemaining()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
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
    }

    // MARK: - Compact Week Row

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromSunday = weekday - 1
        guard let startOfWeek = calendar.date(byAdding: .day, value: -daysFromSunday, to: calendar.startOfDay(for: today)) else {
            return []
        }
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startOfWeek)
        }
    }

    private var compactWeekRow: some View {
        VStack(spacing: 8) {
            // Thin separator
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)

            // Week dots row
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { date in
                    let calendar = Calendar.current
                    let dateKey = calendar.startOfDay(for: date)
                    let completed = healthManager.dailyMileGoals[dateKey] ?? false
                    let isToday = calendar.isDateInToday(date)
                    let isFuture = date > Date()
                    let dayLetter = Self.narrowDayFormatter.string(from: date)

                    VStack(spacing: 4) {
                        Text(dayLetter)
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

    private func updateTimeRemaining() {
        if !isGoalCompleted {
            timeRemainingText = user.formattedTimeUntilReset
        } else {
            timeRemainingText = ""
        }
    }

    // Format time without "remaining" text
    private var formattedTimeOnly: String {
        guard let timeRemaining = user.timeUntilStreakReset else {
            return ""
        }

        let hours = Int(timeRemaining) / 3600
        let minutes = Int(timeRemaining) % 3600 / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            updateTimeRemaining()
        }
    }

    // Consistent status color based on completion and risk
    private var statusColor: Color {
        if isGoalCompleted {
            return .green  // Green when completed
        } else if isAtRisk {
            return .red    // Red when at risk (close to expiring)
        } else {
            return .orange  // Orange when not completed but not at risk
        }
    }

    private var statusIconName: String {
        if isGoalCompleted { return "checkmark.circle.fill" }
        if isAtRisk { return "exclamationmark.triangle.fill" }
        return "clock.fill"
    }

    /// The merged single-line status: completion / distance-to-go / time-left.
    /// Reads `timeRemainingText` (the timer-refreshed @State) — nothing else
    /// in body does anymore, and without that dependency SwiftUI would never
    /// re-render on the minute tick and the countdown would freeze.
    private var statusLineText: String {
        if isGoalCompleted { return "Done for today" }
        let toGo = String(format: "%.2f", max(user.goalMiles - currentDistance, 0))
        let time = timeRemainingText.isEmpty ? "" : formattedTimeOnly
        if isAtRisk {
            return time.isEmpty
                ? "At risk — \(toGo) mi to go"
                : "At risk — \(toGo) mi to go · \(time) left"
        }
        return time.isEmpty
            ? "\(toGo) mi to go"
            : "\(toGo) mi to go · \(time) left"
    }
}

struct TodayProgressCard: View {
    let currentDistance: Double
    let goalDistance: Double
    let progress: Double
    let didComplete: Bool
    let onRefresh: () -> Void
    let isRefreshing: Bool
    let user: User
    let fastestPace: TimeInterval
    let mostMiles: Double
    let totalMiles: Double
    /// Passed in by DashboardView (which caches it) instead of decoding the
    /// persisted in-progress workout JSON on every render.
    let hasActiveWorkout: Bool
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @Environment(\.colorScheme) var colorScheme
    @State private var animateProgress = false
    /// Binding that controls whether the workout tracking view is currently presented.
    @Binding var showWorkoutView: Bool
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 16) {
            // Eyebrow header — same quiet grammar as the streak card's
            // "CURRENT STREAK" label; the big number below is the headline.
            HStack(spacing: 6) {
                Text("TODAY")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(1.2)
                    .foregroundColor(didComplete ? .green : .white.opacity(0.7))
                if didComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                Spacer()
            }

            // Large progress display
            VStack(spacing: 8) {
                Text(String(format: "%.2f", currentDistance))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())

                Text("of \(String(format: "%.1f", goalDistance)) mi")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 12)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: didComplete ? [.green, .green] : [.orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: progress * geometry.size.width, height: 12)
                        .animation(.easeOut(duration: 0.8), value: progress)
                }
            }
            .frame(height: 12)

            // Start Mile button (or Resume if workout in progress)
            Button(action: {
                // Always just show the workout view - it will handle restoration if needed
                showWorkoutView = true
            }) {
                HStack(spacing: 8) {
                    if hasActiveWorkout {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                        Text("Resume Workout")
                            .font(.headline)
                            .fontWeight(.semibold)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.title3)
                        Text("Start Mile")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
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
        .padding(20)
        .background(
            ZStack {
                // Liquid glass background
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)

                // Gradient overlay
                LinearGradient(
                    colors: [
                        Color(red: 217/255, green: 64/255, blue: 63/255).opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Glass border
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
    }
}
