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
        WorkoutLiveActivity()
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
        case "behind":  return .orange
        case "winning": return .green
        default:        return .gray
        }
    }

    var body: some View {
        if let summary = entry.summary {
            let color = summary.isStale ? Color.gray : urgencyColor(summary.urgency)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.yellow)

                    Text(summary.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 4)

                    if !summary.rankText.isEmpty {
                        Text(summary.rankText)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 4) {
                    Text(summary.isStale ? "OPEN FOR TODAY'S STANDING" : summary.pill)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(0.5)
                        .foregroundColor(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(color.opacity(0.15)))
                    Spacer(minLength: 0)
                }

                Text(summary.isStale ? "Standings shown are from a previous day." : summary.detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "trophy")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No active competitions")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Start one from the Compete tab")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct CompetitionWidget: Widget {
    let kind: String = "CompetitionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CompetitionProvider()) { entry in
            CompetitionWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Competition")
        .description("Your most urgent competition and what to do today.")
        .supportedFamilies([.systemMedium])
    }
}
