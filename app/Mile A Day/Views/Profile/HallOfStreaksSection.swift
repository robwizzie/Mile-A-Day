//
//  HallOfStreaksSection.swift
//  Mile A Day
//
//  Hall of Streaks: a user's record, then their best runs ranked. Reframes
//  a broken streak from "lost everything" into "here's where this one sits".
//  Self-contained — owns its fetch, parents drop it in with a user id (works
//  for self AND friend profiles; the endpoint authorizes like /stats).
//
//  This deliberately does NOT present streaks as numbered "eras". That version
//  labelled runs "ERA 27" / "ERA 19" — a chronological index nobody asked for,
//  which reads as a system detail rather than an achievement, and invites the
//  question "what happened to eras 20 through 26?". Ranking by LENGTH answers
//  the question people actually have (how does this run compare to my best?),
//  and makes the number on each row mean something: #1 is your record.
//

import SwiftUI

struct HallOfStreaksSection: View {
    let userId: String?
    let isSelf: Bool

    @State private var response: StreakErasResponse?
    @State private var showAll = false

    private let workoutService = WorkoutService()
    private let gold = Color(red: 1.0, green: 0.78, blue: 0.25)
    /// Rows shown before "Show all".
    private let collapsedCount = 4
    /// Hard ceiling on the expanded list. Someone with 140 streaks does not
    /// want 140 rows, and no amount of scrolling makes the 90th one matter.
    private let maxRows = 10
    /// Minimum-length rungs, tried in order. The FIRST rung that brings the
    /// list under `maxRows` wins.
    ///
    /// A fixed threshold can't work for both ends of the population: "5+ days"
    /// buries a light user's entire history (they may have nothing longer),
    /// while for the user with 140 streaks — most of them 2-day — even 5+ is
    /// still a wall of noise. Letting the bar rise with the size of the
    /// history means a sparse user keeps their 2-day runs and a prolific one
    /// only ever sees runs that were actually an achievement FOR THEM. The
    /// bar is relative to the person, which is the only way it reads as
    /// meaningful rather than arbitrary.
    private let lengthRungs = [2, 3, 5, 7, 10, 14, 21, 30, 50, 100]

    var body: some View {
        Group {
            if let response, !shortlist(response).rows.isEmpty {
                content(response)
            } else {
                // Real (zero-size) view, NOT EmptyView: a body that renders
                // EmptyView gets no lifecycle, so the .task below would never
                // fire and the section could never load itself (ios.md).
                Color.clear.frame(height: 0)
            }
        }
        .task(id: userId) { await load() }
    }

    private func load() async {
        guard let userId, !userId.isEmpty else { return }
        // Self profile: show the session cache instantly, then refresh.
        if isSelf, response == nil, let cached = StreakErasStore.shared.response {
            response = cached
        }
        do {
            let fresh = try await workoutService.getStreakEras(userId: userId)
            response = fresh
        } catch {
            print("[HallOfStreaks] load failed: \(error)")
        }
    }

    // MARK: - Data

    private struct RankedStreak: Identifiable {
        let rank: Int
        let era: StreakEraAPI
        var id: String { era.id }
    }

    private struct Shortlist {
        var rows: [RankedStreak]
        /// Minimum length that actually got applied, for the header chip.
        var minLength: Int
        var totalStreaks: Int
        var totalDays: Int
        /// True when anything was held back, so the UI can say so.
        var isTrimmed: Bool { totalStreaks > rows.count }
    }

    /// What to show, and how hard we had to filter to get there.
    ///
    /// Ranks are computed over the FULL history before any filtering, so #1 is
    /// always the real record and a rank is never a position in a filtered
    /// list. Because the sort is by length descending, taking everything at or
    /// above a threshold yields exactly the top K — so visible ranks stay
    /// contiguous, and the only non-contiguous row is the current streak when
    /// it's too short to have qualified on merit.
    private func shortlist(_ response: StreakErasResponse) -> Shortlist {
        let sorted = response.eras.sorted { a, b in
            if a.length != b.length { return a.length > b.length }
            return a.end_date > b.end_date
        }
        let ranks = sorted.enumerated().map { RankedStreak(rank: $0.offset + 1, era: $0.element) }

        // Climb the rungs until the list fits. `last` is the fallback for the
        // (unlikely) history that still overflows at 100+ days; prefix trims it.
        var minLength = lengthRungs.last ?? 2
        for rung in lengthRungs where ranks.filter({ $0.era.length >= rung }).count <= maxRows {
            minLength = rung
            break
        }

        var rows = Array(ranks.filter { $0.era.length >= minLength }.prefix(maxRows))

        // The current run always earns a place, however short and however
        // crowded the history — "where does today's run stand" is the whole
        // reason someone opens this. It keeps its true rank rather than being
        // pinned to the top: being 87th is the honest, motivating answer.
        if let current = ranks.first(where: { $0.era.is_current }),
            !rows.contains(where: { $0.id == current.id })
        {
            rows.append(current)
        }

        return Shortlist(
            rows: rows,
            minLength: minLength,
            totalStreaks: response.eras.count,
            totalDays: response.eras.reduce(0) { $0 + $1.length }
        )
    }

    // MARK: - Content

    private func content(_ response: StreakErasResponse) -> some View {
        let list = shortlist(response)
        let shown = showAll ? list.rows : Array(list.rows.prefix(collapsedCount))

        return VStack(spacing: MADTheme.Spacing.md) {
            header(list)
            recordBanner(response)

            VStack(spacing: 6) {
                ForEach(shown) { item in
                    streakRow(item, recordLength: response.longest_streak)
                }
            }

            if list.rows.count > collapsedCount {
                Button {
                    MADHaptics.tap()
                    withAnimation(MADTheme.Animation.quick) { showAll.toggle() }
                } label: {
                    Text(showAll ? "Show less" : "Show all \(list.rows.count)")
                        .font(MADTheme.Typography.smallBold)
                        .foregroundColor(MADTheme.Colors.madRed)
                }
                .buttonStyle(.plain)
            }

            // Replaces the old "+25 short runs" tile, which sat at the end of
            // the row looking like a card you could tap and told the user
            // nothing they wanted to know. A total is a fact worth having —
            // and once we start hiding rows it's also what keeps the section
            // honest about the history it isn't showing.
            Text(summaryLine(list))
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private func header(_ list: Shortlist) -> some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MADTheme.Colors.redGradient)
            Text("Hall of Streaks")
                .font(MADTheme.Typography.headline)
                .foregroundColor(.primary)
            Spacer()
            // Says WHY short runs are missing, in three characters. Without it
            // a user who knows they have a dozen 2-day streaks just sees them
            // gone and assumes the section is broken.
            if list.minLength > 2, list.isTrimmed {
                Text("\(list.minLength)+ days")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
        }
    }

    private func summaryLine(_ list: Shortlist) -> String {
        let streakWord = list.totalStreaks == 1 ? "streak" : "streaks"
        let dayWord = list.totalDays == 1 ? "day" : "days"
        let totals =
            "\(list.totalStreaks) \(streakWord) · \(list.totalDays) \(dayWord) with a mile in the bank"
        // When rows were held back, lead with the fact that they exist. The
        // totals then read as the full picture rather than as a contradiction
        // of a list that shows ten.
        guard list.isTrimmed else { return totals }
        return "Showing your longest \(list.rows.count) · \(totals) all time"
    }

    // MARK: - Record banner

    private func recordBanner(_ response: StreakErasResponse) -> some View {
        let live = response.current_is_longest
        let recordEra = response.eras.first(where: { $0.length == response.longest_streak })

        return HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(gold.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "crown.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(gold)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(live ? "Longest ever — and still going" : "Longest ever")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                HStack(spacing: 6) {
                    Text("\(response.longest_streak) days")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                    if let recordEra, !live {
                        Text(rangeText(recordEra))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }

            Spacer(minLength: 0)

            if live {
                Image(systemName: "flame.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(gold)
            }
        }
        .padding(MADTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(gold.opacity(live ? 0.10 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(gold.opacity(live ? 0.4 : 0.18), lineWidth: 1)
                )
        )
    }

    // MARK: - Rows

    private func streakRow(_ item: RankedStreak, recordLength: Int) -> some View {
        let era = item.era
        let isRecord = era.length >= recordLength && recordLength > 0
        let accent: Color = era.is_current ? MADTheme.Colors.madRed : (isRecord ? gold : .secondary)

        return HStack(spacing: MADTheme.Spacing.sm) {
            // Rank means something: #1 IS the record. Contrast with "ERA 27",
            // which was a position in a list nobody sees.
            Text("\(item.rank)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(isRecord ? gold : .secondary)
                .frame(width: 22, alignment: .center)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(era.length)")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                Text(era.length == 1 ? "day" : "days")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .frame(width: 74, alignment: .leading)

            Text(era.is_current ? "\(startText(era)) – now" : rangeText(era))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            if era.is_current {
                tag("NOW", color: MADTheme.Colors.madRed)
            } else if isRecord {
                tag("RECORD", color: gold)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(era.is_current || isRecord ? 0.08 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            accent.opacity(era.is_current || isRecord ? 0.35 : 0.10),
                            lineWidth: 1
                        )
                )
        )
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black, design: .rounded))
            .tracking(0.8)
            .foregroundColor(color)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    // MARK: - Date formatting

    /// `local_date` is a CALENDAR DATE, not an instant — "2026-08-01" means
    /// that day in the user's own timezone, and the server already did that
    /// resolution. So both formatters pin to UTC: parse at UTC midnight, print
    /// at UTC.
    ///
    /// Printing in the DEVICE timezone (which is what a bare DateFormatter
    /// does) rewinds UTC midnight into the previous evening for every zone west
    /// of Greenwich, so every date in this section rendered ONE DAY EARLY
    /// across the Americas: a streak that really ran Jul 23 – Aug 1 was shown
    /// as "Jul 22 – Jul 31", which then contradicted the week chart and made a
    /// perfectly correct Save Streak offer look like it was lying.
    private static let apiFormat: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private static let dayFormat: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private static let dayYearFormat: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private func display(_ dateStr: String, includeYear: Bool) -> String {
        guard let date = Self.apiFormat.date(from: dateStr) else { return dateStr }
        return (includeYear ? Self.dayYearFormat : Self.dayFormat).string(from: date)
    }

    private func startText(_ era: StreakEraAPI) -> String {
        display(era.start_date, includeYear: false)
    }

    private func rangeText(_ era: StreakEraAPI) -> String {
        let currentYear = Calendar.current.component(.year, from: Date())
        let eraYear = Int(era.end_date.prefix(4)) ?? currentYear
        let includeYear = eraYear != currentYear
        if era.start_date == era.end_date {
            return display(era.start_date, includeYear: includeYear)
        }
        return "\(display(era.start_date, includeYear: false)) – \(display(era.end_date, includeYear: includeYear))"
    }
}

#Preview {
    HallOfStreaksSection(userId: "preview", isSelf: true)
        .padding()
        .background(Color.black)
}
