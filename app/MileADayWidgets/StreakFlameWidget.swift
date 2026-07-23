import WidgetKit
import SwiftUI

// MARK: - Streak Flame Widget
//
// The dashboard's flame, on the home screen. It mirrors the user's chosen
// dashboard style from the App Group: the Fun buddy (with its face and
// expressions) or the Modern flame framed in the progress ring. Informative —
// streak, today's mile, time left — and alive: the flame's color and mood walk
// through the day via pre-baked hourly timeline entries, so it animates its
// story without spending WidgetKit's reload budget. The app still force-reloads
// on every real data write, and the timeline rebuilds at midnight for the fresh
// day.

struct StreakFlameEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let progress: Double
    let miles: Double
    let goal: Double
    let isGoalCompleted: Bool
    let health: FlameHealth
    let timeLeftText: String?
    let weekCompletions: [Bool]
    let tokensReady: Int
    let isFun: Bool

    var isAtRisk: Bool { health == .critical }
}

struct StreakFlameProvider: TimelineProvider {
    /// Immutable per-refresh snapshot read once from the App Group, then shared
    /// across every baked entry (the only per-entry differences are time-driven).
    private struct Snapshot {
        let streak: Int
        let progress: Double
        let miles: Double
        let goal: Double
        let completed: Bool
        let weekCompletions: [Bool]
        let tokensReady: Int
        let isFun: Bool
    }

    func placeholder(in context: Context) -> StreakFlameEntry {
        StreakFlameEntry(
            date: Date(),
            streak: 436,
            progress: 0.0,
            miles: 0,
            goal: 1,
            isGoalCompleted: false,
            health: .healthy,
            timeLeftText: "5h 51m left",
            weekCompletions: [true, true, true, true, false, false, false],
            tokensReady: 3,
            isFun: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakFlameEntry) -> Void) {
        completion(makeEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakFlameEntry>) -> Void) {
        let snapshot = loadSnapshot()
        let calendar = Calendar.current
        let now = Date()
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(3600)

        var entries: [StreakFlameEntry] = []
        var cursor = now
        while cursor < midnight {
            entries.append(makeEntry(date: cursor, snapshot: snapshot))
            cursor = cursor.addingTimeInterval(3600)
        }
        if entries.isEmpty {
            entries.append(makeEntry(date: now, snapshot: snapshot))
        }

        // Rebuild at midnight so the completed/at-risk state resets for the new
        // day even if the app is never opened.
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }

    private func loadSnapshot() -> Snapshot {
        let data = WidgetDataStore.load()
        return Snapshot(
            streak: WidgetDataStore.loadStreak(),
            progress: data.progress,
            miles: data.miles,
            goal: data.goal,
            completed: data.streakCompleted,
            weekCompletions: WidgetDataStore.loadWeekCompletions(),
            tokensReady: WidgetDataStore.loadTokensReady(),
            isFun: WidgetDataStore.loadDashboardStyle() == "fun"
        )
    }

    private func makeEntry(date: Date, snapshot: Snapshot) -> StreakFlameEntry {
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        let secondsToReset = max(0, midnight.timeIntervalSince(date))
        let isAtRisk = !snapshot.completed && calendar.component(.hour, from: date) >= 18
        let health = FlameHealth.forState(
            isCompleted: snapshot.completed,
            distanceIsFresh: true,
            isAtRisk: isAtRisk,
            secondsToReset: snapshot.completed ? nil : secondsToReset,
            streak: snapshot.streak
        )
        return StreakFlameEntry(
            date: date,
            streak: snapshot.streak,
            progress: snapshot.progress,
            miles: snapshot.miles,
            goal: snapshot.goal,
            isGoalCompleted: snapshot.completed,
            health: health,
            timeLeftText: snapshot.completed ? nil : Self.timeLeftText(secondsToReset),
            weekCompletions: snapshot.weekCompletions,
            tokensReady: snapshot.tokensReady,
            isFun: snapshot.isFun
        )
    }

    private static func timeLeftText(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) % 3600 / 60
        return hours > 0 ? "\(hours)h \(minutes)m left" : "\(minutes)m left"
    }
}

// MARK: - Shared helpers

private func flameStatusColor(_ entry: StreakFlameEntry) -> Color {
    if entry.isGoalCompleted { return MADWidgetStyle.green }
    if entry.isAtRisk { return MADWidgetStyle.red }
    return MADWidgetStyle.orange
}

/// Unfinished mile → tap drops straight into the tracker; done → open the app.
private func flameDeepLink(_ entry: StreakFlameEntry) -> URL? {
    entry.isGoalCompleted ? nil : URL(string: "mileaday://workout/start")
}

/// The flame art itself — the Fun buddy, or the Modern flame set in the brand
/// progress ring. Kept in one place so both widget sizes stay in sync.
private struct FlameHero: View {
    let entry: StreakFlameEntry
    /// Footprint of the hero. For Fun this is the buddy size; for Modern it is
    /// the ring diameter.
    let size: CGFloat
    /// Modern only: overlay the streak number inside the ring (small widget,
    /// which has no room for a separate stat column).
    var streakInRing: Bool = false

    var body: some View {
        if entry.isFun {
            FlameBuddyFigure(health: entry.health, size: size)
        } else {
            MADWidgetRing(
                progress: entry.progress,
                size: size,
                lineWidth: max(5, size * 0.075),
                isComplete: entry.isGoalCompleted
            ) {
                ZStack {
                    FlameBuddyFigure(health: entry.health, size: size * 0.60, showsFace: false)
                        .offset(y: -size * 0.05)

                    if streakInRing {
                        VStack(spacing: -2) {
                            Spacer(minLength: 0)
                            Text("\(entry.streak)")
                                .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.7), radius: 3, x: 0, y: 1)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text("DAYS")
                                .font(.system(size: size * 0.075, weight: .black, design: .rounded))
                                .tracking(1.0)
                                .foregroundColor(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                        }
                        .padding(.bottom, size * 0.16)
                    }
                }
            }
        }
    }
}

/// Tinted status pill: green when the mile is banked, red countdown when at
/// risk, otherwise the time left in the day.
private struct FlameStatusChip: View {
    let entry: StreakFlameEntry

    var body: some View {
        let color = flameStatusColor(entry)
        return HStack(spacing: 4) {
            Image(systemName: entry.isGoalCompleted
                  ? "checkmark.seal.fill"
                  : entry.isAtRisk ? "exclamationmark.triangle.fill" : "clock.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(entry.isGoalCompleted ? "Streak safe" : (entry.timeLeftText ?? "Keep it alive"))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundColor(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.16)))
    }
}

/// Held streak tokens — a quiet gold shield count. Hidden at 0 so token-free
/// installs render exactly as before.
private struct FlameTokenPill: View {
    let count: Int

    var body: some View {
        if count > 0 {
            HStack(spacing: 2) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 8, weight: .bold))
                Text("\(count)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
            }
            .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.35))
        }
    }
}

// MARK: - Small

private struct SmallFlameView: View {
    let entry: StreakFlameEntry

    var body: some View {
        VStack(spacing: 4) {
            if entry.isFun {
                FlameHero(entry: entry, size: 74)
                    .frame(maxHeight: .infinity)
                VStack(spacing: -2) {
                    Text("\(entry.streak)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("DAY STREAK")
                        .font(.system(size: 7.5, weight: .black, design: .rounded))
                        .tracking(1.0)
                        .foregroundColor(MADWidgetStyle.secondaryText)
                }
            } else {
                FlameHero(entry: entry, size: 96, streakInRing: true)
                    .frame(maxHeight: .infinity)
            }

            FlameStatusChip(entry: entry)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            FlameTokenPill(count: entry.tokensReady)
        }
        .widgetURL(flameDeepLink(entry))
    }
}

// MARK: - Medium

private struct MediumFlameView: View {
    let entry: StreakFlameEntry

    private static let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    private var todayIndex: Int {
        Calendar.current.component(.weekday, from: entry.date) - 1
    }

    var body: some View {
        HStack(spacing: 14) {
            FlameHero(entry: entry, size: entry.isFun ? 128 : 112)
                .frame(width: 124, height: 150)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    MADWidgetLabel(icon: "flame.fill", text: "DAY STREAK", color: flameStatusColor(entry))
                    Spacer(minLength: 4)
                    FlameTokenPill(count: entry.tokensReady)
                }

                Text("\(entry.streak)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(MADWidgetStyle.red)
                    Text(String(format: "%.2f", entry.miles))
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                    Text(String(format: "/ %.1f mi", entry.goal))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(MADWidgetStyle.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 2)

                weekStrip

                Spacer(minLength: 2)

                FlameStatusChip(entry: entry)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .widgetURL(flameDeepLink(entry))
    }

    private var weekStrip: some View {
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { index in
                let completed = index < entry.weekCompletions.count ? entry.weekCompletions[index] : false
                let isToday = index == todayIndex
                Circle()
                    .fill(completed
                          ? AnyShapeStyle(MADWidgetStyle.green)
                          : AnyShapeStyle(Color.white.opacity(index > todayIndex ? 0.06 : 0.14)))
                    .frame(width: 12, height: 12)
                    .overlay {
                        if isToday {
                            Circle().strokeBorder(flameStatusColor(entry), lineWidth: 1.5)
                        }
                    }
                    .overlay {
                        if completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 6, weight: .black))
                                .foregroundColor(.white)
                        }
                    }
            }
        }
    }
}

// MARK: - Entry view + configuration

struct StreakFlameWidgetEntryView: View {
    var entry: StreakFlameEntry
    @Environment(\.widgetFamily) var widgetFamily

    var body: some View {
        switch widgetFamily {
        case .systemSmall:
            SmallFlameView(entry: entry)
        default:
            MediumFlameView(entry: entry)
        }
    }
}

struct StreakFlameWidget: Widget {
    let kind: String = "StreakFlameWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakFlameProvider()) { entry in
            StreakFlameWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { MADWidgetStyle.background }
        }
        .configurationDisplayName("Streak Flame")
        .description("Your streak flame — the Fun buddy or Modern flame, matching your dashboard.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    StreakFlameWidget()
} timeline: {
    StreakFlameEntry(date: .now, streak: 436, progress: 0.0, miles: 0, goal: 1, isGoalCompleted: false, health: .healthy, timeLeftText: "5h 51m left", weekCompletions: [true, true, true, true, false, false, false], tokensReady: 3, isFun: true)
    StreakFlameEntry(date: .now, streak: 436, progress: 0.4, miles: 0.4, goal: 1, isGoalCompleted: false, health: .critical, timeLeftText: "1h 12m left", weekCompletions: [true, true, true, true, false, false, false], tokensReady: 0, isFun: false)
    StreakFlameEntry(date: .now, streak: 437, progress: 1.0, miles: 1.0, goal: 1, isGoalCompleted: true, health: .blazing, timeLeftText: nil, weekCompletions: [true, true, true, true, true, false, false], tokensReady: 2, isFun: true)
}

#Preview(as: .systemMedium) {
    StreakFlameWidget()
} timeline: {
    StreakFlameEntry(date: .now, streak: 436, progress: 0.25, miles: 0.25, goal: 1, isGoalCompleted: false, health: .dimming, timeLeftText: "5h 51m left", weekCompletions: [true, true, true, true, false, false, false], tokensReady: 3, isFun: true)
    StreakFlameEntry(date: .now, streak: 436, progress: 0.25, miles: 0.25, goal: 1, isGoalCompleted: false, health: .dimming, timeLeftText: "5h 51m left", weekCompletions: [true, true, true, true, false, false, false], tokensReady: 3, isFun: false)
}
