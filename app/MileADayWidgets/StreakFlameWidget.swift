import WidgetKit
import SwiftUI

// MARK: - Streak Flame Widget
//
// The dashboard's flame, on the home screen. It mirrors the user's chosen
// dashboard style from the App Group: the Fun buddy (face + expressions) or the
// Modern flame framed in the progress ring. The flame burns DOWN with the day
// exactly like the in-app hero — same size curve, same golden→ember palette —
// driven by a per-entry `vigor` value; WidgetKit advances the pre-baked hourly
// entries with no reload cost. Numbers use the dashboard header's stat-line
// styling. The app still force-reloads on every real data write; the timeline
// rebuilds at midnight.

struct StreakFlameEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let progress: Double
    let miles: Double
    let goal: Double
    let isGoalCompleted: Bool
    let health: FlameHealth
    /// Fraction of the day left (1→0). Drives the flame's burn-down; nil when
    /// blazing (done) or coal (no streak), which render at their own size.
    let vigor: Double?
    /// Hours/minutes left, e.g. "5h 12m" (nil when the mile is done).
    let timeLeftValue: String?
    let tokensReady: Int
    let isFun: Bool

    var isAtRisk: Bool { health == .critical }
}

struct StreakFlameProvider: TimelineProvider {
    private struct Snapshot {
        let streak: Int
        let progress: Double
        let miles: Double
        let goal: Double
        let completed: Bool
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
            vigor: 0.62,
            timeLeftValue: "5h 51m",
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
        let burning = !snapshot.completed && snapshot.streak > 0
        return StreakFlameEntry(
            date: date,
            streak: snapshot.streak,
            progress: snapshot.progress,
            miles: snapshot.miles,
            goal: snapshot.goal,
            isGoalCompleted: snapshot.completed,
            health: health,
            vigor: burning ? min(max(secondsToReset / StreakFlameClock.dayLength, 0), 1) : nil,
            timeLeftValue: snapshot.completed ? nil : Self.timeLeftValue(secondsToReset),
            tokensReady: snapshot.tokensReady,
            isFun: snapshot.isFun
        )
    }

    private static func timeLeftValue(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) % 3600 / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

// MARK: - Shared pieces

private func flameStatusColor(_ entry: StreakFlameEntry) -> Color {
    if entry.isGoalCompleted { return MADWidgetStyle.green }
    if entry.isAtRisk { return MADWidgetStyle.red }
    return MADWidgetStyle.orange
}

private func flameDeepLink(_: StreakFlameEntry) -> URL? {
    URL(string: "mileaday://dashboard")
}

/// The flame art itself — Fun buddy or Modern flame in the progress ring, both
/// driven by `vigor` so they shrink exactly like the dashboard hero.
private struct FlameArt: View {
    let entry: StreakFlameEntry
    /// Fun: buddy footprint. Modern: ring diameter.
    let size: CGFloat

    private var vigor: CGFloat? { entry.vigor.map { CGFloat($0) } }

    var body: some View {
        if entry.isFun {
            FlameBuddyFigure(health: entry.health, size: size, showsFace: true, vigor: vigor, grounded: true)
        } else {
            MADWidgetRing(
                progress: entry.progress,
                size: size,
                lineWidth: max(5, size * 0.07),
                isComplete: entry.isGoalCompleted
            ) {
                FlameBuddyFigure(health: entry.health, size: size * 0.70, showsFace: false, vigor: vigor, grounded: false)
            }
        }
    }
}

/// Dashboard-header stat row: tinted icon chip, big value + unit, small-caps
/// label. Mirrors `ModernHeroStatLine`.
private struct FlameStat: View {
    let icon: String
    let value: String
    let unit: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.14)))

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Text(label)
                    .font(.system(size: 8.5, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }
}

/// Big streak number set off by a divider, like the Fun dashboard headline.
private struct FlameStreakHeadline: View {
    let streak: Int
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("\(streak)")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Rectangle()
                .fill(color.opacity(0.5))
                .frame(width: 1, height: 26)
            Text("DAY\nSTREAK")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .tracking(1.0)
                .foregroundColor(color)
                .lineLimit(2)
                .fixedSize()
        }
    }
}

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
        VStack(spacing: 3) {
            FlameArt(entry: entry, size: entry.isFun ? 88 : 98)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(entry.streak)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("DAY STREAK")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundColor(MADWidgetStyle.secondaryText)
            }

            statusPill
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { FlameTokenPill(count: entry.tokensReady) }
        .widgetURL(flameDeepLink(entry))
    }

    @ViewBuilder
    private var statusPill: some View {
        let color = flameStatusColor(entry)
        HStack(spacing: 4) {
            Image(systemName: entry.isGoalCompleted
                  ? "checkmark.seal.fill"
                  : entry.isAtRisk ? "exclamationmark.triangle.fill" : "clock.fill")
                .font(.system(size: 8.5, weight: .semibold))
            Text(entry.isGoalCompleted ? "Streak safe" : (entry.timeLeftValue.map { "\($0) left" } ?? "Keep it alive"))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(color.opacity(0.16)))
    }
}

// MARK: - Medium

private struct MediumFlameView: View {
    let entry: StreakFlameEntry

    var body: some View {
        HStack(spacing: 12) {
            FlameArt(entry: entry, size: entry.isFun ? 146 : 122)
                .frame(width: 140, height: 150)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    FlameStreakHeadline(streak: entry.streak, color: flameStatusColor(entry))
                    Spacer(minLength: 0)
                    FlameTokenPill(count: entry.tokensReady)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                FlameStat(
                    icon: "figure.run",
                    value: String(format: "%.2f", entry.miles),
                    unit: "mi",
                    label: "Mileage",
                    tint: MADWidgetStyle.red
                )

                if entry.isGoalCompleted {
                    FlameStat(icon: "checkmark.seal.fill", value: "Done", unit: "", label: "Streak safe", tint: MADWidgetStyle.green)
                } else {
                    FlameStat(
                        icon: "clock.fill",
                        value: entry.timeLeftValue ?? "--",
                        unit: "left",
                        label: "Left today",
                        tint: flameStatusColor(entry)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .widgetURL(flameDeepLink(entry))
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
    StreakFlameEntry(date: .now, streak: 436, progress: 0.0, miles: 0, goal: 1, isGoalCompleted: false, health: .healthy, vigor: 0.62, timeLeftValue: "5h 51m", tokensReady: 3, isFun: true)
    StreakFlameEntry(date: .now, streak: 436, progress: 0.4, miles: 0.4, goal: 1, isGoalCompleted: false, health: .critical, vigor: 0.2, timeLeftValue: "1h 12m", tokensReady: 0, isFun: false)
    StreakFlameEntry(date: .now, streak: 437, progress: 1.0, miles: 1.0, goal: 1, isGoalCompleted: true, health: .blazing, vigor: nil, timeLeftValue: nil, tokensReady: 2, isFun: true)
}

#Preview(as: .systemMedium) {
    StreakFlameWidget()
} timeline: {
    StreakFlameEntry(date: .now, streak: 436, progress: 0.25, miles: 0.25, goal: 1, isGoalCompleted: false, health: .dimming, vigor: 0.45, timeLeftValue: "5h 12m", tokensReady: 3, isFun: true)
    StreakFlameEntry(date: .now, streak: 436, progress: 0.25, miles: 0.25, goal: 1, isGoalCompleted: false, health: .critical, vigor: 0.2, timeLeftValue: "1h 30m", tokensReady: 3, isFun: false)
}
