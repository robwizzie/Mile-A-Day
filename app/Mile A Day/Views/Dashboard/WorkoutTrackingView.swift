import SwiftUI
import HealthKit
import CoreLocation
import CoreMotion
import ActivityKit

// MARK: - Workout Tracking View

// Location Manager for tracking distance during workouts.
//
// Distance tracking modes:
//   - Outdoor (GPS): Incremental — each location update adds a delta to currentDistance.
//   - Indoor (Pedometer): Cumulative — pedometer reports total distance since its start.
//     We add a `pedometerOffset` so recovered workouts don't lose prior distance.
//
// The key invariant: currentDistance must NEVER be overwritten with a smaller value
// by the tracking system itself. Only stopTracking() and explicit reset can clear it.
class WorkoutLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let pedometer = CMPedometer()
    private var lastLocation: CLLocation?
    private var isUsingPedometer = false
    private var isTracking = false

    // For indoor pedometer mode: the pedometer reports cumulative distance from its
    // start date. When recovering a workout, we set this offset to the previously
    // accumulated distance so the pedometer's new readings ADD to it instead of
    // replacing it. For GPS mode this is unused (GPS is incremental).
    private var pedometerOffset: Double = 0.0

    @Published var currentDistance: Double = 0.0 // Distance in miles
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = locationManager.authorizationStatus
    }

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Start tracking distance.
    ///
    /// - Parameters:
    ///   - locationType: `.outdoor` for GPS, `.indoor` for pedometer.
    ///   - initialDistance: Distance already accumulated in a prior session (0 for new workouts).
    ///     For GPS mode, this becomes the starting value that incremental updates add to.
    ///     For pedometer mode, this becomes the offset added to the pedometer's readings.
    func startTracking(locationType: HKWorkoutSessionLocationType = .outdoor, initialDistance: Double = 0.0) {
        // Prevent double-start
        guard !isTracking else { return }
        isTracking = true

        currentDistance = initialDistance
        lastLocation = nil
        isUsingPedometer = (locationType == .indoor)
        pedometerOffset = initialDistance

        if locationType == .indoor {
            if CMPedometer.isDistanceAvailable() {
                pedometer.startUpdates(from: Date()) { [weak self] pedometerData, error in
                    guard let self = self, let data = pedometerData, error == nil else { return }

                    if let distance = data.distance {
                        let distanceInMiles = distance.doubleValue * 0.000621371
                        let newTotal = self.pedometerOffset + distanceInMiles
                        DispatchQueue.main.async {
                            self.currentDistance = newTotal
                        }
                    }
                }
            } else {
                isUsingPedometer = false
                startGPSTracking()
            }
        } else {
            startGPSTracking()
        }
    }

    private func startGPSTracking() {
        if authorizationStatus == .notDetermined {
            requestPermission()
        }
        locationManager.startUpdatingLocation()
    }

    func stopTracking() {
        guard isTracking else { return }
        isTracking = false

        if isUsingPedometer {
            pedometer.stopUpdates()
        } else {
            locationManager.stopUpdatingLocation()
        }
        lastLocation = nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }

        // Only use accurate locations
        guard newLocation.horizontalAccuracy > 0 && newLocation.horizontalAccuracy < 50 else {
            return
        }

        // Calculate distance if we have a previous location
        if let lastLocation = lastLocation {
            let distance = newLocation.distance(from: lastLocation) // meters
            let distanceInMiles = distance * 0.000621371

            // Only add distance if it's reasonable (not a GPS jump)
            if distanceInMiles < 0.1 {
                DispatchQueue.main.async {
                    self.currentDistance += distanceInMiles
                }
            }
        }

        lastLocation = newLocation

        // Persist route point for recovery
        InProgressWorkoutStore.addRoutePoint(newLocation)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[WorkoutLocationManager] Error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}

// MARK: - In‑Progress Workout Banner

/// Compact banner shown on the dashboard when there is an in‑progress workout
/// but the full‑screen tracker has been dismissed. Tapping it resumes the workout.
struct InProgressWorkoutBanner: View {
    let state: InProgressWorkoutState
    let onResume: () -> Void

    @State private var currentTime = Date()
    @State private var latestState: InProgressWorkoutState?

    // Compute real-time elapsed time based on start time
    private var realTimeElapsedSeconds: TimeInterval {
        if let latest = latestState {
            return currentTime.timeIntervalSince(latest.startTime)
        }
        return currentTime.timeIntervalSince(state.startTime)
    }

    private var formattedTime: String {
        let minutes = Int(realTimeElapsedSeconds) / 60
        let seconds = Int(realTimeElapsedSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var currentDistance: Double {
        latestState?.currentDistance ?? state.currentDistance
    }

    var body: some View {
        Button(action: onResume) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 0.25, blue: 0.35),
                                    Color(red: 0.7, green: 0.2, blue: 0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: "play.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .bold))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Workout in progress")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Text("\(String(format: "%.2f", currentDistance)) mi • \(formattedTime)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            // Start a timer to update the time display every second
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                currentTime = Date()
                // Reload the latest state to get updated distance
                if let updated = InProgressWorkoutStore.load(), updated.isActive {
                    latestState = updated
                }
            }
        }
    }
}

struct WorkoutTrackingView: View {
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var userManager: UserManager
    let goalDistance: Double
    let startingDistance: Double
    @Environment(\.dismiss) var dismiss

    @StateObject private var locationManager = WorkoutLocationManager()
    @State private var showActivitySelection = true
    @State private var showLocationTypeSelection = false
    @State private var selectedActivityType: HKWorkoutActivityType?
    @State private var selectedLocationType: HKWorkoutSessionLocationType = .outdoor
    @State private var countdownNumber = 3
    @State private var showCountdown = false
    @State private var isTracking = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var workoutStartDate: Date?
    @State private var showCompletion = false
    @State private var hasShownCompletion = false // Track if we've already shown completion
    @State private var showPreviousProgress = false // Show notification when reaching previous progress
    @State private var hasReachedPreviousProgress = false // Track if we've reached starting distance
    @State private var showRecap = false
    @State private var showStopConfirmation = false // Confirmation before ending workout
    @State private var isStopping = false // Prevents double-stop and shows "Ending..." UI
    @State private var showEndWorkoutError = false // Show error alert when end fails
    @State private var endWorkoutErrorMessage = "" // Error message for end workout failure
    @State private var endWorkoutTimeoutTask: DispatchWorkItem? // Timeout for end workout flow
    @State private var workoutSession: HKWorkoutSession?
    @State private var workoutBuilder: HKWorkoutBuilder?
    @State private var workoutActivity: Activity<WorkoutActivityAttributes>?

    // Workout distance only (starts at 0)
    private var currentDistance: Double {
        locationManager.currentDistance
    }

    // Total daily distance (starting + workout)
    private var totalDailyDistance: Double {
        startingDistance + locationManager.currentDistance
    }

    private var progress: Double {
        min(totalDailyDistance / goalDistance, 1.0)
    }

    private var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        ZStack {
            // Red gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.25, blue: 0.35),  // Top: lighter red
                    Color(red: 0.7, green: 0.2, blue: 0.3),     // Mid-top
                    Color(red: 0.5, green: 0.15, blue: 0.2),    // Mid-bottom
                    Color(red: 0.3, green: 0.1, blue: 0.15)     // Bottom: darker red
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if showActivitySelection {
                // Activity selection view
                VStack(spacing: 0) {
                    // Back button at top
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("Back")
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                        Spacer()
                    }
                    .padding(.top, 16)

                    VStack(spacing: 40) {
                        Spacer()

                        // Header
                        VStack(spacing: 16) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 60))
                                .foregroundColor(.white)

                            Text("Choose Activity Type")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Text("Select how you'll complete your mile")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)

                        Spacer()

                    // Activity buttons
                    VStack(spacing: 20) {
                        // Run button
                        Button(action: {
                            selectActivity(.running)
                        }) {
                            HStack(spacing: 16) {
                                Image(systemName: "figure.run")
                                    .font(.system(size: 32))
                                    .frame(width: 50)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Run")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                    Text("Track as a running workout")
                                        .font(.subheadline)
                                        .opacity(0.9)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(24)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Walk button
                        Button(action: {
                            selectActivity(.walking)
                        }) {
                            HStack(spacing: 16) {
                                Image(systemName: "figure.walk")
                                    .font(.system(size: 32))
                                    .frame(width: 50)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Walk")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                    Text("Track as a walking workout")
                                        .font(.subheadline)
                                        .opacity(0.9)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(24)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 32)

                        Spacer()
                    }
                }
            } else if showLocationTypeSelection {
                // Location type selection view (Indoor/Outdoor)
                VStack(spacing: 0) {
                    // Back button at top
                    HStack {
                        Button(action: {
                            withAnimation {
                                showLocationTypeSelection = false
                                showActivitySelection = true
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("Back")
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                        Spacer()
                    }
                    .padding(.top, 16)

                    VStack(spacing: 40) {
                        Spacer()

                        // Header
                        VStack(spacing: 16) {
                            Image(systemName: selectedActivityType == .running ? "figure.run" : "figure.walk")
                                .font(.system(size: 60))
                                .foregroundColor(.white)

                            Text("Choose Location")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Text("Where will you be working out?")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)

                        Spacer()

                    // Location type buttons
                    VStack(spacing: 20) {
                        // Outdoor button
                        Button(action: {
                            selectLocationType(.outdoor)
                        }) {
                            HStack(spacing: 16) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 32))
                                    .frame(width: 50)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Outdoor")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                    Text("Uses GPS for accurate tracking")
                                        .font(.subheadline)
                                        .opacity(0.9)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(24)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Indoor button
                        Button(action: {
                            selectLocationType(.indoor)
                        }) {
                            HStack(spacing: 16) {
                                Image(systemName: "figure.indoor.cycle")
                                    .font(.system(size: 32))
                                    .frame(width: 50)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Indoor")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                    Text("Uses motion sensors for distance")
                                        .font(.subheadline)
                                        .opacity(0.9)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(24)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 32)

                        Spacer()
                    }
                }
            } else if showCountdown {
                // Countdown view
                VStack {
                    Text("\(countdownNumber)")
                        .font(.system(size: 120, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .scaleEffect(countdownNumber > 0 ? 1.0 : 0.5)
                        .opacity(countdownNumber > 0 ? 1.0 : 0.0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: countdownNumber)
                }
                .onAppear {
                    startCountdown()
                }
            } else if showRecap {
                WorkoutRecapView(
                    distance: currentDistance,
                    duration: elapsedTime,
                    goalDistance: goalDistance,
                    onDismiss: {
                        dismiss()
                    }
                )
            } else {
                // Tracking view
                VStack(spacing: 40) {
                    // Back button to minimize workout and return to dashboard
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("Dashboard")
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                        Spacer()
                    }
                    .padding(.top, 16)

                    Spacer()

                    // Distance display
                    VStack(spacing: 12) {
                        Text("DISTANCE")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.7))
                            .tracking(1.5)

                        // Main counter - Workout distance (starts at 0)
                        Text(String(format: "%.2f", currentDistance))
                            .font(.system(size: 80, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .contentTransition(.numericText())

                        Text("miles")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.8))

                        // Smaller daily total counter
                        if startingDistance > 0 {
                            VStack(spacing: 4) {
                                Text("Daily Total: \(String(format: "%.2f", totalDailyDistance)) mi")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .padding(.top, 4)
                        }
                    }

                    // Progress ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 12)
                            .frame(width: 200, height: 200)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                LinearGradient(
                                    colors: progress >= 1.0 ? [.green, .green] : [.orange, .red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )
                            .frame(width: 200, height: 200)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.5), value: progress)

                        VStack(spacing: 4) {
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("of goal")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    // Time display
                    VStack(spacing: 8) {
                        Text("TIME")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.7))
                            .tracking(1.5)

                        Text(formattedTime)
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .monospacedDigit()
                    }

                    Spacer()

                    // Stop button - shows confirmation dialog
                    Button(action: {
                        showStopConfirmation = true
                    }) {
                        HStack(spacing: 12) {
                            if isStopping {
                                ProgressView()
                                    .tint(.white)
                                Text("Ending...")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            } else {
                                Image(systemName: "stop.fill")
                                    .font(.title2)
                                Text("Stop Workout")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.red.opacity(isStopping ? 0.15 : 0.3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.red.opacity(isStopping ? 0.5 : 1.0), lineWidth: 2)
                                )
                        )
                    }
                    .disabled(isStopping)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                    .buttonStyle(PlainButtonStyle())
                }
                .opacity(showCompletion || showPreviousProgress ? 0 : 1)
                .overlay(
                    // Previous progress notification
                    Group {
                        if showPreviousProgress {
                            VStack(spacing: 20) {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.blue)
                                    .scaleEffect(showPreviousProgress ? 1.0 : 0.5)
                                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showPreviousProgress)

                                Text("Back to where you were!")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)

                                Text("\(String(format: "%.2f", startingDistance)) miles reached")
                                    .font(.title3)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                )
                .overlay(
                    // Goal completion celebration
                    Group {
                        if showCompletion {
                            VStack(spacing: 24) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 100))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.green, .green.opacity(0.7)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .scaleEffect(showCompletion ? 1.0 : 0.5)
                                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showCompletion)

                                Text("Goal Complete!")
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)

                                Text("You did it! Keep going or finish your workout.")
                                    .font(.title3)
                                    .foregroundColor(.white.opacity(0.9))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                )
            }
        }
        .onChange(of: currentDistance) { oldValue, newValue in
            // Check if we've reached the previous progress point
            if !hasReachedPreviousProgress && startingDistance > 0 && newValue >= startingDistance {
                hasReachedPreviousProgress = true

                // Show notification that they've reached where they were
                withAnimation {
                    showPreviousProgress = true
                }

                // Haptic feedback
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)

                // Hide notification after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showPreviousProgress = false
                    }
                }
            }

            // Check if we've reached the goal (using total daily distance)
            // Only show completion if:
            // 1. We haven't shown it yet
            // 2. The goal wasn't already completed when we started (startingDistance < goalDistance)
            // 3. We've now reached the goal with total daily distance
            if !hasShownCompletion && startingDistance < goalDistance && totalDailyDistance >= goalDistance {
                hasShownCompletion = true // Mark as shown so it doesn't loop

                // Show completion celebration
                withAnimation {
                    showCompletion = true
                }

                // Haptic feedback
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)

                // Hide completion after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showCompletion = false
                    }
                }
            }
        }
        .onDisappear {
            // When the view disappears (e.g., user dismisses to dashboard),
            // do a final Live Activity update and state save so the Dynamic Island
            // shows current data while the view is gone.
            if isTracking && !isStopping {
                updateLiveActivity()
            }

            // Stop the timer to save battery. The workout state remains persisted
            // so we can restore it when the user comes back.
            timer?.invalidate()
            timer = nil
        }
        .alert("End Workout?", isPresented: $showStopConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End Workout", role: .destructive) {
                stopWorkout()
            }
        } message: {
            Text("Are you sure you want to end this workout? Your progress will be saved to HealthKit.")
        }
        .alert("Couldn't Save Workout", isPresented: $showEndWorkoutError) {
            Button("OK") {
                // Dismiss back to dashboard since the workout state is already cleared
                dismiss()
            }
        } message: {
            Text(endWorkoutErrorMessage)
        }
        .onAppear {
            // Workout recovery: if there's a persisted in-progress workout, restore it.
            // Guard: skip if we're currently ending a workout or already tracking.
            guard !isStopping, !isTracking else { return }
            guard let saved = InProgressWorkoutStore.load(), saved.isActive else { return }

            // Restore core state
            workoutStartDate = saved.startTime
            elapsedTime = max(0, Date().timeIntervalSince(saved.startTime))

            // Restore activity + location type
            if saved.activityType == "Running" {
                selectedActivityType = .running
            } else if saved.activityType == "Walking" {
                selectedActivityType = .walking
            }
            if let locationType = HKWorkoutSessionLocationType(rawValue: saved.locationTypeRawValue) {
                selectedLocationType = locationType
            }

            // Jump directly into the tracking UI
            showActivitySelection = false
            showLocationTypeSelection = false
            showCountdown = false
            isTracking = true

            // Resume tracking with the saved distance as the starting point.
            // For pedometer: new pedometer readings will ADD to saved.currentDistance.
            // For GPS: new GPS deltas will add to saved.currentDistance.
            locationManager.startTracking(locationType: selectedLocationType, initialDistance: saved.currentDistance)

            // Restart HKWorkoutBuilder (non-blocking, best-effort)
            healthManager.requestAuthorization { authorized in
                guard authorized else { return }

                let configuration = HKWorkoutConfiguration()
                configuration.activityType = self.selectedActivityType ?? .walking
                configuration.locationType = self.selectedLocationType

                let healthStore = HKHealthStore()
                let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
                self.workoutBuilder = builder

                builder.beginCollection(withStart: saved.startTime) { _, _ in }
            }

            // Restart timer and Live Activity
            startWorkoutTimer()
            startLiveActivity()
        }
    }

    private func selectActivity(_ activityType: HKWorkoutActivityType) {
        selectedActivityType = activityType

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Hide activity selection and show location type selection
        withAnimation {
            showActivitySelection = false
            showLocationTypeSelection = true
        }
    }

    private func selectLocationType(_ locationType: HKWorkoutSessionLocationType) {
        selectedLocationType = locationType

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Hide location type selection and show countdown
        withAnimation {
            showLocationTypeSelection = false
            showCountdown = true
            countdownNumber = 3 // Reset countdown
        }
    }

    private func startCountdown() {
        // Haptic feedback for countdown
        let impact = UIImpactFeedbackGenerator(style: .heavy)

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdownNumber > 1 {
                countdownNumber -= 1
                impact.impactOccurred()
            } else {
                timer.invalidate()
                // Start workout
                withAnimation {
                    showCountdown = false
                    isTracking = true
                }
                startWorkout()
            }
        }
    }

    private func startWorkout() {
        // Acquire workout lock to enforce single workout at a time
        guard InProgressWorkoutStore.acquireLock() else {
            endWorkoutErrorMessage = "Another Mile A Day workout is already active. Please finish or cancel that workout first."
            showEndWorkoutError = true
            return
        }

        workoutStartDate = Date()

        // Immediately persist initial workout state
        let initialState = InProgressWorkoutState(
            isActive: true,
            isPaused: false,
            startTime: workoutStartDate!,
            elapsedTime: 0,
            pausedTime: 0,
            currentDistance: 0,
            startingDistance: startingDistance,
            totalDailyDistance: totalDailyDistance,
            goalDistance: goalDistance,
            activityType: selectedActivityType == .running ? "Running" : "Walking",
            locationTypeRawValue: selectedLocationType.rawValue,
            workoutUUID: UUID().uuidString,
            lastSaveTime: Date(),
            routePoints: [],
            isUsingPedometer: selectedLocationType == .indoor,
            liveActivityID: nil
        )
        InProgressWorkoutStore.save(initialState)

        // Start location/pedometer tracking (fresh workout, initialDistance = 0)
        locationManager.startTracking(locationType: selectedLocationType, initialDistance: 0)

        // Start Live Activity
        startLiveActivity()

        // Start the timer IMMEDIATELY — don't wait for HealthKit authorization.
        // The timer drives both the UI clock and periodic state persistence.
        startWorkoutTimer()

        // Set up HKWorkoutBuilder in the background (non-blocking).
        // If this fails, the workout still tracks distance; it just won't save to HealthKit.
        healthManager.requestAuthorization { authorized in
            guard authorized else { return }

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = self.selectedActivityType ?? .walking
            configuration.locationType = self.selectedLocationType

            let healthStore = HKHealthStore()
            let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
            self.workoutBuilder = builder

            builder.beginCollection(withStart: self.workoutStartDate ?? Date()) { _, _ in }
        }
    }

    /// Start (or restart) the workout timer that drives the UI clock and periodic state saves.
    private func startWorkoutTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            guard let startDate = workoutStartDate else { return }
            // Don't persist state while we're in the middle of stopping
            guard !isStopping else { return }
            elapsedTime = Date().timeIntervalSince(startDate)
            updateLiveActivity()
        }
    }

    private func stopWorkout() {
        guard !isStopping else { return }
        isStopping = true

        // Capture final distance before stopping tracking
        let finalDistance = currentDistance

        // Flush any buffered route points
        InProgressWorkoutStore.flushRoutePoints()

        // Stop timer and location tracking
        timer?.invalidate()
        timer = nil
        locationManager.stopTracking()

        // Safety timeout: if HealthKit callbacks never fire, force-cleanup after 10s
        let timeout = DispatchWorkItem { [self] in
            finishCleanup(workoutSaved: false)
        }
        endWorkoutTimeoutTask = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)

        // If we have no builder (e.g. HK auth failed), skip straight to cleanup
        guard let builder = workoutBuilder, let startDate = workoutStartDate else {
            finishCleanup(workoutSaved: false)
            return
        }

        // Clear references now (the local `builder` variable keeps the object alive for callbacks)
        workoutSession = nil
        workoutBuilder = nil

        let endDate = Date()

        // Async chain: add distance sample → end collection → finish workout → cleanup.
        // Every step proceeds regardless of whether the previous step failed.
        let addCompletion: (Bool, Error?) -> Void = { _, _ in
            builder.endCollection(withEnd: endDate) { _, _ in
                builder.finishWorkout { workout, error in
                    let saved = (workout != nil && error == nil)
                    DispatchQueue.main.async {
                        self.finishCleanup(workoutSaved: saved)
                        if saved {
                            self.healthManager.fetchAllWorkoutData()
                        }
                    }
                }
            }
        }

        if finalDistance > 0 {
            let distanceMeters = finalDistance / 0.000621371
            let distanceQuantity = HKQuantity(unit: HKUnit.meter(), doubleValue: distanceMeters)
            let sample = HKQuantitySample(
                type: HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
                quantity: distanceQuantity,
                start: startDate,
                end: endDate
            )
            builder.add([sample], completion: addCompletion)
        } else {
            addCompletion(true, nil)
        }
    }

    /// Force-end a stuck workout without saving to HealthKit.
    private func forceEndWorkout() {
        endWorkoutTimeoutTask?.cancel()
        endWorkoutTimeoutTask = nil
        timer?.invalidate()
        timer = nil
        locationManager.stopTracking()
        endLiveActivity()
        InProgressWorkoutStore.clear()
        workoutSession = nil
        workoutBuilder = nil
        isStopping = false
        isTracking = false
        dismiss()
    }

    // MARK: - Workout Cleanup

    /// Final cleanup after a workout ends. Always clears persisted state to prevent zombie sessions.
    private func finishCleanup(workoutSaved: Bool) {
        // Guard against double-execution (timeout + normal callback both fire)
        guard isStopping else { return }

        // Cancel timeout (we got here normally)
        endWorkoutTimeoutTask?.cancel()
        endWorkoutTimeoutTask = nil

        // End Live Activity
        endLiveActivity()

        // ALWAYS clear persisted state. Leaving it active on failure was causing
        // permanent corruption that required reinstalling the app.
        InProgressWorkoutStore.clear()

        // Mark stopping as done BEFORE showing UI, so no timer/update callbacks can re-save state
        isStopping = false
        isTracking = false

        // Show result to user
        if workoutSaved {
            withAnimation { showRecap = true }
        } else {
            endWorkoutErrorMessage = "Your workout couldn't be saved to HealthKit. The distance you covered will still count from GPS/pedometer data on your next sync."
            showEndWorkoutError = true
        }
    }

    // MARK: - Live Activity Management

    private func startLiveActivity() {
        // CRITICAL FIX: Check for existing Live Activities before creating a new one
        // This prevents creating multiple activities when app restarts

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities are not enabled")
            return
        }

        // First, check if we already have a reference to an active Live Activity
        if let existingActivity = workoutActivity {
            print("✅ Live Activity already exists in memory: \(existingActivity.id)")
            return
        }

        // Second, check for any running Live Activities (in case app was killed and restarted)
        let existingActivities = Activity<WorkoutActivityAttributes>.activities
        print("🔍 Found \(existingActivities.count) existing Live Activities")

        // Try to find an active Live Activity that matches our current workout
        if let matchingActivity = existingActivities.first(where: { activity in
            let timeDiff = abs(activity.attributes.startTime.timeIntervalSince(workoutStartDate ?? Date()))
            return timeDiff < 5.0 // Within 5 seconds of our workout start time
        }) {
            print("✅ Found matching Live Activity from previous session: \(matchingActivity.id)")
            workoutActivity = matchingActivity

            // Save the Live Activity ID to persistent storage
            if var state = InProgressWorkoutStore.load() {
                state.liveActivityID = matchingActivity.id
                InProgressWorkoutStore.save(state)
            }
            return
        }

        // Clean up any orphaned Live Activities that don't match our workout
        for orphanedActivity in existingActivities {
            let timeDiff = abs(orphanedActivity.attributes.startTime.timeIntervalSince(workoutStartDate ?? Date()))
            if timeDiff > 5.0 {
                print("🗑️ Ending orphaned Live Activity: \(orphanedActivity.id)")
                Task {
                    await orphanedActivity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }

        // No matching activity found, create a new one
        print("📱 Creating new Live Activity...")

        let attributes = WorkoutActivityAttributes(
            startTime: workoutStartDate ?? Date(),
            goalDistance: goalDistance
        )

        // Compute real-time elapsed time from start date
        let realTimeElapsed: TimeInterval
        if let startDate = workoutStartDate {
            realTimeElapsed = Date().timeIntervalSince(startDate)
        } else {
            realTimeElapsed = 0
        }

        let initialState = WorkoutActivityAttributes.ContentState(
            distance: currentDistance,
            totalDailyDistance: totalDailyDistance,
            elapsedTime: realTimeElapsed,
            goalDistance: goalDistance,
            activityType: selectedActivityType == .running ? "Running" : "Walking"
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            workoutActivity = activity
            print("✅ Live Activity created: \(activity.id)")

            // CRITICAL: Save the Live Activity ID to persistent storage
            if var state = InProgressWorkoutStore.load() {
                state.liveActivityID = activity.id
                InProgressWorkoutStore.save(state)
                print("✅ Live Activity ID saved to persistent storage")
            }
        } catch {
            print("❌ Failed to start Live Activity: \(error)")
        }
    }

    /// Called once per second by the workout timer.
    /// Updates the Live Activity and persists current state for recovery.
    private func updateLiveActivity() {
        // CRITICAL: Never persist state while stopping — finishCleanup may have already cleared it.
        guard !isStopping else { return }

        let freshDistance = locationManager.currentDistance
        let freshTotalDaily = startingDistance + freshDistance
        let realTimeElapsed = workoutStartDate.map { Date().timeIntervalSince($0) } ?? elapsedTime

        // Update Live Activity (if we have one)
        if workoutActivity == nil {
            startLiveActivity()
        }
        if let activity = workoutActivity {
            let updatedState = WorkoutActivityAttributes.ContentState(
                distance: freshDistance,
                totalDailyDistance: freshTotalDaily,
                elapsedTime: realTimeElapsed,
                goalDistance: goalDistance,
                activityType: selectedActivityType == .running ? "Running" : "Walking"
            )
            Task {
                await activity.update(ActivityContent(state: updatedState, staleDate: nil))
            }
        }

        // Persist state for recovery (only update EXISTING state, never create new).
        InProgressWorkoutStore.flushRoutePoints()
        if var existingState = InProgressWorkoutStore.load() {
            existingState.elapsedTime = realTimeElapsed
            existingState.currentDistance = freshDistance
            existingState.totalDailyDistance = freshTotalDaily
            existingState.lastSaveTime = Date()
            existingState.liveActivityID = workoutActivity?.id
            InProgressWorkoutStore.save(existingState)
        }
    }

    private func endLiveActivity() {
        // End all Live Activities for this workout.
        // NOTE: This does NOT clear InProgressWorkoutStore — the caller is responsible
        // for clearing state after confirming HealthKit save status.
        print("🔚 Ending Live Activity...")

        // Use FRESH data for the final state
        let freshDistance = locationManager.currentDistance
        let freshTotalDaily = startingDistance + freshDistance
        let realTimeElapsed = workoutStartDate.map { Date().timeIntervalSince($0) } ?? elapsedTime

        let finalState = WorkoutActivityAttributes.ContentState(
            distance: freshDistance,
            totalDailyDistance: freshTotalDaily,
            elapsedTime: realTimeElapsed,
            goalDistance: goalDistance,
            activityType: selectedActivityType == .running ? "Running" : "Walking"
        )

        // Capture the ID before clearing the reference so the orphan cleanup can exclude it
        let endedActivityID = workoutActivity?.id

        // End the Live Activity we have a reference to
        if let activity = workoutActivity {
            Task {
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .after(.now + 5) // Keep visible for 5 seconds
                )
                print("✅ Ended Live Activity: \(activity.id)")
            }
            workoutActivity = nil
        }

        // Also end any orphaned Live Activities (e.g. from previous crashed sessions)
        Task {
            let allActivities = Activity<WorkoutActivityAttributes>.activities
            for orphanedActivity in allActivities {
                if orphanedActivity.id != endedActivityID {
                    print("🗑️ Cleaning up orphaned Live Activity: \(orphanedActivity.id)")
                    await orphanedActivity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }
}

// MARK: - Workout Recap View

struct WorkoutRecapView: View {
    let distance: Double
    let duration: TimeInterval
    let goalDistance: Double
    let onDismiss: () -> Void

    private var formattedTime: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var pace: String {
        guard distance > 0 else { return "--:--" }
        let paceSeconds = duration / distance
        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        ZStack {
            // Transparent background
            Color.clear
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Header
                VStack(spacing: 12) {
                    Image(systemName: distance >= goalDistance ? "checkmark.circle.fill" : "flag.checkered.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: distance >= goalDistance ? [.green, .green] : [.orange, .red],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text(distance >= goalDistance ? "Workout Complete!" : "Great Work!")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if distance >= goalDistance {
                        Text("You reached your goal!")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }

                // Stats
                VStack(spacing: 20) {
                    StatRow(icon: "figure.walk", label: "Distance", value: String(format: "%.2f mi", distance))
                    StatRow(icon: "clock.fill", label: "Time", value: formattedTime)
                    StatRow(icon: "speedometer", label: "Avg Pace", value: "\(pace) /mi")

                    if distance >= goalDistance {
                        StatRow(icon: "target", label: "Goal", value: "✓ Completed")
                    } else {
                        StatRow(icon: "target", label: "Goal Progress", value: String(format: "%.0f%%", (distance / goalDistance) * 100))
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 32)

                Spacer()

                // Done button
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 217/255, green: 64/255, blue: 63/255),
                                            Color(red: 180/255, green: 50/255, blue: 50/255)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: Color(red: 217/255, green: 64/255, blue: 63/255).opacity(0.4), radius: 12, x: 0, y: 6)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct StatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 32)

            Text(label)
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))

            Spacer()

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
}
