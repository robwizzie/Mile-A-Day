import SwiftUI
import HealthKit

struct ContentView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var userManager: UserManager
    @State private var showWorkoutView = false

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
        NavigationView {
            VStack(spacing: 16) {
                // Streak display
                VStack(spacing: 4) {
                    Text("\(currentStreak)")
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
                            Text(String(format: "%.2f", currentDistance))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("miles")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Goal text
                    Text("Goal: \(String(format: "%.1f", goalDistance)) mi")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Completion status
                    if isCompleted {
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
                goalDistance: goalDistance,
                startingDistance: currentDistance
            )
        }
        .onAppear {
            // Refresh data when view appears
            healthManager.fetchTodaysDistance()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(HealthKitManager.shared)
        .environmentObject(UserManager.shared)
}
