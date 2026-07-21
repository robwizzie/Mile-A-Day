import WidgetKit
import SwiftUI

struct StreakCountEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let liveProgress: Double
    let isGoalCompleted: Bool
    let isAtRisk: Bool
    let timeUntilReset: String?
    /// Sun–Sat goal-completion flags for the current week (empty when unknown).
    var weekCompletions: [Bool] = []
    /// Total miles this week, for the medium widget's status line (0 = unknown).
    var weekMiles: Double = 0
    /// Streak tokens currently held (0 = none or feature off → indicator hidden).
    var tokensReady: Int = 0
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

    func getSnapshot(in context: Context, completion: @escaping (StreakCountEntry) -> Void) {
        let streak = WidgetDataStore.loadStreak()
        let widgetData = WidgetDataStore.load()
        
        // Calculate status
        let isGoalCompleted = widgetData.streakCompleted
        let progress = widgetData.progress
        
        // Calculate risk status and time remaining
        let currentHour = Calendar.current.component(.hour, from: Date())
        let isAtRisk = currentHour >= 18 && !isGoalCompleted
        
        // Calculate time until reset if not completed
        let timeUntilReset = calculateTimeUntilReset(isCompleted: isGoalCompleted)
                
        completion(StreakCountEntry(
            date: Date(),
            streak: streak,
            liveProgress: progress,
            isGoalCompleted: isGoalCompleted,
            isAtRisk: isAtRisk,
            timeUntilReset: timeUntilReset,
            tokensReady: WidgetDataStore.loadTokensReady()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakCountEntry>) -> Void) {
        let streak = WidgetDataStore.loadStreak()
        let widgetData = WidgetDataStore.load()
        
        // Calculate status
        let isGoalCompleted = widgetData.streakCompleted
        let progress = widgetData.progress
        
        // Calculate risk status and time remaining
        let currentHour = Calendar.current.component(.hour, from: Date())
        let isAtRisk = currentHour >= 18 && !isGoalCompleted
        
        // Calculate time until reset if not completed
        let timeUntilReset = calculateTimeUntilReset(isCompleted: isGoalCompleted)
                
        let entry = StreakCountEntry(
            date: Date(),
            streak: streak,
            liveProgress: progress,
            isGoalCompleted: isGoalCompleted,
            isAtRisk: isAtRisk,
            timeUntilReset: timeUntilReset,
            weekCompletions: WidgetDataStore.loadWeekCompletions(),
            weekMiles: WidgetDataStore.loadWeekMiles(),
            tokensReady: WidgetDataStore.loadTokensReady()
        )

        // Refresh more frequently if streak is at risk
        let refreshInterval: TimeInterval = isAtRisk ? 1800 : 3600 // 30 minutes if at risk, 1 hour otherwise

        // Cap the sleep at the next midnight so the "completed today" state
        // resets at the day boundary even if the app is never opened.
        let intervalRefresh = Date().addingTimeInterval(refreshInterval)
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let nextMidnight = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? intervalRefresh
        let nextRefresh = min(intervalRefresh, nextMidnight)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
    
    private func calculateTimeUntilReset(isCompleted: Bool) -> String? {
        if isCompleted { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Get end of today
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
                case .systemMedium:
                    MediumStreakView(entry: entry)
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

// MARK: - Medium (flame + streak on the left, week dots on the right)

struct MediumStreakView: View {
    let entry: StreakCountEntry

    private static let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    private var todayIndex: Int {
        Calendar.current.component(.weekday, from: entry.date) - 1
    }

    private var completedThisWeek: Int {
        entry.weekCompletions.prefix(todayIndex + 1).filter { $0 }.count
    }

    var body: some View {
        HStack(spacing: 14) {
            // Left zone: streak ring with the day-status chip right under it,
            // so the whole card reads as two full columns — no dead bands.
            VStack(spacing: 6) {
                MADWidgetRing(
                    progress: entry.liveProgress,
                    size: 76,
                    lineWidth: 6,
                    isComplete: entry.isGoalCompleted
                ) {
                    VStack(spacing: -1) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(MADWidgetStyle.orange)
                        Text("\(entry.streak)")
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
                Text("DAY STREAK")
                    .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                    .tracking(1.0)
                    .foregroundColor(MADWidgetStyle.secondaryText)

                // Held streak tokens — tiny gold shield count; hidden at 0
                // so pre-token installs render exactly as before.
                if entry.tokensReady > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(entry.tokensReady)")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.35))
                }
            }

            // Right column: section label, the week dots (focal element),
            // and an always-present status line.
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    MADWidgetLabel(icon: "calendar", text: "THIS WEEK", color: MADWidgetStyle.red)
                    Spacer(minLength: 4)
                    if entry.weekMiles > 0 {
                        Text(String(format: "%.1f mi", entry.weekMiles))
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.85))
                    }
                }

                Spacer(minLength: 6)

                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { index in
                        let completed = index < entry.weekCompletions.count ? entry.weekCompletions[index] : false
                        let isToday = index == todayIndex
                        let isFuture = index > todayIndex

                        VStack(spacing: 5) {
                            Text(Self.dayLetters[index])
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(isToday ? .white : MADWidgetStyle.secondaryText)

                            ZStack {
                                Circle()
                                    .fill(
                                        completed
                                            ? AnyShapeStyle(LinearGradient(
                                                colors: [MADWidgetStyle.green, MADWidgetStyle.green.opacity(0.7)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                                            : AnyShapeStyle(Color.white.opacity(isFuture ? 0.05 : 0.12))
                                    )
                                    .frame(width: 23, height: 23)

                                if completed {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                }

                                if isToday {
                                    Circle()
                                        .stroke(
                                            entry.isGoalCompleted ? MADWidgetStyle.green : MADWidgetStyle.red,
                                            lineWidth: 1.5
                                        )
                                        .frame(width: 27, height: 27)
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 6)

                statusLine
            }
            .frame(maxHeight: .infinity)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    // Always-present bottom line so the card never renders an empty band:
    // red countdown when at risk, a green confirmation once the mile is done,
    // otherwise this week's tally as a nudge.
    @ViewBuilder
    private var statusLine: some View {
        if entry.isAtRisk, let timeRemaining = entry.timeUntilReset {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(timeRemaining)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(.red)
        } else if entry.isGoalCompleted {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("Mile done — streak safe")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(MADWidgetStyle.green)
        } else {
            Text("\(completedThisWeek)/7 days · keep it alive")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(MADWidgetStyle.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
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

    // WidgetKit renders this view statically — .onAppear-driven @State
    // animation never plays, so the real progress value is drawn directly.
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            MADWidgetRing(
                progress: entry.liveProgress,
                size: 90,
                lineWidth: 7,
                isComplete: entry.isGoalCompleted
            ) {
                VStack(spacing: -1) {
                    Image(systemName: entry.isAtRisk ? "exclamationmark.triangle.fill" : "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(entry.isAtRisk ? .red : MADWidgetStyle.orange)

                    Text("\(entry.streak)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }

            // Fixed breathing room between the ring and the chip; the flexible
            // spacers above/below keep the ring + chip group optically centered.
            Color.clear.frame(height: 14)

            // Always-present status chip so the ring never floats over an empty
            // band: countdown when at risk, confirmation when done, otherwise
            // today's live progress toward the mile.
            statusChip

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Held streak tokens — a quiet gold shield count in the corner.
        // Hidden at 0 so pre-token installs render exactly as before.
        .overlay(alignment: .topTrailing) {
            if entry.tokensReady > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(entry.tokensReady)")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                }
                .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.35))
            }
        }
        // Unfinished mile → tapping the widget lands straight in the tracker
        // (the widget is a remote control, not just a readout). Once done,
        // tap opens the app normally.
        .widgetURL(entry.isGoalCompleted ? nil : URL(string: "mileaday://workout/start"))
    }

    @ViewBuilder
    private var statusChip: some View {
        if entry.isAtRisk, let timeRemaining = entry.timeUntilReset {
            StreakStatusChip(icon: "exclamationmark.triangle.fill", text: timeRemaining, color: .red)
        } else if entry.isGoalCompleted {
            StreakStatusChip(icon: "flame.fill", text: "Streak safe", color: MADWidgetStyle.green)
        } else {
            StreakStatusChip(icon: nil, text: "\(Int(entry.liveProgress * 100))% today", color: MADWidgetStyle.secondaryText)
        }
    }
}

/// Compact tinted status pill used at the bottom of the streak widget.
private struct StreakStatusChip: View {
    let icon: String?
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}

struct StreakCountWidget: Widget {
    let kind: String = "StreakCountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakCountProvider()) { entry in
            StreakCountWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { MADWidgetStyle.background }
        }
        .configurationDisplayName("Streak Count")
        .description("See your current streak with live progress updates.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) {
    StreakCountWidget()
} timeline: {
    StreakCountEntry(date: .now, streak: 10, liveProgress: 0.7, isGoalCompleted: false, isAtRisk: false, timeUntilReset: "4h 23m remaining")
    StreakCountEntry(date: .now, streak: 7, liveProgress: 0.3, isGoalCompleted: false, isAtRisk: true, timeUntilReset: "2h 15m remaining")
    StreakCountEntry(date: .now, streak: 15, liveProgress: 1.0, isGoalCompleted: true, isAtRisk: false, timeUntilReset: nil)
} 