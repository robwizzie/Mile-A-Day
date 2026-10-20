import Combine
import Foundation

// MARK: - Errors

enum RunPlanError: Error, Equatable {
    /// 403 `{ error: 'plus_required' }`: Mile A Day+ lapsed or never started.
    case plusRequired
    case notFound
    case other(String)

    var message: String {
        switch self {
        case .plusRequired: return "Run plans are part of Mile A Day+."
        case .notFound: return "That's no longer there."
        case .other(let m): return m
        }
    }

    static func from(_ error: Error) -> RunPlanError {
        if let mine = error as? RunPlanError { return mine }
        if let api = error as? APIError {
            switch api {
            case .apiError(let m) where m == "plus_required": return .plusRequired
            case .notFound: return .notFound
            case .badRequest(let m): return .other(m)
            case .conflict(let m): return .other(m)
            case .rateLimited(let m): return .other(m)
            default: break
            }
        }
        return .other("Couldn't reach your plan right now. Try again in a moment.")
    }
}

// MARK: - Endpoints

/// `/run-plans/*`, Plus-gated on the server. Stateless; `RunPlanStore`
/// holds what the screens show. Every read sends the client's local day.
enum RunPlanService {
    private struct Ignored: Decodable {}
    private struct ProposalEnvelope: Decodable { let proposal: RunPlanProposal? }
    private struct FitnessEnvelope: Decodable {
        let fitness: RunPlanFitness?
        let baseline: RunPlanFitness?
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private static func run<T: Decodable>(_ endpoint: String, method: HTTPMethod = .GET, body: Data? = nil,
                                          as type: T.Type) async throws -> T {
        do {
            return try await APIClient.fancyFetch(endpoint: endpoint, method: method, body: body, responseType: type)
        } catch {
            throw RunPlanError.from(error)
        }
    }

    /// For calls whose body we don't read: an empty 200/204 isn't a failure.
    private static func runIgnoringBody(_ endpoint: String, method: HTTPMethod, body: Data? = nil) async throws {
        do {
            _ = try await APIClient.fancyFetch(endpoint: endpoint, method: method, body: body, responseType: Ignored.self)
        } catch is DecodingError {
            return
        } catch {
            throw RunPlanError.from(error)
        }
    }

    /// Accepts `{ fitness: {...} }` / `{ baseline: {...} }` or a bare object.
    static func fitness() async throws -> RunPlanFitness {
        let data = try await run("/run-plans/fitness", as: RawJSON.self).data
        if let env = try? JSONDecoder().decode(FitnessEnvelope.self, from: data), let f = env.fitness ?? env.baseline {
            return f
        }
        do {
            return try JSONDecoder().decode(RunPlanFitness.self, from: data)
        } catch {
            throw RunPlanError.other("Couldn't read your runs right now.")
        }
    }

    static func current(today: String = RunPlanDate.todayKey()) async throws -> RunPlanCurrent {
        try await run("/run-plans/current?today=\(today)", as: RunPlanCurrent.self)
    }

    static func create(_ request: RunPlanCreateRequest) async throws -> RunPlanCurrent {
        try await run("/run-plans", method: .POST, body: try encode(request), as: RunPlanCurrent.self)
    }

    static func update(_ update: RunPlanUpdate) async throws -> RunPlanCurrent {
        try await run("/run-plans/current", method: .PATCH, body: try encode(update), as: RunPlanCurrent.self)
    }

    static func endPlan() async throws {
        try await runIgnoringBody("/run-plans/current", method: .DELETE)
    }

    private struct CheckinBody: Encodable {
        let today: String
        let feeling: String?
        let message: String?
        let pain_flag: Bool?
    }

    static func checkIn(feeling: RunPlanFeeling?, message: String?, pain: Bool?,
                        today: String = RunPlanDate.todayKey()) async throws -> RunPlanCheckinResult {
        let body = CheckinBody(today: today, feeling: feeling?.rawValue, message: message, pain_flag: pain)
        return try await run("/run-plans/checkins", method: .POST, body: try encode(body), as: RunPlanCheckinResult.self)
    }

    private struct ProposeBody: Encodable {
        let today: String
        let action: String
        let summary: String?
        let rationale: String?
    }

    /// Flamey's proposal (source flamey). The engine validates and clamps it.
    static func propose(action: RunPlanAction, summary: String?, rationale: String?,
                        today: String = RunPlanDate.todayKey()) async throws -> RunPlanProposal {
        let body = try encode(ProposeBody(today: today, action: action.rawValue, summary: summary, rationale: rationale))
        let data = try await run("/run-plans/proposals", method: .POST, body: body, as: RawJSON.self).data
        if let env = try? JSONDecoder().decode(ProposalEnvelope.self, from: data), let p = env.proposal { return p }
        do {
            return try JSONDecoder().decode(RunPlanProposal.self, from: data)
        } catch {
            throw RunPlanError.other("Flamey couldn't change the plan right now.")
        }
    }

    static func apply(proposalId: String) async throws -> RunPlanCurrent {
        try await run("/run-plans/proposals/\(proposalId)/apply", method: .POST,
                      body: try encode(["today": RunPlanDate.todayKey()]), as: RunPlanCurrent.self)
    }

    static func decline(proposalId: String) async throws {
        try await runIgnoringBody("/run-plans/proposals/\(proposalId)/decline", method: .POST,
                                  body: try encode(["today": RunPlanDate.todayKey()]))
    }

    private struct AdjustBody: Encodable {
        let action: String
        let today: String
    }

    /// Pre-run chips (easier / shorter / just_mile), applied immediately.
    /// Returns the fresh plan when the server sends one.
    static func adjust(date: String, action: RunPlanAction,
                       today: String = RunPlanDate.todayKey()) async throws -> RunPlanCurrent? {
        let body = try encode(AdjustBody(action: action.rawValue, today: today))
        let data = try await run("/run-plans/days/\(date)/adjust", method: .POST, body: body, as: RawJSON.self).data
        return try? JSONDecoder().decode(RunPlanCurrent.self, from: data)
    }

    /// Revoke every coach-MCP token for this user.
    static func disconnectClaude() async throws {
        try await runIgnoringBody("/run-plans/claude", method: .DELETE)
    }
}

/// Captures a response body undecoded, for endpoints whose shape we probe.
private struct RawJSON: Decodable {
    let data: Data

    init(from decoder: Decoder) throws {
        let value = try JSONAnyValue(from: decoder)
        data = (try? JSONSerialization.data(withJSONObject: value.object, options: [.fragmentsAllowed])) ?? Data()
    }
}

/// Minimal JSON tree, so `RawJSON` can re-serialize what it was handed.
private enum JSONAnyValue: Decodable {
    case null, bool(Bool), number(Double), string(String), array([JSONAnyValue]), object([String: JSONAnyValue])

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: AnyKey.self) {
            var dict: [String: JSONAnyValue] = [:]
            for key in keyed.allKeys { dict[key.stringValue] = try keyed.decode(JSONAnyValue.self, forKey: key) }
            self = .object(dict)
            return
        }
        if var list = try? decoder.unkeyedContainer() {
            var items: [JSONAnyValue] = []
            while !list.isAtEnd { items.append(try list.decode(JSONAnyValue.self)) }
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
/// launch, refreshed on appear / foreground (throttled) and replaced by every
/// mutation's response. The pre-run wizard, GhostCoach's plan mode and the
/// Watch push read `current?.today` from here.
@MainActor
final class RunPlanStore: ObservableObject {
    static let shared = RunPlanStore()

    /// Every change re-sends today's segments to the Watch (`RunPlanWatchSync`).
    @Published private(set) var current: RunPlanCurrent? {
        didSet { RunPlanWatchSync.update(today: current?.today) }
    }
    /// A server answer (or this account's cache) is in hand.
    @Published private(set) var loaded = false
    @Published private(set) var isRefreshing = false
    /// The server said Plus is required (lapsed since the last status read).
    @Published private(set) var plusRequired = false
    @Published private(set) var fitness: RunPlanFitness?
    @Published private(set) var fitnessLoaded = false

    private var lastRefresh: Date?
    private var lastRefreshDay: String?
    private let cachePrefix = "runPlanCurrentV1|"

    private init() {
        if let cached = loadCache() {
            current = cached
            loaded = true
        }
        // `didSet` doesn't run inside init.
        RunPlanWatchSync.update(today: current?.today)
    }

    var plan: RunPlan? { current?.plan }
    var hasPlan: Bool { current?.plan != nil }
    var today: RunPlanDay? { current?.today }
    var pendingProposals: [RunPlanProposal] { (current?.pending_proposals ?? []).filter(\.isPending) }

    private var userId: String? {
        guard let id = SessionIdentity.cachedUserId, !id.isEmpty else { return nil }
        return id
    }

    // MARK: Reads

    /// Cheap to call on every appear / foreground: skips if refreshed in the
    /// last minute on the same local day.
    func refreshIfStale() async {
        let day = RunPlanDate.todayKey()
        if let lastRefresh, lastRefreshDay == day, Date().timeIntervalSince(lastRefresh) < 60 { return }
        await refresh()
    }

    func refresh() async {
        guard TokenStore.hasTokens, userId != nil, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fresh = try await RunPlanService.current()
            adopt(fresh)
        } catch RunPlanError.plusRequired {
            plusRequired = true
            current = nil
            loaded = true
            clearCache()
        } catch {
            // Keep what we have; the next appear retries.
        }
    }

    func loadFitness() async {
        guard TokenStore.hasTokens else { return }
        if let f = try? await RunPlanService.fitness() { fitness = f }
        fitnessLoaded = true
    }

    // MARK: Writes

    func create(_ request: RunPlanCreateRequest) async throws {
        do {
            let fresh = try await RunPlanService.create(request)
            adopt(fresh)
        } catch { throw note(error) }
    }

    func update(_ update: RunPlanUpdate) async throws {
        do {
            let fresh = try await RunPlanService.update(update)
            adopt(fresh)
        } catch { throw note(error) }
    }

    func endPlan() async throws {
        do {
            try await RunPlanService.endPlan()
            await refresh()
            if current?.plan != nil { current = nil }
        } catch { throw note(error) }
    }

    /// A chip or a typed check-in. A returned pending proposal joins
    /// `pendingProposals`; an applied one triggers a refresh.
    @discardableResult
    func checkIn(feeling: RunPlanFeeling?, message: String? = nil, pain: Bool? = nil) async throws -> RunPlanCheckinResult {
        do {
            let result = try await RunPlanService.checkIn(feeling: feeling, message: message, pain: pain)
            if let p = result.proposal { await absorb(p) }
            return result
        } catch { throw note(error) }
    }

    @discardableResult
    func propose(action: RunPlanAction, summary: String?, rationale: String?) async throws -> RunPlanProposal {
        do {
            let p = try await RunPlanService.propose(action: action, summary: summary, rationale: rationale)
            await absorb(p)
            return p
        } catch { throw note(error) }
    }

    func apply(_ proposal: RunPlanProposal) async throws {
        do {
            let fresh = try await RunPlanService.apply(proposalId: proposal.id)
            adopt(fresh)
        } catch { throw note(error) }
    }

    func decline(_ proposal: RunPlanProposal) async throws {
        do {
            try await RunPlanService.decline(proposalId: proposal.id)
            current?.pending_proposals.removeAll { $0.id == proposal.id }
            saveCache()
        } catch { throw note(error) }
    }

    func adjust(date: String, action: RunPlanAction) async throws {
        do {
            if let fresh = try await RunPlanService.adjust(date: date, action: action) {
                adopt(fresh)
            } else {
                await refresh()
            }
        } catch { throw note(error) }
    }

    func disconnectClaude() async throws {
        do {
            try await RunPlanService.disconnectClaude()
            await refresh()
        } catch { throw note(error) }
    }

    /// Sign-out: the cached plan belongs to the account we're leaving.
    func reset() {
        current = nil
        loaded = false
        fitness = nil
        fitnessLoaded = false
        plusRequired = false
        lastRefresh = nil
    }

    // MARK: Internals

    private func absorb(_ proposal: RunPlanProposal) async {
        if proposal.isApplied {
            await refresh()
        } else if proposal.isPending, current != nil {
            current?.pending_proposals.removeAll { $0.id == proposal.id }
            current?.pending_proposals.append(proposal)
            saveCache()
        }
    }

    private func note(_ error: Error) -> RunPlanError {
        let mapped = RunPlanError.from(error)
        if mapped == .plusRequired { plusRequired = true }
        return mapped
    }

    private func adopt(_ fresh: RunPlanCurrent) {
        current = fresh
        loaded = true
        plusRequired = false
        lastRefresh = Date()
        lastRefreshDay = RunPlanDate.todayKey()
        saveCache()
    }

    private func saveCache() {
        guard let userId else { return }
        if let current, let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: cachePrefix + userId)
        }
    }

    private func clearCache() {
        guard let userId else { return }
        UserDefaults.standard.removeObject(forKey: cachePrefix + userId)
    }

    private func loadCache() -> RunPlanCurrent? {
        guard let userId, let data = UserDefaults.standard.data(forKey: cachePrefix + userId) else { return nil }
        return try? JSONDecoder().decode(RunPlanCurrent.self, from: data)
    }
}
