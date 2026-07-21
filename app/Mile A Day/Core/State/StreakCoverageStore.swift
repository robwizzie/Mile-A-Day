import Foundation

/// Local mirror of the server's token-covered streak days ("frozen dates").
///
/// The streak rule lives in three client walks (WorkoutIndex, WorkoutProcessor,
/// retroactive calculation) that only see HealthKit workouts — a day rescued by
/// a Double Down / Streak Save / Streak Assist has NO workout, so without this
/// store every local recompute would break at the covered day and fight the
/// backend (tripping the vettedHealthKitStreak quarantine). Each walk unions
/// these dates into its "day counts" set so all five walks (2 server, 3 client)
/// agree.
///
/// Populated from the gated `streak_features.frozen_dates` on getUserStats;
/// empty (and therefore a no-op in every walk) until the server enables the
/// feature for this user.
enum StreakCoverageStore {
    private static let datesKey = "streakCoverageDates"
    private static let activeKey = "streakFeaturesActive"

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    /// Covered local-day strings ("yyyy-MM-dd"), matching WorkoutIndex's
    /// dateKey format and the server's local_date values.
    static var coveredDayKeys: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: datesKey) ?? [])
    }

    /// Covered days as start-of-day Dates, for the walks keyed by Date.
    static var coveredDays: Set<Date> {
        let calendar = Calendar.current
        return Set(coveredDayKeys.compactMap { key in
            dayFormatter.date(from: key).map { calendar.startOfDay(for: $0) }
        })
    }

    /// Whether the server has streak features ON for this user — the client
    /// gate for every token surface. Off (default) = zero UI, zero behavior
    /// change anywhere.
    static var isActive: Bool {
        UserDefaults.standard.bool(forKey: activeKey)
    }

    /// Replace the store from a fresh gated stats payload.
    static func update(coveredDates: [String]) {
        UserDefaults.standard.set(Array(Set(coveredDates)).sorted(), forKey: datesKey)
        UserDefaults.standard.set(true, forKey: activeKey)
    }

    /// Server stopped sending the payload (feature off / un-enrolled): clear so
    /// walks and UI return to stock behavior.
    static func deactivate() {
        UserDefaults.standard.removeObject(forKey: datesKey)
        UserDefaults.standard.set(false, forKey: activeKey)
    }
}
