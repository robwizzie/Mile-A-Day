import Foundation
import Observation

/// Run Plans (Mile A Day+) live coaching on the iPhone: walks today's
/// segments (warm up, reps, recoveries, cool down) during a tracked run and
/// says what to do next.
///
/// It owns NO voice. Every line goes out through `GhostCoach.sayPlanLine`, so
/// the synthesizer, the music ducking, the on-a-call buzz, the mute switch
/// and the on-screen echo are the ones the tracker already has. It rides the
/// tracker's existing 1 Hz tick (`update`, beside `GhostCoach.update`) and
/// keeps no timer of its own.
///
/// Every number it speaks comes from the server's plan (distances,
/// durations, target paces); it only measures the run against them.
///
/// Lifetimes: `arm` on the pre-run "Today's plan" card, `begin(allowed:)`
/// in `startWorkout` (allowed = no ghost armed: the two are exclusive), `stop`
/// when the workout ends. A singleton because the tracker's `@State` dies
/// whenever its cover is re-presented mid-run.
@Observable
final class PlanRunCoach {
    static let shared = PlanRunCoach()

    /// Where the run is in the plan. nil = not a plan run (the card hides).
    private(set) var status: RunPlanLiveStatus?
    /// Pace over the last minute (s/mi), as the coach judged it.
    private(set) var recentPace: Double?
    /// The plan's last line, for the card when the voice is muted.
    private(set) var line: String?
    private(set) var title = ""

    private struct Armed {
        let date: String
        let title: String
        let segments: [RunPlanLiveSegment]
        let at: Date
    }

    @ObservationIgnored private var armed: Armed?
    @ObservationIgnored private var tracker: RunPlanTracker?
    @ObservationIgnored private var lastPaceLineAt = Date.distantPast
    @ObservationIgnored private var paceLinesThisSegment = 0
    @ObservationIgnored private var lastCall: RunPlanPaceCall?

    /// Pace nudges: at least this far apart (longer on a steady run, where
    /// there's no rep ending to correct before), and at most this many per segment.
    private static let paceLineGap: TimeInterval = 25
    private static let steadyPaceLineGap: TimeInterval = 90
    private static let paceLinesPerSegment = 3
    /// An arm older than this (wizard abandoned) never starts a plan.
    private static let armLifetime: TimeInterval = 15 * 60

    private init() {}

    var isActive: Bool { status != nil }

    // MARK: Lifecycle

    /// The runner picked "Today's plan" in the pre-run wizard.
    func arm(day: RunPlanDay) {
        armed = Armed(date: day.local_date, title: RunPlanFormat.title(day),
                      segments: day.liveSegments, at: Date())
    }

    func disarm() {
        armed = nil
    }

    /// Called from `startWorkout`. Starts the plan when one was armed for
    /// today and no ghost race is (`allowed`). Always consumes the arm.
    func begin(allowed: Bool) {
        let pending = armed
        armed = nil
        stop()
        guard allowed, let pending, !pending.segments.isEmpty,
              Date().timeIntervalSince(pending.at) < Self.armLifetime,
              pending.date == RunPlanDate.todayKey() else { return }
        let fresh = RunPlanTracker(segments: pending.segments)
        tracker = fresh
        title = pending.title
        status = fresh.status(miles: 0, clock: 0)
        GhostCoach.shared.setPlanMode(true)
    }

    func stop() {
        tracker = nil
        status = nil
        recentPace = nil
        line = nil
        title = ""
        lastPaceLineAt = .distantPast
        paceLinesThisSegment = 0
        lastCall = nil
        GhostCoach.shared.setPlanMode(false)
    }

    // MARK: Tick

    /// The tracker's 1 Hz tick. `distance` = `liveDistance`; `clock` = the
    /// tracker's `elapsedTime` (wall time minus MANUAL pauses — never the
    /// moving clock, which freezes while the runner stands, so a timed
    /// recovery spent standing still would never end); `recentPace` =
    /// `recentPaceSecondsPerMile`, the figure GhostCoach also gets.
    func update(distance: Double, clock: TimeInterval, recentPace: Double?) {
        guard var walker = tracker else { return }
        let change = walker.step(miles: distance, clock: clock)
        tracker = walker
        guard let fresh = walker.status(miles: distance, clock: clock) else { return }
        status = fresh
        if self.recentPace != recentPace { self.recentPace = recentPace }

        if let change {
            announce(change, status: fresh)
        } else {
            nudge(fresh, recentPace: recentPace)
        }
    }

    // MARK: Lines

    private func announce(_ change: RunPlanTracker.Change, status: RunPlanLiveStatus) {
        paceLinesThisSegment = 0
        lastCall = nil
        // A segment change resets the nudge clock: the runner just got told
        // what to do, so the next pace line waits a full gap.
        lastPaceLineAt = Date()
        switch change {
        case .finished:
            speak("Plan done. Nice work.", force: true)
        case .began, .advanced:
            speak(RunPlanCue.intro(status), force: true)
        }
    }

    /// Pace vs target on work and steady segments. Dead band (10 s/mi),
    /// a gap between lines, a cap per segment, and quiet near a segment's end.
    private func nudge(_ status: RunPlanLiveStatus, recentPace: Double?) {
        let segment = status.segment
        guard !status.finished, segment.isWork || segment.kind == "steady" else { return }
        let gap = segment.isWork ? Self.paceLineGap : Self.steadyPaceLineGap
        guard paceLinesThisSegment < Self.paceLinesPerSegment,
              Date().timeIntervalSince(lastPaceLineAt) >= gap else { return }
        guard let call = RunPlanPaceCall.judge(recent: recentPace, target: segment.targetPace) else { return }
        if let left = status.remainingSeconds, left < 12 { return }
        if let left = status.remainingMiles, let target = segment.targetPace, left * target < 12 { return }

        // `recentPace` looks back ~45 s, so early in a rep it still holds the
        // jog before it: "fast" is trustworthy sooner than "slow".
        let text: String
        switch call {
        case .onPace:
            // Only worth saying right after a correction landed.
            guard let previous = lastCall, previous != .onPace else { return }
            text = "That's it. Right on pace."
        case .fast(let drift):
            guard status.segmentSeconds >= 30 else { return }
            text = "\(RunPlanCue.seconds(drift)) fast — ease off a touch."
        case .slow(let drift):
            guard status.segmentSeconds >= 50 else { return }
            text = "\(RunPlanCue.seconds(drift)) slow — pick it up a little."
        }
        lastCall = call
        lastPaceLineAt = Date()
        paceLinesThisSegment += 1
        speak(text, force: false)
    }

    private func speak(_ text: String, force: Bool) {
        line = text
        GhostCoach.shared.sayPlanLine(text, force: force)
    }
}

// MARK: - Words

/// The plan coach's lines and the live card's short labels. Built for the
/// eye; `GhostCoach` turns "1:40" into "1 40" when it speaks.
enum RunPlanCue {
    static func intro(_ status: RunPlanLiveStatus) -> String {
        let segment = status.segment
        switch segment.kind {
        case "warmup":
            return "Warm up, easy for \(span(segment))."
        case "work":
            return workIntro(status)
        case "recover":
            return "Recover. \(recoverSpan(segment))."
        case "cooldown":
            return "Cool down. Easy for \(span(segment))."
        default:
            return steadyIntro(segment)
        }
    }

    private static func workIntro(_ status: RunPlanLiveStatus) -> String {
        let segment = status.segment
        let target = targetPhrase(segment)
        if status.workCount > 1, let n = status.workNumber {
            let head = n == status.workCount ? "Last one. Go." : "Interval \(n) of \(status.workCount). Go."
            guard let target else { return head }
            return "\(head) \(target)."
        }
        if let pace = segment.targetPace {
            return "Go. \(span(segment)) at \(paceClock(pace)) pace."
        }
        return "Go. \(span(segment)), strong."
    }

    private static func steadyIntro(_ segment: RunPlanLiveSegment) -> String {
        guard segment.isDistanceBased || segment.isDurationBased else { return "Run easy." }
        if let pace = segment.targetPace {
            return "Steady at \(paceClock(pace)) pace for \(span(segment))."
        }
        return "Easy for \(span(segment)), any pace."
    }

    private static func recoverSpan(_ segment: RunPlanLiveSegment) -> String {
        if segment.isDurationBased, let t = segment.durationSeconds {
            return "\(duration(t, adjective: true)) jog"
        }
        return "Easy jog for \(span(segment))"
    }

    /// "1:40 target" for a sub-mile rep, else "6:40 pace"; nil without a target.
    private static func targetPhrase(_ segment: RunPlanLiveSegment) -> String? {
        guard let pace = segment.targetPace else { return nil }
        if let mi = segment.distanceMiles, mi > 0, mi < 0.95 {
            return "\(RunPlanFormat.clock(pace * mi)) target"
        }
        if segment.isDurationBased, let t = segment.durationSeconds {
            return "\(duration(t, adjective: false)) at \(paceClock(pace)) pace"
        }
        return "\(paceClock(pace)) pace"
    }

    /// Seconds per mile → "6:40" in the display unit.
    static func paceClock(_ secondsPerMile: Double) -> String {
        RunPlanFormat.clock(secondsPerMile.pacePerDisplayUnit)
    }

    /// A pace drift (s/mi) in the display unit: "14 seconds".
    static func seconds(_ driftPerMile: Double) -> String {
        let n = max(1, Int(driftPerMile.pacePerDisplayUnit.rounded()))
        return n == 1 ? "1 second" : "\(n) seconds"
    }

    /// Short drift for the card: "14s".
    static func secondsShort(_ driftPerMile: Double) -> String {
        "\(max(1, Int(driftPerMile.pacePerDisplayUnit.rounded())))s"
    }

    /// How long a segment is, in words: "half a mile", "400 meters", "5 minutes".
    static func span(_ segment: RunPlanLiveSegment) -> String {
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
        let number = RunPlanFormat.distanceNumber(miles)
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
        return RunPlanFormat.clock(Double(s))
    }

    // MARK: Card labels

    /// "INTERVAL 3 OF 6 · FAST", "RECOVER · JOG", "WARM UP · EASY".
    static func header(_ status: RunPlanLiveStatus) -> String {
        if status.finished { return "PLAN DONE" }
        switch status.segment.kind {
        case "warmup": return "WARM UP · EASY"
        case "recover": return "RECOVER · JOG"
        case "cooldown": return "COOL DOWN · EASY"
        case "work":
            if status.workCount > 1, let n = status.workNumber {
                return "INTERVAL \(n) OF \(status.workCount) · FAST"
            }
            return "MAIN SET"
        default:
            return status.segment.targetPace == nil ? "EASY RUN" : "STEADY"
        }
    }

    /// A segment's length, short: "400m", "2 mi", "2:00".
    static func short(_ segment: RunPlanLiveSegment) -> String {
        if segment.isDistanceBased, let mi = segment.distanceMiles { return RunPlanFormat.repLength(mi) }
        if segment.isDurationBased, let t = segment.durationSeconds { return RunPlanFormat.clock(t) }
        return ""
    }

    /// The Next tile: "2:00 jog", "Interval 4 · 400m", "Cool down 800m".
    static func next(_ status: RunPlanLiveStatus) -> String {
        guard let next = status.next else { return status.finished ? "All done" : "Finish" }
        let length = short(next)
        switch next.kind {
        case "work":
            if status.workCount > 1 { return "Interval \(status.upcomingWorkNumber) · \(length)" }
            return "Main set · \(length)"
        case "recover": return "\(length) jog"
        case "warmup": return "Warm up \(length)"
        case "cooldown": return "Cool down \(length)"
        default: return "Run \(length)"
        }
    }
}
