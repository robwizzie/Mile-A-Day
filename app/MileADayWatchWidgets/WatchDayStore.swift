import Foundation

// SHARED by the Watch app and its complications — two BYTE-IDENTICAL copies:
//   app/Mile A Day Watch Watch App/WatchDayStore.swift
//   app/MileADayWatchWidgets/WatchDayStore.swift
// Edit one, `cp` it over the other, `cmp` them.

/// Today's numbers for the watch face. The Watch app writes them; the
/// complications only read, and never see HealthKit or the iPhone directly.
enum WatchDayStore {
    static let suiteName = "group.mileaday.shared"
    private static let key = "watch_day_snapshot_v1"

    struct Snapshot: Codable, Equatable {
        var streak: Int
        var miles: Double
        var goal: Double
        /// `dayStamp` of the day `miles` belongs to.
        var day: String
    }

    static func dayStamp(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func load() -> Snapshot? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: suiteName)?.set(data, forKey: key)
    }

    /// Miles count only on the day they were walked, so a timeline entry baked
    /// for after midnight starts the new day at zero.
    static func miles(in snapshot: Snapshot, on date: Date) -> Double {
        snapshot.day == dayStamp(date) ? snapshot.miles : 0
    }
}
