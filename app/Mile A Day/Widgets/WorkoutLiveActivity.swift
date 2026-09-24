import ActivityKit
import WidgetKit
import SwiftUI

/// Display miles truncated to 2 decimals — NEVER rounded up, so a shown
/// "1.00" always means the mile is actually there (0.995 used to round up
/// beside an incomplete goal). Private copy of `Double.milesFloor2` in the
/// main app's Extensions.swift — widget-extension targets can't see that
/// file; keep the formula in sync.
private func flooredMilesText(_ miles: Double) -> String {
    String(format: "%.2f", (miles * 100.0 + 1e-6).rounded(.down) / 100.0)
}

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
        /// The user manually paused. Distinct from `isAutoPaused`, which is a
        /// movement GUESS — this one is an instruction, and it freezes the
        /// clock as well as the distance. Optional for the same decode-safety
        /// reason as the fields above: an activity already in flight from the
        /// shipped build must still decode.
        var isPaused: Bool? = nil
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
    /// stop at a light doesn't drag the number toward absurdity — but only
    /// while that clock has actually covered the walk. A moving figure far
    /// under elapsed is a witness gap (thin GPS, a pocketed phone), and
    /// dividing the full distance by a fraction of the time prints a pace
    /// nobody walked. Widget targets can't see `DisplayPace`, so the rule is
    /// copied here; keep the two in step.
    var paceSecondsPerMile: TimeInterval? {
        guard distance > 0.05 else { return nil }
        let moving = movingSeconds ?? 0
        let covers = elapsedTime > 0 && moving <= elapsedTime && moving >= elapsedTime * 0.5
        let divisor = covers ? moving : elapsedTime
        guard divisor > 0 else { return nil }
        return divisor / distance
    }

    var showsManualPause: Bool { isPaused == true }

    /// The movement guess only gets to speak when the user hasn't already
    /// settled the question by pausing.
    var showsAutoPaused: Bool { isAutoPaused == true && !showsManualPause }

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
    /// Base point size. The view steps it down itself once the clock gains an
    /// hours field — see `resolvedSize`.
    var size: CGFloat
    var weight: Font.Weight = .semibold
    var alignment: TextAlignment = .trailing

    var body: some View {
        Group {
            // A manual pause drops the anchor, so this falls through to the
            // frozen pushed value. It has to: `Text(timerInterval:)` is
            // rendered by the system and keeps counting with no updates from
            // the app — the very property that makes it right for a live
            // workout makes it a lie about a paused one.
            if let start = state.timerStartDate, !state.showsManualPause {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
            } else {
                Text(staticTime)
            }
        }
        .font(.system(size: resolvedSize, weight: weight, design: .rounded))
        .monospacedDigit()
        // Belt AND braces, because neither alone is enough. `Text(timerInterval:)`
        // is rendered by the SYSTEM: this side never sees the string, so it
        // cannot measure it, and a width that fits "58:12" silently truncated
        // an hour-long walk to "1:03:…" on the lock screen. The step-down
        // below handles the predictable case; the scale factor catches the
        // minute between crossing the hour and the next content push.
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .multilineTextAlignment(alignment)
    }

    /// "58:12" is five glyphs, "1:03:45" is seven — about 40% wider, at the
    /// one boundary every long walk crosses.
    private var resolvedSize: CGFloat { isOverAnHour ? size * 0.76 : size }

    private var isOverAnHour: Bool {
        if let start = state.timerStartDate, !state.showsManualPause {
            return Date().timeIntervalSince(start) >= 3600
        }
        return state.elapsedTime >= 3600
    }

    /// The frozen value a paused walk falls back to, in the SAME shape the
    /// system's live clock uses. It was minutes:seconds with no hours field,
    /// so pausing an hour-long walk changed "1:03:12" into "63:12" — the same
    /// workout, two different-looking times, on the same line.
    private var staticTime: String {
        let total = Int(state.elapsedTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Flamey (Fun only)

/// A tiny, STATIC Flamey for the Live Activity (a system-rendered snapshot:
/// no onAppear, no animation). Fun-only, read from the App Group mirror of the
/// dashboard style; draws nothing on Modern or on a stale activity. His
/// look is resolved from the same mirrored facts the flame widget uses, and
/// his pose from the DAY's progress in three bands:
///
///   < 50%   ready    — plain, calm
///   50–99%  excited  — leaning in, sparkles
///   ≥ 100%  cheering — blazing, shades + party hat, confetti
///
/// Compiled into BOTH the app module and the widget extension, so it only
/// touches API the two copies of the figure/wardrobe share.
struct LiveActivityFlamey: View {
    let progress: Double
    let size: CGFloat
    var isStale: Bool = false

    enum Band: Equatable { case ready, excited, cheering }

    static func band(for progress: Double) -> Band {
        if progress >= 1 { return .cheering }
        if progress >= 0.5 { return .excited }
        return .ready
    }

    static var isFun: Bool { WidgetDataStore.loadDashboardStyle() == "fun" }

    var body: some View {
        if Self.isFun && !isStale {
            let band = Self.band(for: progress)
            let look = FlameyLook.resolve(
                longestStreak: WidgetDataStore.loadLongestStreak(),
                earnedBadgeIds: WidgetDataStore.loadFlameyBadgeIds(),
                signupDate: WidgetDataStore.loadFlameySignupDate(),
                date: Date(),
                moodProps: band == .cheering ? [.shades, .partyHat] : []
            )
            let health: FlameHealth = band == .cheering ? .blazing : .healthy
            ZStack {
                if band != .ready { flair(band) }
                FlameyOutfitLayer(look: look, size: size, scale: health.bodyScale, side: .behind, still: true)
                FlameBuddyFigure(health: health, size: size, showsFace: true, vigor: nil, grounded: true)
                FlameyOutfitLayer(look: look, size: size, scale: health.bodyScale, side: .front, still: true)
            }
            .rotationEffect(.degrees(band == .excited ? -6 : 0), anchor: .bottom)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }

    /// Sparkles (excited) or confetti (cheering), baked in place.
    @ViewBuilder
    private func flair(_ band: Band) -> some View {
        if band == .excited {
            ForEach(0..<2, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: size * (i == 0 ? 0.20 : 0.14), weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.92, blue: 0.55))
                    .offset(x: (i == 0 ? 1 : -1) * size * 0.46, y: -size * (i == 0 ? 0.30 : 0.05))
            }
        } else {
            let pieces: [(x: CGFloat, y: CGFloat, deg: Double, hue: Int)] = [
                (-0.52, -0.42, 20, 0), (0.50, -0.36, -30, 1), (-0.46, 0.02, 50, 2),
                (0.56, 0.04, 10, 3), (-0.30, -0.62, -15, 3), (0.34, -0.60, 35, 2),
            ]
            let colors = [Color(red: 1.0, green: 0.42, blue: 0.62), Color(red: 0.55, green: 0.42, blue: 1.0),
                          Color(red: 0.35, green: 0.85, blue: 0.95), Color(red: 1.0, green: 0.9, blue: 0.45)]
            ForEach(0..<pieces.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(colors[pieces[i].hue])
                    .frame(width: size * 0.09, height: size * 0.05)
                    .rotationEffect(.degrees(pieces[i].deg))
                    .offset(x: size * pieces[i].x, y: size * pieces[i].y)
            }
        }
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

                        Text("\(flooredMilesText(context.state.distance)) mi")
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

                            LiveTimerText(state: context.state, size: 20)
                                .foregroundColor(.white)

                            if context.state.showsManualPause {
                                Text("PAUSED")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .foregroundColor(.orange)
                            } else if context.state.showsAutoPaused {
                                Text("AUTO-PAUSED")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
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
                    HStack(alignment: .bottom, spacing: 10) {
                    // Fun: a tiny Flamey leading the progress bar (nothing on
                    // Modern — an EmptyView takes no room in the stack).
                    LiveActivityFlamey(progress: context.state.dailyProgress, size: 34, isStale: context.isStale)
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
                                    Text("Daily: \(flooredMilesText(context.state.totalDailyDistance)) mi")
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
                    Text(flooredMilesText(context.state.distance))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("miles")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                // Daily total if different
                if context.state.totalDailyDistance > context.state.distance {
                    Text("Daily: \(flooredMilesText(context.state.totalDailyDistance)) mi")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            // Fun: Flamey stands in the gap between the two columns — the
            // spacers keep both columns exactly where they were, and nothing
            // caps the timer's width. Modern: nothing, i.e. one Spacer.
            Spacer(minLength: 0)
            LiveActivityFlamey(progress: progress, size: 54, isStale: context.isStale)
                .padding(.top, 10)
            Spacer(minLength: 0)

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
                                .accessibilityHidden(true)
                            Text("TRACKING INTERRUPTED")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                        }
                        .foregroundColor(.yellow)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        Text("Open Mile A Day to resume")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("TIME")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))

                    LiveTimerText(state: context.state, size: 24)
                        .foregroundColor(.white)

                    if context.state.showsManualPause {
                        HStack(spacing: 4) {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text("PAUSED")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                        }
                        .foregroundColor(.orange)
                    } else if context.state.showsAutoPaused {
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
                            .minimumScaleFactor(0.7)
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

                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        // Fill the WHOLE lock-screen card. The gradient used to be a
        // background on the content alone, so it only covered the content's
        // own height; the system's card is taller, and with a `.clear` tint
        // the rest showed through as dark translucent bands above and below.
        // The frame stretches the content (and the gradient under it) to the
        // card's height, and the tint is the card's own colour in case the
        // system ever draws a sliver the view doesn't reach.
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .activityBackgroundTint(Color(red: 0.7, green: 0.2, blue: 0.3))
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
