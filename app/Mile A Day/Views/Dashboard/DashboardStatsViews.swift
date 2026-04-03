import SwiftUI
import HealthKit

// MARK: - Supporting Components

// Unified Stats Grid Component
struct UnifiedStatsGrid: View {
    let user: User
    @ObservedObject var healthManager: HealthKitManager
    let statsType: StatsViewType
    @State private var statsData: (totalMiles: Double, mostMiles: Double, fastestPace: TimeInterval, streakDays: Int) = (0.0, 0.0, 0.0, 0)
    @State private var hasLoadedOnce = false
    @State private var isCalculating = false
    @State private var showFastestPaceDetail = false
    @State private var showMostMilesDetail = false
    @State private var showGoalSheet = false
    @State private var isRefreshingFastestPace = false

    enum StatsViewType: String, CaseIterable {
        case allTime = "All Time"
        case currentStreak = "Current Streak"
    }

    /// Best fastest pace from all sources (user stored + HealthKit live)
    var bestAllTimeFastestPace: TimeInterval {
        let userPace = user.fastestMilePace
        let hkPace = healthManager.fastestMilePace
        if userPace > 0 && hkPace > 0 {
            return min(userPace, hkPace) // lower is faster
        }
        return userPace > 0 ? userPace : hkPace
    }

    var isFastestPaceLoading: Bool {
        if statsType == .allTime {
            return isRefreshingFastestPace && bestAllTimeFastestPace <= 0
        } else {
            return isCalculating && statsData.fastestPace <= 0
        }
    }

    var formattedFastestPace: String {
        if statsType == .allTime {
            let pace = bestAllTimeFastestPace
            if pace > 0 {
                let minutes = Int(pace)
                let seconds = Int((pace - Double(minutes)) * 60)
                return String(format: "%d:%02d /mi", minutes, seconds)
            }
        } else {
            if statsData.fastestPace > 0 {
                let totalMinutes = statsData.fastestPace
                let minutes = Int(totalMinutes)
                let seconds = Int((totalMinutes - Double(minutes)) * 60)
                return String(format: "%d:%02d /mi", minutes, seconds)
            }
        }
        return "Not yet recorded"
    }

    var headerIcon: String {
        statsType == .allTime ? "trophy.fill" : "flame.fill"
    }

    var headerTitle: String {
        statsType == .allTime ? "All Time Stats" : "Current Streak Stats"
    }

    var badgeValue: String {
        if statsType == .allTime {
            return "All Time"
        } else {
            return "\(statsData.streakDays) days"
        }
    }

    var badgeColor: Color {
        statsType == .allTime ? .blue : .orange
    }

    var totalMiles: Double {
        statsType == .allTime ? user.totalMiles : statsData.totalMiles
    }

    var mostMiles: Double {
        if statsType == .allTime {
            // Calculate all-time most miles directly from all workouts to avoid timezone/caching issues
            let allWorkouts = healthManager.cachedWorkouts.isEmpty ? healthManager.recentWorkouts : healthManager.cachedWorkouts

            // Group all workouts by day (using device timezone for all-time stats)
            let calendar = Calendar.current
            var workoutsByDay: [Date: [HKWorkout]] = [:]

            for workout in allWorkouts {
                let dateComponents = calendar.dateComponents([.year, .month, .day], from: workout.endDate)
                if let date = calendar.date(from: dateComponents) {
                    if workoutsByDay[date] == nil {
                        workoutsByDay[date] = []
                    }
                    workoutsByDay[date]?.append(workout)
                }
            }

            // Calculate most miles in a single day from all workouts
            var maxMilesInDay: Double = 0.0
            for (_, dayWorkouts) in workoutsByDay {
                var totalMilesForDay: Double = 0.0
                for workout in dayWorkouts {
                    if let distance = workout.totalDistance {
                        let miles = distance.doubleValue(for: HKUnit.mile())
                        totalMilesForDay += miles
                    }
                }
                if totalMilesForDay > maxMilesInDay {
                    maxMilesInDay = totalMilesForDay
                }
            }

            // Return calculated value, with fallbacks
            if maxMilesInDay > 0 {
                return maxMilesInDay
            } else if healthManager.mostMilesInOneDay > 0 {
                return healthManager.mostMilesInOneDay
            } else {
                return user.mostMilesInOneDay
            }
        } else {
            return statsData.mostMiles
        }
    }

    var streakDays: Int {
        statsType == .allTime ? user.streak : statsData.streakDays
    }

    var avgMilesPerDay: Double {
        if streakDays > 0 {
            return totalMiles / Double(streakDays)
        }
        return 0.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Header with icon and badge
            HStack {
                Image(systemName: headerIcon)
                    .foregroundColor(badgeColor)
                    .font(.title2)

                Text(headerTitle)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                // Badge
                Text(badgeValue)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(badgeColor)
                    )
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                // Total Miles Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "map.fill")
                            .foregroundColor(.blue)
                        Text(statsType == .allTime ? "Total Miles" : "Streak Miles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if isCalculating && statsType == .currentStreak && !hasLoadedOnce {
                        ProgressView()
                            .frame(height: 28)
                    } else {
                        Text(String(format: "%.1f mi", totalMiles))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }

                    Text(streakDays > 0 && statsType == .currentStreak
                         ? String(format: "%.1f avg/day", avgMilesPerDay)
                         : (statsType == .allTime ? "All time" : " "))
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 100)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                )

                // Fastest Mile Card
                Button {
                    showFastestPaceDetail = true
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "hare.fill")
                                .foregroundColor(.green)
                            Text("Fastest Mile")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if isFastestPaceLoading {
                            ProgressView()
                                .frame(height: 28)
                        } else {
                            Text(formattedFastestPace)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                        }

                        if isCalculating || isRefreshingFastestPace {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(height: 14)
                        } else {
                            Text(statsType == .allTime ? "All time" : "Current streak")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Most Miles Card
                Button {
                    showMostMilesDetail = true
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundColor(.purple)
                            Text("Most in One Day")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if isCalculating && statsType == .currentStreak && !hasLoadedOnce {
                            ProgressView()
                                .frame(height: 28)
                        } else {
                            Text(String(format: "%.1f mi", mostMiles))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        }

                        Text(statsType == .allTime ? "All time" : "Current streak")
                            .font(.caption2)
                            .foregroundColor(.purple)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.purple.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Daily Goal / Streak Days Card
                if statsType == .allTime {
                    Button {
                        showGoalSheet = true
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "target")
                                    .foregroundColor(.gray)
                                Text("Daily Goal")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text(user.goalMiles.milesFormatted)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)

                            Text("Tap to edit")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                            Text("Streak Days")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if isCalculating && !hasLoadedOnce {
                            ProgressView()
                                .frame(height: 28)
                        } else {
                            Text("\(streakDays)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        }

                        if streakDays > 0 {
                            Text("Current streak")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )

                    // Total Miles (lifetime) card in current streak view
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "map.fill")
                                .foregroundColor(.red)
                            Text("Total Miles")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text(String(format: "%.1f mi", user.totalMiles))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        Text("Lifetime")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            )
                    )

                    // Average per day card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundColor(.cyan)
                            Text("Avg Per Day")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if isCalculating && !hasLoadedOnce {
                            ProgressView()
                                .frame(height: 28)
                        } else {
                            Text(String(format: "%.2f mi", avgMilesPerDay))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        }

                        Text("Current streak")
                            .font(.caption2)
                            .foregroundColor(.cyan)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.cyan.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .onAppear {
            if statsType == .currentStreak {
                calculateCurrentStreakStats()
            }
        }
        .onChange(of: healthManager.retroactiveStreak) { _, _ in
            if statsType == .currentStreak {
                calculateCurrentStreakStats()
            }
        }
        .onChange(of: statsType) { _, newType in
            if newType == .currentStreak {
                calculateCurrentStreakStats()
            }
        }
        .sheet(isPresented: $showFastestPaceDetail) {
            if statsType == .allTime {
                FastestPaceDetailView(healthManager: healthManager)
            } else {
                CurrentStreakFastestPaceDetailView(healthManager: healthManager, currentStreakStats: statsData)
            }
        }
        .sheet(isPresented: $showMostMilesDetail) {
            if statsType == .allTime {
                MostMilesDetailView(miles: mostMiles, healthManager: healthManager)
            } else {
                CurrentStreakMostMilesDetailView(mostMiles: mostMiles, healthManager: healthManager, currentStreakStats: statsData)
            }
        }
        .sheet(isPresented: $showGoalSheet) {
            GoalSettingSheet(
                currentGoal: user.goalMiles,
                onSave: { newGoal in
                    // Note: This will need to be handled by the parent view
                    // since we don't have access to userManager here
                }
            )
            .presentationDetents([.height(300)])
        }
    }

    private func calculateCurrentStreakStats() {
        // Show cached data immediately to avoid content shift
        let cached = healthManager.cachedCurrentStreakStats
        if cached.streakDays > 0 && !hasLoadedOnce {
            statsData = cached
        }

        isCalculating = !hasLoadedOnce

        DispatchQueue.global(qos: .userInitiated).async {
            let stats = healthManager.calculateCurrentStreakStats()

            DispatchQueue.main.async {
                self.statsData = stats
                self.isCalculating = false
                self.hasLoadedOnce = true
            }
        }
    }
}

// Stats Grid Component with Toggle
struct StatsGridView: View {
    let user: User
    @ObservedObject var healthManager: HealthKitManager
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedStatsView: UnifiedStatsGrid.StatsViewType = .allTime

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Header with toggle
            HStack {
                Text("Your Stats")
                    .font(.headline)

                Spacer()

                // Toggle between All Time and Current Streak
                Picker("Stats View", selection: $selectedStatsView) {
                    ForEach(UnifiedStatsGrid.StatsViewType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 180)
            }

            // Show unified stats view based on selection
            UnifiedStatsGrid(
                user: user,
                healthManager: healthManager,
                statsType: selectedStatsView
            )
        }
        .padding()
        .background(
            ZStack {
                // Liquid glass background
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)

                // Gradient overlay
                LinearGradient(
                    colors: [
                        Color.purple.opacity(0.05),
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

// Stat Card Component
struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.primary)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard()
    }
}

// Recent Workouts Component
struct RecentWorkoutsView: View {
    let workouts: [HKWorkout]
    @State private var selectedWorkout: IdentifiableWorkout?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Workouts")
                .font(.headline)

            if workouts.isEmpty {
                Text("No recent workouts found")
                    .foregroundColor(.secondary)
                    .padding(.vertical)
            } else {
                ForEach(workouts, id: \.uuid) { workout in
                    Button {
                        selectedWorkout = IdentifiableWorkout(workout: workout)
                    } label: {
                        DashboardWorkoutRow(workout: workout)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding()
        .cardStyle()
        .sheet(item: $selectedWorkout) { identifiableWorkout in
            WorkoutDetailView(workout: identifiableWorkout.workout)
        }
    }
}

// Workout Row Component for DashboardView (without MADTheme dependency)
struct DashboardWorkoutRow: View {
    let workout: HKWorkout

    var workoutTypeText: String {
        switch workout.workoutActivityType {
        case .running:
            return "Run"
        case .walking:
            return "Walk"
        default:
            return "Workout"
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(workoutTypeText)
                    .font(.headline)
                Text(workout.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(workout.formattedDistance)
                    .font(.headline)

                Text("\(workout.formattedDuration) (\(workout.pace))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 5)
    }
}

// Workout Detail View
struct WorkoutDetailView: View {
    let workout: HKWorkout
    @Environment(\.dismiss) private var dismiss
    @State private var calories: Double?
    @State private var splitTimes: [TimeInterval]?
    @State private var isLoadingSplits = false
    @EnvironmentObject var healthManager: HealthKitManager

    // Timezone-corrected times from index
    private var correctedEndTime: Date {
        healthManager.getCorrectedLocalTime(for: workout)
    }

    private var correctedStartTime: Date {
        let endTime = correctedEndTime
        return endTime.addingTimeInterval(-workout.duration)
    }

    private var workoutTypeString: String {
        switch workout.workoutActivityType {
        case .running: return "Run"
        case .walking: return "Walk"
        case .cycling: return "Ride"
        default: return "Workout"
        }
    }

    private var workoutIcon: String {
        switch workout.workoutActivityType {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        default: return "figure.mixed.cardio"
        }
    }

    private var workoutColor: Color {
        switch workout.workoutActivityType {
        case .running: return MADTheme.Colors.madRed
        case .walking: return .blue
        case .cycling: return .green
        default: return .purple
        }
    }

    private var distanceMiles: Double {
        workout.totalDistance?.doubleValue(for: .mile()) ?? 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        // Hero card — type, distance, date
                        VStack(spacing: MADTheme.Spacing.md) {
                            // Workout type badge
                            HStack(spacing: MADTheme.Spacing.sm) {
                                Image(systemName: workoutIcon)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(workoutTypeString)
                                    .font(MADTheme.Typography.smallBold)
                            }
                            .foregroundColor(workoutColor)
                            .padding(.horizontal, MADTheme.Spacing.md)
                            .padding(.vertical, MADTheme.Spacing.xs + 2)
                            .background(
                                Capsule()
                                    .fill(workoutColor.opacity(0.15))
                            )

                            // Distance — the hero number
                            Text(workout.formattedDistance)
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)

                            // Date
                            Text(correctedEndTime.formattedDate)
                                .font(MADTheme.Typography.body)
                                .foregroundColor(.secondary)
                        }
                        .padding(MADTheme.Spacing.lg)
                        .frame(maxWidth: .infinity)
                        .madLiquidGlass()

                        // Key stats row
                        HStack(spacing: MADTheme.Spacing.sm) {
                            DashboardStatBox(
                                title: "Duration",
                                value: workout.formattedDuration,
                                icon: "clock.fill",
                                color: .orange
                            )

                            DashboardStatBox(
                                title: "Pace",
                                value: workout.pace,
                                icon: "speedometer",
                                color: .green
                            )

                            if let calories = calories {
                                DashboardStatBox(
                                    title: "Calories",
                                    value: "\(Int(calories))",
                                    icon: "flame.fill",
                                    color: MADTheme.Colors.madRed
                                )
                            }
                        }

                        // Timeline details card
                        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                            HStack(spacing: MADTheme.Spacing.sm) {
                                Image(systemName: "clock.arrow.2.circlepath")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(MADTheme.Colors.redGradient)
                                Text("Timeline")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(.primary)
                            }

                            DetailRow(icon: "play.fill", iconColor: .green, title: "Start", value: correctedStartTime.formattedTime)
                            DetailRow(icon: "stop.fill", iconColor: MADTheme.Colors.madRed, title: "End", value: correctedEndTime.formattedTime)
                            DetailRow(icon: "timer", iconColor: .orange, title: "Duration", value: workout.formattedDuration)
                        }
                        .padding(MADTheme.Spacing.md)
                        .madLiquidGlass()

                        // Performance details card
                        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                            HStack(spacing: MADTheme.Spacing.sm) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(MADTheme.Colors.redGradient)
                                Text("Performance")
                                    .font(MADTheme.Typography.headline)
                                    .foregroundColor(.primary)
                            }

                            DetailRow(icon: "point.topleft.down.to.point.bottomright.curvepath.fill", iconColor: .blue, title: "Distance", value: workout.formattedDistance)
                            DetailRow(icon: "speedometer", iconColor: .green, title: "Avg Pace", value: workout.pace)
                            if let calories = calories {
                                DetailRow(icon: "flame.fill", iconColor: MADTheme.Colors.madRed, title: "Calories", value: "\(Int(calories)) kcal")
                            }
                        }
                        .padding(MADTheme.Spacing.md)
                        .madLiquidGlass()

                        // Mile Splits Section
                        if let splitTimes = splitTimes, !splitTimes.isEmpty {
                            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                                HStack(spacing: MADTheme.Spacing.sm) {
                                    Image(systemName: "flag.checkered")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(MADTheme.Colors.redGradient)
                                    Text("Mile Splits")
                                        .font(MADTheme.Typography.headline)
                                        .foregroundColor(.primary)
                                }

                                let fastestIndex = splitTimes.enumerated().min(by: { $0.element < $1.element })?.offset

                                ForEach(Array(splitTimes.enumerated()), id: \.offset) { index, splitTime in
                                    let isFastest = index == fastestIndex && splitTimes.count > 1
                                    HStack {
                                        HStack(spacing: MADTheme.Spacing.sm) {
                                            Text("Mile \(index + 1)")
                                                .font(MADTheme.Typography.body)
                                                .foregroundColor(.primary)

                                            if isFastest {
                                                Text("Fastest")
                                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                                    .foregroundColor(MADTheme.Colors.success)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(
                                                        Capsule()
                                                            .fill(MADTheme.Colors.success.opacity(0.15))
                                                    )
                                            }
                                        }

                                        Spacer()

                                        Text(formatSplitTime(splitTime))
                                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                                            .foregroundColor(isFastest ? MADTheme.Colors.success : .primary)
                                    }
                                    .padding(.vertical, MADTheme.Spacing.xs)

                                    if index < splitTimes.count - 1 {
                                        Divider()
                                            .overlay(Color.white.opacity(0.06))
                                    }
                                }
                            }
                            .padding(MADTheme.Spacing.md)
                            .madLiquidGlass()
                        } else if isLoadingSplits {
                            VStack(spacing: MADTheme.Spacing.md) {
                                HStack(spacing: MADTheme.Spacing.sm) {
                                    Image(systemName: "flag.checkered")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(MADTheme.Colors.redGradient)
                                    Text("Mile Splits")
                                        .font(MADTheme.Typography.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }

                                HStack(spacing: MADTheme.Spacing.sm) {
                                    ProgressView()
                                        .tint(.secondary)
                                        .scaleEffect(0.8)
                                    Text("Loading splits...")
                                        .font(MADTheme.Typography.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(MADTheme.Spacing.md)
                            .madLiquidGlass()
                        }
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
            .task {
                await fetchCalories()
                await fetchSplitTimes()
            }
        }
    }

    private func fetchSplitTimes() async {
        isLoadingSplits = true

        let healthManager = HealthKitManager()

        await withCheckedContinuation { continuation in
            healthManager.getWorkoutSplitTimes(for: workout) { splits in
                DispatchQueue.main.async {
                    self.splitTimes = splits
                    self.isLoadingSplits = false
                }
                continuation.resume()
            }
        }
    }

    private func formatSplitTime(_ splitTime: TimeInterval) -> String {
        let totalMinutes = splitTime
        let minutes = Int(totalMinutes)
        let seconds = Int((totalMinutes - Double(minutes)) * 60)

        return String(format: "%d:%02d", minutes, seconds)
    }

    private func fetchCalories() async {
        let healthStore = HKHealthStore()
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        let query = HKStatisticsQuery(
            quantityType: energyType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, error in
            guard let result = result,
                  let sum = result.sumQuantity() else {
                return
            }

            let calories = sum.doubleValue(for: HKUnit.kilocalorie())
            DispatchQueue.main.async {
                self.calories = calories
            }
        }

        healthStore.execute(query)
    }
}

struct DashboardStatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
            }

            Text(value)
                .font(MADTheme.Typography.headline)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MADTheme.Spacing.md)
        .padding(.horizontal, MADTheme.Spacing.sm)
        .madLiquidGlass()
    }
}

struct DetailRow: View {
    var icon: String? = nil
    var iconColor: Color = .secondary
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 20)
            }

            Text(title)
                .font(MADTheme.Typography.body)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(MADTheme.Typography.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding(.vertical, MADTheme.Spacing.xs)
    }
}

// Goal Setting Sheet with Version Info
struct GoalSettingSheet: View {
    let currentGoal: Double
    let onSave: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newGoalMiles: Double = 1.0

    // Version information from bundle
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private var versionString: String {
        "v\(appVersion) (\(buildNumber))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily Goal") {
                    Stepper(value: $newGoalMiles, in: 0.1...26.2, step: 0.1) {
                        HStack {
                            Text("Miles:")
                            Text(newGoalMiles.milesFormatted)
                                .fontWeight(.bold)
                        }
                    }
                }

                Section("Common Goals") {
                    Button("1 mile") { newGoalMiles = 1.0 }
                    Button("5K (3.1 miles)") { newGoalMiles = 3.1 }
                    Button("10K (6.2 miles)") { newGoalMiles = 6.2 }
                }

                Section("App Info") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(versionString)
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }

                    HStack {
                        Text("Build Date")
                        Spacer()
                        Text(getBuildDate())
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(newGoalMiles)
                        dismiss()
                    }
                }
            }
            .onAppear {
                newGoalMiles = currentGoal
            }
        }
    }

    private func getBuildDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        if let infoPath = Bundle.main.path(forResource: "Info", ofType: "plist"),
           let infoAttrs = try? FileManager.default.attributesOfItem(atPath: infoPath),
           let infoDate = infoAttrs[.modificationDate] as? Date {
            return formatter.string(from: infoDate)
        }

        return formatter.string(from: Date())
    }
}
