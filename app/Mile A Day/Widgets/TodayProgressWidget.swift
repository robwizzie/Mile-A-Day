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
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .semibold))
            Text(text)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .tracking(1.6)
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
    var streak: Int = 0  // Current streak (read straight from the shared store).
}

struct TodayProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayProgressEntry {
        TodayProgressEntry(
            date: Date(),
            milesCompleted: 0.5,
            goal: 1.0,
            streakCompleted: false,
            progress: 0.5,
            streak: 12
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayProgressEntry) -> Void) {
        let data = WidgetDataStore.load()
        completion(TodayProgressEntry(
            date: Date(),
            milesCompleted: data.miles,
            goal: data.goal,
            streakCompleted: data.streakCompleted,
            progress: data.progress,
            streak: WidgetDataStore.loadStreak()
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
            progress: data.progress,
            streak: WidgetDataStore.loadStreak()
        )
        
        // The timeline policy is only a FALLBACK (plus the midnight reset
        // below) — the app force-reloads this widget on every real data write.
        // The old 1-minute policy drained WidgetKit's daily refresh budget
        // (~40-70 reloads) within the first hour of each day, after which iOS
        // silently dropped ALL reloads — including the app's post-run writes —
        // freezing the widget on stale morning zeros while the app was correct.
        let refreshInterval: TimeInterval = data.streakCompleted ? 3600 : 1800 // 30min incomplete, 1h completed

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
                        streakCompleted: entry.streakCompleted,
                        streak: entry.streak
                    )
                }
            } else {
                HomeScreenProgressView(
                    progress: entry.progress,
                    milesCompleted: entry.milesCompleted,
                    goal: entry.goal,
                    streakCompleted: entry.streakCompleted,
                    streak: entry.streak
                )
            }
        }
        .widgetURL(URL(string: "mileaday://dashboard"))
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
    var streak: Int = 0

    var body: some View {
        // Three zones: progress ring (left), today's mile (center), streak
        // (right). Every text element is single-line + scalable so the layout
        // holds from the narrowest systemMedium (iPhone SE/11) up to Pro Max
        // and iPad without clipping.
        HStack(spacing: 14) {
            // Progress ring — the visual anchor; fills the card height. Kept
            // moderate so the center + streak zones never get squeezed on the
            // narrowest systemMedium.
            MADWidgetRing(
                progress: progress,
                size: 96,
                lineWidth: 7,
                isComplete: streakCompleted
            ) {
                if streakCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(MADWidgetStyle.green)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(progress * 100))")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("%")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(MADWidgetStyle.secondaryText)
                    }
                }
            }

            // Center: label, today's miles, status / CTA.
            VStack(alignment: .leading, spacing: 7) {
                MADWidgetLabel(icon: "figure.run", text: "TODAY'S MILE")

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.2f", milesCompleted))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(String(format: "/ %.1f mi", goal))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(MADWidgetStyle.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                // Status: celebration chip when done, otherwise a Start button
                // that deep-links into the in-app tracker. (Widget buttons that
                // open the app must be Links — Button(intent:) runs in the
                // background only.)
                if streakCompleted {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Streak safe")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(MADWidgetStyle.green)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(MADWidgetStyle.green.opacity(0.15)))
                } else {
                    Link(destination: URL(string: "mileaday://workout/start")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("Start Mile")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(MADWidgetStyle.red))
                    }
                }
            }

            Spacer(minLength: 8)

            // Right: streak — a prominent stat filling the right side, set off
            // by a hairline divider so it reads as its own zone.
            if streak > 0 {
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1, height: 58)

                    VStack(spacing: 1) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(MADWidgetStyle.orange)
                        Text("\(streak)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("DAY STREAK")
                            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                            .tracking(1.0)
                            .foregroundColor(MADWidgetStyle.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .fixedSize()
                }
            }
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
    TodayProgressEntry(date: .now, milesCompleted: 0.2, goal: 1.0, streakCompleted: false, progress: 0.2, streak: 401)
}
