import Foundation

/// One race-distance personal record (best time), from the backend
/// `/workouts/:id/race-records` endpoints. Keys are already camelCase.
struct RaceRecord: Codable, Identifiable, Equatable {
    let distanceKey: String
    let durationSec: Double
    let distanceMiles: Double
    let workoutId: String
    let achievedDate: String  // "YYYY-MM-DD" in the user's local timezone

    var id: String { distanceKey + "-" + workoutId }
}

/// Display metadata for the standard race distances, in presentation order.
/// Mirrors `RACE_DISTANCES` in the backend workoutService — keep in sync.
struct RaceDistance: Identifiable, Equatable {
    let key: String
    let name: String
    var id: String { key }
}

enum RaceCatalog {
    static let distances: [RaceDistance] = [
        .init(key: "1mi", name: "1 Mile"),
        .init(key: "2mi", name: "2 Miles"),
        .init(key: "5k", name: "5K"),
        .init(key: "5mi", name: "5 Miles"),
        .init(key: "10k", name: "10K"),
        .init(key: "15k", name: "15K"),
        .init(key: "half", name: "Half Marathon"),
        .init(key: "marathon", name: "Marathon"),
    ]

    static func name(for key: String) -> String {
        distances.first { $0.key == key }?.name ?? key
    }

    /// mm:ss, or h:mm:ss once a time reaches an hour.
    static func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}

/// Read-only fetches for race PRs. All records are derived server-side from the
/// user's existing workouts — no separate PR store — so a full history counts.
enum RaceRecordsService {
    /// Best time per distance (distances with no qualifying run are absent).
    static func fetchRecords(userId: String) async throws -> [RaceRecord] {
        struct Resp: Decodable { let records: [RaceRecord] }
        let resp: Resp = try await APIClient.fancyFetch(
            endpoint: "/workouts/\(userId)/race-records",
            responseType: Resp.self
        )
        return resp.records
    }

    /// Full progression history (every qualifying run, newest first) for one distance.
    static func fetchHistory(userId: String, distanceKey: String) async throws -> [RaceRecord] {
        struct Resp: Decodable { let history: [RaceRecord] }
        let resp: Resp = try await APIClient.fancyFetch(
            endpoint: "/workouts/\(userId)/race-records/\(distanceKey)",
            responseType: Resp.self
        )
        return resp.history
    }
}
