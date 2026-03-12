import SwiftUI
import HealthKit

struct ContentView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var userManager: UserManager
    @State private var showWorkoutView = false
    @State private var selectedActivityType: HKWorkoutActivityType = .running

    // Theme
    private let accentRed = Color(red: 217/255, green: 64/255, blue: 63/255)

    private var goalDistance: Double {
        userManager.currentUser.goalMiles > 0 ? userManager.currentUser.goalMiles : 1.0
    }

    private var currentDistance: Double {
        healthManager.todaysDistance
    }

    private var progress: Double {
        min(currentDistance / goalDistance, 1.0)
    }

    private var isCompleted: Bool {
        currentDistance >= goalDistance
    }

    private var currentStreak: Int {
        healthManager.retroactiveStreak
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Progress ring with distance
                progressRing
                    .padding(.top, 4)

                // Streak pill
                streakPill

                // Action buttons
                actionButtons
                    .padding(.top, 4)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
        .fullScreenCover(isPresented: $showWorkoutView) {
            WorkoutView(
                healthManager: healthManager,
                userManager: userManager,
                goalDistance: goalDistance,
                startingDistance: currentDistance,
                activityType: selectedActivityType
            )
        }
        .onAppear {
            healthManager.fetchTodaysDistance()
        }
        .onChange(of: showWorkoutView) { oldValue, newValue in
            if oldValue && !newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    healthManager.fetchTodaysDistance()
                }
            }
        }
    }

    // MARK: - Progress Ring

    private var progressRing: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 12)
                .frame(width: 120, height: 120)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: isCompleted
                            ? [.green, .green.opacity(0.7), .green]
                            : [accentRed, .orange, accentRed.opacity(0.6)],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.7), value: progress)

            // Center content
            VStack(spacing: 1) {
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                }
                Text(String(format: "%.2f", currentDistance))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.7)
                Text("/ \(String(format: "%.1f", goalDistance)) mi")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Streak Pill

    private var streakPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)
            Text("\(currentStreak)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("day streak")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.1))
        )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 10) {
            // Run button
            Button {
                selectedActivityType = .running
                showWorkoutView = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                    Text("Run")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(accentRed)
                )
            }
            .buttonStyle(.plain)

            // Walk button
            Button {
                selectedActivityType = .walking
                showWorkoutView = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                    Text("Walk")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(HealthKitManager.shared)
        .environmentObject(UserManager.shared)
}
