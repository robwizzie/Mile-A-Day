import SwiftUI
import HealthKit

struct MostMilesDetailView: View {
    let miles: Double
    @ObservedObject var healthManager: HealthKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWorkout: IdentifiableWorkout?
    @State private var dayWorkouts: [HKWorkout] = []
    @State private var bestDayDateString: String?
    @State private var isLoading = true

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
                await loadBestDayWorkouts()
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Personal Record")
                    .font(MADTheme.Typography.smallBold)
            }
            .foregroundColor(.purple)
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.xs + 2)
            .background(
                Capsule()
                    .fill(Color.purple.opacity(0.15))
            )

            Text(miles.milesFormatted)
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
                value: miles.milesFormatted,
                icon: "map.fill",
                color: .purple
            )
            DashboardStatBox(
                title: "Est. Steps",
                value: String(format: "%.0f", miles * 2000),
                icon: "figure.walk",
                color: MADTheme.Colors.success
            )
            DashboardStatBox(
                title: "Est. Calories",
                value: String(format: "%.0f", miles * 100),
                icon: "flame.fill",
                color: MADTheme.Colors.warning
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
        } else if !dayWorkouts.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MADTheme.Colors.redGradient)
                    Text("Workouts That Day")
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

    private func loadBestDayWorkouts() async {
        if let index = healthManager.workoutIndex,
           let bestDayKey = index.mostMilesInOneDayDateKey {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            if let date = formatter.date(from: bestDayKey) {
                let displayFormatter = DateFormatter()
                displayFormatter.dateStyle = .medium
                displayFormatter.timeStyle = .none
                await MainActor.run {
                    bestDayDateString = displayFormatter.string(from: date)
                }
            }

            let recordUUIDs = Set(index.mostMilesInOneDayRecords.map { $0.id })
            let matched = healthManager.cachedWorkouts.filter { recordUUIDs.contains($0.uuid.uuidString) }
                .sorted { $0.endDate < $1.endDate }

            await MainActor.run {
                dayWorkouts = matched
                isLoading = false
            }
        } else {
            await MainActor.run {
                dayWorkouts = healthManager.mostMilesWorkouts
                isLoading = false
            }
        }
    }
}

// Stat box component for detail views
struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 50)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(color)
            }
            VStack(spacing: MADTheme.Spacing.xs) {
                Text(value)
                    .font(MADTheme.Typography.headline)
                    .fontWeight(.bold)
                    .foregroundColor(MADTheme.Colors.primaryText)
                    .multilineTextAlignment(.center)
                Text(title)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.lg)
        .madCard()
    }
}

// Workout row component
struct WorkoutRow: View {
    let workout: HKWorkout
    @EnvironmentObject var healthManager: HealthKitManager

    private var correctedStartTime: Date {
        let correctedEndTime = healthManager.getCorrectedLocalTime(for: workout)
        return correctedEndTime.addingTimeInterval(-workout.duration)
    }

    private var workoutDistance: String {
        if let distance = workout.totalDistance {
            let miles = distance.doubleValue(for: .mile())
            return miles.milesFormatted
        }
        return "Unknown"
    }

    private var workoutDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: workout.duration) ?? "Unknown"
    }

    private var workoutColor: Color {
        switch workout.workoutActivityType {
        case .running: return MADTheme.Colors.madRed
        case .walking: return .blue
        case .cycling: return .green
        default: return .purple
        }
    }

    private var workoutSource: WorkoutSource {
        healthManager.workoutRecord(forUUID: workout.uuid.uuidString)?.source ?? .healthkit
    }

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(workoutColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: workoutIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(workoutColor)
            }
            VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                HStack(spacing: 6) {
                    Text(workoutTypeString)
                        .font(MADTheme.Typography.body)
                        .fontWeight(.medium)
                        .foregroundColor(MADTheme.Colors.primaryText)
                    ManualWorkoutBadge(source: workoutSource)
                }
                HStack {
                    Text(workoutDistance)
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                    Text("\u{2022}")
                        .foregroundColor(MADTheme.Colors.secondaryText)
                    Text(workoutDuration)
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                }
            }
            Spacer()
            Text(DateFormatter.shortTime.string(from: correctedStartTime))
                .font(MADTheme.Typography.caption)
                .foregroundColor(MADTheme.Colors.secondaryText)
        }
    }

    private var workoutTypeString: String {
        switch workout.workoutActivityType {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
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
}

// Date formatter extension
extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    MostMilesDetailView(miles: 5.2, healthManager: HealthKitManager())
}
