import Foundation
import Combine

/// Buddy walks on the Watch: see the walk you're on, start recording it here,
/// and report it to the crew.
///
/// The whole point is the phone in a pocket. A guest's PHONE only starts
/// recording when its lobby is on screen at the countdown; the Watch is on
/// the wrist, so "it started" is one tap there. The Watch then records with
/// its own HKWorkoutSession (`WatchWorkoutManager`, the same as any Watch
/// walk) and reports progress straight to the server every 5s as
/// `device: "watch"`, which is what tells the phone to stand down instead of
/// starting a second workout (`BuddyParticipant.isRecordingOnWatch`).
///
/// Talks to the API directly with the credentials the phone already shares
/// with the Watch (`authToken`/`backendUserId`, as `WatchWorkoutUploader`
/// does). Everything is best-effort: a failed report is retried by the next.
@MainActor
final class WatchBuddyClient: ObservableObject {
    static let shared = WatchBuddyClient()
    private init() {}

    private static let baseURL = "https://mad.mindgoblin.tech"

    /// The walk this user is on, when the Watch should offer it.
    @Published private(set) var offer: WatchBuddyOffer?

    private var lastReport: Date?

    // MARK: - Reading

    func refresh() async {
        guard let mine: WatchBuddyMine = await get("/buddy/sessions/mine") else { return }
        offer = mine.active.flatMap { WatchBuddyOffer(session: $0, me: Self.userId) }
    }

    // MARK: - Recording

    /// Throttled to one report per 5s; `force` for the last one.
    func reportProgress(
        sessionId: String, miles: Double, seconds: TimeInterval, paused: Bool, force: Bool = false
    ) async {
        if !force, let lastReport, Date().timeIntervalSince(lastReport) < 5 { return }
        lastReport = Date()
        _ = await post(
            "/buddy/sessions/\(sessionId)/progress",
            body: [
                "distanceMiles": max(0, miles),
                "durationSeconds": max(0, Int(seconds)),
                "paused": paused,
                "device": "watch",
            ])
    }

    /// The last metres, then done. The phone's own finish path is untouched:
    /// it never started a workout for this walk.
    func finish(sessionId: String, miles: Double, seconds: TimeInterval) async {
        await reportProgress(sessionId: sessionId, miles: miles, seconds: seconds, paused: false, force: true)
        _ = await post("/buddy/sessions/\(sessionId)/finish", body: [:])
        offer = nil
    }

    // MARK: - HTTP

    private static var token: String? {
        let t = UserDefaults.standard.string(forKey: "authToken")
        return (t?.isEmpty == false) ? t : nil
    }

    static var userId: String? {
        let id = UserDefaults.standard.string(forKey: "backendUserId")
        return (id?.isEmpty == false) ? id : nil
    }

    private func get<T: Decodable>(_ path: String) async -> T? {
        guard let token = Self.token, let url = URL(string: Self.baseURL + path) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("[WatchBuddyClient] GET \(path) failed: \(error)")
            return nil
        }
    }

    private func post(_ path: String, body: [String: Any]) async -> Bool {
        guard let token = Self.token, let url = URL(string: Self.baseURL + path),
              let payload = try? JSONSerialization.data(withJSONObject: body)
        else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        request.timeoutInterval = 15
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("[WatchBuddyClient] POST \(path) failed: \(error)")
            return false
        }
    }
}

// MARK: - What the Watch reads (just enough of the session snapshot)

struct WatchBuddyMine: Decodable {
    let active: WatchBuddySession?
}

struct WatchBuddySession: Decodable {
    let id: String
    let status: String
    let activityType: String?
    let startedAt: String?
    let participants: [WatchBuddyParticipant]

    enum CodingKeys: String, CodingKey {
        case id, status, participants
        case activityType = "activity_type"
        case startedAt = "started_at"
    }
}

struct WatchBuddyParticipant: Decodable {
    let userId: String
    let firstName: String?
    let username: String?
    let status: String
    let isHost: Bool?
    let lastHeardSeconds: Int?

    var name: String {
        if let firstName, !firstName.isEmpty { return firstName }
        if let username, !username.isEmpty { return username }
        return "your friend"
    }

    enum CodingKeys: String, CodingKey {
        case status
        case userId = "user_id"
        case firstName = "first_name"
        case username
        case isHost = "is_host"
        case lastHeardSeconds = "last_heard_seconds"
    }
}

/// The card on the Watch's home screen.
struct WatchBuddyOffer: Equatable {
    let sessionId: String
    let hostName: String
    let isRun: Bool
    /// The walk has started and nothing is recording this user yet: offer
    /// Start. False = still in the lobby (the card just says it's coming).
    let canStart: Bool
    /// Others on the walk, for "with Rob and 2 others".
    let othersCount: Int

    init?(session: WatchBuddySession, me: String?) {
        guard let me, session.status == "lobby" || session.status == "active",
              let mine = session.participants.first(where: { $0.userId == me }),
              ["joined", "ready", "active"].contains(mine.status)
        else { return nil }
        // Something (the phone, or this Watch) is already reporting them.
        if mine.lastHeardSeconds != nil { return nil }
        let host = session.participants.first { $0.isHost == true }
        sessionId = session.id
        hostName = host?.userId == me ? "your" : (host?.name ?? "your friend")
        isRun = session.activityType == "running"
        canStart = session.status == "active"
        othersCount = session.participants.filter {
            $0.userId != me && ["joined", "ready", "active", "finished"].contains($0.status)
        }.count
    }
}
