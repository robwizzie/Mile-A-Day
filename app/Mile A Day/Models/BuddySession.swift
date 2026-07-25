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
