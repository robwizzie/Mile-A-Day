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

    /// Hard floor between lines. Three quarter-mile callouts plus a lead change
    /// on a nine-minute mile is about as much as anyone wants.
    private static let minSecondsBetweenLines: TimeInterval = 25

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

    func start(ghostName: String, isRun: Bool) {
        guard Self.isEnabled else { return }
        self.ghostName = ghostName
        isRacing = true
        lastSpokeAt = .distantPast
        firedMilestones = []
        wasAhead = nil
        say("Racing \(ghostName). \(isRun ? "Run" : "Walk") strong.", force: true)
    }

    /// Called from the tracker's existing 1 Hz tick — no timer of its own.
    ///
    /// `delta` is the SAME frozen-at-the-crossing figure the chip shows
    /// (positive = ahead), so the voice can never contradict the screen.
    func update(distance: Double, delta: TimeInterval?) {
        guard Self.isEnabled, isRacing, let delta else { return }
        // Under 2 seconds either way is inside the noise — calling it a lead
        // would have the coach flip-flopping every few strides.
        let ahead = delta >= 2
        let behind = delta <= -2

        // A lead CHANGE is the most useful thing to hear, so it outranks the
        // distance milestones and is checked first.
        if ahead || behind {
            if let was = wasAhead, was != ahead {
                say(
                    ahead
                        ? "You're ahead of \(ghostName) by \(seconds(delta))."
                        : "\(ghostName.capitalizedFirst) is up by \(seconds(delta)). Time to push."
                )
                wasAhead = ahead
                return
            }
            if wasAhead == nil { wasAhead = ahead }
        }

        for milestone in Self.milestones where distance >= milestone.at {
            guard !firedMilestones.contains(milestone.id) else { continue }
            firedMilestones.insert(milestone.id)
            say("\(milestone.label) \(standing(delta))")
            return
        }
    }

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

    private func seconds(_ value: TimeInterval) -> String {
        let whole = max(1, Int(abs(value).rounded()))
        return whole == 1 ? "1 second" : "\(whole) seconds"
    }

    // MARK: - Speech

    private func say(_ line: String, force: Bool = false) {
        guard Self.isEnabled else { return }
        if !force, Date().timeIntervalSince(lastSpokeAt) < Self.minSecondsBetweenLines {
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
