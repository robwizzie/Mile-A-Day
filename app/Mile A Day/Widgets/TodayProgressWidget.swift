import WidgetKit
import SwiftUI

struct TodayProgressEntry: TimelineEntry {
    let date: Date
    let milesCompleted: Double
    let goal: Double
    let streakCompleted: Bool
    let progress: Double
    let totalDistance: Double
}

struct TodayProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayProgressEntry {
        TodayProgressEntry(
            date: Date(), 
            milesCompleted: 0.5, 
            goal: 1.0, 
            streakCompleted: false,
            progress: 0.5,
            totalDistance: 0.5
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayProgressEntry) -> Void) {
        let data = WidgetDataStore.load()
        print("[Widget] Snapshot - Miles: \(data.miles), Goal: \(data.goal), Progress: \(Int(data.progress * 100))%")
        completion(TodayProgressEntry(
            date: Date(), 
            milesCompleted: data.miles, 
            goal: data.goal, 
            streakCompleted: data.streakCompleted,
            progress: data.progress,
            totalDistance: data.totalDistance
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayProgressEntry>) -> Void) {
        let data = WidgetDataStore.load()
        
        print("[Widget] Timeline - Miles: \(data.miles), Goal: \(data.goal), Progress: \(Int(data.progress * 100))%")
        
        let entry = TodayProgressEntry(
            date: Date(), 
            milesCompleted: data.miles, 
            goal: data.goal, 
            streakCompleted: data.streakCompleted,
            progress: data.progress,
            totalDistance: data.totalDistance
        )
        
        // More frequent refresh for better sync - widgets need to stay updated throughout the day
        let refreshInterval: TimeInterval = data.streakCompleted ? 300 : 30 // 30s incomplete, 5min completed
        
        let nextRefresh = Date().addingTimeInterval(refreshInterval)
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
                        milesCompleted: entry.totalDistance,
                        goal: entry.goal,
                        streakCompleted: entry.streakCompleted
                    )
                case .accessoryRectangular:
                    RectangularProgressView(
                        progress: entry.progress,
                        milesCompleted: entry.totalDistance,
                        goal: entry.goal,
                        streakCompleted: entry.streakCompleted
                    )
                case .accessoryInline:
                    InlineProgressView(
                        milesCompleted: entry.totalDistance,
                        goal: entry.goal,
                        streakCompleted: entry.streakCompleted
                    )
                default:
                    HomeScreenProgressView(
                        progress: entry.progress,
                        milesCompleted: entry.totalDistance,
                        goal: entry.goal,
                        streakCompleted: entry.streakCompleted
                    )
                }
            } else {
                HomeScreenProgressView(
                    progress: entry.progress,
                    milesCompleted: entry.totalDistance,
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
                .trim(from: 0, to: progress)
                .stroke(streakCompleted ? Color.green : Color("appPrimary"), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .scaleEffect(0.8)
                .animation(.easeInOut(duration: 0.5), value: progress)
                    .frame(width: 4, height: 4)
                    .scaleEffect(1.5)
                    .opacity(0.8)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isLiveTracking)
                    .offset(y: -25)
            }
            
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
                    .foregroundColor(.primary)
                Text("Progress")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
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
                        .frame(width: progress * geometry.size.width, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: progress)
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
                .foregroundColor(.primary)
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
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "figure.run")
                    .foregroundColor(.primary)
                Text("Today's Progress")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                if streakCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            // Progress Bar - Always capped at 100%
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 16)
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(streakCompleted ? Color.green : Color("appPrimary"))
                        .frame(width: progress * geometry.size.width, height: 16)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 16)
            
            // Distance Display
            HStack {
                Text(String(format: "%.2f", milesCompleted))
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("of")
                    .font(.subheadline)
                
                Text(String(format: "%.1f mi", goal))
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            // Status or remaining distance
            if streakCompleted {
                Label("Goal Complete!", systemImage: "star.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            } else if isLiveTracking {
                Label("Tracking in progress...", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundColor(.red)
                    .font(.caption)
            } else {
                let remaining = max(goal - milesCompleted, 0.0)
                Text(String(format: "%.2f mi to go", remaining))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Widget Configuration

struct TodayProgressWidget: Widget {
    let kind: String = "TodayProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProgressProvider()) { entry in
            TodayProgressWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Progress")
        .description("Track your daily mile progress.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) {
    TodayProgressWidget()
} timeline: {
    TodayProgressEntry(date: .now, milesCompleted: 0.2, goal: 1.0, streakCompleted: false, progress: 0.2, totalDistance: 0.2, isLiveTracking: false)
} 