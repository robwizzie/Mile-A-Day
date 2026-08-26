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

    /// A recorded (or synthesized) best effort. `curve` is cumulative,
    /// monotonic, and ends exactly at (seconds, `distanceMiles`).
    struct BestMileEffort: Codable, Equatable {
        var dateISO: String
        var seconds: Double
        var curve: [CurvePoint]
        var workoutId: String? = nil

        /// How far this effort covers, in miles — OPTIONAL on purpose.
        ///
        /// This struct is persisted to UserDefaults as a Codable blob, and
        /// synthesized `Decodable` ignores property defaults: a non-optional
        /// stored property added here would throw on every already-saved
        /// effort, i.e. everyone's recorded best would silently vanish. An
        /// Optional decodes to nil when the key is absent, which is exactly
        /// what every blob written before this existed needs to mean.
        ///
        /// Read `distanceMiles`, never this.
        var distanceMilesRaw: Double? = nil

        /// The effort's distance. Every legacy value — and everything the
        /// recorder writes — is one mile.
        var distanceMiles: Double {
            guard let raw = distanceMilesRaw, raw.isFinite, raw > 0 else { return 1.0 }
            return raw
        }
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

    // MARK: - Targets

    /// What the user chose to race. There is ALWAYS at least one option
    /// (`.custom`), so no activity can end up with the race unavailable —
    /// a walk with no history used to have nothing to race at all.
    enum GhostTarget: Equatable {
        /// Their own fastest recorded in-app mile for this activity type.
        case recordedBest
        /// The backend fastest-mile PR, flattened to a constant pace.
        case personalRecord
        /// A time the user typed in, over a distance they chose. Constant
        /// pace, same as the PR ghost.
        ///
        /// `seconds` is the TOTAL for `distanceMiles`, not a per-mile pace —
        /// it stays the "how long is this ghost's whole race" figure every
        /// other case already carries, so nothing downstream has to know
        /// which unit it is holding. This is the ONLY case that is ever
        /// anything other than a mile: `.recordedBest`, `.personalRecord` and
        /// `.friend` are all measured mile efforts, and stretching one of
        /// them over a 5K would invent a time nobody ran.
        case custom(seconds: Double, distanceMiles: Double)
        /// A FRIEND's fastest mile, from `GET /ghosts/friends`.
        ///
        /// The seconds and the name ride in the case rather than being looked
        /// up, because `resolve` is synchronous and offline — there is nowhere
        /// to await a friend's time inside this store, and `shortName` is
        /// produced there. The stored name is refreshed whenever the picker
        /// reloads, so a rename shows up the next time they open it.
        case friend(id: String, seconds: Double, name: String)

        /// Compact form for @AppStorage — the enum has an associated value, so
        /// it can't be RawRepresentable in the way AppStorage wants.
        var storage: String {
            switch self {
            case .recordedBest: return "best"
            case .personalRecord: return "pr"
            case .custom(let seconds, let distanceMiles):
                // A ONE-MILE custom target keeps the byte-identical shipped
                // encoding, and the distance is appended only when there is
                // one — so the overwhelmingly common value still round-trips
                // through any build, and a stored `custom:540` still decodes
                // (as a mile) here. Hundredths of a mile as an Int, matching
                // how seconds are already stored: no float formatting, no
                // locale to get wrong, and every offered distance is exact.
                let total = Int(seconds.rounded())
                let hundredths = Int((distanceMiles * 100).rounded())
                if hundredths == 100 { return "custom:\(total)" }
                return "custom:\(total):\(hundredths)"
            case .friend(let id, let seconds, let name):
                // Name goes LAST so it may contain colons — the decoder splits
                // with maxSplits and takes the remainder verbatim.
                return "friend:\(id):\(Int(seconds.rounded())):\(name)"
            }
        }

        init?(storage: String) {
            switch storage {
            case "best": self = .recordedBest
            case "pr": self = .personalRecord
            default:
                // NOTE: this switches over a STRING, so a missing case here is
                // silent — a stored target that doesn't decode just falls back
                // to `defaultTarget` with no crash and no warning. Any new case
                // added above must be given a branch here too.
                if storage.hasPrefix("friend:") {
                    let parts = storage.dropFirst("friend:".count)
                        .split(separator: ":", maxSplits: 2,
                               omittingEmptySubsequences: false)
                    guard parts.count == 3,
                        !parts[0].isEmpty,
                        let seconds = Double(parts[1]),
                        Self.isPlausible(seconds)
                    else { return nil }
                    self = .friend(
                        id: String(parts[0]),
                        seconds: seconds,
                        name: String(parts[2])
                    )
                    return
                }
                guard storage.hasPrefix("custom:") else { return nil }
                // Two accepted forms, and the short one is what the entire
                // installed base has stored:
                //   "custom:540"      -> 9:00 for ONE mile  (shipped form)
                //   "custom:1488:310" -> 24:48 for 3.10 mi  (additive form)
                let customParts = storage.dropFirst("custom:".count)
                    .split(separator: ":", maxSplits: 1,
                           omittingEmptySubsequences: false)
                guard let head = customParts.first, let seconds = Double(head)
                else { return nil }
                var miles: Double = 1.0
                if customParts.count > 1 {
                    guard let hundredths = Double(customParts[1]), hundredths > 0
                    else { return nil }
                    miles = hundredths / 100
                }
                guard Self.isPlausible(seconds, over: miles) else { return nil }
                self = .custom(seconds: seconds, distanceMiles: miles)
            }
        }

        /// How far this target races. Only `.custom` is ever anything but a
        /// mile — see the case's own note.
        var distanceMiles: Double {
            if case .custom(_, let miles) = self, miles.isFinite, miles > 0 {
                return miles
            }
            return 1.0
        }

        /// The friend whose mile this races, when it races one.
        var friendUserId: String? {
            if case .friend(let id, _, _) = self { return id }
            return nil
        }

        /// A mile between 4:01 and 40:00.
        ///
        /// The floor is the mile world record (3:43) rounded up: anything at
        /// or under it, from a consumer phone, is a car or a GPS glitch rather
        /// than a person. It has to match the server's
        /// `MIN_PLAUSIBLE_MILE_SECONDS` exactly — a target outside the band
        /// would be armed, raced, won, and then dropped on upload, so the win
        /// would simply never appear. The ceiling keeps a fat-fingered target
        /// from being unbeatable-by-standing-still.
        static func isPlausible(_ seconds: Double) -> Bool {
            isPlausible(seconds, over: 1.0)
        }

        /// The same band, applied to the PACE the target implies rather than
        /// its total — a 24:48 5K is a 8:00 mile, which is exactly as
        /// plausible as an 8:00 mile target and has to be accepted as one.
        /// Identical to the mile check when `distanceMiles` is 1.
        static func isPlausible(_ seconds: Double, over distanceMiles: Double) -> Bool {
            guard seconds.isFinite, distanceMiles.isFinite,
                distanceMiles >= minTargetMiles, distanceMiles <= maxTargetMiles
            else { return false }
            let perMile = seconds / distanceMiles
            return perMile >= minPlausibleSeconds && perMile <= maxPlausibleSeconds
        }

        /// 4:01 — mirrors `backend/src/services/mileTime.ts`.
        static let minPlausibleSeconds: Double = 241
        static let maxPlausibleSeconds: Double = 2400

        /// A custom target never races LESS than a mile — the mile is the
        /// app's unit and every other target is one — and never more than a
        /// marathon.
        static let minTargetMiles: Double = 1.0
        static let maxTargetMiles: Double = 26.2
    }

    /// The distances a custom target may be raced over. The mile first,
    /// because it is still what almost everyone picks.
    static let targetDistanceChoices: [Double] = [1, 1.5, 2, 3, 3.1, 5, 6.2, 10, 13.1]

    /// Short label for a race distance — "5K" and "10K" are what people call
    /// those, and nobody says "3.1 miles".
    static func distanceLabel(_ miles: Double) -> String {
        if abs(miles - 3.1) < 0.005 { return "5K" }
        if abs(miles - 6.2) < 0.005 { return "10K" }
        if abs(miles - 13.1) < 0.005 { return "Half" }
        if abs(miles - miles.rounded()) < 0.005 {
            return "\(Int(miles.rounded())) mi"
        }
        return String(format: "%.1f mi", miles)
    }

    /// One quarter of a raced mile: your split beside the ghost's.
    struct RaceSplit: Identifiable, Equatable {
        /// 0-based quarter index.
        let index: Int
        let yours: TimeInterval
        let ghost: TimeInterval

        var id: Int { index }
        var label: String { "Q\(index + 1)" }
        /// Seconds GAINED on the ghost in this quarter (negative = lost).
        var delta: TimeInterval { ghost - yours }
    }

    /// Quarter-by-quarter comparison of a finished mile against its ghost.
    ///
    /// This is the story of the race — "3 down at halfway, took it in the last
    /// quarter" — and it's the one thing the live chip can never show, because
    /// the chip only knows the running total.
    ///
    /// Same inputs and the same scaling as `recordFinish`, so the splits
    /// describe the exact mile that was recorded rather than a second opinion.
    /// Returns empty unless the curve is a genuine full mile from a standing
    /// start — a recovered workout resumes mid-distance and has no history for
    /// the quarters it never saw.
    static func raceSplits(
        rawCurve: [(t: TimeInterval, d: Double)],
        distanceScale: Double,
        ghost: BestMileEffort
    ) -> [RaceSplit] {
        let scale = distanceScale.isFinite && distanceScale > 0 ? distanceScale : 1.0
        let curve = rawCurve.map { CurvePoint(t: $0.t, d: $0.d * scale) }
        // Quarters of the RACE, which is the mile for every ghost but a
        // custom long-distance target — so this is byte-identical to the
        // mile-only version whenever the ghost is a mile.
        let raceDistance = ghost.distanceMiles
        guard let first = curve.first, let last = curve.last,
            raceDistance > 0, first.d <= 0.05, last.d >= raceDistance
        else { return [] }

        let mine = BestMileEffort(dateISO: "", seconds: last.t, curve: curve)
        var splits: [RaceSplit] = []
        for quarter in 0..<4 {
            let from = Double(quarter) * 0.25 * raceDistance
            let to = from + 0.25 * raceDistance
            splits.append(
                RaceSplit(
                    index: quarter,
                    yours: timeAtDistance(to, in: mine) - timeAtDistance(from, in: mine),
                    ghost: timeAtDistance(to, in: ghost) - timeAtDistance(from, in: ghost)
                )
            )
        }
        return splits
    }

    /// A resolved target: the effort to race plus how to talk about it.
    struct ResolvedGhost: Equatable {
        var target: GhostTarget
        var effort: BestMileEffort
        /// Short label used in the live chip, the card subtitle and the
        /// celebration. Kept terse — it sits inside an 11pt chip.
        var shortName: String
    }

    /// Every target the user can pick right now, best-first. `.custom` is
    /// always last and always present.
    static func availableTargets(
        for activityKey: String,
        seedPaceSecondsPerMile: Double?
    ) -> [GhostTarget] {
        var targets: [GhostTarget] = []
        if best(for: activityKey) != nil { targets.append(.recordedBest) }
        if seededPace(activityKey: activityKey, pace: seedPaceSecondsPerMile) != nil {
            targets.append(.personalRecord)
        }
        targets.append(storedCustomTarget(for: activityKey))
        return targets
    }

    /// The custom target as the user last left it: their per-mile pace held
    /// over their last chosen distance.
    static func storedCustomTarget(for activityKey: String) -> GhostTarget {
        let miles = customDistanceMiles(for: activityKey)
        return .custom(
            seconds: customSeconds(for: activityKey) * miles,
            distanceMiles: miles
        )
    }

    /// Resolve a target into something raceable, or nil if it no longer exists
    /// (a stored `.recordedBest` after a reinstall, say).
    static func resolve(
        _ target: GhostTarget,
        activityKey: String,
        seedPaceSecondsPerMile: Double?
    ) -> ResolvedGhost? {
        switch target {
        case .recordedBest:
            guard let stored = best(for: activityKey) else { return nil }
            return ResolvedGhost(target: target, effort: stored, shortName: "your best")
        case .personalRecord:
            guard let pace = seededPace(activityKey: activityKey, pace: seedPaceSecondsPerMile)
            else { return nil }
            return ResolvedGhost(
                target: target, effort: constantPace(pace), shortName: "your PR")
        case .custom(let seconds, let distanceMiles):
            guard GhostTarget.isPlausible(seconds, over: distanceMiles) else { return nil }
            return ResolvedGhost(
                target: target,
                effort: constantPace(seconds, distanceMiles: distanceMiles),
                shortName: "your target"
            )
        case .friend(_, let seconds, let name):
            guard GhostTarget.isPlausible(seconds) else { return nil }
            // A flat pace, like the PR and custom ghosts: the server only has
            // the friend's fastest mile SPLIT, never their effort curve (that
            // lives on their device). `shortName` is their name, so the live
            // chip reads "12s ahead of Alex" and the celebration "ahead of
            // Alex over the mile" with no copy changes anywhere.
            return ResolvedGhost(
                target: target,
                effort: constantPace(seconds),
                shortName: name.isEmpty ? "your friend" : name
            )
        }
    }

    /// The target to offer when the user hasn't chosen one yet: their own
    /// recorded best if they have one, else their PR, else a custom time.
    static func defaultTarget(
        for activityKey: String,
        seedPaceSecondsPerMile: Double?
    ) -> GhostTarget {
        availableTargets(for: activityKey, seedPaceSecondsPerMile: seedPaceSecondsPerMile)
            .first ?? storedCustomTarget(for: activityKey)
    }

    /// Walks never inherit a RUN PR — a run PR is not a walk target, and
    /// offering it would be an unbeatable ghost dressed up as a fair one.
    private static func seededPace(activityKey: String, pace: Double?) -> Double? {
        guard activityKey == "running", let pace, pace.isFinite,
            pace >= GhostTarget.minPlausibleSeconds, pace <= 1800
        else { return nil }
        return pace
    }

    /// A ghost that holds one exact pace for the whole race. Defaults to the
    /// mile, so the PR and friend ghosts — which are measured MILE efforts —
    /// keep calling it unchanged and stay miles.
    private static func constantPace(
        _ seconds: Double, distanceMiles: Double = 1.0
    ) -> BestMileEffort {
        let miles = (distanceMiles.isFinite && distanceMiles > 0) ? distanceMiles : 1.0
        return BestMileEffort(
            dateISO: "",
            seconds: seconds,
            curve: [CurvePoint(t: 0, d: 0), CurvePoint(t: seconds, d: miles)],
            workoutId: nil,
            distanceMilesRaw: miles
        )
    }

    // MARK: - Custom target persistence

    private static func customKey(_ activityKey: String) -> String {
        "ghostCustomTargetV1.\(activityKey)"
    }

    /// The user's last custom time for this activity, or a sensible starting
    /// point: a shade under their best/PR if they have one (a target you have
    /// to reach for), else a round 12:00 walk / 9:00 run.
    static func customSeconds(for activityKey: String) -> Double {
        let stored = UserDefaults.standard.double(forKey: customKey(activityKey))
        if GhostTarget.isPlausible(stored) { return stored }
        if let recorded = best(for: activityKey)?.seconds {
            return max(GhostTarget.minPlausibleSeconds, (recorded - 15).rounded())
        }
        return activityKey == "running" ? 540 : 720
    }

    static func saveCustomSeconds(_ seconds: Double, for activityKey: String) {
        guard GhostTarget.isPlausible(seconds) else { return }
        UserDefaults.standard.set(seconds.rounded(), forKey: customKey(activityKey))
    }

    private static func customDistanceKey(_ activityKey: String) -> String {
        "ghostCustomDistanceV1.\(activityKey)"
    }

    /// The distance the user last raced a custom target over. A missing key
    /// reads 0 from UserDefaults and therefore falls through to the mile,
    /// which is what every install had before this existed.
    static func customDistanceMiles(for activityKey: String) -> Double {
        let stored = UserDefaults.standard.double(forKey: customDistanceKey(activityKey))
        guard stored.isFinite, stored >= GhostTarget.minTargetMiles,
            stored <= GhostTarget.maxTargetMiles
        else { return 1.0 }
        return stored
    }

    static func saveCustomDistanceMiles(_ miles: Double, for activityKey: String) {
        guard miles.isFinite, miles >= GhostTarget.minTargetMiles,
            miles <= GhostTarget.maxTargetMiles
        else { return }
        UserDefaults.standard.set(miles, forKey: customDistanceKey(activityKey))
    }

    /// Persist a whole custom target, given its TOTAL time.
    ///
    /// The seconds key keeps holding a PER-MILE pace, exactly as it always
    /// has: it is seeded from a mile time, compared against the mile band,
    /// and read by `customSeconds` — so storing a 5K total in it would make
    /// every one of those mean something different overnight.
    static func saveCustomTarget(
        seconds: Double, distanceMiles: Double, for activityKey: String
    ) {
        let miles = (distanceMiles.isFinite && distanceMiles > 0) ? distanceMiles : 1.0
        saveCustomDistanceMiles(miles, for: activityKey)
        saveCustomSeconds(seconds / miles, for: activityKey)
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
        // Same floor as everything else that reports a mile time: a sub-4:01
        // "mile" is a drive, and letting one in here would make it the user's
        // recorded best — the ghost they can then never beat.
        guard mileSeconds.isFinite, mileSeconds >= GhostTarget.minPlausibleSeconds
        else { return .notAMile }

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

    /// Same, but rolls over into hours — a half marathon target is two hours
    /// of running, and "127:18" is not a time anyone reads.
    static func formatClock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
