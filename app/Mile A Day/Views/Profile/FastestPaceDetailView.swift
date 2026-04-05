import SwiftUI
import HealthKit

struct FastestPaceDetailView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWorkout: IdentifiableWorkout?
    @State private var dayWorkouts: [HKWorkout] = []
    @State private var isLoading = true

    /// Use HealthKit pace (calculated from actual split times) as the authoritative source.
    /// Falls back to backend value only if HealthKit hasn't calculated yet.
    private var bestPace: TimeInterval {
        let hkPace = healthManager.fastestMilePace
        if hkPace > 0 { return hkPace }
        return userManager.currentUser.fastestMilePace
    }

    var formattedPace: String {
        guard bestPace > 0 else { return "N/A" }
        let minutes = Int(bestPace)
        let seconds = Int((bestPace - Double(minutes)) * 60)
        return String(format: "%d:%02d /mi", minutes, seconds)
    }

    var speedMph: String {
        guard bestPace > 0 else { return "0.0 mph" }
        return String(format: "%.1f mph", 60 / bestPace)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        heroCard
                        keyStatsRow

                        if bestPace > 0 {
                            performanceSection
                        }

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
                await loadFastestMileWorkouts()
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "hare.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Personal Record")
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
            if bestPace > 0 {
                DashboardStatBox(
                    title: "Category",
                    value: performanceCategory,
                    icon: "medal.fill",
                    color: performanceCategoryColor
                )
            }
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
                    isActive: bestPace < 5.0,
                    color: .purple
                )
                PerformanceCategoryRow(
                    category: "Competitive",
                    paceRange: "5:00 - 6:30",
                    isActive: bestPace >= 5.0 && bestPace < 6.5,
                    color: MADTheme.Colors.madRed
                )
                PerformanceCategoryRow(
                    category: "Recreational",
                    paceRange: "6:30 - 8:00",
                    isActive: bestPace >= 6.5 && bestPace < 8.0,
                    color: .blue
                )
                PerformanceCategoryRow(
                    category: "Fitness",
                    paceRange: "8:00 - 10:00",
                    isActive: bestPace >= 8.0 && bestPace < 10.0,
                    color: MADTheme.Colors.success
                )
                PerformanceCategoryRow(
                    category: "Beginner",
                    paceRange: "10:00+",
                    isActive: bestPace >= 10.0,
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
                    Text("Fastest Mile Workouts")
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
        } else if !dayWorkouts.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.redGradient)
                    Text("Fastest Mile Workouts")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(.primary)
                }
                ForEach(dayWorkouts, id: \.uuid) { workout in
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

    private func loadFastestMileWorkouts() async {
        // First check if healthManager already has them
        if !healthManager.fastestMileWorkouts.isEmpty {
            let workouts = healthManager.fastestMileWorkouts
            // Get all workouts from the same day(s) as the fastest mile workouts
            let fastestDays = Set(workouts.map { Calendar.current.startOfDay(for: $0.endDate) })
            let allDayWorkouts = healthManager.cachedWorkouts.filter { workout in
                let day = Calendar.current.startOfDay(for: workout.endDate)
                return fastestDays.contains(day)
            }.sorted { $0.endDate < $1.endDate }

            await MainActor.run {
                dayWorkouts = allDayWorkouts
                isLoading = false
            }
            return
        }

        // Wait briefly for findFastestMileWorkouts to finish populating
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        if !healthManager.fastestMileWorkouts.isEmpty {
            let workouts = healthManager.fastestMileWorkouts
            let fastestDays = Set(workouts.map { Calendar.current.startOfDay(for: $0.endDate) })
            let allDayWorkouts = healthManager.cachedWorkouts.filter { workout in
                let day = Calendar.current.startOfDay(for: workout.endDate)
                return fastestDays.contains(day)
            }.sorted { $0.endDate < $1.endDate }

            await MainActor.run {
                dayWorkouts = allDayWorkouts
                isLoading = false
            }
            return
        }

        // Final fallback: use cachedWorkouts to find fastest-pace workouts ourselves
        let pace = healthManager.fastestMilePace
        guard pace > 0 else {
            await MainActor.run { isLoading = false }
            return
        }

        // Find qualifying workouts and check their average pace
        let tolerance: TimeInterval = 0.5 // 30 seconds tolerance for average pace matching
        let qualifying = healthManager.cachedWorkouts.filter { workout in
            guard let distance = workout.totalDistance else { return false }
            let miles = distance.doubleValue(for: HKUnit.mile())
            guard miles >= 0.95 else { return false }
            let avgPace = workout.duration / 60.0 / miles
            return avgPace <= pace + tolerance
        }.sorted { $0.endDate > $1.endDate }

        // Take the best matching workouts (up to 5)
        let matched = Array(qualifying.prefix(5))

        await MainActor.run {
            dayWorkouts = matched
            isLoading = false
        }
    }

    // MARK: - Helpers

    private var performanceCategory: String {
        if bestPace < 5.0 { return "Elite" }
        if bestPace < 6.5 { return "Competitive" }
        if bestPace < 8.0 { return "Recreational" }
        if bestPace < 10.0 { return "Fitness" }
        return "Beginner"
    }

    private var performanceCategoryColor: Color {
        if bestPace < 5.0 { return .purple }
        if bestPace < 6.5 { return MADTheme.Colors.madRed }
        if bestPace < 8.0 { return .blue }
        if bestPace < 10.0 { return MADTheme.Colors.success }
        return MADTheme.Colors.warning
    }
}

struct PerformanceCategoryRow: View {
    let category: String
    let paceRange: String
    let isActive: Bool
    let color: Color

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(isActive ? color.opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(width: 12, height: 12)

                if isActive {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
            }

            Text(category)
                .font(MADTheme.Typography.body)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundColor(isActive ? .primary : .secondary)

            Spacer()

            Text(paceRange)
                .font(MADTheme.Typography.callout)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, MADTheme.Spacing.xs)
        .opacity(isActive ? 1.0 : 0.6)
    }
}

#Preview {
    FastestPaceDetailView(healthManager: HealthKitManager(), userManager: UserManager())
}
