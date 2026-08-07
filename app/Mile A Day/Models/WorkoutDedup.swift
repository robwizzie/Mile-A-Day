import Foundation
import HealthKit

/// The same walk, recorded by two apps, counted once.
///
/// Every third-party fitness platform — Google Health, Strava, Garmin, WHOOP —
/// reaches this app by writing into Apple Health. So the SAME walk arrives
/// twice with two UUIDs, and summing HealthKit naively counts it twice. A
/// 1.02 mi walk with Google Health also recording 0.96 mi of it reads as 1.98.
///
/// The backend already solves this (`duplicateExclusionStatements` in
/// workoutService.ts) and that fixes streaks, leaderboards and the feed. It does
/// NOT fix what this app displays, because every "today's distance" on screen is
/// summed on-device straight from HealthKit and never asks the server what
/// counts. That gap is why the dashboard, the Road view and Insights could each
/// show a different, inflated number for the same day.
///
/// So the rule lives here too, deliberately duplicated rather than fetched:
/// these sums run offline, on launch, and inside widget/background paths where a
/// round trip isn't available. The THRESHOLDS below are the contract — they must
/// stay identical to the server's constants or the two will disagree, which is
/// the exact failure this exists to end.
enum WorkoutDedup {
    // ─── Must match backend/src/services/workoutService.ts ───────────────
    /// Share of the SHORTER workout that must overlap before it's the same run.
    static let minOverlapRatio = 0.5
    /// How far two measurements of one route may disagree (fraction of longer).
    static let distanceTolerance = 0.2
    /// Absolute floor for the above, so short walks aren't held to a few feet.
    static let distanceFloor = 0.1
    /// How much of the shorter workout must sit inside the longer one before
    /// it's treated as a fragment of the same activity.
    static let containmentRatio = 0.9

    /// One workout, reduced to what the rule needs.
    private struct Candidate {
        let index: Int
        let bundleId: String
        let start: Date
        let end: Date
        let duration: TimeInterval
        let miles: Double
        /// Mile A Day's own recording. Preferred survivor: it's the copy that
        /// carries the GPS route, which is also the server's first tiebreak.
        let isFirstParty: Bool
    }

    /// Indices of workouts that should NOT be counted, because another workout
    /// in the same array already covers them.
    ///
    /// Returns indices rather than a filtered array so callers can both sum the
    /// survivors AND show the user what was left out — never removing a workout
    /// silently is a requirement, not a nicety.
    static func duplicateIndices(in workouts: [HKWorkout]) -> Set<Int> {
        var excluded = Set<Int>()
        guard workouts.count > 1 else { return excluded }

        // Exact repeats first. Two entries with one UUID are one workout by
        // definition, whatever any distance rule says.
        var seenUUIDs = Set<String>()
        var candidates: [Candidate] = []
        for (index, workout) in workouts.enumerated() {
            let uuid = workout.uuid.uuidString
            if seenUUIDs.contains(uuid) {
                excluded.insert(index)
                continue
            }
            seenUUIDs.insert(uuid)

            let duration = workout.duration
            guard duration > 0 else { continue }
            let bundle = workout.sourceRevision.source.bundleIdentifier
            candidates.append(
                Candidate(
                    index: index,
                    bundleId: bundle,
                    start: workout.startDate,
                    end: workout.endDate,
                    duration: duration,
                    miles: workout.totalDistance?.doubleValue(for: .mile()) ?? 0,
                    isFirstParty: WorkoutAttribution(bundleId: bundle).isFirstParty
                )
            )
        }

        // Preferred survivor sorts FIRST, so a later candidate is only ever
        // dropped in favour of a better one. Mile A Day's copy wins (it has the
        // route); then the longer distance, since a fragment can't be longer
        // than the walk that contains it.
        let ranked = candidates.sorted {
            if $0.isFirstParty != $1.isFirstParty { return $0.isFirstParty }
            if $0.miles != $1.miles { return $0.miles > $1.miles }
            return $0.index < $1.index
        }

        for (position, candidate) in ranked.enumerated() {
            if excluded.contains(candidate.index) { continue }
            for keeper in ranked[..<position] {
                if excluded.contains(keeper.index) { continue }
                if isSameActivity(candidate, keeper) {
                    excluded.insert(candidate.index)
                    break
                }
            }
        }
        return excluded
    }

    /// Two recordings of one real-world activity.
    ///
    /// Same-source pairs are never matched: one app segmenting its own walk is
    /// that app's business, and UUID equality already covers true repeats.
    private static func isSameActivity(_ a: Candidate, _ b: Candidate) -> Bool {
        guard a.bundleId != b.bundleId else { return false }

        let overlap = min(a.end, b.end).timeIntervalSince(max(a.start, b.start))
        guard overlap >= minOverlapRatio * min(a.duration, b.duration) else {
            return false
        }

        // Either both apps recorded the whole activity, so the distances
        // agree...
        let budget = max(distanceFloor, distanceTolerance * max(a.miles, b.miles))
        if abs(a.miles - b.miles) <= budget { return true }

        // ...or `a` is a FRAGMENT of `b`: its window sits almost entirely inside
        // and it covers no more ground. An app that starts tracking partway
        // through writes a short workout inside the long one, and 0.36 vs 1.84
        // fails every distance test while being unmistakably the same walk.
        return overlap >= containmentRatio * a.duration && a.miles <= b.miles
    }

    /// Total miles for a set of workouts, counting each real activity once.
    ///
    /// THE function for "how far did they go". Every surface that shows a day's
    /// distance should call this rather than summing the array itself — that's
    /// what stops the dashboard, the Road view and Insights from disagreeing.
    static func totalMiles(_ workouts: [HKWorkout]) -> Double {
        let excluded = duplicateIndices(in: workouts)
        var total = 0.0
        for (index, workout) in workouts.enumerated() where !excluded.contains(index) {
            total += workout.totalDistance?.doubleValue(for: .mile()) ?? 0
        }
        return total
    }

    /// The workouts that actually count, in their original order.
    static func counting(_ workouts: [HKWorkout]) -> [HKWorkout] {
        let excluded = duplicateIndices(in: workouts)
        guard !excluded.isEmpty else { return workouts }
        return workouts.enumerated()
            .filter { !excluded.contains($0.offset) }
            .map(\.element)
    }
}
