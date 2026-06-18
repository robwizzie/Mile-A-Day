import WidgetKit
import SwiftUI

// MARK: - Shared MAD widget styling
// One visual family for all home-screen widgets: the app's dark gradient with
// a soft red glow, brand-gradient rings, and small-caps section labels —
// matching the Live Activity lock-screen card.

enum MADWidgetStyle {
    static let red = Color(red: 217/255, green: 64/255, blue: 63/255)
    static let orange = Color(red: 1.0, green: 0.55, blue: 0.2)
    static let green = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let track = Color.white.opacity(0.14)
    static let secondaryText = Color.white.opacity(0.65)

    static var ringGradient: AngularGradient {
        AngularGradient(
            colors: [red, orange, red],
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }

    @ViewBuilder
    static var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.07, blue: 0.09),
                    Color(red: 0.06, green: 0.03, blue: 0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [red.opacity(0.28), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 190
            )
        }
    }
}

/// Small-caps section label shared by all MAD widgets.
struct MADWidgetLabel: View {
    let icon: String
    let text: String
    var color: Color = MADWidgetStyle.red

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.0)
        }
        .foregroundColor(color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// Brand progress ring with rounded caps; flips green when complete.
struct MADWidgetRing<Center: View>: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat
    var isComplete: Bool = false
    @ViewBuilder let center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(MADWidgetStyle.track, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(max(progress, isComplete ? 1.0 : 0.0), 1.0))
                .stroke(
                    isComplete
                        ? AnyShapeStyle(MADWidgetStyle.green)
                        : AnyShapeStyle(MADWidgetStyle.ringGradient),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            center()
        }
        .frame(width: size, height: size)
    }
}

struct TodayProgressEntry: TimelineEntry {
    let date: Date
    let milesCompleted: Double
    let goal: Double
    let streakCompleted: Bool
    let progress: Double // Pre-calculated progress capped at 1.0
}

struct TodayProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayProgressEntry {
        TodayProgressEntry(
            date: Date(), 
            milesCompleted: 0.5, 
            goal: 1.0, 
            streakCompleted: false,
            progress: 0.5
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayProgressEntry) -> Void) {
        let data = WidgetDataStore.load()
        completion(TodayProgressEntry(
            date: Date(), 
            milesCompleted: data.miles, 
            goal: data.goal, 
            streakCompleted: data.streakCompleted,
            progress: data.progress
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayProgressEntry>) -> Void) {
        let data = WidgetDataStore.load()
        
        print("[Widget] Timeline - Miles: \(data.miles), Goal: \(data.goal), Progress: \(data.progress * 100)%")
        
        let entry = TodayProgressEntry(
            date: Date(), 
            milesCompleted: data.miles, 
            goal: data.goal, 
            streakCompleted: data.streakCompleted,
            progress: data.progress
        )
        
        // Refresh every minute for incomplete goals, every 15 minutes for completed goals
        let refreshInterval: TimeInterval = data.streakCompleted ? 900 : 60 // 1min incomplete, 15min completed

        // Never sleep past midnight: WidgetDataStore.load() zeroes out data
        // from a previous day, so rebuilding right at the day boundary makes
        // the widget reset to 0.00 mi without the app being opened.
        let intervalRefresh = Date().addingTimeInterval(refreshInterval)
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let nextMidnight = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? intervalRefresh
        let nextRefresh = min(intervalRefresh, nextMidnight)
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}

struct TodayProgressWidgetEntryView: View {
    var entry: TodayProgressProvider.Entry

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                switch widgetFamily {
                case .accessoryCircular:
                    CircularProgressView(
                        progress: entry.progress,
                        milesCompleted: entry.milesCompleted,
                        goal: entry.goal,
                        streakCompleted: entry.streakCompleted
                    )
                case .accessoryRectangular:
                    RectangularProgressView(
                        progress: entry.progress,
                        milesCompleted: entry.milesCompleted,
                        goal: entry.goal,
                        streakCompleted: entry.streakCompleted
                    )
                case .accessoryInline:
                    InlineProgressView(
                        milesCompleted: entry.milesCompleted,
                        goal: entry.goal,
                        streakCompleted: entry.streakCompleted
                    )
                default:
                    HomeScreenProgressView(
                        progress: entry.progress,
                        milesCompleted: entry.milesCompleted,
                        goal: entry.goal,
                        streakCompleted: entry.streakCompleted
                    )
                }
            } else {
                HomeScreenProgressView(
                    progress: entry.progress,
                    milesCompleted: entry.milesCompleted,
                    goal: entry.goal,
                    streakCompleted: entry.streakCompleted
                )
            }
        }
    }
    
    @Environment(\.widgetFamily) var widgetFamily
}

// MARK: - Lock Screen Views

@available(iOS 16.0, *)
struct CircularProgressView: View {
    let progress: Double
    let milesCompleted: Double
    let goal: Double
    let streakCompleted: Bool
    
    var body: some View {
        ZStack {
            // Outer circle - filled orange when complete
            Circle()
                .fill(streakCompleted ? Color.orange : Color.clear)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
            
            // Progress circle - Always capped at 100%
            Circle()
                .trim(from: 0, to: progress) // progress is already capped at 1.0
                .stroke(streakCompleted ? Color.green : Color("appPrimary"), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .scaleEffect(0.8)
            
            VStack(spacing: 1) {
                Text(String(format: "%.2f", milesCompleted))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(streakCompleted ? .white : .primary)
                Text("mi")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(streakCompleted ? .white.opacity(0.8) : .secondary)
            }
        }
    }
}

@available(iOS 16.0, *)
struct RectangularProgressView: View {
    let progress: Double
    let milesCompleted: Double
    let goal: Double
    let streakCompleted: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "figure.run")
                    .font(.caption)
                Text("Progress")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(String(format: "%.2f/%.1f", milesCompleted, goal))
                    .font(.caption)
                    .fontWeight(.bold)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(streakCompleted ? Color.green : Color("appPrimary"))
                        .frame(width: progress * geometry.size.width, height: 4) // progress already capped
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .frame(height: 4)
        }
    }
}

@available(iOS 16.0, *)
struct InlineProgressView: View {
    let milesCompleted: Double
    let goal: Double
    let streakCompleted: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.run")
            Text(String(format: "%.2f/%.1f mi", milesCompleted, goal))
                .fontWeight(.medium)
            if streakCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }
}

// MARK: - Home Screen View

struct HomeScreenProgressView: View {
    let progress: Double
    let milesCompleted: Double
    let goal: Double
    let streakCompleted: Bool

    var body: some View {
        HStack(spacing: 18) {
            // Progress ring with % (checkmark when done)
            MADWidgetRing(
                progress: progress,
                size: 92,
                lineWidth: 9,
                isComplete: streakCompleted
            ) {
                if streakCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(MADWidgetStyle.green)
                } else {
                    VStack(spacing: -2) {
                        Text("\(Int(progress * 100))")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(MADWidgetStyle.secondaryText)
                    }
                }
            }

            // Right column spans the full widget height: section label pinned
            // to the top, the hero stat floated to the optical center, and the
            // status / CTA row anchored to the bottom edge. The Spacers do the
            // vertical distribution so the card reads edge-to-edge instead of
            // a small block hovering in the middle.
            VStack(alignment: .leading, spacing: 0) {
                MADWidgetLabel(icon: "figure.run", text: "TODAY'S MILE")

                Spacer(minLength: 4)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(format: "%.2f", milesCompleted))
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(String(format: "of %.1f mi", goal))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(MADWidgetStyle.secondaryText)
                }

                Spacer(minLength: 4)

                // Status row: celebration when done, otherwise remaining
                // distance + a Start Mile button that deep-links straight into
                // the in-app workout tracker. (Widget buttons that should open
                // the app must be Links — Button(intent:) runs in the
                // background only.)
                if streakCompleted {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Streak safe — see you tomorrow!")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(MADWidgetStyle.green)
                } else {
                    HStack(spacing: 8) {
                        let remaining = max(goal - milesCompleted, 0.0)
                        Text(String(format: "%.2f mi to go", remaining))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(MADWidgetStyle.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer(minLength: 4)

                        Link(destination: URL(string: "mileaday://workout/start")!) {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Start Mile")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(MADWidgetStyle.red)
                                    .shadow(color: MADWidgetStyle.red.opacity(0.5), radius: 5, y: 2)
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Widget Configuration

struct TodayProgressWidget: Widget {
    let kind: String = "TodayProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProgressProvider()) { entry in
            TodayProgressWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { MADWidgetStyle.background }
        }
        .configurationDisplayName("Today's Progress")
        .description("Track your daily mile progress.")
        .supportedFamilies([.systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemMedium) {
    TodayProgressWidget()
} timeline: {
    TodayProgressEntry(date: .now, milesCompleted: 0.2, goal: 1.0, streakCompleted: false, progress: 0.2)
}