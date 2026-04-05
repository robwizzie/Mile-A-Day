import SwiftUI

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
