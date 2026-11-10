import Foundation
import Observation

/// `GET /users/:id/special-events`: one-day events (Champ 5K Day) showing now,
/// with the caller's own miles that day and how many friends are in.
struct SpecialEventsResponse: Codable {
    let events: [SpecialEvent]
}

struct SpecialEvent: Codable, Identifiable, Equatable {
    let event_id: String
    let title: String
    /// The local day, "2026-11-14".
    let date: String
    let miles: Double
    /// The distance that counts as done (the daily-goal leeway).
    let target_miles: Double
    let badge_id: String
    let reward_item_ids: [String]
    /// `upcoming`, `today` or `over`. A plain string so a future state can't
    /// fail the decode; anything unknown reads as over.
    let state: String
    let days_until: Int
    let my_miles: Double
    let earned: Bool
    let friends_going: Int
    let friends_done: Int
    let friends_preview: [Friend]

    struct Friend: Codable, Equatable, Identifiable {
        let user_id: String
        let username: String?
        let profile_image_url: String?
        var id: String { user_id }
    }

    var id: String { event_id }

    enum Phase { case upcoming, today, over }

    var phase: Phase {
        switch state {
        case "upcoming": return .upcoming
        case "today": return .today
        default: return .over
        }
    }

    var progress: Double { min(1, my_miles / max(target_miles, 0.01)) }
    var milesLeft: Double { max(0, miles - my_miles) }

    var rewardItems: [FlameyItem] { reward_item_ids.compactMap(FlameyItem.init(rawValue:)) }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "Saturday, Nov 14".
    var dayLine: String {
        guard let d = Self.dayParser.date(from: date) else { return date }
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return f.string(from: d)
    }

    /// "Nov 14".
    var shortDay: String {
        guard let d = Self.dayParser.date(from: date) else { return date }
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: d)
    }

    /// "rob, dave and 14 friends are in" / nil with nobody yet.
    var friendsLine: String? {
        guard friends_going > 0 else { return nil }
        let names = Array(friends_preview.compactMap(\.username).prefix(2))
        let others = friends_going - names.count
        let subject: String
        if names.isEmpty {
            subject = friends_going == 1 ? "1 friend" : "\(friends_going) friends"
        } else if others <= 0 {
            subject = names.joined(separator: " and ")
        } else {
            subject = names.joined(separator: ", ") + " and \(others) \(others == 1 ? "friend" : "friends")"
        }
        let one = friends_going == 1
        switch phase {
        case .upcoming: return "\(subject) \(one ? "is" : "are") in"
        case .today: return "\(subject) \(one ? "is" : "are") going for it"
        case .over: return "\(subject) went for it"
        }
    }
}

/// Loads and caches the special events. Snapshotted per user so the card has
/// content on a cold launch.
@MainActor
@Observable
final class SpecialEventService {
    static let shared = SpecialEventService()

    private(set) var events: [SpecialEvent] = []

    @ObservationIgnored private let snapshotKey = "specialEventsSnapshotV1"
    @ObservationIgnored private let snapshotUserKey = "specialEventsSnapshotUserV1"
    @ObservationIgnored private var lastLoadedAt: Date?
    @ObservationIgnored private var isLoading = false

    private var userId: String? { UserDefaults.standard.string(forKey: "backendUserId") }

    private init() {
        let defaults = UserDefaults.standard
        guard let userId, defaults.string(forKey: snapshotUserKey) == userId,
              let data = defaults.data(forKey: snapshotKey),
              let cached = try? JSONDecoder().decode(SpecialEventsResponse.self, from: data) else { return }
        events = cached.events
    }

    func event(id: String?) -> SpecialEvent? {
        guard let id else { return events.first }
        return events.first { $0.event_id == id }
    }

    /// Cheap to call from every appearance; miles change on sync.
    func refreshIfStale(maxAge: TimeInterval = 120) async {
        if let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < maxAge { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading, let userId, !userId.isEmpty, TokenStore.hasTokens else { return }
        isLoading = true
        defer { isLoading = false }
        // A failed read keeps what's on screen.
        guard let response: SpecialEventsResponse = try? await APIClient.fancyFetch(
            endpoint: "/users/\(userId)/special-events",
            responseType: SpecialEventsResponse.self
        ) else { return }
        events = response.events
        lastLoadedAt = Date()
        if let data = try? JSONEncoder().encode(response) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
            UserDefaults.standard.set(userId, forKey: snapshotUserKey)
        }
    }
}
