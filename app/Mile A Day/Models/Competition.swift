import Foundation
import SwiftUI

// MARK: - Competition Models

/// Represents a competition from the backend API
struct Competition: Codable, Identifiable {
    let competition_id: String
    let competition_name: String
    let start_date: String?
    let end_date: String?
    let workouts: [CompetitionActivity]
    let type: CompetitionType
    let options: CompetitionOptions
    let owner: String?
    let winner: String?
    let users: [CompetitionUser]

    var id: String { competition_id }

    enum CodingKeys: String, CodingKey {
        case competition_id = "id"
        case competition_name
        case start_date
        case end_date
        case workouts
        case type
        case options
        case owner
        case winner
        case users
    }

    init(competition_id: String, competition_name: String, start_date: String?, end_date: String?, workouts: [CompetitionActivity], type: CompetitionType, options: CompetitionOptions, owner: String? = nil, winner: String? = nil, users: [CompetitionUser]) {
        self.competition_id = competition_id
        self.competition_name = competition_name
        self.start_date = start_date
        self.end_date = end_date
        self.workouts = workouts
        self.type = type
        self.options = options
        self.owner = owner
        self.winner = winner
        self.users = users
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        competition_id = try container.decode(String.self, forKey: .competition_id)
        competition_name = try container.decode(String.self, forKey: .competition_name)
        start_date = try container.decodeIfPresent(String.self, forKey: .start_date)
        end_date = try container.decodeIfPresent(String.self, forKey: .end_date)
        workouts = try container.decodeIfPresent([CompetitionActivity].self, forKey: .workouts) ?? []
        type = try container.decode(CompetitionType.self, forKey: .type)
        options = try container.decodeIfPresent(CompetitionOptions.self, forKey: .options) ?? CompetitionOptions.defaults
        owner = try container.decodeIfPresent(String.self, forKey: .owner)
        winner = try container.decodeIfPresent(String.self, forKey: .winner)
        users = try container.decodeIfPresent([CompetitionUser].self, forKey: .users) ?? []
    }

    // Computed properties
    var isOwner: Bool {
        guard let currentUserId = UserDefaults.standard.string(forKey: "backendUserId") else {
            return false
        }
        return owner == currentUserId
    }

    /// Whether the current user won this competition (1st place)
    var isWinner: Bool {
        guard status == .finished,
              let currentUserId = UserDefaults.standard.string(forKey: "backendUserId") else {
            return false
        }
        // Use authoritative winner field from backend if available
        if let winnerId = winner {
            return winnerId == currentUserId
        }
        // Fallback: compute from scores
        let ranked = users
            .filter { $0.invite_status == .accepted }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        return ranked.first?.user_id == currentUserId
    }

    var currentUserInviteStatus: InviteStatus? {
        guard let currentUserId = UserDefaults.standard.string(forKey: "backendUserId") else {
            return nil
        }
        return users.first(where: { $0.user_id == currentUserId })?.invite_status
    }

    var acceptedUsersCount: Int {
        users.filter { $0.invite_status == .accepted }.count
    }

    /// Parses a "YYYY-MM-DD" string from the backend as midnight in Eastern Time.
    /// The backend treats start_date / end_date as ET calendar dates, so a competition
    /// dated "2026-04-27" begins at 2026-04-27 00:00 America/New_York — not midnight UTC.
    private static let etDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Eastern-Time Gregorian calendar — the timezone the backend buckets workout
    /// dates and competition start/end dates in.
    private static let etCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    /// The weekly interval key ("YYYY-MM-DD" for the day that begins the 7-day window
    /// containing `date`). Weekly windows are anchored to the competition's start_date —
    /// week 1 is start..start+6, week 2 is start+7..start+13, etc. — so this MUST match
    /// getCurrentInterval(..., 'week', start_date) in the backend's competitionService.ts.
    /// Falls back to the calendar-week start when start_date is unknown (lobby state).
    func weeklyIntervalKey(for date: Date) -> String {
        let cal = Self.etCalendar
        guard let startDate = startDateFormatted else {
            var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            comps.weekday = cal.firstWeekday
            let startOfWeek = cal.date(from: comps) ?? date
            return Self.etDateFormatter.string(from: startOfWeek)
        }
        let startDay = cal.startOfDay(for: startDate)
        let curDay = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: startDay, to: curDay).day ?? 0
        let weekIndex = Int(floor(Double(days) / 7.0))
        let windowStart = cal.date(byAdding: .day, value: weekIndex * 7, to: startDay) ?? startDay
        return Self.etDateFormatter.string(from: windowStart)
    }

    /// The [start, end] day boundaries (inclusive, ET) of the interval window that
    /// contains `date`, honoring the competition's cadence. Weekly windows are
    /// anchored to start_date (so a week can run e.g. Wed→Tue), matching
    /// `weeklyIntervalKey(for:)` and the backend. Both dates are midnight-ET.
    func intervalWindow(for date: Date) -> (start: Date, end: Date) {
        let cal = Self.etCalendar
        switch options.interval ?? .day {
        case .day:
            let start = cal.startOfDay(for: date)
            return (start, start)
        case .week:
            let windowStart: Date
            if let startDate = startDateFormatted {
                let startDay = cal.startOfDay(for: startDate)
                let curDay = cal.startOfDay(for: date)
                let days = cal.dateComponents([.day], from: startDay, to: curDay).day ?? 0
                let weekIndex = Int(floor(Double(days) / 7.0))
                windowStart = cal.date(byAdding: .day, value: weekIndex * 7, to: startDay) ?? startDay
            } else {
                var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                comps.weekday = cal.firstWeekday
                windowStart = cal.date(from: comps) ?? cal.startOfDay(for: date)
            }
            let end = cal.date(byAdding: .day, value: 6, to: windowStart) ?? windowStart
            return (windowStart, end)
        case .month:
            var comps = cal.dateComponents([.year, .month], from: date)
            comps.day = 1
            let start = cal.date(from: comps) ?? cal.startOfDay(for: date)
            let nextMonth = cal.date(byAdding: .month, value: 1, to: start) ?? start
            let end = cal.date(byAdding: .day, value: -1, to: nextMonth) ?? start
            return (start, end)
        }
    }

    /// The instant the interval containing `date` expires — the end of its last ET
    /// day. Clamped to the competition's own end date so the final interval never
    /// counts down past the competition itself.
    func intervalExpiry(for date: Date) -> Date {
        let cal = Self.etCalendar
        let window = intervalWindow(for: date)
        let expiry = cal.date(byAdding: .day, value: 1, to: window.end) ?? window.end
        if let endDate = endDateFormatted,
           let compExpiry = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: endDate)),
           compExpiry < expiry {
            return compExpiry
        }
        return expiry
    }

    /// True when the interval window containing `date` also contains right now —
    /// i.e. `date` falls in the live interval.
    func isCurrentInterval(_ date: Date) -> Bool {
        let cal = Self.etCalendar
        let window = intervalWindow(for: date)
        let now = cal.startOfDay(for: Date())
        return now >= window.start && now <= window.end
    }

    var startDateFormatted: Date? {
        guard let dateStr = start_date else { return nil }
        return Self.etDateFormatter.date(from: dateStr)
    }

    var endDateFormatted: Date? {
        guard let dateStr = end_date else { return nil }
        return Self.etDateFormatter.date(from: dateStr)
    }

    /// Computed competition status based on dates
    var status: CompetitionStatus {
        guard let startStr = start_date else {
            return .lobby
        }

        let now = Date()

        guard let startDate = Self.etDateFormatter.date(from: startStr) else {
            return .lobby
        }

        if startDate > now {
            return .scheduled
        }

        // Start date is in the past — competition is finished only after the end_date day
        // has fully elapsed in ET (matches backend `c.end_date < TODAY_ET` behavior).
        if let endStr = end_date, let endDate = Self.etDateFormatter.date(from: endStr) {
            var et = Calendar(identifier: .gregorian)
            et.timeZone = TimeZone(identifier: "America/New_York")!
            if let endOfEndDay = et.date(byAdding: .day, value: 1, to: endDate), endOfEndDay <= now {
                return .finished
            }
        }

        return .active
    }

    /// Total lives for a streak competition. Reads from options.lives (preferred)
    /// and falls back to options.first_to for legacy records created before the
    /// dedicated `lives` field existed.
    var streakLives: Int {
        options.lives ?? (options.first_to > 0 ? options.first_to : 0)
    }

    /// When the viewer is close to overtaking the next person above them in
    /// the standings, returns a hint describing the gap. Returns nil when
    /// the viewer isn't in striking distance, is already leading, or the
    /// competition type isn't comparison-based (streaks — independent
    /// streaks per user — never returns a hint).
    ///
    /// Special case for **clash**: prefer today's daily miles gap (more
    /// actionable — "go a little farther and you win today's point") over
    /// the cumulative wins-based gap. Wins-based hint only kicks in when
    /// the daily race isn't close.
    var rivalryHint: RivalryHint? {
        // Streaks: each user's streak is independent — "passing" doesn't apply.
        guard type != .streaks else { return nil }
        // Only useful while the comp is live.
        guard status == .active else { return nil }
        guard let currentUserId = UserDefaults.standard.string(forKey: "backendUserId") else { return nil }

        // For clash, the daily miles race is the more actionable signal.
        // Try that first; fall through to the overall score gap if not close.
        if type == .clash, let dailyHint = clashDailyRivalryHint(currentUserId: currentUserId) {
            return dailyHint
        }

        let ranked = users
            .filter { $0.invite_status == .accepted }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        guard ranked.count >= 2 else { return nil }
        guard let myIndex = ranked.firstIndex(where: { $0.user_id == currentUserId }) else { return nil }
        guard myIndex > 0 else { return nil } // already leading

        let me = ranked[myIndex]
        let target = ranked[myIndex - 1]
        let myScore = me.score ?? 0
        let targetScore = target.score ?? 0
        let gap = targetScore - myScore
        guard gap > 0 else { return nil }

        // Format gap based on comp type. Clash/targets are points-based;
        // apex/race are miles-based.
        let isPoints = type == .clash || type == .targets
        let threshold: Double = isPoints ? 1.001 : 0.5
        guard gap <= threshold else { return nil }

        let gapText: String
        if isPoints {
            let pts = Int(gap.rounded())
            gapText = pts == 1 ? "1 \(type == .targets ? "point" : "win")" : "\(pts) \(type == .targets ? "points" : "wins")"
        } else {
            gapText = String(format: "%.2f \(options.unit.shortDisplayName)", gap)
        }

        return RivalryHint(
            targetUserId: target.user_id,
            targetDisplayName: target.displayName,
            targetProfileImageURL: target.profile_image_url,
            gap: gap,
            gapText: gapText,
            competitionName: competition_name,
            kind: isPoints ? .wins : .miles
        )
    }

    /// Clash-specific: compute today's interval winner and report the gap
    /// if the viewer is within 0.5 mi of the daily leader. Returns nil for
    /// non-clash comps or when the viewer is already leading today / not
    /// close enough to act on.
    private func clashDailyRivalryHint(currentUserId: String) -> RivalryHint? {
        guard type == .clash else { return nil }

        // Build today's interval key matching the per-comp interval setting.
        // Default to .day if interval is missing.
        let interval = options.interval ?? .day
        let calendar = Calendar.current
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let key: String
        switch interval {
        case .day:
            key = formatter.string(from: calendar.startOfDay(for: now))
        case .week:
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            components.weekday = calendar.firstWeekday
            let start = calendar.date(from: components) ?? now
            key = formatter.string(from: start)
        case .month:
            var components = calendar.dateComponents([.year, .month], from: now)
            components.day = 1
            let start = calendar.date(from: components) ?? now
            key = formatter.string(from: start)
        }

        let accepted = users.filter { $0.invite_status == .accepted }
        guard accepted.count >= 2 else { return nil }
        guard let me = accepted.first(where: { $0.user_id == currentUserId }) else { return nil }

        let myMiles = me.intervals?[key] ?? 0
        // Find the highest-miles person today (excluding me).
        guard let leader = accepted
            .filter({ $0.user_id != currentUserId })
            .max(by: { ($0.intervals?[key] ?? 0) < ($1.intervals?[key] ?? 0) })
        else { return nil }

        let leaderMiles = leader.intervals?[key] ?? 0
        let gap = leaderMiles - myMiles
        // If I'm already winning today, no rivalry hint needed.
        guard gap > 0 else { return nil }
        // Within striking distance — same threshold as cumulative miles hints.
        guard gap <= 0.5 else { return nil }

        return RivalryHint(
            targetUserId: leader.user_id,
            targetDisplayName: leader.displayName,
            targetProfileImageURL: leader.profile_image_url,
            gap: gap,
            gapText: String(format: "%.2f \(options.unit.shortDisplayName)", gap),
            competitionName: competition_name,
            kind: .clashToday
        )
    }
}

/// Lightweight "you're X behind Y" signal surfaced on comp previews and
/// optionally aggregated on the dashboard. Built by `Competition.rivalryHint`.
struct RivalryHint: Identifiable, Equatable {
    let targetUserId: String
    let targetDisplayName: String
    let targetProfileImageURL: String?
    let gap: Double
    let gapText: String
    let competitionName: String
    /// Distinguishes the rivalry context so the UI can phrase the hint
    /// appropriately. `clashToday` is the "win today's point" framing;
    /// `miles` / `wins` are cumulative passing.
    let kind: Kind

    enum Kind: Equatable {
        case miles       // cumulative miles (apex, race)
        case wins        // cumulative wins/points (clash, targets)
        case clashToday  // today's daily clash race
    }

    var id: String { targetUserId }

    /// Suffix copy paired with `gapText` in the UI. Lets the same component
    /// render "0.20 mi from passing Sarah" vs "0.20 mi from today's win".
    var actionSuffix: String {
        switch kind {
        case .miles, .wins: return "from passing \(targetDisplayName)"
        case .clashToday: return "from winning today's clash vs \(targetDisplayName)"
        }
    }
}

/// Competition lifecycle status - derived from dates
enum CompetitionStatus: String {
    case lobby       // start_date is nil - waiting for owner to start
    case scheduled   // start_date is in the future
    case active      // start_date is in the past, end_date is nil or in the future
    case finished    // end_date is in the past

    var displayName: String {
        switch self {
        case .lobby: return "Lobby"
        case .scheduled: return "Scheduled"
        case .active: return "Active"
        case .finished: return "Finished"
        }
    }

    var icon: String {
        switch self {
        case .lobby: return "hourglass"
        case .scheduled: return "calendar.badge.clock"
        case .active: return "bolt.fill"
        case .finished: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .lobby: return .orange
        case .scheduled: return .blue
        case .active: return .green
        case .finished: return .gray
        }
    }
}

/// Competition type enum
enum CompetitionType: String, Codable, CaseIterable {
    case streaks = "streaks"
    case apex = "apex"
    case targets = "targets"
    case clash = "clash"
    case race = "race"

    var displayName: String {
        switch self {
        case .streaks: return "Streaks"
        case .apex: return "Apex"
        case .targets: return "Targets"
        case .clash: return "Clash"
        case .race: return "Race"
        }
    }

    var description: String {
        switch self {
        case .streaks:
            return "Hold a running streak as long as you can. First to break the streak loses"
        case .apex:
            return "Over a period of time (ex: 1 week) whoever has the most distance during that time wins"
        case .targets:
            return "Anyone who completes the goal in a given day gets a point. Whoever has the most points at the end of the period wins"
        case .clash:
            return "Whoever goes the furthest each day wins a point. First to reach the target score or most points at the end wins"
        case .race:
            return "There is a distance goal set and whoever gets there first wins"
        }
    }

    var icon: String {
        switch self {
        case .streaks: return "flame.fill"
        case .apex: return "arrow.up.circle.fill"
        case .targets: return "target"
        case .clash: return "bolt.fill"
        case .race: return "flag.fill"
        }
    }

    var gradient: [String] {
        switch self {
        case .streaks: return ["FF6B6B", "FF8E53"]
        case .apex: return ["4ECDC4", "44A08D"]
        case .targets: return ["F7971E", "FFD200"]
        case .clash: return ["C33764", "1D2671"]
        case .race: return ["667EEA", "764BA2"]
        }
    }
}

/// Competition activity type
enum CompetitionActivity: String, Codable, CaseIterable {
    case run = "run"
    case walk = "walk"

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        }
    }

    /// Key the backend uses for this type inside `daily_activity` payloads.
    var dailyActivityKey: String {
        switch self {
        case .run: return "running"
        case .walk: return "walking"
        }
    }

    var color: Color {
        switch self {
        case .run: return MADTheme.Colors.madRed
        case .walk: return .blue
        }
    }

    var backgroundColor: Color {
        switch self {
        case .run: return MADTheme.Colors.madRed.opacity(0.12)
        case .walk: return Color.blue.opacity(0.12)
        }
    }
}

/// Competition options
struct CompetitionOptions: Codable {
    let goal: Double
    let unit: CompetitionUnit
    let first_to: Int
    let lives: Int?
    let history: Bool?
    let interval: CompetitionInterval?
    let duration_hours: Int?

    /// Default values for when the server returns null options
    static let defaults = CompetitionOptions(
        goal: 0, unit: .miles, first_to: 0, lives: nil,
        history: nil, interval: nil, duration_hours: nil
    )

    init(goal: Double, unit: CompetitionUnit, first_to: Int, lives: Int?, history: Bool?, interval: CompetitionInterval?, duration_hours: Int?) {
        self.goal = goal
        self.unit = unit
        self.first_to = first_to
        self.lives = lives
        self.history = history
        self.interval = interval
        self.duration_hours = duration_hours
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goal = try container.decodeIfPresent(Double.self, forKey: .goal) ?? 0
        unit = try container.decodeIfPresent(CompetitionUnit.self, forKey: .unit) ?? .miles
        first_to = try container.decodeIfPresent(Int.self, forKey: .first_to) ?? 0
        lives = try container.decodeIfPresent(Int.self, forKey: .lives)
        history = try container.decodeIfPresent(Bool.self, forKey: .history)
        interval = try container.decodeIfPresent(CompetitionInterval.self, forKey: .interval)
        duration_hours = try container.decodeIfPresent(Int.self, forKey: .duration_hours)
    }

    var goalFormatted: String {
        if unit == .miles {
            return String(format: "%.1f", goal)
        } else {
            return String(format: "%.0f", goal)
        }
    }

    /// Format a quantity (distance OR steps) using this competition's unit.
    /// Steps render as integer with thousands separators; distance units render with one decimal.
    func formatQuantity(_ value: Double) -> String {
        if unit == .steps {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    /// "<value> <unit>" — e.g. "3.2 mi" or "42,317 steps".
    func formatQuantityWithUnit(_ value: Double) -> String {
        return "\(formatQuantity(value)) \(unit.shortDisplayName)"
    }

    var durationFormatted: String? {
        guard let hours = duration_hours else { return nil }
        if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        let days = hours / 24
        if days == 7 { return "1 week" }
        if days == 14 { return "2 weeks" }
        if days == 30 { return "1 month" }
        return "\(days) day\(days == 1 ? "" : "s")"
    }
}

/// Competition unit
enum CompetitionUnit: String, Codable, CaseIterable {
    case miles = "miles"
    case kilometers = "kilometers"
    case steps = "steps"

    var displayName: String {
        rawValue.capitalized
    }

    var shortDisplayName: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        case .steps: return "steps"
        }
    }

    var icon: String {
        switch self {
        case .miles: return "figure.run"
        case .kilometers: return "figure.run"
        case .steps: return "figure.walk"
        }
    }
}

/// Competition interval
enum CompetitionInterval: String, Codable, CaseIterable {
    case day = "day"
    case week = "week"
    case month = "month"

    var displayName: String {
        rawValue.capitalized
    }
}

/// One activity type's slice of a user's day — distance + workout count for
/// "running" or "walking" on a single local date. Both fields optional so
/// partial backend payloads decode safely.
struct DailyActivityEntry: Codable, Equatable {
    let distance: Double?
    let count: Int?
}

/// Competition user with enriched data from backend
struct CompetitionUser: Codable, Identifiable {
    let competition_id: String
    let user_id: String
    let invite_status: InviteStatus
    let username: String?
    let profile_image_url: String?
    let score: Double?
    let intervals: [String: Double]?
    let remaining_lives: Int?
    let has_manual_workouts: Bool?
    /// Per-day activity-type breakdown, keyed by "YYYY-MM-DD" local date then
    /// by activity type ("running"/"walking"). Already filtered server-side to
    /// the comp's allowed types. Nil on older backends / pre-start / steps
    /// comps — everything reading it must degrade gracefully.
    let daily_activity: [String: [String: DailyActivityEntry]]?

    var id: String { "\(competition_id)-\(user_id)" }

    var hasProfileImage: Bool {
        profile_image_url != nil && !profile_image_url!.isEmpty
    }

    var displayName: String {
        if let uname = username, !uname.isEmpty {
            return uname
        }
        return "Unknown"
    }

    /// Summed distance across all intervals — the player's total for the comp.
    var totalIntervalDistance: Double {
        intervals?.values.reduce(0, +) ?? 0
    }

    /// True when the backend sent the per-activity daily breakdown.
    var hasDailyActivity: Bool {
        !(daily_activity?.isEmpty ?? true)
    }

    /// This user's distance/count split for one activity type on one
    /// "YYYY-MM-DD" local day. Nil when the day or type has no data.
    func dailyActivityEntry(for activity: CompetitionActivity, onDay dayKey: String) -> DailyActivityEntry? {
        daily_activity?[dayKey]?[activity.dailyActivityKey]
    }

    /// Total workout count for one activity type across the whole competition.
    func totalActivityCount(for activity: CompetitionActivity) -> Int {
        guard let daily = daily_activity else { return 0 }
        return daily.values.reduce(0) { $0 + ($1[activity.dailyActivityKey]?.count ?? 0) }
    }

    init(competition_id: String, user_id: String, invite_status: InviteStatus, username: String?, profile_image_url: String? = nil, score: Double?, intervals: [String: Double]?, remaining_lives: Int? = nil, has_manual_workouts: Bool? = nil, daily_activity: [String: [String: DailyActivityEntry]]? = nil) {
        self.competition_id = competition_id
        self.user_id = user_id
        self.invite_status = invite_status
        self.username = username
        self.profile_image_url = profile_image_url
        self.score = score
        self.intervals = intervals
        self.remaining_lives = remaining_lives
        self.has_manual_workouts = has_manual_workouts
        self.daily_activity = daily_activity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        competition_id = try container.decodeIfPresent(String.self, forKey: .competition_id) ?? ""
        user_id = try container.decode(String.self, forKey: .user_id)
        invite_status = try container.decodeIfPresent(InviteStatus.self, forKey: .invite_status) ?? .pending
        username = try container.decodeIfPresent(String.self, forKey: .username)
        profile_image_url = try container.decodeIfPresent(String.self, forKey: .profile_image_url)
        score = try container.decodeIfPresent(Double.self, forKey: .score)
        intervals = try container.decodeIfPresent([String: Double].self, forKey: .intervals)
        remaining_lives = try container.decodeIfPresent(Int.self, forKey: .remaining_lives)
        has_manual_workouts = try container.decodeIfPresent(Bool.self, forKey: .has_manual_workouts)
        daily_activity = try container.decodeIfPresent([String: [String: DailyActivityEntry]].self, forKey: .daily_activity)
    }
}

/// Invite status
enum InviteStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case accepted = "accepted"
    case declined = "declined"

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - API Request Models

/// Request to create a competition
struct CreateCompetitionRequest: Codable {
    let competition_name: String
    let type: CompetitionType
    let start_date: String?
    let end_date: String?
    let workouts: [CompetitionActivity]
    let options: CompetitionOptionsRequest
}

struct CompetitionOptionsRequest: Codable {
    let goal: Double
    let unit: CompetitionUnit
    let first_to: Int
    let lives: Int?
    let history: Bool
    let interval: CompetitionInterval
    let duration_hours: Int?
}

/// Request to update a competition
struct UpdateCompetitionRequest: Codable {
    let competition_name: String?
    let type: CompetitionType?
    let start_date: String?
    let end_date: String?
    let workouts: [CompetitionActivity]?
    let options: PartialCompetitionOptionsRequest?
}

struct PartialCompetitionOptionsRequest: Codable {
    let goal: Double?
    let unit: CompetitionUnit?
    let first_to: Int?
    let lives: Int?
    let history: Bool?
    let interval: CompetitionInterval?
}

/// Request to invite a user
struct InviteUserRequest: Codable {
    let inviteUser: String
}

// MARK: - API Response Models

struct CreateCompetitionResponse: Codable {
    let competition_id: String
}

struct CompetitionResponse: Codable {
    let competition: Competition
}

struct CompetitionsListResponse: Codable {
    let competitions: [Competition]
}

struct CompetitionInvitesResponse: Codable {
    let competitionInvites: [Competition]
}

struct InviteUserResponse: Codable {
    let message: String
}

struct DeleteCompetitionResponse: Codable {
    let message: String
}

struct FlexRequest: Codable {
    let target_user_id: String
    let message: String?
}

struct FlexResponse: Codable {
    let message: String
}

struct FlexPresetsResponse: Codable {
    let presets: [String]
}

struct NudgeRequest: Codable {
    let targetUserId: String
}

struct NudgeResponse: Codable {
    let message: String
}

struct FriendNudgeResponse: Codable {
    let message: String
}

struct NudgeStatusResponse: Codable, Equatable {
    let can_nudge: Bool
    let has_completed_mile: Bool
    /// Legacy: derived from can_nudge server-side, so unlimited (admin)
    /// nudgers read false here even after nudging. Prefer `nudgedToday`.
    let already_nudged_today: Bool
    let today_miles: Double?
    /// Friend's current streak (in days). Optional for backward compatibility
    /// with pre-leaderboard backend deploys.
    let current_streak: Int?
    /// Log truth: the sender HAS nudged this friend today — set even for
    /// unlimited nudgers, who may still nudge again. Absent on old backends.
    var has_nudged_today: Bool? = nil
    /// The sender's role bypasses the once-per-friend-per-day nudge limit.
    var unlimited_nudges: Bool? = nil

    /// Display truth for "already nudged today" across backend versions.
    var nudgedToday: Bool { has_nudged_today ?? already_nudged_today }
    var unlimitedNudges: Bool { unlimited_nudges ?? false }
}

struct NudgeStatusBatchResponse: Codable {
    let statuses: [String: NudgeStatusResponse]
}

// MARK: - Notification Settings Models

struct NotificationSettingsResponse: Codable {
    let nudges_enabled: Bool
    let flexes_enabled: Bool
    let friend_activity_enabled: Bool
    let competition_invites_enabled: Bool
    let competition_updates_enabled: Bool
    let competition_milestones_enabled: Bool
    let quiet_hours_start: Int?
    let quiet_hours_end: Int?
    // Optional: absent on older server builds.
    let h2h_close_friends_only: Bool?
}

struct FriendNotificationSetting: Codable, Identifiable {
    let friend_id: String
    let username: String?
    let muted: Bool
    let nudges_muted: Bool
    let activity_muted: Bool

    var id: String { friend_id }
}

struct FriendNotificationSettingsResponse: Codable {
    let settings: [FriendNotificationSetting]
}

// MARK: - In-App Notification Models

struct InAppNotification: Codable, Identifiable {
    let id: String
    let title: String
    let body: String
    let type: String
    let data: [String: String]?
    let is_read: Bool
    let created_at: String

    // Server-computed hype affordance fields. Null/absent when the row isn't hype-able
    // or when responding from an older backend that doesn't yet populate them.
    let hype_target_user_id: String?
    let hype_context_type: String?
    let hype_context_id: String?
    let hype_context_label: String?
    let is_hyped: Bool?
    /// Total hypes this event has received (all senders), computed with the
    /// SAME canonical context keys as the feed so both surfaces agree.
    /// Absent on older backends / non-hypeable rows.
    var hype_count: Int?
}

struct InAppNotificationResponse: Codable {
    let notifications: [InAppNotification]
    let unread_count: Int
}

struct UnreadCountResponse: Codable {
    let unread_count: Int
}

// MARK: - Trophy Models

struct CompetitionTrophy: Codable, Identifiable {
    let id: String
    let competitionName: String
    let competitionType: CompetitionType
    let placement: Int
    let score: Double
    let totalParticipants: Int
    let completedDate: String
    let unit: CompetitionUnit

    var medal: TrophyMedal? {
        switch placement {
        case 1: return .gold
        case 2: return .silver
        case 3: return .bronze
        default: return nil
        }
    }
}

enum TrophyMedal: String, Codable {
    case gold, silver, bronze

    var color: Color {
        switch self {
        case .gold: return .yellow
        case .silver: return Color(white: 0.75)
        case .bronze: return .brown
        }
    }

    var gradient: [Color] {
        switch self {
        case .gold: return [.yellow, .orange]
        case .silver: return [Color(white: 0.85), Color(white: 0.6)]
        case .bronze: return [.brown, Color(red: 0.7, green: 0.4, blue: 0.2)]
        }
    }

    var icon: String { "medal.fill" }

    var displayName: String {
        switch self {
        case .gold: return "1st Place"
        case .silver: return "2nd Place"
        case .bronze: return "3rd Place"
        }
    }
}
