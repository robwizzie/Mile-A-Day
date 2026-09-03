import Foundation
import HealthKit
import Observation

/// Where "Well Earned" gets its calories — ONE source, said plainly on every
/// surface: the active energy Apple Health recorded for your walks and runs,
/// the same workouts Mile A Day counts toward your miles. Not the Watch's
/// all-day ring, not resting calories. (An "all activity" option existed
/// briefly; for real users the two numbers never meaningfully differed, so
/// the switch only raised a question nobody needed to answer.)
///
/// Every total goes through `WorkoutDedup.counting` PER LOCAL DAY: a walk
/// that Strava and the Watch both wrote to HealthKit is two HKWorkouts and
/// would otherwise be two burgers. Grouping by day first also keeps the
/// pairwise dedupe cheap over a multi-year history. Reads
/// `HealthKitManager`'s in-memory caches only — no HealthKit queries.
enum CalorieLedger {
    /// Plain-English provenance, printed wherever the number is.
    static let sourceSentence =
        "Counts the active calories Apple Health recorded for your walks and runs — the same workouts Mile A Day counts toward your miles. Other activity, resting calories and your Watch's all-day ring aren't included."

    static func kilocalories(_ workout: HKWorkout) -> Double {
        RunPostService.workoutCalories(workout)
    }

    /// Deduped kcal for ONE day's workouts.
    static func countedKilocalories(in workouts: [HKWorkout]) -> Double {
        guard !workouts.isEmpty else { return 0 }
        return WorkoutDedup.counting(workouts).reduce(0) { $0 + kilocalories($1) }
    }

    /// Workout kcal for a period, computed OFF the main thread from arrays the
    /// caller snapshotted there. During a live walk `todaysDistance` publishes
    /// every few seconds and the cards refresh on it; walking a multi-year
    /// history through the dedupe on the main thread each time is what made
    /// the dashboard stutter. Local day is `startOfDay(startDate)` — the one
    /// rule every bucketing surface uses (ios.md). Week is Sunday-start,
    /// exactly like the dashboard's weekly miles, so the two agree.
    nonisolated static func workoutKilocalories(
        period: TreatPeriod,
        cachedWorkouts: [HKWorkout],
        todaysWorkouts: [HKWorkout],
        now: Date = Date()
    ) async -> Double {
        await Task.detached(priority: .utility) {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            let live = cachedWorkouts.filter { !DeletedWorkoutRegistry.contains($0.uuid.uuidString) }
            var byDay = Dictionary(grouping: live) { calendar.startOfDay(for: $0.startDate) }
            // The full history can lag today's walk by a sync; the day list
            // never does.
            if byDay[today]?.isEmpty ?? true, !todaysWorkouts.isEmpty {
                byDay[today] = todaysWorkouts
            }
            func dayTotal(_ day: Date) -> Double {
                countedKilocalories(in: byDay[day] ?? [])
            }
            switch period {
            case .today:
                return dayTotal(today)
            case .week:
                let weekday = calendar.component(.weekday, from: now)
                guard let start = calendar.date(byAdding: .day, value: -(weekday - 1), to: today)
                else { return 0 }
                return (0..<weekday).reduce(0.0) { sum, offset in
                    guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return sum }
                    return sum + dayTotal(day)
                }
            case .allTime:
                return byDay.keys.reduce(0.0) { $0 + dayTotal($1) }
            }
        }.value
    }
}

/// The card's state: which treat, which period, and the kcal behind them.
/// Memoised on a fingerprint of the inputs so a dashboard re-render doesn't
/// re-walk the history; the cards call `refresh` on appear and on the
/// HealthKit publishes they already observe. One computation in flight at a
/// time.
@MainActor
@Observable
final class TreatCounterModel {
    private(set) var treat: CalorieTreat
    private(set) var period: TreatPeriod
    private(set) var kcal: Double = 0
    private var fingerprint = ""
    private var inFlight: Task<Void, Never>?

    init() {
        treat = CalorieTreat.current
        period = TreatPeriod.current
    }

    /// Units of the chosen treat.
    var count: Double {
        guard treat.kcalPerUnit > 0 else { return 0 }
        return kcal / treat.kcalPerUnit
    }

    var isEmpty: Bool { count <= 0.0001 }

    /// Identity for the Flamey scene: a new treat OR a flip between "nothing
    /// yet" and "something" is a new set of motions, so callers `.id` on this
    /// and the view is rebuilt with fresh timings.
    var sceneKey: String { "\(treat.rawValue)-\(isEmpty ? "empty" : "earned")" }

    func select(_ treat: CalorieTreat) {
        guard treat != self.treat else { return }
        self.treat = treat
        CalorieTreat.current = treat
    }

    func select(_ period: TreatPeriod) {
        guard period != self.period else { return }
        self.period = period
        TreatPeriod.current = period
        fingerprint = ""
    }

    func refresh(_ healthManager: HealthKitManager) {
        let print = [
            period.rawValue,
            String(healthManager.cachedWorkouts.count),
            String(healthManager.todaysWorkouts.count),
            String(healthManager.cachedLatestWorkoutDate?.timeIntervalSince1970 ?? 0),
            String(healthManager.todaysDistance),
            String(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970),
        ].joined(separator: "|")
        guard print != fingerprint else { return }
        fingerprint = print

        // Snapshot on the main actor, compute off it (see workoutKilocalories).
        let snapshot = healthManager.cachedWorkouts
        let today = healthManager.todaysWorkouts
        let period = self.period
        inFlight?.cancel()
        inFlight = Task { [weak self] in
            let value = await CalorieLedger.workoutKilocalories(
                period: period, cachedWorkouts: snapshot, todaysWorkouts: today)
            guard !Task.isCancelled, let self else { return }
            self.kcal = value
        }
    }
}

/// The one caption every surface prints under the number, so the dashboard
/// card, the Modern tile and the sheet never explain the mechanic three ways.
/// Always names the source.
enum TreatCopy {
    /// Reads the main-actor model, so it runs there too (views already do).
    @MainActor
    static func caption(_ model: TreatCounterModel) -> String {
        if model.isEmpty {
            return "Nothing earned yet \(model.period.caption). \(model.treat.perMileHint)"
        }
        return "≈ \(TreatFormat.kcal(model.kcal)) kcal your walks & runs burned \(model.period.caption), per Apple Health"
    }
}
