import Foundation

/// Local record of the days the user's HealthKit steps reached the daily step
/// goal (`ProgressCalculator.dailyStepGoal`, 10,000).
///
/// "1 mile OR 10,000 steps" completes a day, on the server and here. A
/// steps-only day has NO workout, so — exactly like a token-covered day
/// (`StreakCoverageStore`) — every local streak walk unions these keys into
/// its "day counts" set; without them the phone's walk would break at the
/// day and fight the server's (tripping the `vettedHealthKitStreak`
/// quarantine and its daily index rebuild).
///
/// Filled by `DailyStepsSyncService`: today's key the moment today's count
/// crosses the goal, and the whole history from one HealthKit statistics
/// query (`refreshStepGoalHistory`). iPhone only: the Watch shows the phone's
/// streak, so every reference from a file the Watch also compiles sits behind
/// `#if !os(watchOS)`.
enum StepGoalDayStore {
    private static let daysKey = "stepGoalDayKeysV1"

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    /// "yyyy-MM-dd" for a date in the device's current calendar day — the
    /// WorkoutIndex key format and the server's `local_date`.
    static func dayKey(for date: Date) -> String {
        dayFormatter.timeZone = TimeZone.current
        return dayFormatter.string(from: date)
    }

    /// Goal-met local days ("yyyy-MM-dd").
    static var goalDayKeys: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: daysKey) ?? [])
    }

    /// Goal-met days as start-of-day Dates, for the walks keyed by Date.
    static var goalDays: Set<Date> {
        let calendar = Calendar.current
        dayFormatter.timeZone = TimeZone.current
        return Set(goalDayKeys.compactMap { key in
            dayFormatter.date(from: key).map { calendar.startOfDay(for: $0) }
        })
    }

    /// Did today's steps already reach the goal? Read from the day-keyed store
    /// only — never from `HealthKitManager.todaysSteps`, which carries no day
    /// and still holds yesterday's count until the first read after midnight.
    /// Every successful today read records here (`fetchTodaysSteps`, the step
    /// observer), so the key lands the moment the count crosses.
    static func isTodayMet(now: Date = Date()) -> Bool {
        goalDayKeys.contains(dayKey(for: now))
    }

    /// Record one day's total. Only ever ADDS a key: a step count never goes
    /// down within a day, so a lower reading is a partial or failed read, not
    /// a reason to forget the day. Returns true when the day is new.
    @discardableResult
    static func record(steps: Int, on date: Date) -> Bool {
        guard steps >= ProgressCalculator.dailyStepGoal else { return false }
        var keys = goalDayKeys
        let inserted = keys.insert(dayKey(for: date)).inserted
        if inserted { save(keys) }
        return inserted
    }

    /// Merge a history read (day key → total steps). Additive for the same
    /// reason as `record`. Returns the keys that were new.
    @discardableResult
    static func merge(history: [String: Int]) -> Set<String> {
        var keys = goalDayKeys
        var added: Set<String> = []
        for (key, steps) in history where steps >= ProgressCalculator.dailyStepGoal {
            if keys.insert(key).inserted { added.insert(key) }
        }
        if !added.isEmpty { save(keys) }
        return added
    }

    // No sign-out clear: the days are read from THIS phone's Health data,
    // which doesn't change with the account. What is per account — whether
    // the history has reached the server — is keyed by user id in
    // DailyStepsSyncService.

    private static func save(_ keys: Set<String>) {
        UserDefaults.standard.set(Array(keys).sorted(), forKey: daysKey)
    }
}
