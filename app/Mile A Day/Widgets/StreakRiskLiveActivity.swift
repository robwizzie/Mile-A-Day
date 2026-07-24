import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Attributes

/// Lock-screen countdown for an at-risk streak: started by the app on an
/// at-risk evening (goal unmet after 6pm), ended the moment the mile lands
/// or the day rolls over. The countdown is system-rendered
/// (`Text(timerInterval:)`), so it ticks with zero updates from the app.
struct StreakRiskActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Miles still needed to keep the streak.
        var milesToGo: Double
        /// Local midnight - when the streak dies.
        var deadline: Date
    }

    /// The number on the line.
    var streak: Int
    var goalMiles: Double
    var funStyle: Bool

    init(streak: Int, goalMiles: Double, funStyle: Bool = false) {
        self.streak = streak
        self.goalMiles = goalMiles
        self.funStyle = funStyle
    }

    enum CodingKeys: String, CodingKey {
        case streak
        case goalMiles
        case funStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streak = try container.decode(Int.self, forKey: .streak)
        goalMiles = try container.decode(Double.self, forKey: .goalMiles)
        funStyle = try container.decodeIfPresent(Bool.self, forKey: .funStyle) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(streak, forKey: .streak)
        try container.encode(goalMiles, forKey: .goalMiles)
        try container.encode(funStyle, forKey: .funStyle)
    }
}

// MARK: - Live Activity

struct StreakRiskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StreakRiskActivityAttributes.self) { context in
            StreakRiskLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if context.attributes.funStyle {
                        HStack(spacing: 6) {
                            FlameBuddyFigure(health: .critical, size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("DAY \(context.attributes.streak)")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Text("on the line")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: 126, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.red)
                                Text("DAY \(context.attributes.streak)")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            Text("on the line")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: 126, alignment: .leading)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(timerInterval: Date()...context.state.deadline, countsDown: true)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.red)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .frame(maxWidth: 86, alignment: .trailing)
                    }
                    .padding(.trailing, 8)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        Text(String(format: "%.2f mi to go", context.state.milesToGo))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Spacer()
                        Link(destination: URL(string: "mileaday://workout/start")!) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Start Mile")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color(red: 217/255, green: 64/255, blue: 63/255)))
                        }
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.red)
            } compactTrailing: {
                Text(compactTimeLeft(until: context.state.deadline))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: 42, alignment: .trailing)
            } minimal: {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.red)
            }
        }
    }

    private func compactTimeLeft(until deadline: Date) -> String {
        let seconds = max(0, Int(deadline.timeIntervalSince(Date())))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h" }
        return "\(max(1, minutes))m"
    }
}

// MARK: - Lock screen view

private struct StreakRiskLockScreenView: View {
    let context: ActivityViewContext<StreakRiskActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            if context.attributes.funStyle {
                FlameBuddyFigure(health: .critical, size: 62)
                    .frame(width: 64, height: 64)
            }

            // The number on the line.
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !context.attributes.funStyle {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                            )
                    }
                    Text("Day \(context.attributes.streak) on the line")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }

                Text(String(format: "%.2f mi keeps it alive", context.state.milesToGo))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))

                Text(timerInterval: Date()...context.state.deadline, countsDown: true)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.red)
                    .frame(maxWidth: 120, alignment: .leading)
            }

            Spacer()

            Link(destination: URL(string: "mileaday://workout/start")!) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.16))
                            .frame(width: 28, height: 28)
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .black))
                            .offset(x: 1)
                    }
                    Text("Start Mile")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .foregroundColor(.white)
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color(red: 226/255, green: 58/255, blue: 62/255))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        )
                )
            }
            .accessibilityLabel("Start Mile")
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.05, blue: 0.07),
                    Color(red: 0.28, green: 0.06, blue: 0.09),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .activityBackgroundTint(Color.clear)
        .activitySystemActionForegroundColor(.white)
        .widgetURL(URL(string: "mileaday://dashboard"))
    }
}
