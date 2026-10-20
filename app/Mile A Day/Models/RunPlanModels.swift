import Foundation

// Run Plans (Mile A Day+) — the wire types for `/run-plans/*`.
//
// The backend's rules engine owns every number: these types only carry what
// it decided. Keys are the server's snake_case, like every other DTO here.
// Decoding is deliberately lenient (optionals, numbers that may arrive as
// Postgres `numeric` strings, unknown kinds) so a field the server adds or
// reshapes later degrades a row instead of failing the whole screen. The
// pre-run wizard, GhostCoach's plan mode and the Watch consume these too.

// MARK: - Lenient number

/// A Double that also decodes from a numeric string ("2.50" — node-pg's
/// default for `numeric`) and treats a missing key or null as nil.
@propertyWrapper
struct RunPlanNumber: Codable, Equatable, Hashable, Sendable {
    var wrappedValue: Double?

    init(wrappedValue: Double?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            wrappedValue = nil
        } else if let d = try? c.decode(Double.self) {
            wrappedValue = d
        } else if let s = try? c.decode(String.self) {
            wrappedValue = Double(s)
        } else {
            wrappedValue = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let wrappedValue { try c.encode(wrappedValue) } else { try c.encodeNil() }
    }
}

extension KeyedDecodingContainer {
    /// A missing key is nil, not a `keyNotFound`.
    func decode(_ type: RunPlanNumber.Type, forKey key: Key) throws -> RunPlanNumber {
        try decodeIfPresent(type, forKey: key) ?? RunPlanNumber(wrappedValue: nil)
    }
}

// MARK: - Enums

/// The only things anyone (Flamey, Claude, the user) can ask the engine for.
enum RunPlanAction: String, Codable, CaseIterable, Sendable {
    case easier
    case shorter
    case justMile = "just_mile"
    case harder
    case swapHardToday = "swap_hard_today"
    /// Tomorrow becomes a streak mile (never a skipped day).
    case restTomorrow = "rest_tomorrow"
    /// `params: { from, to }` (local dates).
    case move
    /// Claude only: `params: { local_date, kind, distance_mi, segments? }`.
    case setDay = "set_day"

    /// The pre-run / chip adjustments `POST /run-plans/days/:date/adjust` takes.
    static let dayAdjustments: [RunPlanAction] = [.easier, .shorter, .justMile]
}

enum RunPlanDayKind: String, Codable, CaseIterable, Sendable {
    case streak, easy, intervals, tempo, long
    case raceTest = "race_test"

    /// Hard = intervals/tempo/long/race_test (the engine's spacing rule).
    var isHard: Bool {
        switch self {
        case .intervals, .tempo, .long, .raceTest: return true
        case .streak, .easy: return false
        }
    }
}

/// Derived on read by the server.
enum RunPlanDayStatus: String, Codable, Sendable {
    case done, partial, missed, today, planned
}

enum RunPlanFeeling: String, Codable, CaseIterable, Identifiable, Sendable {
    case tired, sore, normal, great

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .tired: return "😴"
        case .sore: return "🤕"
        case .normal: return "🙂"
        case .great: return "🔥"
        }
    }

    var label: String {
        switch self {
        case .tired: return "Tired"
        case .sore: return "Sore"
        case .normal: return "Normal"
        case .great: return "Great"
        }
    }
}

enum RunPlanGoalType: String, Codable, CaseIterable, Identifiable, Sendable {
    case fasterMile = "faster_mile"
    case fiveK = "5k"
    case tenK = "10k"
    case half
    case marathon
    case firstFiveK = "first_5k"
    case moreMiles = "more_miles"

    var id: String { rawValue }

    /// Race distance in miles, for goals that are a race time.
    var raceMiles: Double? {
        switch self {
        case .fasterMile: return 1
        case .fiveK, .firstFiveK: return 3.10686
        case .tenK: return 6.21371
        case .half: return 13.1094
        case .marathon: return 26.2188
        case .moreMiles: return nil
        }
    }
}

// MARK: - Plan

struct RunPlanGoal: Codable, Equatable, Hashable, Sendable {
    let type: String
    /// Target race time for the goal's distance (nil = just finish / keep improving).
    @RunPlanNumber var target_seconds: Double?
    @RunPlanNumber var distance_mi: Double?

    init(type: RunPlanGoalType, targetSeconds: Double? = nil, distanceMiles: Double? = nil) {
        self.type = type.rawValue
        self.target_seconds = targetSeconds
        self.distance_mi = distanceMiles
    }

    var goalType: RunPlanGoalType? { RunPlanGoalType(rawValue: type) }
}

/// An intermediate target when the goal is far ("sub-24 first").
struct RunPlanCheckpoint: Codable, Equatable, Hashable, Sendable {
    let type: String?
    @RunPlanNumber var target_seconds: Double?
    let by_date: String?
    /// Server-written sentence, when it sends one.
    let label: String?
}

struct RunPlan: Codable, Equatable, Hashable, Identifiable, Sendable {
    let plan_id: String
    let status: String?
    let goals: [RunPlanGoal]
    /// 1 Easy does it · 2 Steady · 3 Push · 4 All in.
    let effort: Int
    /// Override 1–7; nil = from effort.
    let hard_days: Int?
    let run_daily_mile: Bool?
    /// Local date; nil = keep improving.
    let finish_by: String?
    let claude_auto_apply: Bool?
    let checkpoints: [RunPlanCheckpoint]?
    /// 1-based plan week, when the server sends it (else derive from `created_at`).
    let week: Int?
    let created_at: String?
    let updated_at: String?

    var id: String { plan_id }
    var autoApplyClaude: Bool { claude_auto_apply ?? false }
}

// MARK: - Days

/// One interval-session block. Live coaching walks these in order.
struct RunPlanSegment: Codable, Equatable, Hashable, Sendable {
    /// warmup | work | recover | cooldown | steady
    let kind: String
    @RunPlanNumber var distance_mi: Double?
    @RunPlanNumber var duration_s: Double?
    /// Seconds per MILE.
    @RunPlanNumber var target_pace_s: Double?
    /// 1-based rep number within `reps`.
    let rep: Int?
    let reps: Int?

    var isWork: Bool { kind == "work" }
}

/// What the user actually ran on a planned day (counted workouts).
struct RunPlanCompleted: Codable, Equatable, Hashable, Sendable {
    let workout_ids: [String]?
    @RunPlanNumber var distance_mi: Double?
    /// Seconds per mile.
    @RunPlanNumber var avg_pace_s: Double?
    @RunPlanNumber var walk_fraction: Double?
}

struct RunPlanDay: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// YYYY-MM-DD, the user's local day.
    let local_date: String
    let kind: String
    let title: String?
    @RunPlanNumber var distance_mi: Double?
    let segments: [RunPlanSegment]?
    /// Seconds per mile for the day's main effort.
    @RunPlanNumber var target_pace_s: Double?
    /// Flamey's / the engine's note for the day.
    let note: String?
    let status: String?
    /// Changed from the engine's original (draws the gold dot).
    let moved: Bool?
    /// engine | flamey | claude | user
    let source: String?
    let completed: RunPlanCompleted?

    var id: String { local_date }
    var dayKind: RunPlanDayKind { RunPlanDayKind(rawValue: kind) ?? .easy }
    var dayStatus: RunPlanDayStatus? { status.flatMap(RunPlanDayStatus.init(rawValue:)) }
    var miles: Double { max(distance_mi ?? 1, 0) }
    var isDone: Bool { dayStatus == .done }
    var wasMoved: Bool { moved ?? false }
    var workSegments: [RunPlanSegment] { (segments ?? []).filter(\.isWork) }
    var date: Date? { RunPlanDate.date(from: local_date) }
}

/// A day as it reads in a proposal's before/after.
struct RunPlanDaySummary: Codable, Equatable, Hashable, Sendable {
    let kind: String?
    let title: String?
    @RunPlanNumber var distance_mi: Double?
}

struct RunPlanChange: Codable, Equatable, Hashable, Sendable {
    let local_date: String
    let before: RunPlanDaySummary?
    let after: RunPlanDaySummary?
}

struct RunPlanProposal: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    /// flamey | claude | engine
    let source: String?
    let action: String?
    let summary: String?
    let rationale: String?
    let changes: [RunPlanChange]?
    /// Set when the engine clamped the request ("Capped at 8 reps…").
    let cap_note: String?
    /// pending | applied | declined | expired
    let status: String?
    let created_at: String?

    var actionKind: RunPlanAction? { action.flatMap(RunPlanAction.init(rawValue:)) }
    var isPending: Bool { status == nil || status == "pending" }
    var isApplied: Bool { status == "applied" }
    var isFromClaude: Bool { source == "claude" }
}

struct RunPlanCheckin: Codable, Equatable, Hashable, Sendable {
    let local_date: String?
    let feeling: String?
    let message: String?
    let pain_flag: Bool?
    let created_at: String?

    var feelingValue: RunPlanFeeling? { feeling.flatMap(RunPlanFeeling.init(rawValue:)) }
    /// Pain anywhere: flagged, or the Sore chip. Drives the doctor line.
    var signalsPain: Bool { pain_flag == true || feelingValue == .sore }
}

/// One of the last 7 counted runs (Flamey's context).
struct RunPlanRecentRun: Codable, Equatable, Hashable, Sendable {
    let local_date: String?
    @RunPlanNumber var distance_mi: Double?
    @RunPlanNumber var avg_pace_s: Double?
    @RunPlanNumber var moving_seconds: Double?
    @RunPlanNumber var walk_fraction: Double?
    let indoor: Bool?
    /// The planned kind for that day, when it was a plan day.
    let kind: String?
}

struct RunPlanClaudeStatus: Codable, Equatable, Hashable, Sendable {
    let connected: Bool
    let last_used_at: String?
}

/// `GET /run-plans/fitness` — baseline numbers for the setup screen.
struct RunPlanFitness: Codable, Equatable, Hashable, Sendable {
    /// Best mile split, all time / last 90 days (seconds).
    @RunPlanNumber var best_mile_s: Double?
    let best_mile_date: String?
    let best_mile_indoor: Bool?
    @RunPlanNumber var best_mile_90d_s: Double?
    /// Best ~5K effort (Riegel-normalized), seconds.
    @RunPlanNumber var best_5k_s: Double?
    /// Average miles/week, last 4 weeks.
    @RunPlanNumber var weekly_miles: Double?
    @RunPlanNumber var longest_run_mi: Double?
    /// Typical easy pace, seconds per mile.
    @RunPlanNumber var easy_pace_s: Double?
    let walk_heavy: Bool?
}

// MARK: - Responses

/// `GET /run-plans/current` (also returned by create / update / apply).
struct RunPlanCurrent: Codable, Equatable, Sendable {
    let plan: RunPlan?
    var days: [RunPlanDay]
    /// The server's today, as a Day (a bare date string decodes to nil).
    let todayDay: RunPlanDay?
    @RunPlanNumber var week_total_mi: Double?
    let checkpoints: [RunPlanCheckpoint]?
    /// Mutable so a just-made proposal can show before the next refresh.
    var pending_proposals: [RunPlanProposal]
    let recent_runs: [RunPlanRecentRun]
    let claude: RunPlanClaudeStatus?
    /// e.g. hard_days >= 5.
    let warning: String?
    /// Today's latest check-in, when the server sends it.
    let latest_checkin: RunPlanCheckin?

    enum CodingKeys: String, CodingKey {
        case plan, days, today, week_total_mi, checkpoints, pending_proposals,
             recent_runs, claude, warning, latest_checkin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try c.decodeIfPresent(RunPlan.self, forKey: .plan)
        days = (try? c.decodeIfPresent([RunPlanDay].self, forKey: .days)) ?? []
        todayDay = try? c.decodeIfPresent(RunPlanDay.self, forKey: .today)
        week_total_mi = (try? c.decode(RunPlanNumber.self, forKey: .week_total_mi))?.wrappedValue
        checkpoints = try? c.decodeIfPresent([RunPlanCheckpoint].self, forKey: .checkpoints)
        pending_proposals = (try? c.decodeIfPresent([RunPlanProposal].self, forKey: .pending_proposals)) ?? []
        recent_runs = (try? c.decodeIfPresent([RunPlanRecentRun].self, forKey: .recent_runs)) ?? []
        claude = try? c.decodeIfPresent(RunPlanClaudeStatus.self, forKey: .claude)
        warning = try? c.decodeIfPresent(String.self, forKey: .warning)
        latest_checkin = try? c.decodeIfPresent(RunPlanCheckin.self, forKey: .latest_checkin)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(plan, forKey: .plan)
        try c.encode(days, forKey: .days)
        try c.encodeIfPresent(todayDay, forKey: .today)
        try c.encode(_week_total_mi, forKey: .week_total_mi)
        try c.encodeIfPresent(checkpoints, forKey: .checkpoints)
        try c.encode(pending_proposals, forKey: .pending_proposals)
        try c.encode(recent_runs, forKey: .recent_runs)
        try c.encodeIfPresent(claude, forKey: .claude)
        try c.encodeIfPresent(warning, forKey: .warning)
        try c.encodeIfPresent(latest_checkin, forKey: .latest_checkin)
    }

    /// The plan day for a local date key.
    func day(for key: String) -> RunPlanDay? {
        if let todayDay, todayDay.local_date == key { return todayDay }
        return days.first { $0.local_date == key }
    }

    /// Today's day: the server's `today`, else the day keyed today locally.
    var today: RunPlanDay? { day(for: RunPlanDate.todayKey()) ?? todayDay }

    /// The Monday–Sunday week holding today, in date order.
    var thisWeek: [RunPlanDay] {
        let keys = Set(RunPlanDate.weekKeys(containing: Date()))
        return days.filter { keys.contains($0.local_date) }.sorted { $0.local_date < $1.local_date }
    }

    /// Planned miles this week (server's, else summed).
    var weekTotalMiles: Double { week_total_mi ?? thisWeek.reduce(0) { $0 + $1.miles } }

    var allCheckpoints: [RunPlanCheckpoint] { checkpoints ?? plan?.checkpoints ?? [] }
}

/// `POST /run-plans/checkins`.
struct RunPlanCheckinResult: Decodable, Sendable {
    let checkin: RunPlanCheckin?
    let proposal: RunPlanProposal?
}

// MARK: - Requests

struct RunPlanCreateRequest: Encodable, Sendable {
    let goals: [RunPlanGoal]
    let effort: Int
    let hard_days: Int?
    let finish_by: String?
    let run_daily_mile: Bool
    let today: String
}

/// `PATCH /run-plans/current`. Only set fields are sent; `clearHardDays` /
/// `clearFinishBy` send an explicit null (back to "from effort" / "keep improving").
struct RunPlanUpdate: Encodable, Sendable {
    var effort: Int? = nil
    var hard_days: Int? = nil
    var clearHardDays = false
    var run_daily_mile: Bool? = nil
    var claude_auto_apply: Bool? = nil
    var goals: [RunPlanGoal]? = nil
    var finish_by: String? = nil
    var clearFinishBy = false
    var today: String = RunPlanDate.todayKey()

    enum CodingKeys: String, CodingKey {
        case effort, hard_days, run_daily_mile, claude_auto_apply, goals, finish_by, today
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(effort, forKey: .effort)
        if clearHardDays { try c.encodeNil(forKey: .hard_days) } else { try c.encodeIfPresent(hard_days, forKey: .hard_days) }
        try c.encodeIfPresent(run_daily_mile, forKey: .run_daily_mile)
        try c.encodeIfPresent(claude_auto_apply, forKey: .claude_auto_apply)
        try c.encodeIfPresent(goals, forKey: .goals)
        if clearFinishBy { try c.encodeNil(forKey: .finish_by) } else { try c.encodeIfPresent(finish_by, forKey: .finish_by) }
        try c.encode(today, forKey: .today)
    }
}

// MARK: - Local dates

/// The client's local calendar day as the API's `YYYY-MM-DD` — always
/// Gregorian digits whatever calendar the phone uses.
enum RunPlanDate {
    private static var gregorian: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        cal.firstWeekday = 2 // Monday
        return cal
    }

    static func key(for date: Date) -> String {
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func todayKey() -> String { key(for: Date()) }

    static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// Monday…Sunday keys of the week holding `date`.
    static func weekKeys(containing date: Date) -> [String] {
        let cal = gregorian
        guard let start = cal.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }.map(key(for:))
    }

    static func addingDays(_ n: Int, to key: String) -> String? {
        guard let d = date(from: key), let moved = gregorian.date(byAdding: .day, value: n, to: d) else { return nil }
        return self.key(for: moved)
    }
}
