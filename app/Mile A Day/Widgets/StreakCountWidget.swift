import WidgetKit
import SwiftUI

struct StreakCountEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let liveProgress: Double
    let isGoalCompleted: Bool
    let isAtRisk: Bool
    let timeUntilReset: String?
}

struct StreakCountProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakCountEntry {
        StreakCountEntry(
            date: Date(), 
            streak: 5, 
            liveProgress: 0.3, 
            isGoalCompleted: false,
            isAtRisk: false,
            timeUntilReset: "6h 30m remaining"
        )
    }

    private var utcCalendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakCountEntry) -> Void) {
        let streak = WidgetDataStore.loadStreak()
        let widgetData = WidgetDataStore.load()
        
        // Calculate status
        let isGoalCompleted = widgetData.streakCompleted
        let progress = widgetData.progress
        
        // Calculate risk status and time remaining
        let currentHour = utcCalendar.component(.hour, from: Date())
        let isAtRisk = currentHour >= 18 && !isGoalCompleted
        
        // Calculate time until reset if not completed
        let timeUntilReset = calculateTimeUntilReset(isCompleted: isGoalCompleted)
        
        print("[Streak Widget] Snapshot - Streak: \(streak), Progress: \(progress * 100)%, Completed: \(isGoalCompleted), At Risk: \(isAtRisk)")
        
        completion(StreakCountEntry(
            date: Date(), 
            streak: streak, 
            liveProgress: progress, 
            isGoalCompleted: isGoalCompleted,
            isAtRisk: isAtRisk,
            timeUntilReset: timeUntilReset
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakCountEntry>) -> Void) {
        let streak = WidgetDataStore.loadStreak()
        let widgetData = WidgetDataStore.load()
        
        // Calculate status
        let isGoalCompleted = widgetData.streakCompleted
        let progress = widgetData.progress
        
        // Calculate risk status and time remaining
        let currentHour = utcCalendar.component(.hour, from: Date())
        let isAtRisk = currentHour >= 18 && !isGoalCompleted
        
        // Calculate time until reset if not completed
        let timeUntilReset = calculateTimeUntilReset(isCompleted: isGoalCompleted)
        
        print("[Streak Widget] Timeline - Streak: \(streak), Progress: \(progress * 100)%, Completed: \(isGoalCompleted), At Risk: \(isAtRisk)")
        
        let entry = StreakCountEntry(
            date: Date(), 
            streak: streak, 
            liveProgress: progress, 
            isGoalCompleted: isGoalCompleted,
            isAtRisk: isAtRisk,
            timeUntilReset: timeUntilReset
        )
        
        // Refresh more frequently if streak is at risk
        let refreshInterval: TimeInterval = isAtRisk ? 1800 : 3600 // 30 minutes if at risk, 1 hour otherwise
        let nextRefresh = Date().addingTimeInterval(refreshInterval)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
    
    private func calculateTimeUntilReset(isCompleted: Bool) -> String? {
        if isCompleted { return nil }
        
        let calendar = utcCalendar
        let now = Date()
        
        // Get end of today in UTC
        guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) else {
            return nil
        }
        
        let timeRemaining = endOfDay.timeIntervalSince(now)
        let hours = Int(timeRemaining) / 3600
        let minutes = Int(timeRemaining) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else {
            return "\(minutes)m remaining"
        }
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
                    
                    // At-risk indicator
                    if entry.isAtRisk {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.red)
                    }
                }
                
                Text("\(entry.streak) days")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(entry.streakColor)
                
                // Show time remaining if at risk - use same color as streak
                if entry.isAtRisk, let timeRemaining = entry.timeUntilReset {
                    Text(timeRemaining)
                        .font(.system(size: 8))
                        .foregroundColor(entry.streakColor.opacity(0.8))
                        .lineLimit(1)
                }
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
            
            // At-risk indicator
            if entry.isAtRisk {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption2)
            }
        }
    }
}

// MARK: - Home Screen View

struct HomeScreenStreakView: View {
    let entry: StreakCountEntry
    @State private var animateProgress = false
    @State private var animateAtRisk = false
    
    var body: some View {
        VStack(spacing: 4) {
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
                    .scaleEffect(animateAtRisk ? 1.05 : 1.0)
                
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
                VStack(spacing: 2) {
                    // At-risk warning icon
                    if entry.isAtRisk {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .scaleEffect(animateAtRisk ? 1.2 : 1.0)
                    }
                    
                    Text("\(entry.streak)")
                        .font(.system(size: entry.isAtRisk ? 28 : 32, weight: .bold, design: .rounded))
                        .foregroundColor(entry.streakColor)
                    
                    Text(entry.streak == 1 ? "day" : "days")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(entry.streakColor.opacity(0.8))
                }
            }
            
            // Time remaining below the circle if at risk
            if entry.isAtRisk, let timeRemaining = entry.timeUntilReset {
                Text(timeRemaining)
                    .font(.system(size: 10))
                    .foregroundColor(entry.streakColor.opacity(0.8))
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            animateProgress = true
            
            // Start pulsing animation for at-risk streaks
            if entry.isAtRisk {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    animateAtRisk = true
                }
            }
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
    StreakCountEntry(date: .now, streak: 10, liveProgress: 0.7, isGoalCompleted: false, isAtRisk: false, timeUntilReset: "4h 23m remaining")
    StreakCountEntry(date: .now, streak: 7, liveProgress: 0.3, isGoalCompleted: false, isAtRisk: true, timeUntilReset: "2h 15m remaining")
    StreakCountEntry(date: .now, streak: 15, liveProgress: 1.0, isGoalCompleted: true, isAtRisk: false, timeUntilReset: nil)
} 