import SwiftUI
import HealthKit

struct ContentView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var userManager: UserManager
    @State private var showWorkoutView = false

    private var currentState: DayState {
        healthManager.getCurrentDayState(for: userManager.user)
    }

    private var progress: Double {
        min(currentState.distance / currentState.goal, 1.0)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Streak display
                VStack(spacing: 4) {
                    Text("\(healthManager.currentStreak)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)

                    Text("Day Streak")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                // Today's progress
                VStack(spacing: 12) {
                    Text("Today")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    // Progress ring
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 10)
                            .frame(width: 120, height: 120)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                LinearGradient(
                                    colors: progress >= 1.0 ? [.green, .green] : [.orange, .red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.5), value: progress)

                        VStack(spacing: 2) {
                            Text(String(format: "%.2f", currentState.distance))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("miles")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Goal text
                    Text("Goal: \(String(format: "%.1f", currentState.goal)) mi")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Completion status
                    if currentState.isCompleted {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Goal Complete!")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                // Start workout button
                Button(action: {
                    showWorkoutView = true
                }) {
                    HStack {
                        Image(systemName: "figure.run")
                            .font(.title3)
                        Text("Start Mile")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.horizontal)
            }
            .navigationTitle("Mile A Day")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(isPresented: $showWorkoutView) {
            WorkoutView(
                healthManager: healthManager,
                userManager: userManager,
                goalDistance: currentState.goal,
                startingDistance: currentState.distance
            )
        }
        .onAppear {
            // Refresh data when view appears
            healthManager.fetchLatestWorkoutData()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(HealthKitManager.shared)
            .environmentObject(UserManager.shared)
    }
}
