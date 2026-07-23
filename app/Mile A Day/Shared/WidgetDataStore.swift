import Foundation
import WidgetKit

struct WidgetDataStore {
    private static let suiteName = "group.mileaday.shared"
    private static let milesKey = "today_miles_completed"
    private static let goalKey = "daily_goal"
    private static let streakKey = "streak_count"
    private static let dataDayKey = "widget_data_day"
    private static let dashboardStyleKey = "dashboard_style"

    /// Day stamp (device-local calendar day) for the saved progress values.
    /// Lets `load()` detect data written on a previous day so widgets show a
    /// fresh 0-mile day after midnight instead of yesterday's run.
    private static func dayStamp(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Saves today's progress data
    /// Ensures progress never exceeds 100% and maintains accurate sync
    static func save(todayMiles: Double, goal: Double) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }

        // Ensure goal is never 0
        let safeGoal = goal > 0 ? goal : 1.0
        let stamp = dayStamp()

        // Skip no-op writes: every save triggers widget timeline reloads, and
        // iOS rations those per day — burning the budget on unchanged values
        // means real updates later in the day get silently dropped.
        if defaults.double(forKey: milesKey) == todayMiles,
           defaults.double(forKey: goalKey) == safeGoal,
           defaults.string(forKey: dataDayKey) == stamp {
            return
        }

        // Calculate progress and cap at 100%
        let progress = min(todayMiles / safeGoal, 1.0)
        let isCompleted = todayMiles >= safeGoal

        // Save all values with proper synchronization
        defaults.set(todayMiles, forKey: milesKey)
        defaults.set(safeGoal, forKey: goalKey)
        defaults.set(isCompleted, forKey: "streak_completed_today")
        defaults.set(todayMiles, forKey: "total_current_distance")
        defaults.set(progress, forKey: "current_progress")
        defaults.set(stamp, forKey: dataDayKey)

        // Force synchronization to disk
        defaults.synchronize()

        // Reload both widget kinds — the streak widget renders the same
        // progress/completed values, so reloading only the progress widget
        // left the two disagreeing for up to an hour.
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "TodayProgressWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "StreakCountWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "StreakFlameWidget")
        }
    }

    /// Loads today's progress data
    static func load() -> (miles: Double, goal: Double, streakCompleted: Bool, progress: Double) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return (0, 1, false, 0)
        }

        let goal = defaults.double(forKey: goalKey) == 0 ? 1 : defaults.double(forKey: goalKey)

        // Saved values are from a previous day — surface a fresh, empty day
        // (keeping the goal) rather than yesterday's miles/completion state.
        if let storedDay = defaults.string(forKey: dataDayKey), storedDay != dayStamp() {
            return (0, goal, false, 0)
        }

        let miles = defaults.double(forKey: milesKey)
        let streakCompleted = defaults.bool(forKey: "streak_completed_today")
        let progress = defaults.double(forKey: "current_progress")

        return (miles, goal, streakCompleted, progress)
    }

    // MARK: - Streak helpers
    static func save(streak: Int) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }

        // Skip no-op writes — see save(todayMiles:goal:).
        if defaults.integer(forKey: streakKey) == streak {
            return
        }

        defaults.set(streak, forKey: streakKey)
        defaults.synchronize()

        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "StreakCountWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "StreakFlameWidget")
        }
    }

    static func loadStreak() -> Int {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return 0
        }
        return defaults.integer(forKey: streakKey)
    }

    // MARK: - Dashboard style (streak flame widget)

    /// Mirrors the user's chosen dashboard style ("fun" / "modern") into the
    /// App Group so the Streak Flame widget can match it. The style itself
    /// lives in `UserDefaults.standard` (app-process only); the widget process
    /// can only see the shared suite, so it must be copied here.
    static func save(dashboardStyle: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        // Skip no-op writes — see save(todayMiles:goal:).
        if defaults.string(forKey: dashboardStyleKey) == dashboardStyle { return }
        defaults.set(dashboardStyle, forKey: dashboardStyleKey)
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "StreakFlameWidget")
        }
    }

    /// Defaults to "modern" to match `DashboardStylePreference.current`.
    static func loadDashboardStyle() -> String {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return "modern" }
        return defaults.string(forKey: dashboardStyleKey) ?? "modern"
    }

    // MARK: - Streak tokens (streak widget accessory)

    private static let tokensReadyKey = "tokens_ready"

    /// Count of streak tokens currently HELD (0–3), mirrored from the gated
    /// token payload. Not day-stamped — held tokens persist until spent.
    /// Absent/zero simply hides the widget's token pill, so installs without
    /// the feature render exactly as before.
    static func save(tokensReady: Int) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        // Skip no-op writes — see save(todayMiles:goal:).
        if defaults.integer(forKey: tokensReadyKey) == tokensReady { return }
        defaults.set(tokensReady, forKey: tokensReadyKey)
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "StreakCountWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "StreakFlameWidget")
        }
    }

    static func loadTokensReady() -> Int {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return 0 }
        return defaults.integer(forKey: tokensReadyKey)
    }

    // MARK: - Week completions (medium streak widget)

    private static let weekCompletionsKey = "week_completions"
    private static let weekStampKey = "week_completions_week"
    private static let weekMilesKey = "week_miles"

    /// Stamp identifying the current week (its Sunday's day stamp), so data
    /// from a previous week reads as empty instead of wrong.
    private static func weekStamp(for date: Date = Date()) -> String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: calendar.startOfDay(for: date)) ?? date
        return dayStamp(for: sunday)
    }

    /// Saves Sun–Sat goal-completion flags for the current week, plus the
    /// week's total miles for the streak widget's status line.
    static func save(weekCompletions: [Bool], weekMiles: Double = 0) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let stamp = weekStamp()
        let previous = defaults.array(forKey: weekCompletionsKey) as? [Bool]
        if previous == weekCompletions,
           defaults.double(forKey: weekMilesKey) == weekMiles,
           defaults.string(forKey: weekStampKey) == stamp {
            return
        }
        defaults.set(weekCompletions, forKey: weekCompletionsKey)
        defaults.set(weekMiles, forKey: weekMilesKey)
        defaults.set(stamp, forKey: weekStampKey)
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "StreakCountWidget")
        }
    }

    static func loadWeekCompletions() -> [Bool] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              defaults.string(forKey: weekStampKey) == weekStamp(),
              let stored = defaults.array(forKey: weekCompletionsKey) as? [Bool] else {
            return []
        }
        return stored
    }

    static func loadWeekMiles() -> Double {
        guard let defaults = UserDefaults(suiteName: suiteName),
              defaults.string(forKey: weekStampKey) == weekStamp() else {
            return 0
        }
        return defaults.double(forKey: weekMilesKey)
    }

    // MARK: - Competition summary (competition widget)

    private static let compIdKey = "comp_id"
    private static let compNameKey = "comp_name"
    private static let compPillKey = "comp_pill"
    private static let compDetailKey = "comp_detail"
    private static let compRankKey = "comp_rank"
    private static let compUrgencyKey = "comp_urgency"
    private static let compStampKey = "comp_day"
    private static let compStandingsKey = "comp_standings"

    /// One standings row for the competition widget's mini-leaderboard.
    struct StandingRow: Codable {
        let name: String
        let valueText: String
        let isMe: Bool
    }

    struct CompetitionSummary {
        let id: String
        let name: String
        let pill: String
        let detail: String
        let rankText: String
        let urgency: String   // "urgent" | "behind" | "neutral" | "winning"
        let isStale: Bool     // saved on a previous day
        /// Ranked top players (me included) — empty when written by an older
        /// app build; the widget falls back to the detail line.
        var standings: [StandingRow] = []
    }

    static func save(
        competitionId: String,
        competitionName: String,
        pill: String,
        detail: String,
        rankText: String,
        urgency: String,
        standings: [StandingRow] = []
    ) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let stamp = dayStamp()
        let standingsData = (try? JSONEncoder().encode(standings)) ?? Data()
        if defaults.string(forKey: compIdKey) == competitionId,
           defaults.string(forKey: compNameKey) == competitionName,
           defaults.string(forKey: compPillKey) == pill,
           defaults.string(forKey: compDetailKey) == detail,
           defaults.string(forKey: compRankKey) == rankText,
           defaults.data(forKey: compStandingsKey) == standingsData,
           defaults.string(forKey: compStampKey) == stamp {
            return
        }
        defaults.set(competitionId, forKey: compIdKey)
        defaults.set(competitionName, forKey: compNameKey)
        defaults.set(pill, forKey: compPillKey)
        defaults.set(detail, forKey: compDetailKey)
        defaults.set(rankText, forKey: compRankKey)
        defaults.set(urgency, forKey: compUrgencyKey)
        defaults.set(standingsData, forKey: compStandingsKey)
        defaults.set(stamp, forKey: compStampKey)
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "CompetitionWidget")
        }
    }

    static func clearCompetitionSummary() {
        guard let defaults = UserDefaults(suiteName: suiteName),
              defaults.string(forKey: compNameKey) != nil else { return }
        defaults.removeObject(forKey: compIdKey)
        defaults.removeObject(forKey: compNameKey)
        defaults.removeObject(forKey: compPillKey)
        defaults.removeObject(forKey: compDetailKey)
        defaults.removeObject(forKey: compRankKey)
        defaults.removeObject(forKey: compUrgencyKey)
        defaults.removeObject(forKey: compStandingsKey)
        defaults.removeObject(forKey: compStampKey)
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "CompetitionWidget")
        }
    }

    static func loadCompetitionSummary() -> CompetitionSummary? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let name = defaults.string(forKey: compNameKey) else {
            return nil
        }
        let standings = defaults.data(forKey: compStandingsKey)
            .flatMap { try? JSONDecoder().decode([StandingRow].self, from: $0) } ?? []
        return CompetitionSummary(
            id: defaults.string(forKey: compIdKey) ?? "",
            name: name,
            pill: defaults.string(forKey: compPillKey) ?? "",
            detail: defaults.string(forKey: compDetailKey) ?? "",
            rankText: defaults.string(forKey: compRankKey) ?? "",
            urgency: defaults.string(forKey: compUrgencyKey) ?? "neutral",
            isStale: defaults.string(forKey: compStampKey) != dayStamp(),
            standings: standings
        )
    }

    // MARK: - Daily leaderboard (leaderboard widget)

    private static let leaderboardRowsKey = "daily_leaderboard_rows"
    private static let leaderboardStampKey = "daily_leaderboard_day"

    /// One ranked row of today's friends leaderboard (me included).
    struct LeaderboardRow: Codable {
        let name: String
        let miles: Double
        let isMe: Bool
        let completed: Bool
    }

    struct LeaderboardSnapshot {
        let rows: [LeaderboardRow]   // already sorted by miles, descending
        let isStale: Bool            // saved on a previous day
    }

    /// Saves today's friends leaderboard for the Daily Leaderboard widget.
    static func save(leaderboardRows: [LeaderboardRow]) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(leaderboardRows) else { return }
        let stamp = dayStamp()
        if defaults.data(forKey: leaderboardRowsKey) == data,
           defaults.string(forKey: leaderboardStampKey) == stamp {
            return
        }
        defaults.set(data, forKey: leaderboardRowsKey)
        defaults.set(stamp, forKey: leaderboardStampKey)
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "DailyLeaderboardWidget")
        }
    }

    static func loadLeaderboard() -> LeaderboardSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: leaderboardRowsKey),
              let rows = try? JSONDecoder().decode([LeaderboardRow].self, from: data),
              !rows.isEmpty else {
            return nil
        }
        return LeaderboardSnapshot(
            rows: rows,
            isStale: defaults.string(forKey: leaderboardStampKey) != dayStamp()
        )
    }
}
