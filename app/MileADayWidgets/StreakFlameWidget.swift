import WidgetKit
import SwiftUI

/// Display miles truncated to 2 decimals — NEVER rounded up, so a shown
/// "1.00" always means the mile is actually there (0.995 used to round up
/// beside an incomplete goal). Private copy of `Double.milesFloor2` in the
/// main app's Extensions.swift — widget-extension targets can't see that
/// file; keep the formula in sync.
private func flooredMilesText(_ miles: Double) -> String {
    String(format: "%.2f", (miles * 100.0 + 1e-6).rounded(.down) / 100.0)
}

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
    /// Deadline for today's mile (next local midnight); nil when it's done.
    /// Rendered as a live countdown, never as a string baked at build time —
    /// entries can sit on screen for an hour, which is how this widget read
    /// "7h 24m left" at 5:28 PM while the dashboard said "6h 30m".
    let dayEnd: Date?
    let tokensReady: Int
    let isFun: Bool
    /// All-time best, for the dashboard hero's gold "BEST EVER" crown.
    var longestStreak: Int = 0
    /// Today's steps. Refreshed roughly per 1,000 (see `WidgetDataStore`), so
    /// it lags the dashboard's live number by up to a bucket.
    var steps: Int = 0

    var isAtRisk: Bool { health == .critical }

    /// Same rule as the dashboard hero — `>= 7` so a brand-new account isn't
    /// crowned on day 1.
    var atAllTimeBest: Bool {
        longestStreak > 0 && streak >= longestStreak && streak >= 7
    }

    /// Mirrors `FlameBuddyHeroCard.statusText`. The widget has no "Syncing"
    /// state: the store only ever holds values the app already trusted.
    /// (Named `statusLabel` so it can't be confused with `SmallFlameView`'s
    /// own `statusText`, which is the countdown.)
    var statusLabel: String {
        if isGoalCompleted { return "Streak safe" }
        if isAtRisk { return "Streak at risk" }
        return "Keep it alive"
    }
}

struct StreakFlameProvider: TimelineProvider {
    private struct Snapshot {
        let streak: Int
        let longestStreak: Int
        /// `var` so the timeline can derive a fresh-day copy for the entry it
        /// bakes at midnight (see getTimeline).
        var progress: Double
        var miles: Double
        var steps: Int
        let goal: Double
        var completed: Bool
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
            dayEnd: MADWidgetClock.endOfDay(),
            tokensReady: 3,
            isFun: true,
            longestStreak: 436,
            steps: 6842
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakFlameEntry) -> Void) {
        completion(makeEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakFlameEntry>) -> Void) {
        let snapshot = loadSnapshot()

        // Entries land on real hour boundaries (not at an arbitrary offset from
        // whenever the timeline happened to be built), so the flame's burn-down
        // and the at-risk switch step when they actually should.
        let dayEnd = MADWidgetClock.endOfDay()
        var entries = MADWidgetClock.hourlyEntryDates().map { makeEntry(date: $0, snapshot: snapshot) }
        if entries.isEmpty { entries = [makeEntry(date: Date(), snapshot: snapshot)] }

        // Safety net at the day boundary: the store would read as a fresh empty
        // day here anyway, so bake that entry now. If iOS drops the midnight
        // reload the flame still relights for the new day instead of sitting
        // "blazing / streak safe" on yesterday's mile all morning.
        var freshDay = snapshot
        freshDay.progress = 0
        freshDay.miles = 0
        freshDay.steps = 0
        freshDay.completed = false
        entries.append(makeEntry(date: dayEnd, snapshot: freshDay))

        completion(Timeline(entries: entries, policy: .after(dayEnd)))
    }

    private func loadSnapshot() -> Snapshot {
        let data = WidgetDataStore.load()
        return Snapshot(
            streak: WidgetDataStore.loadStreak(),
            longestStreak: WidgetDataStore.loadLongestStreak(),
            progress: data.progress,
            miles: data.miles,
            steps: WidgetDataStore.loadTodaySteps(),
            goal: data.goal,
            completed: data.streakCompleted,
            tokensReady: WidgetDataStore.loadTokensReady(),
            isFun: WidgetDataStore.loadDashboardStyle() == "fun"
        )
    }

    private func makeEntry(date: Date, snapshot: Snapshot) -> StreakFlameEntry {
        let midnight = MADWidgetClock.endOfDay(after: date)
        let secondsToReset = max(0, midnight.timeIntervalSince(date))
        let isAtRisk = MADWidgetClock.isAtRisk(at: date, isCompleted: snapshot.completed)
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
            dayEnd: snapshot.completed ? nil : midnight,
            tokensReady: snapshot.tokensReady,
            isFun: snapshot.isFun,
            longestStreak: snapshot.longestStreak,
            steps: snapshot.steps
        )
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

/// Mirrors `HeroStatColumn.stepTint` — same thresholds, same colours, so the
/// steps row is the same shade in both places.
private func flameStepTint(_ steps: Int) -> Color {
    if steps >= 10000 { return Color(red: 0.2, green: 0.7, blue: 0.3) }   // MADTheme success
    if steps >= 7500 { return Color(red: 1.0, green: 0.6, blue: 0.0) }    // MADTheme warning
    if steps >= 5000 { return .yellow }
    return .orange
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

/// Sizing for the medium widget's stat column, DERIVED from the height the
/// column is actually given rather than assumed.
///
/// The steps row went missing twice because the layout was picked from a
/// predicted canvas height. Predicting it is the mistake: a medium widget's
/// usable height depends on the device AND on system content margins that are
/// nothing like the documented figure. So nothing here is a constant — the row
/// height is whatever is left after the streak box, split three ways, and the
/// type scales to the row. The column fills its space exactly, on any device,
/// and all three stats always fit because they are what the arithmetic solves
/// for.
private struct FlameColumnMetrics {
    let boxHeight: CGFloat
    let streakSize: CGFloat
    let rowHeight: CGFloat
    let iconSize: CGFloat
    let valueSize: CGFloat
    let labelSize: CGFloat
    let spacing: CGFloat

    /// Solves `box + spacing + 3 × row + 2 hairlines == height`, then sizes the
    /// type to the row. The caps are the "looks right on a big widget" values;
    /// the floors stop a freak small canvas from rendering unreadable type
    /// (it would overflow slightly instead, which is the better failure).
    static func fitting(height: CGFloat) -> FlameColumnMetrics {
        let spacing: CGFloat = 4
        let box = min(38, max(26, height * 0.30))
        let row = max(18, (height - box - spacing - 2) / 3)
        return FlameColumnMetrics(
            boxHeight: box,
            streakSize: min(25, box * 0.66),
            rowHeight: row,
            iconSize: min(22, row * 0.82),
            valueSize: min(15, row * 0.56),
            labelSize: min(7.5, row * 0.30),
            spacing: spacing
        )
    }
}

/// Dashboard-header stat row: tinted icon chip, big value + unit, small-caps
/// label. Mirrors `ModernHeroStatLine`.
private struct FlameStat: View {
    let icon: String
    /// A `Text` rather than a `String` so the "left today" row can carry a
    /// self-updating countdown instead of a value baked at build time.
    let value: Text
    let unit: String
    let label: String
    let tint: Color
    let metrics: FlameColumnMetrics

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: metrics.iconSize * 0.45, weight: .bold))
                .foregroundColor(tint)
                .frame(width: metrics.iconSize, height: metrics.iconSize)
                .background(Circle().fill(tint.opacity(0.14)))

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    value
                        .font(.system(size: metrics.valueSize, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .font(.system(size: metrics.labelSize + 0.5, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Text(label)
                    .font(.system(size: metrics.labelSize, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        // FIXED, not minHeight: the column's height has to be knowable without
        // measuring text. Two frames because `frame` has no
        // maxWidth-plus-height overload.
        .frame(height: metrics.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hairline between stat rows — the dashboard hero's `ModernHeroDivider`,
/// inset past the icon chip so it starts under the text.
private struct FlameStatDivider: View {
    let metrics: FlameColumnMetrics

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, metrics.iconSize + 8)
    }
}

/// The dashboard hero's streak box at widget scale: big number, hairline
/// divider, "DAY STREAK" over either the gold all-time-best crown or the day's
/// status, all inside the same bordered pill. It used to be bare text with
/// "DAY / STREAK" wrapped onto two lines, which is what made the widget and
/// the dashboard read as two different apps.
private struct FlameStreakBox: View {
    let entry: StreakFlameEntry
    let statusColor: Color
    let metrics: FlameColumnMetrics

    private static let gold = Color(red: 1.0, green: 0.78, blue: 0.25)

    private var accent: Color { entry.atAllTimeBest ? Self.gold : statusColor }

    var body: some View {
        // Sized for the NARROWEST medium widget (a 375pt phone leaves this
        // column ~145pt), so nothing has to auto-shrink on a small screen.
        HStack(alignment: .center, spacing: 6) {
            Text("\(entry.streak)")
                .font(.system(size: metrics.streakSize, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .layoutPriority(1)

            Rectangle()
                .fill(accent.opacity(0.45))
                .frame(width: 1, height: metrics.boxHeight * 0.5)

            VStack(alignment: .leading, spacing: 1) {
                Text("DAY STREAK")
                    .font(.system(size: metrics.labelSize + 1, weight: .black, design: .rounded))
                    .tracking(0.5)
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if entry.atAllTimeBest {
                    HStack(spacing: 2) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: metrics.labelSize, weight: .black))
                        Text("BEST EVER")
                            .font(.system(size: metrics.labelSize + 1, weight: .black, design: .rounded))
                            .tracking(0.4)
                    }
                    .foregroundColor(Self.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                } else {
                    Text(entry.statusLabel)
                        .font(.system(size: metrics.labelSize + 1, weight: .black, design: .rounded))
                        .tracking(0.3)
                        .textCase(.uppercase)
                        .foregroundColor(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
            }

            Spacer(minLength: 2)

            FlameTokenPill(count: entry.tokensReady, tint: entry.isFun ? MADWidgetStyle.green : .cyan)
        }
        .padding(.horizontal, 8)
        // FIXED height, so the column's total is arithmetic — see FlameColumnMetrics.
        .frame(height: metrics.boxHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(entry.atAllTimeBest ? Self.gold.opacity(0.10) : Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accent.opacity(entry.atAllTimeBest ? 0.45 : 0.20), lineWidth: 1)
                )
        )
    }
}

/// The dashboard's savers chip, shrunk to fit. The word "savers" is what gets
/// dropped for the widget — the tinted capsule is the recognisable part.
private struct FlameTokenPill: View {
    let count: Int
    var tint: Color = MADWidgetStyle.green

    var body: some View {
        if count > 0 {
            HStack(spacing: 3) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 8, weight: .bold))
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .black, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundColor(.white.opacity(0.90))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .fixedSize()
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.30), lineWidth: 1))
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
        .overlay(alignment: .topTrailing) {
            FlameTokenPill(count: entry.tokensReady, tint: entry.isFun ? MADWidgetStyle.green : .cyan)
        }
        .widgetURL(flameDeepLink(entry))
    }

    private var statusText: Text {
        if entry.isGoalCompleted { return Text("Streak safe") }
        guard let dayEnd = entry.dayEnd else { return Text("Keep it alive") }
        return MADWidgetCountdown.text(to: dayEnd, suffix: " left")
    }

    @ViewBuilder
    private var statusPill: some View {
        let color = flameStatusColor(entry)
        HStack(spacing: 4) {
            Image(systemName: entry.isGoalCompleted
                  ? "checkmark.seal.fill"
                  : entry.isAtRisk ? "exclamationmark.triangle.fill" : "clock.fill")
                .font(.system(size: 8.5, weight: .semibold))
            statusText
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
        HStack(spacing: 10) {
            // maxHeight, not a fixed 146: a child taller than the container
            // makes the HStack taller than the canvas, and then the
            // GeometryReader beside it can't be trusted to report the real
            // height. The art still DRAWS at 146 and overflows exactly as
            // before — only its layout height changes.
            FlameArt(entry: entry, size: entry.isFun ? 146 : 122)
                .frame(width: 132)
                .frame(maxHeight: .infinity)

            // Measure, don't predict. A ViewThatFits between a with-steps and a
            // without-steps candidate silently dropped the row whenever the
            // predicted height was off — and it was, twice, because a medium
            // widget's usable height is well under what the content-margin
            // docs imply. Reading the real height makes all three rows fit by
            // construction instead of by luck.
            GeometryReader { geo in
                column(metrics: .fitting(height: geo.size.height))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity)
        .widgetURL(flameDeepLink(entry))
    }

    private func column(metrics: FlameColumnMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing) {
            FlameStreakBox(entry: entry, statusColor: flameStatusColor(entry), metrics: metrics)

            // Rows separated by hairlines rather than one rule above the
            // block, so the stack matches the dashboard's stat column.
            VStack(spacing: 0) {
                FlameStat(
                    icon: "figure.run",
                    value: Text(flooredMilesText(entry.miles)),
                    unit: "mi",
                    label: "Mileage",
                    tint: MADWidgetStyle.red,
                    metrics: metrics
                )

                FlameStatDivider(metrics: metrics)

                FlameStat(
                    icon: "shoeprints.fill",
                    value: Text(entry.steps.formatted()),
                    unit: "steps",
                    label: "Steps",
                    tint: flameStepTint(entry.steps),
                    metrics: metrics
                )

                FlameStatDivider(metrics: metrics)

                if entry.isGoalCompleted {
                    FlameStat(icon: "checkmark.seal.fill", value: Text("Done"), unit: "", label: "Streak safe", tint: MADWidgetStyle.green, metrics: metrics)
                } else {
                    FlameStat(
                        icon: "clock.fill",
                        value: entry.dayEnd.map { MADWidgetCountdown.text(to: $0) } ?? Text("--"),
                        // No unit: a `.relative` Text is greedy, so it claimed
                        // the row's spare width and stranded "left" against the
                        // far edge. "LEFT TODAY" underneath already says it.
                        unit: "",
                        label: "Left today",
                        tint: flameStatusColor(entry),
                        metrics: metrics
                    )
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
    StreakFlameEntry(date: .now, streak: 436, progress: 0.0, miles: 0, goal: 1, isGoalCompleted: false, health: .healthy, vigor: 0.62, dayEnd: .now.addingTimeInterval(5.85 * 3600), tokensReady: 3, isFun: true, longestStreak: 436, steps: 4210)
    StreakFlameEntry(date: .now, streak: 436, progress: 0.4, miles: 0.4, goal: 1, isGoalCompleted: false, health: .critical, vigor: 0.2, dayEnd: .now.addingTimeInterval(1.2 * 3600), tokensReady: 0, isFun: false, longestStreak: 500, steps: 8930)
    StreakFlameEntry(date: .now, streak: 437, progress: 1.0, miles: 1.0, goal: 1, isGoalCompleted: true, health: .blazing, vigor: nil, dayEnd: nil, tokensReady: 2, isFun: true, longestStreak: 437, steps: 12480)
}

#Preview(as: .systemMedium) {
    StreakFlameWidget()
} timeline: {
    // At the all-time best (gold crown) …
    StreakFlameEntry(date: .now, streak: 448, progress: 0.25, miles: 0.25, goal: 1, isGoalCompleted: false, health: .dimming, vigor: 0.45, dayEnd: .now.addingTimeInterval(5.2 * 3600), tokensReady: 3, isFun: true, longestStreak: 448, steps: 7420)
    // … and chasing one, at risk (status line instead of the crown).
    StreakFlameEntry(date: .now, streak: 436, progress: 0.25, miles: 0.25, goal: 1, isGoalCompleted: false, health: .critical, vigor: 0.2, dayEnd: .now.addingTimeInterval(1.5 * 3600), tokensReady: 3, isFun: false, longestStreak: 500, steps: 11305)
}
