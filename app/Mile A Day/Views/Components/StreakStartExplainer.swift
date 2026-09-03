//
//  StreakStartExplainer.swift
//  Mile A Day
//
//  "Why does my streak start there?"
//
//  A streak number on its own is unfalsifiable: someone who has genuinely run
//  every day since 2019 is shown 325 and has no way to find out whether that
//  is the app being wrong or a day they actually missed. The only honest
//  answer is the DATE — a streak begins the day after the last day with no
//  qualifying mile, so naming that day turns an argument into something the
//  user can check against their own memory.
//

import SwiftUI

/// Where the current streak begins, and what put it there.
///
/// Everything is derived from the eras the server already computes
/// (`StreakErasStore`); this view invents nothing. When the history hasn't
/// loaded it says so rather than guessing a date.
struct StreakStartExplainer: View {
    /// The streak being explained, so the copy matches the number on screen
    /// even if the store is a beat behind.
    let streak: Int

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var erasStore = StreakErasStore.shared
    @ObservedObject private var syncService = WorkoutSyncService.shared

    private var currentEra: StreakEraAPI? { erasStore.currentEra }
    private var previousEra: StreakEraAPI? { erasStore.previousEra }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        startCard
                        if syncService.isImportingHistory {
                            importingNotice
                        }
                        gapCard
                        rulesCard
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
            .navigationTitle("Your streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(MADTheme.Colors.madRed)
                }
            }
        }
        .task { await erasStore.refreshIfStale() }
    }

    // MARK: - Start

    private var startCard: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(MADTheme.Colors.redGradient)

            Text("This streak started")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.55))

            Text(StreakDateText.long(currentEra?.start_date) ?? "Still working it out")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)

            Text(startSubtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var startSubtitle: String {
        guard currentEra?.start_date != nil else {
            return "We couldn't load your streak history just now. Pull to refresh your profile and try again."
        }
        let days = currentEra?.length ?? streak
        return "You've logged a qualifying mile every day since then — \(days) day\(days == 1 ? "" : "s") in a row."
    }

    // MARK: - The gap that created it

    @ViewBuilder
    private var gapCard: some View {
        if let start = currentEra?.start_date {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                Text("Why not earlier?")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(gapExplanation(start: start))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                if let previousEra {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                        Text("Before it: \(previousEra.length) day\(previousEra.length == 1 ? "" : "s"), ending \(StreakDateText.long(previousEra.end_date) ?? previousEra.end_date)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MADTheme.Spacing.md)
            .madLiquidGlass()
        }
    }

    /// The day (or run of days) immediately before the streak, named.
    private func gapExplanation(start: String) -> String {
        let dayBefore = StreakDateText.long(StreakDateText.dayBefore(start))
        guard let previousEra else {
            guard let dayBefore else {
                return "A streak starts the day after the last day without a qualifying mile."
            }
            return "We have no qualifying mile for \(dayBefore) — that's the day your streak counts from. If this is your first history import, anything older simply isn't in Apple Health on this phone yet."
        }
        let missedDays = StreakDateText.dayCount(from: previousEra.end_date, to: start) - 1
        if missedDays <= 1, let dayBefore {
            return "There's no qualifying mile on \(dayBefore). One day without one is what ends a streak and starts the next, so everything before that date is counted separately."
        }
        let firstMissed = StreakDateText.long(StreakDateText.dayAfter(previousEra.end_date)) ?? ""
        let lastMissed = dayBefore ?? ""
        return "We have no qualifying miles between \(firstMissed) and \(lastMissed) — \(missedDays) days. Everything before that is counted as its own streak."
    }

    // MARK: - Notices

    private var importingNotice: some View {
        HStack(alignment: .top, spacing: MADTheme.Spacing.sm) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text("Still importing your history")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("This number can still grow. Older workouts are being read from Apple Health right now — keep the app open and check back when it finishes.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Text("What counts as a day")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            rule(
                icon: "figure.walk",
                text: "A walk or run in Apple Health that reaches your daily goal. Treadmill and indoor workouts count."
            )
            rule(
                icon: "calendar",
                text: "The day is decided by when the workout STARTED, in the timezone your phone was in. A run that begins at 11:50 PM belongs to that day, not the next one."
            )
            rule(
                icon: "arrow.triangle.branch",
                text: "The same run recorded by two apps counts once. Anything we set aside as a duplicate still shows on your profile, marked."
            )
            rule(
                icon: "iphone.gen3",
                text: "We can only see what's in Apple Health on this iPhone. History from an old phone that never synced isn't there — importing from Strava or Garmin brings it back."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private func rule(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: MADTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MADTheme.Colors.madRed)
                .frame(width: 20, height: 20)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Date helpers

/// `local_date` strings are CALENDAR DATES, not instants — "2026-08-01" means
/// that day where the user was, and the server already resolved it. Every
/// formatter here is pinned to UTC for exactly the reason HallOfStreaksSection
/// documents: printing UTC midnight in a device timezone west of Greenwich
/// rewinds it into the previous evening and shows every date one day early.
enum StreakDateText {
    static func long(_ dateStr: String?) -> String? {
        guard let dateStr, let date = api.date(from: dateStr) else { return nil }
        return longFormat.string(from: date)
    }

    static func dayBefore(_ dateStr: String) -> String? {
        shift(dateStr, by: -1)
    }

    static func dayAfter(_ dateStr: String) -> String? {
        shift(dateStr, by: 1)
    }

    /// Inclusive day count between two `yyyy-MM-dd` strings.
    static func dayCount(from: String, to: String) -> Int {
        guard let a = api.date(from: from), let b = api.date(from: to) else { return 0 }
        return utcCalendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    private static func shift(_ dateStr: String, by days: Int) -> String? {
        guard let date = api.date(from: dateStr),
              let moved = utcCalendar.date(byAdding: .day, value: days, to: date)
        else { return nil }
        return api.string(from: moved)
    }

    private static var utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal
    }()

    private static let api: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let longFormat: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()
}

#Preview {
    StreakStartExplainer(streak: 165)
}
