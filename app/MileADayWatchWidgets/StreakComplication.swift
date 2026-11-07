import SwiftUI
import WidgetKit

// The streak on the watch face. Everything shown comes from `WatchDayStore`,
// written by the Watch app; a stale store shows an honest last-known number.

struct StreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let miles: Double
    let goal: Double

    var isDone: Bool { miles >= goal }
    var progress: Double { goal > 0 ? min(miles / goal, 1) : 0 }
    var milesLeft: Double { max(goal - miles, 0) }
    /// Same evening rule as the iPhone widgets, for a streak that exists.
    var isAtRisk: Bool {
        !isDone && streak > 0 && Calendar.current.component(.hour, from: date) >= 18
    }
    var dayEnd: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    }
    var tint: Color {
        if isDone { return .green }
        return isAtRisk ? .red : .orange
    }

    /// Whole-hour time left; an entry is baked each hour, so this never lags.
    var timeLeft: String {
        let hours = Int(dayEnd.timeIntervalSince(date) / 3600)
        return hours < 1 ? "<1h left" : "\(hours)h left"
    }

    var milesLeftText: String { String(format: "%.2f mi left", milesLeft) }

    static let placeholder = StreakEntry(date: Date(), streak: 42, miles: 0.6, goal: 1)
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(at: Date()))
    }

    /// Hourly through the day and one at midnight, all baked now, so the time
    /// left and the new day need no reload.
    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        var dates = [now]
        var next = calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime)
        while let date = next, date <= midnight {
            dates.append(date)
            next = calendar.date(byAdding: .hour, value: 1, to: date)
        }
        completion(Timeline(entries: dates.map(entry(at:)), policy: .after(midnight)))
    }

    private func entry(at date: Date) -> StreakEntry {
        guard let snapshot = WatchDayStore.load() else {
            return StreakEntry(date: date, streak: 0, miles: 0, goal: 1)
        }
        return StreakEntry(date: date, streak: snapshot.streak,
                           miles: WatchDayStore.miles(in: snapshot, on: date), goal: snapshot.goal)
    }
}

struct StreakComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MileADayStreak", provider: StreakProvider()) { entry in
            StreakComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Your streak and today's mile.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct StreakComplicationView: View {
    let entry: StreakEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCorner: corner
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: circular
        }
    }

    /// Ring = today's mile, centre = the streak.
    private var circular: some View {
        Gauge(value: entry.progress) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            VStack(spacing: -1) {
                Image(systemName: entry.isDone ? "checkmark" : "flame.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(entry.tint)
                    .widgetAccentable()
                Text("\(entry.streak)")
                    .font(.system(.body, design: .rounded).weight(.heavy))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(entry.tint)
        .accessibilityLabel(accessibilityText)
    }

    private var corner: some View {
        Text("\(entry.streak)")
            .font(.system(.title3, design: .rounded).weight(.heavy))
            .foregroundStyle(entry.tint)
            .widgetAccentable()
            .widgetCurvesContent()
            .widgetLabel {
                if entry.isDone {
                    Text("Done today")
                } else {
                    Gauge(value: entry.progress) {
                        Text("Today")
                    } currentValueLabel: {
                        Text(entry.isAtRisk ? entry.timeLeft : entry.milesLeftText)
                    }
                    .tint(entry.tint)
                }
            }
            .accessibilityLabel(accessibilityText)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(entry.tint)
                    .widgetAccentable()
                Text(entry.streak == 1 ? "1 day" : "\(entry.streak) days")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ProgressView(value: entry.progress)
                .tint(entry.tint)
            Text(statusLine)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var inline: some View {
        Label {
            // Inline slots are narrow: "mi left" gets cut off beside the icon.
            Text(entry.isDone ? "\(entry.streak) · done" : String(format: "%d · %.2f mi", entry.streak, entry.milesLeft))
        } icon: {
            Image(systemName: "flame.fill")
        }
    }

    private var statusLine: String {
        if entry.isDone { return "Done today" }
        return entry.isAtRisk ? "\(entry.milesLeftText) · \(entry.timeLeft)" : entry.milesLeftText
    }

    private var accessibilityText: String {
        let days = entry.streak == 1 ? "1 day streak" : "\(entry.streak) day streak"
        return "\(days). \(statusLine)"
    }
}

#Preview(as: .accessoryRectangular) {
    StreakComplication()
} timeline: {
    StreakEntry.placeholder
}
