import SwiftUI
import HealthKit

// MARK: - Stats Grid Component with Toggle

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

// MARK: - Stat Card Component

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

// MARK: - Recent Workouts Component

struct RecentWorkoutsView: View {
    let workouts: [HKWorkout]
    @EnvironmentObject var healthManager: HealthKitManager
    @State private var selectedWorkout: IdentifiableWorkout?

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("Recent Workouts")
                .font(MADTheme.Typography.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, MADTheme.Spacing.xs)

            if workouts.isEmpty {
                Text("No recent workouts found")
                    .foregroundColor(.secondary)
                    .padding(.vertical)
            } else {
                ForEach(workouts, id: \.uuid) { workout in
                    Button {
                        selectedWorkout = IdentifiableWorkout(workout: workout)
                    } label: {
                        WorkoutRow(workout: workout)
                            .padding(MADTheme.Spacing.md)
                            .madLiquidGlass()
                    }
                    .buttonStyle(ScaleButtonStyle())
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
