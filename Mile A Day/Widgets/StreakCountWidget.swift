import WidgetKit
import SwiftUI

struct StreakCountEntry: TimelineEntry {
    let date: Date
    let streak: Int
}

struct StreakCountProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakCountEntry {
        StreakCountEntry(date: Date(), streak: 5)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakCountEntry) -> Void) {
        let streak = WidgetDataStore.loadStreak()
        print("[Widget] Streak Snapshot - Streak: \(streak)")
        completion(StreakCountEntry(date: Date(), streak: streak))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakCountEntry>) -> Void) {
        let streak = WidgetDataStore.loadStreak()
        print("[Widget] Streak Timeline - Streak: \(streak)")
        let entry = StreakCountEntry(date: Date(), streak: streak)
        // Refresh hourly to stay lightweight; reloadTimeline is triggered on save
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct StreakCountWidgetEntryView: View {
    var entry: StreakCountProvider.Entry

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                switch widgetFamily {
                case .accessoryCircular:
                    CircularStreakView(streak: entry.streak)
                case .accessoryRectangular:
                    RectangularStreakView(streak: entry.streak)
                case .accessoryInline:
                    InlineStreakView(streak: entry.streak)
                default:
                    HomeScreenStreakView(streak: entry.streak)
                }
            } else {
                HomeScreenStreakView(streak: entry.streak)
            }
        }
    }
    
    @Environment(\.widgetFamily) var widgetFamily
}

// MARK: - Lock Screen Views

@available(iOS 16.0, *)
struct CircularStreakView: View {
    let streak: Int
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 4)
            
            VStack(spacing: 1) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange.gradient)
                Text("\(streak)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
        }
    }
}

@available(iOS 16.0, *)
struct RectangularStreakView: View {
    let streak: Int
    
    var body: some View {
        HStack {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(.orange.gradient)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Streak")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("\(streak) days")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            Spacer()
        }
    }
}

@available(iOS 16.0, *)
struct InlineStreakView: View {
    let streak: Int
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
            Text("\(streak) day streak")
                .fontWeight(.medium)
        }
    }
}

// MARK: - Home Screen View

struct HomeScreenStreakView: View {
    let streak: Int
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 24))
                .foregroundStyle(.orange.gradient)
            
            Text("\(streak)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StreakCountWidget: Widget {
    let kind = "StreakCountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakCountProvider()) { entry in
            StreakCountWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Streak Count")
        .description("See your current streak at a glance.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) {
    StreakCountWidget()
} timeline: {
    StreakCountEntry(date: .now, streak: 10)
} 