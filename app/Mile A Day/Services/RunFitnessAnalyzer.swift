import Foundation
import HealthKit
import os

/// Run Plans v2 fitness analysis, ON THE PHONE (build spec §3, research rules
/// 14–18). Reads the last 100 running workouts from HealthKit with their full
/// heart-rate and distance sample series, finds steady running segments, and
/// computes the compact `RunPlanV2FitnessProfile` — the only thing that
/// leaves the phone (`PUT /run-plans/fitness-profile`). Raw samples never do.
///
/// Heart rate, resting HR, HRV and date of birth are NOT in
/// `HealthKitManager.healthKitReadTypes` (growing that set re-prompts every
/// install). They're asked for once, from plan setup's "What I found" step
/// (`requestAccess()`); before that, or if denied, the profile has no HR and
/// the coach describes effort instead of zones.
@MainActor
final class RunFitnessAnalyzer: ObservableObject {
    static let shared = RunFitnessAnalyzer()

    @Published private(set) var profile: RunPlanV2FitnessProfile?
    @Published private(set) var isAnalyzing = false
    /// The last analysis failed (HealthKit locked / unavailable).
    @Published private(set) var failed = false

    private var task: Task<RunPlanV2FitnessProfile?, Never>?
    private let cachePrefix = "runPlanV2FitnessProfile|"
    private let uploadedPrefix = "runPlanV2FitnessUploadedAt|"
    static let accessAskedKey = "runPlanV2HRAccessAsked"
    /// Recompute at most this often unless a new run invalidates it.
    private let maxAge: TimeInterval = 12 * 3600
    private var invalidated = false

    private init() {
        if let cached = loadCache() { profile = cached }
    }

    /// The extra read types this feature needs (asked on the setup screen only).
    nonisolated static var extraReadTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        if let t = HKObjectType.quantityType(forIdentifier: .heartRate) { set.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { set.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { set.insert(t) }
        if let t = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { set.insert(t) }
        return set
    }

    var hasAskedForAccess: Bool { UserDefaults.standard.bool(forKey: Self.accessAskedKey) }

    /// Asks for heart rate / resting HR / HRV / age. User-initiated only
    /// (plan setup). HealthKit never says whether READ was granted; a denial
    /// just returns no samples, which the analysis already handles.
    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await HealthKitManager.shared.healthStore.requestAuthorization(
                toShare: [], read: Self.extraReadTypes)
            UserDefaults.standard.set(true, forKey: Self.accessAskedKey)
        } catch {
            // Treat like a denial: analysis runs without HR.
        }
    }

    /// A new run synced: the next refresh recomputes.
    func invalidate() { invalidated = true }

    /// Background-safe: recompute if the cache is old or a run invalidated it,
    /// then upload when the plan exists. Never prompts.
    func refreshIfStale() {
        guard TokenStore.hasTokens else { return }
        if !invalidated, let at = RunPlanV2Date.parseTimestamp(profile?.computed_at),
           Date().timeIntervalSince(at) < maxAge { return }
        Task { _ = await analyze(upload: true) }
    }

    /// Runs (or joins) one analysis. Off the main thread, capped at 100 runs.
    @discardableResult
    func analyze(upload: Bool) async -> RunPlanV2FitnessProfile? {
        if let task { return await task.value }
        isAnalyzing = true
        failed = false
        let includeHR = hasAskedForAccess
        let store = HealthKitManager.shared.healthStore
        let floor = HistoryWindow.floor
        let t = Task.detached(priority: .utility) { () -> RunPlanV2FitnessProfile? in
            try? await RunFitnessComputation(store: store, includeHR: includeHR, historyFloor: floor).run()
        }
        task = t
        let result = await t.value
        task = nil
        isAnalyzing = false
        guard let result else {
            failed = true
            return profile
        }
        invalidated = false
        profile = result
        saveCache(result)
        RunPlanV2Store.shared.setFitnessProfile(result)
        if upload { await uploadIfNeeded(result) }
        return result
    }

    /// Uploads when the user has a plan (or is setting one up: `force`).
    func uploadIfNeeded(_ profile: RunPlanV2FitnessProfile, force: Bool = false) async {
        guard force || RunPlanV2Store.shared.hasPlan, RunPlanV2Store.shared.isPlus else { return }
        guard let userId = SessionIdentity.cachedUserId else { return }
        let key = uploadedPrefix + userId
        if !force, UserDefaults.standard.string(forKey: key) == profile.computed_at { return }
        do {
            let result = try await RunPlanV2Service.uploadFitnessProfile(profile)
            UserDefaults.standard.set(profile.computed_at, forKey: key)
            result.proposals.forEach { RunPlanV2Store.shared.absorb($0) }
        } catch {
            // Next refresh retries.
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        profile = nil
        isAnalyzing = false
        failed = false
    }

    private func saveCache(_ profile: RunPlanV2FitnessProfile) {
        guard let userId = SessionIdentity.cachedUserId, let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: cachePrefix + userId)
    }

    private func loadCache() -> RunPlanV2FitnessProfile? {
        guard let userId = SessionIdentity.cachedUserId,
              let data = UserDefaults.standard.data(forKey: cachePrefix + userId) else { return nil }
        return try? JSONDecoder().decode(RunPlanV2FitnessProfile.self, from: data)
    }
}

// MARK: - The computation (off main)

/// One run's fine-grained timeline: 10-second buckets from the start.
struct RunFitnessTimeline {
    static let bucket: TimeInterval = 10

    let start: Date
    let localDate: String
    let indoor: Bool
    let miles: Double
    let duration: TimeInterval
    /// Metres per bucket.
    var meters: [Double]
    /// Mean HR per bucket (nil = no sample in it).
    var hr: [Double?]
    /// Whether the distance series was fine enough to read pace from.
    var fine: Bool
}

struct RunFitnessSegment {
    let seconds: TimeInterval
    let meters: Double
    let avgHR: Double?
    let driftPct: Double?
    let date: Date

    var paceSPerMile: Double { meters > 0 ? seconds / (meters / 1609.344) : .infinity }
}

struct RunFitnessEffort {
    let meters: Double
    let seconds: Double
    let date: Date
    let localDate: String
    let indoor: Bool
}

struct RunFitnessComputation: Sendable {
    let store: HKHealthStore
    let includeHR: Bool
    let historyFloor: Date?

    static let maxRuns = 100
    /// Faster than 16:00/mi counts as running (walk breaks are slower).
    static let runningSpeed = 1609.344 / (16 * 60)
    /// Slower than 18:00/mi for 20 s+ is a walk break.
    static let walkSpeed = 1609.344 / (18 * 60)
    static let mile = 1609.344

    func run() async throws -> RunPlanV2FitnessProfile {
        let now = Date()
        let workouts = try await fetchRuns()
        var timelines: [RunFitnessTimeline] = []
        // 4 runs at a time: HealthKit queues queries anyway; this keeps
        // memory flat (a run is ~360 buckets per hour).
        var index = 0
        while index < workouts.count {
            try Task.checkCancellation()
            let slice = Array(workouts[index..<min(index + 4, workouts.count)])
            let built = try await withThrowingTaskGroup(of: RunFitnessTimeline?.self) { group -> [RunFitnessTimeline] in
                for w in slice { group.addTask { try? await timeline(for: w) } }
                var out: [RunFitnessTimeline] = []
                for try await t in group { if let t { out.append(t) } }
                return out
            }
            timelines.append(contentsOf: built)
            index += 4
        }
        timelines.sort { $0.start > $1.start }

        let age = includeHR ? self.age() : nil
        let resting = includeHR ? try? await dailyAverages(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), days: 30) : nil
        let hrv = includeHR ? try? await dailyAverages(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), days: 60) : nil
        let firstEver = try? await firstRunDate()

        return Self.profile(from: timelines, workouts: workouts, age: age, restingDaily: resting ?? [:],
                            hrvDaily: hrv ?? [:], firstEver: firstEver, now: now)
    }

    // MARK: HealthKit reads

    private func fetchRuns() async throws -> [HKWorkout] {
        let predicate = HistoryWindow.limitPredicate(HKQuery.predicateForWorkouts(with: .running), floor: historyFloor)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: Self.maxRuns,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                let runs = (samples as? [HKWorkout] ?? []).filter { $0.madDistanceMiles > 0.1 && $0.madDuration > 120 }
                cont.resume(returning: Self.dedupe(runs))
            }
            store.execute(q)
        }
    }

    /// The same run recorded twice (Watch + a third-party app) overlaps in
    /// time: keep the longer recording.
    private static func dedupe(_ runs: [HKWorkout]) -> [HKWorkout] {
        var kept: [HKWorkout] = []
        for w in runs {
            if let i = kept.firstIndex(where: { $0.startDate < w.endDate && w.startDate < $0.endDate }) {
                if w.madDistanceMiles > kept[i].madDistanceMiles { kept[i] = w }
            } else {
                kept.append(w)
            }
        }
        return kept
    }

    private func firstRunDate() async throws -> Date? {
        let predicate = HistoryWindow.limitPredicate(HKQuery.predicateForWorkouts(with: .running), floor: historyFloor)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: samples?.first?.startDate)
            }
            store.execute(q)
        }
    }

    private final class SeriesBox: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock()
        private var _points: [(start: Date, end: Date, value: Double)] = []
        private var finished = false

        var count: Int { lock.lock(); defer { lock.unlock() }; return _points.count }
        var points: [(start: Date, end: Date, value: Double)] { lock.lock(); defer { lock.unlock() }; return _points }
        func append(_ p: (start: Date, end: Date, value: Double)) { lock.lock(); _points.append(p); lock.unlock() }
        /// True exactly once: whoever gets it resumes the continuation.
        func finish() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if finished { return false }
            finished = true
            return true
        }
    }

    /// Every value in [start, end], series samples expanded. A 20 s
    /// watchdog stops a query that never reports `done`.
    private func series(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date,
                        cap: Int = 20_000) async throws -> [(start: Date, end: Date, value: Double)] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let box = SeriesBox()
        let store = self.store
        return try await withCheckedThrowingContinuation { cont in
            let q = HKQuantitySeriesSampleQuery(quantityType: type, predicate: predicate) { query, quantity, interval, _, done, error in
                if let error {
                    guard box.finish() else { return }
                    // "No data" is a successful empty answer, not a failure.
                    if let hk = error as? HKError, hk.code == .errorNoData {
                        cont.resume(returning: [])
                    } else {
                        cont.resume(throwing: error)
                    }
                    return
                }
                if let quantity, let interval, box.count < cap {
                    box.append((interval.start, interval.end, quantity.doubleValue(for: unit)))
                }
                if done || box.count >= cap {
                    guard box.finish() else { return }
                    if !done { store.stop(query) }
                    cont.resume(returning: box.points)
                }
            }
            store.execute(q)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20) {
                guard box.finish() else { return }
                store.stop(q)
                cont.resume(returning: box.points)
            }
        }
    }

    private func timeline(for workout: HKWorkout) async throws -> RunFitnessTimeline {
        let start = workout.startDate
        let end = workout.endDate
        let span = max(end.timeIntervalSince(start), 1)
        let n = max(1, Int((span / RunFitnessTimeline.bucket).rounded(.up)))
        var meters = [Double](repeating: 0, count: n)
        let distance = try await series(.distanceWalkingRunning, unit: .meter(), start: start, end: end)
        // Fine = samples short enough to see a walk break in.
        let durations = distance.map { $0.end.timeIntervalSince($0.start) }.sorted()
        let median = durations.isEmpty ? .infinity : durations[durations.count / 2]
        let fine = !distance.isEmpty && median <= 60
        for p in distance {
            let ps = max(p.start.timeIntervalSince(start), 0)
            let pe = min(max(p.end.timeIntervalSince(start), ps), span)
            let len = pe - ps
            if len <= 0 {
                let i = min(n - 1, Int(ps / RunFitnessTimeline.bucket))
                meters[i] += p.value
                continue
            }
            var t = ps
            while t < pe {
                let i = min(n - 1, Int(t / RunFitnessTimeline.bucket))
                let bucketEnd = min(Double(i + 1) * RunFitnessTimeline.bucket, pe)
                let part = max(bucketEnd - t, 0)
                meters[i] += p.value * part / len
                if bucketEnd <= t { break }
                t = bucketEnd
            }
        }
        var hr = [Double?](repeating: nil, count: n)
        if includeHR {
            let bpm = HKUnit.count().unitDivided(by: .minute())
            let samples = (try? await series(.heartRate, unit: bpm, start: start, end: end)) ?? []
            var sums = [Double](repeating: 0, count: n)
            var counts = [Int](repeating: 0, count: n)
            for s in samples where s.value >= 40 && s.value <= 230 {
                let t = s.start.timeIntervalSince(start)
                guard t >= 0, t <= span else { continue }
                let i = min(n - 1, Int(t / RunFitnessTimeline.bucket))
                sums[i] += s.value
                counts[i] += 1
            }
            for i in 0..<n where counts[i] > 0 { hr[i] = sums[i] / Double(counts[i]) }
        }
        return RunFitnessTimeline(start: start, localDate: RunPlanV2Date.key(for: start), indoor: workout.isIndoorWorkout,
                           miles: workout.madDistanceMiles, duration: workout.madDuration,
                           meters: meters, hr: hr, fine: fine)
    }

    /// Daily average of a quantity over the last `days` days, by local date.
    private func dailyAverages(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async throws -> [String: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [:] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let end = Date()
        let anchor = cal.startOfDay(for: end)
        guard let start = cal.date(byAdding: .day, value: -days, to: anchor) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                options: .discreteAverage, anchorDate: anchor,
                                                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, results, error in
                if let error {
                    if let hk = error as? HKError, hk.code == .errorNoData { cont.resume(returning: [:]) }
                    else { cont.resume(throwing: error) }
                    return
                }
                var out: [String: Double] = [:]
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let v = stats.averageQuantity()?.doubleValue(for: unit) {
                        out[RunPlanV2Date.key(for: stats.startDate)] = v
                    }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    private func age() -> Int? {
        guard let comps = try? store.dateOfBirthComponents(),
              let dob = Calendar(identifier: .gregorian).date(from: comps) else { return nil }
        let years = Calendar(identifier: .gregorian).dateComponents([.year], from: dob, to: Date()).year
        guard let years, years >= 10, years <= 100 else { return nil }
        return years
    }

    // MARK: Analysis

    static func profile(from runs: [RunFitnessTimeline], workouts: [HKWorkout], age: Int?,
                        restingDaily: [String: Double], hrvDaily: [String: Double],
                        firstEver: Date?, now: Date) -> RunPlanV2FitnessProfile {
        var p = RunPlanV2FitnessProfile()
        p.today = RunPlanV2Date.key(for: now)
        p.computed_at = RunPlanV2Date.timestamp(now)
        p.runs_analyzed = runs.count
        p.age = age

        let oldest = runs.last?.start
        let firstRun = [firstEver, oldest].compactMap { $0 }.min()
        p.first_run_date = firstRun.map(RunPlanV2Date.key(for:))
        p.total_miles = round2(runs.reduce(0) { $0 + $1.miles })

        // Volume: four rolling 7-day weeks ending today, oldest first.
        let day: TimeInterval = 86_400
        let weeks: [Double] = (0..<4).reversed().map { w in
            let hi = now.addingTimeInterval(-Double(w) * 7 * day)
            let lo = hi.addingTimeInterval(-7 * day)
            return round2(runs.filter { $0.start > lo && $0.start <= hi }.reduce(0) { $0 + $1.miles })
        }
        p.weekly_miles_by_week = weeks
        p.weekly_miles_4w = round2(weeks.reduce(0, +) / 4)
        let last30 = runs.filter { now.timeIntervalSince($0.start) <= 30 * day }
        p.longest_run_30d_mi = last30.map(\.miles).max().map(round2)
        p.longest_run_mi = runs.map(\.miles).max().map(round2)
        if !runs.isEmpty {
            p.treadmill_fraction = round2(Double(runs.filter(\.indoor).count) / Double(runs.count))
        }

        // Typical start hour (last 30 runs, median).
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let hours = runs.prefix(30).map { cal.component(.hour, from: $0.start) }.sorted()
        p.typical_run_hour = hours.isEmpty ? nil : hours[hours.count / 2]

        // Resting HR + HRV (oldest first, 7 days ending today).
        let last7Keys: [String] = (0..<7).reversed().compactMap { RunPlanV2Date.addingDays(-$0, to: RunPlanV2Date.key(for: now)) }
        let rest7 = last7Keys.map { restingDaily[$0].map { Int($0.rounded()) } }
        p.resting_hr_7d = rest7.contains { $0 != nil } ? rest7 : nil
        let restVals = rest7.compactMap { $0 }
        if !restVals.isEmpty {
            p.resting_hr = median(restVals.map(Double.init)).map { Int($0.rounded()) }
        } else if !restingDaily.isEmpty {
            p.resting_hr = median(Array(restingDaily.values)).map { Int($0.rounded()) }
        }
        let hrv7 = last7Keys.map { hrvDaily[$0].map { Int($0.rounded()) } }
        p.hrv_7d_ms = hrv7.contains { $0 != nil } ? hrv7 : nil
        if hrvDaily.count >= 7 {
            p.hrv_baseline_ms = Int((hrvDaily.values.reduce(0, +) / Double(hrvDaily.count)).rounded())
        }

        // Max HR (rule 14): highest clean HR in the last 12 months, unless it's
        // so far under Tanaka it can't have been a hard effort.
        let tanaka = age.map { 208 - 0.7 * Double($0) }
        let yearRuns = runs.filter { now.timeIntervalSince($0.start) <= 365 * day }
        let observed = yearRuns.compactMap(cleanMaxHR).max()
        let hasHR = runs.contains { r in r.hr.compactMap { $0 }.count >= 30 }
        p.has_hr = hasHR
        if let observed, observed <= 225, tanaka.map({ observed >= $0 - 12 }) ?? true {
            p.max_hr = Int(observed.rounded())
            p.max_hr_source = "observed"
        } else if let tanaka, hasHR {
            p.max_hr = Int(tanaka.rounded())
            p.max_hr_source = "tanaka"
        }

        // Zones (rule 15): HR reserve with a measured resting HR, else %HRmax.
        if hasHR, let maxHR = p.max_hr.map(Double.init) {
            if let rest = p.resting_hr.map(Double.init), rest < maxHR - 40 {
                let r = maxHR - rest
                let cuts = [0.50, 0.60, 0.70, 0.80, 0.90, 1.0]
                p.zones = (1...5).map { z in
                    RunPlanV2Zone(zone: z, low: Int((rest + cuts[z - 1] * r).rounded()) + (z == 1 ? 0 : 1),
                                  high: Int((rest + cuts[z] * r).rounded()))
                }
                p.zone_method = "hrr"
            } else {
                let cuts = [0.55, 0.68, 0.80, 0.87, 0.93, 1.0]
                p.zones = (1...5).map { z in
                    RunPlanV2Zone(zone: z, low: Int((cuts[z - 1] * maxHR).rounded()) + (z == 1 ? 0 : 1),
                                  high: Int((cuts[z] * maxHR).rounded()))
                }
                p.zone_method = "hrmax"
            }
        }

        // Steady segments (rule 17) and run/walk habits.
        var segments: [RunFitnessSegment] = []
        var walkBreakRuns = 0
        var fineRuns = 0
        var runStretches: [Double] = []
        var walkStretches: [Double] = []
        for r in runs where r.fine {
            fineRuns += 1
            let a = analyzeStretches(r)
            segments.append(contentsOf: a.segments)
            if a.walkBreaks > 0 { walkBreakRuns += 1 }
            if a.walkBreaks >= 3 {
                runStretches.append(contentsOf: a.runStretches)
                walkStretches.append(contentsOf: a.walkStretches)
            }
        }
        if fineRuns > 0 {
            p.run_walk = RunPlanV2RunWalk(
                walk_break_runs_fraction: round2(Double(walkBreakRuns) / Double(fineRuns)),
                typical_run_s: median(runStretches).map { Int($0.rounded()) },
                typical_walk_s: median(walkStretches).map { Int($0.rounded()) })
        }
        let drifts = segments.compactMap(\.driftPct)
        let segHR = segments.compactMap(\.avgHR)
        p.steady_segments = RunPlanV2SteadySegments(
            count: segments.count,
            minutes: Int((segments.reduce(0) { $0 + $1.seconds } / 60).rounded()),
            median_pace_s: median(segments.map(\.paceSPerMile)).map { Int($0.rounded()) },
            median_hr: median(segHR).map { Int($0.rounded()) },
            cardiac_drift_pct: median(drifts).map { round1($0) },
            longest_steady_min: segments.map(\.seconds).max().map { Int(($0 / 60).rounded()) })

        // Zone 2 / easy pace at heart rate (prefer the last 8 weeks).
        let recentSegs = segments.filter { now.timeIntervalSince($0.date) <= 56 * day }
        let pool = recentSegs.count >= 5 ? recentSegs : segments
        if let z2 = p.zones.first(where: { $0.zone == 2 }), let lo = z2.low, let hi = z2.high {
            let inZ2 = pool.filter { ($0.avgHR ?? 0) >= Double(lo) && ($0.avgHR ?? 999) <= Double(hi) }
            p.zone2_pace_s = median(inZ2.map(\.paceSPerMile)).map { Int($0.rounded()) }
            p.zone2_hr = median(inZ2.compactMap(\.avgHR)).map { Int($0.rounded()) }
            let easy = pool.filter { ($0.avgHR ?? 999) <= Double(hi) }
            p.easy_pace_s = median(easy.map(\.paceSPerMile)).map { Int($0.rounded()) }
        }
        if p.easy_pace_s == nil, !pool.isEmpty {
            // No HR: the slower 60th percentile of steady running reads as easy.
            let paces = pool.map(\.paceSPerMile).sorted()
            p.easy_pace_s = Int(paces[min(paces.count - 1, Int(Double(paces.count) * 0.6))].rounded())
        }

        // Best efforts (fastest contiguous stretch covering each distance).
        let targets: [(String, Double)] = [("mile", 1609.344), ("5k", 5000), ("10k", 10000),
                                           ("half", 21097.5), ("marathon", 42195)]
        var bests: [String: RunFitnessEffort] = [:]
        var recentBests: [RunFitnessEffort] = []
        for r in runs where r.fine {
            for (key, m) in targets {
                guard let e = fastest(r, meters: m) else { continue }
                if bests[key].map({ e.seconds < $0.seconds }) ?? true { bests[key] = e }
                if now.timeIntervalSince(r.start) <= 56 * day { recentBests.append(e) }
            }
        }
        p.best_efforts = targets.compactMap { key, _ in
            bests[key].map { RunPlanV2BestEffort(distance: key, seconds: Int($0.seconds.rounded()),
                                                  date: $0.localDate, indoor: $0.indoor) }
        }

        // VDOT from the best 5+ minute effort of the last 8 weeks (rule 17).
        let vdots = recentBests.filter { $0.seconds >= 300 }.compactMap { vdot(meters: $0.meters, seconds: $0.seconds) }
        if let v = vdots.max(), v >= 20, v <= 85 {
            p.vdot = round1(v)
            p.race_estimates = RunPlanV2RaceEstimates(
                mile_s: timeFor(vdot: v, meters: 1609.344),
                five_k_s: timeFor(vdot: v, meters: 5000),
                ten_k_s: timeFor(vdot: v, meters: 10000),
                half_s: timeFor(vdot: v, meters: 21097.5),
                marathon_s: timeFor(vdot: v, meters: 42195).map { Int(Double($0) * 1.03) })
        } else if let base = (bests["5k"] ?? bests["mile"]) {
            // Riegel (1.06; 1.08 for the marathon, research: too optimistic for recreational runners).
            func riegel(_ m: Double, _ k: Double) -> Int { Int((base.seconds * pow(m / base.meters, k)).rounded()) }
            p.race_estimates = RunPlanV2RaceEstimates(
                mile_s: riegel(1609.344, 1.06), five_k_s: riegel(5000, 1.06), ten_k_s: riegel(10000, 1.06),
                half_s: riegel(21097.5, 1.06), marathon_s: riegel(42195, 1.08))
        }

        // Critical speed from the best 3- and 12-minute efforts in 8 weeks.
        let recentRuns = runs.filter { $0.fine && now.timeIntervalSince($0.start) <= 56 * day }
        let d3 = recentRuns.compactMap { bestDistance($0, seconds: 180) }.max()
        let d12 = recentRuns.compactMap { bestDistance($0, seconds: 720) }.max()
        if let d3, let d12, d12 > d3 {
            let cs = (d12 - d3) / (720 - 180)
            if cs > 1.5, cs < 7 { p.critical_speed_mps = round2(cs) }
        }

        // Experience (contract: new < 8 weeks; novice < 10 mi/week or < 6 months).
        let weeksRunning = firstRun.map { now.timeIntervalSince($0) / (7 * day) } ?? 0
        if weeksRunning < 8 || runs.count < 4 {
            p.experience = "new"
        } else if (p.weekly_miles_4w ?? 0) < 10 || weeksRunning < 26 {
            p.experience = "novice"
        } else {
            p.experience = "experienced"
        }

        // Calibration (rule 18): only when history is thin.
        let runs8w = runs.filter { now.timeIntervalSince($0.start) <= 56 * day }
        let thin = runs8w.count < 3 || (p.vdot == nil && recentSegs.count < 3)
        p.calibration_needed = thin
        if thin {
            switch p.experience {
            case "new": p.calibration_kind = "mile_tt_talk_test"
            case "novice": p.calibration_kind = "3k"
            default:
                let canRun30 = (p.steady_segments?.longest_steady_min ?? 0) >= 30
                p.calibration_kind = hasHR && canRun30 ? "lthr_30min" : "5k"
            }
        }
        return p
    }

    /// Highest HR held over two adjacent 10-s buckets (a spike in one bucket
    /// is usually a strap artefact).
    private static func cleanMaxHR(_ r: RunFitnessTimeline) -> Double? {
        var best: Double?
        for i in 1..<max(r.hr.count, 1) {
            guard let a = r.hr[i - 1], let b = r.hr[i], abs(a - b) <= 6 else { continue }
            let v = min(a, b)
            if best.map({ v > $0 }) ?? true { best = v }
        }
        return best
    }

    private struct StretchResult {
        var segments: [RunFitnessSegment] = []
        var walkBreaks = 0
        var runStretches: [Double] = []
        var walkStretches: [Double] = []
    }

    /// Splits a run into running and walking stretches (30-s smoothed speed),
    /// then keeps running stretches ≥ 3 min after the first 5 min (rule 16) as
    /// steady segments, trimmed where pace wanders off the stretch's median.
    private static func analyzeStretches(_ r: RunFitnessTimeline) -> StretchResult {
        let b = RunFitnessTimeline.bucket
        let n = r.meters.count
        guard n >= 6 else { return StretchResult() }
        var smooth = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let lo = max(0, i - 1), hi = min(n - 1, i + 1)
            smooth[i] = r.meters[lo...hi].reduce(0, +) / (Double(hi - lo + 1) * b)
        }
        var out = StretchResult()
        enum State { case run, walk }
        var stretches: [(state: State, from: Int, to: Int)] = []
        for i in 0..<n {
            let s: State = smooth[i] >= runningSpeed ? .run : (smooth[i] <= walkSpeed ? .walk : (stretches.last?.state ?? .run))
            if let last = stretches.last, last.state == s {
                stretches[stretches.count - 1].to = i
            } else {
                stretches.append((s, i, i))
            }
        }
        // A walk break: ≥ 20 s of walking with running on both sides.
        for (k, st) in stretches.enumerated() {
            let len = Double(st.to - st.from + 1) * b
            if st.state == .walk, k > 0, k < stretches.count - 1, len >= 20 {
                out.walkBreaks += 1
                out.walkStretches.append(len)
            } else if st.state == .run {
                out.runStretches.append(len)
            }
        }
        let skip = Int(300 / b)
        for st in stretches where st.state == .run {
            let from = max(st.from, skip)
            guard st.to - from + 1 >= Int(180 / b) else { continue }
            // Trim to the longest run of buckets within ±15% of the median speed.
            let speeds = Array(smooth[from...st.to])
            guard let med = median(speeds), med > 0 else { continue }
            var bestFrom = from, bestTo = from - 1, curFrom = from
            for i in from...st.to {
                if abs(smooth[i] - med) / med > 0.15 {
                    curFrom = i + 1
                } else if i - curFrom > bestTo - bestFrom {
                    bestFrom = curFrom
                    bestTo = i
                }
            }
            let count = bestTo - bestFrom + 1
            guard count >= Int(180 / b) else { continue }
            let meters = r.meters[bestFrom...bestTo].reduce(0, +)
            let seconds = Double(count) * b
            let hrs = r.hr[bestFrom...bestTo].compactMap { $0 }
            let avgHR = hrs.count >= count / 3 && !hrs.isEmpty ? hrs.reduce(0, +) / Double(hrs.count) : nil
            var drift: Double?
            if seconds >= 1200, avgHR != nil {
                let mid = bestFrom + count / 2
                let h1 = r.hr[bestFrom..<mid].compactMap { $0 }, h2 = r.hr[mid...bestTo].compactMap { $0 }
                let m1 = r.meters[bestFrom..<mid].reduce(0, +), m2 = r.meters[mid...bestTo].reduce(0, +)
                if !h1.isEmpty, !h2.isEmpty, m1 > 0, m2 > 0 {
                    let e1 = (h1.reduce(0, +) / Double(h1.count)) / m1
                    let e2 = (h2.reduce(0, +) / Double(h2.count)) / m2
                    drift = (e2 / e1 - 1) * 100
                }
            }
            out.segments.append(RunFitnessSegment(seconds: seconds, meters: meters, avgHR: avgHR, driftPct: drift,
                                              date: r.start.addingTimeInterval(Double(bestFrom) * b)))
        }
        return out
    }

    /// Fastest contiguous stretch of a run covering `meters` (two pointers
    /// over the buckets). Nil when the run is shorter.
    private static func fastest(_ r: RunFitnessTimeline, meters target: Double) -> RunFitnessEffort? {
        let m = r.meters
        guard m.reduce(0, +) >= target else { return nil }
        var best: Double = .infinity
        var lo = 0
        var sum = 0.0
        for hi in 0..<m.count {
            sum += m[hi]
            while lo < hi, sum - m[lo] >= target {
                sum -= m[lo]
                lo += 1
            }
            if sum >= target {
                // Prorate the last bucket so a window isn't charged 10 s for a metre.
                let over = sum - target
                let lastFrac = m[hi] > 0 ? min(over / m[hi], 1) : 0
                let t = Double(hi - lo + 1) * RunFitnessTimeline.bucket - lastFrac * RunFitnessTimeline.bucket
                best = min(best, t)
            }
        }
        guard best.isFinite else { return nil }
        // Implausible (faster than 3:30/mi): a GPS jump, not an effort.
        guard best / (target / mile) >= 210 else { return nil }
        return RunFitnessEffort(meters: target, seconds: best, date: r.start, localDate: r.localDate, indoor: r.indoor)
    }

    private static func bestDistance(_ r: RunFitnessTimeline, seconds: Double) -> Double? {
        let k = Int(seconds / RunFitnessTimeline.bucket)
        guard r.meters.count >= k, k > 0 else { return nil }
        var sum = r.meters[0..<k].reduce(0, +)
        var best = sum
        if r.meters.count > k {
            for i in k..<r.meters.count {
                sum += r.meters[i] - r.meters[i - k]
                best = max(best, sum)
            }
        }
        // Faster than 3:30/mi isn't a run.
        return best / seconds <= mile / 210 ? best : nil
    }

    /// Daniels & Gilbert VDOT for a performance.
    static func vdot(meters: Double, seconds: Double) -> Double? {
        let t = seconds / 60
        guard t > 0 else { return nil }
        let v = meters / t
        let vo2 = -4.60 + 0.182258 * v + 0.000104 * v * v
        let pct = 0.8 + 0.1894393 * exp(-0.012778 * t) + 0.2989558 * exp(-0.1932605 * t)
        return pct > 0 ? vo2 / pct : nil
    }

    /// Race time for a VDOT (bisection on Daniels' formula).
    static func timeFor(vdot target: Double, meters: Double) -> Int? {
        var lo = meters / 1609.344 * 150.0, hi = meters / 1609.344 * 1800.0
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            guard let v = vdot(meters: meters, seconds: mid) else { return nil }
            if v > target { lo = mid } else { hi = mid }
        }
        return Int(((lo + hi) / 2).rounded())
    }

    static func median(_ xs: [Double]) -> Double? {
        let s = xs.filter(\.isFinite).sorted()
        guard !s.isEmpty else { return nil }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
    static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
}

extension HistoryWindow {
    /// `limit(_:)` with a floor read on the main thread beforehand (the
    /// analysis runs detached).
    static func limitPredicate(_ base: NSPredicate, floor: Date?) -> NSPredicate {
        guard let floor else { return base }
        let window = HKQuery.predicateForSamples(withStart: floor, end: nil, options: .strictStartDate)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [base, window])
    }
}
