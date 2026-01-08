import SwiftUI
import HealthKit
import CoreLocation

struct WorkoutView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    let goalDistance: Double
    let startingDistance: Double
    let activityType: HKWorkoutActivityType
    @Environment(\.dismiss) var dismiss

    @StateObject private var workoutManager = WatchWorkoutManager()
    @State private var showRecap = false
    @State private var workoutStarted = false

    private var currentDistance: Double {
        workoutManager.distance
    }

    private var totalDailyDistance: Double {
        startingDistance + workoutManager.distance
    }

    private var progress: Double {
        min(totalDailyDistance / goalDistance, 1.0)
    }

    private var activityName: String {
        activityType == .running ? "Active Run" : "Active Walk"
    }

    var body: some View {
        Group {
            if showRecap {
                WorkoutRecapView(
                    distance: currentDistance,
                    duration: workoutManager.elapsedTime,
                    heartRate: workoutManager.averageHeartRate,
                    calories: workoutManager.calories,
                    activityName: activityName,
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
                    isPaused: workoutManager.isPaused,
                    activityName: activityName,
                    onPause: {
                        workoutManager.pauseWorkout()
                    },
                    onResume: {
                        workoutManager.resumeWorkout()
                    },
                    onEnd: {
                        endWorkout()
                    }
                )
            }
        }
        .onAppear {
            if !workoutStarted {
                workoutStarted = true
                // Default to outdoor workout for simplicity
                workoutManager.startWorkout(
                    activityType: activityType,
                    locationType: .outdoor
                )
            }
        }
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
    
    private let madOrange = Color.orange
    private let madRed = Color(red: 217/255, green: 64/255, blue: 63/255)

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with back button
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .frame(height: 32)
            
            Spacer()
            
            // Activity selection
            VStack(spacing: 16) {
                // Run button
                Button(action: onSelectRun) {
                    VStack(spacing: 10) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(madOrange)
                        Text("Run")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(madOrange.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)

                // Walk button
                Button(action: onSelectWalk) {
                    VStack(spacing: 10) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(.blue)
                        Text("Walk")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.blue.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            
            Spacer()
        }
    }
}

// MARK: - Location Type Selection View
struct LocationTypeSelectionView: View {
    let activityType: HKWorkoutActivityType
    let onSelectOutdoor: () -> Void
    let onSelectIndoor: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with back button
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .frame(height: 32)
            
            Spacer()
            
            // Activity icon
            Image(systemName: activityType == .running ? "figure.run" : "figure.walk")
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(.primary)
                .padding(.bottom, 8)
            
            // Location selection
            VStack(spacing: 16) {
                // Outdoor button
                Button(action: onSelectOutdoor) {
                    VStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.green)
                        Text("Outdoor")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("GPS")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.green.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)

                // Indoor button
                Button(action: onSelectIndoor) {
                    VStack(spacing: 8) {
                        Image(systemName: "figure.indoor.cycle")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.purple)
                        Text("Indoor")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Motion")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.purple.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            
            Spacer()
        }
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
    let isPaused: Bool
    let activityName: String
    let onPause: () -> Void
    let onResume: () -> Void
    let onEnd: () -> Void

    private var formattedTime: String {
        let hours = Int(elapsedTime) / 3600
        let minutes = Int(elapsedTime) / 60 % 60
        let seconds = Int(elapsedTime) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private var pace: String {
        guard distance > 0 else { return "--'--\"" }
        let paceInSeconds = elapsedTime / distance
        let paceMinutes = Int(paceInSeconds) / 60
        let paceSeconds = Int(paceInSeconds) % 60
        return String(format: "%d'%02d\"", paceMinutes, paceSeconds)
    }

    private let madOrange = Color.orange
    private let madRed = Color(red: 217/255, green: 64/255, blue: 63/255)

    var body: some View {
        VStack(spacing: 0) {
            // Activity name at top
            Text(activityName)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(madRed)
                .textCase(.uppercase)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Spacer()

            // Main content
            VStack(spacing: 20) {
                // Distance - large and prominent
                VStack(spacing: 2) {
                    Text(String(format: "%.2f", distance))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .minimumScaleFactor(0.8)
                    Text("MI")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)

                // Time and Pace - side by side
                HStack(spacing: 0) {
                    VStack(spacing: 2) {
                        Text("TIME")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        Text(formattedTime)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1, height: 36)

                    VStack(spacing: 2) {
                        Text("PACE")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        Text(pace)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
            }

            Spacer()

            // Control buttons at bottom
            HStack(spacing: 20) {
                // Pause/Resume button
                Button(action: isPaused ? onResume : onPause) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.8, green: 0.6, blue: 0.2))
                            .frame(width: 56, height: 56)

                        if isPaused {
                            Image(systemName: "play.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.black)
                        } else {
                            Image(systemName: "pause")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.black)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Stop button
                Button(action: onEnd) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 56, height: 56)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white)
                            .frame(width: 18, height: 18)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Workout Recap View
struct WorkoutRecapView: View {
    let distance: Double
    let duration: TimeInterval
    let heartRate: Double
    let calories: Double
    let activityName: String
    let onDismiss: () -> Void

    private var formattedTime: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private var pace: String {
        guard distance > 0 else { return "--'--\"" }
        let paceInSeconds = duration / distance
        let paceMinutes = Int(paceInSeconds) / 60
        let paceSeconds = Int(paceInSeconds) % 60
        return String(format: "%d'%02d\"", paceMinutes, paceSeconds)
    }

    private let madOrange = Color.orange
    private let madRed = Color(red: 217/255, green: 64/255, blue: 63/255)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Activity name
                Text(activityName)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(madRed)
                    .textCase(.uppercase)
                    .padding(.top, 4)

                // Checkmark
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 70, height: 70)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50, weight: .medium))
                        .foregroundColor(.green)
                }

                Text("Complete!")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                // Stats
                VStack(spacing: 10) {
                    StatRow(label: "Distance", value: String(format: "%.2f mi", distance))
                    StatRow(label: "Time", value: formattedTime)
                    StatRow(label: "Pace", value: "\(pace) /mi")

                    if heartRate > 0 {
                        StatRow(label: "Heart Rate", value: "\(Int(heartRate)) bpm")
                    }

                    if calories > 0 {
                        StatRow(label: "Calories", value: "\(Int(calories))")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.secondary.opacity(0.1))
                )

                Button(action: onDismiss) {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(madOrange)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 4)
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
    }
}
