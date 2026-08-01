import WidgetKit
import SwiftUI

struct StreakCountEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let liveProgress: Double
    let isGoalCompleted: Bool
    let isAtRisk: Bool
    /// Deadline for today's mile (next local midnight); nil once it's done.
    /// Rendered as a live countdown rather than a baked string — see
    /// `MADWidgetCountdown`.
    let dayEnd: Date?
    /// Sun–Sat goal-completion flags for the current week (empty when unknown).
    var weekCompletions: [Bool] = []
    /// Total miles this week, for the medium widget's status line (0 = unknown).
    var weekMiles: Double = 0
    /// Streak tokens currently held (0 = none or feature off → indicator hidden).
    var tokensReady: Int = 0
}

struct StreakCountProvider: TimelineProvider {
    private struct Snapshot {
        let streak: Int
        /// `var` so the timeline can derive a fresh-day copy for the entry it
        /// bakes at midnight (see getTimeline).
        var progress: Double
        var isGoalCompleted: Bool
        let weekCompletions: [Bool]
        let weekMiles: Double
        let tokensReady: Int
    }

    func placeholder(in context: Context) -> StreakCountEntry {
        StreakCountEntry(
            date: Date(),
            streak: 5,
            liveProgress: 0.3,
            isGoalCompleted: false,
            isAtRisk: false,
            dayEnd: MADWidgetClock.endOfDay()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakCountEntry) -> Void) {
        completion(makeEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakCountEntry>) -> Void) {
        let snapshot = loadSnapshot()

        // Pre-baked hour-boundary entries instead of a polling refresh policy.
        // The only thing that moves without the app is the clock — the 6 PM
        // at-risk switch — and a baked entry flips it exactly on the hour for
        // free. The old policy asked for a reload every 30-60 minutes (~30/day)
        // for a value the app rewrites (and force-reloads) whenever it changes;
        // that budget, once spent, takes the app's own reloads down with it and
        // freezes the widget on a stale streak.
        let dayEnd = MADWidgetClock.endOfDay()
        var entries = MADWidgetClock.hourlyEntryDates().map { makeEntry(date: $0, snapshot: snapshot) }
        if entries.isEmpty { entries = [makeEntry(date: Date(), snapshot: snapshot)] }

        // Safety net at the day boundary: the store would read as a fresh empty
        // day here anyway, so bake that entry now. If iOS drops the midnight
        // reload the widget still rolls over instead of showing yesterday's
        // "Mile done — streak safe" through the next morning.
        var freshDay = snapshot
        freshDay.progress = 0
        freshDay.isGoalCompleted = false
        entries.append(makeEntry(date: dayEnd, snapshot: freshDay))

        completion(Timeline(entries: entries, policy: .after(dayEnd)))
    }

    private func loadSnapshot() -> Snapshot {
        let widgetData = WidgetDataStore.load()
        return Snapshot(
            streak: WidgetDataStore.loadStreak(),
            progress: widgetData.progress,
            isGoalCompleted: widgetData.streakCompleted,
            weekCompletions: WidgetDataStore.loadWeekCompletions(),
            weekMiles: WidgetDataStore.loadWeekMiles(),
            tokensReady: WidgetDataStore.loadTokensReady()
        )
    }

    private func makeEntry(date: Date, snapshot: Snapshot) -> StreakCountEntry {
        StreakCountEntry(
            date: date,
            streak: snapshot.streak,
            liveProgress: snapshot.progress,
            isGoalCompleted: snapshot.isGoalCompleted,
            isAtRisk: MADWidgetClock.isAtRisk(at: date, isCompleted: snapshot.isGoalCompleted),
            dayEnd: snapshot.isGoalCompleted ? nil : MADWidgetClock.endOfDay(after: date),
            weekCompletions: snapshot.weekCompletions,
            weekMiles: snapshot.weekMiles,
            tokensReady: snapshot.tokensReady
        )
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
        if entry.isAtRisk, let dayEnd = entry.dayEnd {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .semibold))
                MADWidgetCountdown.text(to: dayEnd, suffix: " remaining")
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
                if entry.isAtRisk, let dayEnd = entry.dayEnd {
                    MADWidgetCountdown.text(to: dayEnd, suffix: " remaining")
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
        .widgetURL(URL(string: "mileaday://dashboard"))
    }

    @ViewBuilder
    private var statusChip: some View {
        if entry.isAtRisk, let dayEnd = entry.dayEnd {
            StreakStatusChip(
                icon: "exclamationmark.triangle.fill",
                text: MADWidgetCountdown.text(to: dayEnd, suffix: " left"),
                color: .red
            )
        } else if entry.isGoalCompleted {
            StreakStatusChip(icon: "flame.fill", text: Text("Streak safe"), color: MADWidgetStyle.green)
        } else {
            StreakStatusChip(icon: nil, text: Text("\(Int(entry.liveProgress * 100))% today"), color: MADWidgetStyle.secondaryText)
        }
    }
}

/// Compact tinted status pill used at the bottom of the streak widget.
/// Takes a `Text` rather than a `String` so callers can pass a self-updating
/// countdown (`MADWidgetCountdown`) instead of a value baked at build time.
private struct StreakStatusChip: View {
    let icon: String?
    let text: Text
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            text
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
    StreakCountEntry(date: .now, streak: 10, liveProgress: 0.7, isGoalCompleted: false, isAtRisk: false, dayEnd: .now.addingTimeInterval(4 * 3600))
    StreakCountEntry(date: .now, streak: 7, liveProgress: 0.3, isGoalCompleted: false, isAtRisk: true, dayEnd: .now.addingTimeInterval(2 * 3600))
    StreakCountEntry(date: .now, streak: 15, liveProgress: 1.0, isGoalCompleted: true, isAtRisk: false, dayEnd: nil)
}
