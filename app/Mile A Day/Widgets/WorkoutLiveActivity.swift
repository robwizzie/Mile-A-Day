import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Activity Attributes

struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var distance: Double // Current workout distance in miles
        var totalDailyDistance: Double // Total for the day
        var elapsedTime: TimeInterval // Time in seconds (fallback display)
        var goalDistance: Double
        var activityType: String // "Running" or "Walking"
        /// Anchor for the system-rendered, self-ticking timer
        /// (`Text(timerInterval:)`). Set to now − elapsedTime on each update so
        /// the clock keeps running smoothly between activity updates instead
        /// of freezing at the last pushed value.
        var timerStartDate: Date? = nil
        /// Current streak, for the goal-completed celebration copy.
        var streak: Int = 0
        /// Seconds of witnessed movement — the display-pace divisor (elapsed
        /// keeps ticking through stops; pace shouldn't). Optionals so an
        /// in-flight activity from an older build still decodes.
        var movingSeconds: TimeInterval? = nil
        /// The tracker's movement gate is closed (standing, sitting, riding).
        var isAutoPaused: Bool? = nil
        /// Ghost race: seconds ahead (+) / behind (−) the user's best mile at
        /// the current distance. nil = not racing this session. Optional so
        /// an in-flight activity from an older build still decodes.
        var ghostDeltaSeconds: Double? = nil
        /// Mid-workout hypes from friends (live presence): how many landed
        /// this session and who sent the latest. Defaulted optionals for the
        /// same decode-safety reason as above.
        var hypeCount: Int? = nil
        var latestHypeName: String? = nil
    }

    var startTime: Date
    var goalDistance: Double
}

// MARK: - Shared helpers

private extension WorkoutActivityAttributes.ContentState {
    var dailyProgress: Double {
        guard goalDistance > 0 else { return 0 }
        return min(totalDailyDistance / goalDistance, 1.0)
    }

    var isGoalComplete: Bool {
        goalDistance > 0 && totalDailyDistance >= goalDistance
    }

    /// Current pace in seconds per mile, when there's enough distance to be
    /// meaningful. Divides by MOVING time when the tracker sent it, so a
    /// stop at a light doesn't drag the number toward absurdity.
    var paceSecondsPerMile: TimeInterval? {
        guard distance > 0.05 else { return nil }
        let divisor = (movingSeconds ?? 0) > 0 ? movingSeconds! : elapsedTime
        return divisor / distance
    }

    var showsAutoPaused: Bool { isAutoPaused == true }

    var paceText: String? {
        guard let pace = paceSecondsPerMile, pace.isFinite, pace < 3600 else { return nil }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d /mi", minutes, seconds)
    }

    /// "▲ 12s" / "▼ 8s" ghost-race delta, with ahead-ness for tinting.
    var ghostDeltaText: (text: String, ahead: Bool)? {
        guard let delta = ghostDeltaSeconds, delta.isFinite else { return nil }
        let ahead = delta >= 0
        let magnitude = Int(abs(delta).rounded())
        return ("\(ahead ? "▲" : "▼") \(magnitude)s", ahead)
    }

    /// "🔥 Davey" — the latest mid-workout hype, when any landed.
    var hypeLineText: String? {
        guard let count = hypeCount, count > 0 else { return nil }
        if let name = latestHypeName, !name.isEmpty {
            return count > 1 ? "🔥 \(name) +\(count - 1)" : "🔥 \(name)"
        }
        return "🔥 ×\(count)"
    }
}

/// Self-ticking elapsed-time text: rendered by the system from the anchor
/// date, so it advances every second with no activity updates. Falls back to
/// the last pushed static value when no anchor is available.
private struct LiveTimerText: View {
    let state: WorkoutActivityAttributes.ContentState
    var font: Font
    var alignment: TextAlignment = .trailing

    var body: some View {
        Group {
            if let start = state.timerStartDate {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
            } else {
                Text(staticTime)
            }
        }
        .font(font)
        .monospacedDigit()
        .multilineTextAlignment(alignment)
    }

    private var staticTime: String {
        let minutes = Int(state.elapsedTime) / 60
        let seconds = Int(state.elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
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
                        // Stale = the app stopped sending updates (iOS likely
                        // terminated it mid-workout). Say so instead of
                        // letting the self-ticking clock imply all is well.
                        if context.isStale {
                            Text("TRACKING")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            Text("INTERRUPTED")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundColor(.yellow)
                            Text("Open to resume")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.8))
                        } else {
                            Text("TIME")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))

                            LiveTimerText(
                                state: context.state,
                                font: .system(size: 20, weight: .semibold, design: .rounded)
                            )
                            .foregroundColor(.white)
                            .frame(maxWidth: 70, alignment: .trailing)

                            if context.state.showsAutoPaused {
                                Text("PAUSED")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .foregroundColor(.orange)
                            } else if let pace = context.state.paceText {
                                Text(pace)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.7))
                                    .monospacedDigit()
                            }

                            if let ghost = context.state.ghostDeltaText {
                                Text(ghost.text)
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .foregroundColor(ghost.ahead ? .green : .orange)
                                    .monospacedDigit()
                            }

                            if let hype = context.state.hypeLineText {
                                Text(hype)
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                            }
                        }
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

                        // Stats row — flips to a celebration line once the
                        // daily goal is in the bank.
                        if context.state.isGoalComplete {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text(context.state.streak > 0
                                     ? "Mile done — streak safe at day \(context.state.streak)!"
                                     : "Mile done — streak safe!")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                                Spacer()
                            }
                        } else {
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
                    }
                    .padding(.horizontal, 12)
                }
            } compactLeading: {
                // Compact leading (left side of Dynamic Island) — flips to a
                // green flame the moment the daily mile is done.
                Image(systemName: context.state.isGoalComplete
                      ? "flame.fill"
                      : (context.state.activityType == "Running" ? "figure.run" : "figure.walk"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(context.state.isGoalComplete ? .green : .white)
            } compactTrailing: {
                // Compact trailing — the question mid-mile is "how close am
                // I?", so show daily progress, not the clock (time lives in
                // the expanded view). A stale activity outranks both: the
                // app died and the user should know at a glance.
                if context.isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.yellow)
                } else if context.state.isGoalComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                } else {
                    ProgressView(value: context.state.dailyProgress)
                        .progressViewStyle(.circular)
                        .tint(Color(red: 0.9, green: 0.3, blue: 0.3))
                }
            } minimal: {
                // Minimal (when multiple Live Activities are active)
                if context.isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow)
                } else if context.state.isGoalComplete {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                } else {
                    ProgressView(value: context.state.dailyProgress)
                        .progressViewStyle(.circular)
                        .tint(Color(red: 0.9, green: 0.3, blue: 0.3))
                }
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
                // Time — unless the activity went stale (the app stopped
                // sending updates, i.e. iOS likely terminated it). The
                // system-rendered clock would keep ticking forever on a dead
                // workout; the warning is the honest thing to show.
                if context.isStale {
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("TRACKING INTERRUPTED")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                        }
                        .foregroundColor(.yellow)
                        Text("Open Mile A Day to resume")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                    }
                } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("TIME")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))

                    LiveTimerText(
                        state: context.state,
                        font: .system(size: 24, weight: .semibold, design: .rounded)
                    )
                    .foregroundColor(.white)
                    .frame(maxWidth: 90, alignment: .trailing)

                    if context.state.showsAutoPaused {
                        HStack(spacing: 4) {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text("AUTO-PAUSED")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                        }
                        .foregroundColor(.orange)
                    } else if let pace = context.state.paceText {
                        Text(pace)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                            .monospacedDigit()
                    }

                    if let ghost = context.state.ghostDeltaText {
                        Text(ghost.text)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(ghost.ahead ? .green : .orange)
                            .monospacedDigit()
                    }

                    if let hype = context.state.hypeLineText {
                        Text(hype)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(.orange)
                            .lineLimit(1)
                    }
                }
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
