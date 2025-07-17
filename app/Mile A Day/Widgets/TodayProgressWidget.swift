import WidgetKit
import SwiftUI

struct TodayProgressEntry: TimelineEntry {
    let date: Date
    let milesCompleted: Double
    let goal: Double
    let streakCompleted: Bool
    let progress: Double // Pre-calculated progress capped at 1.0
    let totalDistance: Double // Include live workout distance
    let isLiveTracking: Bool // Live tracking status
}

struct TodayProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayProgressEntry {
        TodayProgressEntry(
            date: Date(), 
            milesCompleted: 0.5, 
            goal: 1.0, 
            streakCompleted: false,
            progress: 0.5,
            totalDistance: 0.5,
            isLiveTracking: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayProgressEntry) -> Void) {
        let data = WidgetDataStore.load()
        print("[Widget] Snapshot - Base Miles: \(data.miles), Total: \(data.totalDistance), Goal: \(data.goal), Progress: \(Int(data.progress * 100))%")
        completion(TodayProgressEntry(
            date: Date(), 
            milesCompleted: data.miles, 
            goal: data.goal, 
            streakCompleted: data.streakCompleted,
            progress: data.progress,
            totalDistance: data.totalDistance,
            isLiveTracking: false // No live data in snapshot
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayProgressEntry>) -> Void) {
        let data = WidgetDataStore.load()
        let liveData = WidgetDataStore.loadLiveWorkout()
        
        print("[Widget] Timeline - Base Miles: \(data.miles), Total: \(data.totalDistance), Goal: \(data.goal), Progress: \(Int(data.progress * 100))%, Live Active: \(liveData.isActive)")
        
        let entry = TodayProgressEntry(
            date: Date(), 
            milesCompleted: data.miles, 
            goal: data.goal, 
            streakCompleted: data.streakCompleted,
            progress: data.progress,
            totalDistance: data.totalDistance,
            isLiveTracking: liveData.isActive
        )
        
        // Refresh much more frequently for live workouts - every 5 seconds for true real-time
        let refreshInterval: TimeInterval = liveData.isActive ? 5 : (data.streakCompleted ? 900 : 60) // 5s live, 1min incomplete, 15min completed
        
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
                        streakCompleted: entry.streakCompleted,
                        isLiveTracking: entry.isLiveTracking
                    )
                case .accessoryRectangular:
                    RectangularProgressView(
                        progress: entry.progress,
                        milesCompleted: entry.totalDistance,
                        goal: entry.goal,
                        streakCompleted: entry.streakCompleted,
                        isLiveTracking: entry.isLiveTracking
                    )
                case .accessoryInline:
                    InlineProgressView(
                        milesCompleted: entry.totalDistance,
                        goal: entry.goal,
                        streakCompleted: entry.streakCompleted,
                        isLiveTracking: entry.isLiveTracking
                    )
                default:
                    HomeScreenProgressView(
                        progress: entry.progress,
                        milesCompleted: entry.totalDistance,
                        goal: entry.goal,
                        streakCompleted: entry.streakCompleted,
                        isLiveTracking: entry.isLiveTracking
                    )
                }
            } else {
                HomeScreenProgressView(
                    progress: entry.progress,
                    milesCompleted: entry.totalDistance,
                    goal: entry.goal,
                    streakCompleted: entry.streakCompleted,
                    isLiveTracking: entry.isLiveTracking
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
    let isLiveTracking: Bool
    
    var body: some View {
        ZStack {
            // Outer circle - filled orange when complete
            Circle()
                .fill(streakCompleted ? Color.orange : Color.clear)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
            
            // Progress circle - Always capped at 100%
            Circle()
                .trim(from: 0, to: progress) // progress is already capped at 1.0
                .stroke(streakCompleted ? Color.green : (isLiveTracking ? Color.red : Color("appPrimary")), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .scaleEffect(0.8)
                .animation(.easeInOut(duration: 0.5), value: progress)
            
            // Live tracking indicator
            if isLiveTracking {
                Circle()
                    .fill(Color.red)
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
    let isLiveTracking: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "figure.run")
                    .font(.caption)
                    .foregroundColor(isLiveTracking ? .red : .primary)
                Text(isLiveTracking ? "LIVE" : "Progress")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isLiveTracking ? .red : .primary)
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
                        .fill(streakCompleted ? Color.green : (isLiveTracking ? Color.red : Color("appPrimary")))
                        .frame(width: progress * geometry.size.width, height: 4) // progress already capped
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
    let isLiveTracking: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isLiveTracking ? "dot.radiowaves.left.and.right" : "figure.run")
                .foregroundColor(isLiveTracking ? .red : .primary)
            Text(String(format: "%.2f/%.1f mi", milesCompleted, goal))
                .fontWeight(.medium)
            if streakCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if isLiveTracking {
                Text("LIVE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
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
    let isLiveTracking: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: isLiveTracking ? "dot.radiowaves.left.and.right" : "figure.run")
                    .foregroundColor(isLiveTracking ? .red : .primary)
                Text(isLiveTracking ? "Live Tracking" : "Today's Progress")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(isLiveTracking ? .red : .primary)
                Spacer()
                if streakCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if isLiveTracking {
                    HStack(spacing: 2) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .scaleEffect(1.2)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isLiveTracking)
                        Text("LIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.1))
                    )
                }
            }
            
            // Progress Bar - Always capped at 100%
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 16)
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(streakCompleted ? Color.green : (isLiveTracking ? Color.red : Color("appPrimary")))
                        .frame(width: progress * geometry.size.width, height: 16) // progress already capped
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