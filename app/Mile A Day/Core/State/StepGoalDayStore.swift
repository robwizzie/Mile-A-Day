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
/// Filled by `DailyStepsSyncService` and `fetchTodaysSteps`: today's key the
/// moment a read of today crosses the goal, and the whole history from one
/// HealthKit statistics query (`syncStepGoalHistory`). iPhone only: the Watch
/// shows the phone's streak, so every reference from a file the Watch also
/// compiles sits behind `#if !os(watchOS)`.
enum StepGoalDayStore {
    private static let daysKey = "stepGoalDayKeysV1"

    /// `record` runs on main (today's foreground read) while `merge` runs off
    /// it (the history sync): each is a read-modify-write of one array, so
    /// unguarded they can drop each other's days.
    private static let lock = NSLock()

    /// The key for a date's local day — `DayKeyFormatter`, the WorkoutIndex's
    /// own key format (current calendar and time zone, POSIX digits), so a
    /// step day lines up with the index's days in every calendar. NOT the
    /// server's `local_date`, which is always Gregorian: see
    /// `DailyStepsSyncService.localDateString`.
    static func dayKey(for date: Date) -> String {
        DayKeyFormatter.string(from: date)
    }

    /// Goal-met local days.
    static var goalDayKeys: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: daysKey) ?? [])
    }

    /// Goal-met days as start-of-day Dates, for the walks keyed by Date.
    static var goalDays: Set<Date> {
        let calendar = Calendar.current
        return Set(goalDayKeys.compactMap { key in
            DayKeyFormatter.date(from: key).map { calendar.startOfDay(for: $0) }
        })
    }

    /// Did today's steps already reach the goal? Read from the day-keyed store
    /// only — never from `HealthKitManager.todaysSteps`, which carries no day
    /// and still holds yesterday's count until the first read after midnight.
    /// Every successful read of today records here (`fetchTodaysSteps`, the
    /// step observer), so the key lands the moment the count crosses.
    static func isTodayMet(now: Date = Date()) -> Bool {
        goalDayKeys.contains(dayKey(for: now))
    }

    /// Record one day's total, read for that day. Only ever ADDS a key: a
    /// step count never goes down within a day, so a lower reading is a
    /// partial or failed read, not a reason to forget the day. Returns true
    /// when the day is new.
    @discardableResult
    static func record(steps: Int, on date: Date) -> Bool {
        guard steps >= ProgressCalculator.dailyStepGoal else { return false }
        let key = dayKey(for: date)
        lock.lock()
        var keys = goalDayKeys
        let inserted = keys.insert(key).inserted
        if inserted { save(keys) }
        lock.unlock()
        if inserted { mirrorToWidgetsIfToday(key) }
        return inserted
    }

    /// Merge a history read (each day's start → its total steps). Additive
    /// for the same reason as `record`. Returns the keys that were new.
    @discardableResult
    static func merge(history: [Date: Int]) -> Set<String> {
        lock.lock()
        var keys = goalDayKeys
        var added: Set<String> = []
        for (day, steps) in history where steps >= ProgressCalculator.dailyStepGoal {
            let key = dayKey(for: day)
            if keys.insert(key).inserted { added.insert(key) }
        }
        if !added.isEmpty { save(keys) }
        lock.unlock()
        for key in added { mirrorToWidgetsIfToday(key) }
        return added
    }

    /// Re-assert today's goal to the widgets' app group (a no-op once it's
    /// there). The widget extension can't read this store, and its own step
    /// count has no trustworthy day, so it reads this flag instead.
    static func syncWidgetFlag() {
        if isTodayMet() { WidgetDataStore.saveStepGoalMetToday() }
    }

    // No sign-out clear: the days are read from THIS phone's Health data,
    // which doesn't change with the account. What is per account — whether
    // the history has reached the server — is keyed by user id in
    // DailyStepsSyncService.

    private static func mirrorToWidgetsIfToday(_ key: String) {
        if key == dayKey(for: Date()) { WidgetDataStore.saveStepGoalMetToday() }
    }

    private static func save(_ keys: Set<String>) {
        UserDefaults.standard.set(Array(keys).sorted(), forKey: daysKey)
    }
}
