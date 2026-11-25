import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

// Run Plans v2 — the AI Coach on Apple's models (build spec §1).
//
// Apple's cloud model (Private Cloud Compute, iOS 27) makes plan decisions
// (plan build, adjust, weekly review, chat); the on-device
// `SystemLanguageModel` writes short check-in replies, and stands in for the
// cloud model when the cloud one can't be used. The model DECIDES; code
// MEASURES AND CHECKS: every number comes from a server tool
// (`/coach/options`, `/coach/build-day`, `/coach/validate`, `/coach/estimate`)
// and every proposal goes to `POST /proposals`, which validates it. Each call
// is logged to `POST /coach/calls` for the overseer.
//
// API names verified against Apple's FoundationModels docs (Nov 25 2026):
// `PrivateCloudComputeLanguageModel` (iOS 27, `quotaUsage`,
// `Error.quotaLimitReached`), `LanguageModelSession(model:tools:instructions:)`,
// `respond(to:generating:)`, `Tool` (`Output: PromptRepresentable`),
// `@Generable` / `@Guide`. The PCC pieces sit behind `compiler(>=6.4)` so an
// older Xcode still type-checks (they compile to nothing there).

@MainActor
final class AppleCoach {
    static let shared = AppleCoach()

    /// The PCC model needs Apple's MANAGED entitlement
    /// `com.apple.developer.private-cloud-compute` (requested at
    /// developer.apple.com/private-cloud-compute). Without it `availability`
    /// still says `.available` and the first prompt is a FATAL ERROR, so it
    /// stays off until the entitlement is on the App ID and in
    /// `Mile A Day.entitlements`. Off = the on-device model does every job.
    static let privateCloudComputeEntitled = false

    private var running = false
    private var lastPass: [String: Date] = [:]
    private let limitDayKey = "runPlanV2AppleLimitDay"
    private let limitToldKey = "runPlanV2AppleLimitToldDay"

    // MARK: Availability

    /// True when this phone can run Apple's model right now (either one).
    static var isAvailable: Bool { cloudAvailable || onDeviceAvailable }

    static var onDeviceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static var cloudAvailable: Bool {
        guard privateCloudComputeEntitled else { return false }
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, *) {
            return AppleCloudModel.shared.isAvailable
        }
        #endif
        return false
    }

    /// Why the AI Coach can't run here, for the formula-tier card.
    static var unavailableReason: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return String(localized: "AI Coach is ready.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return String(localized: "Turn on Apple Intelligence in Settings to use the AI Coach.")
            case .unavailable(.modelNotReady):
                return String(localized: "Apple Intelligence is still getting ready on this iPhone. Check back later.")
            default:
                return String(localized: "AI Coach needs an iPhone with Apple Intelligence.")
            }
        }
        #endif
        return String(localized: "AI Coach needs an iPhone with Apple Intelligence.")
    }

    /// Apple's daily allowance ran out today: plan-level jobs follow the
    /// formula until tomorrow.
    var dailyLimitHitToday: Bool {
        UserDefaults.standard.string(forKey: limitDayKey) == RunPlanV2Date.todayKey()
    }

    /// Offers Apple's iCloud+ upgrade when the allowance can grow.
    var canSuggestMoreAllowance: Bool {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, *), Self.privateCloudComputeEntitled {
            return AppleCloudModel.shared.limitIncreaseAvailable
        }
        #endif
        return false
    }

    func showMoreAllowance() {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, *), Self.privateCloudComputeEntitled {
            AppleCloudModel.shared.showLimitIncrease()
        }
        #endif
    }

    // MARK: Jobs

    /// After a run / first open / nightly: read the plan, propose changes.
    /// Monday's first open is the weekly review.
    func runAdjustPass(trigger: RunPlanV2AICallTrigger) async {
        let store = RunPlanV2Store.shared
        guard store.coachTier == .apple, store.hasPlan, !dailyLimitHitToday, !running else { return }
        let key = "\(trigger.rawValue)|\(RunPlanV2Date.todayKey())"
        if let last = lastPass[key], Date().timeIntervalSince(last) < (trigger == .afterRun ? 600 : 6 * 3600) { return }
        lastPass[key] = Date()
        running = true
        defer { running = false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            let monday = cal.component(.weekday, from: Date()) == 2
            let kind: RunPlanV2AICallKind = (trigger == .firstOpen && monday) ? .weeklyReview : .adjust
            await AppleCoachEngine().adjust(kind: kind, trigger: trigger)
        }
        #endif
    }

    /// Check-in before the run: a tailored proposal for today (or nil to
    /// keep the formula's) and Flamey's one-line reply.
    func checkIn(_ checkin: RunPlanV2CheckinRequest, checkinId: String?,
                 formulaProposal: RunPlanV2Proposal?) async -> (proposal: RunPlanV2Proposal?, reply: String?) {
        guard Self.isAvailable else { return (nil, nil) }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await AppleCoachEngine().checkIn(checkin, formulaProposal: formulaProposal)
        }
        #endif
        return (nil, nil)
    }

    /// Ask Flamey (plan home chat). Returns Flamey's reply; a change he
    /// suggests arrives in the store as a pending proposal.
    func ask(_ message: String, history: [RunPlanChatMessage]) async -> String? {
        guard Self.isAvailable else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await AppleCoachEngine().chat(message, history: history)
        }
        #endif
        return nil
    }

    /// Plan build at setup: the formula draft, reviewed and adjusted for the
    /// first two weeks, one week per step (fits the 32K context). Nil = use
    /// the formula draft as it is.
    func buildInitialDays(request: RunPlanV2CreateRequest, preview: RunPlanV2PlanWithDays,
                          profile: RunPlanV2FitnessProfile?) async -> [RunPlanV2InitialDay]? {
        guard Self.isAvailable, !dailyLimitHitToday else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await AppleCoachEngine().buildPlan(request: request, preview: preview, profile: profile)
        }
        #endif
        return nil
    }

    /// Flamey's post-run summary in his own words (replaces a template one).
    func writePostRunSummary(day: RunPlanV2Day, grade: RunPlanV2Grade) async -> String? {
        guard Self.isAvailable, !dailyLimitHitToday else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await AppleCoachEngine().postRunSummary(day: day, grade: grade)
        }
        #endif
        return nil
    }

    // MARK: Quota

    func noteDailyLimitHit() {
        let today = RunPlanV2Date.todayKey()
        UserDefaults.standard.set(today, forKey: limitDayKey)
        guard UserDefaults.standard.string(forKey: limitToldKey) != today else { return }
        UserDefaults.standard.set(today, forKey: limitToldKey)
        RunPlanV2Store.shared.noteCoachFallback(String(localized:
            "You've used today's Apple Intelligence allowance, so your plan follows the formula until tomorrow."))
    }
}

/// One line of the plan home chat.
struct RunPlanChatMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable { case user, flamey }
    let id = UUID()
    let role: Role
    let text: String
}

// MARK: - Call log

/// Collects what one model call did, then uploads it (`POST /coach/calls`).
final class AppleCoachCallRecorder: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var tools: [RunPlanV2ToolCallLog] = []
    private var toolText: [String] = []
    let id = UUID().uuidString.lowercased()
    let started = Date()

    func tool(_ name: String, ok: Bool, summary: String) {
        lock.lock(); defer { lock.unlock() }
        tools.append(RunPlanV2ToolCallLog(name: name, ok: ok))
        toolText.append("[\(name)] \(summary.prefix(600))")
    }

    var toolCalls: [RunPlanV2ToolCallLog] { lock.lock(); defer { lock.unlock() }; return tools }
    var toolTranscript: String { lock.lock(); defer { lock.unlock() }; return toolText.joined(separator: "\n") }

    func upload(kind: RunPlanV2AICallKind, trigger: RunPlanV2AICallTrigger, model: String, input: String,
                output: String, error: String?, dailyLimitHit: Bool, proposalIds: [String],
                tokensIn: Int? = nil, tokensOut: Int? = nil) async {
        let trimmedOutput = toolTranscript.isEmpty ? output : output + "\n--- tools ---\n" + toolTranscript
        let call = RunPlanV2AICallLog(
            client_call_id: id, provider: "apple", kind: kind.rawValue, trigger: trigger.rawValue,
            model: model, started_at: RunPlanV2Date.timestamp(started),
            latency_ms: Int(Date().timeIntervalSince(started) * 1000),
            input: String(input.prefix(60_000)), output: String(trimmedOutput.prefix(60_000)),
            tool_calls: toolCalls, tokens_in: tokensIn, tokens_out: tokensOut, error: error,
            daily_limit_hit: dailyLimitHit, proposal_ids: proposalIds)
        _ = try? await RunPlanV2Service.uploadCalls([call])
    }
}

// MARK: - Prompt text (shared, no FoundationModels types)

enum AppleCoachPrompt {
    static let instructions = """
    You are Flamey, the friendly flame who coaches runners in the Mile A Day app. You design and adjust one \
    runner's training plan. Mile A Day users keep a daily streak: every day needs 1 mile or 10,000 steps, \
    so a "walk day" is a day without a run, not a day off.

    How you work:
    - You decide; the app's tools compute. Never state a pace, distance, heart rate or time you did not read \
    in the context or get back from a tool. Use get_options, build_day and validate_changes for numbers.
    - Every change is a proposal the runner approves. Only propose when it clearly helps; otherwise propose \
    nothing.
    - Changes to today stay small (about 10% distance or pace). Bigger changes go on later days.
    - Hard rules (never break): no run more than 10% longer than the longest run of the past 30 days \
    (spike limit by date in the context); never two hard days in a row.
    - Conventions you may break only with a one-sentence deviation_reason: weekly miles up at most 10% or \
    2 mi, a cutback week every 4th week, about 80% of running easy.
    - Missed easy run: drop it. Missed key session: move it only with an easy day on each side, else drop it.
    - Never give medical, injury, illness, medication or diet advice. Pain and illness are the runner's call.
    - Write like a coach texting a friend: short, plain, warm, one sentence of reason. No emoji, no hashtags.
    """

    static let kinds = ["easy", "long", "tempo", "intervals", "race", "calibration", "walk"]

    /// One compact line per day: date, weekday, kind, miles, title, flags, status.
    static func line(_ d: RunPlanV2Day) -> String {
        var parts = [d.local_date ?? "?", d.date.map { $0.formatted(.dateTime.weekday(.abbreviated)) } ?? "",
                     d.dayKind.rawValue]
        if !d.isWalk { parts.append(String(format: "%.2f mi", d.miles)) }
        if let t = d.title, !t.isEmpty { parts.append("\"\(t)\"") }
        var flags: [String] = []
        if d.isHard { flags.append("hard") }
        if d.isKey { flags.append("key") }
        if d.isFlex { flags.append("flex") }
        if !flags.isEmpty { parts.append("[\(flags.joined(separator: ","))]") }
        if let s = d.status { parts.append("status=\(s)") }
        if let c = d.completed, let mi = c.distance_mi {
            var done = String(format: "ran %.2f mi", mi)
            if let p = c.avg_pace_s { done += " at \(pace(p))/mi" }
            parts.append(done)
        }
        if let g = d.grade?.score { parts.append("grade \(g)") }
        if let w = d.workSegments.first {
            var seg = "work:"
            if let r = w.reps { seg += " \(r)x" }
            if let mi = w.distance_mi { seg += String(format: " %.2f mi", mi) }
            if let s = w.duration_s { seg += " \(s)s" }
            if let p = w.target_pace_s { seg += " at \(pace(p))/mi" }
            if let lo = w.hr_low, let hi = w.hr_high { seg += " HR \(lo)-\(hi)" }
            parts.append(seg)
        }
        return parts.joined(separator: " ")
    }

    static func pace(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

    /// The compact context the model reads. `wide` = the cloud model's 32K;
    /// otherwise the on-device model's few thousand tokens.
    static func context(_ c: RunPlanV2CoachContext, wide: Bool) -> String {
        var out: [String] = []
        out.append("Today: \(c.today ?? RunPlanV2Date.todayKey())")
        if let p = c.plan {
            var goals: [String] = []
            for g in p.goals {
                switch g.goalType {
                case .distanceTime:
                    var s = "\(g.distance ?? "race")"
                    if let t = g.target_s { s += " target \(clock(t))" }
                    if let n = g.current_s { s += " (now ~\(clock(n)))" }
                    goals.append(s)
                case .justImprove: goals.append("just improve")
                case .burnCalories: goals.append("burn calories (\(g.weekly_minutes ?? 150) min/week)")
                }
            }
            out.append("Goals: \(goals.joined(separator: "; "))")
            out.append("Plan: week \(p.week_index ?? 1), phase \(p.phase ?? "?"), \(p.runs_per_week ?? 0) runs/week, "
                       + "difficulty \(p.difficulty ?? 2)/4, walk days \(p.walk_mode ?? "built_in"), "
                       + "week target \(String(format: "%.1f", p.weekly_target_mi ?? 0)) mi, "
                       + "hard sessions/week \(p.hard_sessions_per_week ?? 0)"
                       + (p.target_date.map { ", race date \($0)" } ?? ""))
            if let notes = p.coach_notes, !notes.isEmpty {
                out.append("Runner's notes for the coach: \(notes.prefix(wide ? 2000 : 400))")
            }
        }
        if let f = c.fitness_profile {
            var s = "Fitness:"
            if let v = f.vdot { s += " VDOT \(v)" }
            if let e = f.easy_pace_s { s += ", easy pace \(pace(e))/mi" }
            if let z = f.zone2_pace_s, let h = f.zone2_hr { s += ", zone 2 \(pace(z))/mi at \(h) bpm" }
            if let w = f.weekly_miles_4w { s += ", \(w) mi/week lately" }
            if let l = f.longest_run_30d_mi { s += ", longest run 30d \(l) mi" }
            if let t = f.treadmill_fraction { s += ", treadmill share \(Int(t * 100))%" }
            if f.hasHeartRate == false { s += ", no heart rate (describe effort, not zones)" }
            out.append(s)
        }
        if let pc = c.paces {
            var s = "Paces (s/mi):"
            if let e = pc.easy_s, e.count == 2 { s += " easy \(pace(e[0]))-\(pace(e[1]))" }
            if let t = pc.threshold_s { s += ", threshold \(pace(t))" }
            if let i = pc.interval_s { s += ", interval \(pace(i))" }
            out.append(s)
        }
        if let ceiling = c.hr?.easy_ceiling { out.append("Easy HR ceiling: \(ceiling) bpm") }
        if let l = c.limits {
            var s = "Limits:"
            if let w = l.week_cap_mi { s += " week cap \(w) mi" }
            if let spikes = l.spike_limit_mi_by_date {
                let next = spikes.sorted { $0.key < $1.key }.prefix(wide ? 14 : 7)
                s += ", spike limit " + next.map { "\($0.key)≤\(String(format: "%.1f", $0.value))" }.joined(separator: " ")
            }
            out.append(s)
        }
        if let sig = c.signals {
            var s: [String] = []
            if let d = sig.days_since_last_run { s.append("days since last run \(d)") }
            if !sig.missed_key_sessions.isEmpty { s.append("missed key sessions \(sig.missed_key_sessions.joined(separator: ","))") }
            if sig.fatigue_flag == true { s.append("FATIGUE FLAG") }
            if let r = sig.resting_hr_delta { s.append("resting HR delta \(r)") }
            if sig.hrv_below_baseline == true { s.append("HRV below baseline") }
            if let a = sig.acwr { s.append("ACWR \(a)") }
            if let h = sig.hard_efforts_last_6d { s.append("hard efforts last 6d \(h)") }
            if let e = sig.low_energy_streak, e > 0 { s.append("low-energy check-ins in a row \(e)") }
            if sig.walk_day_earned == true { s.append("walk day earned") }
            if sig.overdoing_it == true { s.append("overdoing it") }
            if !s.isEmpty { out.append("Signals: " + s.joined(separator: "; ")) }
        }
        let past = wide ? c.past : Array(c.past.suffix(5))
        if !past.isEmpty { out.append("Recent days:\n" + past.map(line).joined(separator: "\n")) }
        let ahead = wide ? c.ahead : Array(c.ahead.prefix(8))
        if !ahead.isEmpty { out.append("Coming days:\n" + ahead.map(line).joined(separator: "\n")) }
        if !c.checkins.isEmpty {
            let cs = c.checkins.suffix(wide ? 7 : 2).map { ci in
                "\(ci.local_date ?? "?"): energy \(ci.energy.map(String.init) ?? "-")/10, soreness \(ci.soreness.map(String.init) ?? "-")/10"
                    + (ci.text.map { " \"\($0.prefix(200))\"" } ?? "")
            }
            out.append("Check-ins:\n" + cs.joined(separator: "\n"))
        }
        let pending = c.pending_proposals + c.formula_proposals
        if !pending.isEmpty {
            out.append("Already proposed (waiting for the runner; don't repeat):\n"
                       + pending.prefix(5).map { "\($0.title ?? $0.kind ?? "change"): \($0.reason ?? "")" }.joined(separator: "\n"))
        }
        let declined = c.recent_decisions.filter { $0.status == "declined" }
        if !declined.isEmpty {
            out.append("Recently declined by the runner: " + declined.prefix(5).compactMap(\.kind).joined(separator: ", "))
        }
        if wide, let rules = c.rules, !rules.isEmpty { out.append("Training rules:\n\(rules.prefix(6000))") }
        return out.joined(separator: "\n")
    }

    static func clock(_ s: Int) -> String {
        s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : pace(s)
    }

    static func violations(_ e: RunPlanV2Error) -> String? {
        switch e {
        case .hardRuleViolation(let v):
            return "The app rejected that change (hard rule): " + v.map { "\($0.local_date ?? "") \($0.rule ?? ""): \($0.message ?? "")" }.joined(separator: "; ")
                + ". Pick something inside the limits, or propose nothing."
        case .deviationReasonRequired(let d):
            return "That change breaks a convention: " + d.map { "\($0.rule ?? ""): \($0.message ?? "")" }.joined(separator: "; ")
                + ". Give a one-sentence deviation_reason, or change it to fit."
        default:
            return nil
        }
    }
}

#if canImport(FoundationModels)

// MARK: - Structured output

@available(iOS 26.0, *)
@Generable
struct CoachDaySpec {
    @Guide(description: "YYYY-MM-DD, today or later")
    var local_date: String
    @Guide(description: "Run kind", .anyOf(["easy", "long", "tempo", "intervals", "race", "calibration", "walk"]))
    var kind: String
    @Guide(description: "Total miles for easy, long, tempo, race and calibration days; 0 for intervals and walk")
    var distance_mi: Double
    @Guide(description: "Tempo only: miles at tempo pace; else 0")
    var work_mi: Double
    @Guide(description: "Intervals only: number of reps; else 0")
    var reps: Int
    @Guide(description: "Intervals only: miles per rep (0.25 = 400m); 0 if reps are timed")
    var rep_mi: Double
    @Guide(description: "Intervals only: seconds per rep when timed; else 0")
    var rep_s: Int
    @Guide(description: "Intervals only: recovery jog seconds; else 0")
    var recover_s: Int
    @Guide(description: "1.0 keeps the plan's paces; up to 1.15 slower, down to 0.85 faster")
    var pace_factor: Double

    var change: RunPlanV2DayChange {
        RunPlanV2DayChange(local_date: local_date, after: RunPlanV2DaySpec(
            kind: RunPlanV2DayKind(raw: kind),
            distanceMi: distance_mi > 0 ? distance_mi : nil,
            workMi: work_mi > 0 ? work_mi : nil,
            reps: reps > 0 ? reps : nil,
            repMi: rep_mi > 0 ? rep_mi : nil,
            repSeconds: rep_s > 0 ? rep_s : nil,
            recoverSeconds: recover_s > 0 ? recover_s : nil,
            paceFactor: (pace_factor > 0 && abs(pace_factor - 1) > 0.005) ? min(max(pace_factor, 0.85), 1.15) : nil))
    }
}

@available(iOS 26.0, *)
@Generable
struct CoachDayNote {
    @Guide(description: "YYYY-MM-DD, today or later")
    var local_date: String
    @Guide(description: "Flamey's note for that day, at most two short sentences, no numbers you didn't read")
    var note: String
}

@available(iOS 26.0, *)
@Generable
struct CoachDecision {
    @Guide(description: "true only if a change clearly helps the runner")
    var propose: Bool
    @Guide(description: "Short title, e.g. Easier Thursday")
    var title: String
    @Guide(description: "Why, one plain sentence the runner reads")
    var reason: String
    @Guide(description: "Proposal kind", .anyOf(["adjust", "missed_run", "return_from_break", "pace_update",
                                                  "walk_day_earned", "walk_day_needed", "weekly_review"]))
    var kind: String
    @Guide(description: "The changed days (empty when propose is false)", .maximumCount(7))
    var changes: [CoachDaySpec]
    @Guide(description: "Only if a convention is broken: one sentence why; else empty")
    var deviation_reason: String
    @Guide(description: "Notes for upcoming days (optional)", .maximumCount(3))
    var notes: [CoachDayNote]
}

@available(iOS 26.0, *)
@Generable
struct CheckinDecision {
    @Guide(description: "Flamey's reply to the runner, one or two short sentences")
    var reply: String
    @Guide(description: "true to suggest a different version of today's run")
    var propose: Bool
    @Guide(description: "Short question-style title, e.g. Make it 6 mi, keep the last 2 easy?")
    var title: String
    @Guide(description: "Why, one plain sentence")
    var reason: String
    @Guide(description: "Today's new run (when propose is true)")
    var today: CoachDaySpec
    @Guide(description: "Only if a convention is broken: one sentence why; else empty")
    var deviation_reason: String
}

@available(iOS 26.0, *)
@Generable
struct PlanWeekDecision {
    @Guide(description: "Days of this week to change from the draft (empty = keep the draft)", .maximumCount(7))
    var changes: [CoachDaySpec]
    @Guide(description: "Notes for this week's runs", .maximumCount(7))
    var notes: [CoachDayNote]
}

// MARK: - Tools (numbers come from the server)

@available(iOS 26.0, *)
struct GetOptionsTool: Tool {
    let recorder: AppleCoachCallRecorder
    let name = "get_options"
    let description = "Get computed, rule-checked options for one day: easier, shorter, longer, harder, swap_walk, move_key (needs to_date) or fit_time (needs minutes)."

    @Generable
    struct Arguments {
        @Guide(description: "YYYY-MM-DD")
        var local_date: String
        @Guide(description: "What to change", .anyOf(["easier", "shorter", "longer", "harder", "swap_walk", "move_key", "fit_time"]))
        var intent: String
        @Guide(description: "fit_time only: minutes available; else 0")
        var minutes: Int
        @Guide(description: "move_key only: YYYY-MM-DD to move to; else empty")
        var to_date: String
    }

    func call(arguments: Arguments) async throws -> String {
        let req = RunPlanV2OptionsRequest(
            today: RunPlanV2Date.todayKey(), local_date: arguments.local_date, intent: arguments.intent,
            minutes: arguments.minutes > 0 ? arguments.minutes : nil,
            to_date: arguments.to_date.isEmpty ? nil : arguments.to_date)
        do {
            let result = try await RunPlanV2Service.coachOptions(req)
            let text = result.options.enumerated().map { i, o in
                "\(i + 1). \(o.label ?? "option"): " + o.changes.map { c in
                    "\(c.local_date) \(c.after.kind) " + [c.after.distance_mi.map { String(format: "%.2f mi", $0) },
                                                          c.after.reps.map { "\($0) reps" }].compactMap { $0 }.joined(separator: " ")
                }.joined(separator: "; ") + (o.checks?.text.map { " (\($0))" } ?? "")
            }.joined(separator: "\n")
            recorder.tool(name, ok: true, summary: text)
            return text.isEmpty ? "No options for that day." : text
        } catch {
            recorder.tool(name, ok: false, summary: "\(error)")
            return "No options available (\((error as? RunPlanV2Error)?.message ?? "error"))."
        }
    }
}

@available(iOS 26.0, *)
struct BuildDayTool: Tool {
    let recorder: AppleCoachCallRecorder
    let name = "build_day"
    let description = "Compute a day from a spec: returns its segments, paces, heart-rate bands and any rule problems. Nothing is saved."

    @Generable
    struct Arguments {
        var day: CoachDaySpec
    }

    func call(arguments: Arguments) async throws -> String {
        let change = arguments.day.change
        do {
            let r = try await RunPlanV2Service.buildDay(localDate: change.local_date, day: change.after)
            var text = r.day.map(AppleCoachPrompt.line) ?? "Built."
            if !r.violations.isEmpty { text += "\nHard rule problems: " + r.violations.compactMap(\.message).joined(separator: "; ") }
            if !r.deviations.isEmpty { text += "\nConvention deviations: " + r.deviations.compactMap(\.message).joined(separator: "; ") }
            recorder.tool(name, ok: r.violations.isEmpty, summary: text)
            return text
        } catch {
            recorder.tool(name, ok: false, summary: "\(error)")
            return "Couldn't build that day (\((error as? RunPlanV2Error)?.message ?? "error"))."
        }
    }
}

@available(iOS 26.0, *)
struct ValidateTool: Tool {
    let recorder: AppleCoachCallRecorder
    let name = "validate_changes"
    let description = "Dry-run a set of day changes against the safety rules before proposing them."

    @Generable
    struct Arguments {
        @Guide(description: "The changed days", .maximumCount(7))
        var changes: [CoachDaySpec]
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            let r = try await RunPlanV2Service.validate(arguments.changes.map(\.change))
            var text = (r.ok ?? false) ? "OK." : "Not OK."
            if let t = r.checks?.text { text += " \(t)" }
            if !r.violations.isEmpty { text += "\nHard rule problems: " + r.violations.compactMap(\.message).joined(separator: "; ") }
            if !r.deviations.isEmpty { text += "\nConvention deviations (need a reason): " + r.deviations.compactMap(\.message).joined(separator: "; ") }
            recorder.tool(name, ok: r.ok ?? false, summary: text)
            return text
        } catch {
            recorder.tool(name, ok: false, summary: "\(error)")
            return "Couldn't validate (\((error as? RunPlanV2Error)?.message ?? "error"))."
        }
    }
}

@available(iOS 26.0, *)
struct EstimateTool: Tool {
    let recorder: AppleCoachCallRecorder
    let name = "race_estimate"
    let description = "The runner's current estimated race time for a distance, computed from their runs."

    @Generable
    struct Arguments {
        @Guide(description: "Distance", .anyOf(["mile", "5k", "10k", "half", "marathon"]))
        var distance: String
    }

    func call(arguments: Arguments) async throws -> String {
        do {
            let r = try await RunPlanV2Service.estimate(distance: arguments.distance)
            let text = r.estimate_s.map { "\(arguments.distance): about \(AppleCoachPrompt.clock($0)) (\(r.method ?? "estimate"))" }
                ?? "No estimate yet."
            recorder.tool(name, ok: r.estimate_s != nil, summary: text)
            return text
        } catch {
            recorder.tool(name, ok: false, summary: "\(error)")
            return "No estimate available."
        }
    }
}

/// Chat only: lets Flamey put a change in front of the runner. The server
/// validates it; the runner still decides.
@available(iOS 26.0, *)
struct ProposeChangeTool: Tool {
    let recorder: AppleCoachCallRecorder
    let proposals: ProposalBox
    let name = "propose_change"
    let description = "Suggest a plan change to the runner (they approve or decline it). Use only after the runner asks for a change."

    @Generable
    struct Arguments {
        @Guide(description: "Short title")
        var title: String
        @Guide(description: "Why, one plain sentence")
        var reason: String
        @Guide(description: "The changed days", .maximumCount(7))
        var changes: [CoachDaySpec]
        @Guide(description: "Only if a convention is broken: one sentence why; else empty")
        var deviation_reason: String
    }

    func call(arguments: Arguments) async throws -> String {
        let req = RunPlanV2ProposalRequest(
            today: RunPlanV2Date.todayKey(), source: "apple", kind: "adjust",
            title: String(arguments.title.prefix(80)), reason: String(arguments.reason.prefix(300)),
            goal_impact: nil, changes: arguments.changes.map(\.change),
            deviation_reason: arguments.deviation_reason.isEmpty ? nil : arguments.deviation_reason, ai_call_id: nil)
        do {
            let p = try await RunPlanV2Service.submitProposal(req)
            proposals.add(p)
            recorder.tool(name, ok: true, summary: p.title ?? "proposed")
            return "Proposed. The runner sees it on their plan and decides."
        } catch let e as RunPlanV2Error {
            recorder.tool(name, ok: false, summary: e.message)
            return AppleCoachPrompt.violations(e) ?? "Couldn't propose that (\(e.message))."
        }
    }
}

final class ProposalBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var items: [RunPlanV2Proposal] = []
    func add(_ p: RunPlanV2Proposal) { lock.lock(); items.append(p); lock.unlock() }
    var all: [RunPlanV2Proposal] { lock.lock(); defer { lock.unlock() }; return items }
}

// MARK: - The engine

@available(iOS 26.0, *)
@MainActor
struct AppleCoachEngine {
    enum Size { case big, small }

    private struct Model {
        let session: LanguageModelSession
        let name: String
        let wide: Bool
    }

    /// The cloud model for big jobs when it's usable; the on-device model
    /// otherwise (and for small jobs).
    private func session(_ size: Size, tools: [any Tool], instructions: String) -> Model? {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *), size == .big, AppleCoach.cloudAvailable, !AppleCoach.shared.dailyLimitHitToday {
            let s = LanguageModelSession(model: AppleCloudModel.shared.model, tools: tools, instructions: instructions)
            return Model(session: s, name: "apple-pcc", wide: true)
        }
        #endif
        guard AppleCoach.onDeviceAvailable else { return nil }
        let s = LanguageModelSession(model: SystemLanguageModel.default, tools: tools, instructions: instructions)
        return Model(session: s, name: "apple-on-device", wide: false)
    }

    /// The cloud model's daily allowance ran out.
    private func isQuotaError(_ error: Error) -> Bool {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *), let e = error as? PrivateCloudComputeLanguageModel.Error,
           case .quotaLimitReached = e {
            return true
        }
        #endif
        return false
    }

    private func tokens(_ response: Any) -> (Int?, Int?) {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            if let r = response as? LanguageModelSession.Response<CoachDecision> {
                return (r.usage.input.totalTokenCount, r.usage.output.totalTokenCount)
            }
            if let r = response as? LanguageModelSession.Response<String> {
                return (r.usage.input.totalTokenCount, r.usage.output.totalTokenCount)
            }
        }
        #endif
        return (nil, nil)
    }

    private func handleFailure(_ error: Error, recorder: AppleCoachCallRecorder, kind: RunPlanV2AICallKind,
                               trigger: RunPlanV2AICallTrigger, model: String, input: String) async {
        let quota = isQuotaError(error)
        if quota { AppleCoach.shared.noteDailyLimitHit() }
        await recorder.upload(kind: kind, trigger: trigger, model: model, input: input, output: "",
                              error: quota ? "daily_limit" : String(describing: error).prefix(500).description,
                              dailyLimitHit: quota, proposalIds: [])
    }

    // MARK: Adjust / weekly review

    func adjust(kind: RunPlanV2AICallKind, trigger: RunPlanV2AICallTrigger) async {
        guard let fetched = try? await RunPlanV2Service.coachContext() else { return }
        let ctx = fetched.0
        let recorder = AppleCoachCallRecorder()
        let tools: [any Tool] = [GetOptionsTool(recorder: recorder), BuildDayTool(recorder: recorder),
                                 ValidateTool(recorder: recorder), EstimateTool(recorder: recorder)]
        guard let m = session(.big, tools: tools, instructions: AppleCoachPrompt.instructions) else { return }
        let ask: String
        switch kind {
        case .weeklyReview:
            ask = "It's the start of a new week. Review last week against the plan and decide whether this week needs a change. Also write a short note for the next run."
        default:
            ask = trigger == .afterRun
                ? "A run just synced. Look at how it went against the plan and decide whether the coming days need a change. Write a note for the next run."
                : "Look at the plan as it stands this morning (missed runs, fatigue, how the runner is doing) and decide whether the coming days need a change."
        }
        let prompt = AppleCoachPrompt.context(ctx, wide: m.wide) + "\n\n" + ask
        do {
            var response = try await m.session.respond(to: prompt, generating: CoachDecision.self)
            var decision = response.content
            var proposalIds: [String] = []
            var lastError: String?
            if decision.propose, !decision.changes.isEmpty {
                for attempt in 0..<2 {
                    do {
                        let p = try await submit(decision, kind: kind)
                        proposalIds.append(p.id)
                        RunPlanV2Store.shared.absorb(p)
                        break
                    } catch let e as RunPlanV2Error {
                        lastError = e.message
                        guard attempt == 0, let fix = AppleCoachPrompt.violations(e) else { break }
                        response = try await m.session.respond(to: fix, generating: CoachDecision.self)
                        decision = response.content
                        if !decision.propose || decision.changes.isEmpty { break }
                    }
                }
            }
            await putNotes(decision.notes)
            let (ti, to) = tokens(response)
            await recorder.upload(kind: kind, trigger: trigger, model: m.name, input: prompt,
                                  output: describe(decision), error: proposalIds.isEmpty ? lastError : nil,
                                  dailyLimitHit: false, proposalIds: proposalIds, tokensIn: ti, tokensOut: to)
        } catch {
            await handleFailure(error, recorder: recorder, kind: kind, trigger: trigger, model: m.name, input: prompt)
        }
    }

    private func submit(_ d: CoachDecision, kind: RunPlanV2AICallKind) async throws -> RunPlanV2Proposal {
        let pk = RunPlanV2ProposalKind(raw: d.kind)
        let req = RunPlanV2ProposalRequest(
            today: RunPlanV2Date.todayKey(), source: "apple",
            kind: kind == .weeklyReview && pk == .adjust ? "weekly_review" : pk.rawValue,
            title: String(d.title.prefix(80)), reason: String(d.reason.prefix(300)), goal_impact: nil,
            changes: d.changes.map(\.change),
            deviation_reason: d.deviation_reason.isEmpty ? nil : d.deviation_reason, ai_call_id: nil)
        return try await RunPlanV2Service.submitProposal(req)
    }

    private func putNotes(_ notes: [CoachDayNote]) async {
        let today = RunPlanV2Date.todayKey()
        let items = notes.filter { $0.local_date >= today && !$0.note.isEmpty }
            .map { RunPlanV2NoteItem(local_date: $0.local_date, note: String($0.note.prefix(600))) }
        guard !items.isEmpty else { return }
        _ = try? await RunPlanV2Service.putNotes(RunPlanV2NotesRequest(today: today, source: "apple", notes: items, grade_summaries: []))
    }

    private func describe(_ d: CoachDecision) -> String {
        var s = "propose=\(d.propose) kind=\(d.kind) title=\(d.title)\nreason=\(d.reason)"
        for c in d.changes {
            s += "\n\(c.local_date) \(c.kind) \(c.distance_mi) mi work \(c.work_mi) reps \(c.reps)x\(c.rep_mi)mi/\(c.rep_s)s rec \(c.recover_s)s pf \(c.pace_factor)"
        }
        if !d.deviation_reason.isEmpty { s += "\ndeviation: \(d.deviation_reason)" }
        for n in d.notes { s += "\nnote \(n.local_date): \(n.note)" }
        return s
    }

    // MARK: Check-in

    func checkIn(_ c: RunPlanV2CheckinRequest, formulaProposal: RunPlanV2Proposal?) async -> (RunPlanV2Proposal?, String?) {
        let store = RunPlanV2Store.shared
        guard let today = store.today else { return (nil, nil) }
        let recorder = AppleCoachCallRecorder()
        let tools: [any Tool] = [GetOptionsTool(recorder: recorder), ValidateTool(recorder: recorder)]
        // Short job: the on-device model unless the cloud one is clearly better here.
        guard let m = session(.small, tools: tools, instructions: AppleCoachPrompt.instructions) else { return (nil, nil) }
        var lines = ["Today: \(AppleCoachPrompt.line(today))"]
        if let limit = (try? await RunPlanV2Service.coachContext(daysBack: 3, daysAhead: 3))?.0 {
            lines.append(AppleCoachPrompt.context(limit, wide: false))
        }
        var checkin = "Before-the-run check-in:"
        if let t = c.time_available_min { checkin += " time available \(t >= 240 ? "60+" : String(t)) min;" }
        if let e = c.energy { checkin += " energy \(e)/10 (0 drained, 10 energized);" }
        if let s = c.soreness { checkin += " soreness \(s)/10;" }
        if let g = c.go_further_mi { checkin += String(format: " wants to go further: %.1f mi;", g) }
        if let t = c.text, !t.isEmpty { checkin += " says: \"\(t.prefix(1000))\"" }
        lines.append(checkin)
        if let f = formulaProposal {
            lines.append("The app's rule-based suggestion: \(f.title ?? "") — \(f.reason ?? "")")
        }
        lines.append("Reply to the runner, and if today's run should change, propose today's new version (use get_options for numbers). Keep it within about 10% unless they asked to go further.")
        let prompt = lines.joined(separator: "\n")
        do {
            let response = try await m.session.respond(to: prompt, generating: CheckinDecision.self)
            let d = response.content
            var proposal: RunPlanV2Proposal?
            var err: String?
            if d.propose {
                var spec = d.today
                spec.local_date = today.dateKey
                let req = RunPlanV2ProposalRequest(
                    today: RunPlanV2Date.todayKey(), source: "apple", kind: "checkin",
                    title: String(d.title.prefix(80)), reason: String(d.reason.prefix(300)), goal_impact: nil,
                    changes: [spec.change], deviation_reason: d.deviation_reason.isEmpty ? nil : d.deviation_reason,
                    ai_call_id: nil)
                do {
                    proposal = try await RunPlanV2Service.submitProposal(req)
                    if let proposal { store.absorb(proposal) }
                } catch let e as RunPlanV2Error {
                    err = e.message
                } catch {
                    err = "\(error)"
                }
            }
            await recorder.upload(kind: .checkin, trigger: .checkin, model: m.name, input: prompt,
                                  output: "reply=\(d.reply)\npropose=\(d.propose) \(d.title): \(d.reason)",
                                  error: err, dailyLimitHit: false, proposalIds: proposal.map { [$0.id] } ?? [])
            return (proposal, d.reply.isEmpty ? nil : d.reply)
        } catch {
            await handleFailure(error, recorder: recorder, kind: .checkin, trigger: .checkin, model: m.name, input: prompt)
            return (nil, nil)
        }
    }

    // MARK: Chat

    func chat(_ message: String, history: [RunPlanChatMessage]) async -> String? {
        let recorder = AppleCoachCallRecorder()
        let box = ProposalBox()
        let tools: [any Tool] = [GetOptionsTool(recorder: recorder), BuildDayTool(recorder: recorder),
                                 ValidateTool(recorder: recorder), EstimateTool(recorder: recorder),
                                 ProposeChangeTool(recorder: recorder, proposals: box)]
        guard let m = session(.big, tools: tools, instructions: AppleCoachPrompt.instructions
                              + "\nAnswer questions about the plan in two or three short sentences.") else { return nil }
        var prompt = ""
        if let ctx = (try? await RunPlanV2Service.coachContext())?.0 { prompt = AppleCoachPrompt.context(ctx, wide: m.wide) + "\n\n" }
        let recent = history.suffix(8).map { "\($0.role == .user ? "Runner" : "Flamey"): \($0.text)" }.joined(separator: "\n")
        if !recent.isEmpty { prompt += "Conversation so far:\n\(recent)\n\n" }
        prompt += "Runner: \(message.prefix(1000))"
        do {
            let response = try await m.session.respond(to: prompt)
            let reply = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let made = box.all
            made.forEach { RunPlanV2Store.shared.absorb($0) }
            let (ti, to) = tokens(response)
            await recorder.upload(kind: .chat, trigger: .chat, model: m.name, input: prompt, output: reply,
                                  error: nil, dailyLimitHit: false, proposalIds: made.map(\.id), tokensIn: ti, tokensOut: to)
            return reply
        } catch {
            await handleFailure(error, recorder: recorder, kind: .chat, trigger: .chat, model: m.name, input: prompt)
            return nil
        }
    }

    // MARK: Plan build (setup)

    func buildPlan(request: RunPlanV2CreateRequest, preview: RunPlanV2PlanWithDays,
                   profile: RunPlanV2FitnessProfile?) async -> [RunPlanV2InitialDay]? {
        let recorder = AppleCoachCallRecorder()
        let tools: [any Tool] = [BuildDayTool(recorder: recorder), ValidateTool(recorder: recorder),
                                 EstimateTool(recorder: recorder)]
        guard let m = session(.big, tools: tools, instructions: AppleCoachPrompt.instructions) else { return nil }
        var ctx = RunPlanV2CoachContext()
        ctx.today = request.today
        ctx.plan = preview.plan
        ctx.fitness_profile = profile
        let base = AppleCoachPrompt.context(ctx, wide: m.wide)
        let days = preview.days.sorted { ($0.local_date ?? "") < ($1.local_date ?? "") }
        let weeks = [Array(days.prefix(7)), Array(days.dropFirst(7).prefix(7))].filter { !$0.isEmpty }
        var initial: [String: RunPlanV2DaySpec] = [:]
        var notes: [RunPlanV2NoteItem] = []
        var transcript = ""
        // Step 1 sees the outline; each step then shapes one week.
        let outline = "Draft plan from the app's formula (first 4 weeks):\n"
            + days.prefix(28).map(AppleCoachPrompt.line).joined(separator: "\n")
        var input = base + "\n\n" + outline
        do {
            for (i, week) in weeks.enumerated() {
                let ask = (i == 0 ? input + "\n\n" : "")
                    + "Shape week \(i + 1) (\(week.first?.local_date ?? "") to \(week.last?.local_date ?? "")) for this runner. "
                    + "Change a day only when the runner's goals, notes or fitness call for it; check numbers with build_day. "
                    + "Write a short note for each run day."
                let response = try await m.session.respond(to: ask, generating: PlanWeekDecision.self)
                transcript += "\nweek \(i + 1): \(response.content.changes.count) changes"
                for c in response.content.changes { initial[c.local_date] = c.change.after }
                for n in response.content.notes where !n.note.isEmpty {
                    notes.append(RunPlanV2NoteItem(local_date: n.local_date, note: String(n.note.prefix(600))))
                }
            }
        } catch {
            await handleFailure(error, recorder: recorder, kind: .planBuild, trigger: .setup, model: m.name, input: input)
            return nil
        }
        input += transcript
        // Every draft day the model kept is sent as-is, so the first two weeks are complete.
        let covered = weeks.flatMap { $0 }
        let result = covered.compactMap { d -> RunPlanV2InitialDay? in
            guard let key = d.local_date else { return nil }
            return RunPlanV2InitialDay(local_date: key, day: initial[key] ?? RunPlanV2DaySpec(day: d))
        }
        AppleCoachEngine.pendingSetupNotes = notes
        await recorder.upload(kind: .planBuild, trigger: .setup, model: m.name, input: input,
                              output: result.map { "\($0.local_date) \($0.day.kind) \($0.day.distance_mi ?? 0)" }.joined(separator: "\n"),
                              error: nil, dailyLimitHit: false, proposalIds: [])
        return initial.isEmpty ? nil : result
    }

    /// Notes written during the plan build, saved once the plan exists.
    static var pendingSetupNotes: [RunPlanV2NoteItem] = []

    static func flushSetupNotes() async {
        let notes = pendingSetupNotes
        pendingSetupNotes = []
        let today = RunPlanV2Date.todayKey()
        let items = notes.filter { $0.local_date >= today }
        guard !items.isEmpty else { return }
        _ = try? await RunPlanV2Service.putNotes(RunPlanV2NotesRequest(today: today, source: "apple", notes: items, grade_summaries: []))
    }

    // MARK: Post-run summary

    func postRunSummary(day: RunPlanV2Day, grade: RunPlanV2Grade) async -> String? {
        let recorder = AppleCoachCallRecorder()
        guard let m = session(.small, tools: [], instructions: AppleCoachPrompt.instructions) else { return nil }
        let prompt = """
        The runner just finished: \(AppleCoachPrompt.line(day))
        Grade \(grade.score ?? 0)/100 (completion \(grade.completion ?? 0), on target \(grade.on_target ?? 0), \
        consistency \(grade.consistency ?? 0)). The app's summary: \(grade.summary ?? "none").
        Write Flamey's two-sentence summary of how the run went against the plan. Use only the numbers above.
        """
        do {
            let response = try await m.session.respond(to: prompt)
            let text = String(response.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
            if let key = day.local_date, !text.isEmpty {
                _ = try? await RunPlanV2Service.putNotes(RunPlanV2NotesRequest(
                    today: RunPlanV2Date.todayKey(), source: "apple", notes: [],
                    grade_summaries: [RunPlanV2SummaryItem(local_date: key, summary: text)]))
            }
            await recorder.upload(kind: .postRun, trigger: .afterRun, model: m.name, input: prompt, output: text,
                                  error: nil, dailyLimitHit: false, proposalIds: [])
            return text.isEmpty ? nil : text
        } catch {
            await handleFailure(error, recorder: recorder, kind: .postRun, trigger: .afterRun, model: m.name, input: prompt)
            return nil
        }
    }
}

// MARK: - The cloud model (iOS 27)

#if compiler(>=6.4)
/// One shared `PrivateCloudComputeLanguageModel` (Apple: create once and
/// share; creating it runs an authentication check).
@available(iOS 27.0, *)
@MainActor
final class AppleCloudModel {
    static let shared = AppleCloudModel()
    let model = PrivateCloudComputeLanguageModel()

    var isAvailable: Bool {
        if case .available = model.availability { return !model.quotaUsage.isLimitReached }
        return false
    }

    var limitIncreaseAvailable: Bool { model.quotaUsage.limitIncreaseSuggestion != nil }

    func showLimitIncrease() { model.quotaUsage.limitIncreaseSuggestion?.show() }
}
#endif

#endif
