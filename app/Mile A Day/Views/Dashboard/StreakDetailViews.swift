import SwiftUI
import HealthKit

// MARK: - Current Streak Detail Views

// Current Streak Fastest Pace Detail View
struct CurrentStreakFastestPaceDetailView: View {
    @ObservedObject var healthManager: HealthKitManager
    let currentStreakStats: (totalMiles: Double, mostMiles: Double, fastestPace: TimeInterval, streakDays: Int)
    @Environment(\.dismiss) private var dismiss
    @State private var streakWorkouts: [HKWorkout] = []
    @State private var isLoading = true
    @State private var selectedWorkout: IdentifiableWorkout?

    var formattedPace: String {
        guard currentStreakStats.fastestPace > 0 else { return "Not yet recorded" }

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
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: MADTheme.Spacing.xl) {
                    // Top banner
                    VStack(spacing: MADTheme.Spacing.md) {
                        Text("Current Streak")
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(MADTheme.Colors.secondaryText)

                        Text("Fastest Mile Pace")
                            .font(MADTheme.Typography.title1)
                            .fontWeight(.bold)
                            .foregroundColor(MADTheme.Colors.primaryText)

                        Text(formattedPace)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(MADTheme.Colors.success)
                            .padding(.top, MADTheme.Spacing.sm)
                    }
                    .padding(MADTheme.Spacing.xl)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .fill(MADTheme.Colors.success.opacity(0.1))
                    )
                    .madCard(hasShadow: false)

                    // Stats grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: MADTheme.Spacing.lg) {
                        StatBox(
                            title: "Pace",
                            value: formattedPace,
                            icon: "hare.fill",
                            color: MADTheme.Colors.success
                        )
                        StatBox(
                            title: "Speed",
                            value: speedMph,
                            icon: "speedometer",
                            color: Color.blue
                        )
                        StatBox(
                            title: "Streak Days",
                            value: "\(currentStreakStats.streakDays)",
                            icon: "flame.fill",
                            color: .orange
                        )
                        StatBox(
                            title: "Total Miles",
                            value: String(format: "%.1f mi", currentStreakStats.totalMiles),
                            icon: "map.fill",
                            color: .blue
                        )
                    }
                    .padding(.horizontal, MADTheme.Spacing.lg)

                    // Performance categories
                    if currentStreakStats.fastestPace > 0 {
                        performanceSection
                    }

                    // Workouts during streak
                    if isLoading {
                        ProgressView("Loading streak workouts...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !streakWorkouts.isEmpty {
                        VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                            Text("Fastest Mile During Current Streak")
                                .font(MADTheme.Typography.title3)
                                .fontWeight(.bold)
                                .foregroundColor(MADTheme.Colors.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                ForEach(streakWorkouts.prefix(10), id: \.uuid) { workout in
                                Button {
                                    selectedWorkout = IdentifiableWorkout(workout: workout)
                                } label: {
                                    WorkoutRow(workout: workout)
                                        .padding(MADTheme.Spacing.lg)
                                        .madCard()
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, MADTheme.Spacing.lg)
                    }

                    // Tips and achievements
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                        Text("Medals")
                            .font(MADTheme.Typography.title3)
                            .fontWeight(.bold)
                            .foregroundColor(MADTheme.Colors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: MADTheme.Spacing.lg) {
                            Image(systemName: "stopwatch.fill")
                                .font(.largeTitle)
                                .foregroundColor(.orange)

                            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                                Text("Your fastest pace in current streak!")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(MADTheme.Colors.primaryText)

                                Text("You've run a mile at \(formattedPace) during your current streak. Great job!")
                                    .font(MADTheme.Typography.body)
                                    .foregroundColor(MADTheme.Colors.secondaryText)
                            }
                        }
                        .padding(MADTheme.Spacing.lg)
                        .madCard()

                        // Tips for improving pace
                        HStack(spacing: MADTheme.Spacing.lg) {
                            Image(systemName: "bolt.fill")
                                .font(.largeTitle)
                                .foregroundColor(.yellow)

                            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                                Text("Improve your pace!")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(MADTheme.Colors.primaryText)

                                Text("Try interval training and tempo runs to increase your speed over time.")
                                    .font(MADTheme.Typography.body)
                                    .foregroundColor(MADTheme.Colors.secondaryText)
                            }
                        }
                        .padding(MADTheme.Spacing.lg)
                        .madCard()
                    }
                    .padding(.horizontal, MADTheme.Spacing.lg)
                }
                .padding(MADTheme.Spacing.lg)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .scrollDisabled(false)
            .background(MADTheme.Colors.secondaryBackground)
            .navigationTitle("Streak Pace Record")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .madTertiaryButton()
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

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
            Text("Performance Category")
                .font(MADTheme.Typography.title3)
                .fontWeight(.bold)
                .foregroundColor(MADTheme.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: MADTheme.Spacing.md) {
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
                    color: Color.blue
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
        .padding(.horizontal, MADTheme.Spacing.lg)
    }

    private func loadStreakWorkouts() async {
        isLoading = true

        // Use the pre-calculated workouts from HealthKitManager
        // This avoids recalculating split times for every workout
        let allStreakWorkouts = healthManager.getWorkoutsForCurrentStreak()
        let fastestMileWorkouts = healthManager.currentStreakFastestMileWorkouts

        // Get all workouts from the day(s) that contain the fastest mile
        var dayWorkouts: [HKWorkout] = []

        if !fastestMileWorkouts.isEmpty {
            // Get all unique days that contain fastest mile workouts
            let fastestDays = Set(fastestMileWorkouts.map { Calendar.current.startOfDay(for: $0.endDate) })

            // Get all workouts from those days
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

    private func formatPace(minutesPerMile: TimeInterval) -> String {
        let totalMinutes = minutesPerMile
        let minutes = Int(totalMinutes)
        let seconds = Int((totalMinutes - Double(minutes)) * 60)
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
}

// Current Streak Most Miles Detail View
struct CurrentStreakMostMilesDetailView: View {
    let mostMiles: Double
    @ObservedObject var healthManager: HealthKitManager
    let currentStreakStats: (totalMiles: Double, mostMiles: Double, fastestPace: TimeInterval, streakDays: Int)
    @Environment(\.dismiss) private var dismiss
    @State private var streakWorkouts: [HKWorkout] = []
    @State private var isLoading = true
    @State private var selectedWorkout: IdentifiableWorkout?

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: MADTheme.Spacing.xl) {
                    // Top banner
                    VStack(spacing: MADTheme.Spacing.md) {
                        Text("Current Streak")
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(MADTheme.Colors.secondaryText)

                        Text("Most Miles in One Day")
                            .font(MADTheme.Typography.title1)
                            .fontWeight(.bold)
                            .foregroundColor(MADTheme.Colors.primaryText)

                        Text(mostMiles.milesFormatted)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(Color.purple)
                            .padding(.top, MADTheme.Spacing.sm)
                    }
                    .padding(MADTheme.Spacing.xl)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .fill(Color.purple.opacity(0.1))
                    )
                    .madCard(hasShadow: false)

                    // Stats grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: MADTheme.Spacing.lg) {
                        StatBox(
                            title: "Distance",
                            value: mostMiles.milesFormatted,
                            icon: "map.fill",
                            color: Color.purple
                        )
                        StatBox(
                            title: "Steps",
                            value: String(format: "%.0f steps", mostMiles * 2000),
                            icon: "figure.walk",
                            color: MADTheme.Colors.success
                        )
                        StatBox(
                            title: "Calories Burned",
                            value: String(format: "%.0f calories", mostMiles * 100),
                            icon: "flame.fill",
                            color: MADTheme.Colors.warning
                        )
                        StatBox(
                            title: "Streak Days",
                            value: "\(currentStreakStats.streakDays)",
                            icon: "flame.fill",
                            color: .orange
                        )
                    }
                    .padding(.horizontal, MADTheme.Spacing.lg)

                    // Workouts during streak
                    if isLoading {
                        ProgressView("Loading streak workouts...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !streakWorkouts.isEmpty {
                        VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                            Text("Most Miles During Current Streak")
                                .font(MADTheme.Typography.title3)
                                .fontWeight(.bold)
                                .foregroundColor(MADTheme.Colors.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                ForEach(streakWorkouts.prefix(10), id: \.uuid) { workout in
                                Button {
                                    selectedWorkout = IdentifiableWorkout(workout: workout)
                                } label: {
                                    WorkoutRow(workout: workout)
                                        .padding(MADTheme.Spacing.lg)
                                        .madCard()
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, MADTheme.Spacing.lg)
                    }

                    // Tips and achievements
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
                        Text("Medals")
                            .font(MADTheme.Typography.title3)
                            .fontWeight(.bold)
                            .foregroundColor(MADTheme.Colors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: MADTheme.Spacing.lg) {
                            Image(systemName: "trophy.fill")
                                .font(.largeTitle)
                                .foregroundColor(.yellow)

                            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                                Text("Streak Distance Record!")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(MADTheme.Colors.primaryText)

                                Text("You've covered \(mostMiles.milesFormatted) in a single day during your current streak. Amazing achievement!")
                                    .font(MADTheme.Typography.body)
                                    .foregroundColor(MADTheme.Colors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(MADTheme.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .madCard()

                        // Tips for improving distance
                        HStack(spacing: MADTheme.Spacing.lg) {
                            Image(systemName: "figure.run")
                                .font(.largeTitle)
                                .foregroundColor(MADTheme.Colors.success)

                            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                                Text("Build Endurance!")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(MADTheme.Colors.primaryText)

                                Text("Gradually increase your daily distance and incorporate long runs into your training.")
                                    .font(MADTheme.Typography.body)
                                    .foregroundColor(MADTheme.Colors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(MADTheme.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .madCard()
                    }
                    .padding(.horizontal, MADTheme.Spacing.lg)
                    .frame(maxWidth: .infinity)
                }
                .padding(MADTheme.Spacing.lg)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .scrollDisabled(false)
            .background(MADTheme.Colors.secondaryBackground)
            .navigationTitle("Streak Distance Record")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .madTertiaryButton()
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

    private func loadStreakWorkouts() async {
        isLoading = true

        // Get workouts for the specific day that had the most miles
        // We need to find which day had the most miles and get workouts from that day only
        let allStreakWorkouts = healthManager.getWorkoutsForCurrentStreak()
        let workoutsByDay = Dictionary(grouping: allStreakWorkouts) { workout in
            Calendar.current.startOfDay(for: workout.endDate)
        }

        // Find the day with the most miles
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

        // Get workouts from the specific day with most miles
        let dayWorkouts = mostMilesDay != nil ? (workoutsByDay[mostMilesDay!] ?? []) : []

        await MainActor.run {
            self.streakWorkouts = dayWorkouts
            self.isLoading = false
        }
    }

    private func formatPace(minutesPerMile: TimeInterval) -> String {
        let totalMinutes = minutesPerMile
        let minutes = Int(totalMinutes)
        let seconds = Int((totalMinutes - Double(minutes)) * 60)
        return String(format: "%d:%02d /mi", minutes, seconds)
    }
}
