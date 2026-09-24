import Foundation
import HealthKit

/// "Flamey remembers things": a few TRUE facts about the user's own recent
/// walking, turned into bubble lines. Computed ONCE per hero appearance / day
/// / completion change (the hero's `.task(id:)`), off the main thread from
/// snapshotted arrays — never from `body`, which re-runs on every frame the
/// hero animates.
///
/// Every fact is optional and nothing is ever invented: no data, no line.
/// Days are bucketed the one way every surface buckets them
/// (`startOfDay(startDate)`) and deduped per day (`WorkoutDedup.counting`),
/// so a Strava+Watch twin can't turn one walk into two early mornings.
struct FlameyMemory: Equatable {
    /// Consecutive days, ending today or yesterday, whose goal was done
    /// before 8 AM. Only reported from 3.
    var earlyBirdStreak: Int = 0
    /// Yesterday had a real (≥ 0.5 mi) walk to measure a pace against.
    var hasYesterdayPace = false
    /// Last Sunday–Saturday week's counted miles.
    var lastWeekMiles: Double = 0
    var streak: Int = 0
    var longestStreak: Int = 0
    var doneToday = false

    /// ONE line for today, suited to the mood — or nil. Deterministic per
    /// day (`dayIndex`), so the line doesn't change every time the hero
    /// re-appears.
    func line(for kind: FlameMood.Kind, dayIndex: Int) -> String? {
        var candidates: [String] = []
        let early = earlyBirdStreak >= 3 ? "\(earlyBirdStreak) days before 8 AM!" : nil
        let lastWeek = lastWeekMiles >= 0.1 ? "Last week: \(lastWeekMiles.distanceFormatted1) 🔥" : nil
        let toRecord = longestStreak - streak
        let record: String? = {
            guard streak > 0, longestStreak > 0 else { return nil }
            if toRecord >= 1, toRecord <= 3 {
                return toRecord == 1 ? "1 day to your record!" : "\(toRecord) days to your record!"
            }
            if streak >= longestStreak, streak >= 7 { return "Record streak!" }
            return nil
        }()

        switch kind {
        case .done, .party:
            if streak >= 2 { candidates.append("Day \(streak). Nice.") }
            candidates += [early, lastWeek, record].compactMap { $0 }
        case .ready, .going, .halfway, .almost, .groggy, .nervous:
            if hasYesterdayPace, !doneToday { candidates.append("Beat yesterday's pace?") }
            candidates += [early, record, lastWeek].compactMap { $0 }
        case .unlit:
            candidates += [lastWeek].compactMap { $0 }
        case .sleepy, .bedtime:
            return nil
        }
        guard !candidates.isEmpty else { return nil }
        return candidates[abs(dayIndex) % candidates.count]
    }

    /// Stable per local day.
    static func dayIndex(_ date: Date = Date()) -> Int {
        Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
    }

    /// Reads only in-memory caches (no HealthKit queries), on a detached task.
    static func compute(
        cachedWorkouts: [HKWorkout],
        todaysWorkouts: [HKWorkout],
        goalMiles: Double,
        streak: Int,
        longestStreak: Int,
        doneToday: Bool,
        now: Date = Date()
    ) async -> FlameyMemory {
        await Task.detached(priority: .utility) {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            guard let horizon = calendar.date(byAdding: .day, value: -15, to: today) else { return FlameyMemory() }
            // Only the last ~two weeks matter; filter before grouping.
            let recent = cachedWorkouts.filter { $0.startDate >= horizon }
            var byDay = Dictionary(grouping: recent) { calendar.startOfDay(for: $0.startDate) }
            if byDay[today]?.isEmpty ?? true, !todaysWorkouts.isEmpty { byDay[today] = todaysWorkouts }
            let counted = byDay.mapValues { WorkoutDedup.counting($0) }
            let goal = max(goalMiles, 0.1)

            var memory = FlameyMemory()
            memory.streak = streak
            memory.longestStreak = max(longestStreak, streak)
            memory.doneToday = doneToday

            // Early bird: the day's goal was covered by walks that had
            // FINISHED before 8 AM.
            func doneBefore8(_ day: Date) -> Bool {
                guard let eight = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day) else { return false }
                let early = (counted[day] ?? []).filter { $0.endDate <= eight }
                let miles = early.reduce(0) { $0 + $1.madDistanceMiles }
                return miles >= goal * 0.95
            }
            var cursor = doneBefore8(today) ? today : calendar.date(byAdding: .day, value: -1, to: today) ?? today
            var run = 0
            while run < 14, doneBefore8(cursor) {
                run += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
            }
            memory.earlyBirdStreak = run

            // Yesterday's pace exists.
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
                let walks = counted[yesterday] ?? []
                let miles = walks.reduce(0) { $0 + $1.madDistanceMiles }
                let seconds = walks.reduce(0) { $0 + $1.duration }
                memory.hasYesterdayPace = miles >= 0.5 && seconds > 0
            }

            // Last week, Sunday-start like the weekly challenge.
            let weekday = calendar.component(.weekday, from: now)
            if let thisWeekStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: today),
               let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: thisWeekStart) {
                var total = 0.0
                for offset in 0..<7 {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: lastWeekStart) else { continue }
                    total += (counted[day] ?? []).reduce(0) { $0 + $1.madDistanceMiles }
                }
                memory.lastWeekMiles = total
            }
            return memory
        }.value
    }
}
