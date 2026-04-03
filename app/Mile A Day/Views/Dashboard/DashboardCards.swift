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
    @State private var animateStreak = false
    @State private var animateFire = false
    @State private var showingShareSheet = false
    @State private var timeRemainingText: String = ""
    @State private var timer: Timer?

    // Streak milestone milestones
    private let milestones = [3, 5, 7, 10, 14, 21, 30, 50, 60, 75, 90, 100, 150, 200, 250, 365, 500, 1000]

    /// Best fastest pace from user stored value and HealthKit live value
    private var bestFastestPace: TimeInterval {
        let userPace = fastestPace
        let hkPace = healthManager.fastestMilePace
        if userPace > 0 && hkPace > 0 {
            return min(userPace, hkPace)
        }
        return userPace > 0 ? userPace : hkPace
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

                    // Status message - make completion status super obvious with consistent colors
                    VStack(alignment: .leading, spacing: 6) {
                        if isGoalCompleted {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundColor(statusColor)
                                Text("Goal completed today!")
                                    .font(.subheadline)
                                    .foregroundColor(statusColor)
                                    .fontWeight(.bold)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: isAtRisk ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundColor(statusColor)
                                Text(isAtRisk ? "Streak at risk!" : "Goal not completed")
                                    .font(.subheadline)
                                    .foregroundColor(statusColor)
                                    .fontWeight(.bold)
                            }

                            if !isAtRisk {
                                Text("\(String(format: "%.2f", user.goalMiles - currentDistance)) mi to go")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                }

                Spacer()

                // Right side: Flame icon - consistent colors based on status
                ZStack {
                    if isGoalCompleted {
                        // Outer glow - green/orange when completed
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        statusColor.opacity(0.5),
                                        statusColor.opacity(0.2),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 45
                                )
                            )
                            .frame(width: 90, height: 90)
                            .scaleEffect(animateFire ? 1.15 : 0.95)
                            .opacity(animateFire ? 0.9 : 0.5)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateFire)

                        // Inner circle background - green/orange when completed
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

                        // Flame icon with animation - green/orange and pulsing when completed
                        Image(systemName: "flame.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [statusColor, statusColor.opacity(0.8), statusColor.opacity(0.6)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .scaleEffect(animateFire ? 1.15 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: animateFire)
                            .shadow(color: statusColor.opacity(0.7), radius: animateFire ? 15 : 8)
                    } else {
                        // Consistent color when not completed - white if not at risk, red tint if at risk
                        Circle()
                            .fill(statusColor.opacity(0.1))
                            .frame(width: 70, height: 70)

                        Image(systemName: "flame.fill")
                            .font(.system(size: 36))
                            .foregroundColor(isAtRisk ? statusColor.opacity(0.8) : .white.opacity(0.7))
                    }
                }
            }

            // Milestone progress
            if let milestone = nextMilestone {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Next Milestone: \(milestone.value) Days")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.9))

                        Spacer()

                        Text("\(milestone.daysToGo) days to go")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(statusColor)
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [.yellow, .orange, .red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: milestone.progress * geometry.size.width, height: 8)
                                .animation(.easeOut(duration: 0.8), value: milestone.progress)
                        }
                    }
                    .frame(height: 8)
                }
            }

            // Compact week-at-a-glance row
            compactWeekRow

            // Share hint
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 10))
                Text("Tap to share your streak")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
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
            // Time/check positioned at absolute top right edge
            if isGoalCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.top, 24)
                    .padding(.trailing, 24)
            } else if !timeRemainingText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundColor(statusColor)
                    Text(formattedTimeOnly)
                        .font(.caption2)
                        .foregroundColor(statusColor)
                        .fontWeight(.medium)
                }
                .padding(.top, 24)
                .padding(.trailing, 24)
            }
        }
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .onAppear {
            updateTimeRemaining()
            startTimer()
            // Start fire animation only if goal is completed
            if isGoalCompleted {
                animateFire = true
            } else {
                animateFire = false
            }
        }
        .onChange(of: isGoalCompleted) { oldValue, newValue in
            updateTimeRemaining()
            if newValue && !oldValue {
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
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
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
                    let dayLetter = {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "EEEEE"
                        return formatter.string(from: date)
                    }()

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
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @Environment(\.colorScheme) var colorScheme
    @State private var animateProgress = false
    /// Binding that controls whether the workout tracking view is currently presented.
    @Binding var showWorkoutView: Bool
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "figure.run")
                    .foregroundColor(.white)
                    .font(.title3)
                Text("Today's Progress")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                if didComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
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
                    if let state = InProgressWorkoutStore.load(), state.isActive {
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
