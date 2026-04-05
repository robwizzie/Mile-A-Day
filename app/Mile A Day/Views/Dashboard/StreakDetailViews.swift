import SwiftUI
import HealthKit

// MARK: - Current Streak Fastest Pace Detail View

struct CurrentStreakFastestPaceDetailView: View {
    @ObservedObject var healthManager: HealthKitManager
    let currentStreakStats: (totalMiles: Double, mostMiles: Double, fastestPace: TimeInterval, streakDays: Int)
    @Environment(\.dismiss) private var dismiss
    @State private var streakWorkouts: [HKWorkout] = []
    @State private var isLoading = true
    @State private var selectedWorkout: IdentifiableWorkout?

    var formattedPace: String {
        guard currentStreakStats.fastestPace > 0 else { return "N/A" }
        let totalMinutes = currentStreakStats.fastestPace
        let minutes = Int(totalMinutes)
        let seconds = Int((totalMinutes - Double(minutes)) * 60)
        return String(format: "%d:%02d /mi", minutes, seconds)
    }

    var speedMph: String {
        guard currentStreakStats.fastestPace > 0 else { return "0.0 mph" }
        return String(format: "%.1f mph", 60 / currentStreakStats.fastestPace)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        // Hero card
                        heroCard

                        // Key stats row
                        keyStatsRow

                        // Performance categories
                        if currentStreakStats.fastestPace > 0 {
                            performanceSection
                        }

                        // Workouts section
                        workoutsSection
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(MADTheme.Colors.madRed)
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $selectedWorkout) { identifiableWorkout in
                WorkoutDetailView(workout: identifiableWorkout.workout)
            }
            .task {
                await loadStreakWorkouts()
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "hare.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Current Streak")
                    .font(MADTheme.Typography.smallBold)
            }
            .foregroundColor(MADTheme.Colors.success)
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.xs + 2)
            .background(
                Capsule()
                    .fill(MADTheme.Colors.success.opacity(0.15))
            )

            Text(formattedPace)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("Fastest Mile Pace")
                .font(MADTheme.Typography.body)
                .foregroundColor(.secondary)
        }
        .padding(MADTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .madLiquidGlass()
    }

    // MARK: - Key Stats Row

    private var keyStatsRow: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            DashboardStatBox(
                title: "Pace",
                value: formattedPace.replacingOccurrences(of: " /mi", with: ""),
                icon: "hare.fill",
                color: MADTheme.Colors.success
            )
            DashboardStatBox(
                title: "Speed",
                value: speedMph,
                icon: "speedometer",
                color: .blue
            )
            DashboardStatBox(
                title: "Streak",
                value: "\(currentStreakStats.streakDays)d",
                icon: "flame.fill",
                color: .orange
            )
        }
    }

    // MARK: - Performance Section

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("Performance Category")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
            }

            VStack(spacing: MADTheme.Spacing.sm) {
                PerformanceCategoryRow(
                    category: "Elite",
                    paceRange: "< 5:00",
                    isActive: currentStreakStats.fastestPace < 5.0,
                    color: .purple
                )
                PerformanceCategoryRow(
                    category: "Competitive",
                    paceRange: "5:00 - 6:30",
                    isActive: currentStreakStats.fastestPace >= 5.0 && currentStreakStats.fastestPace < 6.5,
                    color: MADTheme.Colors.madRed
                )
                PerformanceCategoryRow(
                    category: "Recreational",
                    paceRange: "6:30 - 8:00",
                    isActive: currentStreakStats.fastestPace >= 6.5 && currentStreakStats.fastestPace < 8.0,
                    color: .blue
                )
                PerformanceCategoryRow(
                    category: "Fitness",
                    paceRange: "8:00 - 10:00",
                    isActive: currentStreakStats.fastestPace >= 8.0 && currentStreakStats.fastestPace < 10.0,
                    color: MADTheme.Colors.success
                )
                PerformanceCategoryRow(
                    category: "Beginner",
                    paceRange: "10:00+",
                    isActive: currentStreakStats.fastestPace >= 10.0,
                    color: MADTheme.Colors.warning
                )
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    // MARK: - Workouts Section

    @ViewBuilder
    private var workoutsSection: some View {
        if isLoading {
            VStack(spacing: MADTheme.Spacing.md) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.redGradient)
                    Text("Fastest Mile During Streak")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.primary)
                    Spacer()
                }
                HStack(spacing: MADTheme.Spacing.sm) {
                    ProgressView()
                        .tint(.secondary)
                        .scaleEffect(0.8)
                    Text("Loading workouts...")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        } else if !streakWorkouts.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.redGradient)
                    Text("Fastest Mile During Streak")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.primary)
                }
                ForEach(streakWorkouts.prefix(10), id: \.uuid) { workout in
                    Button {
                        selectedWorkout = IdentifiableWorkout(workout: workout)
                    } label: {
                        WorkoutRow(workout: workout)
                            .padding(MADTheme.Spacing.md)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(MADTheme.CornerRadius.medium)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        }
    }

    // MARK: - Data Loading

    private func loadStreakWorkouts() async {
        isLoading = true
        let allStreakWorkouts = healthManager.getWorkoutsForCurrentStreak()
        let fastestMileWorkouts = healthManager.currentStreakFastestMileWorkouts

        var dayWorkouts: [HKWorkout] = []
        if !fastestMileWorkouts.isEmpty {
            let fastestDays = Set(fastestMileWorkouts.map { Calendar.current.startOfDay(for: $0.endDate) })
            dayWorkouts = allStreakWorkouts.filter { workout in
                let workoutDay = Calendar.current.startOfDay(for: workout.endDate)
                return fastestDays.contains(workoutDay)
            }
        }

        await MainActor.run {
            self.streakWorkouts = dayWorkouts
            self.isLoading = false
        }
    }
}

// MARK: - Current Streak Most Miles Detail View

struct CurrentStreakMostMilesDetailView: View {
    let mostMiles: Double
    @ObservedObject var healthManager: HealthKitManager
    let currentStreakStats: (totalMiles: Double, mostMiles: Double, fastestPace: TimeInterval, streakDays: Int)
    @Environment(\.dismiss) private var dismiss
    @State private var streakWorkouts: [HKWorkout] = []
    @State private var isLoading = true
    @State private var selectedWorkout: IdentifiableWorkout?
    @State private var bestDayDateString: String?

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        heroCard
                        keyStatsRow
                        workoutsSection
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(MADTheme.Colors.madRed)
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $selectedWorkout) { identifiableWorkout in
                WorkoutDetailView(workout: identifiableWorkout.workout)
            }
            .task {
                await loadStreakWorkouts()
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Current Streak")
                    .font(MADTheme.Typography.smallBold)
            }
            .foregroundColor(.purple)
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.xs + 2)
            .background(
                Capsule()
                    .fill(Color.purple.opacity(0.15))
            )

            Text(mostMiles.milesFormatted)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(spacing: MADTheme.Spacing.xs) {
                Text("Most Miles in One Day")
                    .font(MADTheme.Typography.body)
                    .foregroundColor(.secondary)

                if let dateString = bestDayDateString {
                    Text(dateString)
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(MADTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .madLiquidGlass()
    }

    // MARK: - Key Stats Row

    private var keyStatsRow: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            DashboardStatBox(
                title: "Distance",
                value: mostMiles.milesFormatted,
                icon: "map.fill",
                color: .purple
            )
            DashboardStatBox(
                title: "Est. Steps",
                value: String(format: "%.0f", mostMiles * 2000),
                icon: "figure.walk",
                color: MADTheme.Colors.success
            )
            DashboardStatBox(
                title: "Streak",
                value: "\(currentStreakStats.streakDays)d",
                icon: "flame.fill",
                color: .orange
            )
        }
    }

    // MARK: - Workouts Section

    @ViewBuilder
    private var workoutsSection: some View {
        if isLoading {
            VStack(spacing: MADTheme.Spacing.md) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.redGradient)
                    Text("Workouts That Day")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.primary)
                    Spacer()
                }
                HStack(spacing: MADTheme.Spacing.sm) {
                    ProgressView()
                        .tint(.secondary)
                        .scaleEffect(0.8)
                    Text("Loading workouts...")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        } else if !streakWorkouts.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.redGradient)
                    Text("Workouts That Day")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.primary)
                }
                ForEach(streakWorkouts.prefix(10), id: \.uuid) { workout in
                    Button {
                        selectedWorkout = IdentifiableWorkout(workout: workout)
                    } label: {
                        WorkoutRow(workout: workout)
                            .padding(MADTheme.Spacing.md)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(MADTheme.CornerRadius.medium)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        }
    }

    // MARK: - Data Loading

    private func loadStreakWorkouts() async {
        isLoading = true
        let allStreakWorkouts = healthManager.getWorkoutsForCurrentStreak()
        let workoutsByDay = Dictionary(grouping: allStreakWorkouts) { workout in
            Calendar.current.startOfDay(for: workout.endDate)
        }

        var mostMilesDay: Date?
        var maxMiles = 0.0
        for (date, workouts) in workoutsByDay {
            let dayMiles = workouts.reduce(0.0) { total, workout in
                if let distance = workout.totalDistance {
                    return total + distance.doubleValue(for: HKUnit.mile())
                }
                return total
            }
            if dayMiles > maxMiles {
                maxMiles = dayMiles
                mostMilesDay = date
            }
        }

        let dayWorkouts = mostMilesDay != nil ? (workoutsByDay[mostMilesDay!] ?? []) : []

        // Format best day date
        var dateString: String?
        if let day = mostMilesDay {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            dateString = formatter.string(from: day)
        }

        await MainActor.run {
            self.streakWorkouts = dayWorkouts
            self.bestDayDateString = dateString
            self.isLoading = false
        }
    }
}
