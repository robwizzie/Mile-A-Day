import Foundation
import HealthKit

/// Run Plans v2 effort guess (build spec §9, contract §7b), ON THE PHONE.
///
/// Reads one finished run's heart-rate and distance series from HealthKit
/// (the same 10-s timeline `RunFitnessAnalyzer` builds), measures the
/// contract's `features` and makes a raw 1–10 guess of how hard it felt.
/// Only the features and the guess leave the phone; the server adds the
/// user's calibration (`guess` = raw + offset) and learns from the rating.
///
/// Inputs: HR against the profile's zones (mean zone, time in zones, peak),
/// pace against what the plan predicted from fitness, HR drift on steady
/// running, duration and walk breaks. No HR (no Watch, or HR not allowed):
/// pace and duration only.
enum RunEffortEstimator {
    struct Estimate: Equatable, Sendable {
        /// 1–10, one decimal.
        let rawGuess: Double
        let features: RunPlanV2EffortFeatures
        let runType: RunPlanV2DayKind
    }

    /// The guess for a synced workout (HealthKit UUID string). Nil when the
    /// workout isn't in HealthKit or a read fails (the run then has no guess;
    /// the server never needs one).
    @MainActor
    static func estimate(workoutId: String, day: RunPlanV2Day?,
                         profile: RunPlanV2FitnessProfile?) async -> Estimate? {
        guard let uuid = UUID(uuidString: workoutId), HKHealthStore.isHealthDataAvailable() else { return nil }
        let store = HealthKitManager.shared.healthStore
        let includeHR = RunFitnessAnalyzer.shared.hasAskedForAccess
        let kind = day?.dayKind ?? .easy
        let predicted = predictedPace(day: day, profile: profile)
        let zones = profile?.zones ?? []
        return await Task.detached(priority: .utility) { () -> Estimate? in
            guard let workout = try? await RunEffortEstimator.fetchWorkout(uuid, store: store) else { return nil }
            let computation = RunFitnessComputation(store: store, includeHR: includeHR, historyFloor: nil)
            guard let timeline = try? await computation.timeline(for: workout) else { return nil }
            let features = RunEffortEstimator.measure(timeline, zones: zones, predictedPace: predicted)
            let raw = RunEffortEstimator.guess(features, kind: kind)
            return Estimate(rawGuess: raw, features: features, runType: kind)
        }.value
    }

    // MARK: Features

    /// What the plan expected this run's average pace to be: the server's own
    /// duration over distance (built from the fitness paces), else the
    /// profile's easy pace on easy/long days.
    static func predictedPace(day: RunPlanV2Day?, profile: RunPlanV2FitnessProfile?) -> Int? {
        if let day, let s = day.est_duration_s, s > 0, day.miles > 0.2 {
            return Int((Double(s) / day.miles).rounded())
        }
        guard let kind = day?.dayKind, kind == .easy || kind == .long else { return nil }
        return profile?.easy_pace_s
    }

    static func measure(_ t: RunFitnessTimeline, zones: [RunPlanV2Zone],
                        predictedPace: Int?) -> RunPlanV2EffortFeatures {
        var f = RunPlanV2EffortFeatures()
        f.duration_s = Int(t.duration.rounded())
        if t.miles > 0.05, t.duration > 0 {
            let pace = t.duration / t.miles
            f.avg_pace_s = Int(pace.rounded())
            if let p = predictedPace, p > 0 {
                f.pace_vs_predicted_pct = RunFitnessComputation.round1((pace / Double(p) - 1) * 100)
            }
        }
        f.predicted_pace_s = predictedPace
        let stretches: RunFitnessComputation.StretchResult? = t.fine ? RunFitnessComputation.analyzeStretches(t) : nil
        if let stretches, t.duration > 0 {
            let walked = stretches.walkStretches.reduce(0, +)
            f.walk_fraction = RunFitnessComputation.round2(min(max(walked / t.duration, 0), 1))
        }
        measureHeartRate(t, zones: zones, stretches: stretches, into: &f)
        return f
    }

    /// HR features; `has_hr` needs 3 minutes of readings.
    private static func measureHeartRate(_ t: RunFitnessTimeline, zones: [RunPlanV2Zone],
                                         stretches: RunFitnessComputation.StretchResult?,
                                         into f: inout RunPlanV2EffortFeatures) {
        let readings = t.hr.compactMap { $0 }
        guard readings.count >= 18 else {
            f.has_hr = false
            return
        }
        f.has_hr = true
        f.avg_hr = Int((readings.reduce(0, +) / Double(readings.count)).rounded())
        let peak = RunFitnessComputation.cleanMaxHR(t) ?? readings.max() ?? 0
        f.peak_hr = Int(peak.rounded())
        let bands = zoneBands(zones)
        if !bands.isEmpty {
            var seconds = [Double](repeating: 0, count: 5)
            var zoneSum = 0.0
            for bpm in readings {
                let z = fractionalZone(bpm, bands: bands)
                zoneSum += z
                let i = min(max(Int(z) - 1, 0), 4)
                seconds[i] += RunFitnessTimeline.bucket
            }
            f.avg_hr_zone = RunFitnessComputation.round1(zoneSum / Double(readings.count))
            f.peak_hr_zone = min(max(Int(fractionalZone(peak, bands: bands)), 1), 5)
            f.time_in_zones_s = seconds.map { Int($0.rounded()) }
        }
        // Drift on the longest steady segment of 20 min or more.
        let steady = stretches?.segments.filter { $0.driftPct != nil }.max { $0.seconds < $1.seconds }
        f.hr_drift_pct = steady?.driftPct.map(RunFitnessComputation.round1)
    }

    /// (zone, low, high) for zones 1–5, sorted.
    private static func zoneBands(_ zones: [RunPlanV2Zone]) -> [(zone: Int, low: Double, high: Double)] {
        let bands = zones.compactMap { z -> (zone: Int, low: Double, high: Double)? in
            guard let n = z.zone, let lo = z.low, let hi = z.high, hi > lo else { return nil }
            return (n, Double(lo), Double(hi))
        }
        return bands.sorted { $0.zone < $1.zone }
    }

    /// 3.4 = 40% of the way through zone 3's band. Below zone 1 = 1.0, above
    /// zone 5 = 5.99.
    private static func fractionalZone(_ bpm: Double, bands: [(zone: Int, low: Double, high: Double)]) -> Double {
        guard let first = bands.first, let last = bands.last else { return 1 }
        if bpm < first.low { return 1 }
        if bpm > last.high { return 5.99 }
        for b in bands where bpm <= b.high {
            let span = max(b.high - b.low + 1, 1)
            return Double(b.zone) + min(max((bpm - b.low) / span, 0), 0.99)
        }
        return 5.99
    }

    // MARK: Guess

    /// Raw 1–10 from the features (before the server's per-type calibration).
    static func guess(_ f: RunPlanV2EffortFeatures, kind: RunPlanV2DayKind) -> Double {
        let paceShift = paceAdjustment(f)
        var g: Double
        if f.hasHeartRate, let zone = f.avg_hr_zone {
            g = zoneScore(zone) + hardTimeBonus(f) + driftBonus(f) + paceShift * 0.5
        } else {
            g = typeBase(kind) + paceShift
        }
        g += durationAdjustment(f)
        g -= min((f.walk_fraction ?? 0) * 4, 1.5)
        return RunFitnessComputation.round1(min(max(g, 1), 10))
    }

    /// Mean zone → effort: 1 → 2, 2 → 3.5, 3 → 5.5, 4 → 7.5, 5 → 9.
    private static func zoneScore(_ zone: Double) -> Double {
        let points: [Double] = [2, 3.5, 5.5, 7.5, 9, 9.5]
        let z = min(max(zone, 1), 5.99) - 1
        let i = min(Int(z), 4)
        return points[i] + (points[i + 1] - points[i]) * (z - Double(i))
    }

    /// Time in zones 4–5 (zone 5 counts double), up to +1.5.
    private static func hardTimeBonus(_ f: RunPlanV2EffortFeatures) -> Double {
        guard let t = f.time_in_zones_s, t.count == 5, let d = f.duration_s, d > 0 else { return 0 }
        let hard = Double(t[3]) + 2 * Double(t[4])
        return min(hard / Double(d) * 2.5, 1.5)
    }

    /// Cardiac drift over 5% on steady running, up to +1.
    private static func driftBonus(_ f: RunPlanV2EffortFeatures) -> Double {
        guard let d = f.hr_drift_pct, d > 5 else { return 0 }
        return min((d - 5) / 5, 1)
    }

    /// Every 5% faster than predicted = +1 (slower = −1), within ±2.5.
    private static func paceAdjustment(_ f: RunPlanV2EffortFeatures) -> Double {
        guard let pct = f.pace_vs_predicted_pct else { return 0 }
        return min(max(-pct / 5, -2.5), 2.5)
    }

    /// Long runs feel harder late: +1 per hour past the first, up to +1.5;
    /// a run under 15 minutes −0.5.
    private static func durationAdjustment(_ f: RunPlanV2EffortFeatures) -> Double {
        guard let d = f.duration_s else { return 0 }
        if d < 15 * 60 { return -0.5 }
        guard d > 3600 else { return 0 }
        return min(Double(d - 3600) / 3600, 1.5)
    }

    /// No HR: what the session usually feels like when run as planned.
    private static func typeBase(_ kind: RunPlanV2DayKind) -> Double {
        switch kind {
        case .easy, .walk: return 3
        case .long: return 4
        case .tempo: return 6.5
        case .intervals: return 7
        case .calibration: return 8
        case .race: return 8.5
        }
    }

    // MARK: Words

    /// The contract's label for a 1–10 effort.
    static func label(_ value: Int) -> String {
        switch value {
        case ...2: return String(localized: "very easy")
        case 3...4: return String(localized: "easy")
        case 5...6: return String(localized: "moderate")
        case 7...8: return String(localized: "hard")
        case 9: return String(localized: "very hard")
        default: return String(localized: "max")
        }
    }

    /// A one-line "why" from the features when the server sent no reason
    /// and the Apple model can't phrase one.
    static func reason(_ f: RunPlanV2EffortFeatures) -> String {
        if f.hasHeartRate, let peak = f.peak_hr_zone, let zone = f.avg_hr_zone {
            let mean = Int(zone)
            if peak > mean {
                return String(localized: "Heart rate averaged zone \(mean) and reached zone \(peak).")
            }
            return String(localized: "Heart rate stayed around zone \(mean).")
        }
        if let pct = f.pace_vs_predicted_pct, abs(pct) >= 3 {
            let n = Int(abs(pct).rounded())
            return pct < 0
                ? String(localized: "No heart rate, so from pace: \(n)% faster than your fitness predicts.")
                : String(localized: "No heart rate, so from pace: \(n)% slower than your fitness predicts.")
        }
        if let d = f.duration_s {
            return String(localized: "No heart rate, so from pace and time: \(d / 60) minutes near your usual pace.")
        }
        return String(localized: "From your pace and how long you ran.")
    }

    // MARK: HealthKit

    private static func fetchWorkout(_ uuid: UUID, store: HKHealthStore) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForObject(with: uuid),
                                  limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: samples?.first as? HKWorkout)
            }
            store.execute(q)
        }
    }
}
