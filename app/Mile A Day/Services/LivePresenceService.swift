//
//  LivePresenceService.swift
//  Mile A Day
//
//  Live tracking presence: while an in-app workout runs, keep a ~45s
//  heartbeat with the backend. The response says which accepted friends are
//  out RIGHT NOW (presence only — never location) and which mile hypes
//  landed since this session started, so they can surface mid-walk on the
//  tracking screen and Live Activity.
//
//  Strictly fire-and-forget: a failed call never affects tracking. Ticks are
//  driven from BOTH the view's foreground timer and the location/pedometer
//  callbacks (view timers suspend while the app is backgrounded; delegate
//  callbacks keep firing) — the service self-throttles, so callers just call
//  tick() freely, same contract as armTrackingWatchdog.
//

import Foundation

/// A friend who is mid-walk/run right now (from /live/heartbeat).
struct LiveFriendOut: Decodable, Equatable, Identifiable {
    let user_id: String
    let username: String?
    let first_name: String?
    let last_name: String?
    let profile_image_url: String?
    let workout_type: String
    let started_at: String
    /// The friend's CURRENT local date — the composite key half needed to
    /// send them a mile hype through the existing hype endpoint.
    let local_date: String

    var id: String { user_id }

    var displayName: String {
        let full = [first_name, last_name].compactMap { $0 }
            .joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if !full.isEmpty { return full }
        return username ?? "A friend"
    }

    var firstNameOrUsername: String {
        if let f = first_name, !f.isEmpty { return f }
        return username ?? "A friend"
    }
}

/// A mile hype that landed on ME since this tracking session started.
struct LiveHypeIn: Decodable, Equatable {
    let id: String
    let sender_id: String
    let username: String?
    let first_name: String?
    let last_name: String?
    let profile_image_url: String?
    let context_label: String?
    let created_at: String

    var senderName: String {
        if let f = first_name, !f.isEmpty { return f }
        return username ?? "A friend"
    }
}

final class LivePresenceService: ObservableObject {
    static let shared = LivePresenceService()

    @Published private(set) var friendsOut: [LiveFriendOut] = []
    /// Hypes received this session, appended in arrival order (deduped by
    /// id). The tracking view watches the count to toast + bump the LA.
    @Published private(set) var sessionHypes: [LiveHypeIn] = []

    private var sessionId: String?
    private var lastBeatAt: Date = .distantPast
    private var seenHypeIds = Set<String>()
    private var inFlight = false
    private let beatInterval: TimeInterval = 45

    private init() {}

    private struct StartResponse: Decodable {
        let session_id: String
        let started_at: String
    }
    private struct HeartbeatResponse: Decodable {
        let friends_out: [LiveFriendOut]
        let hypes: [LiveHypeIn]
    }
    private struct EmptyResponse: Decodable {}

    /// Begin a presence session for this workout. Always starts — the
    /// share_live_presence pref gates being SEEN (enforced server-side on
    /// readers), not seeing others.
    func startSession(workoutType: String) {
        friendsOut = []
        sessionHypes = []
        seenHypeIds = []
        sessionId = nil
        lastBeatAt = .distantPast
        Task { [weak self] in
            do {
                struct Body: Encodable { let workout_type: String }
                let body = try JSONEncoder().encode(Body(workout_type: workoutType))
                let resp: StartResponse = try await APIClient.fancyFetch(
                    endpoint: "/live/start",
                    method: .POST,
                    body: body,
                    responseType: StartResponse.self
                )
                await MainActor.run { self?.sessionId = resp.session_id }
                // First beat right away so a friend already out pulses
                // within seconds of starting, not after 45s.
                self?.tick(force: true)
            } catch {
                print("[LivePresence] start failed (non-fatal): \(error)")
            }
        }
    }

    /// Heartbeat, self-throttled to the beat interval — safe to call from
    /// every timer tick and every location/pedometer callback.
    func tick(force: Bool = false) {
        guard let sessionId else { return }
        guard force || Date().timeIntervalSince(lastBeatAt) >= beatInterval else { return }
        guard !inFlight else { return }
        inFlight = true
        lastBeatAt = Date()
        Task { [weak self] in
            defer { self?.inFlight = false }
            do {
                struct Body: Encodable { let session_id: String }
                let body = try JSONEncoder().encode(Body(session_id: sessionId))
                let resp: HeartbeatResponse = try await APIClient.fancyFetch(
                    endpoint: "/live/heartbeat",
                    method: .POST,
                    body: body,
                    responseType: HeartbeatResponse.self
                )
                await MainActor.run {
                    guard let self, self.sessionId == sessionId else { return }
                    self.friendsOut = resp.friends_out
                    let fresh = resp.hypes.filter { !self.seenHypeIds.contains($0.id) }
                    if !fresh.isEmpty {
                        fresh.forEach { self.seenHypeIds.insert($0.id) }
                        self.sessionHypes.append(contentsOf: fresh)
                    }
                }
            } catch {
                // Includes the 404 no_active_session case (stale session after
                // a second-device start): stay quiet — presence is best-effort
                // and must never disturb tracking.
                print("[LivePresence] heartbeat failed (non-fatal): \(error)")
            }
        }
    }

    /// End the session (idempotent server-side).
    func endSession() {
        let ending = sessionId
        sessionId = nil
        friendsOut = []
        guard let ending else { return }
        Task {
            struct Body: Encodable { let session_id: String }
            guard let body = try? JSONEncoder().encode(Body(session_id: ending)) else { return }
            _ = try? await APIClient.fancyFetch(
                endpoint: "/live/end",
                method: .POST,
                body: body,
                responseType: EmptyResponse.self
            )
        }
    }

    /// Persist the user's presence-consent answer locally and to the backend.
    static func setSharePresence(_ enabled: Bool) {
        var prefs = NotificationPreferences.load()
        prefs.shareLivePresence = enabled
        prefs.save()
        Task {
            struct Body: Encodable { let share_live_presence: Bool }
            struct AnyResponse: Decodable {}
            guard let body = try? JSONEncoder().encode(Body(share_live_presence: enabled)) else { return }
            _ = try? await APIClient.fancyFetch(
                endpoint: "/notifications/preferences",
                method: .PUT,
                body: body,
                responseType: AnyResponse.self
            )
        }
    }
}
