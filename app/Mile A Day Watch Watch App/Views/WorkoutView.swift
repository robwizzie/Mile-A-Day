import SwiftUI
import HealthKit

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
    @State private var showEndConfirmation = false
    @State private var goalReached = false

    private var currentDistance: Double {
        workoutManager.distance
    }

    private var totalDailyDistance: Double {
        startingDistance + workoutManager.distance
    }

    private var progress: Double {
        min(totalDailyDistance / goalDistance, 1.0)
    }

    private var isCompleted: Bool {
        totalDailyDistance >= goalDistance
    }

    private var activityName: String {
        activityType == .running ? "Run" : "Walk"
    }

    // Theme
    private let accentRed = Color(red: 217/255, green: 64/255, blue: 63/255)

    var body: some View {
        Group {
            if showRecap {
                WorkoutRecapView(
                    distance: currentDistance,
                    duration: workoutManager.elapsedTime,
                    heartRate: workoutManager.averageHeartRate,
                    calories: workoutManager.calories,
                    activityName: activityName,
                    goalReached: isCompleted,
                    onDismiss: { dismiss() }
                )
            } else {
                activeTrackingView
            }
        }
        .onAppear {
            if !workoutStarted {
                workoutStarted = true
                workoutManager.startWorkout(
                    activityType: activityType,
                    locationType: .outdoor
                )
            }
        }
        .onChange(of: isCompleted) { _, newValue in
            if newValue && !goalReached {
                goalReached = true
                WKInterfaceDevice.current().play(.success)
            }
        }
    }

    // MARK: - Active Tracking

    private var activeTrackingView: some View {
        VStack(spacing: 0) {
            // Activity label
            HStack(spacing: 4) {
                Image(systemName: activityType == .running ? "figure.run" : "figure.walk")
                    .font(.system(size: 11, weight: .semibold))
                Text(activityName.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundColor(accentRed)
            .padding(.top, 6)

            Spacer()

            // Central metrics
            ZStack {
                // Progress ring
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)
                    .frame(width: 130, height: 130)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        isCompleted
                            ? Color.green
                            : accentRed,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: progress)

                // Distance in center
                VStack(spacing: 0) {
                    Text(String(format: "%.2f", currentDistance))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.7)
                    Text("mi")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            // Goal status
            if isCompleted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Goal reached!")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.green)
                .padding(.top, 4)
            } else {
                Text("\(String(format: "%.2f", max(goalDistance - totalDailyDistance, 0))) mi to goal")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 4)
            }

            Spacer()

            // Stats row
            statsRow
                .padding(.horizontal, 4)

            Spacer()

            // Control buttons
            controlButtons
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("End workout?", isPresented: $showEndConfirmation) {
            Button("End Workout", role: .destructive) { endWorkout() }
            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 0) {
            // Time
            statItem(
                label: "TIME",
                value: formattedTime
            )

            divider

            // Pace
            statItem(
                label: "PACE",
                value: formattedPace
            )

            if workoutManager.currentHeartRate > 0 {
                divider

                // Heart rate
                statItem(
                    label: "BPM",
                    value: "\(Int(workoutManager.currentHeartRate))",
                    valueColor: .red
                )
            }
        }
    }

    private func statItem(label: String, value: String, valueColor: Color = .white) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(valueColor)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 28)
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        HStack(spacing: 16) {
            // Pause / Resume
            Button {
                if workoutManager.isPaused {
                    workoutManager.resumeWorkout()
                } else {
                    workoutManager.pauseWorkout()
                }
                WKInterfaceDevice.current().play(.click)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.9))
                        .frame(width: 50, height: 50)

                    Image(systemName: workoutManager.isPaused ? "play.fill" : "pause")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .buttonStyle(.plain)

            // Stop
            Button {
                showEndConfirmation = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 50, height: 50)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let h = Int(workoutManager.elapsedTime) / 3600
        let m = Int(workoutManager.elapsedTime) / 60 % 60
        let s = Int(workoutManager.elapsedTime) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private var formattedPace: String {
        guard currentDistance > 0.01 else { return "--:--" }
        let paceSeconds = workoutManager.elapsedTime / currentDistance
        let m = Int(paceSeconds) / 60
        let s = Int(paceSeconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func endWorkout() {
        workoutManager.endWorkout { success in
            if success {
                showRecap = true
            }
        }
    }
}

// MARK: - Workout Recap View

struct WorkoutRecapView: View {
    let distance: Double
    let duration: TimeInterval
    let heartRate: Double
    let calories: Double
    let activityName: String
    let goalReached: Bool
    let onDismiss: () -> Void

    private let accentRed = Color(red: 217/255, green: 64/255, blue: 63/255)

    private var formattedTime: String {
        let h = Int(duration) / 3600
        let m = Int(duration) / 60 % 60
        let s = Int(duration) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private var formattedPace: String {
        guard distance > 0.01 else { return "--:--" }
        let paceSeconds = duration / distance
        let m = Int(paceSeconds) / 60
        let s = Int(paceSeconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Status icon
                ZStack {
                    Circle()
                        .fill(goalReached ? Color.green.opacity(0.15) : accentRed.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: goalReached ? "checkmark" : "figure.run")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(goalReached ? .green : accentRed)
                }
                .padding(.top, 8)

                // Title
                Text(goalReached ? "Goal Complete!" : "Workout Done")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // Primary stat: distance
                VStack(spacing: 0) {
                    Text(String(format: "%.2f", distance))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("miles")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }

                // Stats grid
                VStack(spacing: 8) {
                    recapRow(icon: "clock", label: "Duration", value: formattedTime)
                    recapRow(icon: "speedometer", label: "Avg Pace", value: "\(formattedPace) /mi")

                    if heartRate > 0 {
                        recapRow(icon: "heart.fill", label: "Avg HR", value: "\(Int(heartRate)) bpm", valueColor: .red)
                    }

                    if calories > 0 {
                        recapRow(icon: "flame.fill", label: "Calories", value: "\(Int(calories)) kcal", valueColor: .orange)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.08))
                )

                // Done button
                Button {
                    onDismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(accentRed)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 8)
        }
    }

    private func recapRow(icon: String, label: String, value: String, valueColor: Color = .white) -> some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(valueColor)
        }
    }
}
