import Foundation
import SwiftUI

/// Wire models for Buddy Walks & Runs.
///
/// Keys are snake_case to match the backend verbatim (every buddy query is raw
/// SQL, so the server speaks snake_case). Decoding uses explicit CodingKeys
/// rather than `.convertFromSnakeCase` because APIClient's shared decoder does
/// not apply a key strategy.
///
/// Every field the client does not strictly need is optional, so a server that
/// grows the payload can never break an installed build.

/// Parses the backend's timestamptz strings.
///
/// Backend `timestamptz` columns come back through `JSON.stringify(Date)`, i.e.
/// `2026-07-25T00:34:15.600Z` — WITH fractional seconds. `JSONDecoder`'s
/// `.iso8601` strategy (what APIClient's shared decoder uses) cannot parse
/// those, and one unparseable date fails the ENTIRE payload. So buddy
/// timestamps are carried as `String` and converted here, matching how the rest
/// of the app handles backend timestamps (see NotificationInboxView,
/// ProfileView).
enum BuddyDate {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return withFraction.date(from: value) ?? plain.date(from: value)
    }
}

// MARK: - Mode

enum BuddyMode: String, Codable, CaseIterable, Identifiable {
    /// No goal. Shared presence + live stats + one collab post at the end.
    case together
    /// Everyone's distance pools toward one shared target. Nobody loses.
    case coopGoal = "coop_goal"
    /// First to the goal wins.
    case raceGoal = "race_goal"
    /// Everyone moves for N minutes; furthest wins.
    case raceTime = "race_time"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .together: return "Just Together"
        case .coopGoal: return "Shared Goal"
        case .raceGoal: return "Race to Goal"
        case .raceTime: return "Furthest in Time"
        }
    }

    var subtitle: String {
        switch self {
        case .together: return "No goal — just move together"
        case .coopGoal: return "Pool your miles toward one target"
        case .raceGoal: return "First one to the distance wins"
        case .raceTime: return "Most distance before time's up"
        }
    }

    var icon: String {
        switch self {
        case .together: return "figure.2"
        case .coopGoal: return "target"
        case .raceGoal: return "flag.checkered"
        case .raceTime: return "stopwatch"
        }
    }

    /// Cooperative modes deliberately never declare a winner.
    var isCooperative: Bool {
        self == .together || self == .coopGoal
    }

    var needsGoal: Bool { self != .together }

    /// Goal is miles for distance modes, minutes for `raceTime`.
    var goalUnitLabel: String { self == .raceTime ? "min" : "mi" }

    var defaultGoal: Double { self == .raceTime ? 30 : 2 }

    var goalOptions: [Double] {
        self == .raceTime ? [10, 15, 20, 30, 45, 60] : [1, 2, 3, 5, 10]
    }

    /// An unrecognized future mode decodes as `.together` rather than failing
    /// the whole payload — the same survival rule the two status enums below
    /// already follow, and it matters more here: mode rides on every session
    /// AND on every row of the walk history, so one unknown value would take
    /// out an entire page rather than one card. `together` is the safe landing
    /// spot because it is the mode that asserts the least: no goal, no winner,
    /// no scoring claim about a walk this build can't score.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BuddyMode(rawValue: raw) ?? .together
    }
}

/// How a session came to exist. Sent at create time purely so we can measure
/// which door people actually use before investing in another one — the
/// proximity/tap handshake is a large piece of work and this is the evidence
/// that would justify it.
///
/// Not decoded from the server (nothing renders it); it only ever travels out.
enum BuddyOrigin: String {
    /// Host picked friends and invited them.
    case invite
    /// Host created a room to share a code, with nobody invited up front.
    case code
    /// Created in response to seeing a friend already out.
    case joinActive = "join_active"
    /// Formed by a proximity handshake. Unreachable until that ships.
    case nearby
}

enum BuddySessionStatus: String, Codable {
    case lobby, active, completed, cancelled

    /// An unrecognized future status decodes as `.completed` rather than
    /// failing the whole payload. Completed is the safe landing spot: it stops
    /// polling and shows a recap, where an unknown status treated as `.active`
    /// would leave the client stuck in a session it can't reason about.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BuddySessionStatus(rawValue: raw) ?? .completed
    }
}

enum BuddyParticipantStatus: String, Codable {
    case invited, joined, ready, active, finished, left, declined

    /// Unknown future values decode as `.joined` rather than failing the whole
    /// payload — a shipped build must survive the server growing a new state.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BuddyParticipantStatus(rawValue: raw) ?? .joined
    }
}

// MARK: - Participant

struct BuddyParticipant: Codable, Identifiable, Equatable {
    let userId: String
    let username: String?
    let firstName: String?
    let lastName: String?
    let profileImageUrl: String?
    let status: BuddyParticipantStatus
    let distanceMiles: Double
    let durationSeconds: Int
    /// Server-derived: no progress report in the last 90s. Rendered as a dimmed
    /// outline — never removed from the roster, because a friend who vanishes
    /// mid-walk reads as a crash.
    let isStale: Bool
    let isHost: Bool
    let place: Int?
    let finalDistanceMiles: Double?
    /// The real HKWorkout, stamped once it syncs. Nil until then — used to link
    /// a recap post to the run.
    let workoutId: String?

    var id: String { userId }

    var displayName: String {
        if let first = firstName, !first.isEmpty { return first }
        if let username, !username.isEmpty { return username }
        return "Friend"
    }

    /// Reconciled distance once the real workout has synced, live distance
    /// until then.
    var bestDistance: Double { finalDistanceMiles ?? distanceMiles }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case firstName = "first_name"
        case lastName = "last_name"
        case profileImageUrl = "profile_image_url"
        case status
        case distanceMiles = "distance_miles"
        case durationSeconds = "duration_seconds"
        case isStale = "is_stale"
        case isHost = "is_host"
        case place
        case finalDistanceMiles = "final_distance_miles"
        case workoutId = "workout_id"
    }
}

// MARK: - Session

struct BuddySessionState: Codable, Identifiable, Equatable {
    let id: String
    let joinCode: String
    let mode: BuddyMode
    let goalValue: Double?
    let activityType: String
    let status: BuddySessionStatus
    let hostUserId: String?
    /// Raw ISO strings — see `BuddyDate` for why these aren't `Date`.
    /// Use `startedAtDate` / `endsAtDate` instead of parsing at call sites.
    let scheduledStartAtRaw: String?
    let startedAtRaw: String?
    let endsAtRaw: String?
    let endedAtRaw: String?
    let winnerUserId: String?
    let stateVersion: Int
    let participants: [BuddyParticipant]
    let groupDistanceMiles: Double

    enum CodingKeys: String, CodingKey {
        case id
        case joinCode = "join_code"
        case mode
        case goalValue = "goal_value"
        case activityType = "activity_type"
        case status
        case hostUserId = "host_user_id"
        case scheduledStartAtRaw = "scheduled_start_at"
        case startedAtRaw = "started_at"
        case endsAtRaw = "ends_at"
        case endedAtRaw = "ended_at"
        case winnerUserId = "winner_user_id"
        case stateVersion = "state_version"
        case participants
        case groupDistanceMiles = "group_distance_miles"
    }

    // MARK: Derived

    /// The synced start instant. Set a few seconds in the FUTURE at start so
    /// every client counts down to the same wall-clock moment.
    var startedAtDate: Date? { BuddyDate.parse(startedAtRaw) }
    /// When a walk booked ahead of time is due to begin. The lobby counts down
    /// to this instead of showing the host's start button.
    var scheduledStartAtDate: Date? { BuddyDate.parse(scheduledStartAtRaw) }

    /// A booked walk that hasn't been promoted yet.
    var isScheduledPending: Bool {
        guard status == .lobby, let when = scheduledStartAtDate else { return false }
        return when > Date()
    }
    var endsAtDate: Date? { BuddyDate.parse(endsAtRaw) }
    var endedAtDate: Date? { BuddyDate.parse(endedAtRaw) }

    /// Participants actually moving (or done) — invitees who never joined are
    /// excluded so they can't dilute a co-op goal or pad the roster.
    var activeParticipants: [BuddyParticipant] {
        participants.filter { $0.status == .active || $0.status == .finished }
    }

    var lobbyParticipants: [BuddyParticipant] {
        participants.filter { $0.status != .left && $0.status != .declined }
    }

    func isHost(_ userId: String?) -> Bool {
        guard let userId else { return false }
        return hostUserId == userId
    }

    func me(_ userId: String?) -> BuddyParticipant? {
        guard let userId else { return nil }
        return participants.first { $0.userId == userId }
    }

    /// 0...1 progress toward the session's goal. Co-op measures the pooled
    /// total; races measure the leader.
    var goalProgress: Double {
        guard let goal = goalValue, goal > 0 else { return 0 }
        switch mode {
        case .together:
            return 0
        case .coopGoal:
            return min(groupDistanceMiles / goal, 1)
        case .raceGoal:
            let leader = activeParticipants.map(\.distanceMiles).max() ?? 0
            return min(leader / goal, 1)
        case .raceTime:
            guard let start = startedAtDate, let end = endsAtDate else { return 0 }
            let total = end.timeIntervalSince(start)
            guard total > 0 else { return 0 }
            return min(max(Date().timeIntervalSince(start) / total, 0), 1)
        }
    }

    /// Seconds until the synced start. Nil once underway.
    var secondsUntilStart: TimeInterval? {
        guard status == .active, let startedAtDate else { return nil }
        let remaining = startedAtDate.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    /// Run color follows the app-wide rule (runs red, walks blue).
    var accentColor: Color {
        MADTheme.workoutColor(activityType == "running" ? "running" : "walking")
    }

    var isRunning: Bool { activityType == "running" }
}

// MARK: - Responses

struct BuddyMySessionsResponse: Codable {
    let active: BuddySessionState?
    let invites: [BuddySessionState]
}

struct BuddyCandidate: Codable, Identifiable, Equatable {
    let userId: String
    let username: String?
    let firstName: String?
    let lastName: String?
    let profileImageUrl: String?
    let currentStreak: Int?

    var id: String { userId }

    var displayName: String {
        if let firstName, !firstName.isEmpty { return firstName }
        if let username, !username.isEmpty { return username }
        return "Friend"
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case firstName = "first_name"
        case lastName = "last_name"
        case profileImageUrl = "profile_image_url"
        case currentStreak = "current_streak"
    }
}

struct BuddyCandidatesResponse: Codable {
    let candidates: [BuddyCandidate]
}

struct BuddyRecapEvent: Codable, Identifiable {
    let kind: String
    let userId: String?
    /// Raw ISO string — see `BuddyDate`.
    let atRaw: String?

    var id: String { "\(kind)-\(userId ?? "-")-\(atRaw ?? "")" }
    var at: Date? { BuddyDate.parse(atRaw) }

    enum CodingKeys: String, CodingKey {
        case kind
        case userId = "user_id"
        case atRaw = "at"
    }
}

struct BuddyRecapResponse: Codable {
    let session: BuddySessionState
    let events: [BuddyRecapEvent]
}

struct BuddyOKResponse: Codable {
    let ok: Bool?
}

/// A friend's buddy walk that's running right now and has room.
///
/// This is the permission-free substitute for ambient proximity sensing:
/// same "they're doing it, join them" moment, no Bluetooth, any distance,
/// and it works for remote friends too. Pull-only — the server deliberately
/// sends no push for these, so nobody gets spammed every time a friend walks.
struct JoinableFriendSession: Codable, Identifiable, Equatable {
    let sessionId: String
    let joinCode: String
    let mode: BuddyMode
    let activityType: String
    let status: BuddySessionStatus
    let hostUserId: String
    let hostUsername: String?
    let hostFirstName: String?
    let hostProfileImageUrl: String?
    let participantCount: Int

    var id: String { sessionId }

    var hostDisplayName: String {
        if let hostFirstName, !hostFirstName.isEmpty { return hostFirstName }
        if let hostUsername, !hostUsername.isEmpty { return hostUsername }
        return "A friend"
    }

    var isRunning: Bool { activityType == "running" }
    var accentColor: Color {
        MADTheme.workoutColor(isRunning ? "running" : "walking")
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case joinCode = "join_code"
        case mode
        case activityType = "activity_type"
        case status
        case hostUserId = "host_user_id"
        case hostUsername = "host_username"
        case hostFirstName = "host_first_name"
        case hostProfileImageUrl = "host_profile_image_url"
        case participantCount = "participant_count"
    }
}

struct JoinableFriendSessionsResponse: Codable {
    let sessions: [JoinableFriendSession]
}

/// A friend who is out walking or running RIGHT NOW, seen from the Friends tab.
///
/// Supersedes `JoinableFriendSession` for the Friends-tab card: that one could
/// only ever see friends already inside a buddy room, which meant a friend
/// walking solo — the single best person to start a walk with — was invisible.
/// This comes from live presence, so it sees both, and the buddy fields are
/// simply nil for a solo walker.
struct FriendOutNow: Codable, Identifiable, Equatable {
    let userId: String
    let username: String?
    let firstName: String?
    let lastName: String?
    let profileImageUrl: String?
    let workoutType: String
    /// Live miles as of their last heartbeat. Monotonic server-side.
    /// Optional: absent from older server builds, in which case the row shows
    /// presence without asserting a confident "0.00".
    let distanceMiles: Double?
    /// THEIR daily goal, so progress draws against the right target.
    let goalMiles: Double?
    /// When their session started — used for "out 12m".
    let startedAt: String?
    /// Their CURRENT local date: the composite key half needed to hype a mile
    /// mid-walk through the existing endpoint.
    let localDate: String?
    /// Non-nil only when they're in a buddy room that has space left.
    let buddySessionId: String?
    let buddyJoinCode: String?
    let buddyMode: BuddyMode?
    let buddyParticipantCount: Int?

    var id: String { userId }

    var displayName: String {
        if let firstName, !firstName.isEmpty { return firstName }
        if let username, !username.isEmpty { return username }
        return "A friend"
    }

    var isRunning: Bool { workoutType == "running" }
    var accentColor: Color {
        MADTheme.workoutColor(isRunning ? "running" : "walking")
    }

    /// True when there's a room to join. False means they're out on their own —
    /// which is an invitation opportunity, not a dead end.
    var hasJoinableRoom: Bool { buddySessionId != nil }

    /// Their goal, defaulting to the app's premise when the server didn't say.
    var goal: Double { (goalMiles ?? 0) > 0 ? (goalMiles ?? 1) : 1 }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case firstName = "first_name"
        case lastName = "last_name"
        case profileImageUrl = "profile_image_url"
        case workoutType = "workout_type"
        case distanceMiles = "distance_miles"
        case goalMiles = "goal_miles"
        case startedAt = "started_at"
        case localDate = "local_date"
        case buddySessionId = "buddy_session_id"
        case buddyJoinCode = "buddy_join_code"
        case buddyMode = "buddy_mode"
        case buddyParticipantCount = "buddy_participant_count"
    }
}

struct FriendsOutNowResponse: Codable {
    let friends: [FriendOutNow]
}

// MARK: - Recurring walks

/// A standing buddy walk — "us, 6pm, weekdays".
///
/// A TEMPLATE, not a session. The server spawns a real scheduled session from
/// it shortly before each occurrence, so nothing downstream (lobby, countdown,
/// recap) knows a routine was involved.
///
/// `minutesOfDay` is LOCAL wall-clock minutes since midnight, paired with an
/// IANA zone, never an instant — "6pm on weekdays" has to survive DST, and a
/// stored timestamp would drift an hour twice a year.
struct BuddyRecurringWalk: Codable, Identifiable, Equatable {
    let id: String
    let mode: BuddyMode
    let goalValue: Double?
    let activityType: String
    let daysOfWeek: [Int]
    let minutesOfDay: Int
    let isActive: Bool

    var isRunning: Bool { activityType == "running" }

    /// "6:00 PM", in the reader's own locale.
    var timeText: String {
        var components = DateComponents()
        components.hour = minutesOfDay / 60
        components.minute = minutesOfDay % 60
        guard let date = Calendar.current.date(from: components) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// "Weekdays" / "Every day" / "Mon, Wed, Fri" — 0 = Sunday, matching the
    /// server's `EXTRACT(DOW)`.
    var daysText: String {
        let days = Set(daysOfWeek)
        if days == Set(0...6) { return "Every day" }
        if days == Set(1...5) { return "Weekdays" }
        if days == Set([0, 6]) { return "Weekends" }
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return daysOfWeek.sorted().compactMap { names.indices.contains($0) ? names[$0] : nil }
            .joined(separator: ", ")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case mode
        case goalValue = "goal_value"
        case activityType = "activity_type"
        case daysOfWeek = "days_of_week"
        case minutesOfDay = "minutes_of_day"
        case isActive = "is_active"
    }
}

struct BuddyRoutinesResponse: Codable {
    let routines: [BuddyRecurringWalk]
}

// MARK: - Walking partners

/// How much you've actually walked with one friend.
///
/// Derived server-side from finished sessions you both completed — no stored
/// counter, so it can't drift. `milesTogether` is YOUR distance across those
/// walks, not the pooled total: a pooled figure double-counts the same walk
/// from each side, so the two of you would see different numbers for the same
/// history and neither would match what either actually covered.
struct BuddyPartner: Codable, Identifiable, Equatable {
    let userId: String
    let username: String?
    let firstName: String?
    let profileImageUrl: String?
    let walks: Int
    let milesTogether: Double
    /// `date` column, so a plain string is safe.
    let lastWalkDate: String?

    var id: String { userId }

    var displayName: String {
        if let firstName, !firstName.isEmpty { return firstName }
        if let username, !username.isEmpty { return username }
        return "Friend"
    }

    /// "12 walks · 14.2 mi together"
    var summary: String {
        let walkWord = walks == 1 ? "walk" : "walks"
        return "\(walks) \(walkWord) · \(String(format: "%.1f", milesTogether)) mi together"
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case firstName = "first_name"
        case profileImageUrl = "profile_image_url"
        case walks
        case milesTogether = "miles_together"
        case lastWalkDate = "last_walk_date"
    }
}

struct BuddyPartnersResponse: Codable {
    let partners: [BuddyPartner]
}

// MARK: - History

/// A photo somebody posted from a past walk.
///
/// The server resolves these through the SAME post-access guard the feed and
/// comments use, so a photo that left the feed leaves the history with it —
/// having walked with someone is not standing permission to see their photos.
struct BuddyWalkPhoto: Codable, Identifiable, Equatable {
    let postId: String
    let userId: String
    let mediaUrl: String
    let caption: String?

    var id: String { postId }

    /// The DB stores bare paths and the server signs them at read; resolving
    /// against the API host is `ProfileImageService.fullImageURL`'s job, the
    /// same helper `PostItem.mediaURL` uses. A raw `URL(string:)` here would
    /// produce a relative url that loads nothing.
    var url: URL? { ProfileImageService.fullImageURL(for: mediaUrl) }

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case userId = "user_id"
        case mediaUrl = "media_url"
        case caption
    }
}

/// One person on a past walk.
///
/// `username`/`firstName`/`profileImageUrl` come back nil when the viewer can
/// no longer see that profile (the friendship ended). Their miles still count
/// toward the walk's total — the walk happened — so the row renders
/// anonymously rather than disappearing.
struct BuddyWalkParticipant: Codable, Identifiable, Equatable {
    let userId: String
    let username: String?
    let firstName: String?
    let profileImageUrl: String?
    let distanceMiles: Double
    let durationSeconds: Int
    let place: Int?
    let isHost: Bool

    var id: String { userId }

    /// True when the viewer can still see who this was.
    var isNamed: Bool {
        (firstName?.isEmpty == false) || (username?.isEmpty == false)
    }

    var displayName: String {
        if let firstName, !firstName.isEmpty { return firstName }
        if let username, !username.isEmpty { return username }
        return "A friend"
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case firstName = "first_name"
        case profileImageUrl = "profile_image_url"
        case distanceMiles = "distance_miles"
        case durationSeconds = "duration_seconds"
        case place
        case isHost = "is_host"
    }
}

/// A walk you've already taken, as the history screen draws it.
struct BuddyWalkRecord: Codable, Identifiable, Equatable {
    let id: String
    let mode: BuddyMode
    let activityType: String
    let goalValue: Double?
    /// `date` column, so a plain string is safe (see BuddyDate for the
    /// timestamptz ones below).
    let localDate: String
    let startedAtRaw: String?
    let endedAtRaw: String?
    let winnerUserId: String?
    let groupDistanceMiles: Double
    let myDistanceMiles: Double
    let myDurationSeconds: Int
    let myPlace: Int?
    let participants: [BuddyWalkParticipant]
    let photos: [BuddyWalkPhoto]
    /// Keyset cursor. Pass the LAST record's cursor as `before` for the next
    /// page — never a hand-built timestamp.
    let cursor: String

    enum CodingKeys: String, CodingKey {
        case id
        case mode
        case activityType = "activity_type"
        case goalValue = "goal_value"
        case localDate = "local_date"
        case startedAtRaw = "started_at"
        case endedAtRaw = "ended_at"
        case winnerUserId = "winner_user_id"
        case groupDistanceMiles = "group_distance_miles"
        case myDistanceMiles = "my_distance_miles"
        case myDurationSeconds = "my_duration_seconds"
        case myPlace = "my_place"
        case participants
        case photos
        case cursor
    }

    // MARK: Derived

    var startedAtDate: Date? { BuddyDate.parse(startedAtRaw) }
    var endedAtDate: Date? { BuddyDate.parse(endedAtRaw) }

    var isRunning: Bool { activityType == "running" }
    var accentColor: Color { MADTheme.workoutColor(isRunning ? "running" : "walking") }

    /// Everyone but the viewer. The walk's identity is who you were with.
    func others(excluding viewerId: String?) -> [BuddyWalkParticipant] {
        participants.filter { $0.userId != viewerId }
    }

    /// "You and Sam" / "You, Sam and 2 others" — the line that names the walk.
    func crewText(excluding viewerId: String?) -> String {
        let names = others(excluding: viewerId).map(\.displayName)
        switch names.count {
        case 0: return "On your own"
        case 1: return "You and \(names[0])"
        case 2: return "You, \(names[0]) and \(names[1])"
        default:
            return "You, \(names[0]) and \(names.count - 1) others"
        }
    }

    /// Wall-clock length of the walk. Falls back to the viewer's own recorded
    /// duration when the session never stamped an end (a swept-abandoned room).
    var durationSeconds: Int {
        if let start = startedAtDate, let end = endedAtDate {
            let span = Int(end.timeIntervalSince(start))
            if span > 0 { return span }
        }
        return myDurationSeconds
    }

    /// "42m" / "1h 08m". Never "0m" — a walk that took no time reads as broken.
    var durationText: String {
        let seconds = max(durationSeconds, 60)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(String(format: "%02d", minutes))m" : "\(minutes)m"
    }

    /// The walk's calendar day.
    ///
    /// `local_date` is a LABEL ("2026-08-11"), not an instant, so it is parsed
    /// in the DEVICE's zone — which is the zone everything downstream then
    /// renders and compares in (`isDateInToday`, `.formatted`). Parsing it as
    /// ET or UTC and then formatting locally is the bug HallOfStreaksSection
    /// documents: the two zones disagree and every date prints one day early
    /// across the Americas.
    var date: Date? { BuddyWalkRecord.dayFormatter.date(from: localDate) }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        // POSIX so a non-Gregorian device calendar can't reinterpret the
        // fixed format; time zone deliberately left at the system default.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var dayText: String {
        guard let date else { return localDate }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "AUGUST 2026" — the timeline's section header.
    var monthKey: String {
        guard let date else { return "" }
        return date.formatted(.dateTime.month(.wide).year()).uppercased()
    }
}

/// Lifetime shared-walk totals, as the history screen's headline.
struct BuddyHistoryTotals: Codable, Equatable {
    let walks: Int
    /// The viewer's OWN miles — see `BuddyPartner` for why a pooled figure
    /// would disagree with itself from the other side.
    let miles: Double
    let partners: Int
    let firstWalkDate: String?
    let lastWalkDate: String?

    enum CodingKeys: String, CodingKey {
        case walks
        case miles
        case partners
        case firstWalkDate = "first_walk_date"
        case lastWalkDate = "last_walk_date"
    }
}

/// `totals` rides the FIRST page only — it describes the whole archive, not the
/// page, so the client keeps what page 1 gave it while paginating.
struct BuddyHistoryResponse: Codable {
    let sessions: [BuddyWalkRecord]
    let nextBefore: String?
    let totals: BuddyHistoryTotals?

    enum CodingKeys: String, CodingKey {
        case sessions
        case nextBefore = "next_before"
        case totals
    }
}
