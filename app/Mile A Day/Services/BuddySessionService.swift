import Foundation
import SwiftUI

enum BuddyServiceError: LocalizedError {
    case notAuthenticated
    case api(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Please sign in again."
        case .api(let code): return BuddyServiceError.friendlyMessage(for: code)
        case .network(let message): return message
        }
    }

    /// The backend returns machine-readable codes; users need sentences.
    static func friendlyMessage(for code: String) -> String {
        switch code {
        case "session_full": return "This buddy walk is full."
        case "session_closed": return "This buddy walk already ended."
        case "session_not_found": return "We couldn't find that buddy walk."
        case "not_friends_with_host": return "You need to be friends to join."
        case "blocked": return "You can't join this buddy walk."
        case "not_host": return "Only the host can change this."
        case "session_not_editable": return "This walk already started."
        case "not_a_participant": return "You're not in this buddy walk."
        case "goal_required": return "Pick a goal to continue."
        case "goal_too_large": return "That goal is a little too ambitious."
        case "too_many_participants": return "That's too many people for one walk."
        default: return "Something went wrong. Try again."
        }
    }
}

/// Buddy Walks & Runs client.
///
/// A `.shared` singleton because a session must outlive any single view — the
/// same reasoning as `WorkoutLocationManager.shared`. The user can leave the
/// tracker, switch tabs, background the app and come back, and the session
/// keeps running.
///
/// TRANSPORT: plain REST polling. There is no WebSocket or SSE anywhere in this
/// app or the backend, and the backend runs overlapping containers on deploy,
/// so an in-memory room would split-brain. Two cadences:
///
///  - **Lobby / idle:** `GET /buddy/sessions/{id}/state` every 5s.
///  - **Actively tracking:** `POST /buddy/sessions/{id}/progress` every 5s, and
///    read the roster out of THAT response. The progress endpoint returns the
///    full snapshot precisely so a tracking client makes one call instead of
///    two — it halves the request count over a 45-minute walk and removes any
///    chance of a poll and a post racing each other.
///
/// The server also supports a `?since=<version>` cursor that answers 304 when
/// nothing changed. This client deliberately does not use it: handling 304
/// would mean adding a case to the shared `APIError` enum, which several other
/// services switch over exhaustively — a wide blast radius for a payload that
/// is only a handful of participants. The cursor stays available for any
/// future client that needs it.
@MainActor
final class BuddySessionService: ObservableObject {
    static let shared = BuddySessionService()

    /// The session the user is currently in (lobby or active).
    @Published private(set) var session: BuddySessionState?
    /// Invites waiting for a response.
    @Published private(set) var invites: [BuddySessionState] = []
    @Published private(set) var candidates: [BuddyCandidate] = []
    /// Friends walking right now that the user could join.
    @Published private(set) var joinableFriendSessions: [JoinableFriendSession] = []
    /// Everyone out right now — buddy room or solo. Superset of the above, and
    /// what the dashboard card actually renders.
    @Published private(set) var friendsOutNow: [FriendOutNow] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// Set once the app has told the backend this build has the buddy UI.
    private var hasEnrolled = false

    private var pollTask: Task<Void, Never>?
    private var lastProgressReport: Date?

    /// Foreground poll cadence. Fast enough that a friend's number never feels
    /// frozen, slow enough not to matter for battery over an hour.
    private let pollInterval: TimeInterval = 5
    /// Minimum gap between progress reports, independent of the tracker's 1 Hz
    /// UI tick.
    private let progressInterval: TimeInterval = 5

    private init() {}

    // MARK: - Derived

    var currentUserId: String? {
        UserManager.shared.currentUser.backendUserId
            ?? UserDefaults.standard.string(forKey: "backendUserId")
    }

    /// True when the user is mid-session and the tracker should show the roster.
    var hasLiveSession: Bool {
        guard let session else { return false }
        return session.status == .lobby || session.status == .active
    }

    var activeSessionId: String? {
        guard let session, session.status == .active else { return nil }
        return session.id
    }

    // MARK: - Enrollment

    /// Tell the backend this install has the Buddy Walks UI.
    ///
    /// This is the per-user half of the rollout gate: until a user is enrolled
    /// the server will never offer them as an invite candidate and never send
    /// them a buddy push, because their app might not be able to render it.
    /// Safe to call on every launch — the server keeps the first timestamp.
    func enrollIfNeeded() async {
        guard !hasEnrolled, currentUserId != nil else { return }
        do {
            _ = try await request(
                "/buddy/enroll", method: .POST, responseType: BuddyOKResponse.self)
            hasEnrolled = true
        } catch {
            // Enrolment is best-effort. A failure just means the user isn't
            // offered buddy walks yet; nothing else in the app is affected.
            print("[BuddySessionService] enroll failed: \(error)")
        }
    }

    // MARK: - Loading

    func refreshMySessions() async {
        guard currentUserId != nil else { return }
        do {
            let response = try await request(
                "/buddy/sessions/mine", responseType: BuddyMySessionsResponse.self)
            apply(response.active)
            invites = response.invites
        } catch {
            // A silent failure here is correct: this runs on every foreground
            // and must never surface an alert for a transient network blip.
            print("[BuddySessionService] refreshMySessions failed: \(error)")
        }
    }

    /// Refresh the "friends walking right now" list.
    ///
    /// Silent on failure — this drives an optional dashboard card, and a
    /// network blip must never produce an alert for something the user didn't
    /// ask for. Cleared on failure so a stale offer can't linger.
    func refreshJoinableFriendSessions() async {
        guard currentUserId != nil else { return }
        do {
            joinableFriendSessions = try await request(
                "/buddy/joinable", responseType: JoinableFriendSessionsResponse.self
            ).sessions
        } catch {
            joinableFriendSessions = []
        }
    }

    /// Everyone who is out right now — in a buddy room or walking on their own.
    ///
    /// Reads live presence rather than buddy rooms, which is what makes solo
    /// walkers visible at all. Silent on failure and cleared on error: this
    /// drives an optional dashboard card, and a stale offer to join a walk that
    /// already ended is worse than no card.
    func refreshFriendsOutNow() async {
        guard currentUserId != nil else { return }
        do {
            friendsOutNow = try await request(
                "/live/friends-out", responseType: FriendsOutNowResponse.self
            ).friends
        } catch {
            friendsOutNow = []
        }
    }

    /// Start a walk *because* a friend is already out, and invite them into it.
    ///
    /// Mirrors their activity so you're doing the same thing they are, and
    /// stamps `origin = .joinActive` — this is exactly the door that origin
    /// tracking exists to measure.
    func askFriendToWalk(_ friend: FriendOutNow) async throws {
        _ = try await createSession(
            mode: .together,
            goalValue: nil,
            activityType: friend.isRunning ? "running" : "walking",
            inviteUserIds: [friend.userId],
            origin: .joinActive
        )
    }

    /// Silent on failure, for the same reason refreshJoinableFriendSessions is:
    /// nobody ASKED for this list, it loads itself when the sheet appears. It
    /// used to publish `errorMessage`, which meant an alert slid over the sheet
    /// on every open whenever the endpoint was unreachable — and while an alert
    /// is presenting or dismissing, taps underneath it are swallowed, so the
    /// whole screen reads as laggy. The empty-friends card already says the
    /// right thing when the list comes back empty.
    func loadCandidates() async {
        do {
            candidates = try await request(
                "/buddy/candidates", responseType: BuddyCandidatesResponse.self
            ).candidates
        } catch {
            candidates = []
            print("[BuddySessionService] loadCandidates failed: \(error)")
        }
    }

    // MARK: - Lifecycle

    func createSession(
        mode: BuddyMode,
        goalValue: Double?,
        activityType: String,
        inviteUserIds: [String],
        origin: BuddyOrigin = .invite,
        /// Book the walk for later. The session waits in the lobby until then,
        /// and the server promotes it — so it starts on time whether or not
        /// anyone has the app open.
        scheduledStartAt: Date? = nil
    ) async throws -> BuddySessionState {
        var payload: [String: Any] = [
            "mode": mode.rawValue,
            "activityType": activityType,
            "inviteUserIds": inviteUserIds,
            // Which door this session came through. Until now the client never
            // sent it, so every session on record reads 'invite' and the
            // measurement it exists for wasn't running.
            "origin": origin.rawValue,
        ]
        if mode.needsGoal, let goalValue { payload["goalValue"] = goalValue }
        if let scheduledStartAt {
            payload["scheduledStartAt"] = ISO8601DateFormatter().string(
                from: scheduledStartAt)
        }

        let state = try await request(
            "/buddy/sessions",
            method: .POST,
            json: payload,
            responseType: BuddySessionState.self
        )
        apply(state)
        startPolling()
        return state
    }

    /// Change the lobby's settings, or pull more people in, before it starts.
    ///
    /// Host-only and lobby-only server-side. Only the fields you pass are
    /// touched — which is why `scheduledStartAt` needs three states rather than
    /// two: omitted leaves the booking alone, `.some(nil)` cancels it, and a
    /// date moves it. A plain optional couldn't say "cancel".
    ///
    /// `goalValue` follows the mode. Sending a new mode without a goal makes
    /// the server clear it, which is right for `together` and a 400
    /// (`goal_required`) for the scored modes — so callers changing INTO a
    /// scored mode must send both together.
    func updateSession(
        mode: BuddyMode? = nil,
        goalValue: Double? = nil,
        activityType: String? = nil,
        scheduledStartAt: Date?? = nil,
        inviteUserIds: [String]? = nil
    ) async throws -> BuddySessionState {
        guard let sessionId = session?.id else {
            throw BuddyServiceError.api("session_not_found")
        }
        var payload: [String: Any] = [:]
        if let mode { payload["mode"] = mode.rawValue }
        if let goalValue { payload["goalValue"] = goalValue }
        if let activityType { payload["activityType"] = activityType }
        if let inviteUserIds { payload["inviteUserIds"] = inviteUserIds }
        if let scheduledStartAt {
            // Present-but-nil is the explicit cancel; NSNull is how that
            // survives JSONSerialization, which drops a Swift nil entirely.
            // Written as an if/else rather than `map(...) ?? NSNull()` because
            // that form asks Swift to unify String and NSNull through `??`,
            // which only resolves via Any and reads as ambiguous.
            if let date = scheduledStartAt {
                payload["scheduledStartAt"] = ISO8601DateFormatter().string(from: date)
            } else {
                payload["scheduledStartAt"] = NSNull()
            }
        }

        let state = try await request(
            "/buddy/sessions/\(sessionId)",
            method: .PATCH,
            json: payload,
            responseType: BuddySessionState.self
        )
        apply(state)
        return state
    }

    func join(sessionId: String) async throws {
        let state = try await request(
            "/buddy/sessions/\(sessionId)/join",
            method: .POST,
            responseType: BuddySessionState.self
        )
        apply(state)
        invites.removeAll { $0.id == sessionId }
        startPolling()
    }

    func join(code: String) async throws {
        let state = try await request(
            "/buddy/sessions/join",
            method: .POST,
            json: ["code": code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()],
            responseType: BuddySessionState.self
        )
        apply(state)
        startPolling()
    }

    func decline(sessionId: String) async {
        _ = try? await request(
            "/buddy/sessions/\(sessionId)/decline",
            method: .POST,
            responseType: BuddyOKResponse.self
        )
        invites.removeAll { $0.id == sessionId }
    }

    func setReady(_ ready: Bool) async {
        guard let id = session?.id else { return }
        do {
            apply(
                try await request(
                    "/buddy/sessions/\(id)/ready",
                    method: .POST,
                    json: ["ready": ready],
                    responseType: BuddySessionState.self
                ))
        } catch {
            errorMessage = friendly(error)
        }
    }

    func start() async throws {
        guard let id = session?.id else { return }
        apply(
            try await request(
                "/buddy/sessions/\(id)/start",
                method: .POST,
                responseType: BuddySessionState.self
            ))
    }

    func leave() async {
        guard let id = session?.id else { return }
        _ = try? await request(
            "/buddy/sessions/\(id)/leave",
            method: .POST,
            responseType: BuddyOKResponse.self
        )
        stopPolling()
        session = nil
    }

    // MARK: - Progress

    /// Report live progress, throttled.
    ///
    /// Called from the tracker's existing 1 Hz tick; this collapses that to one
    /// network call every `progressInterval`. `force` bypasses the throttle for
    /// the final report before finishing, so the last few metres always land.
    func reportProgress(distanceMiles: Double, durationSeconds: TimeInterval, force: Bool = false) async {
        guard let id = activeSessionId else { return }
        if !force, let last = lastProgressReport,
            Date().timeIntervalSince(last) < progressInterval
        {
            return
        }
        lastProgressReport = Date()

        do {
            // The response IS the roster — no separate poll while tracking.
            apply(
                try await request(
                    "/buddy/sessions/\(id)/progress",
                    method: .POST,
                    json: [
                        "distanceMiles": distanceMiles,
                        "durationSeconds": Int(durationSeconds),
                    ],
                    responseType: BuddySessionState.self
                ))
        } catch {
            // Never surface a progress failure. The walk continues regardless;
            // the next report carries the cumulative total anyway, so a dropped
            // request self-heals.
            print("[BuddySessionService] progress failed: \(error)")
        }
    }

    /// Mark this participant done. Distance is reported one last time first so
    /// the recap and placements use the true final number.
    func finish(finalDistanceMiles: Double, durationSeconds: TimeInterval) async {
        guard let id = session?.id else { return }
        await reportProgress(
            distanceMiles: finalDistanceMiles,
            durationSeconds: durationSeconds,
            force: true
        )
        do {
            apply(
                try await request(
                    "/buddy/sessions/\(id)/finish",
                    method: .POST,
                    responseType: BuddySessionState.self
                ))
        } catch {
            print("[BuddySessionService] finish failed: \(error)")
        }
        stopPolling()
    }

    func recap(sessionId: String) async throws -> BuddyRecapResponse {
        try await request(
            "/buddy/sessions/\(sessionId)/recap", responseType: BuddyRecapResponse.self)
    }

    // MARK: - Polling

    /// Poll the session while it's on screen and the app is foregrounded.
    ///
    /// Suspended on background: the roster isn't visible, and the walk's own
    /// distance keeps accruing locally in WorkoutLocationManager either way.
    func startPolling() {
        stopPolling()
        guard hasLiveSession else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
                if Task.isCancelled { return }
                await self.pollOnce()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollOnce() async {
        guard let id = session?.id else {
            stopPolling()
            return
        }
        // While actively tracking, progress reports already carry the roster
        // back — polling on top of them would double the request count.
        if session?.status == .active, let last = lastProgressReport,
            Date().timeIntervalSince(last) < progressInterval * 2
        {
            return
        }
        do {
            apply(
                try await request(
                    "/buddy/sessions/\(id)/state", responseType: BuddySessionState.self))
        } catch {
            print("[BuddySessionService] poll failed: \(error)")
        }
    }

    // MARK: - State

    private func apply(_ state: BuddySessionState?) {
        guard let state else {
            session = nil
            stopPolling()
            return
        }
        session = state
        if state.status == .completed || state.status == .cancelled {
            stopPolling()
        }
    }

    /// Clear a finished session once its recap has been seen, so the dashboard
    /// stops offering it.
    func clearFinishedSession() {
        guard let session, session.status == .completed || session.status == .cancelled
        else { return }
        self.session = nil
    }

    // MARK: - Networking

    private func friendly(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
    }

    /// `nonisolated` for the same reason `makeRequest` below is, and it has to
    /// be: an @MainActor generic function lets its caller supply a MainActor-
    /// ISOLATED `Codable` conformance for `T`, which then can't be forwarded
    /// into nonisolated `makeRequest`. Being nonisolated makes the conformance
    /// requirement nonisolated too, so the hand-off is legal. It touches no
    /// actor state — serialize, forward, return.
    ///
    /// `json` is `sending` because `[String: Any]` isn't Sendable (`Any`
    /// isn't). Every caller passes a dictionary literal or a local it doesn't
    /// touch again, so the value is always in a disconnected region.
    private nonisolated func request<T: Codable & SendableMetatype>(
        _ endpoint: String,
        method: HTTPMethod = .GET,
        json: sending [String: Any]? = nil,
        responseType: T.Type
    ) async throws -> T {
        var body: Data?
        if let json { body = try JSONSerialization.data(withJSONObject: json) }
        return try await makeRequest(
            endpoint: endpoint, method: method, body: body, responseType: responseType)
    }

    /// `nonisolated` for the same reason CompetitionService's is: this only
    /// forwards to `APIClient.fancyFetch` and maps errors, and staying on
    /// @MainActor would push the call into a @concurrent context Swift 6
    /// rejects.
    private nonisolated func makeRequest<T: Codable & SendableMetatype>(
        endpoint: String,
        method: HTTPMethod,
        body: Data?,
        responseType: T.Type
    ) async throws -> T {
        do {
            return try await APIClient.fancyFetch(
                endpoint: endpoint,
                method: method,
                body: body,
                responseType: responseType
            )
        } catch let error as APIError {
            switch error {
            // accountMismatch is the cached-id-vs-token drift SessionIdentity
            // catches — same handling as every other service: it's an auth
            // problem, not a buddy problem.
            case .notAuthenticated, .unauthorized, .tokenRefreshFailed,
                .accountMismatch:
                throw BuddyServiceError.notAuthenticated
            case .badRequest(let message),
                .conflict(let message),
                .gone(let message),
                .rateLimited(let message),
                .apiError(let message):
                throw BuddyServiceError.api(message)
            case .notFound:
                // The feature flag is off server-side, or the session is gone.
                throw BuddyServiceError.api("session_not_found")
            case .serverError(let code):
                throw BuddyServiceError.network("Server error (\(code))")
            case .networkError(let message):
                throw BuddyServiceError.network(message)
            case .invalidURL, .invalidResponse:
                throw BuddyServiceError.network("Unexpected response")
            }
        } catch {
            throw BuddyServiceError.network(error.localizedDescription)
        }
    }
}
