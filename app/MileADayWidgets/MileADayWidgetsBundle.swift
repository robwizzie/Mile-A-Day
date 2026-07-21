//
//  MileADayWidgetsBundle.swift
//  Mile A Day
//
//  Created by Robert Wiscount on 6/13/25.
//

import WidgetKit
import SwiftUI

@main
struct MileADayWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        TodayProgressWidget()
        StreakCountWidget()
        CompetitionWidget()
        DailyLeaderboardWidget()
        WorkoutLiveActivity()
        StreakRiskLiveActivity()
    }
}

// MARK: - Competition Widget
// Shows the user's most urgent active competition ("what should I do today?"),
// mirroring the dashboard's focus cards. The app writes the summary into the
// App Group via WidgetDataStore whenever competitions refresh.

struct CompetitionEntry: TimelineEntry {
    let date: Date
    let summary: WidgetDataStore.CompetitionSummary?
}

struct CompetitionProvider: TimelineProvider {
    func placeholder(in context: Context) -> CompetitionEntry {
        CompetitionEntry(
            date: Date(),
            summary: WidgetDataStore.CompetitionSummary(
                id: "",
                name: "Summer Clash",
                pill: "BEHIND 0.40 MI",
                detail: "You: 0.60 mi · Leader: 1.00 mi",
                rankText: "2nd of 4",
                urgency: "behind",
                isStale: false
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CompetitionEntry) -> Void) {
        completion(CompetitionEntry(date: Date(), summary: WidgetDataStore.loadCompetitionSummary()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CompetitionEntry>) -> Void) {
        let entry = CompetitionEntry(date: Date(), summary: WidgetDataStore.loadCompetitionSummary())

        // Standings only change when the app syncs, so an hourly rebuild is
        // plenty — but never sleep past midnight so the stale-day state shows.
        let intervalRefresh = Date().addingTimeInterval(3600)
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let nextMidnight = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? intervalRefresh
        completion(Timeline(entries: [entry], policy: .after(min(intervalRefresh, nextMidnight))))
    }
}

struct CompetitionWidgetEntryView: View {
    var entry: CompetitionEntry

    private func urgencyColor(_ key: String) -> Color {
        switch key {
        case "urgent":  return Color(red: 1.00, green: 0.45, blue: 0.30)
        case "behind":  return MADWidgetStyle.orange
        case "winning": return MADWidgetStyle.green
        default:        return .gray
        }
    }

    var body: some View {
        if let summary = entry.summary {
            let color = summary.isStale ? Color.gray : urgencyColor(summary.urgency)

            // Title row up top, then real content instead of air: the ranked
            // mini-leaderboard (you highlighted) with the urgency pill as the
            // footer. Old snapshots without standings fall back to the detail
            // sentence so nothing renders empty mid-update.
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.yellow.opacity(0.25), Color.orange.opacity(0.12)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .frame(width: 24, height: 24)
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                            )
                    }

                    Text(summary.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 4)

                    if !summary.rankText.isEmpty {
                        Text(summary.rankText)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(MADWidgetStyle.secondaryText)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                }

                if summary.standings.isEmpty {
                    Spacer(minLength: 2)
                    Text(summary.isStale ? "Standings shown are from a previous day." : summary.detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(MADWidgetStyle.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 2)
                } else {
                    VStack(spacing: 4) {
                        ForEach(Array(summary.standings.prefix(3).enumerated()), id: \.offset) { index, row in
                            standingRow(row, rank: index + 1)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }

                HStack(spacing: 4) {
                    Text(summary.isStale ? "OPEN FOR TODAY'S STANDING" : summary.pill)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundColor(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(
                            Capsule()
                                .fill(color.opacity(0.16))
                                .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
                        )
                    Spacer(minLength: 0)
                }
            }
            .frame(maxHeight: .infinity)
            // Tap lands directly on this competition's detail screen.
            .widgetURL(URL(string: "mileaday://competition/\(summary.id)"))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "trophy")
                    .font(.system(size: 22))
                    .foregroundColor(MADWidgetStyle.secondaryText.opacity(0.6))
                Text("No active competitions")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Start one from the Compete tab")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(MADWidgetStyle.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(URL(string: "mileaday://compete"))
        }
    }

    /// One compact standings row: medal-colored rank dot, name, score.
    /// The user's own row carries the brand tint so "where am I" pops.
    private func standingRow(_ row: WidgetDataStore.StandingRow, rank: Int) -> some View {
        HStack(spacing: 7) {
            MADWidgetRankBadge(rank: rank, size: 17)
            Text(row.isMe ? "You" : row.name)
                .font(.system(size: 12, weight: row.isMe ? .heavy : .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(row.valueText)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(row.isMe ? .white : MADWidgetStyle.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(row.isMe ? MADWidgetStyle.red.opacity(0.22) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(row.isMe ? MADWidgetStyle.red.opacity(0.65) : .clear, lineWidth: 1)
                )
        )
    }
}

/// Gold / silver / bronze rank dot shared by the competition + leaderboard
/// widgets — the same medal language as the post-mile celebration.
struct MADWidgetRankBadge: View {
    let rank: Int
    var size: CGFloat = 20

    private var fill: Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case 2: return Color(white: 0.8)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return Color.white.opacity(0.12)
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(fill)
            Text("\(rank)")
                .font(.system(size: size * 0.55, weight: .black, design: .rounded))
                .foregroundColor(rank <= 3 ? .black : .white)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Daily Leaderboard Widget
// Today's miles race against your friends — the same standings (and the same
// medal/highlight language) as the post-mile leaderboard celebration. The app
// mirrors FriendService.fetchFriendsActivityToday() into the App Group on
// launch and foreground.

struct DailyLeaderboardEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetDataStore.LeaderboardSnapshot?
}

struct DailyLeaderboardProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyLeaderboardEntry {
        DailyLeaderboardEntry(
            date: Date(),
            snapshot: WidgetDataStore.LeaderboardSnapshot(
                rows: [
                    .init(name: "David", miles: 1.56, isMe: false, completed: true),
                    .init(name: "You", miles: 1.17, isMe: true, completed: true),
                    .init(name: "Maddie", miles: 0.42, isMe: false, completed: false)
                ],
                isStale: false
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyLeaderboardEntry) -> Void) {
        completion(DailyLeaderboardEntry(date: Date(), snapshot: WidgetDataStore.loadLeaderboard()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyLeaderboardEntry>) -> Void) {
        let entry = DailyLeaderboardEntry(date: Date(), snapshot: WidgetDataStore.loadLeaderboard())

        // Standings move when the app syncs (which rewrites the snapshot and
        // reloads us), so an hourly rebuild suffices — but never sleep past
        // midnight, when yesterday's race must stop showing as live.
        let intervalRefresh = Date().addingTimeInterval(3600)
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let nextMidnight = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? intervalRefresh
        completion(Timeline(entries: [entry], policy: .after(min(intervalRefresh, nextMidnight))))
    }
}

struct DailyLeaderboardWidgetEntryView: View {
    var entry: DailyLeaderboardEntry

    /// Ranked rows to display: top 3 always; if I'm below the podium, the top
    /// 2 plus my row (with its real rank) — "where am I" always answers in
    /// one glance, exactly like the post-mile board.
    private var displayRows: [(rank: Int, row: WidgetDataStore.LeaderboardRow)] {
        guard let rows = entry.snapshot?.rows else { return [] }
        let ranked = rows.enumerated().map { (rank: $0.offset + 1, row: $0.element) }
        guard let mine = ranked.first(where: { $0.row.isMe }), mine.rank > 3 else {
            return Array(ranked.prefix(3))
        }
        return Array(ranked.prefix(2)) + [mine]
    }

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.isStale, displayRows.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                        )
                    Text("TODAY'S LEADERBOARD")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .tracking(1.6)
                        .foregroundColor(MADWidgetStyle.secondaryText)
                    Spacer(minLength: 0)
                    if let me = snapshot.rows.firstIndex(where: { $0.isMe }) {
                        Text("#\(me + 1) of \(snapshot.rows.count)")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                }

                VStack(spacing: 5) {
                    ForEach(displayRows, id: \.rank) { item in
                        leaderboardRow(item.row, rank: item.rank)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            .widgetURL(URL(string: "mileaday://friends"))
        } else {
            emptyState(stale: entry.snapshot?.isStale == true)
        }
    }

    private func leaderboardRow(_ row: WidgetDataStore.LeaderboardRow, rank: Int) -> some View {
        HStack(spacing: 8) {
            MADWidgetRankBadge(rank: rank, size: 19)
            Text(row.isMe ? "You" : row.name)
                .font(.system(size: 13, weight: row.isMe ? .heavy : .semibold, design: .rounded))
                .foregroundColor(.white.opacity(row.completed || row.isMe ? 1 : 0.55))
                .lineLimit(1)
            if !row.completed && !row.isMe {
                Text("not yet")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(MADWidgetStyle.secondaryText.opacity(0.7))
            }
            Spacer(minLength: 4)
            Text(String(format: "%.2f mi", row.miles))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(row.isMe ? .white : MADWidgetStyle.secondaryText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(row.isMe ? MADWidgetStyle.red.opacity(0.22) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(row.isMe ? MADWidgetStyle.red.opacity(0.65) : .clear, lineWidth: 1)
                )
        )
    }

    private func emptyState(stale: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "trophy")
                .font(.system(size: 22))
                .foregroundColor(MADWidgetStyle.secondaryText.opacity(0.6))
            Text(stale ? "A new race day has started" : "No standings yet")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(stale ? "Open Mile A Day for today's leaderboard" : "Add friends to race daily miles")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(MADWidgetStyle.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "mileaday://friends"))
    }
}

struct DailyLeaderboardWidget: Widget {
    let kind: String = "DailyLeaderboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyLeaderboardProvider()) { entry in
            DailyLeaderboardWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { MADWidgetStyle.background }
        }
        .configurationDisplayName("Daily Leaderboard")
        .description("Today's miles race between you and your friends.")
        .supportedFamilies([.systemMedium])
    }
}

struct CompetitionWidget: Widget {
    let kind: String = "CompetitionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CompetitionProvider()) { entry in
            CompetitionWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { MADWidgetStyle.background }
        }
        .configurationDisplayName("Competition")
        .description("Your most urgent competition and what to do today.")
        .supportedFamilies([.systemMedium])
    }
}
