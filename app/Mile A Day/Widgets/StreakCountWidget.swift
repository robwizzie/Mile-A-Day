import WidgetKit
import SwiftUI

struct StreakCountEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let liveProgress: Double
    let isGoalCompleted: Bool
    let isAtRisk: Bool
}

struct StreakCountProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakCountEntry {
        StreakCountEntry(
            date: Date(), 
            streak: 5, 
            liveProgress: 0.3, 
            isGoalCompleted: false,
            isAtRisk: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakCountEntry) -> Void) {
        let streak = WidgetDataStore.loadStreak()
        let widgetData = WidgetDataStore.load()
        
        // Calculate status
        let isGoalCompleted = widgetData.streakCompleted
        let progress = widgetData.progress
        
        // Simple risk calculation for widget (past 6pm and not completed)
        let currentHour = Calendar.current.component(.hour, from: Date())
        let isAtRisk = currentHour >= 18 && !isGoalCompleted
        
        print("[Streak Widget] Snapshot - Streak: \(streak), Progress: \(progress * 100)%, Completed: \(isGoalCompleted)")
        
        completion(StreakCountEntry(
            date: Date(), 
            streak: streak, 
            liveProgress: progress, 
            isGoalCompleted: isGoalCompleted,
            isAtRisk: isAtRisk
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakCountEntry>) -> Void) {
        let streak = WidgetDataStore.loadStreak()
        let widgetData = WidgetDataStore.load()
        
        // Calculate status
        let isGoalCompleted = widgetData.streakCompleted
        let progress = widgetData.progress
        
        // Simple risk calculation for widget
        let currentHour = Calendar.current.component(.hour, from: Date())
        let isAtRisk = currentHour >= 18 && !isGoalCompleted
        
        print("[Streak Widget] Timeline - Streak: \(streak), Progress: \(progress * 100)%, Completed: \(isGoalCompleted)")
        
        let entry = StreakCountEntry(
            date: Date(), 
            streak: streak, 
            liveProgress: progress, 
            isGoalCompleted: isGoalCompleted,
            isAtRisk: isAtRisk
        )
        
        // Refresh hourly
        let refreshInterval: TimeInterval = 3600
        let nextRefresh = Date().addingTimeInterval(refreshInterval)
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
                    CircularStreakView(entry: entry)
                case .accessoryRectangular:
                    RectangularStreakView(entry: entry)
                case .accessoryInline:
                    InlineStreakView(entry: entry)
                default:
                    HomeScreenStreakView(entry: entry)
                }
            } else {
                HomeScreenStreakView(entry: entry)
            }
        }
    }
    
    @Environment(\.widgetFamily) var widgetFamily
}

// MARK: - Enhanced Widget Views Matching Dashboard

// Color calculation helper
extension StreakCountEntry {
    var streakColor: Color {
        if isGoalCompleted {
            return .green
        } else if isAtRisk {
            return .red
        } else {
            return .orange
        }
    }
    
    var backgroundColor: Color {
        if isGoalCompleted {
            return .green.opacity(0.1)
        } else if isAtRisk {
            return .red.opacity(0.1)
        } else {
            return .orange.opacity(0.1)
        }
    }
}

// MARK: - Lock Screen Views

@available(iOS 16.0, *)
struct CircularStreakView: View {
    let entry: StreakCountEntry
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(entry.backgroundColor)
                .frame(width: 50, height: 50)
            
            // Live progress ring (matches dashboard design)
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 2)
                .frame(width: 55, height: 55)
            
            Circle()
                .trim(from: 0, to: entry.liveProgress)
                .stroke(entry.streakColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 55, height: 55)
                .rotationEffect(.degrees(-90))
            
            // Center content
            VStack(spacing: 1) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10))
                    .foregroundColor(entry.streakColor)
                
                Text("\(entry.streak)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(entry.streakColor)
            }
        }
    }
}

@available(iOS 16.0, *)
struct RectangularStreakView: View {
    let entry: StreakCountEntry
    
    var body: some View {
        HStack(spacing: 8) {
            // Icon with background
            ZStack {
                Circle()
                    .fill(entry.backgroundColor)
                    .frame(width: 28, height: 28)
                
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundColor(entry.streakColor)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                Text("Streak")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                
                Text("\(entry.streak) days")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(entry.streakColor)
            }
            
            Spacer()
            
            // Progress indicator
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 20, height: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .fill(entry.streakColor)
                        .frame(width: 20 * entry.liveProgress, height: 2),
                    alignment: .leading
                )
        }
        .padding(.horizontal, 4)
    }
}

@available(iOS 16.0, *)
struct InlineStreakView: View {
    let entry: StreakCountEntry
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .foregroundColor(entry.streakColor)
            
            Text("\(entry.streak) day streak")
                .fontWeight(.medium)
        }
    }
}

// MARK: - Home Screen View

struct HomeScreenStreakView: View {
    let entry: StreakCountEntry
    @State private var animateProgress = false
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [entry.streakColor.opacity(0.3), entry.streakColor.opacity(0.1)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 90, height: 90)
            
            // Live progress ring
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                .frame(width: 100, height: 100)
            
            Circle()
                .trim(from: 0, to: animateProgress ? entry.liveProgress : 0)
                .stroke(entry.streakColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: animateProgress)
            

            
            // Streak number in center
            VStack(spacing: 4) {
                Text("\(entry.streak)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(entry.streakColor)
                
                Text(entry.streak == 1 ? "day" : "days")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(entry.streakColor.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            animateProgress = true
        }
    }
}

struct StreakCountWidget: Widget {
    let kind: String = "StreakCountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakCountProvider()) { entry in
            StreakCountWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Streak Count")
        .description("See your current streak with live progress updates.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) {
    StreakCountWidget()
} timeline: {
    StreakCountEntry(date: .now, streak: 10, liveProgress: 0.7, isGoalCompleted: false, isAtRisk: false)
} 