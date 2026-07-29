//
//  HallOfStreaksSection.swift
//  Mile A Day
//
//  "Eras" view of a user's streak history: every past run of 3+ days as a
//  card, the current run highlighted, the record celebrated. Reframes a
//  broken streak from "lost everything" into "chapter two". Self-contained —
//  owns its fetch, parents drop it in with a user id (works for self AND
//  friend profiles; the endpoint authorizes like /stats).
//

import SwiftUI

struct HallOfStreaksSection: View {
    let userId: String?
    let isSelf: Bool

    @State private var response: StreakErasResponse?

    private let workoutService = WorkoutService()
    private let gold = Color(red: 1.0, green: 0.78, blue: 0.25)

    var body: some View {
        Group {
            if let response, !visibleEras(response).isEmpty {
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

    // MARK: - Content

    /// Eras worth a card: 3+ days, or the current run at any length. Newest
    /// first (API order), capped so a years-long history doesn't scroll forever.
    private func visibleEras(_ response: StreakErasResponse) -> [StreakEraAPI] {
        Array(response.eras.filter { $0.length >= 3 || $0.is_current }.prefix(12))
    }

    private func content(_ response: StreakErasResponse) -> some View {
        let visible = visibleEras(response)
        let shortRuns = response.eras.count - visible.count
        let recordLength = response.longest_streak

        return VStack(spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("Hall of Streaks")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
                Spacer()
            }

            recordBanner(response)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(visible) { era in
                        eraCard(
                            era: era,
                            number: eraNumber(of: era, in: response),
                            isRecord: era.length >= recordLength && recordLength > 0
                        )
                    }
                    if shortRuns > 0 {
                        shortRunsPill(shortRuns)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    /// Chronological era number (Era 1 = the first ever) — eras arrive newest
    /// first, so number = position from the END of the full list.
    private func eraNumber(of era: StreakEraAPI, in response: StreakErasResponse) -> Int {
        guard let index = response.eras.firstIndex(where: { $0.id == era.id }) else { return 1 }
        return response.eras.count - index
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
                Text("Longest streak")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    Text("\(response.longest_streak) days")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                    if let recordEra, !live {
                        Text(rangeText(recordEra))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if live {
                Text("HAPPENING NOW")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.1)
                    .foregroundColor(.black.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(gold))
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

    // MARK: - Era cards

    private func eraCard(era: StreakEraAPI, number: Int, isRecord: Bool) -> some View {
        let accent: Color = era.is_current ? MADTheme.Colors.madRed : (isRecord ? gold : .secondary)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("ERA \(number)")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.secondary)
                if isRecord {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(gold)
                }
                Spacer(minLength: 0)
                if era.is_current {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(MADTheme.Colors.madRed)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(era.length)")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                Text(era.length == 1 ? "day" : "days")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Text(era.is_current ? "\(startText(era)) – now" : rangeText(era))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if era.is_current {
                Text("CURRENT")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(1.0)
                    .foregroundColor(MADTheme.Colors.madRed)
            }
        }
        .padding(10)
        .frame(width: 124, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(era.is_current || isRecord ? 0.08 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            accent.opacity(era.is_current || isRecord ? 0.45 : 0.15),
                            lineWidth: era.is_current ? 1.5 : 1
                        )
                )
        )
    }

    private func shortRunsPill(_ count: Int) -> some View {
        VStack(spacing: 4) {
            Text("+\(count)")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.secondary)
            Text(count == 1 ? "short run" : "short runs")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(width: 84, height: 96)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            Color.secondary.opacity(0.15),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                )
        )
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
