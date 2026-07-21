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
        /// Local midnight — when the streak dies.
        var deadline: Date
    }

    /// The number on the line.
    var streak: Int
    var goalMiles: Double
}

// MARK: - Live Activity

struct StreakRiskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StreakRiskActivityAttributes.self) { context in
            StreakRiskLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.red)
                            Text("DAY \(context.attributes.streak)")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                        }
                        Text("on the line")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("TIME LEFT")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                        Text(timerInterval: Date()...context.state.deadline, countsDown: true)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.red)
                            .frame(maxWidth: 80, alignment: .trailing)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(String(format: "%.2f mi to go", context.state.milesToGo))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Link(destination: URL(string: "mileaday://workout/start")!) {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Start Mile")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color(red: 217/255, green: 64/255, blue: 63/255)))
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.red)
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.deadline, countsDown: true)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.red)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - Lock screen view

private struct StreakRiskLockScreenView: View {
    let context: ActivityViewContext<StreakRiskActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            // The number on the line.
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                        )
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
                VStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("Start\nMile")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 217/255, green: 64/255, blue: 63/255))
                )
            }
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
        .widgetURL(URL(string: "mileaday://workout/start"))
    }
}
