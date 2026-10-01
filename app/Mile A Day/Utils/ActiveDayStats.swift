import Foundation

extension HealthKitManager {
    /// Days with any counted miles, and the miles on those days, from the
    /// local workout index — the honest denominator for "average per day".
    /// Both halves come from the SAME source on purpose: "Avg/Day" used to
    /// divide lifetime miles by the CURRENT STREAK (and "Days Active" showed
    /// the streak), which read as a huge number for anyone whose streak had
    /// restarted. Nil until the index exists.
    var activeDayStats: (days: Int, miles: Double)? {
        guard let index = workoutIndex else { return nil }
        var days = 0
        var miles = 0.0
        for (key, records) in index.workoutsByDate {
            let dayMiles = index.countedMilesByDate?[key] ?? records.reduce(0) { $0 + $1.distance }
            guard dayMiles > 0 else { continue }
            days += 1
            miles += dayMiles
        }
        return days > 0 ? (days, miles) : nil
    }
}
