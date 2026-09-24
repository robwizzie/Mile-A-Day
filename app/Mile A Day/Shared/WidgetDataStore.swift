import Foundation
import WidgetKit
import AppIntents

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

        // The server's DAILY_GOAL_TOLERANCE, restated because this file is
        // compiled into the widget extension, which can't see
        // ProgressCalculator. A raw `>=` drew "streak at risk" on the home
        // screen for a 0.97 mi day the app and the server both count as done.
        let isCompleted = todayMiles >= safeGoal * 0.95

        // Skip no-op writes: every save triggers widget timeline reloads, and
        // iOS rations those per day — burning the budget on unchanged values
        // means real updates later in the day get silently dropped. The
        // completed flag is part of the comparison so a stored day whose miles
        // didn't move still picks up a change in how it is judged.
        if defaults.double(forKey: milesKey) == todayMiles,
           defaults.double(forKey: goalKey) == safeGoal,
           defaults.bool(forKey: "streak_completed_today") == isCompleted,
           defaults.string(forKey: dataDayKey) == stamp {
            return
        }

        // Calculate progress and cap at 100%
        let progress = min(todayMiles / safeGoal, 1.0)

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

    /// True only when today's progress snapshot was written TODAY. `load()`
    /// answers a stale (or never-written) day with zeros, which is right for a
    /// ring but wrong for a sentence: "you're at 0.00 today" is a claim, and
    /// the "How far today?" intent must say "open the app to refresh" instead
    /// of making it.
    static func hasProgressForToday() -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return false }
        return defaults.string(forKey: dataDayKey) == dayStamp()
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

    private static let longestStreakKey = "longest_streak"

    /// All-time-best streak, so the flame widget can crown the streak box the
    /// same way the dashboard hero does.
    ///
    /// Deliberately does NOT reload any timeline: it only ever changes on a day
    /// the streak itself changed, and `save(streak:)` — always called alongside
    /// it — reloads for both. Spending a second reload here would buy nothing
    /// and widget reloads are rationed per day.
    static func save(longestStreak: Int) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        guard defaults.integer(forKey: longestStreakKey) != longestStreak else { return }
        defaults.set(longestStreak, forKey: longestStreakKey)
    }

    static func loadLongestStreak() -> Int {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return 0 }
        return defaults.integer(forKey: longestStreakKey)
    }

    // MARK: - Steps (flame widget stat row)

    private static let stepsKey = "today_steps"
    private static let stepsDayKey = "today_steps_day"

    /// Re-render the flame widget once per this many steps.
    ///
    /// The STORED value is always exact — this only rations how often the
    /// widget rebuilds. Steps climb all day, and iOS caps widget reloads per
    /// day and drops every reload for a kind that goes over (the app's own
    /// included, which freezes the widget while the app stays right). Reloading
    /// on each new step count would spend the whole budget on this one row.
    private static let stepsReloadBucket = 1000

    /// Today's step count for the flame widget's stat row.
    ///
    /// Monotonic within the day: `HealthKitManager.todaysSteps` is set to 0
    /// when its query FAILS (a locked device — protected data), and a real step
    /// count never goes down, so a zero after a real reading is always a bad
    /// read. Taking it would blank the widget's row at random.
    static func save(todaySteps: Int) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let stamp = dayStamp()
        let isNewDay = defaults.string(forKey: stepsDayKey) != stamp
        let previous = isNewDay ? 0 : defaults.integer(forKey: stepsKey)
        let steps = isNewDay ? max(0, todaySteps) : max(previous, todaySteps)

        // A new day always writes (yesterday's count has to clear) — otherwise
        // only a real change is worth touching disk.
        guard isNewDay || steps != previous else { return }
        defaults.set(steps, forKey: stepsKey)
        defaults.set(stamp, forKey: stepsDayKey)

        // In-between values ride along on the next miles/streak write or the
        // foreground full reload, so the row is never more than a bucket stale.
        let crossedBucket = steps / stepsReloadBucket != previous / stepsReloadBucket
        guard isNewDay || crossedBucket else { return }
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "StreakFlameWidget")
        }
    }

    /// Zero on a stale day, like `load()` does for miles.
    static func loadTodaySteps() -> Int {
        guard let defaults = UserDefaults(suiteName: suiteName),
              defaults.string(forKey: stepsDayKey) == dayStamp() else { return 0 }
        return defaults.integer(forKey: stepsKey)
    }

    // MARK: - Recovery

    private static let lastForcedReloadKey = "last_forced_widget_reload"

    /// Rebuild every MAD widget, at most once per `minimumInterval`.
    ///
    /// The per-value saves above deliberately skip no-op writes, which means a
    /// widget whose *rendered timeline* has drifted — a reload iOS dropped, a
    /// background sync that never ran — never recovers on its own, because the
    /// stored values it would be rebuilt from are already correct. This is the
    /// escape hatch: cheap, throttled, and called when the user brings the app
    /// forward, which is exactly when a wrong widget has just been noticed.
    static func requestFullReload(minimumInterval: TimeInterval = 900) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let now = Date()
        if let last = defaults.object(forKey: lastForcedReloadKey) as? Date,
           now.timeIntervalSince(last) < minimumInterval {
            return
        }
        defaults.set(now, forKey: lastForcedReloadKey)
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadAllTimelines()
        }
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

    // MARK: - Flamey's wardrobe facts (streak flame widget, Fun style)

    private static let flameyBadgesKey = "flamey_badge_ids"
    private static let flameySignupKey = "flamey_signup_epoch"

    /// The durable facts the flame widget resolves Flamey's look from
    /// (`FlameyLook.resolve`, per timeline entry, so a holiday outfit goes on
    /// at midnight with no reload). The longest streak rides `longest_streak`.
    /// Only the catalog's badge ids are stored. The caller decides `reload`
    /// — it's true only when what he'd wear today or tomorrow changed, so
    /// badge churn that changes nothing on him costs no reload budget.
    static func save(flameyBadgeIds: [String], signupDate: Date?, reload: Bool) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let sorted = flameyBadgeIds.sorted()
        let epoch = signupDate?.timeIntervalSince1970 ?? 0
        let unchanged = (defaults.stringArray(forKey: flameyBadgesKey) ?? []) == sorted
            && defaults.double(forKey: flameySignupKey) == epoch
        if !unchanged {
            defaults.set(sorted, forKey: flameyBadgesKey)
            defaults.set(epoch, forKey: flameySignupKey)
        }
        guard reload else { return }
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "StreakFlameWidget")
        }
    }

    static func loadFlameyBadgeIds() -> Set<String> {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return [] }
        return Set(defaults.stringArray(forKey: flameyBadgesKey) ?? [])
    }

    static func loadFlameySignupDate() -> Date? {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        let epoch = defaults.double(forKey: flameySignupKey)
        return epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
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

    /// Returns whether anything was written (and the widget reloaded).
    @discardableResult
    static func save(
        competitionId: String,
        competitionName: String,
        pill: String,
        detail: String,
        rankText: String,
        urgency: String,
        standings: [StandingRow] = []
    ) -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return false }
        let stamp = dayStamp()
        let standingsData = (try? JSONEncoder().encode(standings)) ?? Data()
        if defaults.string(forKey: compIdKey) == competitionId,
           defaults.string(forKey: compNameKey) == competitionName,
           defaults.string(forKey: compPillKey) == pill,
           defaults.string(forKey: compDetailKey) == detail,
           defaults.string(forKey: compRankKey) == rankText,
           defaults.data(forKey: compStandingsKey) == standingsData,
           defaults.string(forKey: compStampKey) == stamp {
            return false
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
        return true
    }

    @discardableResult
    static func clearCompetitionSummary() -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName),
              defaults.string(forKey: compNameKey) != nil else { return false }
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
        return true
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
    /// Returns whether anything was written (and the widget reloaded).
    @discardableResult
    static func save(leaderboardRows: [LeaderboardRow]) -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(leaderboardRows) else { return false }
        let stamp = dayStamp()
        if defaults.data(forKey: leaderboardRowsKey) == data,
           defaults.string(forKey: leaderboardStampKey) == stamp {
            return false
        }
        defaults.set(data, forKey: leaderboardRowsKey)
        defaults.set(stamp, forKey: leaderboardStampKey)
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: "DailyLeaderboardWidget")
        }
        return true
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

// MARK: - Start My Mile (shared by the app AND the widget extension)
//
// This lives in this file on purpose: it is the one source file that is
// already a member of BOTH the app and the widget extension, and a control
// that opens the app (the Control Center "Start My Mile" button) needs its
// intent compiled into both — the extension to declare it, the app to run it
// (`openAppWhenRun` intents perform in the APP's process). A new file would
// join the app target only; extension membership is a pbxproj edit. Keep this
// block dependency-free (Foundation + AppIntents): the extension can't see
// anything else in the app.

/// Walk or run, as Siri, Shortcuts and the Action Button name it.
enum MileActivityOption: String, AppEnum {
    case walk
    case run

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Activity")
    }

    static var caseDisplayRepresentations: [MileActivityOption: DisplayRepresentation] {
        [
            .walk: DisplayRepresentation(title: "Walk"),
            .run: DisplayRepresentation(title: "Run")
        ]
    }
}

/// The hand-off from the intent to the app's own routing. The intent can't
/// reach `DeepLinkRouter` (the extension compiles this file too), so the app
/// installs `handler` at launch; a request that arrives before that is parked
/// and delivered on install.
@MainActor
enum StartMileLaunch {
    struct Request {
        let activity: MileActivityOption?
    }

    private static var parked: Request?

    static var handler: ((Request) -> Void)? {
        didSet {
            guard let handler, let request = parked else { return }
            parked = nil
            handler(request)
        }
    }

    static func request(activity: MileActivityOption?) {
        let request = Request(activity: activity)
        if let handler {
            handler(request)
        } else {
            parked = request
        }
    }
}

/// "Start my mile": opens the app on the workout tracker. It never starts a
/// second workout — the app reopens one already in progress instead (see
/// `DeepLinkRouter.requestOpenTracker`).
struct StartMileIntent: AppIntent {
    static var title: LocalizedStringResource { "Start My Mile" }

    static var description: IntentDescription {
        IntentDescription(
            "Opens Mile A Day to the workout tracker. If a workout is already in progress, it reopens that workout instead of starting another."
        )
    }

    static var openAppWhenRun: Bool { true }

    @Parameter(
        title: "Activity",
        description: "Walk or run. Leave empty to use the one you last tracked."
    )
    var activity: MileActivityOption?

    static var parameterSummary: some ParameterSummary {
        Summary("Start my mile as a \(\.$activity)")
    }

    init() {}

    init(activity: MileActivityOption?) {
        self.activity = activity
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        StartMileLaunch.request(activity: activity)
        return .result()
    }
}
