import AVFoundation
import Foundation

/// The voice in your ear during a workout.
///
/// It exists because the delta chip is unreadable while you're actually
/// running: the phone is in a pocket or a strap, and the one thing you want to
/// know — am I ahead or behind — is the one thing you can't check without
/// breaking stride. So the run says it out loud.
///
/// Design rules, in the order they matter:
///
///  - **Say little.** A coach that talks constantly gets muted, and a muted
///    coach helps nobody. There is a hard floor between lines, milestones fire
///    once each, and a loss at the finish stays silent — the same rule the
///    celebration follows, because being told you lost isn't coaching.
///  - **Never stop the music.** The session ducks (`.duckOthers`) rather than
///    interrupting, and it is only ACTIVE while an utterance is in flight —
///    holding it open for a whole workout would leave the user's music quiet
///    the entire time.
///  - **Every line is also text.** `lastLine` is published so the tracking
///    screen can show what was said, which is what makes this usable with the
///    volume down or the coach off.
///
/// Two lifetimes, and keeping them apart is what lets the coach outlive the
/// race: `isActive` is the WORKOUT (started at the first step, ended at Finish)
/// and `isRacing` is the GHOST (ends the moment the target distance is
/// crossed). Folding them together is what used to make the coach go silent at
/// exactly one mile — the split, pace and interval lines below all belong to
/// the workout, so mile 2, 3 and 4 keep getting called.
final class GhostCoach: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = GhostCoach()

    /// User preference. Default ON — most people want it, and it announces
    /// itself in the first ten seconds so it's easy to find and turn off.
    static let enabledKey = "ghostCoachEnabledV1"
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: enabledKey)
    }

    /// How often the coach calls out distance + pace, in miles. 0 turns the
    /// interval line off without silencing splits, milestones or the race.
    ///
    /// `object(forKey:)` rather than `double(forKey:)` on purpose: the latter
    /// reads an unset key as 0, which is a real setting here (off), so an
    /// untouched install would come up with the feature disabled.
    static let intervalKey = "coachIntervalMilesV1"
    static let intervalChoices: [Double] = [0, 0.1, 0.25, 0.5, 1.0]
    static var intervalMiles: Double {
        UserDefaults.standard.object(forKey: intervalKey) as? Double ?? 0.5
    }
    static func setIntervalMiles(_ miles: Double) {
        UserDefaults.standard.set(miles, forKey: intervalKey)
    }

    /// The most recent line, for the on-screen echo. Cleared by `stop()`.
    @Published private(set) var lastLine: String?

    private let synthesizer = AVSpeechSynthesizer()

    /// How much a line is worth interrupting for.
    ///
    /// The floor adapts because a race decided by three seconds deserves more
    /// talk than a rout: a fixed interval either nags during a blowout or goes
    /// quiet exactly when it matters.
    enum Urgency {
        /// Lead changes, milestones, a close race — the moments worth hearing.
        case high
        /// Effort nudges in a race that isn't close.
        case normal

        var floor: TimeInterval {
            switch self {
            case .high: return 15
            case .normal: return 40
            }
        }
    }

    /// Where you stand against the goal pace, with a dead band so a stride's
    /// worth of drift doesn't get announced.
    enum PaceState {
        case ahead
        case on
        case behind

        var spoken: String {
            switch self {
            case .ahead: return "You're now ahead of pace."
            case .on: return "You're now on pace."
            case .behind: return "You're now behind pace."
            }
        }
    }

    private var ghostName = "your ghost"
    /// The GHOST is live — lead changes, chase lines, the verdict.
    private var isRacing = false
    /// The WORKOUT is live — splits, intervals, pace state. Outlives the race.
    private var isActive = false
    private var lastSpokeAt = Date.distantPast
    private var firedMilestones: Set<String> = []
    /// Nil until the first meaningful delta — the first few steps are noise.
    private var wasAhead: Bool?

    /// The distance the goal is stated over: the race distance when a ghost is
    /// armed, else the day's goal. Milestones are FRACTIONS of this, so they
    /// still mean something over a 5K.
    private var targetDistance: Double = 1.0
    /// Seconds per mile the goal implies. Nil when nothing was targeted, which
    /// is what silences the ahead/behind lines rather than inventing a pace.
    private var goalPace: Double?

    /// Seeded from the first sample, never from zero: the coach can be started
    /// mid-workout (a re-entered tracker, a mid-run ghost arm), and counting
    /// from 0 would announce every mile already run in one breath.
    private var hasSeededProgress = false
    private var lastMileCompleted = 0
    private var lastMileClock: TimeInterval = 0
    private var lastIntervalMark: Double = 0
    private var paceState: PaceState?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Lifecycle

    /// Start the coach for a workout.
    ///
    /// `ghostSeconds` nil means there is no ghost — the coach still calls
    /// splits, intervals and the halfway turnaround, which is the whole point
    /// of it being a coach rather than a scoreboard.
    func start(
        ghostName: String,
        isRun: Bool,
        ghostSeconds: Double?,
        targetDistance: Double = 1.0
    ) {
        guard Self.isEnabled else { return }
        self.ghostName = ghostName
        self.targetDistance = max(targetDistance, 0.1)
        isActive = true
        isRacing = ghostSeconds != nil
        lastSpokeAt = .distantPast
        firedMilestones = []
        wasAhead = nil
        hasSeededProgress = false
        lastMileCompleted = 0
        lastMileClock = 0
        lastIntervalMark = 0
        paceState = nil
        goalPace = ghostSeconds.map { $0 / self.targetDistance }

        guard let ghostSeconds else { return }
        // The brief. A target in the abstract is hard to run to; a per-mile
        // pace is a number you can actually check yourself against, and over
        // anything longer than a mile it's the only one that travels.
        if self.targetDistance > 1.01, let goalPace {
            say(
                "Racing \(ghostName). \(BestEffortStore.formatSeconds(ghostSeconds)) "
                    + "for \(milesSpoken(self.targetDistance)) — \(paceWords(goalPace)).",
                force: true
            )
        } else {
            let quarter = ghostSeconds / 4
            say(
                "Racing \(ghostName). \(BestEffortStore.formatSeconds(ghostSeconds)) "
                    + "for the mile — \(BestEffortStore.formatSeconds(quarter)) a quarter.",
                force: true
            )
        }
    }

    /// Everything the coach needs, sampled at one instant.
    ///
    /// A struct rather than loose arguments because the lines are only honest
    /// if the figures agree with each other — `delta` and `recentPace` read
    /// from the same tick, so the coach can't say "slipping" off a stale pace
    /// while quoting a fresh delta.
    struct Sample {
        /// Miles so far — `liveDistance`, the same number the ring shows.
        let distance: Double
        /// Race clock in seconds (moving time outdoors).
        let raceClock: TimeInterval
        /// Seconds ahead(+)/behind(−), the SAME figure the chip renders. Nil
        /// once the race is decided, or when none was armed.
        let delta: TimeInterval?
        /// The ghost's total time over the target distance. Nil when no ghost.
        let ghostSeconds: Double?
        /// Pace over roughly the last minute, seconds/mile. Nil when the
        /// runner has gone quiet — the coach must then say nothing about
        /// effort rather than guess.
        let recentPace: Double?
        /// The distance the goal is stated over. Defaults to the mile so every
        /// existing caller keeps its meaning.
        var targetDistance: Double = 1.0

        init(
            distance: Double,
            raceClock: TimeInterval,
            delta: TimeInterval?,
            ghostSeconds: Double?,
            recentPace: Double?,
            targetDistance: Double = 1.0
        ) {
            self.distance = distance
            self.raceClock = raceClock
            self.delta = delta
            self.ghostSeconds = ghostSeconds
            self.recentPace = recentPace
            self.targetDistance = targetDistance
        }

        /// Seconds per mile needed over what's left to finish level with the
        /// ghost. Pure arithmetic — no curve lookup, because the finish line
        /// is a fixed distance and the ghost's total is a fixed time.
        var requiredPace: Double? {
            guard let ghostSeconds else { return nil }
            let remaining = targetDistance - distance
            guard remaining > 0.02 else { return nil }
            let budget = ghostSeconds - raceClock
            guard budget > 0 else { return nil }
            return budget / remaining
        }

        /// Average pace for everything run so far. The honest fallback when
        /// there's no recent-pace derivative to quote.
        var averagePace: Double? {
            guard distance > 0.05, raceClock > 0 else { return nil }
            return raceClock / distance
        }
    }

    /// Called from the tracker's existing 1 Hz tick — no timer of its own.
    ///
    /// Ordered by what a runner most wants to hear, and every branch that
    /// speaks RETURNS: two lines in one breath is how a coach gets muted.
    func update(_ sample: Sample) {
        guard Self.isEnabled, isActive else { return }
        targetDistance = max(sample.targetDistance, 0.1)
        if goalPace == nil, let ghostSeconds = sample.ghostSeconds {
            goalPace = ghostSeconds / targetDistance
        }

        // Adopt wherever the run already is, silently. Only the FIRST sample
        // takes this path, so nothing below can fire for ground already covered.
        guard hasSeededProgress else {
            hasSeededProgress = true
            lastMileCompleted = Int(sample.distance)
            lastMileClock = sample.raceClock
            lastIntervalMark = sample.distance
            return
        }

        // A lead CHANGE is the most useful thing to hear, so it outranks
        // everything else — while there is still a race to lead.
        if isRacing, let delta = sample.delta {
            // Under 2 seconds either way is inside the noise — calling it a
            // lead would have the coach flip-flopping every few strides.
            let ahead = delta >= 2
            let behind = delta <= -2
            if ahead || behind {
                if let was = wasAhead, was != ahead {
                    say(
                        ahead
                            ? "You're ahead of \(ghostName) by \(seconds(delta)). \(holdLine(sample))"
                            : "\(ghostName.capitalizedFirst) is up by \(seconds(delta)). \(chaseLine(sample))",
                        urgency: .high
                    )
                    wasAhead = ahead
                    return
                }
                if wasAhead == nil { wasAhead = ahead }
            }
        }

        // A completed mile is the headline of any run, so it is the one line
        // allowed past the floor: it carries two numbers you can't reconstruct
        // later (that mile's split, and the average it moved).
        if let mileLine = mileSplitLine(sample) {
            say(mileLine, urgency: .high, force: true)
            return
        }

        // Fractions of the TARGET, not of a mile — over a 5K the useful
        // halfway is 1.55 miles, and it's the one a there-and-back turns on.
        if let milestoneLine = milestoneLine(sample) {
            say(milestoneLine, urgency: .high)
            return
        }

        // Crossing between ahead / on / behind the goal pace. Hysteresis in
        // `resolvedPaceState` is what keeps this from narrating every stride.
        if let stateLine = paceStateLine(sample) {
            say(stateLine, urgency: .high)
            return
        }

        // The metronome: where you are and how fast, every N miles.
        if let intervalLine = intervalLine(sample) {
            say(intervalLine, urgency: .normal)
            return
        }

        // Effort. This is the line that makes it a coach rather than a
        // scoreboard, and it's the one that needs a real pace derivative —
        // silence is correct when `recentPace` is nil.
        if isRacing, let delta = sample.delta, let effort = effortLine(sample) {
            say(effort, urgency: closeRace(delta) ? .high : .normal)
        }
    }

    // MARK: - Lines

    /// "Mile 2. 8 oh 5. Average 8 oh 9."
    ///
    /// Fires on the whole mile only, and re-anchors the interval marker so the
    /// two lines can't stack up a stride apart.
    private func mileSplitLine(_ sample: Sample) -> String? {
        let mile = Int(sample.distance)
        guard mile > lastMileCompleted, mile >= 1 else { return nil }
        let split = sample.raceClock - lastMileClock
        lastMileCompleted = mile
        lastMileClock = sample.raceClock
        lastIntervalMark = Double(mile)
        // A split needs a clock that actually ran. A workout adopted mid-run,
        // or a mile crossed while the clock was frozen, has nothing to report.
        guard split > 1, let average = sample.averagePace else { return nil }
        return "Mile \(mile). \(clockWords(split)). Average \(paceWords(average))."
    }

    /// Quarter / half / three-quarter / last stretch, as fractions of the
    /// target. Only the halfway line fires when there's no ghost — the others
    /// are race furniture, and a plain run doesn't need a countdown.
    private func milestoneLine(_ sample: Sample) -> String? {
        for milestone in Self.milestones {
            let at = milestone.fraction * targetDistance
            guard sample.distance >= at else { continue }
            guard !firedMilestones.contains(milestone.id) else { continue }
            guard isRacing || milestone.id == "half" else { continue }
            firedMilestones.insert(milestone.id)
            if milestone.id == "half" {
                // The turnaround cue is the whole reason this one is spoken on
                // a plain run: an out-and-back has to know when to turn.
                let head = "Half way. \(milesSpoken(sample.distance)). Turn around if you're heading back."
                return isRacing ? "\(head) \(standing(sample.delta))" : head
            }
            return "\(milestone.label) \(standing(sample.delta)) \(chaseLine(sample))"
        }
        return nil
    }

    /// Announce only TRANSITIONS, and only once the run is long enough for an
    /// average to mean anything.
    private func paceStateLine(_ sample: Sample) -> String? {
        guard let goalPace, let average = sample.averagePace else { return nil }
        guard sample.distance >= 0.25 else { return nil }
        let resolved = resolvedPaceState(average: average, goal: goalPace)
        guard resolved != paceState else { return nil }
        paceState = resolved
        return resolved.spoken
    }

    /// Dead band plus hysteresis: inside 6 seconds a mile is "on pace", and it
    /// takes 10 to claim a side. Without the gap between those two numbers a
    /// runner hovering on the boundary gets narrated every few strides.
    private func resolvedPaceState(average: Double, goal: Double) -> PaceState {
        let drift = average - goal
        if drift <= -10 { return .ahead }
        if drift >= 10 { return .behind }
        if abs(drift) <= 6 { return .on }
        return paceState ?? .on
    }

    /// "You're at 1.25 miles, running at 8 12 pace."
    ///
    /// Prefers the recent-pace derivative — that's the number that answers "am
    /// I running well RIGHT NOW" — and falls back to the average rather than
    /// going silent, since the whole line is about where you are.
    private func intervalLine(_ sample: Sample) -> String? {
        let interval = Self.intervalMiles
        guard interval > 0 else { return nil }
        guard sample.distance >= lastIntervalMark + interval else { return nil }
        // Snap to the interval grid rather than to where the tick happened to
        // land, or a slow GPS second permanently offsets every later call.
        lastIntervalMark = (sample.distance / interval).rounded(.down) * interval
        guard let pace = sample.recentPace ?? sample.averagePace else { return nil }
        return "You're at \(milesSpoken(sample.distance)), running at \(paceWords(pace))."
    }

    /// Fading or holding, judged against what it currently takes to win.
    ///
    /// Only speaks when the gap is big enough to act on: telling someone
    /// they're two seconds per mile off is noise, and being told to push when
    /// you're already pushing is worse than silence.
    private func effortLine(_ sample: Sample) -> String? {
        guard let recent = sample.recentPace, let required = sample.requiredPace
        else { return nil }
        // Enough of the target is left that a correction is still possible.
        let progress = sample.distance / targetDistance
        guard progress >= 0.15, progress <= 0.92 else { return nil }

        let drift = recent - required
        if drift > 20 {
            return "You're slipping. \(paceWords(required)) to take it back."
        }
        if drift < -20, (sample.delta ?? 0) > 0 {
            return "That's the pace. You're pulling away."
        }
        return nil
    }

    /// What it takes from here, when that's still a real question.
    private func chaseLine(_ sample: Sample) -> String {
        guard let required = sample.requiredPace else { return "" }
        return "\(paceWords(required)) to win."
    }

    private func holdLine(_ sample: Sample) -> String {
        guard sample.requiredPace != nil else { return "" }
        return "Hold it."
    }

    /// A race decided by a handful of seconds deserves more talk than a rout.
    private func closeRace(_ delta: TimeInterval) -> Bool { abs(delta) < 6 }

    /// The verdict, spoken once. A loss stays silent by design.
    ///
    /// Ends the RACE and nothing else: the coach keeps calling splits and pace
    /// for as long as the workout runs, which is what makes a goal pace set
    /// over one mile still useful on mile four.
    func finish(won: Bool, marginSeconds: TimeInterval) {
        guard Self.isEnabled, isRacing else { return }
        isRacing = false
        wasAhead = nil
        guard won else { return }
        say("You beat \(ghostName) by \(seconds(marginSeconds)). Nice.", force: true)
    }

    func stop() {
        isRacing = false
        isActive = false
        firedMilestones = []
        wasAhead = nil
        hasSeededProgress = false
        lastMileCompleted = 0
        lastMileClock = 0
        lastIntervalMark = 0
        paceState = nil
        goalPace = nil
        synthesizer.stopSpeaking(at: .immediate)
        DispatchQueue.main.async { self.lastLine = nil }
        deactivateSession()
    }

    // MARK: - Lines

    private struct Milestone {
        let id: String
        let fraction: Double
        let label: String
    }

    private static let milestones: [Milestone] = [
        Milestone(id: "quarter", fraction: 0.25, label: "Quarter of the way."),
        Milestone(id: "half", fraction: 0.5, label: "Half way."),
        Milestone(id: "threequarter", fraction: 0.75, label: "Three quarters."),
        Milestone(id: "last", fraction: 0.9, label: "Last stretch."),
    ]

    private func standing(_ delta: TimeInterval?) -> String {
        guard let delta else { return "" }
        if delta >= 2 { return "\(seconds(delta)) ahead." }
        if delta <= -2 { return "\(seconds(delta)) behind." }
        return "Dead even."
    }

    /// "8 oh 5" — spoken, so the synthesizer reads it as a time rather than
    /// two numbers.
    private func clockWords(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded()))
        let minutes = whole / 60
        let secs = whole % 60
        // Spoken bare (a mile split), so this one has to be plural-correct:
        // "Mile 2. 8 minutes." `paceWords` never routes an exact-minute value
        // here — it has its own "8 minute pace" phrasing — so the two can't
        // disagree.
        if secs == 0 { return "\(minutes) minute\(minutes == 1 ? "" : "s")" }
        return "\(minutes) \(secs < 10 ? "oh " : "")\(secs)"
    }

    /// "8:40 pace", spoken.
    private func paceWords(_ secondsPerMile: Double) -> String {
        let whole = max(0, Int(secondsPerMile.rounded()))
        if whole % 60 == 0 { return "\(whole / 60) minute pace" }
        return "\(clockWords(secondsPerMile)) pace"
    }

    /// "1.25 miles" / "3 miles" — trailing zeros are noise to a synthesizer.
    private func milesSpoken(_ miles: Double) -> String {
        let rounded = (miles * 100).rounded() / 100
        if rounded == rounded.rounded() {
            let whole = Int(rounded)
            return "\(whole) mile\(whole == 1 ? "" : "s")"
        }
        return String(format: "%.2f miles", rounded)
    }

    private func seconds(_ value: TimeInterval) -> String {
        let whole = max(1, Int(abs(value).rounded()))
        return whole == 1 ? "1 second" : "\(whole) seconds"
    }

    // MARK: - Speech

    private func say(_ line: String, urgency: Urgency = .normal, force: Bool = false) {
        guard Self.isEnabled else { return }
        if !force, Date().timeIntervalSince(lastSpokeAt) < urgency.floor {
            return
        }
        lastSpokeAt = Date()
        DispatchQueue.main.async { self.lastLine = line }

        activateSession()
        let utterance = AVSpeechUtterance(string: line)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    /// Activated only around an utterance. `.duckOthers` lowers music instead
    /// of stopping it; `.mixWithOthers` keeps anything else playing alive.
    ///
    /// NOTE: for this to be audible with the phone LOCKED — i.e. for most of a
    /// real run — the app target needs `audio` in `UIBackgroundModes`. Without
    /// it, iOS silences the session on background and the coach only speaks
    /// while the screen is on.
    private func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            // Never let audio setup break a workout — the on-screen line still
            // lands, which is the part that always works.
            print("[GhostCoach] audio session failed: \(error)")
        }
    }

    private func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Deactivation failing just means music stays ducked a moment
            // longer; not worth surfacing.
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        // Hand the audio back so the user's music comes straight back up.
        deactivateSession()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        deactivateSession()
    }
}

private extension String {
    /// "your best" → "Your best", for a line that starts with the ghost's name.
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
