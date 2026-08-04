import AVFoundation
import Foundation

/// The voice in your ear during a ghost race.
///
/// It exists because the delta chip is unreadable while you're actually
/// running: the phone is in a pocket or a strap, and the one thing you want to
/// know — am I ahead or behind — is the one thing you can't check without
/// breaking stride. So the race says it out loud.
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

    private var ghostName = "your ghost"
    private var isRacing = false
    private var lastSpokeAt = Date.distantPast
    private var firedMilestones: Set<String> = []
    /// Nil until the first meaningful delta — the first few steps are noise.
    private var wasAhead: Bool?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Lifecycle

    func start(ghostName: String, isRun: Bool, ghostSeconds: Double) {
        guard Self.isEnabled else { return }
        self.ghostName = ghostName
        isRacing = true
        lastSpokeAt = .distantPast
        firedMilestones = []
        wasAhead = nil
        // The brief. A target in the abstract is hard to run to; a quarter
        // split is a number you can actually check yourself against.
        let quarter = ghostSeconds / 4
        say(
            "Racing \(ghostName). \(BestEffortStore.formatSeconds(ghostSeconds)) "
                + "for the mile — \(BestEffortStore.formatSeconds(quarter)) a quarter.",
            force: true
        )
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
        /// Seconds ahead(+)/behind(−), the SAME figure the chip renders.
        let delta: TimeInterval
        /// The ghost's mile time.
        let ghostSeconds: Double
        /// Pace over roughly the last minute, seconds/mile. Nil when the
        /// runner has gone quiet — the coach must then say nothing about
        /// effort rather than guess.
        let recentPace: Double?

        /// Seconds per mile needed over what's left to finish level with the
        /// ghost. Pure arithmetic — no curve lookup, because the finish line
        /// is a fixed distance and the ghost's total is a fixed time.
        var requiredPace: Double? {
            let remaining = 1.0 - distance
            guard remaining > 0.02 else { return nil }
            let budget = ghostSeconds - raceClock
            guard budget > 0 else { return nil }
            return budget / remaining
        }
    }

    /// Called from the tracker's existing 1 Hz tick — no timer of its own.
    func update(_ sample: Sample) {
        guard Self.isEnabled, isRacing else { return }
        let delta = sample.delta
        // Under 2 seconds either way is inside the noise — calling it a lead
        // would have the coach flip-flopping every few strides.
        let ahead = delta >= 2
        let behind = delta <= -2

        // A lead CHANGE is the most useful thing to hear, so it outranks
        // everything else.
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

        // Distance milestones — each fires once, with the standing and, when
        // it's known, what it now takes.
        for milestone in Self.milestones where sample.distance >= milestone.at {
            guard !firedMilestones.contains(milestone.id) else { continue }
            firedMilestones.insert(milestone.id)
            say("\(milestone.label) \(standing(delta)) \(chaseLine(sample))", urgency: .high)
            return
        }

        // Effort. This is the line that makes it a coach rather than a
        // scoreboard, and it's the one that needs a real pace derivative —
        // silence is correct when `recentPace` is nil.
        if let effort = effortLine(sample) {
            say(effort, urgency: closeRace(delta) ? .high : .normal)
        }
    }

    /// Fading or holding, judged against what it currently takes to win.
    ///
    /// Only speaks when the gap is big enough to act on: telling someone
    /// they're two seconds per mile off is noise, and being told to push when
    /// you're already pushing is worse than silence.
    private func effortLine(_ sample: Sample) -> String? {
        guard let recent = sample.recentPace, let required = sample.requiredPace
        else { return nil }
        // Enough of the mile is left that a correction is still possible.
        guard sample.distance >= 0.15, sample.distance <= 0.92 else { return nil }

        let drift = recent - required
        if drift > 20 {
            return "You're slipping. \(paceWords(required)) to take it back."
        }
        if drift < -20, sample.delta > 0 {
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
    func finish(won: Bool, marginSeconds: TimeInterval) {
        guard Self.isEnabled, isRacing else { return }
        isRacing = false
        guard won else { return }
        say("You beat \(ghostName) by \(seconds(marginSeconds)). Nice.", force: true)
    }

    func stop() {
        isRacing = false
        firedMilestones = []
        wasAhead = nil
        synthesizer.stopSpeaking(at: .immediate)
        DispatchQueue.main.async { self.lastLine = nil }
        deactivateSession()
    }

    // MARK: - Lines

    private struct Milestone {
        let id: String
        let at: Double
        let label: String
    }

    private static let milestones: [Milestone] = [
        Milestone(id: "quarter", at: 0.25, label: "Quarter mile."),
        Milestone(id: "half", at: 0.5, label: "Half way."),
        Milestone(id: "threequarter", at: 0.75, label: "Three quarters."),
        Milestone(id: "last", at: 0.9, label: "Last stretch."),
    ]

    private func standing(_ delta: TimeInterval) -> String {
        if delta >= 2 { return "\(seconds(delta)) ahead." }
        if delta <= -2 { return "\(seconds(delta)) behind." }
        return "Dead even."
    }

    /// "8:40 pace" — spoken, so the synthesizer reads it as a time rather than
    /// two numbers.
    private func paceWords(_ secondsPerMile: Double) -> String {
        let whole = max(0, Int(secondsPerMile.rounded()))
        let minutes = whole / 60
        let secs = whole % 60
        if secs == 0 { return "\(minutes) minute pace" }
        return "\(minutes) \(secs < 10 ? "oh " : "")\(secs) pace"
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
