import Foundation

/// One door for the screens: routes each coach job to the tier that runs it
/// now (`RunPlanV2Store.coachTier`). Formula = the server's rules only;
/// Apple = `AppleCoach` on this phone; Anthropic = the server runs Claude
/// (`POST /coach/anthropic`), so the phone only calls endpoints.
@MainActor
enum RunPlanCoach {
    struct CheckinOutcome {
        var checkin: RunPlanV2Checkin?
        /// The proposal for today (the AI's when it made one, else the formula's).
        var proposal: RunPlanV2Proposal?
        /// Flamey's reply (AI tiers only).
        var reply: String?
    }

    private static var store: RunPlanV2Store { RunPlanV2Store.shared }

    /// Before-the-run check-in. The formula's tweak always comes back from
    /// the server; an AI tier may then build its own (which supersedes it).
    static func checkIn(_ request: RunPlanV2CheckinRequest) async throws -> CheckinOutcome {
        let result = try await store.checkIn(request)
        var outcome = CheckinOutcome(checkin: result.checkin, proposal: result.proposal, reply: nil)
        switch store.coachTier {
        case .formula:
            break
        case .apple:
            guard !AppleCoach.shared.dailyLimitHitToday || AppleCoach.onDeviceAvailable else { break }
            let ai = await AppleCoach.shared.checkIn(request, checkinId: result.checkin?.id, formulaProposal: result.proposal)
            if let p = ai.proposal { outcome.proposal = p }
            outcome.reply = ai.reply
        case .anthropic:
            let message = [request.text, summary(request)].compactMap { $0 }.joined(separator: "\n")
            if let reply = try? await anthropic(kind: "checkin", message: message, checkinId: result.checkin?.id) {
                if let p = reply.proposals.first(where: { $0.touches(request.local_date) }) ?? reply.proposals.first {
                    outcome.proposal = p
                }
                outcome.reply = reply.reply
            }
        }
        return outcome
    }

    /// The check-in as words for the server-side coach.
    private static func summary(_ r: RunPlanV2CheckinRequest) -> String? {
        var parts: [String] = []
        if let t = r.time_available_min { parts.append("time \(t >= 240 ? "60+" : String(t)) min") }
        if let e = r.energy { parts.append("energy \(e)/10") }
        if let s = r.soreness { parts.append("soreness \(s)/10") }
        if let g = r.go_further_mi { parts.append(String(format: "go further to %.1f mi", g)) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Ask Flamey (AI tiers). Nil = no answer (offline, model unavailable).
    static func ask(_ message: String, history: [RunPlanChatMessage]) async -> String? {
        switch store.coachTier {
        case .formula: return nil
        case .apple: return await AppleCoach.shared.ask(message, history: history)
        case .anthropic: return (try? await anthropic(kind: "chat", message: message))?.reply
        }
    }

    /// Creates the plan. The Apple coach shapes the first two weeks first
    /// (validated by the server; a rejected build falls back to the formula
    /// draft); the Anthropic coach reviews the new plan on the server.
    static func createPlan(_ request: RunPlanV2CreateRequest, profile: RunPlanV2FitnessProfile?) async throws {
        var request = request
        switch store.coachTier {
        case .apple:
            if let preview = try? await store.preview(request),
               let days = await AppleCoach.shared.buildInitialDays(request: request, preview: preview, profile: profile) {
                var ai = request
                ai.initial_days = days
                ai.source = "apple"
                do {
                    try await store.create(ai)
                    #if canImport(FoundationModels)
                    if #available(iOS 26.0, *) { await AppleCoachEngine.flushSetupNotes() }
                    #endif
                    return
                } catch RunPlanV2Error.hardRuleViolation, RunPlanV2Error.deviationReasonRequired {
                    // Fall through to the formula draft.
                }
            }
            request.initial_days = nil
            request.source = "formula"
            try await store.create(request)
        case .anthropic:
            request.initial_days = nil
            request.source = "formula"
            try await store.create(request)
            _ = try? await anthropic(kind: "plan_build", message: nil)
            await store.refreshQuietly()
        case .formula:
            request.initial_days = nil
            request.source = "formula"
            try await store.create(request)
        }
    }

    /// After a run syncs / first open of the day: the AI tier's pass.
    static func runBackgroundPass(trigger: RunPlanV2AICallTrigger) async {
        switch store.coachTier {
        case .formula:
            return
        case .apple:
            await AppleCoach.shared.runAdjustPass(trigger: trigger)
        case .anthropic:
            let key = "runPlanV2AnthropicPass|\(trigger.rawValue)"
            let stamp = trigger == .afterRun ? RunPlanV2Date.timestamp() : RunPlanV2Date.todayKey()
            if trigger != .afterRun, UserDefaults.standard.string(forKey: key) == stamp { return }
            if trigger == .afterRun, let last = RunPlanV2Date.parseTimestamp(UserDefaults.standard.string(forKey: key)),
               Date().timeIntervalSince(last) < 600 { return }
            UserDefaults.standard.set(stamp, forKey: key)
            _ = try? await anthropic(kind: trigger == .afterRun ? "post_run" : "adjust", message: nil)
        }
        await store.refreshQuietly()
    }

    /// Server-side Claude. 503 `ai_unavailable` → the formula plan, said once.
    static func anthropic(kind: String, message: String?, checkinId: String? = nil) async throws -> RunPlanV2AnthropicReply {
        do {
            let reply = try await RunPlanV2Service.anthropic(RunPlanV2AnthropicRequest(
                today: RunPlanV2Date.todayKey(), kind: kind, message: message, checkin_id: checkinId))
            reply.proposals.forEach { store.absorb($0) }
            return reply
        } catch RunPlanV2Error.aiUnavailable(let reason) {
            if reason == "anthropic_budget_exhausted" || reason == "provider_error" {
                store.noteCoachFallback(String(localized: "The AI Coach is taking a break, so your plan follows the formula for now."))
            }
            throw RunPlanV2Error.aiUnavailable(reason: reason)
        }
    }
}
