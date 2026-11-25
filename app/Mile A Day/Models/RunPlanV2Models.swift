import Foundation
import os

// Run Plans v2 (Mile A Day+) — the wire types for `/run-plans/*`.
//
// Contract: plan server `mad-run-plans-api` (v1.0, Nov 25 2026). Keys are the
// server's snake_case, like every other DTO here. Decoding is deliberately
// lenient: every field is optional or defaulted, numbers also decode from
// numeric strings (node-pg sends `numeric` as "2.50"), and enums are carried
// as raw strings with a typed accessor that maps unknown values to the
// contract's fallback (unknown day kind = easy, unknown proposal kind =
// adjust). A field the server adds or reshapes later degrades one row
// instead of failing the screen.
//
// These names are shared with the live run coach and the Watch work: add
// fields and types, never rename.

// MARK: - Lenient scalars

/// A Double that also decodes from a numeric string and treats a missing key
/// or null as nil. Encodes nil as `null` (the contract's "always present").
@propertyWrapper
struct RunPlanV2Number: Codable, Equatable, Hashable, Sendable {
    var wrappedValue: Double?

    init(wrappedValue: Double?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            wrappedValue = nil
        } else if let d = try? c.decode(Double.self) {
            wrappedValue = d.isFinite ? d : nil
        } else if let s = try? c.decode(String.self) {
            wrappedValue = Double(s.trimmingCharacters(in: .whitespaces))
        } else {
            wrappedValue = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let wrappedValue, wrappedValue.isFinite { try c.encode(wrappedValue) } else { try c.encodeNil() }
    }
}

/// An Int that also decodes from a Double (rounded) or a numeric string.
@propertyWrapper
struct RunPlanV2Int: Codable, Equatable, Hashable, Sendable {
    var wrappedValue: Int?

    init(wrappedValue: Int?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            wrappedValue = nil
        } else if let i = try? c.decode(Int.self) {
            wrappedValue = i
        } else if let d = try? c.decode(Double.self), d.isFinite, abs(d) < 1e12 {
            wrappedValue = Int(d.rounded())
        } else if let s = try? c.decode(String.self), let d = Double(s.trimmingCharacters(in: .whitespaces)),
                  d.isFinite, abs(d) < 1e12 {
            wrappedValue = Int(d.rounded())
        } else {
            wrappedValue = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let wrappedValue { try c.encode(wrappedValue) } else { try c.encodeNil() }
    }
}

/// A Bool that tolerates 0/1 and "true"/"false"; missing = nil.
@propertyWrapper
struct RunPlanV2Bool: Codable, Equatable, Hashable, Sendable {
    var wrappedValue: Bool?

    init(wrappedValue: Bool?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            wrappedValue = nil
        } else if let b = try? c.decode(Bool.self) {
            wrappedValue = b
        } else if let i = try? c.decode(Int.self) {
            wrappedValue = i != 0
        } else if let s = try? c.decode(String.self) {
            wrappedValue = ["true", "1", "yes"].contains(s.lowercased())
        } else {
            wrappedValue = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let wrappedValue { try c.encode(wrappedValue) } else { try c.encodeNil() }
    }
}

/// An array that decodes a missing key, null, or a malformed value as `[]`,
/// and skips elements that fail to decode instead of failing the whole list.
@propertyWrapper
struct RunPlanV2List<Element: Codable & Equatable & Hashable & Sendable>: Codable, Equatable, Hashable, Sendable {
    var wrappedValue: [Element] = []

    init(wrappedValue: [Element]) { self.wrappedValue = wrappedValue }

    private struct Skip: Decodable {}

    init(from decoder: Decoder) throws {
        guard var list = try? decoder.unkeyedContainer() else {
            wrappedValue = []
            return
        }
        var out: [Element] = []
        while !list.isAtEnd {
            if let item = try? list.decode(Element.self) {
                out.append(item)
            } else if (try? list.decode(Skip.self)) == nil {
                // Neither decoded: the container can't advance. Stop rather than loop.
                break
            }
        }
        wrappedValue = out
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue)
    }
}

extension KeyedDecodingContainer {
    /// A missing key is nil, not a `keyNotFound`.
    func decode(_ type: RunPlanV2Number.Type, forKey key: Key) throws -> RunPlanV2Number {
        (try? decodeIfPresent(type, forKey: key)) ?? RunPlanV2Number(wrappedValue: nil)
    }

    func decode(_ type: RunPlanV2Int.Type, forKey key: Key) throws -> RunPlanV2Int {
        (try? decodeIfPresent(type, forKey: key)) ?? RunPlanV2Int(wrappedValue: nil)
    }

    func decode(_ type: RunPlanV2Bool.Type, forKey key: Key) throws -> RunPlanV2Bool {
        (try? decodeIfPresent(type, forKey: key)) ?? RunPlanV2Bool(wrappedValue: nil)
    }

    func decode<E>(_ type: RunPlanV2List<E>.Type, forKey key: Key) throws -> RunPlanV2List<E> {
        (try? decodeIfPresent(type, forKey: key)) ?? RunPlanV2List(wrappedValue: [])
    }
}

// MARK: - Dates

/// The phone's local calendar day as the contract's `"YYYY-MM-DD"`. Always
/// Gregorian + POSIX so a Buddhist/Japanese calendar setting can't send a
/// year the server rejects as `invalid_today`.
enum RunPlanV2Date {
    private static let lock = OSAllocatedUnfairLock()
    private static var cached: (DateFormatter, String)?

    private static func formatter() -> DateFormatter {
        let tz = TimeZone.current
        lock.lock(); defer { lock.unlock() }
        if let (f, id) = cached, id == tz.identifier { return f }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd"
        cached = (f, tz.identifier)
        return f
    }

    static func todayKey(_ now: Date = Date()) -> String { formatter().string(from: now) }
    static func key(for date: Date) -> String { formatter().string(from: date) }
    /// Local midnight of the key's day.
    static func date(from key: String) -> Date? { formatter().date(from: key) }

    static func addingDays(_ days: Int, to key: String) -> String? {
        guard let d = date(from: key) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(byAdding: .day, value: days, to: d).map(self.key(for:))
    }

    /// ISO-8601 UTC with milliseconds, like the server's timestamps.
    static func timestamp(_ date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    static func parseTimestamp(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// MARK: - Enums (typed views over raw strings)

enum RunPlanV2GoalType: String, Codable, CaseIterable, Sendable {
    case distanceTime = "distance_time"
    case justImprove = "just_improve"
    case burnCalories = "burn_calories"
}

enum RunPlanV2GoalDistance: String, Codable, CaseIterable, Sendable {
    case mile, fiveK = "5k", tenK = "10k", half, marathon, custom

    /// Race distance in miles (custom: nil, the goal carries `distance_mi`).
    var miles: Double? {
        switch self {
        case .mile: return 1.0
        case .fiveK: return 3.11
        case .tenK: return 6.21
        case .half: return 13.11
        case .marathon: return 26.22
        case .custom: return nil
        }
    }
}

/// 1 Easy does it · 2 Steady · 3 Push · 4 All in.
enum RunPlanV2Difficulty: Int, Codable, CaseIterable, Sendable {
    case easy = 1, steady = 2, push = 3, allIn = 4
}

enum RunPlanV2WalkMode: String, Codable, CaseIterable, Sendable {
    case builtIn = "built_in"
    case fixed
    case flexible
}

enum RunPlanV2DayKind: String, Codable, CaseIterable, Sendable {
    case easy, long, tempo, intervals, race, calibration, walk

    /// Contract: unknown day kinds are treated as `easy`.
    init(raw: String?) { self = raw.flatMap(RunPlanV2DayKind.init(rawValue:)) ?? .easy }

    var isRun: Bool { self != .walk }
    /// The shoe slot this kind draws from (`shoe_assignments` key).
    var shoeRunType: RunPlanV2ShoeRunType {
        switch self {
        case .easy, .calibration: return .easy
        case .long: return .long
        case .tempo: return .tempo
        case .intervals: return .intervals
        case .race: return .race
        case .walk: return .walk
        }
    }
}

enum RunPlanV2SegmentKind: String, Codable, CaseIterable, Sendable {
    case warmup, steady, work, recover, cooldown, walk

    init(raw: String?) { self = raw.flatMap(RunPlanV2SegmentKind.init(rawValue:)) ?? .steady }
}

enum RunPlanV2Phase: String, Codable, CaseIterable, Sendable {
    case base, build, peak, taper, race, rolling, cutback
    case returning = "return"
}

enum RunPlanV2DayStatus: String, Codable, CaseIterable, Sendable {
    case planned, today, done, partial, missed
    case walkDone = "walk_done"

    init(raw: String?) { self = raw.flatMap(RunPlanV2DayStatus.init(rawValue:)) ?? .planned }

    var isComplete: Bool { self == .done || self == .walkDone }
}

enum RunPlanV2ProposalSource: String, Codable, CaseIterable, Sendable {
    case formula, apple, anthropic, overseer
    case userClaude = "user_claude"
    case user
}

enum RunPlanV2ProposalStatus: String, Codable, CaseIterable, Sendable {
    case pending
    /// "Apply after today's run".
    case scheduled
    case applied, declined, superseded, undone, expired

    init(raw: String?) { self = raw.flatMap(RunPlanV2ProposalStatus.init(rawValue:)) ?? .pending }
}

enum RunPlanV2ProposalKind: String, Codable, CaseIterable, Sendable {
    case adjust
    case missedRun = "missed_run"
    case returnFromBreak = "return_from_break"
    case paceUpdate = "pace_update"
    case checkin
    case walkDayEarned = "walk_day_earned"
    case walkDayNeeded = "walk_day_needed"
    case postRun = "post_run"
    case weeklyReview = "weekly_review"
    case planBuild = "plan_build"

    /// Contract: unknown proposal kinds are treated as `adjust`.
    init(raw: String?) { self = raw.flatMap(RunPlanV2ProposalKind.init(rawValue:)) ?? .adjust }
}

enum RunPlanV2AIMode: String, Codable, CaseIterable, Sendable {
    case off, apple, anthropic
}

/// `ai.effective`: the provider the app must use now.
enum RunPlanV2Effective: String, Codable, CaseIterable, Sendable {
    /// Use Apple's model if this phone supports it, else the formula plan.
    case apple
    /// The server runs Claude; just call `/coach/anthropic`.
    case anthropic
    case formula
}

enum RunPlanV2AICallKind: String, Codable, CaseIterable, Sendable {
    case planBuild = "plan_build"
    case adjust, checkin, chat, notes
    case postRun = "post_run"
    case weeklyReview = "weekly_review"
}

enum RunPlanV2AICallTrigger: String, Codable, CaseIterable, Sendable {
    case afterRun = "after_run"
    case firstOpen = "first_open"
    case nightly, checkin, chat, setup
}

enum RunPlanV2ShoeRunType: String, Codable, CaseIterable, Sendable {
    case easy, long, tempo, intervals, race, walk
}

enum RunPlanV2ScoreBy: String, Codable, CaseIterable, Sendable {
    case pace, hr
    case paceAndHR = "pace_and_hr"
    case effort

    init(raw: String?) { self = raw.flatMap(RunPlanV2ScoreBy.init(rawValue:)) ?? .effort }
}

// MARK: - Status / AI settings (§1)

struct RunPlanV2AI: Codable, Equatable, Hashable, Sendable {
    var ai_mode: String?
    @RunPlanV2Bool var global_enabled: Bool? = nil
    var effective: String?
    /// global_off | user_opt_out | anthropic_not_configured | anthropic_budget_exhausted
    /// | anthropic_consent_required | not_plus
    var reason: String?
    var anthropic_consent_at: String?
    @RunPlanV2Bool var user_opt_out: Bool? = nil

    var mode: RunPlanV2AIMode { ai_mode.flatMap(RunPlanV2AIMode.init(rawValue:)) ?? .apple }
    var effectiveProvider: RunPlanV2Effective {
        effective.flatMap(RunPlanV2Effective.init(rawValue:)) ?? .formula
    }
    var optedOut: Bool { user_opt_out ?? false }
    var hasAnthropicConsent: Bool { !(anthropic_consent_at ?? "").isEmpty }
    var needsAnthropicConsent: Bool {
        mode == .anthropic && reason == "anthropic_consent_required"
    }

    static let formulaOnly = RunPlanV2AI(ai_mode: "off", global_enabled: false, effective: "formula",
                                         reason: nil, anthropic_consent_at: nil, user_opt_out: false)
}

struct RunPlanV2Status: Codable, Equatable, Hashable, Sendable {
    @RunPlanV2Bool var plus: Bool? = nil
    @RunPlanV2Bool var has_plan: Bool? = nil
    var plan_id: String?
    var ai: RunPlanV2AI?
    var fitness_profile_at: String?
    @RunPlanV2Int var pending_proposals: Int? = nil

    var isPlus: Bool { plus ?? false }
    var hasPlan: Bool { has_plan ?? false }
}

// MARK: - Fitness profile (§2)

struct RunPlanV2Zone: Codable, Equatable, Hashable, Sendable {
    @RunPlanV2Int var zone: Int? = nil
    @RunPlanV2Int var low: Int? = nil
    @RunPlanV2Int var high: Int? = nil

    init(zone: Int, low: Int, high: Int) {
        self.zone = zone
        self.low = low
        self.high = high
    }
}

struct RunPlanV2BestEffort: Codable, Equatable, Hashable, Sendable {
    /// mile | 5k | 10k | half | marathon (goal distance keys)
    var distance: String?
    @RunPlanV2Int var seconds: Int? = nil
    var date: String?
    @RunPlanV2Bool var indoor: Bool? = nil

    init(distance: String, seconds: Int, date: String?, indoor: Bool?) {
        self.distance = distance
        self.seconds = seconds
        self.date = date
        self.indoor = indoor
    }
}

struct RunPlanV2RaceEstimates: Codable, Equatable, Hashable, Sendable {
    @RunPlanV2Int var mile_s: Int? = nil
    @RunPlanV2Int var five_k_s: Int? = nil
    @RunPlanV2Int var ten_k_s: Int? = nil
    @RunPlanV2Int var half_s: Int? = nil
    @RunPlanV2Int var marathon_s: Int? = nil

    enum CodingKeys: String, CodingKey {
        case mile_s
        case five_k_s = "5k_s"
        case ten_k_s = "10k_s"
        case half_s, marathon_s
    }

    init(mile_s: Int? = nil, five_k_s: Int? = nil, ten_k_s: Int? = nil, half_s: Int? = nil, marathon_s: Int? = nil) {
        self.mile_s = mile_s
        self.five_k_s = five_k_s
        self.ten_k_s = ten_k_s
        self.half_s = half_s
        self.marathon_s = marathon_s
    }

    func seconds(for distance: RunPlanV2GoalDistance) -> Int? {
        switch distance {
        case .mile: return mile_s
        case .fiveK: return five_k_s
        case .tenK: return ten_k_s
        case .half: return half_s
        case .marathon: return marathon_s
        case .custom: return nil
        }
    }
}

struct RunPlanV2SteadySegments: Codable, Equatable, Hashable, Sendable {
    @RunPlanV2Int var count: Int? = nil
    @RunPlanV2Int var minutes: Int? = nil
    @RunPlanV2Int var median_pace_s: Int? = nil
    @RunPlanV2Int var median_hr: Int? = nil
    @RunPlanV2Number var cardiac_drift_pct: Double? = nil
    @RunPlanV2Int var longest_steady_min: Int? = nil

    init(count: Int?, minutes: Int?, median_pace_s: Int?, median_hr: Int?,
         cardiac_drift_pct: Double?, longest_steady_min: Int?) {
        self.count = count
        self.minutes = minutes
        self.median_pace_s = median_pace_s
        self.median_hr = median_hr
        self.cardiac_drift_pct = cardiac_drift_pct
        self.longest_steady_min = longest_steady_min
    }
}

struct RunPlanV2RunWalk: Codable, Equatable, Hashable, Sendable {
    @RunPlanV2Number var walk_break_runs_fraction: Double? = nil
    @RunPlanV2Int var typical_run_s: Int? = nil
    @RunPlanV2Int var typical_walk_s: Int? = nil

    init(walk_break_runs_fraction: Double?, typical_run_s: Int?, typical_walk_s: Int?) {
        self.walk_break_runs_fraction = walk_break_runs_fraction
        self.typical_run_s = typical_run_s
        self.typical_walk_s = typical_walk_s
    }
}

/// The compact profile the phone computes from the last 100 runs
/// (`RunFitnessAnalyzer`). Raw samples never leave the phone.
struct RunPlanV2FitnessProfile: Codable, Equatable, Hashable, Sendable {
    var today: String?
    var computed_at: String?
    @RunPlanV2Int var runs_analyzed: Int? = nil
    var first_run_date: String?
    @RunPlanV2Number var total_miles: Double? = nil
    @RunPlanV2Number var weekly_miles_4w: Double? = nil
    @RunPlanV2List var weekly_miles_by_week: [Double] = []
    @RunPlanV2Number var longest_run_30d_mi: Double? = nil
    @RunPlanV2Number var longest_run_mi: Double? = nil
    @RunPlanV2Number var treadmill_fraction: Double? = nil
    @RunPlanV2Bool var has_hr: Bool? = nil
    @RunPlanV2Int var max_hr: Int? = nil
    /// observed | tanaka
    var max_hr_source: String?
    @RunPlanV2Int var resting_hr: Int? = nil
    /// Oldest first; null entries are days with no reading.
    var resting_hr_7d: [Int?]?
    var hrv_7d_ms: [Int?]?
    @RunPlanV2Int var hrv_baseline_ms: Int? = nil
    @RunPlanV2Int var lthr: Int? = nil
    @RunPlanV2List var zones: [RunPlanV2Zone] = []
    /// lthr | hrr | hrmax | nil (no HR: effort cues only)
    var zone_method: String?
    @RunPlanV2Number var vdot: Double? = nil
    @RunPlanV2Number var critical_speed_mps: Double? = nil
    @RunPlanV2Int var zone2_pace_s: Int? = nil
    @RunPlanV2Int var zone2_hr: Int? = nil
    @RunPlanV2Int var easy_pace_s: Int? = nil
    @RunPlanV2List var best_efforts: [RunPlanV2BestEffort] = []
    var race_estimates: RunPlanV2RaceEstimates?
    var steady_segments: RunPlanV2SteadySegments?
    var run_walk: RunPlanV2RunWalk?
    @RunPlanV2Int var typical_run_hour: Int? = nil
    @RunPlanV2Int var age: Int? = nil
    /// new | novice | experienced
    var experience: String?
    @RunPlanV2Bool var calibration_needed: Bool? = nil
    /// mile_tt_talk_test | 3k | 5k | lthr_30min
    var calibration_kind: String?

    init() {
        weekly_miles_by_week = []
        zones = []
        best_efforts = []
    }

    var hasHeartRate: Bool { has_hr ?? false }
    var needsCalibration: Bool { calibration_needed ?? false }
}

struct RunPlanV2FitnessProfileEnvelope: Codable, Equatable, Sendable {
    var profile: RunPlanV2FitnessProfile?
    var updated_at: String?
}

// MARK: - Plan (§3)

struct RunPlanV2Goal: Codable, Equatable, Hashable, Sendable {
    var type: String
    /// mile | 5k | 10k | half | marathon | custom (distance_time only)
    var distance: String?
    @RunPlanV2Number var distance_mi: Double? = nil
    @RunPlanV2Int var target_s: Int? = nil
    /// The server's estimate from the fitness profile (response only).
    @RunPlanV2Int var current_s: Int? = nil
    /// burn_calories only.
    @RunPlanV2Int var weekly_minutes: Int? = nil

    init(type: RunPlanV2GoalType, distance: RunPlanV2GoalDistance? = nil, distanceMi: Double? = nil,
         targetSeconds: Int? = nil, weeklyMinutes: Int? = nil) {
        self.type = type.rawValue
        self.distance = distance?.rawValue
        self.distance_mi = distanceMi
        self.target_s = targetSeconds
        self.current_s = nil
        self.weekly_minutes = weeklyMinutes
    }

    enum CodingKeys: String, CodingKey {
        case type, distance, distance_mi, target_s, current_s, weekly_minutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? RunPlanV2GoalType.justImprove.rawValue
        distance = try? c.decodeIfPresent(String.self, forKey: .distance)
        _distance_mi = try c.decode(RunPlanV2Number.self, forKey: .distance_mi)
        _target_s = try c.decode(RunPlanV2Int.self, forKey: .target_s)
        _current_s = try c.decode(RunPlanV2Int.self, forKey: .current_s)
        _weekly_minutes = try c.decode(RunPlanV2Int.self, forKey: .weekly_minutes)
    }

    /// Request bodies send only what the goal uses (no nulls for unused keys).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(distance, forKey: .distance)
        try c.encodeIfPresent(distance_mi, forKey: .distance_mi)
        try c.encodeIfPresent(target_s, forKey: .target_s)
        try c.encodeIfPresent(current_s, forKey: .current_s)
        try c.encodeIfPresent(weekly_minutes, forKey: .weekly_minutes)
    }

    var goalType: RunPlanV2GoalType { RunPlanV2GoalType(rawValue: type) ?? .justImprove }
    var goalDistance: RunPlanV2GoalDistance? { distance.flatMap(RunPlanV2GoalDistance.init(rawValue:)) }
    var miles: Double? { distance_mi ?? goalDistance?.miles }
}

struct RunPlanV2Checkpoint: Codable, Equatable, Hashable, Sendable {
    var label: String?
    @RunPlanV2Int var goal_index: Int? = nil
    @RunPlanV2Int var target_s: Int? = nil
    @RunPlanV2Int var eta_week: Int? = nil
}

/// `shoe_assignments`: run type → shoe id (null = none).
typealias RunPlanV2ShoeAssignments = [String: String?]

struct RunPlanV2Plan: Codable, Equatable, Hashable, Sendable, Identifiable {
    var plan_id: String
    var status: String?
    @RunPlanV2List var goals: [RunPlanV2Goal] = []
    var target_date: String?
    @RunPlanV2Int var runs_per_week: Int? = nil
    @RunPlanV2Int var difficulty: Int? = nil
    var walk_mode: String?
    @RunPlanV2List var fixed_walk_days: [Int] = []
    var coach_notes: String?
    var shoe_assignments: RunPlanV2ShoeAssignments?
    @RunPlanV2Int var hard_sessions_per_week: Int? = nil
    var start_date: String?
    @RunPlanV2Int var week_index: Int? = nil
    var phase: String?
    @RunPlanV2Number var weekly_target_mi: Double? = nil
    @RunPlanV2List var checkpoints: [RunPlanV2Checkpoint] = []
    var created_at: String?
    var updated_at: String?

    enum CodingKeys: String, CodingKey {
        case plan_id, status, goals, target_date, runs_per_week, difficulty, walk_mode, fixed_walk_days,
             coach_notes, shoe_assignments, hard_sessions_per_week, start_date, week_index, phase,
             weekly_target_mi, checkpoints, created_at, updated_at
        case id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan_id = (try? c.decodeIfPresent(String.self, forKey: .plan_id))
            ?? (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        _goals = try c.decode(RunPlanV2List<RunPlanV2Goal>.self, forKey: .goals)
        target_date = try? c.decodeIfPresent(String.self, forKey: .target_date)
        _runs_per_week = try c.decode(RunPlanV2Int.self, forKey: .runs_per_week)
        _difficulty = try c.decode(RunPlanV2Int.self, forKey: .difficulty)
        walk_mode = try? c.decodeIfPresent(String.self, forKey: .walk_mode)
        _fixed_walk_days = try c.decode(RunPlanV2List<Int>.self, forKey: .fixed_walk_days)
        coach_notes = try? c.decodeIfPresent(String.self, forKey: .coach_notes)
        shoe_assignments = try? c.decodeIfPresent(RunPlanV2ShoeAssignments.self, forKey: .shoe_assignments)
        _hard_sessions_per_week = try c.decode(RunPlanV2Int.self, forKey: .hard_sessions_per_week)
        start_date = try? c.decodeIfPresent(String.self, forKey: .start_date)
        _week_index = try c.decode(RunPlanV2Int.self, forKey: .week_index)
        phase = try? c.decodeIfPresent(String.self, forKey: .phase)
        _weekly_target_mi = try c.decode(RunPlanV2Number.self, forKey: .weekly_target_mi)
        _checkpoints = try c.decode(RunPlanV2List<RunPlanV2Checkpoint>.self, forKey: .checkpoints)
        created_at = try? c.decodeIfPresent(String.self, forKey: .created_at)
        updated_at = try? c.decodeIfPresent(String.self, forKey: .updated_at)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(plan_id, forKey: .plan_id)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encode(goals, forKey: .goals)
        try c.encodeIfPresent(target_date, forKey: .target_date)
        try c.encodeIfPresent(runs_per_week, forKey: .runs_per_week)
        try c.encodeIfPresent(difficulty, forKey: .difficulty)
        try c.encodeIfPresent(walk_mode, forKey: .walk_mode)
        try c.encode(fixed_walk_days, forKey: .fixed_walk_days)
        try c.encodeIfPresent(coach_notes, forKey: .coach_notes)
        try c.encodeIfPresent(shoe_assignments, forKey: .shoe_assignments)
        try c.encodeIfPresent(hard_sessions_per_week, forKey: .hard_sessions_per_week)
        try c.encodeIfPresent(start_date, forKey: .start_date)
        try c.encodeIfPresent(week_index, forKey: .week_index)
        try c.encodeIfPresent(phase, forKey: .phase)
        try c.encodeIfPresent(weekly_target_mi, forKey: .weekly_target_mi)
        try c.encode(checkpoints, forKey: .checkpoints)
        try c.encodeIfPresent(created_at, forKey: .created_at)
        try c.encodeIfPresent(updated_at, forKey: .updated_at)
    }

    var id: String { plan_id }
    var walkMode: RunPlanV2WalkMode { walk_mode.flatMap(RunPlanV2WalkMode.init(rawValue:)) ?? .builtIn }
    var difficultyLevel: RunPlanV2Difficulty {
        difficulty.flatMap(RunPlanV2Difficulty.init(rawValue:)) ?? .steady
    }
    var phaseKind: RunPlanV2Phase? { phase.flatMap(RunPlanV2Phase.init(rawValue:)) }
    func shoeId(for type: RunPlanV2ShoeRunType) -> String? {
        shoe_assignments?[type.rawValue] ?? nil
    }
}

// MARK: - Day, segment, grade

struct RunPlanV2Segment: Codable, Equatable, Hashable, Sendable {
    /// warmup | steady | work | recover | cooldown | walk
    var kind: String?
    /// Exactly one of `distance_mi` / `duration_s` is set.
    @RunPlanV2Number var distance_mi: Double? = nil
    @RunPlanV2Int var duration_s: Int? = nil
    /// 1-based rep number within `reps` (work/recover only).
    @RunPlanV2Int var rep: Int? = nil
    @RunPlanV2Int var reps: Int? = nil
    /// Seconds per mile.
    @RunPlanV2Int var target_pace_s: Int? = nil
    /// Fastest allowed (seconds per mile).
    @RunPlanV2Int var pace_low_s: Int? = nil
    /// Slowest allowed (seconds per mile).
    @RunPlanV2Int var pace_high_s: Int? = nil
    /// 3600 / target_pace_s, 0.1 mph (treadmill cue).
    @RunPlanV2Number var speed_mph: Double? = nil
    @RunPlanV2Int var hr_low: Int? = nil
    @RunPlanV2Int var hr_high: Int? = nil
    @RunPlanV2Int var zone: Int? = nil
    /// pace | hr | pace_and_hr | effort
    var score_by: String?
    /// For no-watch users: how it should feel.
    var feel: String?

    var segmentKind: RunPlanV2SegmentKind { RunPlanV2SegmentKind(raw: kind) }
    var scoreBy: RunPlanV2ScoreBy { RunPlanV2ScoreBy(raw: score_by) }
    var isWork: Bool { segmentKind == .work }
    var hasPaceBand: Bool { pace_low_s != nil && pace_high_s != nil }
    var hasHRBand: Bool { hr_low != nil && hr_high != nil }
}

struct RunPlanV2DayShoe: Codable, Equatable, Hashable, Sendable {
    var shoe_id: String?
    var name: String?
    var brand: String?
}

struct RunPlanV2Completed: Codable, Equatable, Hashable, Sendable {
    @RunPlanV2List var workout_ids: [String] = []
    @RunPlanV2Number var distance_mi: Double? = nil
    @RunPlanV2Int var duration_s: Int? = nil
    @RunPlanV2Int var avg_pace_s: Int? = nil
}

struct RunPlanV2Grade: Codable, Equatable, Hashable, Sendable {
    @RunPlanV2Int var score: Int? = nil
    @RunPlanV2Int var completion: Int? = nil
    @RunPlanV2Int var on_target: Int? = nil
    @RunPlanV2Int var consistency: Int? = nil
    /// phone | server
    var source: String?
    var summary: String?
    /// template | apple | anthropic | …
    var summary_source: String?
    var workout_id: String?
    var graded_at: String?
}

/// A plan day. Also the shape of a served proposal's `before`/`after`
/// ("a full Day minus status fields"), so status-ish fields are optional.
struct RunPlanV2Day: Codable, Equatable, Hashable, Sendable, Identifiable {
    var local_date: String?
    /// 0 = Monday … 6 = Sunday.
    @RunPlanV2Int var weekday: Int? = nil
    var kind: String?
    var title: String?
    var subtitle: String?
    @RunPlanV2Number var distance_mi: Double? = nil
    @RunPlanV2Int var est_duration_s: Int? = nil
    @RunPlanV2Bool var is_hard: Bool? = nil
    @RunPlanV2Bool var is_key: Bool? = nil
    /// Flexible walk mode: this run may become a walk day.
    @RunPlanV2Bool var flex: Bool? = nil
    var phase: String?
    @RunPlanV2Int var week_index: Int? = nil
    @RunPlanV2List var segments: [RunPlanV2Segment] = []
    var note: String?
    /// template | apple | anthropic | overseer | user_claude
    var note_source: String?
    var shoe: RunPlanV2DayShoe?
    var status: String?
    var completed: RunPlanV2Completed?
    var grade: RunPlanV2Grade?
    @RunPlanV2List var pending_proposal_ids: [String] = []
    @RunPlanV2Int var version: Int? = nil

    var id: String { local_date ?? "\(kind ?? "day")-\(title ?? "")" }
    var dateKey: String { local_date ?? "" }
    var date: Date? { local_date.flatMap(RunPlanV2Date.date(from:)) }
    var dayKind: RunPlanV2DayKind { RunPlanV2DayKind(raw: kind) }
    var dayStatus: RunPlanV2DayStatus { RunPlanV2DayStatus(raw: status) }
    var isWalk: Bool { dayKind == .walk }
    var isHard: Bool { is_hard ?? false }
    var isKey: Bool { is_key ?? false }
    var isFlex: Bool { flex ?? false }
    var miles: Double { max(distance_mi ?? 0, 0) }
    var workSegments: [RunPlanV2Segment] { segments.filter(\.isWork) }
    var hasPendingProposal: Bool { !pending_proposal_ids.isEmpty }
    /// Note written by a model (Flamey's own words) rather than a template.
    var noteIsAI: Bool { ["apple", "anthropic", "overseer", "user_claude"].contains(note_source ?? "") }
}

// MARK: - DaySpec (§5: what the model / user sends; the server computes the rest)

struct RunPlanV2DaySpec: Codable, Equatable, Hashable, Sendable {
    var kind: String
    var distance_mi: Double?
    var work_mi: Double?
    var reps: Int?
    var rep_mi: Double?
    var rep_s: Int?
    var recover_s: Int?
    /// 0.85–1.15 scales computed paces (>1 slower). nil = 1.0.
    var pace_factor: Double?
    var note: String?

    init(kind: RunPlanV2DayKind, distanceMi: Double? = nil, workMi: Double? = nil, reps: Int? = nil,
         repMi: Double? = nil, repSeconds: Int? = nil, recoverSeconds: Int? = nil,
         paceFactor: Double? = nil, note: String? = nil) {
        self.kind = kind.rawValue
        self.distance_mi = distanceMi
        self.work_mi = workMi
        self.reps = reps
        self.rep_mi = repMi
        self.rep_s = repSeconds
        self.recover_s = recoverSeconds
        self.pace_factor = paceFactor
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case kind, distance_mi, work_mi, reps, rep_mi, rep_s, recover_s, pace_factor, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? RunPlanV2DayKind.easy.rawValue
        distance_mi = (try c.decode(RunPlanV2Number.self, forKey: .distance_mi)).wrappedValue
        work_mi = (try c.decode(RunPlanV2Number.self, forKey: .work_mi)).wrappedValue
        reps = (try c.decode(RunPlanV2Int.self, forKey: .reps)).wrappedValue
        rep_mi = (try c.decode(RunPlanV2Number.self, forKey: .rep_mi)).wrappedValue
        rep_s = (try c.decode(RunPlanV2Int.self, forKey: .rep_s)).wrappedValue
        recover_s = (try c.decode(RunPlanV2Int.self, forKey: .recover_s)).wrappedValue
        pace_factor = (try c.decode(RunPlanV2Number.self, forKey: .pace_factor)).wrappedValue
        note = try? c.decodeIfPresent(String.self, forKey: .note)
    }

    /// Nulls are sent explicitly, like the contract's example.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(distance_mi, forKey: .distance_mi)
        try c.encode(work_mi, forKey: .work_mi)
        try c.encode(reps, forKey: .reps)
        try c.encode(rep_mi, forKey: .rep_mi)
        try c.encode(rep_s, forKey: .rep_s)
        try c.encode(recover_s, forKey: .recover_s)
        try c.encode(pace_factor, forKey: .pace_factor)
        try c.encode(note, forKey: .note)
    }

    var dayKind: RunPlanV2DayKind { RunPlanV2DayKind(raw: kind) }

    /// The spec that reproduces a served day (for "keep this day, tweak one thing").
    init(day: RunPlanV2Day) {
        let kind = day.dayKind
        self.kind = kind.rawValue
        self.note = nil
        self.pace_factor = nil
        switch kind {
        case .walk:
            distance_mi = nil; work_mi = nil; reps = nil; rep_mi = nil; rep_s = nil; recover_s = nil
        case .intervals:
            let work = day.workSegments
            distance_mi = nil
            work_mi = nil
            reps = work.first?.reps ?? (work.isEmpty ? nil : work.count)
            rep_mi = work.first?.distance_mi
            rep_s = work.first?.distance_mi == nil ? work.first?.duration_s : nil
            recover_s = day.segments.first(where: { $0.segmentKind == .recover })?.duration_s
        case .tempo:
            distance_mi = day.distance_mi
            let w = day.workSegments.compactMap(\.distance_mi).reduce(0, +)
            work_mi = w > 0 ? w : nil
            reps = nil; rep_mi = nil; rep_s = nil; recover_s = nil
        default:
            distance_mi = day.distance_mi
            work_mi = nil; reps = nil; rep_mi = nil; rep_s = nil; recover_s = nil
        }
    }
}

struct RunPlanV2DayChange: Codable, Equatable, Hashable, Sendable {
    var local_date: String
    var after: RunPlanV2DaySpec
}

struct RunPlanV2InitialDay: Codable, Equatable, Hashable, Sendable {
    var local_date: String
    var day: RunPlanV2DaySpec
}

// MARK: - Proposals (§4)

struct RunPlanV2GoalImpact: Codable, Equatable, Hashable, Sendable {
    var label: String?
    @RunPlanV2Int var before_s: Int? = nil
    @RunPlanV2Int var after_s: Int? = nil
}

struct RunPlanV2ProposalChange: Codable, Equatable, Hashable, Sendable {
    var local_date: String?
    var before: RunPlanV2Day?
    var after: RunPlanV2Day?
    @RunPlanV2Int var before_version: Int? = nil
}

struct RunPlanV2Deviation: Codable, Equatable, Hashable, Sendable {
    var rule: String?
    var message: String?
    var local_date: String?
}

struct RunPlanV2Violation: Codable, Equatable, Hashable, Sendable {
    var rule: String?
    var local_date: String?
    var message: String?
    @RunPlanV2Number var limit_mi: Double? = nil
}

struct RunPlanV2Checks: Codable, Equatable, Hashable, Sendable {
    @RunPlanV2Number var week_mi_before: Double? = nil
    @RunPlanV2Number var week_mi_after: Double? = nil
    @RunPlanV2List var hard_rules_passed: [String] = []
    @RunPlanV2List var deviations: [RunPlanV2Deviation] = []
    var deviation_reason: String?
    /// Server-written one-liner ("Checked: week goes 18 → 18.5 mi …").
    var text: String?
}

struct RunPlanV2Proposal: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: String
    var plan_id: String?
    var source: String?
    var kind: String?
    var status: String?
    var title: String?
    var reason: String?
    var goal_impact: RunPlanV2GoalImpact?
    @RunPlanV2List var changes: [RunPlanV2ProposalChange] = []
    var checks: RunPlanV2Checks?
    @RunPlanV2Bool var affects_next_run: Bool? = nil
    var first_date: String?
    var created_at: String?
    var decided_at: String?
    var applied_at: String?
    var undo_until: String?
    var apply_after_date: String?

    var proposalKind: RunPlanV2ProposalKind { RunPlanV2ProposalKind(raw: kind) }
    var proposalStatus: RunPlanV2ProposalStatus { RunPlanV2ProposalStatus(raw: status) }
    var proposalSource: RunPlanV2ProposalSource? { source.flatMap(RunPlanV2ProposalSource.init(rawValue:)) }
    var isPending: Bool { proposalStatus == .pending }
    var isScheduled: Bool { proposalStatus == .scheduled }
    var isWalkSuggestion: Bool { proposalKind == .walkDayEarned || proposalKind == .walkDayNeeded }
    /// Undo is offered while `undo_until` is in the future.
    func canUndo(now: Date = Date()) -> Bool {
        guard proposalStatus == .applied, let until = RunPlanV2Date.parseTimestamp(undo_until) else { return false }
        return until > now
    }
    func touches(_ localDate: String) -> Bool { changes.contains { $0.local_date == localDate } }
}

struct RunPlanV2ProposalRequest: Codable, Equatable, Sendable {
    var today: String
    /// apple | user (other sources are server-side only)
    var source: String
    var kind: String
    var title: String
    var reason: String
    var goal_impact: RunPlanV2GoalImpact?
    var changes: [RunPlanV2DayChange] = []
    var deviation_reason: String?
    var ai_call_id: String?
}

struct RunPlanV2HistoryEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: String
    var at: String?
    /// plan_created | settings_changed | proposal_created | proposal_applied | proposal_scheduled
    /// | proposal_declined | proposal_superseded | proposal_undone | proposal_expired
    /// | overseer_set_plan | plan_archived
    var event: String?
    var source: String?
    var proposal_id: String?
    var summary: String?
    @RunPlanV2List var dates: [String] = []
}

// MARK: - Current (§3 GET /current)

struct RunPlanV2Current: Codable, Equatable, Sendable {
    var plan: RunPlanV2Plan
    var today: RunPlanV2Day?
    @RunPlanV2List var week: [RunPlanV2Day] = []
    var next_run: RunPlanV2Day?
    @RunPlanV2List var pending_proposals: [RunPlanV2Proposal] = []
    @RunPlanV2List var suggestions: [RunPlanV2Proposal] = []
    var fitness_profile_at: String?
    var ai: RunPlanV2AI?
}

/// `POST /run-plans` and `POST /preview` responses.
struct RunPlanV2PlanWithDays: Codable, Equatable, Sendable {
    var plan: RunPlanV2Plan
    @RunPlanV2List var days: [RunPlanV2Day] = []
    @RunPlanV2List var warnings: [String] = []
}

struct RunPlanV2CreateRequest: Codable, Equatable, Sendable {
    var today: String
    var goals: [RunPlanV2Goal] = []
    var target_date: String?
    var runs_per_week: Int
    var difficulty: Int
    var walk_mode: String
    var fixed_walk_days: [Int] = []
    var coach_notes: String
    var shoe_assignments: RunPlanV2ShoeAssignments?
    var start_date: String?
    var initial_days: [RunPlanV2InitialDay]?
    /// formula | apple | anthropic
    var source: String

    enum CodingKeys: String, CodingKey {
        case today, goals, target_date, runs_per_week, difficulty, walk_mode, fixed_walk_days,
             coach_notes, shoe_assignments, start_date, initial_days, source
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(today, forKey: .today)
        try c.encode(goals, forKey: .goals)
        try c.encode(target_date, forKey: .target_date)
        try c.encode(runs_per_week, forKey: .runs_per_week)
        try c.encode(difficulty, forKey: .difficulty)
        try c.encode(walk_mode, forKey: .walk_mode)
        try c.encode(fixed_walk_days, forKey: .fixed_walk_days)
        try c.encode(coach_notes, forKey: .coach_notes)
        // Omitted = the server picks from the user's shoes.
        try c.encodeIfPresent(shoe_assignments, forKey: .shoe_assignments)
        try c.encodeIfPresent(start_date, forKey: .start_date)
        try c.encode(initial_days, forKey: .initial_days)
        try c.encode(source, forKey: .source)
    }
}

/// `PATCH /run-plans/current`: only the fields set are sent.
struct RunPlanV2PlanPatch: Encodable, Equatable, Sendable {
    var today: String = RunPlanV2Date.todayKey()
    var goals: [RunPlanV2Goal]?
    /// `.some(nil)` sends `"target_date": null` (clear the date).
    var target_date: String??
    var runs_per_week: Int?
    var difficulty: Int?
    var walk_mode: String?
    var fixed_walk_days: [Int]?
    var coach_notes: String?
    var shoe_assignments: RunPlanV2ShoeAssignments?

    enum CodingKeys: String, CodingKey {
        case today, goals, target_date, runs_per_week, difficulty, walk_mode, fixed_walk_days,
             coach_notes, shoe_assignments
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(today, forKey: .today)
        try c.encodeIfPresent(goals, forKey: .goals)
        if let target_date { try c.encode(target_date, forKey: .target_date) }
        try c.encodeIfPresent(runs_per_week, forKey: .runs_per_week)
        try c.encodeIfPresent(difficulty, forKey: .difficulty)
        try c.encodeIfPresent(walk_mode, forKey: .walk_mode)
        try c.encodeIfPresent(fixed_walk_days, forKey: .fixed_walk_days)
        try c.encodeIfPresent(coach_notes, forKey: .coach_notes)
        try c.encodeIfPresent(shoe_assignments, forKey: .shoe_assignments)
    }

    var isEmpty: Bool {
        goals == nil && target_date == nil && runs_per_week == nil && difficulty == nil && walk_mode == nil
            && fixed_walk_days == nil && coach_notes == nil && shoe_assignments == nil
    }
}

// MARK: - Check-ins (§7)

struct RunPlanV2CheckinRequest: Codable, Equatable, Sendable {
    var today: String = RunPlanV2Date.todayKey()
    var local_date: String = RunPlanV2Date.todayKey()
    /// 10–240 (60+ = 240).
    var time_available_min: Int?
    /// 0 drained … 10 energized.
    var energy: Int?
    /// 0 none … 10 very sore.
    var soreness: Int?
    /// ≤ 2× planned.
    var go_further_mi: Double?
    /// ≤ 1,000 chars, coach model only.
    var text: String?
    var coach_mode: Bool?
}

struct RunPlanV2Checkin: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: String
    var created_at: String?
    var proposal_id: String?
    var local_date: String?
    @RunPlanV2Int var time_available_min: Int? = nil
    @RunPlanV2Int var energy: Int? = nil
    @RunPlanV2Int var soreness: Int? = nil
    @RunPlanV2Number var go_further_mi: Double? = nil
    var text: String?
    @RunPlanV2Bool var coach_mode: Bool? = nil
}

struct RunPlanV2CheckinResult: Codable, Equatable, Sendable {
    var checkin: RunPlanV2Checkin?
    var proposal: RunPlanV2Proposal?
}

// MARK: - Grades (§7)

struct RunPlanV2SegmentStat: Codable, Equatable, Hashable, Sendable {
    /// Index into the day's `segments`.
    var index: Int
    /// Seconds scored (already excludes rule-16 time).
    var scored_s: Int
    var in_band_s: Int
    var too_fast_s: Int
    var too_slow_s: Int
    var avg_pace_s: Int?
    var avg_hr: Int?
}

struct RunPlanV2GradeUpload: Codable, Equatable, Sendable {
    var today: String
    var local_date: String
    var workout_id: String
    var actual_distance_mi: Double
    var segments: [RunPlanV2SegmentStat] = []
    var rep_paces_s: [Int] = []
    var easy_hr_drift_pct: Double?
    var avg_hr: Int?
}

struct RunPlanV2GradeResult: Codable, Equatable, Sendable {
    var grade: RunPlanV2Grade?
    @RunPlanV2List var proposals: [RunPlanV2Proposal] = []
}

// MARK: - Triggers (§6)

struct RunPlanV2OpenResult: Codable, Equatable, Sendable {
    @RunPlanV2Bool var ran: Bool? = nil
    @RunPlanV2List var new_proposals: [RunPlanV2Proposal] = []
    @RunPlanV2List var pending_proposals: [RunPlanV2Proposal] = []
    var ai: RunPlanV2AI?
}

// MARK: - Coach tools (§5)

struct RunPlanV2Paces: Codable, Equatable, Hashable, Sendable {
    var easy_s: [Int]?
    var long_s: [Int]?
    @RunPlanV2Int var marathon_s: Int? = nil
    @RunPlanV2Int var threshold_s: Int? = nil
    @RunPlanV2Int var interval_s: Int? = nil
    @RunPlanV2Int var rep_s: Int? = nil
    @RunPlanV2Number var vdot: Double? = nil
    var source: String?
}

struct RunPlanV2HRGuide: Codable, Equatable, Hashable, Sendable {
    @RunPlanV2Int var easy_ceiling: Int? = nil
    @RunPlanV2List var zones: [RunPlanV2Zone] = []
}

struct RunPlanV2Limits: Codable, Equatable, Hashable, Sendable {
    var spike_limit_mi_by_date: [String: Double]?
    @RunPlanV2Number var longest_run_30d_mi: Double? = nil
    @RunPlanV2Number var week_cap_mi: Double? = nil
    @RunPlanV2Int var hard_sessions_per_week: Int? = nil
}

struct RunPlanV2Signals: Codable, Equatable, Hashable, Sendable {
    @RunPlanV2Int var days_since_last_run: Int? = nil
    @RunPlanV2List var missed_key_sessions: [String] = []
    @RunPlanV2Bool var fatigue_flag: Bool? = nil
    @RunPlanV2Int var resting_hr_delta: Int? = nil
    @RunPlanV2Bool var hrv_below_baseline: Bool? = nil
    @RunPlanV2Number var acwr: Double? = nil
    @RunPlanV2Int var hard_efforts_last_6d: Int? = nil
    @RunPlanV2Int var low_energy_streak: Int? = nil
    @RunPlanV2Bool var walk_day_earned: Bool? = nil
    @RunPlanV2Bool var overdoing_it: Bool? = nil
}

struct RunPlanV2RecentDecision: Codable, Equatable, Hashable, Sendable {
    var proposal_id: String?
    var kind: String?
    var status: String?
    var decided_at: String?
}

struct RunPlanV2CoachContext: Codable, Equatable, Sendable {
    var today: String?
    var plan: RunPlanV2Plan?
    var fitness_profile: RunPlanV2FitnessProfile?
    var paces: RunPlanV2Paces?
    var hr: RunPlanV2HRGuide?
    var limits: RunPlanV2Limits?
    @RunPlanV2List var past: [RunPlanV2Day] = []
    @RunPlanV2List var ahead: [RunPlanV2Day] = []
    @RunPlanV2List var checkins: [RunPlanV2Checkin] = []
    @RunPlanV2List var pending_proposals: [RunPlanV2Proposal] = []
    @RunPlanV2List var recent_decisions: [RunPlanV2RecentDecision] = []
    var signals: RunPlanV2Signals?
    /// The research rules as compact text.
    var rules: String?
    @RunPlanV2List var formula_proposals: [RunPlanV2Proposal] = []
}

enum RunPlanV2OptionIntent: String, Codable, CaseIterable, Sendable {
    case easier, shorter, longer, harder
    case swapWalk = "swap_walk"
    case moveKey = "move_key"
    case fitTime = "fit_time"
}

struct RunPlanV2OptionsRequest: Codable, Equatable, Sendable {
    var today: String
    var local_date: String
    var intent: String
    /// fit_time only.
    var minutes: Int?
    /// move_key only.
    var to_date: String?
}

struct RunPlanV2Option: Codable, Equatable, Hashable, Sendable {
    var label: String?
    @RunPlanV2List var changes: [RunPlanV2DayChange] = []
    var checks: RunPlanV2Checks?
}

struct RunPlanV2OptionsResult: Codable, Equatable, Sendable {
    @RunPlanV2List var options: [RunPlanV2Option] = []
}

struct RunPlanV2BuildDayResult: Codable, Equatable, Sendable {
    var day: RunPlanV2Day?
    @RunPlanV2List var violations: [RunPlanV2Violation] = []
    @RunPlanV2List var deviations: [RunPlanV2Deviation] = []
}

struct RunPlanV2ValidateResult: Codable, Equatable, Sendable {
    @RunPlanV2Bool var ok: Bool? = nil
    @RunPlanV2List var violations: [RunPlanV2Violation] = []
    @RunPlanV2List var deviations: [RunPlanV2Deviation] = []
    var checks: RunPlanV2Checks?
    @RunPlanV2List var days: [RunPlanV2Day] = []
}

struct RunPlanV2Estimate: Codable, Equatable, Sendable {
    @RunPlanV2Number var distance_mi: Double? = nil
    @RunPlanV2Int var estimate_s: Int? = nil
    var method: String?
}

struct RunPlanV2NoteItem: Codable, Equatable, Hashable, Sendable {
    var local_date: String
    var note: String
}

struct RunPlanV2SummaryItem: Codable, Equatable, Hashable, Sendable {
    var local_date: String
    var summary: String
}

struct RunPlanV2NotesRequest: Codable, Equatable, Sendable {
    var today: String
    var source: String
    var notes: [RunPlanV2NoteItem] = []
    var grade_summaries: [RunPlanV2SummaryItem] = []
}

struct RunPlanV2ToolCallLog: Codable, Equatable, Hashable, Sendable {
    var name: String
    var ok: Bool
}

/// One Apple model call, uploaded to `POST /coach/calls` for the overseer.
struct RunPlanV2AICallLog: Codable, Equatable, Sendable, Identifiable {
    var client_call_id: String
    var provider: String
    var kind: String
    var trigger: String
    /// e.g. apple-pcc / apple-on-device
    var model: String
    var started_at: String
    var latency_ms: Int
    var input: String
    var output: String
    var tool_calls: [RunPlanV2ToolCallLog] = []
    var tokens_in: Int?
    var tokens_out: Int?
    var error: String?
    var daily_limit_hit: Bool
    var proposal_ids: [String] = []

    var id: String { client_call_id }

    enum CodingKeys: String, CodingKey {
        case client_call_id, provider, kind, trigger, model, started_at, latency_ms, input, output,
             tool_calls, tokens_in, tokens_out, error, daily_limit_hit, proposal_ids
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(client_call_id, forKey: .client_call_id)
        try c.encode(provider, forKey: .provider)
        try c.encode(kind, forKey: .kind)
        try c.encode(trigger, forKey: .trigger)
        try c.encode(model, forKey: .model)
        try c.encode(started_at, forKey: .started_at)
        try c.encode(latency_ms, forKey: .latency_ms)
        try c.encode(input, forKey: .input)
        try c.encode(output, forKey: .output)
        try c.encode(tool_calls, forKey: .tool_calls)
        try c.encode(tokens_in, forKey: .tokens_in)
        try c.encode(tokens_out, forKey: .tokens_out)
        try c.encode(error, forKey: .error)
        try c.encode(daily_limit_hit, forKey: .daily_limit_hit)
        try c.encode(proposal_ids, forKey: .proposal_ids)
    }
}

struct RunPlanV2CallsAccepted: Codable, Equatable, Sendable {
    @RunPlanV2Int var accepted: Int? = nil
    @RunPlanV2List var ids: [String] = []
}

// MARK: - Anthropic (§9)

struct RunPlanV2AnthropicRequest: Codable, Equatable, Sendable {
    var today: String
    /// chat | checkin | adjust | plan_build | weekly_review | post_run
    var kind: String
    var message: String?
    var checkin_id: String?
}

struct RunPlanV2AnthropicReply: Codable, Equatable, Sendable {
    var reply: String?
    @RunPlanV2List var proposals: [RunPlanV2Proposal] = []
    @RunPlanV2Int var notes_updated: Int? = nil
    var call_id: String?
}

// MARK: - Errors (§10)

/// Every `/run-plans/*` failure, mapped from the server's `{"error": code}`.
enum RunPlanV2Error: Error, Equatable {
    case plusRequired
    case noPlan
    case planExists
    case aiOff
    case aiModeMismatch
    case consentRequired
    /// 503 `ai_unavailable` (+ reason): show the formula plan.
    case aiUnavailable(reason: String?)
    case hardRuleViolation([RunPlanV2Violation])
    case deviationReasonRequired([RunPlanV2Deviation])
    case staleProposal
    case proposalNotPending(status: String?)
    case undoExpired
    case undoConflict
    case notFound(String)
    /// Any other 4xx code (e.g. `invalid_goals`, `past_date`).
    case invalid(String)
    case offline

    /// User-facing sentence. Never shows a raw code.
    var message: String {
        switch self {
        case .plusRequired: return String(localized: "Run plans are part of Mile A Day+.")
        case .noPlan: return String(localized: "You don't have a run plan yet.")
        case .planExists: return String(localized: "You already have a plan running.")
        case .aiOff, .aiModeMismatch, .aiUnavailable:
            return String(localized: "The AI Coach isn't available right now, so your plan follows the formula.")
        case .consentRequired: return String(localized: "Allow the AI Coach first.")
        case .hardRuleViolation:
            return String(localized: "That change would break a safety rule, so it wasn't made.")
        case .deviationReasonRequired:
            return String(localized: "That change needs a reason before it can go in.")
        case .staleProposal: return String(localized: "Your plan changed since this was suggested.")
        case .proposalNotPending: return String(localized: "That change was already handled.")
        case .undoExpired: return String(localized: "Undo is only possible for 24 hours.")
        case .undoConflict: return String(localized: "A later change touched the same day, so this can't be undone.")
        case .notFound: return String(localized: "That's no longer there.")
        case .invalid(let code): return RunPlanV2Error.friendly(code)
        case .offline: return String(localized: "Couldn't reach your plan right now. Try again in a moment.")
        }
    }

    private static func friendly(_ code: String) -> String {
        switch code {
        case "invalid_goals": return String(localized: "Those goals didn't work. Check the distances and times.")
        case "invalid_target_date":
            return String(localized: "Pick a date at least two weeks after the start and within a year.")
        case "fixed_walk_days_mismatch":
            return String(localized: "Pick one walk day for every day you don't run.")
        case "invalid_shoe": return String(localized: "One of those shoes is retired. Pick another.")
        case "past_date": return String(localized: "That day has already passed.")
        case "not_for_today": return String(localized: "This change isn't for today.")
        case "invalid_today": return String(localized: "Your phone's date looks off. Check Settings.")
        default: return String(localized: "Couldn't update your plan right now. Try again in a moment.")
        }
    }
}
