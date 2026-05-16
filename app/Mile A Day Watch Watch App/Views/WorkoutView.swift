import SwiftUI
import HealthKit

// MARK: - Workout View
// Apple Workout-style paginated tracker — swipe between three pages:
//   1. Now Playing (distance + progress ring)
//   2. Live Stats (time / pace / HR / calories)
//   3. Controls (pause / end)
// With a 3-2-1 countdown before tracking begins and a polished recap at the end.

struct WorkoutView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    let goalDistance: Double
    let startingDistance: Double
    let activityType: HKWorkoutActivityType
    let locationType: HKWorkoutSessionLocationType
    @Environment(\.dismiss) var dismiss

    @StateObject private var workoutManager = WatchWorkoutManager()
    @State private var showRecap = false
    @State private var workoutStarted = false
    @State private var showEndConfirmation = false
    @State private var goalReached = false
    @State private var countdownNumber = 3
    @State private var showCountdown = true
    @State private var pageSelection: Int = 0

    private var currentDistance: Double { workoutManager.distance }

    private var totalDailyDistance: Double { startingDistance + workoutManager.distance }

    private var progress: Double { min(totalDailyDistance / goalDistance, 1.0) }

    private var isCompleted: Bool { totalDailyDistance >= goalDistance }

    private var activityName: String { activityType == .running ? "Run" : "Walk" }

    private var activityIcon: String { activityType == .running ? "figure.run" : "figure.walk" }

    var body: some View {
        ZStack {
            WatchTheme.appBackground
                .ignoresSafeArea()

            if showRecap {
                WorkoutRecapView(
                    distance: currentDistance,
                    duration: workoutManager.elapsedTime,
                    heartRate: workoutManager.averageHeartRate,
                    calories: workoutManager.calories,
                    activityName: activityName,
                    activityIcon: activityIcon,
                    goalReached: isCompleted,
                    onDismiss: { dismiss() }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if showCountdown {
                countdownView
                    .transition(.opacity)
            } else {
                trackingPager
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showCountdown)
        .animation(.easeInOut(duration: 0.35), value: showRecap)
        .onAppear {
            if !workoutStarted {
                workoutStarted = true
                runCountdown()
            }
        }
        .onChange(of: isCompleted) { _, newValue in
            if newValue && !goalReached {
                goalReached = true
                WKInterfaceDevice.current().play(.success)
            }
        }
    }

    // MARK: - Countdown

    private var countdownView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: activityIcon)
                Text(activityName.uppercased())
            }
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundColor(WatchTheme.madRedBright)
            .tracking(1.2)

            ZStack {
                Circle()
                    .stroke(WatchTheme.madRed.opacity(0.18), lineWidth: 4)
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(WatchTheme.madRed.opacity(0.15))
                    .frame(width: 120, height: 120)

                Text("\(countdownNumber)")
                    .font(.system(size: 78, weight: .heavy, design: .rounded))
                    .foregroundStyle(WatchTheme.primaryButton)
                    .id(countdownNumber) // re-render for transition
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }

            Text("Get ready")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(WatchTheme.textTertiary)
        }
    }

    private func runCountdown() {
        WKInterfaceDevice.current().play(.start)
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdownNumber > 1 {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                    countdownNumber -= 1
                }
                WKInterfaceDevice.current().play(.click)
            } else {
                timer.invalidate()
                WKInterfaceDevice.current().play(.success)
                withAnimation { showCountdown = false }
                workoutManager.startWorkout(activityType: activityType, locationType: locationType)
            }
        }
    }

    // MARK: - Paginated Tracker

    private var trackingPager: some View {
        TabView(selection: $pageSelection) {
            nowPlayingPage
                .tag(0)
            statsPage
                .tag(1)
            controlsPage
                .tag(2)
        }
        .tabViewStyle(.verticalPage)
        .confirmationDialog("End workout?", isPresented: $showEndConfirmation) {
            Button("End Workout", role: .destructive) { endWorkout() }
            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: - Page 1: Now Playing

    private var nowPlayingPage: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: activityIcon)
                Text(activityName.uppercased())
                if workoutManager.isPaused {
                    Text("· PAUSED")
                        .foregroundColor(WatchTheme.warning)
                }
            }
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundColor(workoutManager.isPaused ? WatchTheme.warning : WatchTheme.madRedBright)
            .tracking(1.0)

            progressRing
                .padding(.top, 2)

            goalLine
                .padding(.top, 4)

            pageDots
                .padding(.top, 4)
        }
        .padding(.horizontal, 8)
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 9)
                .frame(width: 128, height: 128)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isCompleted ? WatchTheme.progressGradientComplete : WatchTheme.progressGradient,
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .frame(width: 128, height: 128)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                .shadow(
                    color: (isCompleted ? WatchTheme.success : WatchTheme.madRedBright).opacity(0.35),
                    radius: 6, x: 0, y: 0
                )

            VStack(spacing: 0) {
                Text(String(format: "%.2f", currentDistance))
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundColor(WatchTheme.textPrimary)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("MI")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(WatchTheme.textTertiary)
                    .tracking(1.5)
            }
        }
    }

    @ViewBuilder
    private var goalLine: some View {
        if isCompleted {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Goal complete!")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(WatchTheme.successGradient)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(WatchTheme.success.opacity(0.18)))
        } else {
            Text(String(format: "%.2f mi to goal · %.2f today", max(goalDistance - totalDailyDistance, 0), totalDailyDistance))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(WatchTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Page 2: Stats

    private var statsPage: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                Text("STATS")
            }
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundColor(WatchTheme.textSecondary)
            .tracking(1.2)

            VStack(spacing: 6) {
                statRow(icon: "clock.fill", label: "Time", value: formattedTime, tint: WatchTheme.madRedBright)
                statRow(icon: "speedometer", label: "Pace", value: formattedPace, suffix: "/mi", tint: WatchTheme.warning)
                if workoutManager.currentHeartRate > 0 {
                    statRow(icon: "heart.fill", label: "Heart", value: "\(Int(workoutManager.currentHeartRate))", suffix: "bpm", tint: .red)
                }
                if workoutManager.calories > 0 {
                    statRow(icon: "flame.fill", label: "Cal", value: "\(Int(workoutManager.calories))", suffix: "kcal", tint: .orange)
                }
            }

            pageDots
                .padding(.top, 2)
        }
        .padding(.horizontal, 10)
    }

    private func statRow(icon: String, label: String, value: String, suffix: String? = nil, tint: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(tint)
            }
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(WatchTheme.textSecondary)
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(WatchTheme.textPrimary)
                    .contentTransition(.numericText())
                if let suffix {
                    Text(suffix)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(WatchTheme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WatchTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(WatchTheme.hairline, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Page 3: Controls

    private var controlsPage: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                Text("CONTROLS")
            }
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundColor(WatchTheme.textSecondary)
            .tracking(1.2)

            HStack(spacing: 14) {
                // Pause / Resume
                Button {
                    if workoutManager.isPaused {
                        workoutManager.resumeWorkout()
                    } else {
                        workoutManager.pauseWorkout()
                    }
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    controlCircle(
                        icon: workoutManager.isPaused ? "play.fill" : "pause.fill",
                        background: WatchTheme.warning,
                        foreground: .black
                    )
                }
                .buttonStyle(WatchPressStyle())

                // End workout
                Button {
                    showEndConfirmation = true
                } label: {
                    controlCircle(
                        icon: "stop.fill",
                        background: WatchTheme.madRed,
                        foreground: .white
                    )
                }
                .buttonStyle(WatchPressStyle())
            }
            .padding(.top, 2)

            Text(workoutManager.isPaused ? "Tap play to resume" : "Tap pause anytime")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(WatchTheme.textTertiary)

            pageDots
                .padding(.top, 2)
        }
        .padding(.horizontal, 10)
    }

    private func controlCircle(icon: String, background: Color, foreground: Color) -> some View {
        ZStack {
            Circle()
                .fill(background.opacity(0.22))
                .frame(width: 60, height: 60)
            Circle()
                .fill(background)
                .frame(width: 50, height: 50)
            Image(systemName: icon)
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(foreground)
        }
        .shadow(color: background.opacity(0.5), radius: 5, x: 0, y: 2)
    }

    // MARK: - Page Dots

    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(pageSelection == i ? WatchTheme.madRedBright : Color.white.opacity(0.22))
                    .frame(width: 4, height: 4)
            }
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let h = Int(workoutManager.elapsedTime) / 3600
        let m = Int(workoutManager.elapsedTime) / 60 % 60
        let s = Int(workoutManager.elapsedTime) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
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
        WKInterfaceDevice.current().play(.stop)
        workoutManager.endWorkout { success in
            if success {
                showRecap = true
            } else {
                // Even on failure, show the recap so the user sees their effort.
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
    let activityIcon: String
    let goalReached: Bool
    let onDismiss: () -> Void

    @State private var celebrate = false

    private var formattedTime: String {
        let h = Int(duration) / 3600
        let m = Int(duration) / 60 % 60
        let s = Int(duration) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
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
            VStack(spacing: 10) {
                // Hero badge
                ZStack {
                    Circle()
                        .fill(goalReached ? WatchTheme.success.opacity(0.18) : WatchTheme.madRed.opacity(0.18))
                        .frame(width: 64, height: 64)
                    Circle()
                        .fill(goalReached ? WatchTheme.success.opacity(0.12) : WatchTheme.madRed.opacity(0.12))
                        .frame(width: 82, height: 82)
                        .blur(radius: 4)
                    Image(systemName: goalReached ? "checkmark.seal.fill" : activityIcon)
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(goalReached ? WatchTheme.successGradient : WatchTheme.primaryButton)
                        .scaleEffect(celebrate ? 1.0 : 0.6)
                        .opacity(celebrate ? 1.0 : 0.0)
                        .animation(.spring(response: 0.55, dampingFraction: 0.6), value: celebrate)
                }
                .padding(.top, 6)

                Text(goalReached ? "Goal Complete!" : "Great \(activityName)!")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(WatchTheme.textPrimary)
                    .multilineTextAlignment(.center)

                // Primary stat
                VStack(spacing: 0) {
                    Text(String(format: "%.2f", distance))
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundColor(WatchTheme.textPrimary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("miles")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(WatchTheme.textTertiary)
                        .tracking(1.0)
                }

                // Stats card
                VStack(spacing: 6) {
                    recapRow(icon: "clock.fill", label: "Duration", value: formattedTime, tint: WatchTheme.madRedBright)
                    recapRow(icon: "speedometer", label: "Avg Pace", value: "\(formattedPace) /mi", tint: WatchTheme.warning)
                    if heartRate > 0 {
                        recapRow(icon: "heart.fill", label: "Avg HR", value: "\(Int(heartRate)) bpm", tint: .red)
                    }
                    if calories > 0 {
                        recapRow(icon: "flame.fill", label: "Calories", value: "\(Int(calories)) kcal", tint: .orange)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(WatchTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(WatchTheme.hairline, lineWidth: 0.5)
                        )
                )

                // Done button
                Button(action: onDismiss) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .heavy))
                        Text("Done")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(WatchTheme.primaryButton)
                    )
                    .shadow(color: WatchTheme.madRedDeep.opacity(0.5), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(WatchPressStyle())
                .padding(.top, 2)
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 8)
        }
        .onAppear {
            celebrate = true
            if goalReached {
                WKInterfaceDevice.current().play(.success)
            } else {
                WKInterfaceDevice.current().play(.stop)
            }
        }
    }

    private func recapRow(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 20, height: 20)
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(tint)
            }
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(WatchTheme.textSecondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(WatchTheme.textPrimary)
        }
    }
}
