import WidgetKit
import SwiftUI

struct TodayProgressEntry: TimelineEntry {
    let date: Date
    let milesCompleted: Double
    let goal: Double
}

struct TodayProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayProgressEntry {
        TodayProgressEntry(date: Date(), milesCompleted: 0.5, goal: 1.0)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayProgressEntry) -> Void) {
        let data = WidgetDataStore.load()
        print("[Widget] Snapshot - Miles: \(data.miles), Goal: \(data.goal)")
        completion(TodayProgressEntry(date: Date(), milesCompleted: data.miles, goal: data.goal))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayProgressEntry>) -> Void) {
        let data = WidgetDataStore.load()
        print("[Widget] Timeline - Miles: \(data.miles), Goal: \(data.goal)")
        let entry = TodayProgressEntry(date: Date(), milesCompleted: data.miles, goal: data.goal)
        // Update every 15 minutes to reflect changes quickly, WidgetCenter.reload is also triggered on save
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}

struct TodayProgressWidgetEntryView: View {
    var entry: TodayProgressProvider.Entry

    var progress: Double {
        guard entry.goal > 0 else { return 0 }
        return min(entry.milesCompleted / entry.goal, 1)
    }

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                switch widgetFamily {
                case .accessoryCircular:
                    CircularProgressView(progress: progress, milesCompleted: entry.milesCompleted, goal: entry.goal)
                case .accessoryRectangular:
                    RectangularProgressView(progress: progress, milesCompleted: entry.milesCompleted, goal: entry.goal)
                case .accessoryInline:
                    InlineProgressView(milesCompleted: entry.milesCompleted, goal: entry.goal)
                default:
                    HomeScreenProgressView(progress: progress, milesCompleted: entry.milesCompleted, goal: entry.goal)
                }
            } else {
                HomeScreenProgressView(progress: progress, milesCompleted: entry.milesCompleted, goal: entry.goal)
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
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(progress >= 1.0 ? Color.green : Color("appPrimary"), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            VStack(spacing: 1) {
                Text(String(format: "%.1f", milesCompleted))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("mi")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }
}

@available(iOS 16.0, *)
struct RectangularProgressView: View {
    let progress: Double
    let milesCompleted: Double
    let goal: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "figure.run")
                    .font(.caption)
                Text("Progress")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(String(format: "%.1f/%.1f", milesCompleted, goal))
                    .font(.caption)
                    .fontWeight(.bold)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(progress >= 1.0 ? Color.green : Color("appPrimary"))
                        .frame(width: min(CGFloat(progress) * geometry.size.width, geometry.size.width), height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

@available(iOS 16.0, *)
struct InlineProgressView: View {
    let milesCompleted: Double
    let goal: Double
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.run")
            Text(String(format: "%.1f/%.1f mi", milesCompleted, goal))
                .fontWeight(.medium)
        }
    }
}

// MARK: - Home Screen View

struct HomeScreenProgressView: View {
    let progress: Double
    let milesCompleted: Double
    let goal: Double
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "figure.run")
                    .foregroundColor(.primary)
                Text("Today's Progress")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 16)
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(progress >= 1.0 ? Color.green : Color("appPrimary"))
                        .frame(width: min(CGFloat(progress) * geometry.size.width, geometry.size.width), height: 16)
                        .animation(.easeInOut, value: progress)
                }
            }
            .frame(height: 16)
            
            // Distance Display
            HStack {
                Text(String(format: "%.1f", milesCompleted))
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("of")
                    .font(.subheadline)
                
                Text(String(format: "%.1f mi", goal))
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            // Status
            if progress >= 1.0 {
                Label("Goal complete!", systemImage: "star.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            } else {
                Text(String(format: "%.1f mi to go", max(goal - milesCompleted, 0)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct TodayProgressWidget: Widget {
    let kind = "TodayProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProgressProvider()) { entry in
            TodayProgressWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Progress")
        .description("Track your mile progress for today.")
        .supportedFamilies([.systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) {
    TodayProgressWidget()
} timeline: {
    TodayProgressEntry(date: .now, milesCompleted: 0.2, goal: 1.0)
} 