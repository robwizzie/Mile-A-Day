import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Activity Attributes

struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var distance: Double // Current workout distance in miles
        var totalDailyDistance: Double // Total for the day
        var elapsedTime: TimeInterval // Time in seconds
        var goalDistance: Double
        var activityType: String // "Running" or "Walking"
    }

    var startTime: Date
    var goalDistance: Double
}

// MARK: - Live Activity Widget

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // Lock screen / banner UI
            WorkoutLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: context.state.activityType == "Running" ? "figure.run" : "figure.walk")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)

                            Text(context.state.activityType)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white.opacity(0.9))
                        }

                        Text(String(format: "%.2f mi", context.state.distance))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("TIME")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))

                        Text(formatTime(context.state.elapsedTime))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .monospacedDigit()
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 8)

                                // Progress fill
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: progressColors(for: context.state.totalDailyDistance / context.state.goalDistance),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(
                                        width: geometry.size.width * min(context.state.totalDailyDistance / context.state.goalDistance, 1.0),
                                        height: 8
                                    )
                            }
                        }
                        .frame(height: 8)

                        // Stats row
                        HStack {
                            if context.state.totalDailyDistance > context.state.distance {
                                Text("Daily: \(String(format: "%.2f", context.state.totalDailyDistance)) mi")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.7))
                            }

                            Spacer()

                            Text("Goal: \(String(format: "%.2f", context.state.goalDistance)) mi")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 12)
                }
            } compactLeading: {
                // Compact leading (left side of Dynamic Island)
                Image(systemName: context.state.activityType == "Running" ? "figure.run" : "figure.walk")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            } compactTrailing: {
                // Compact trailing (right side of Dynamic Island)
                Text(formatTime(context.state.elapsedTime))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            } minimal: {
                // Minimal (when multiple Live Activities are active)
                Image(systemName: context.state.activityType == "Running" ? "figure.run" : "figure.walk")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }
        }
    }

    private func progressColors(for progress: Double) -> [Color] {
        if progress >= 1.0 {
            return [Color.green, Color.green.opacity(0.8)]
        } else {
            return [
                Color(red: 1.0, green: 0.6, blue: 0.2),  // Orange
                Color(red: 0.9, green: 0.3, blue: 0.3)   // Red
            ]
        }
    }

    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Lock Screen View

struct WorkoutLiveActivityView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var progress: Double {
        min(context.state.totalDailyDistance / context.state.goalDistance, 1.0)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Left side - Activity icon & type
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: context.state.activityType == "Running" ? "figure.run" : "figure.walk")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)

                    Text(context.state.activityType)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }

                // Distance
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.2f", context.state.distance))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("miles")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                // Daily total if different
                if context.state.totalDailyDistance > context.state.distance {
                    Text("Daily: \(String(format: "%.2f", context.state.totalDailyDistance)) mi")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            Spacer()

            // Right side - Time & Progress
            VStack(alignment: .trailing, spacing: 10) {
                // Time
                VStack(alignment: .trailing, spacing: 2) {
                    Text("TIME")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))

                    Text(formatTime(context.state.elapsedTime))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }

                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 6)
                        .frame(width: 50, height: 50)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                colors: progress >= 1.0 ? [.green, .green] : [
                                    Color(red: 1.0, green: 0.6, blue: 0.2),
                                    Color(red: 0.9, green: 0.3, blue: 0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.25, blue: 0.35),  // Match app gradient
                    Color(red: 0.7, green: 0.2, blue: 0.3),
                    Color(red: 0.5, green: 0.15, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .activityBackgroundTint(Color.clear)
        .activitySystemActionForegroundColor(.white)
        // Tapping the Live Activity should always take the user back to their
        // in‑progress workout inside the main app.
        .widgetURL(URL(string: "mileaday://workout"))
    }

    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
