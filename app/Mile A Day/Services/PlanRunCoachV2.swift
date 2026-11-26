import AudioToolbox
import Foundation
import Observation

/// Run Plans v2 (Mile A Day+) live coaching on the iPhone: walks today's
/// segments during a tracked run, counts the changes down, corrects pace,
/// and says how it should feel when there's no heart rate.
///
/// The decisions (when to speak) are `PlanRunCoachEngine`'s, shared with the
/// Watch in HealthKitManager.swift; this class owns the WORDS and the plumbing.
/// It owns NO voice: every line goes out through `GhostCoach.sayPlanLine`, so
/// the synthesizer, the music ducking, the on-a-call buzz, the mute switch
/// and the on-screen echo are the ones the tracker already has. It rides the
/// tracker's existing 1 Hz tick (`update`, beside `GhostCoach.update`) and
/// keeps no timer of its own.
///
/// Heart rate: the paired Watch's, live over a mirrored workout session
/// (`WatchWorkoutLink`, started for plan runs); the tracker passes it to
/// `update`. Without a Watch the run coaches on pace and feel.
/// `update` returns the tick's events so the link can mirror them.
///
/// Lifetimes: `arm` from the start wizard's Run plan option, `begin` in
/// `startWorkout` (exclusive with a ghost race), `resume` when a relaunched
/// tracker restores the workout, `end` at Stop, `workoutSaved` once
/// HealthKit hands back the workout, `stop` at cleanup. A singleton because
/// the tracker's `@State` dies whenever its cover is re-presented mid-run.
@Observable
final class PlanRunCoachV2 {
    static let shared = PlanRunCoachV2()

    // MARK: Settings

    /// Coach mode (spoken plan cues): the pre-run screen's toggle
    /// (`RunPlanCoachMode`, remembered). Default on.
    static var coachModeOn: Bool { RunPlanCoachMode.isOn }

    /// "Fewer cues": longer gaps, fewer corrections, no on-pace confirmations.
    static let fewerCuesKey = "planRunFewerCuesV2"
    static var fewerCues: Bool { UserDefaults.standard.bool(forKey: fewerCuesKey) }
    static func setFewerCues(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: fewerCuesKey)
        shared.engine?.fewerCues = on
    }

    // MARK: Live state (the card reads these)

    /// Where the run is in the plan. nil = not a plan run (the card hides).
    private(set) var status: PlanRunStatus?
    private(set) var day: PlanRunDay?
    /// Pace the coach judged (smoothed, or the belt's), seconds per mile.
    private(set) var pace: Double?
    /// 15 s average bpm from the Watch (`WatchWorkoutLink`); nil without one.
    private(set) var heartRate: Double?
    /// The plan's last line.
    private(set) var line: String?
    /// False when the line was only shown (voice muted or coach mode off).
    private(set) var lineWasSpoken = false
    /// The next segment, while its countdown runs (lead said, change not yet).
    private(set) var countingDownTo: PlanRunSegment?
    /// A paired treadmill is feeding this run (targets in belt speed).
    private(set) var onTreadmill = false
    /// The belt's speed, mph.
    private(set) var beltMph: Double?

    // MARK: Post-run

    enum GradeState: Equatable {
        /// Waiting for HealthKit to save, then for the workout to sync.
        case waiting
        case graded(score: Int?)
        /// Upload gave up; the server grades on its own from the sync.
        case serverGrades
    }

    /// The plan run that just ended, until the next one starts.
    struct FinishedRun: Equatable {
        let date: String
        let title: String
        var workoutId: String?
        var state: GradeState
    }

    private(set) var finishedRun: FinishedRun?

    // MARK: Internals

    private struct Armed {
        let day: PlanRunDay
        let at: Date
    }

    private struct PendingGrade: Codable {
        let date: String
        var workoutId: String?
        let upload: Stats
        var attempts: Int
        let endedAt: Date

        struct Stats: Codable {
            let actualMiles: Double
            let segments: [PlanRunSegmentStats]
            let repPaces: [Double]
            let avgHR: Double?
        }
    }

    @ObservationIgnored private var armed: Armed?
    @ObservationIgnored private var engine: PlanRunCoachEngine?
    /// `InProgressWorkoutState.workoutUUID` of the run being coached: the
    /// persisted coach only resumes into the same workout.
    @ObservationIgnored private var workoutKey: String?
    @ObservationIgnored private var lastPersistAt = Date.distantPast
    @ObservationIgnored private var pendingGrade: PendingGrade?
    @ObservationIgnored private var uploadObserver: NSObjectProtocol?
    @ObservationIgnored private var uploading = false

    /// An arm older than this (wizard abandoned) never starts a plan.
    private static let armLifetime: TimeInterval = 30 * 60
    private static let snapshotKey = "planRunCoachSnapshotV2"
    private static let pendingGradeKey = "planRunPendingGradeV2"

    private init() {
        pendingGrade = Self.loadPendingGrade()
        uploadObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("MAD_WorkoutsUploaded"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.tryUploadGrade()
        }
    }

    var isActive: Bool { status != nil }

    /// Today's armed plan (from the plan screen's "Start today's run", or the
    /// wizard), still fresh.
    var armedDay: PlanRunDay? {
        guard let armed, armed.day.isForToday, Date().timeIntervalSince(armed.at) < Self.armLifetime else { return nil }
        return armed.day
    }

    // MARK: Lifecycle

    /// The runner chose today's plan. False when the day has nothing to coach.
    @discardableResult
    func arm(day: RunPlanV2Day) -> Bool {
        guard let live = day.planRunDay, live.isForToday, !live.segments.isEmpty else { return false }
        armed = Armed(day: live, at: Date())
        return true
    }

    func disarm() {
        armed = nil
    }

    /// Called from `startWorkout`. Starts the plan when one was armed for
    /// today and no ghost race is (`allowed`). Always consumes the arm.
    func begin(allowed: Bool, workoutKey: String?) {
        let pending = armedDay
        armed = nil
        stop()
        guard allowed, let pending else { return }
        engine = PlanRunCoachEngine(day: pending, fewerCues: Self.fewerCues)
        self.workoutKey = workoutKey
        pendingShoeId = nil
        day = pending
        finishedRun = nil
        status = engine?.tracker.status(miles: 0, clock: 0)
        GhostCoach.shared.setPlanMode(true, keepsSplits: pending.isEasyDay)
        persist(force: true)
    }

    /// A relaunched tracker restored `workoutKey`: pick the plan back up
    /// where it was (segment, its start, the stats so far). Silent.
    func resume(workoutKey: String) {
        guard engine == nil,
              let data = UserDefaults.standard.data(forKey: Self.snapshotKey),
              let saved = try? JSONDecoder().decode(StoredSnapshot.self, from: data),
              saved.workoutKey == workoutKey, saved.snapshot.day.isForToday else { return }
        let resumed = PlanRunCoachEngine(snapshot: saved.snapshot, fewerCues: Self.fewerCues)
        engine = resumed
        self.workoutKey = workoutKey
        day = saved.snapshot.day
        status = nil
        GhostCoach.shared.setPlanMode(true, keepsSplits: saved.snapshot.day.isEasyDay)
    }

    /// The run ended (Stop). Freezes the plan's stats for the grade upload;
    /// the card goes away with the tracker.
    func end(distance: Double, clock: TimeInterval) {
        guard var engine, let day else { return }
        engine.close(clock: clock, miles: distance)
        let stats = PendingGrade.Stats(
            actualMiles: distance,
            segments: engine.stats,
            repPaces: engine.repPaces,
            avgHR: engine.averageHeartRate)
        pendingGrade = PendingGrade(date: day.date, workoutId: nil, upload: stats, attempts: 0, endedAt: Date())
        savePendingGrade()
        finishedRun = FinishedRun(date: day.date, title: day.title, workoutId: nil, state: .waiting)
        let shoe = day.shoeId
        self.engine = nil
        clearLive()
        UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
        pendingShoeId = shoe
    }

    /// The plan's shoe, waiting for the saved workout's id. Not cleared by
    /// `stop()`: cleanup can run before HealthKit hands back the workout.
    @ObservationIgnored private var pendingShoeId: String?

    /// HealthKit saved the plan run (`recapWorkoutId`). Pre-loads the plan's
    /// shoe on it and queues the grade upload for once it syncs.
    func workoutSaved(workoutId: String) {
        // Only the run that just ended: a pending grade whose save never
        // landed must not adopt a later, unrelated workout.
        guard var pending = pendingGrade, pending.workoutId == nil,
              Date().timeIntervalSince(pending.endedAt) < 10 * 60 else { return }
        pending.workoutId = workoutId
        pendingGrade = pending
        savePendingGrade()
        finishedRun?.workoutId = workoutId
        if let shoeId = pendingShoeId {
            pendingShoeId = nil
            PlanRunShoeHandoff.assign(shoeId: shoeId, workoutId: workoutId)
        }
        // The sync usually lands within seconds of the save; the upload
        // notification retries it, these cover a quiet observer.
        for delay in [8.0, 30.0, 90.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.tryUploadGrade() }
        }
    }

    /// Cleanup at the end of a workout (or a cancelled one). Leaves
    /// `finishedRun` and the pending grade alone.
    func stop() {
        engine = nil
        workoutKey = nil
        clearLive()
        GhostCoach.shared.setPlanMode(false, keepsSplits: true)
        UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
    }

    /// The recap's post-run sheet was seen.
    func clearFinishedRun() {
        finishedRun = nil
    }

    private func clearLive() {
        status = nil
        day = nil
        pace = nil
        heartRate = nil
        line = nil
        lineWasSpoken = false
        countingDownTo = nil
        onTreadmill = false
        beltMph = nil
    }

    // MARK: Tick

    /// The tracker's 1 Hz tick. `distance` = `liveDistance` (belt distance
    /// included on a paired treadmill); `clock` = the tracker's `elapsedTime`
    /// (wall time minus MANUAL pauses — never the moving clock, which freezes
    /// while the runner stands, so a timed recovery spent standing would
    /// never end).
    @discardableResult
    func update(distance: Double, clock: TimeInterval, heartRate bpm: Double? = nil) -> [PlanRunEvent] {
        guard var walker = engine else { return [] }
        let link = TreadmillLink.shared
        let belt = link.isConnected ? link.speedKmh.map { $0 / 1.609344 } : nil
        let beltPace = belt.flatMap { $0 > 0.5 ? 3600 / $0 : nil }
        let events = walker.tick(clock: clock, miles: distance, beltPace: beltPace, heartRate: bpm)
        engine = walker
        guard let fresh = walker.status else { return events }

        if status != fresh { status = fresh }
        if pace != walker.pace { pace = walker.pace }
        if heartRate != walker.heartRate { heartRate = walker.heartRate }
        if onTreadmill != link.isConnected { onTreadmill = link.isConnected }
        let roundedBelt = belt.map { ($0 * 10).rounded() / 10 }
        if beltMph != roundedBelt { beltMph = roundedBelt }

        for event in events { handle(event, status: fresh) }
        persist(force: !events.isEmpty)
        return events
    }

    private func handle(_ event: PlanRunEvent, status: PlanRunStatus) {
        let words = PlanRunLines(status: status, treadmill: onTreadmill, hasHeartRate: heartRate != nil,
                                 day: day, pace: pace, beltMph: beltMph)
        switch event {
        case .began:
            countingDownTo = nil
            say(words.intro(), force: true, change: true)
        case .lead(let next):
            countingDownTo = next
            say(words.lead(next), force: true, change: false)
        case .go(let next):
            say(words.go(next), force: true, interrupt: true, change: true)
        case .advanced(let countedDown):
            countingDownTo = nil
            if countedDown {
                if let follow = words.afterCountdown() { say(follow, force: true, change: false) }
            } else {
                say(words.intro(), force: true, change: true)
            }
        case .finished:
            countingDownTo = nil
            say(words.finished(), force: true, change: true)
        case .pace(let call):
            say(words.pace(call), force: false, change: false)
        case .heartRate(let call):
            say(words.heartRate(call), force: false, change: false)
        case .feel(let text):
            say(words.feel(text), force: false, change: false)
        }
    }

    /// `change`: a segment boundary (buzzes when the line wasn't spoken).
    private func say(_ text: String, force: Bool, interrupt: Bool = false, change: Bool) {
        line = text
        var spoken = false
        if Self.coachModeOn {
            spoken = GhostCoach.shared.sayPlanLine(text, force: force, interrupt: interrupt)
        }
        lineWasSpoken = spoken
        // Voice off: a buzz at each change, so a pocketed phone still marks it.
        if !spoken, change {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    // MARK: Persistence (survives a mid-run relaunch)

    private struct StoredSnapshot: Codable {
        let workoutKey: String
        let snapshot: PlanRunSnapshot
    }

    private func persist(force: Bool) {
        guard let engine, let workoutKey else { return }
        guard force || Date().timeIntervalSince(lastPersistAt) >= 10 else { return }
        lastPersistAt = Date()
        if let data = try? JSONEncoder().encode(StoredSnapshot(workoutKey: workoutKey, snapshot: engine.snapshot)) {
            UserDefaults.standard.set(data, forKey: Self.snapshotKey)
        }
    }

    // MARK: Grade upload

    private func savePendingGrade() {
        if let pendingGrade, let data = try? JSONEncoder().encode(pendingGrade) {
            UserDefaults.standard.set(data, forKey: Self.pendingGradeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pendingGradeKey)
        }
    }

    private static func loadPendingGrade() -> PendingGrade? {
        guard let data = UserDefaults.standard.data(forKey: pendingGradeKey),
              let pending = try? JSONDecoder().decode(PendingGrade.self, from: data) else { return nil }
        // A day-old upload is the server's to grade now.
        guard Date().timeIntervalSince(pending.endedAt) < 24 * 3600 else {
            UserDefaults.standard.removeObject(forKey: pendingGradeKey)
            return nil
        }
        return pending
    }

    /// Posts the phone's segment stats (`POST /run-plans/grades`) once the
    /// workout has a server id. Called on every upload notification and a few
    /// timed retries; gives up after 6 tries (the server then grades from
    /// distance, average pace and splits).
    func tryUploadGrade() {
        guard !uploading, var pending = pendingGrade, let workoutId = pending.workoutId else { return }
        uploading = true
        pending.attempts += 1
        pendingGrade = pending
        savePendingGrade()
        let body = RunPlanV2GradeUpload(
            today: RunPlanV2Date.todayKey(),
            local_date: pending.date,
            workout_id: workoutId,
            actual_distance_mi: (pending.upload.actualMiles * 100).rounded() / 100,
            segments: pending.upload.segments.filter { $0.index >= 0 }.map(Self.wire),
            rep_paces_s: pending.upload.repPaces.map { Int($0.rounded()) },
            easy_hr_drift_pct: nil,
            avg_hr: pending.upload.avgHR.map { Int($0.rounded()) })
        let attempts = pending.attempts
        let date = pending.date
        Task { @MainActor [weak self] in
            var body = body
            body.effort = await PlanRunCoachV2.effortGuess(workoutId: workoutId, date: date)
            do {
                let result = try await RunPlanV2Store.shared.uploadGrade(body)
                self?.gradeUploaded(result.grade)
                // The plan's after-run pass (refetch + Apple's coach).
                RunPlanV2Store.shared.workoutDidSync()
            } catch {
                self?.gradeFailed(attempts: attempts)
            }
        }
    }

    private func gradeUploaded(_ grade: RunPlanV2Grade?) {
        uploading = false
        pendingGrade = nil
        savePendingGrade()
        finishedRun?.state = .graded(score: grade?.score)
    }

    private func gradeFailed(attempts: Int) {
        uploading = false
        guard attempts >= 6 else { return }
        pendingGrade = nil
        savePendingGrade()
        finishedRun?.state = .serverGrades
    }

    /// The phone's effort guess (`RunEffortEstimator`), sent inside the grade
    /// upload. Nil when HealthKit can't read the run: the post-run screen
    /// tries again on its own.
    @MainActor
    private static func effortGuess(workoutId: String, date: String) async -> RunPlanV2GradeEffort? {
        let store = RunPlanV2Store.shared
        let day = ([store.today].compactMap { $0 } + store.week).first { $0.dateKey == date }
        guard day?.isWalk != true else { return nil }
        let profile = RunFitnessAnalyzer.shared.profile
        guard let e = await RunEffortEstimator.estimate(workoutId: workoutId, day: day, profile: profile) else { return nil }
        return RunPlanV2GradeEffort(run_type: day == nil ? nil : e.runType.rawValue,
                                    raw_guess: e.rawGuess, features: e.features)
    }

    private static func wire(_ stat: PlanRunSegmentStats) -> RunPlanV2SegmentStat {
        RunPlanV2SegmentStat(
            index: stat.index,
            scored_s: Int(stat.scoredSeconds.rounded()),
            in_band_s: Int(stat.inBandSeconds.rounded()),
            too_fast_s: Int(stat.fastSeconds.rounded()),
            too_slow_s: Int(stat.slowSeconds.rounded()),
            avg_pace_s: stat.avgPace.map { Int($0.rounded()) },
            avg_hr: stat.avgHR.map { Int($0.rounded()) })
    }
}

// MARK: - Shoe pre-load

/// The plan's shoe for a just-saved plan run. Saved as the workout's pick
/// (the same `PUT /workout-shoes/:id` the recap's picker uses, which wins over
/// the sync's default stamp), and remembered for a few minutes so the recap's
/// picker shows it instead of racing the save with a read.
enum PlanRunShoeHandoff {
    private static var picks: [String: (shoeId: String, at: Date)] = [:]

    @MainActor
    static func pick(for workoutId: String) -> String? {
        guard let pick = picks[workoutId], Date().timeIntervalSince(pick.at) < 10 * 60 else { return nil }
        return pick.shoeId
    }

    static func assign(shoeId: String, workoutId: String) {
        Task { @MainActor in
            // Retired or deleted since the plan was written: leave the default.
            await ShoeStore.shared.refreshIfStale()
            guard let shoe = ShoeStore.shared.shoe(id: shoeId), !shoe.isRetired else { return }
            picks[workoutId] = (shoeId, Date())
            do {
                _ = try await ShoeService.setShoe(shoeId, forWorkout: workoutId)
                ShoeStore.shared.workoutAssignmentChanged()
            } catch {
                print("[PlanRunCoachV2] plan shoe save failed: \(error)")
                picks[workoutId] = nil
            }
        }
    }
}

// MARK: - Wire → live

extension RunPlanV2Segment {
    func live(index: Int) -> PlanRunSegment {
        PlanRunSegment(
            index: index,
            kind: kind ?? "steady",
            distanceMiles: distance_mi,
            durationSeconds: duration_s.map(Double.init),
            targetPace: target_pace_s.map(Double.init),
            paceLow: pace_low_s.map(Double.init),
            paceHigh: pace_high_s.map(Double.init),
            speedMph: speed_mph,
            hrLow: hr_low.map(Double.init),
            hrHigh: hr_high.map(Double.init),
            zone: zone,
            scoreBy: score_by,
            feel: feel,
            rep: rep,
            reps: reps)
    }
}

extension RunPlanV2Day {
    /// Segments the live coach can walk: each needs a distance or a time (an
    /// open-ended one is kept only as the last). A day with no segments but a
    /// distance becomes one steady block (index -1: not graded per segment).
    var livePlanSegments: [PlanRunSegment] {
        let all = segments.enumerated().map { $0.element.live(index: $0.offset) }
        let kept = all.enumerated().filter { pair in
            pair.element.isDistanceBased || pair.element.isDurationBased || pair.offset == all.count - 1
        }.map(\.element)
        if !kept.isEmpty { return kept }
        guard miles > 0 else { return [] }
        return [PlanRunSegment(index: -1, kind: "steady", distanceMiles: miles)]
    }

    /// The live coach's copy of this day; nil without a date.
    var planRunDay: PlanRunDay? {
        guard let local_date, !local_date.isEmpty else { return nil }
        return PlanRunDay(
            date: local_date,
            kind: dayKind.rawValue,
            title: title ?? dayKind.rawValue.capitalized,
            subtitle: subtitle,
            estDurationSeconds: est_duration_s.map(Double.init),
            shoeId: runShoe?.shoe_id,
            shoeName: runShoe?.name,
            segments: livePlanSegments)
    }

    /// Worth a plan run: a run (not a walk day), not already done, with
    /// something to coach. Callers also check it's dated today.
    var offersPlanRun: Bool {
        !isWalk && dayStatus != .done && dayStatus != .walkDone && !livePlanSegments.isEmpty
    }
}

// MARK: - Words

/// The plan coach's spoken lines. Built for the eye ("7:10 pace"); `GhostCoach`
/// turns clocks into speech ("7 10") at the one point a line becomes audio.
/// Paces and distances follow the display unit; belt speeds are mph (km/h for
/// kilometre users), as the treadmill's own console shows them.
struct PlanRunLines {
    let status: PlanRunStatus
    let treadmill: Bool
    let hasHeartRate: Bool
    let day: PlanRunDay?
    let pace: Double?
    let beltMph: Double?

    private var segment: PlanRunSegment { status.segment }

    // MARK: Segment changes

    func intro() -> String {
        var parts: [String] = []
        switch segment.kind {
        case "warmup":
            parts.append("Warm up, easy for \(Self.span(segment)).")
        case "work":
            parts.append(workIntro())
        case "recover":
            parts.append("Recover. \(recoverSpan()).")
        case "cooldown":
            parts.append("Cool down. Easy for \(Self.span(segment)).")
        case "walk":
            parts.append("Walk for \(Self.span(segment)).")
        default:
            parts.append(steadyIntro())
        }
        if let feel = feelForStart() { parts.append(feel) }
        return parts.joined(separator: " ")
    }

    /// After "3, 2, 1": only what the countdown didn't already say.
    func afterCountdown() -> String? {
        switch segment.kind {
        case "recover":
            if status.workCount > 1 {
                return "That's \(status.workDone) of \(status.workCount). \(recoverSpan())."
            }
            return "\(recoverSpan())."
        case "cooldown":
            return "Main set done. Cool down for \(Self.span(segment))."
        case "steady", "warmup":
            return feelForStart()
        default:
            return nil
        }
    }

    /// Ten seconds out.
    func lead(_ next: PlanRunSegment) -> String {
        switch next.kind {
        case "work":
            var head = ""
            if status.nextIsLastWork, status.workCount > 1 {
                head = "Last one. "
            } else if status.workCount > 1 {
                head = "Interval \(status.upcomingWorkNumber) of \(status.workCount). "
            }
            if treadmill, let mph = Self.speed(of: next) {
                return "\(head)Set the belt to \(Self.speedText(mph)) in 10 seconds."
            }
            if let pace = next.quotedPace {
                return "\(head)Speed up to \(Self.paceClock(pace)) pace in 10 seconds."
            }
            return "\(head)Pick it up in 10 seconds."
        case "recover":
            if treadmill, let mph = Self.speed(of: next) {
                return "Belt down to \(Self.speedText(mph)) in 10 seconds."
            }
            return "Ease off to a jog in 10 seconds."
        case "cooldown":
            if treadmill, let mph = Self.speed(of: next) {
                return "Cool down in 10 seconds. Belt to \(Self.speedText(mph))."
            }
            return "Cool down in 10 seconds. Ease right off."
        case "walk":
            return "Walk in 10 seconds."
        default:
            if treadmill, let mph = Self.speed(of: next) {
                return "Set the belt to \(Self.speedText(mph)) in 10 seconds."
            }
            if let pace = next.quotedPace {
                return "Settle into \(Self.paceClock(pace)) pace in 10 seconds."
            }
            return "Easy running in 10 seconds."
        }
    }

    func go(_ next: PlanRunSegment) -> String {
        next.isWork ? "3, 2, 1, go." : "3, 2, 1, and ease off."
    }

    func finished() -> String {
        "Plan done. Nice work. Keep going, or end the run when you're ready."
    }

    // MARK: Corrections

    func pace(_ call: PlanRunPaceCall) -> String {
        let easy = !segment.isWork && (day?.isEasyDay ?? false)
        if treadmill, let belt = beltMph, let target = Self.speed(of: segment) {
            switch call {
            case .onTarget: return "That's it. Right on target."
            case .fast: return "The belt's at \(Self.speedText(belt)). The plan says \(Self.speedText(target))."
            case .slow: return "The belt's at \(Self.speedText(belt)). Bring it up to \(Self.speedText(target))."
            }
        }
        switch call {
        case .onTarget:
            return "That's it. Right on pace."
        case .fast(let drift):
            return easy
                ? "\(Self.seconds(drift)) fast. Easy days stay easy."
                : "\(Self.seconds(drift)) fast. Ease off a touch."
        case .slow(let drift):
            return "\(Self.seconds(drift)) slow. Pick it up a little."
        }
    }

    func heartRate(_ call: PlanRunHRCall) -> String {
        switch call {
        case .high(let bpm, let ceiling):
            if day?.holdsHeartRate ?? false {
                return "Heart rate's \(bpm). Ease off and let the pace slow. Keep it under \(ceiling)."
            }
            return "Heart rate's \(bpm), over \(ceiling). Ease off a little."
        case .low(let bpm, _):
            return "Heart rate's only \(bpm). You can push a bit harder."
        }
    }

    func feel(_ text: String) -> String {
        text.isEmpty ? Self.defaultFeel(segment, day: day) : text
    }

    /// No heart rate: say how it should feel when a block starts (reps get
    /// their pace instead).
    private func feelForStart() -> String? {
        guard !hasHeartRate, !segment.isWork, !segment.isWalk else { return nil }
        return feel(segment.feel ?? "")
    }

    static func defaultFeel(_ segment: PlanRunSegment, day: PlanRunDay?) -> String {
        if segment.isWork { return "Hard but controlled." }
        if segment.kind == "steady", segment.quotedPace != nil, day?.kind == "tempo" || day?.kind == "race" {
            return "Comfortably hard: a few words at a time, not full sentences."
        }
        return "Easy: you should still be able to talk in full sentences."
    }

    // MARK: Pieces

    private func workIntro() -> String {
        var head = "Go."
        if status.workCount > 1, let n = status.workNumber {
            head = n == status.workCount ? "Last one. Go." : "Interval \(n) of \(status.workCount). Go."
        }
        if treadmill, let mph = Self.speed(of: segment) {
            return "\(head) \(Self.span(segment)) at \(Self.speedText(mph))."
        }
        if let pace = segment.quotedPace {
            return "\(head) \(Self.span(segment)) at \(Self.paceClock(pace)) pace."
        }
        return "\(head) \(Self.span(segment)), strong."
    }

    private func steadyIntro() -> String {
        guard segment.isDistanceBased || segment.isDurationBased else { return "Run easy." }
        if treadmill, let mph = Self.speed(of: segment) {
            return "Steady at \(Self.speedText(mph)) for \(Self.span(segment))."
        }
        if let pace = segment.quotedPace {
            return "Steady at \(Self.paceClock(pace)) pace for \(Self.span(segment))."
        }
        return "Easy for \(Self.span(segment)), any pace."
    }

    private func recoverSpan() -> String {
        if segment.isDurationBased, let t = segment.durationSeconds {
            return "\(Self.duration(t, adjective: true)) jog"
        }
        return "Easy jog for \(Self.span(segment))"
    }

    // MARK: Formatting (shared with the live card)

    /// The belt speed a segment asks for, mph: the server's, else from its pace.
    static func speed(of segment: PlanRunSegment) -> Double? {
        if let mph = segment.speedMph, mph > 0 { return mph }
        guard let pace = segment.quotedPace, pace > 0 else { return nil }
        return (3600 / pace * 10).rounded() / 10
    }

    /// "9.0 mph" / "14.5 km/h".
    static func speedText(_ mph: Double) -> String {
        if DistanceUnits.current == .kilometers {
            return String(format: "%.1f km/h", mph * 1.609344)
        }
        return String(format: "%.1f mph", mph)
    }

    /// Speed number only, for the card: "9.0".
    static func speedNumber(_ mph: Double) -> String {
        String(format: "%.1f", DistanceUnits.current == .kilometers ? mph * 1.609344 : mph)
    }

    static var speedUnit: String { DistanceUnits.current == .kilometers ? "km/h" : "mph" }

    /// Seconds per mile → "6:40" in the display unit.
    static func paceClock(_ secondsPerMile: Double) -> String {
        PlanRunFormat.clock(secondsPerMile.pacePerDisplayUnit)
    }

    /// A drift (s/mi) in the display unit: "14 seconds".
    static func seconds(_ driftPerMile: Double) -> String {
        let n = max(1, Int(driftPerMile.pacePerDisplayUnit.rounded()))
        return n == 1 ? "1 second" : "\(n) seconds"
    }

    /// "half a mile", "400 meters", "5 minutes".
    static func span(_ segment: PlanRunSegment) -> String {
        if segment.isDistanceBased, let mi = segment.distanceMiles { return distance(mi) }
        if segment.isDurationBased, let t = segment.durationSeconds { return duration(t, adjective: false) }
        return "a while"
    }

    static func distance(_ miles: Double) -> String {
        let unit = DistanceUnits.current
        if miles < 0.95 {
            if unit == .miles {
                if abs(miles - 0.5) < 0.02 { return "half a mile" }
                if abs(miles - 0.25) < 0.02 { return "a quarter mile" }
                if abs(miles - 0.75) < 0.02 { return "three quarters of a mile" }
            }
            let meters = Int((miles * 1609.344 / 50).rounded() * 50)
            return "\(meters) meters"
        }
        let value = miles.inDisplayUnit
        var number = String(format: "%.2f", (value * 100).rounded() / 100)
        while number.contains("."), number.hasSuffix("0") { number.removeLast() }
        if number.hasSuffix(".") { number.removeLast() }
        return "\(number) \(number == "1" ? unit.singular : unit.plural)"
    }

    /// "2 minute" (adjective) / "2 minutes" / "20 seconds" / "2:30".
    static func duration(_ seconds: Double, adjective: Bool) -> String {
        let s = max(1, Int(seconds.rounded()))
        if s >= 60, s % 60 == 0 {
            let m = s / 60
            return adjective || m == 1 ? "\(m) minute" : "\(m) minutes"
        }
        if s < 120 {
            return adjective || s == 1 ? "\(s) second" : "\(s) seconds"
        }
        return PlanRunFormat.clock(Double(s))
    }

    /// A segment's length, short: "400m", "2 mi", "2:00".
    static func short(_ segment: PlanRunSegment) -> String {
        if segment.isDistanceBased, let mi = segment.distanceMiles {
            if mi < 0.95 { return "\(Int((mi * 1609.344 / 50).rounded() * 50))m" }
            return mi.distanceFormatted
        }
        if segment.isDurationBased, let t = segment.durationSeconds { return PlanRunFormat.clock(t) }
        return ""
    }
}
