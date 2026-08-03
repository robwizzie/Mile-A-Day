//
//  BestEffortStore.swift
//  Mile A Day
//
//  Local store of the user's best-mile efforts ("ghosts") per activity type,
//  captured from in-app tracked sessions. UserDefaults JSON — losing it on
//  reinstall just means the next mile sets a fresh baseline (runs re-seed
//  from the backend fastest-mile PR immediately, so racing never disappears).
//

import Foundation

enum BestEffortStore {

    struct CurvePoint: Codable, Equatable {
        var t: Double  // race-clock seconds
        var d: Double  // cumulative miles
    }

    /// A recorded (or synthesized) best mile. `curve` is cumulative,
    /// monotonic, and ends exactly at (seconds, 1.0).
    struct BestMileEffort: Codable, Equatable {
        var dateISO: String
        var seconds: Double
        var curve: [CurvePoint]
        var workoutId: String? = nil
    }

    private static func key(_ activityKey: String) -> String {
        "bestMileEffortV1.\(activityKey)"
    }

    static func best(for activityKey: String) -> BestMileEffort? {
        guard let data = UserDefaults.standard.data(forKey: key(activityKey)) else { return nil }
        return try? JSONDecoder().decode(BestMileEffort.self, from: data)
    }

    private static func save(_ effort: BestMileEffort, for activityKey: String) {
        if let data = try? JSONEncoder().encode(effort) {
            UserDefaults.standard.set(data, forKey: key(activityKey))
        }
    }

    /// The ghost to race this session, or nil when there's nothing honest to
    /// race. Runs with no recorded best fall back to a constant-pace ghost
    /// synthesized from the backend fastest-mile PR (elapsed-based, so a
    /// slightly forgiving target — beating it means truly faster). Walks
    /// never race a run PR: without a recorded walk mile the caller gets nil
    /// and offers the set-your-baseline flow instead.
    static func ghost(
        for activityKey: String,
        seedPaceSecondsPerMile: Double?
    ) -> (effort: BestMileEffort, isSeeded: Bool)? {
        if let stored = best(for: activityKey) {
            return (stored, false)
        }
        guard activityKey == "running",
            let pace = seedPaceSecondsPerMile,
            pace.isFinite, pace >= 180, pace <= 1800
        else { return nil }
        let effort = BestMileEffort(
            dateISO: "",
            seconds: pace,
            curve: [CurvePoint(t: 0, d: 0), CurvePoint(t: pace, d: 1.0)]
        )
        return (effort, true)
    }

    /// The ghost's race-clock time at cumulative distance `d` (miles), by
    /// linear interpolation along the curve. Clamped to the curve's ends.
    static func timeAtDistance(_ d: Double, in effort: BestMileEffort) -> Double {
        let curve = effort.curve
        guard let first = curve.first, let last = curve.last else { return 0 }
        if d <= first.d { return first.t }
        if d >= last.d { return last.t }
        for i in 1..<curve.count {
            let a = curve[i - 1]
            let b = curve[i]
            if d <= b.d {
                let span = b.d - a.d
                guard span > 0 else { return b.t }
                return a.t + (b.t - a.t) * ((d - a.d) / span)
            }
        }
        return last.t
    }

    enum FinishOutcome: Equatable {
        /// Session never completed a fresh-from-zero mile — nothing recorded.
        case notAMile
        /// First recorded mile for this activity type.
        case baselineSet(seconds: Double)
        /// Faster than the stored best; now the ghost to beat.
        case newBest(seconds: Double, improvedBy: Double)
        /// Completed a mile, slower than the stored best.
        case slower(bestSeconds: Double)
    }

    /// Fold a finished session into the store. Runs for EVERY finished
    /// session (racing only changes what the UI says about it) so an unraced
    /// mile still quietly becomes the baseline/best, keeping future ghosts
    /// honest. `distanceScale` rescales the live curve's distances to the
    /// reconciled final distance — pedometer reconciliation can shrink or
    /// grow the GPS figure at finish, and the curve must agree with the
    /// number the workout actually saved.
    @discardableResult
    static func recordFinish(
        activityKey: String,
        rawCurve: [(t: Double, d: Double)],
        distanceScale: Double,
        workoutId: String?
    ) -> FinishOutcome {
        let scale = distanceScale.isFinite && distanceScale > 0 ? distanceScale : 1.0
        let curve = rawCurve.map { CurvePoint(t: $0.t, d: $0.d * scale) }
        // Only fresh-from-zero sessions are comparable mile efforts — a
        // recovered workout's curve starts mid-distance with no time history.
        guard let first = curve.first, first.d <= 0.05 else { return .notAMile }
        guard let crossingIndex = curve.firstIndex(where: { $0.d >= 1.0 }) else { return .notAMile }

        // Time at the exact 1.0-mile crossing, interpolated.
        let b = curve[crossingIndex]
        var mileSeconds = b.t
        if crossingIndex > 0 {
            let a = curve[crossingIndex - 1]
            let span = b.d - a.d
            if span > 0 {
                mileSeconds = a.t + (b.t - a.t) * ((1.0 - a.d) / span)
            }
        }
        // Sub-2-minute "miles" are broken data, not efforts.
        guard mileSeconds.isFinite, mileSeconds >= 120 else { return .notAMile }

        // Keep only the first mile, downsampled to ≤ 60 points, ending
        // exactly at 1.0 so timeAtDistance is exact at the finish line.
        var mileCurve = Array(curve.prefix(upTo: crossingIndex))
        if mileCurve.count > 59 {
            let step = Double(mileCurve.count - 1) / 58.0
            mileCurve = (0...58).map { mileCurve[min(Int(Double($0) * step), mileCurve.count - 1)] }
        }
        mileCurve.append(CurvePoint(t: mileSeconds, d: 1.0))

        let effort = BestMileEffort(
            dateISO: ISO8601DateFormatter().string(from: Date()),
            seconds: mileSeconds,
            curve: mileCurve,
            workoutId: workoutId
        )

        if let stored = best(for: activityKey) {
            if mileSeconds < stored.seconds {
                save(effort, for: activityKey)
                return .newBest(seconds: mileSeconds, improvedBy: stored.seconds - mileSeconds)
            }
            return .slower(bestSeconds: stored.seconds)
        }
        save(effort, for: activityKey)
        return .baselineSet(seconds: mileSeconds)
    }

    /// "8:42" formatting for card and celebration copy.
    static func formatSeconds(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
