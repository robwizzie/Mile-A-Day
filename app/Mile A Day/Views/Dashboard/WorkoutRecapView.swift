import SwiftUI
import UIKit

// MARK: - Workout Recap View

/// Post-workout summary shown inside WorkoutTrackingView's full-screen cover,
/// over its red gradient background. Every metric is a snapshot captured when
/// the workout ended — the live managers keep refreshing underneath while
/// HealthKit re-syncs, so reading them here would drift or double-count.
struct WorkoutRecapView: View {
    let distance: Double          // Miles covered in this workout
    let duration: TimeInterval    // Seconds elapsed in this workout
    let activityName: String      // "Run" or "Walk"
    let activityIcon: String      // SF Symbol for the activity
    let startingDistance: Double  // Miles already done today before this workout
    let goalDistance: Double      // Daily goal in miles
    let streak: Int               // Current streak in days
    let onDismiss: () -> Void

    // Staggered entrance
    @State private var showHero = false
    @State private var showDistance = false
    @State private var showStats = false
    @State private var showGoal = false

    private var totalDailyDistance: Double { startingDistance + distance }

    private var goalMet: Bool {
        goalDistance > 0 && totalDailyDistance >= goalDistance
    }

    private var goalProgress: Double {
        guard goalDistance > 0 else { return 0 }
        return min(totalDailyDistance / goalDistance, 1.0)
    }

    private var milesRemaining: Double {
        max(goalDistance - totalDailyDistance, 0)
    }

    private var formattedTime: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var formattedPace: String {
        guard distance > 0.01 else { return "--" }
        let paceSeconds = duration / distance
        let minutes = Int(paceSeconds) / 60
        let seconds = Int(paceSeconds) % 60
        return String(format: "%d'%02d\"", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    heroSection
                        .padding(.top, 32)

                    distanceSection

                    statsGrid

                    goalCard
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            doneButton
        }
        .onAppear {
            MADHaptics.success()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { showHero = true }
            withAnimation(.easeOut(duration: 0.35).delay(0.2)) { showDistance = true }
            withAnimation(.easeOut(duration: 0.35).delay(0.35)) { showStats = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) { showGoal = true }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 116, height: 116)

                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 116, height: 116)

                if goalMet {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                } else {
                    Image(systemName: activityIcon)
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                }
            }
            .scaleEffect(showHero ? 1.0 : 0.4)
            .opacity(showHero ? 1 : 0)

            VStack(spacing: 6) {
                Text(goalMet ? "Goal Complete!" : "Great Work!")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("\(activityName) saved to Apple Health")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.7))
            }
            .opacity(showHero ? 1 : 0)
            .offset(y: showHero ? 0 : 12)
        }
    }

    // MARK: - Distance

    private var distanceSection: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.2f", distance))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("MILES THIS \(activityName.uppercased())")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.7))
                .tracking(1.5)
        }
        .opacity(showDistance ? 1 : 0)
        .offset(y: showDistance ? 0 : 12)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            RecapStatCell(icon: "clock.fill", label: "Time", value: formattedTime)
            RecapStatCell(icon: "speedometer", label: "Avg Pace", value: "\(formattedPace) /mi")
            RecapStatCell(icon: activityIcon, label: "Activity", value: activityName)
            RecapStatCell(icon: "chart.bar.fill", label: "Daily Total", value: String(format: "%.2f mi", totalDailyDistance))
        }
        .opacity(showStats ? 1 : 0)
        .offset(y: showStats ? 0 : 12)
    }

    // MARK: - Goal Progress

    private var goalCard: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "target")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                Text("Daily Goal")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                Text(String(format: "%.2f / %.2f mi", totalDailyDistance, goalDistance))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: goalMet ? [.green, .mint] : [.orange, .yellow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        // Bar fills from zero as part of the entrance animation
                        .frame(width: showGoal ? max(geo.size.width * goalProgress, goalProgress > 0 ? 10 : 0) : 0)
                }
            }
            .frame(height: 10)

            HStack(spacing: 6) {
                if goalMet {
                    Image(systemName: "flame.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Text(streak > 0 ? "\(streak)-day streak is safe for today" : "Your streak is safe for today")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                } else {
                    Image(systemName: "figure.walk.motion")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    Text(String(format: "%.2f mi to go — you've got this", milesRemaining))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                }
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .opacity(showGoal ? 1 : 0)
        .offset(y: showGoal ? 0 : 12)
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button(action: onDismiss) {
            Text("Back to Dashboard")
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
        .padding(.top, 8)
        .padding(.bottom, 40)
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Recap Stat Cell

private struct RecapStatCell: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Text(label.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(1)
            }

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
