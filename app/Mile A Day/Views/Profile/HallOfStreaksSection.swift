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

    var body: some View {
        Group {
            if let response, !ranked(response).isEmpty {
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

    /// Streaks worth a row, longest first. The CURRENT run always earns one
    /// even if it's short — "where does today's run stand" is the whole reason
    /// someone opens this — and it keeps its true rank rather than being
    /// pinned to the top, because being 9th is the honest, motivating answer.
    private func ranked(_ response: StreakErasResponse) -> [RankedStreak] {
        let sorted = response.eras.sorted { a, b in
            if a.length != b.length { return a.length > b.length }
            return a.end_date > b.end_date
        }
        let ranks = sorted.enumerated().map { RankedStreak(rank: $0.offset + 1, era: $0.element) }
        return ranks.filter { $0.era.length >= 2 || $0.era.is_current }
    }

    private struct RankedStreak: Identifiable {
        let rank: Int
        let era: StreakEraAPI
        var id: String { era.id }
    }

    // MARK: - Content

    private func content(_ response: StreakErasResponse) -> some View {
        let all = ranked(response)
        let shown = showAll ? all : Array(all.prefix(collapsedCount))
        let totalDays = response.eras.reduce(0) { $0 + $1.length }

        return VStack(spacing: MADTheme.Spacing.md) {
            header
            recordBanner(response)

            VStack(spacing: 6) {
                ForEach(shown) { item in
                    streakRow(item, recordLength: response.longest_streak)
                }
            }

            if all.count > collapsedCount {
                Button {
                    MADHaptics.tap()
                    withAnimation(MADTheme.Animation.quick) { showAll.toggle() }
                } label: {
                    Text(showAll ? "Show less" : "Show all \(all.count)")
                        .font(MADTheme.Typography.smallBold)
                        .foregroundColor(MADTheme.Colors.madRed)
                }
                .buttonStyle(.plain)
            }

            // Replaces the old "+25 short runs" tile, which sat at the end of
            // the row looking like a card you could tap and told the user
            // nothing they wanted to know. A total is a fact worth having.
            Text(summaryLine(streaks: response.eras.count, totalDays: totalDays))
                .font(MADTheme.Typography.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var header: some View {
        HStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MADTheme.Colors.redGradient)
            Text("Hall of Streaks")
                .font(MADTheme.Typography.headline)
                .foregroundColor(.primary)
            Spacer()
        }
    }

    private func summaryLine(streaks: Int, totalDays: Int) -> String {
        let streakWord = streaks == 1 ? "streak" : "streaks"
        let dayWord = totalDays == 1 ? "day" : "days"
        return "\(streaks) \(streakWord) · \(totalDays) \(dayWord) with a mile in the bank"
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

    private static let apiFormat: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private func display(_ dateStr: String, includeYear: Bool) -> String {
        guard let date = Self.apiFormat.date(from: dateStr) else { return dateStr }
        let fmt = DateFormatter()
        fmt.dateFormat = includeYear ? "MMM d, yyyy" : "MMM d"
        return fmt.string(from: date)
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
