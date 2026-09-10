import Foundation
import SwiftUI

// MARK: - Competition Models

/// A competition as it rides on a post's photo: the name, the poster's
/// standing, and the podium they're on.
///
/// Opt-in by construction — nothing puts this on a card. A competition is a
/// closed group with a user-typed name, and a post that announces one on the
/// poster's behalf tells their whole circle about a room they aren't in. The
/// poster adds it from the sticker tray or it isn't there.
struct CompetitionStickerData: Equatable, Hashable {
    struct Row: Equatable, Hashable, Identifiable {
        /// Filled in by `Competition.podium` — the row's place on the real
        /// leaderboard, which is not its index once the viewer is spliced in.
        var place: Int = 0
        let name: String
        let score: String
        let isMe: Bool
        /// True on the viewer's own row when it was lifted from outside the
        /// top three, so the sticker can draw the gap it jumped.
        var truncated: Bool = false
        /// The competitor's own face, on a competition scored on PEOPLE. Nil
        /// on a team row — a team has no one face, so its people ride
        /// `members` instead.
        var avatarURL: String? = nil
        /// Who is actually in this team and what each of them put IN. A team
        /// row's score is the team's, derived server-side from combined miles,
        /// so on its own it says nothing about who is in the competition or
        /// who carried it.
        var members: [Member] = []
        var id: String { "\(place)-\(name)" }
    }

    /// One person under a team row.
    struct Member: Equatable, Hashable, Identifiable {
        let name: String
        /// What they put INTO the team over the scored window — miles, not
        /// their own standing. `Competition.memberScoreLabel` is the one
        /// formatter, shared with the team leaderboard so the two can't
        /// disagree about the same person.
        let value: String
        let avatarURL: String?
        var id: String { "\(name)-\(value)" }
    }

    let competitionId: String
    let name: String
    /// "Team Red" on a team competition, nil otherwise.
    let subtitle: String?
    /// Nil before anyone has scored, which is a real state on day one.
    let place: Int?
    let fieldSize: Int
    let rows: [Row]

    /// "2nd of 6" — nil until there's a placing worth claiming (a field of one
    /// is not a standing).
    var standingText: String? {
        guard let place, fieldSize > 1 else { return nil }
        return "\(ActiveCompetitionRow.ordinal(place)) of \(fieldSize)"
    }

    /// Every name on the sticker is capped HERE, not by a `lineLimit`: the
    /// sticker renders `.fixedSize()`, so a line limit still publishes the
    /// full intrinsic width and one long user-typed competition name would
    /// make the overlay wider than the photo under it.
    static func capped(_ text: String, max: Int = 22) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        return String(trimmed.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The one-line form, for the Minimal sticker style and accessibility.
    var inlineText: String {
        var parts = [name]
        if let subtitle { parts.append(subtitle) }
        if let standingText { parts.append(standingText) }
        return parts.joined(separator: " · ")
    }
}

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
    /// Team play config — nil when this competition has no teams.
    let teams: CompetitionTeamsConfig?
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
        case teams
        case users
    }

    init(competition_id: String, competition_name: String, start_date: String?, end_date: String?, workouts: [CompetitionActivity], type: CompetitionType, options: CompetitionOptions, owner: String? = nil, winner: String? = nil, teams: CompetitionTeamsConfig? = nil, users: [CompetitionUser]) {
        self.competition_id = competition_id
        self.competition_name = competition_name
        self.start_date = start_date
        self.end_date = end_date
        self.workouts = workouts
        self.type = type
        self.options = options
        self.owner = owner
        self.winner = winner
        self.teams = teams
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
        teams = try container.decodeIfPresent(CompetitionTeamsConfig.self, forKey: .teams)
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

    // MARK: Post sticker

    /// Is `localDate` ("yyyy-MM-dd") inside this competition's window? Date
    /// strings compare lexically in that format, which is exactly how the
    /// server lists a post's competitions.
    func isRunning(on localDate: String) -> Bool {
        guard let start = start_date, !start.isEmpty, start <= localDate else { return false }
        if let end = end_date, !end.isEmpty { return end >= localDate }
        return true
    }

    /// The competition as it goes ON a photo: the name, this user's standing,
    /// and the handful of people they're racing. Nil when the user isn't an
    /// accepted member.
    ///
    /// One summary for both the sticker and the widget's mini-leaderboard —
    /// they were separate arithmetic that happened to agree, which is how a
    /// post ends up claiming a place the widget beside it doesn't.
    func stickerSummary(for userId: String) -> CompetitionStickerData? {
        // Membership gates the STICKER, not the arithmetic: a competition the
        // poster isn't in is not theirs to put on a photo.
        guard users.contains(where: {
            $0.invite_status == .accepted && $0.user_id == userId
        }) else { return nil }

        var name = CompetitionStickerData.capped(competition_name)
        if name.isEmpty { name = "Competition" }

        // A team competition is scored on TEAMS, so the standing and the rows
        // are both about teams — a member's rank among people is a fact about
        // a leaderboard this competition isn't scored on.
        let myTeam = hasTeams ? team(for: userId) : nil
        return CompetitionStickerData(
            competitionId: competition_id,
            name: name,
            // No subtitle on a team competition. It read "Team <name>" over a
            // podium whose own first line was that same team — the viewer is
            // always spliced onto the podium, so it could only ever repeat a
            // row, and it was carrying the doubled "Team Team 2" besides.
            subtitle: nil,
            place: place(for: userId),
            fieldSize: myTeam == nil ? acceptedRanked.count : rankedTeams.count,
            rows: standingsPodium(for: userId)
        )
    }

    /// The mini-leaderboard both the sticker and the widget draw: the top
    /// three, with this user always on it. Teams when the competition is
    /// scored on teams, people otherwise.
    ///
    /// Takes an OPTIONAL user and asks nothing of them — the widget renders
    /// for whoever's phone it is, and losing a whole leaderboard because a
    /// membership row read something unexpected is a silent way to break it.
    func standingsPodium(for userId: String?) -> [CompetitionStickerData.Row] {
        let myTeam = hasTeams ? userId.flatMap({ team(for: $0) }) : nil
        if hasTeams {
            return Self.podium(
                rankedTeams.map { team in
                    CompetitionStickerData.Row(
                        // The team's OWN name, never prefixed. Teams created
                        // in the lobby are literally named "Team 1"/"Team 2"
                        // (CompetitionLobbyTeams), so prefixing produced
                        // "Team Team 2"; a team someone named "Red" reads fine
                        // as "Red" in a leaderboard row.
                        name: CompetitionStickerData.capped(team.name),
                        score: scoreLabel(team.score ?? 0),
                        isMe: team.id == myTeam?.id,
                        members: stickerMembers(of: team.id)
                    )
                }
            )
        }
        return Self.podium(
            acceptedRanked.map {
                CompetitionStickerData.Row(
                    name: CompetitionStickerData.capped($0.displayName),
                    score: scoreLabel($0.score ?? 0),
                    isMe: $0.user_id == userId,
                    // People ARE the competitors here, so the face belongs on
                    // the row itself rather than in a member strip under it.
                    avatarURL: $0.profile_image_url
                )
            }
        )
    }

    /// The people under a team row, biggest contributor first.
    ///
    /// Capped at three: this is a sticker sitting on somebody's photo, and a
    /// roster of eight would be taller than the walk it is annotating. The cap
    /// is on the DATA rather than a `lineLimit` for the same reason `capped`
    /// is — the sticker renders `.fixedSize()`, so anything trimmed only at
    /// draw time still publishes its full intrinsic width.
    private func stickerMembers(of teamId: String) -> [CompetitionStickerData.Member] {
        members(of: teamId).prefix(3).map { user in
            CompetitionStickerData.Member(
                name: CompetitionStickerData.capped(user.displayName, max: 12),
                value: memberScoreLabel(user),
                avatarURL: user.profile_image_url
            )
        }
    }

    /// This user's place on whichever leaderboard the competition is scored
    /// on. Nil when they aren't on it yet.
    private func place(for userId: String) -> Int? {
        standing(for: userId)?.place
    }

    /// This user's place AND the size of the field they're placed in — their
    /// team's among teams when the competition has teams, their own among
    /// people otherwise.
    ///
    /// Every surface that prints "2nd of 6" reads this, because a surface that
    /// ranks the PERSON while the standings rank their TEAM contradicts itself
    /// on the same screen: the dashboard banner said "4th of 6" to someone
    /// whose team was winning. Nil when they aren't on the board yet, which is
    /// a real state on day one.
    func standing(for userId: String) -> (place: Int, of: Int, isTeam: Bool)? {
        if hasTeams, let myTeam = team(for: userId) {
            let teams = rankedTeams
            guard let index = teams.firstIndex(where: { $0.id == myTeam.id }) else { return nil }
            return (index + 1, teams.count, true)
        }
        let ranked = acceptedRanked
        guard let index = ranked.firstIndex(where: { $0.user_id == userId }) else { return nil }
        return (index + 1, ranked.count, false)
    }

    /// Accepted members, best score first — the individual leaderboard.
    private var acceptedRanked: [CompetitionUser] {
        users
            .filter { $0.invite_status == .accepted }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
    }

    /// The leaderboard's top three with the viewer always on it: outside the
    /// top three their row replaces the third, so the sticker can never show a
    /// podium the poster isn't on. `truncated` is what draws the gap.
    private static func podium(_ ranked: [CompetitionStickerData.Row]) -> [CompetitionStickerData.Row] {
        var rows = Array(ranked.prefix(3).enumerated().map { index, row in
            var placed = row
            placed.place = index + 1
            return placed
        })
        guard !rows.contains(where: { $0.isMe }),
              let meIndex = ranked.firstIndex(where: { $0.isMe }),
              !rows.isEmpty else { return rows }
        var me = ranked[meIndex]
        me.place = meIndex + 1
        me.truncated = true
        rows[rows.count - 1] = me
        return rows
    }

    /// A score in this competition's own grammar — days for streaks, distance
    /// for apex/race, points for targets/clash. The one place that decides how
    /// a number in this competition reads.
    func scoreLabel(_ score: Double) -> String {
        switch type {
        case .streaks:
            return "\(Int(score))d"
        case .apex, .race:
            return String(format: "%.1f %@", score, options.unit.shortDisplayName)
        case .targets, .clash:
            return "\(Int(score)) pt\(Int(score) == 1 ? "" : "s")"
        }
    }

    // MARK: Teams

    /// True when team play is configured (at least one team exists).
    var hasTeams: Bool {
        !(teams?.teams.isEmpty ?? true)
    }

    /// The team a user belongs to. An orphaned team_id (its team was deleted)
    /// counts as unassigned.
    func team(for userId: String) -> CompetitionTeam? {
        guard let teamId = users.first(where: { $0.user_id == userId })?.team_id else { return nil }
        return teams?.teams.first(where: { $0.id == teamId })
    }

    /// Teams ranked by their score as a competitor (computed server-side from
    /// the members' combined miles), stable on the configured order for
    /// ties/pre-start.
    var rankedTeams: [CompetitionTeam] {
        (teams?.teams ?? []).sorted { ($0.score ?? 0) > ($1.score ?? 0) }
    }

    /// Score label for a whole team, matching the individual leaderboard's units.
    func teamScoreLabel(_ team: CompetitionTeam) -> String {
        formattedScore(team.score ?? 0)
    }

    /// Label for one member inside a team row — what they CONTRIBUTED, in the
    /// competition's own unit.
    ///
    /// Not their score. The team is scored as one competitor over the members'
    /// combined miles, so member points don't sum to the team's number: "Red
    /// Team 4 pts" over "Alice 3 pts, Bob 2 pts" reads as arithmetic that got
    /// away from us. Miles are the thing that does add up, and they answer the
    /// question a member row is actually asked — who carried this.
    ///
    /// Falls back to the score for older servers that send no contribution,
    /// which is byte-identical to what shipped.
    func memberScoreLabel(_ user: CompetitionUser) -> String {
        if let contribution = user.team_contribution {
            return options.formatQuantityWithUnit(contribution)
        }
        return formattedScore(user.score ?? 0)
    }

    private func formattedScore(_ score: Double) -> String {
        switch type {
        case .streaks: return "\(Int(score))d"
        case .apex, .race: return options.formatQuantityWithUnit(score)
        case .targets, .clash: return "\(Int(score)) pts"
        }
    }

    /// Accepted members of a team, biggest contributor first.
    ///
    /// Ordered by what each member put INTO the team, not by their own score:
    /// once the team is what's being scored, a member's individual score is a
    /// fact about the individual leaderboard and says nothing about who carried
    /// the team. Falls back to score on older servers, which send no
    /// contribution.
    func members(of teamId: String) -> [CompetitionUser] {
        users
            .filter { $0.invite_status == .accepted && $0.team_id == teamId }
            .sorted { ($0.teamRankValue ?? $0.score ?? 0) > ($1.teamRankValue ?? $1.score ?? 0) }
    }

    /// A team's COMBINED quantity for one interval — the number the server
    /// scores that interval on.
    ///
    /// Derived client-side from the members' own `intervals`, which is the same
    /// arithmetic the server does; it has to be, because the server sends a
    /// team's SCORE (days won, or miles) and never its per-interval totals.
    func teamIntervalTotal(_ teamId: String, key: String) -> Double {
        members(of: teamId).reduce(0) { $0 + ($1.intervals?[key] ?? 0) }
    }

    /// Teams ranked by what they covered in ONE interval — the Today tab's
    /// order, which is not the standings order (that ranks on the whole
    /// competition's score).
    func rankedTeams(forIntervalKey key: String) -> [CompetitionTeam] {
        (teams?.teams ?? []).sorted {
            teamIntervalTotal($0.id, key: key) > teamIntervalTotal($1.id, key: key)
        }
    }

    /// Accepted participants not on any (existing) team.
    var unassignedUsers: [CompetitionUser] {
        let validIds = Set((teams?.teams ?? []).map { $0.id })
        return users.filter { $0.invite_status == .accepted && !($0.team_id.map(validIds.contains) ?? false) }
    }

    /// Stable per-team accent color, keyed by the team's configured position.
    func teamColor(_ teamId: String) -> Color {
        let palette: [Color] = [MADTheme.Colors.madRed, .blue, .orange, .green, .purple, .teal, .pink, .indigo, .mint, .yellow, .cyan, .brown]
        guard let idx = teams?.teams.firstIndex(where: { $0.id == teamId }) else { return .gray }
        return palette[idx % palette.count]
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

    /// Five-word gist, for the mode gallery and card subtitles. `description`
    /// is the full rules sentence and stays as-is (the create flow's type
    /// selector renders it); this is the version you can read at a glance.
    var tagline: String {
        switch self {
        case .streaks: return "Last one standing."
        case .apex: return "Most miles wins."
        case .targets: return "Hit your goal, bank a point."
        case .clash: return "Win the day, take the point."
        case .race: return "First to the finish line."
        }
    }

    /// Exactly three steps, imperative, no jargon — the body of the mode
    /// explainer. Kept to three because a fourth line stops being scannable,
    /// which is the entire point of the sheet.
    var howItWorks: [String] {
        switch self {
        case .streaks:
            return [
                "Everyone has to hit the same daily goal.",
                "Miss a day and you spend one of your lives.",
                "Run out of lives and you're out. Last one alive wins."
            ]
        case .apex:
            return [
                "Run and walk as normal for the set window.",
                "Every counted mile adds to your total.",
                "Highest total when the clock runs out wins."
            ]
        case .targets:
            return [
                "A goal is set for each day.",
                "Everyone who hits it that day banks a point.",
                "Most points at the end wins — you're racing the goal, not each other."
            ]
        case .clash:
            return [
                "Every day is its own mini-contest.",
                "Whoever goes furthest that day takes the point.",
                "First to the target score wins — or most points when time's up."
            ]
        case .race:
            return [
                "One distance is set as the finish line.",
                "Every mile you log moves you toward it.",
                "First person there wins. No clock, no daily goals."
            ]
        }
    }

    /// A worked example with real numbers. Abstract rules stop being abstract
    /// the moment someone sees one round play out.
    var example: String {
        switch self {
        case .streaks:
            return "Everyone owes a mile a day with 3 lives. You miss Tuesday and Friday — two lives gone, one left. Dave misses four days and he's out."
        case .apex:
            return "Over one week you cover 12.4 mi and Dave covers 9.1. You win — it doesn't matter how you split it up."
        case .targets:
            return "The goal is 2 mi a day. You hit it Mon, Wed and Sat for 3 points; Dave hits it twice. You win 3–2."
        case .clash:
            return "Monday you run 3 mi to Dave's 2.6 — your point. Tuesday he runs 4 to your 1. First to 5 daily wins takes it."
        case .race:
            return "First to 20 mi. You're at 14.2 after five days, Dave's at 16.8. He needs 3.2 more; you need 5.8."
        }
    }

    /// One line on the gallery card answering "should I pick this one?".
    var bestFor: String {
        switch self {
        case .streaks: return "Best for holding each other accountable."
        case .apex: return "Best for a whole-week push with 2–6 friends."
        case .targets: return "Best when everyone's at a different fitness level."
        case .clash: return "Best for a daily back-and-forth with one rival."
        case .race: return "Best for a long-haul goal with no deadline."
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

/// One team within a competition. `score` is derived server-side (straight
/// sum of accepted members' scores) and only present once the comp started.
struct CompetitionTeam: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    /// The team's score as a COMPETITOR — derived server-side from its members'
    /// combined per-interval miles, not from summing their individual scores.
    /// So it does not add up from the member rows, and nothing here should try.
    let score: Double?
    /// Streaks only: the team's shared pool of lives. Nil on older servers.
    let remaining_lives: Int?
    /// The team's combined miles (or steps) over the scored window. Nil on
    /// older servers.
    let quantity: Double?

    init(id: String, name: String, score: Double? = nil, remaining_lives: Int? = nil, quantity: Double? = nil) {
        self.id = id
        self.name = name
        self.score = score
        self.remaining_lives = remaining_lives
        self.quantity = quantity
    }

    /// The team's name in PROSE ("Team Red · 1st of 2"), where the word carries
    /// meaning the surrounding sentence doesn't.
    ///
    /// Only prefixes a name that isn't already one: the lobby creates default
    /// teams literally NAMED "Team 1"/"Team 2" (`CompetitionLobbyTeams`), so a
    /// blind `"Team \(name)"` rendered "Team Team 2" — on the post sticker, the
    /// dashboard rank line and a push, because three places each wrote it out.
    /// A leaderboard ROW needs none of this and uses `name` directly; the
    /// column it sits in is what says these are teams.
    var teamLabel: String {
        name.lowercased().hasPrefix("team") ? name : "Team \(name)"
    }
}

/// Team play configuration mirrored from `competitions.teams` on the backend.
struct CompetitionTeamsConfig: Codable, Equatable {
    /// When true, participants may pick/switch their own team in the lobby.
    let member_pick: Bool
    let teams: [CompetitionTeam]

    init(member_pick: Bool, teams: [CompetitionTeam]) {
        self.member_pick = member_pick
        self.teams = teams
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        member_pick = try container.decodeIfPresent(Bool.self, forKey: .member_pick) ?? false
        teams = try container.decodeIfPresent([CompetitionTeam].self, forKey: .teams) ?? []
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
    /// Team membership (id from Competition.teams). Nil = unassigned.
    let team_id: String?
    let username: String?
    let profile_image_url: String?
    let score: Double?
    let intervals: [String: Double]?
    let remaining_lives: Int?
    let has_manual_workouts: Bool?
    /// What this member put into their team's combined total over the scored
    /// window. Nil for competitions without teams, and on older servers — the
    /// member row falls back to `score` there, which is what shipped builds
    /// draw. Once the TEAM is the competitor, a member's own score no longer
    /// explains their team's, so this is the only number on a member row that
    /// adds up to anything.
    let team_contribution: Double?
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

    /// What to rank and label this member by inside a team row: their
    /// contribution when the server sends one, nil when it doesn't (older
    /// servers, and competitions without teams) so callers fall back to `score`.
    var teamRankValue: Double? { team_contribution }

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

    init(competition_id: String, user_id: String, invite_status: InviteStatus, team_id: String? = nil, username: String?, profile_image_url: String? = nil, score: Double?, intervals: [String: Double]?, remaining_lives: Int? = nil, has_manual_workouts: Bool? = nil, daily_activity: [String: [String: DailyActivityEntry]]? = nil, team_contribution: Double? = nil) {
        self.competition_id = competition_id
        self.user_id = user_id
        self.invite_status = invite_status
        self.team_id = team_id
        self.username = username
        self.profile_image_url = profile_image_url
        self.score = score
        self.intervals = intervals
        self.remaining_lives = remaining_lives
        self.has_manual_workouts = has_manual_workouts
        self.daily_activity = daily_activity
        self.team_contribution = team_contribution
    }

    // NOTE: this decoder is hand-written, so a new stored property added above
    // is NOT picked up for free — it has to be decoded here too, or the type
    // stops compiling (and, if it were given a default instead, would silently
    // read nil for every response).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        competition_id = try container.decodeIfPresent(String.self, forKey: .competition_id) ?? ""
        user_id = try container.decode(String.self, forKey: .user_id)
        invite_status = try container.decodeIfPresent(InviteStatus.self, forKey: .invite_status) ?? .pending
        team_id = try container.decodeIfPresent(String.self, forKey: .team_id)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        profile_image_url = try container.decodeIfPresent(String.self, forKey: .profile_image_url)
        score = try container.decodeIfPresent(Double.self, forKey: .score)
        intervals = try container.decodeIfPresent([String: Double].self, forKey: .intervals)
        remaining_lives = try container.decodeIfPresent(Int.self, forKey: .remaining_lives)
        has_manual_workouts = try container.decodeIfPresent(Bool.self, forKey: .has_manual_workouts)
        daily_activity = try container.decodeIfPresent([String: [String: DailyActivityEntry]].self, forKey: .daily_activity)
        team_contribution = try container.decodeIfPresent(Double.self, forKey: .team_contribution)
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

// MARK: Teams API models

/// PUT /competitions/:id/teams — every field optional; only what's sent changes.
struct SetTeamsRequest: Codable {
    let member_pick: Bool?
    /// Full replacement team list. Entries without an id are new (server mints one).
    let teams: [TeamDefinition]?
    /// userId -> teamId (or nil to unassign). Encoded nils become JSON nulls.
    let assignments: [String: String?]?

    struct TeamDefinition: Codable {
        let id: String?
        let name: String
    }
}

/// POST /competitions/:id/teams/pick
struct PickTeamRequest: Codable {
    let team_id: String?
}

/// GET /competitions/:id/teams/stats — recent-form stats for the balance UI.
struct TeamStatsResponse: Codable {
    let window_days: Int
    let interval: CompetitionInterval
    let unit: CompetitionUnit
    let stats: [String: MemberStat]

    struct MemberStat: Codable {
        let avg_per_day: Double
        let avg_per_interval: Double
    }
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
    /// "public" | "friends" | "private" — who may see my routes and photos.
    /// Optional: absent on older server builds (treat as "friends").
    let workout_visibility: String?
    /// "friends" | "self" — who may launch flyovers of my routes.
    /// Optional: absent on older server builds (treat as "friends").
    let flyover_visibility: String?
    /// Do collabs I'm tagged in join my profile's Posts grid? Server-enforced
    /// (the grid is a SQL query), so this is the authority, not the local copy.
    /// Optional: absent on older server builds (treat as on).
    let tagged_posts_on_profile: Bool?
    /// May friends invite me to a Buddy Walk? Server-enforced (it decides
    /// whether I appear in their picker at all), so this is the authority.
    /// Optional: absent on older server builds (treat as on).
    let buddy_invites_enabled: Bool?
    /// Does a skipped photo prompt still post the route/stats card? Stored
    /// server-side only so the choice follows the user to a new phone — the
    /// enforcement is client-side (see `RunPostService.autoPostMile`).
    /// Optional: absent on older server builds (treat as on).
    let auto_post_without_photo: Bool?
    /// Do photo-less auto route/stat cards join my profile's Posts grid?
    /// Server-enforced like tagged_posts_on_profile. Optional: absent on older
    /// server builds (treat as on).
    let auto_posts_on_profile: Bool?
    /// Stealth Mode — derived by the server from its window log. All optional:
    /// absent on older server builds (treat as off / no windows).
    let stealth_mode: Bool?
    /// ISO timestamp (fractional seconds — parse with BuddyDate), or null.
    let stealth_until: String?
    /// Recent windows, newest first; hydrates StealthModeStore (server wins).
    let stealth_windows: [StealthWindowDTO]?
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

/// The user a notification is about — server-resolved from the row's payload.
/// Drives the row's avatar and bold-name treatment (Instagram-style).
struct NotificationActor: Codable {
    let user_id: String
    let username: String?
    let first_name: String?
    let last_name: String?
    let profile_image_url: String?

    /// Name shown/bolded in row copy — matches the server's push copy, which
    /// leads with the username.
    var displayName: String {
        if let username, !username.isEmpty { return username }
        if let first = first_name, !first.isEmpty { return first }
        return "Someone"
    }

    /// Fuller name for avatar initials (first+last → two letters).
    var initialsName: String {
        let full = [first_name, last_name]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return full.isEmpty ? displayName : full
    }
}

/// The post a notification is about, when the viewer may still see it —
/// server-authorized with the same circle+block rules as the feed. Feeds the
/// row's trailing thumbnail; `post_id` is the row's direct tap target.
struct NotificationPostPreview: Codable {
    let post_id: String
    let media_url: String?
    /// The feed's "run to see today's photos" gate applied to the thumbnail:
    /// true = the photo is withheld until the viewer finishes their own mile,
    /// so the row draws a lock tile instead (media_url arrives blanked).
    let photo_locked: Bool?
}

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

    // Instagram-style row furniture — absent on older backends and on rows
    // with no actor/post, where the type-icon rendering remains.
    var actor: NotificationActor?
    var post_preview: NotificationPostPreview?
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
