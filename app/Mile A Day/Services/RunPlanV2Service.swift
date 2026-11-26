import Combine
import Foundation

// MARK: - Endpoints

/// `/run-plans/*` (contract `mad-run-plans-api` v1.0). Stateless; the store
/// below holds what the screens show. Every read sends the phone's local day
/// (`?today=`), every write sends `"today"` in the body.
enum RunPlanV2Service {
    private struct Ignored: Decodable {}
    private struct ErrorBody: Decodable {
        let error: String?
        let reason: String?
        let status: String?
        /// `undo_conflicts_with_plan`: the day the undo would break.
        let local_date: String?
        @RunPlanV2List var violations: [RunPlanV2Violation] = []
        @RunPlanV2List var deviations: [RunPlanV2Deviation] = []
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private static func q(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    /// Runs one request and maps every failure to `RunPlanV2Error`, reading
    /// the full error body through `APIErrorBodySink`.
    private static func run<T: Decodable>(_ endpoint: String, method: HTTPMethod = .GET, body: Data? = nil,
                                          as type: T.Type) async throws -> T {
        let sink = APIErrorBodySink()
        do {
            return try await APIErrorBodySink.$current.withValue(sink) {
                try await APIClient.fancyFetch(endpoint: endpoint, method: method, body: body, responseType: type)
            }
        } catch {
            throw map(error, sink: sink)
        }
    }

    private static func map(_ error: Error, sink: APIErrorBodySink) -> RunPlanV2Error {
        if let mine = error as? RunPlanV2Error { return mine }
        let parsed = sink.body.flatMap { try? JSONDecoder().decode(ErrorBody.self, from: $0) }
        let code = parsed?.error ?? ""
        switch code {
        case "": break
        case "plus_required": return .plusRequired
        case "no_plan": return .noPlan
        case "plan_exists": return .planExists
        case "ai_off": return .aiOff
        case "ai_mode_mismatch": return .aiModeMismatch
        case "consent_required": return .consentRequired
        case "ai_unavailable": return .aiUnavailable(reason: parsed?.reason)
        case "hard_rule_violation": return .hardRuleViolation(parsed?.violations ?? [])
        case "deviation_reason_required": return .deviationReasonRequired(parsed?.deviations ?? [])
        case "stale_proposal":
            // With `violations`: the plan changed and the HARD rules now fail
            // (the server marked it superseded).
            let violations = parsed?.violations ?? []
            return violations.isEmpty ? .staleProposal : .proposalSuperseded(violations)
        case "proposal_not_pending":
            if parsed?.status == "expired" { return .proposalExpired }
            return .proposalNotPending(status: parsed?.status)
        case "undo_expired": return .undoExpired
        case "undo_conflict": return .undoConflict
        case "undo_conflicts_with_plan":
            return .undoConflictsWithPlan(localDate: parsed?.local_date, violations: parsed?.violations ?? [])
        case "proposal_not_found", "day_not_found", "effort_not_found": return .notFound(code)
        default: return .invalid(code)
        }
        if let api = error as? APIError {
            switch api {
            case .notFound: return .notFound("not_found")
            case .apiError(let m) where m == "plus_required": return .plusRequired
            case .badRequest(let m), .conflict(let m), .apiError(let m): return .invalid(m)
            default: break
            }
        }
        return .offline
    }

    private struct TodayBody: Encodable { let today: String }
    private static func todayBody(_ today: String) throws -> Data { try encode(TodayBody(today: today)) }

    // MARK: §1 Status and settings

    static func status(today: String = RunPlanV2Date.todayKey()) async throws -> RunPlanV2Status {
        try await run("/run-plans/status?today=\(q(today))", as: RunPlanV2Status.self)
    }

    private struct OptOutBody: Encodable { let user_opt_out: Bool }
    static func setCoachOptOut(_ optOut: Bool) async throws -> RunPlanV2AI {
        try await run("/run-plans/coach/settings", method: .PATCH, body: try encode(OptOutBody(user_opt_out: optOut)),
                      as: RunPlanV2AI.self)
    }

    private struct ConsentBody: Encodable { let accepted: Bool }
    static func setAnthropicConsent(_ accepted: Bool) async throws -> RunPlanV2AI {
        try await run("/run-plans/coach/anthropic-consent", method: .POST,
                      body: try encode(ConsentBody(accepted: accepted)), as: RunPlanV2AI.self)
    }

    // MARK: §2 Fitness profile

    static func uploadFitnessProfile(_ profile: RunPlanV2FitnessProfile) async throws -> RunPlanV2FitnessProfileEnvelope {
        try await run("/run-plans/fitness-profile", method: .PUT, body: try encode(profile),
                      as: RunPlanV2FitnessProfileEnvelope.self)
    }

    static func fitnessProfile() async throws -> RunPlanV2FitnessProfileEnvelope {
        try await run("/run-plans/fitness-profile", as: RunPlanV2FitnessProfileEnvelope.self)
    }

    // MARK: §3 Plans

    static func preview(_ request: RunPlanV2CreateRequest) async throws -> RunPlanV2PlanWithDays {
        try await run("/run-plans/preview", method: .POST, body: try encode(request), as: RunPlanV2PlanWithDays.self)
    }

    static func create(_ request: RunPlanV2CreateRequest) async throws -> RunPlanV2PlanWithDays {
        try await run("/run-plans", method: .POST, body: try encode(request), as: RunPlanV2PlanWithDays.self)
    }

    static func current(today: String = RunPlanV2Date.todayKey()) async throws -> RunPlanV2Current {
        try await run("/run-plans/current?today=\(q(today))", as: RunPlanV2Current.self)
    }

    private struct DaysEnvelope: Decodable { @RunPlanV2List var days: [RunPlanV2Day] = [] }
    static func days(from: String, to: String, today: String = RunPlanV2Date.todayKey()) async throws -> [RunPlanV2Day] {
        try await run("/run-plans/days?from=\(q(from))&to=\(q(to))&today=\(q(today))", as: DaysEnvelope.self).days
    }

    static func updatePlan(_ patch: RunPlanV2PlanPatch) async throws -> RunPlanV2Current {
        try await run("/run-plans/current", method: .PATCH, body: try encode(patch), as: RunPlanV2Current.self)
    }

    static func endPlan() async throws {
        _ = try await run("/run-plans/current", method: .DELETE, as: Ignored.self)
    }

    private struct HistoryEnvelope: Decodable { @RunPlanV2List var entries: [RunPlanV2HistoryEntry] = [] }
    static func history(limit: Int = 50, before: String? = nil) async throws -> [RunPlanV2HistoryEntry] {
        var path = "/run-plans/history?limit=\(limit)"
        if let before { path += "&before=\(q(before))" }
        return try await run(path, as: HistoryEnvelope.self).entries
    }

    // MARK: §4 Proposals

    private struct ProposalsEnvelope: Decodable { @RunPlanV2List var proposals: [RunPlanV2Proposal] = [] }
    private struct ProposalEnvelope: Decodable { let proposal: RunPlanV2Proposal }

    /// `status`: pending | scheduled | all
    static func proposals(status: String = "pending", limit: Int = 50) async throws -> [RunPlanV2Proposal] {
        try await run("/run-plans/proposals?status=\(q(status))&limit=\(limit)", as: ProposalsEnvelope.self).proposals
    }

    static func proposal(id: String) async throws -> RunPlanV2Proposal {
        try await run("/run-plans/proposals/\(q(id))", as: ProposalEnvelope.self).proposal
    }

    static func submitProposal(_ request: RunPlanV2ProposalRequest) async throws -> RunPlanV2Proposal {
        try await run("/run-plans/proposals", method: .POST, body: try encode(request), as: ProposalEnvelope.self).proposal
    }

    struct DecisionResult: Decodable {
        let proposal: RunPlanV2Proposal?
        @RunPlanV2List var days: [RunPlanV2Day] = []
    }

    static func apply(proposalId: String, today: String = RunPlanV2Date.todayKey()) async throws -> DecisionResult {
        try await run("/run-plans/proposals/\(q(proposalId))/apply", method: .POST, body: try todayBody(today),
                      as: DecisionResult.self)
    }

    static func applyAfterRun(proposalId: String, today: String = RunPlanV2Date.todayKey()) async throws -> DecisionResult {
        try await run("/run-plans/proposals/\(q(proposalId))/apply-after-run", method: .POST, body: try todayBody(today),
                      as: DecisionResult.self)
    }

    static func decline(proposalId: String, today: String = RunPlanV2Date.todayKey()) async throws -> DecisionResult {
        try await run("/run-plans/proposals/\(q(proposalId))/decline", method: .POST, body: try todayBody(today),
                      as: DecisionResult.self)
    }

    static func undo(proposalId: String, today: String = RunPlanV2Date.todayKey()) async throws -> DecisionResult {
        try await run("/run-plans/proposals/\(q(proposalId))/undo", method: .POST, body: try todayBody(today),
                      as: DecisionResult.self)
    }

    // MARK: §5 Coach tools

    static func coachContext(today: String = RunPlanV2Date.todayKey(), daysBack: Int = 14,
                             daysAhead: Int = 14) async throws -> (RunPlanV2CoachContext, Data) {
        let raw = try await run("/run-plans/coach/context?today=\(q(today))&days_back=\(daysBack)&days_ahead=\(daysAhead)",
                                as: RunPlanV2RawJSON.self)
        let decoded = (try? JSONDecoder().decode(RunPlanV2CoachContext.self, from: raw.data)) ?? RunPlanV2CoachContext()
        return (decoded, raw.data)
    }

    static func coachOptions(_ request: RunPlanV2OptionsRequest) async throws -> RunPlanV2OptionsResult {
        try await run("/run-plans/coach/options", method: .POST, body: try encode(request), as: RunPlanV2OptionsResult.self)
    }

    private struct BuildDayBody: Encodable { let today: String; let local_date: String; let day: RunPlanV2DaySpec }
    static func buildDay(localDate: String, day: RunPlanV2DaySpec,
                         today: String = RunPlanV2Date.todayKey()) async throws -> RunPlanV2BuildDayResult {
        try await run("/run-plans/coach/build-day", method: .POST,
                      body: try encode(BuildDayBody(today: today, local_date: localDate, day: day)),
                      as: RunPlanV2BuildDayResult.self)
    }

    private struct ValidateBody: Encodable { let today: String; let changes: [RunPlanV2DayChange] }
    static func validate(_ changes: [RunPlanV2DayChange],
                         today: String = RunPlanV2Date.todayKey()) async throws -> RunPlanV2ValidateResult {
        try await run("/run-plans/coach/validate", method: .POST,
                      body: try encode(ValidateBody(today: today, changes: changes)), as: RunPlanV2ValidateResult.self)
    }

    /// `distance`: mile | 5k | 10k | half | marathon
    static func estimate(distance: String, today: String = RunPlanV2Date.todayKey()) async throws -> RunPlanV2Estimate {
        try await run("/run-plans/coach/estimate?distance=\(q(distance))&today=\(q(today))", as: RunPlanV2Estimate.self)
    }

    private struct NotesResult: Decodable { @RunPlanV2Int var updated: Int? = nil }
    @discardableResult
    static func putNotes(_ request: RunPlanV2NotesRequest) async throws -> Int {
        try await run("/run-plans/coach/notes", method: .PUT, body: try encode(request), as: NotesResult.self).updated ?? 0
    }

    private struct CallsBody: Encodable { let calls: [RunPlanV2AICallLog] }
    @discardableResult
    static func uploadCalls(_ calls: [RunPlanV2AICallLog]) async throws -> RunPlanV2CallsAccepted {
        try await run("/run-plans/coach/calls", method: .POST, body: try encode(CallsBody(calls: calls)),
                      as: RunPlanV2CallsAccepted.self)
    }

    // MARK: §6 Triggers

    static func open(today: String = RunPlanV2Date.todayKey()) async throws -> RunPlanV2OpenResult {
        try await run("/run-plans/open", method: .POST, body: try todayBody(today), as: RunPlanV2OpenResult.self)
    }

    // MARK: §7 Check-ins and grades

    static func checkIn(_ request: RunPlanV2CheckinRequest) async throws -> RunPlanV2CheckinResult {
        try await run("/run-plans/checkins", method: .POST, body: try encode(request), as: RunPlanV2CheckinResult.self)
    }

    private struct CheckinsEnvelope: Decodable { @RunPlanV2List var checkins: [RunPlanV2Checkin] = [] }
    static func checkins(from: String, to: String) async throws -> [RunPlanV2Checkin] {
        try await run("/run-plans/checkins?from=\(q(from))&to=\(q(to))", as: CheckinsEnvelope.self).checkins
    }

    static func uploadGrade(_ upload: RunPlanV2GradeUpload) async throws -> RunPlanV2GradeResult {
        try await run("/run-plans/grades", method: .POST, body: try encode(upload), as: RunPlanV2GradeResult.self)
    }

    // MARK: §7b Effort guess (RPE)

    private static func path(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? s
    }

    static func submitEffort(_ upload: RunPlanV2EffortUpload) async throws -> RunPlanV2EffortResult {
        try await run("/run-plans/effort", method: .POST, body: try encode(upload), as: RunPlanV2EffortResult.self)
    }

    /// `404 effort_not_found` → `RunPlanV2Error.notFound`.
    static func effort(workoutId: String) async throws -> RunPlanV2EffortResult {
        try await run("/run-plans/effort/\(path(workoutId))", as: RunPlanV2EffortResult.self)
    }

    static func efforts(from: String? = nil, to: String? = nil) async throws -> RunPlanV2EffortList {
        var endpoint = "/run-plans/effort"
        if let from, let to { endpoint += "?from=\(q(from))&to=\(q(to))" }
        return try await run(endpoint, as: RunPlanV2EffortList.self)
    }

    /// `rating` nil clears it (sent as an explicit null).
    private struct RatingBody: Encodable {
        let today: String
        let rating: Int?
        enum CodingKeys: String, CodingKey { case today, rating }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(today, forKey: .today)
            try c.encode(rating, forKey: .rating)
        }
    }

    static func rateEffort(workoutId: String, rating: Int?,
                           today: String = RunPlanV2Date.todayKey()) async throws -> RunPlanV2RatingResult {
        try await run("/run-plans/effort/\(path(workoutId))/rating", method: .POST,
                      body: try encode(RatingBody(today: today, rating: rating)), as: RunPlanV2RatingResult.self)
    }

    // MARK: §9 Anthropic (server-side coach)

    static func anthropic(_ request: RunPlanV2AnthropicRequest) async throws -> RunPlanV2AnthropicReply {
        try await run("/run-plans/coach/anthropic", method: .POST, body: try encode(request),
                      as: RunPlanV2AnthropicReply.self)
    }
}

/// A response body kept undecoded (the coach context goes to the model as-is).
struct RunPlanV2RawJSON: Decodable {
    let data: Data

    init(from decoder: Decoder) throws {
        let value = try RunPlanV2AnyJSON(from: decoder)
        data = (try? JSONSerialization.data(withJSONObject: value.object, options: [.fragmentsAllowed])) ?? Data()
    }
}

/// Minimal JSON tree, so `RunPlanV2RawJSON` can re-serialize what it was handed.
enum RunPlanV2AnyJSON: Decodable {
    case null, bool(Bool), number(Double), string(String), array([RunPlanV2AnyJSON]), object([String: RunPlanV2AnyJSON])

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: AnyKey.self) {
            var dict: [String: RunPlanV2AnyJSON] = [:]
            for key in keyed.allKeys { dict[key.stringValue] = try keyed.decode(RunPlanV2AnyJSON.self, forKey: key) }
            self = .object(dict)
            return
        }
        if var list = try? decoder.unkeyedContainer() {
            var items: [RunPlanV2AnyJSON] = []
            while !list.isAtEnd { items.append(try list.decode(RunPlanV2AnyJSON.self)) }
            self = .array(items)
            return
        }
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else { self = .string(try c.decode(String.self)) }
    }

    var object: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map(\.object)
        case .object(let o): return o.mapValues(\.object)
        }
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

// MARK: - Store

/// The current plan, cached per account so the dashboard card paints on
/// launch. Refreshed on appear / foreground (throttled), on the first open
/// of the local day (`POST /open`), and after a workout syncs; replaced by
/// every mutation's response. The run-time coach and the Watch read
/// `today` / `current?.today?.segments` from here.
@MainActor
final class RunPlanV2Store: ObservableObject {
    static let shared = RunPlanV2Store()

    /// Server status (Plus, plan, AI routing). Works for non-members too.
    @Published private(set) var status: RunPlanV2Status?
    /// `GET /current`; nil without a plan.
    @Published private(set) var current: RunPlanV2Current?
    /// Pending proposals (excluding walk-day suggestions, which are `suggestions`).
    @Published private(set) var pendingProposals: [RunPlanV2Proposal] = []
    /// Walk-day suggestions (`walk_day_earned` / `walk_day_needed`).
    @Published private(set) var suggestions: [RunPlanV2Proposal] = []
    /// Proposals scheduled to apply after today's run.
    @Published private(set) var scheduledProposals: [RunPlanV2Proposal] = []
    /// A server answer (or this account's cache) is in hand.
    @Published private(set) var loaded = false
    @Published private(set) var isRefreshing = false
    /// The server said Plus is required.
    @Published private(set) var plusRequired = false
    /// Latest phone-computed fitness profile (local, not refetched).
    @Published private(set) var fitnessProfile: RunPlanV2FitnessProfile?
    /// Set once when the AI Coach falls back to the formula for the rest of
    /// the day (Apple's daily allowance used up, model unreachable). The plan
    /// home shows it once, then clears it via `acknowledgeCoachNotice()`.
    @Published var coachNotice: String?
    /// Proposal the user just applied, for the 24 h Undo toast.
    @Published private(set) var lastApplied: RunPlanV2Proposal?

    private var lastRefresh: Date?
    private var lastRefreshDay: String?
    private var syncTask: Task<Void, Never>?
    private var uploadObserver: NSObjectProtocol?
    private let cachePrefix = "runPlanV2Current|"
    private let openDayPrefix = "runPlanV2OpenDay|"

    private init() {
        if let cached = loadCache() {
            adoptCurrent(cached, persist: false)
            loaded = true
        }
        // Posted by WorkoutSyncService after every successful upload.
        uploadObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("MAD_WorkoutsUploaded"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in RunPlanV2Store.shared.workoutDidSync() }
        }
    }

    // MARK: Derived

    var plan: RunPlanV2Plan? { current?.plan }
    var hasPlan: Bool { current != nil }
    var today: RunPlanV2Day? { current?.today }
    var nextRun: RunPlanV2Day? { current?.next_run }
    var week: [RunPlanV2Day] { current?.week ?? [] }
    var ai: RunPlanV2AI { current?.ai ?? status?.ai ?? .formulaOnly }
    var isPlus: Bool {
        if plusRequired { return false }
        return status?.isPlus ?? PlusStore.shared.isPlus
    }

    /// Which coach drives this phone right now.
    var coachTier: RunPlanV2CoachTier {
        switch ai.effectiveProvider {
        case .anthropic: return .anthropic
        case .apple: return AppleCoach.isAvailable ? .apple : .formula
        case .formula: return .formula
        }
    }

    /// The proposal for `localDate` that the user still has to decide.
    func pendingProposal(touching localDate: String) -> RunPlanV2Proposal? {
        (pendingProposals + suggestions).first { $0.touches(localDate) }
    }

    func proposal(id: String) -> RunPlanV2Proposal? {
        (pendingProposals + suggestions + scheduledProposals).first { $0.id == id }
    }

    private var userId: String? {
        guard let id = SessionIdentity.cachedUserId, !id.isEmpty else { return nil }
        return id
    }

    // MARK: Reads

    /// Cheap on every appear / foreground: skips if refreshed in the last
    /// minute on the same local day. Runs the first-open-of-day pass once.
    func refreshIfStale() async {
        let day = RunPlanV2Date.todayKey()
        if let lastRefresh, lastRefreshDay == day, Date().timeIntervalSince(lastRefresh) < 60 { return }
        await refresh()
    }

    func refresh() async {
        guard TokenStore.hasTokens, userId != nil, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let today = RunPlanV2Date.todayKey()
        do {
            let s = try await RunPlanV2Service.status(today: today)
            status = s
            plusRequired = !s.isPlus
            guard s.isPlus else {
                clearPlanState()
                loaded = true
                return
            }
            guard s.hasPlan else {
                clearPlanState()
                loaded = true
                lastRefresh = Date()
                lastRefreshDay = today
                return
            }
            await runFirstOpenIfNeeded(today: today)
            let fresh = try await RunPlanV2Service.current(today: today)
            adoptCurrent(fresh)
            loaded = true
            lastRefresh = Date()
            lastRefreshDay = today
            RunFitnessAnalyzer.shared.refreshIfStale()
        } catch RunPlanV2Error.plusRequired {
            plusRequired = true
            clearPlanState()
            loaded = true
        } catch RunPlanV2Error.noPlan {
            clearPlanState()
            loaded = true
        } catch {
            // Keep what we have; the next appear retries.
        }
    }

    /// First app open of the local day: the server's formula pass, then the
    /// phone's own model when Apple's coach is on. Idempotent per day.
    private func runFirstOpenIfNeeded(today: String) async {
        guard let userId else { return }
        let key = openDayPrefix + userId
        guard UserDefaults.standard.string(forKey: key) != today else { return }
        do {
            let result = try await RunPlanV2Service.open(today: today)
            UserDefaults.standard.set(today, forKey: key)
            if let ai = result.ai { status?.ai = ai }
            if coachTier.isAI {
                Task { await RunPlanCoach.runBackgroundPass(trigger: .firstOpen) }
            }
        } catch {
            // Not marked: the next refresh tries again.
        }
    }

    /// After a workout uploads: the server grades and runs its formula pass
    /// asynchronously, so wait a moment, refetch, then let Apple's coach look.
    func workoutDidSync() {
        guard TokenStore.hasTokens, hasPlan || status?.hasPlan == true else { return }
        // A history import posts one upload per batch: coalesce them.
        syncTask?.cancel()
        syncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            lastRefresh = nil
            await refresh()
            RunFitnessAnalyzer.shared.invalidate()
            RunFitnessAnalyzer.shared.refreshIfStale()
            if coachTier.isAI { await RunPlanCoach.runBackgroundPass(trigger: .afterRun) }
        }
    }

    /// Refetch `/current` without the status / open pass.
    func refreshQuietly() async {
        guard TokenStore.hasTokens, hasPlan else { return }
        if let fresh = try? await RunPlanV2Service.current() { adoptCurrent(fresh) }
    }

    func loadScheduled() async {
        guard hasPlan else { return }
        if let list = try? await RunPlanV2Service.proposals(status: "scheduled") { scheduledProposals = list }
    }

    /// Fetches a proposal not in hand (a push tap).
    func fetchProposal(id: String) async throws -> RunPlanV2Proposal {
        if let p = proposal(id: id) { return p }
        return try await RunPlanV2Service.proposal(id: id)
    }

    func history(limit: Int = 50, before: String? = nil) async throws -> [RunPlanV2HistoryEntry] {
        try await call { try await RunPlanV2Service.history(limit: limit, before: before) }
    }

    // MARK: Writes

    func preview(_ request: RunPlanV2CreateRequest) async throws -> RunPlanV2PlanWithDays {
        try await call { try await RunPlanV2Service.preview(request) }
    }

    func create(_ request: RunPlanV2CreateRequest) async throws {
        _ = try await call { try await RunPlanV2Service.create(request) }
        lastRefresh = nil
        await refresh()
    }

    func update(_ patch: RunPlanV2PlanPatch) async throws {
        let fresh = try await call { try await RunPlanV2Service.updatePlan(patch) }
        adoptCurrent(fresh)
    }

    func endPlan() async throws {
        try await call { try await RunPlanV2Service.endPlan() }
        clearPlanState()
        status?.has_plan = false
    }

    func apply(_ proposal: RunPlanV2Proposal) async throws {
        let result = try await call { try await RunPlanV2Service.apply(proposalId: proposal.id) }
        lastApplied = result.proposal ?? proposal
        await afterDecision()
    }

    func applyAfterRun(_ proposal: RunPlanV2Proposal) async throws {
        _ = try await call { try await RunPlanV2Service.applyAfterRun(proposalId: proposal.id) }
        await afterDecision()
        await loadScheduled()
    }

    func decline(_ proposal: RunPlanV2Proposal) async throws {
        _ = try await call { try await RunPlanV2Service.decline(proposalId: proposal.id) }
        pendingProposals.removeAll { $0.id == proposal.id }
        suggestions.removeAll { $0.id == proposal.id }
        await afterDecision()
    }

    func undo(_ proposal: RunPlanV2Proposal) async throws {
        _ = try await call { try await RunPlanV2Service.undo(proposalId: proposal.id) }
        if lastApplied?.id == proposal.id { lastApplied = nil }
        await afterDecision()
    }

    func clearLastApplied() { lastApplied = nil }

    /// Check-in before the run. Returns the formula's proposal; AI tiers then
    /// build their own (which supersedes it) — see `RunPlanPreRunModel`.
    func checkIn(_ request: RunPlanV2CheckinRequest) async throws -> RunPlanV2CheckinResult {
        let result = try await call { try await RunPlanV2Service.checkIn(request) }
        if let p = result.proposal { absorb(p) }
        return result
    }

    /// The phone's grade inputs after a run (live coach calls this).
    func uploadGrade(_ upload: RunPlanV2GradeUpload) async throws -> RunPlanV2GradeResult {
        let result = try await call { try await RunPlanV2Service.uploadGrade(upload) }
        result.proposals.forEach(absorb)
        await refreshQuietly()
        return result
    }

    /// The phone's effort guess for a run (`POST /effort`).
    func submitEffort(_ upload: RunPlanV2EffortUpload) async throws -> RunPlanV2EffortResult {
        try await call { try await RunPlanV2Service.submitEffort(upload) }
    }

    /// The user's 1–10 answer. The server may answer with an
    /// `effort_fatigue` / `effort_progression` proposal; the plan is refetched.
    func rateEffort(workoutId: String, rating: Int?) async throws -> RunPlanV2RatingResult {
        let result = try await call { try await RunPlanV2Service.rateEffort(workoutId: workoutId, rating: rating) }
        result.proposals.forEach(absorb)
        await refreshQuietly()
        return result
    }

    func setCoachOptOut(_ optOut: Bool) async throws {
        let ai = try await call { try await RunPlanV2Service.setCoachOptOut(optOut) }
        setAI(ai)
    }

    func setAnthropicConsent(_ accepted: Bool) async throws {
        let ai = try await call { try await RunPlanV2Service.setAnthropicConsent(accepted) }
        setAI(ai)
    }

    /// A proposal the phone's coach (or the server's Anthropic coach) made.
    func absorb(_ proposal: RunPlanV2Proposal) {
        guard proposal.isPending else { return }
        if proposal.isWalkSuggestion {
            suggestions.removeAll { $0.id == proposal.id || overlaps($0, proposal) }
            suggestions.append(proposal)
        } else {
            pendingProposals.removeAll { $0.id == proposal.id || overlaps($0, proposal) }
            pendingProposals.append(proposal)
        }
    }

    func setFitnessProfile(_ profile: RunPlanV2FitnessProfile?) { fitnessProfile = profile }

    func noteCoachFallback(_ message: String) {
        guard coachNotice == nil else { return }
        coachNotice = message
    }

    func acknowledgeCoachNotice() { coachNotice = nil }

    /// Sign-out: the cached plan belongs to the account we're leaving.
    func reset() {
        PlanRunWatchSync.clearForSignOut()
        clearPlanState(clearCache: false)
        status = nil
        loaded = false
        plusRequired = false
        fitnessProfile = nil
        coachNotice = nil
        lastRefresh = nil
    }

    // MARK: Internals

    private func overlaps(_ a: RunPlanV2Proposal, _ b: RunPlanV2Proposal) -> Bool {
        // The server supersedes an older pending proposal touching the same date.
        a.changes.contains { c in b.changes.contains { $0.local_date == c.local_date } }
    }

    private func afterDecision() async {
        await refreshQuietly()
    }

    private func setAI(_ ai: RunPlanV2AI) {
        status?.ai = ai
        current?.ai = ai
    }

    private func call<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let e as RunPlanV2Error {
            if e == .plusRequired { plusRequired = true }
            if e == .noPlan { clearPlanState() }
            // The plan moved under this proposal (or its days passed): show
            // the plan as it is now, without the stale card.
            if e.refreshesPlan { Task { await self.refreshQuietly() } }
            throw e
        } catch {
            throw RunPlanV2Error.offline
        }
    }

    private func adoptCurrent(_ fresh: RunPlanV2Current, persist: Bool = true) {
        current = fresh
        pendingProposals = fresh.pending_proposals.filter { $0.isPending && !$0.isWalkSuggestion }
        suggestions = fresh.suggestions.filter(\.isPending)
        if let ai = fresh.ai { status?.ai = ai }
        plusRequired = false
        if persist { saveCache() }
    }

    private func clearPlanState(clearCache: Bool = true) {
        current = nil
        pendingProposals = []
        suggestions = []
        scheduledProposals = []
        lastApplied = nil
        if clearCache { self.clearCache() }
    }

    private func saveCache() {
        // Keeps the goals' server estimates (request bodies never carry them).
        guard let userId, let current, let data = try? RunPlanV2GoalCache.encoder().encode(current) else { return }
        UserDefaults.standard.set(data, forKey: cachePrefix + userId)
    }

    private func clearCache() {
        guard let userId else { return }
        UserDefaults.standard.removeObject(forKey: cachePrefix + userId)
    }

    private func loadCache() -> RunPlanV2Current? {
        guard let userId, let data = UserDefaults.standard.data(forKey: cachePrefix + userId) else { return nil }
        return try? JSONDecoder().decode(RunPlanV2Current.self, from: data)
    }
}

/// Which coach drives the plan on this phone right now.
enum RunPlanV2CoachTier: String, Sendable {
    /// Code only (every Plus member).
    case formula
    /// Apple's model on this phone.
    case apple
    /// Claude, run by our server.
    case anthropic

    var isAI: Bool { self != .formula }
}
