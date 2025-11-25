import SwiftUI
import HealthKit
import CoreLocation

struct WorkoutView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    let goalDistance: Double
    let startingDistance: Double
    @Environment(\.dismiss) var dismiss

    @StateObject private var workoutManager = WatchWorkoutManager()
    @State private var showActivitySelection = true
    @State private var showLocationTypeSelection = false
    @State private var selectedActivityType: HKWorkoutActivityType?
    @State private var selectedLocationType: HKWorkoutSessionLocationType = .outdoor
    @State private var showRecap = false

    private var currentDistance: Double {
        workoutManager.distance
    }

    private var totalDailyDistance: Double {
        startingDistance + workoutManager.distance
    }

    private var progress: Double {
        min(totalDailyDistance / goalDistance, 1.0)
    }

    var body: some View {
        Group {
            if showActivitySelection {
                ActivitySelectionView(
                    onSelectRun: {
                        selectedActivityType = .running
                        showActivitySelection = false
                        showLocationTypeSelection = true
                    },
                    onSelectWalk: {
                        selectedActivityType = .walking
                        showActivitySelection = false
                        showLocationTypeSelection = true
                    },
                    onBack: {
                        dismiss()
                    }
                )
            } else if showLocationTypeSelection {
                LocationTypeSelectionView(
                    activityType: selectedActivityType ?? .walking,
                    onSelectOutdoor: {
                        selectedLocationType = .outdoor
                        startWorkout()
                    },
                    onSelectIndoor: {
                        selectedLocationType = .indoor
                        startWorkout()
                    },
                    onBack: {
                        showLocationTypeSelection = false
                        showActivitySelection = true
                    }
                )
            } else if showRecap {
                WorkoutRecapView(
                    distance: currentDistance,
                    duration: workoutManager.elapsedTime,
                    heartRate: workoutManager.averageHeartRate,
                    calories: workoutManager.calories,
                    onDismiss: {
                        dismiss()
                    }
                )
            } else {
                // Active workout tracking
                WorkoutTrackingView(
                    distance: currentDistance,
                    totalDailyDistance: totalDailyDistance,
                    progress: progress,
                    elapsedTime: workoutManager.elapsedTime,
                    heartRate: workoutManager.currentHeartRate,
                    goalDistance: goalDistance,
                    isCompleted: totalDailyDistance >= goalDistance,
                    onEnd: {
                        endWorkout()
                    }
                )
            }
        }
    }

    private func startWorkout() {
        showLocationTypeSelection = false
        workoutManager.startWorkout(
            activityType: selectedActivityType ?? .walking,
            locationType: selectedLocationType
        )
    }

    private func endWorkout() {
        workoutManager.endWorkout { success in
            if success {
                showRecap = true
            }
        }
    }
}

// MARK: - Activity Selection View
struct ActivitySelectionView: View {
    let onSelectRun: () -> Void
    let onSelectWalk: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Back button
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                        Text("Back")
                            .font(.caption)
                    }
                }
                Spacer()
            }
            .padding(.horizontal)

            Spacer()

            Text("Choose Activity")
                .font(.headline)

            // Run button
            Button(action: onSelectRun) {
                VStack(spacing: 8) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 40))
                    Text("Run")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange.opacity(0.2))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            // Walk button
            Button(action: onSelectWalk) {
                VStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 40))
                    Text("Walk")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.2))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Location Type Selection View
struct LocationTypeSelectionView: View {
    let activityType: HKWorkoutActivityType
    let onSelectOutdoor: () -> Void
    let onSelectIndoor: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Back button
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                        Text("Back")
                            .font(.caption)
                    }
                }
                Spacer()
            }
            .padding(.horizontal)

            Spacer()

            Image(systemName: activityType == .running ? "figure.run" : "figure.walk")
                .font(.system(size: 40))

            Text("Choose Location")
                .font(.headline)

            // Outdoor button
            Button(action: onSelectOutdoor) {
                VStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 30))
                    Text("Outdoor")
                        .font(.headline)
                    Text("GPS tracking")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.2))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            // Indoor button
            Button(action: onSelectIndoor) {
                VStack(spacing: 8) {
                    Image(systemName: "figure.indoor.cycle")
                        .font(.system(size: 30))
                    Text("Indoor")
                        .font(.headline)
                    Text("Motion sensors")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple.opacity(0.2))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Workout Tracking View
struct WorkoutTrackingView: View {
    let distance: Double
    let totalDailyDistance: Double
    let progress: Double
    let elapsedTime: TimeInterval
    let heartRate: Double
    let goalDistance: Double
    let isCompleted: Bool
    let onEnd: () -> Void

    private var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var pace: String {
        guard distance > 0 else { return "--:--" }
        let paceInSeconds = elapsedTime / distance
        let paceMinutes = Int(paceInSeconds) / 60
        let paceSeconds = Int(paceInSeconds) % 60
        return String(format: "%d:%02d", paceMinutes, paceSeconds)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Distance - main metric
            VStack(spacing: 2) {
                Text(String(format: "%.2f", distance))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                Text("miles")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: progress >= 1.0 ? [.green, .green] : [.orange, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .fontWeight(.bold)
            }

            // Stats grid
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text(formattedTime)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("Time")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 2) {
                    Text(pace)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("Pace")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Heart rate
            if heartRate > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("\(Int(heartRate))")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("bpm")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // End workout button
            Button(action: onEnd) {
                Text("End Workout")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding()
    }
}

// MARK: - Workout Recap View
struct WorkoutRecapView: View {
    let distance: Double
    let duration: TimeInterval
    let heartRate: Double
    let calories: Double
    let onDismiss: () -> Void

    private var formattedTime: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var pace: String {
        guard distance > 0 else { return "--:--" }
        let paceInSeconds = duration / distance
        let paceMinutes = Int(paceInSeconds) / 60
        let paceSeconds = Int(paceInSeconds) % 60
        return String(format: "%d:%02d", paceMinutes, paceSeconds)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Checkmark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.green)

                Text("Workout Complete!")
                    .font(.headline)

                // Stats
                VStack(spacing: 12) {
                    StatRow(label: "Distance", value: String(format: "%.2f mi", distance))
                    StatRow(label: "Time", value: formattedTime)
                    StatRow(label: "Pace", value: "\(pace) /mi")

                    if heartRate > 0 {
                        StatRow(label: "Avg Heart Rate", value: "\(Int(heartRate)) bpm")
                    }

                    if calories > 0 {
                        StatRow(label: "Calories", value: "\(Int(calories)) cal")
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

                Button(action: onDismiss) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding()
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}
