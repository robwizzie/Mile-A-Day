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

    private let madOrange = Color.orange
    private let madRed = Color(red: 217/255, green: 64/255, blue: 63/255)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Distance - main metric
                VStack(spacing: 4) {
                    Text(String(format: "%.2f", distance))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(madOrange)
                    Text("miles")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                        .frame(width: 90, height: 90)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                colors: progress >= 1.0 
                                    ? [Color.green, Color.green.opacity(0.8)]
                                    : [madOrange, madRed],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 90, height: 90)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)

                    VStack(spacing: 2) {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("goal")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)

                // Stats grid
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text(formattedTime)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Time")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 4) {
                        Text(pace)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Pace")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)

                // Heart rate
                if heartRate > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 12, weight: .medium))
                        Text("\(Int(heartRate))")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text("bpm")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Spacer(minLength: 12)

                // End workout button
                Button(action: onEnd) {
                    Text("End Workout")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red)
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

    private let madOrange = Color.orange
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Checkmark
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(.top, 8)

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
