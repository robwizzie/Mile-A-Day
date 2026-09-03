import Foundation
import CoreLocation

/// Recognizes repeated routes ("your 23rd time on this loop") by comparing
/// coarse spatial signatures: each route becomes the set of ~66m grid cells
/// it passes through, and two routes match when their cell sets overlap
/// enough (Jaccard). Deliberately start-point- and direction-insensitive —
/// the same loop walked the other way round is the same loop.
enum RouteMatcher {
    /// ~66m of latitude; longitude scaled per-route by cos(midLat) so cells
    /// are roughly square everywhere.
    private static let cellDegrees = 0.0006
    /// Overlap needed to call two routes "the same" — loose enough for GPS
    /// scatter and small detours, tight enough that two different loops from
    /// one front door don't merge.
    private static let matchThreshold = 0.62

    static func signature(_ coordinates: [CLLocationCoordinate2D]) -> Set<Int64> {
        guard coordinates.count >= 2 else { return [] }
        let midLat = coordinates.reduce(0) { $0 + $1.latitude } / Double(coordinates.count)
        let lonScale = max(0.2, cos(midLat * .pi / 180))
        var cells: Set<Int64> = []
        for c in coordinates {
            let latIdx = Int64((c.latitude / cellDegrees).rounded())
            let lonIdx = Int64((c.longitude * lonScale / cellDegrees).rounded())
            cells.insert(latIdx &* 100_000_003 &+ lonIdx)
        }
        return cells
    }

    static func isMatch(_ a: Set<Int64>, _ b: Set<Int64>) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        let intersection = a.intersection(b).count
        let union = a.count + b.count - intersection
        guard union > 0 else { return false }
        return Double(intersection) / Double(union) >= matchThreshold
    }

    /// "23rd" — for the repeats banner.
    static func ordinal(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)th"
    }

    // MARK: Own-routes repeat counting

    private struct OwnRoute: Decodable {
        let workout_id: String
        let route: [[Double]]
    }

    private struct CachedSignatures {
        let signatures: [(id: String, cells: Set<Int64>)]
        let fetchedAt: Date
    }
    private static var cache: CachedSignatures?

    /// Drop both caches — after a route was hidden server-side (Stealth) the
    /// library this indexes has shrunk and a stale signature would keep
    /// counting a walk that no longer exists there.
    static func invalidateCache() {
        cache = nil
        if let url = diskURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Signatures survive relaunch: the library fetch is the user's ENTIRE
    /// route history (up to 1000 × 300 points), which is far too heavy to
    /// re-download per session for a banner line. Routes are immutable per
    /// workout, so a day-old signature file is exactly as correct as a fresh
    /// fetch minus the newest day's workouts — and the fetch refreshes it
    /// once the TTL lapses.
    private struct SignatureFile: Codable {
        let cells: [String: [Int64]]
        let fetchedAt: Date
    }
    private static let diskTTL: TimeInterval = 24 * 3600
    private static var diskURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("route-signatures-v1.json")
    }

    private static func loadDiskCache() -> CachedSignatures? {
        guard let url = diskURL,
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SignatureFile.self, from: data),
              Date().timeIntervalSince(file.fetchedAt) < diskTTL
        else { return nil }
        return CachedSignatures(
            signatures: file.cells.map { ($0.key, Set($0.value)) },
            fetchedAt: file.fetchedAt
        )
    }

    private static func saveDiskCache(_ built: [(id: String, cells: Set<Int64>)]) {
        guard let url = diskURL else { return }
        let file = SignatureFile(
            cells: Dictionary(uniqueKeysWithValues: built.map { ($0.id, Array($0.cells)) }),
            fetchedAt: Date()
        )
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Repeats + speed rank for a route: "your 23rd time — 2nd fastest".
    struct RouteStats {
        /// Times this route appears in the library, THIS workout included.
        let count: Int
        /// 1 = fastest among the ranked repeats; nil when fewer than two
        /// repeats carry a local duration to compare against.
        let rank: Int?
        /// How many repeats the rank is out of (durations are read from the
        /// local WorkoutIndex, so server-only history may rank fewer than
        /// `count`).
        let ranked: Int
    }

    /// Stats for the route, ranked by the caller-supplied duration lookup
    /// (local WorkoutIndex — never a network call per matched id).
    static func routeStats(
        for coordinates: [CLLocationCoordinate2D],
        workoutId: String,
        currentDuration: TimeInterval,
        durationFor: (String) -> TimeInterval?
    ) async -> RouteStats? {
        guard let matched = await matchedRouteIds(for: coordinates, workoutId: workoutId)
        else { return nil }
        var durations: [TimeInterval] = []
        for id in matched.ids where id != workoutId {
            if let d = durationFor(id), d > 0 { durations.append(d) }
        }
        var rank: Int? = nil
        if !durations.isEmpty, currentDuration > 0 {
            rank = 1 + durations.filter { $0 < currentDuration - 0.5 }.count
        }
        return RouteStats(count: matched.count, rank: rank,
                          ranked: durations.count + 1)
    }

    /// How many of the user's stored routes (THIS one included) match the
    /// given trace — i.e. "your Nth time on this route". Nil when the library
    /// can't be fetched; 1 means this is the first. Disk-cached for 24h —
    /// the library only grows a route a day, and a same-day repeat still
    /// counts itself via the sawSelf fallback.
    static func repeatCount(for coordinates: [CLLocationCoordinate2D],
                            workoutId: String) async -> Int? {
        (await matchedRouteIds(for: coordinates, workoutId: workoutId))?.count
    }

    private static func matchedRouteIds(
        for coordinates: [CLLocationCoordinate2D],
        workoutId: String
    ) async -> (count: Int, ids: [String])? {
        let target = signature(coordinates)
        guard !target.isEmpty else { return nil }

        if cache == nil { cache = loadDiskCache() }
        var signatures = cache?.signatures
        if signatures == nil || Date().timeIntervalSince(cache?.fetchedAt ?? .distantPast) > diskTTL {
            guard let userId = UserDefaults.standard.string(forKey: "backendUserId"),
                  let fetched = try? await APIClient.fancyFetch(
                      endpoint: "/workouts/\(userId)/routes",
                      responseType: [OwnRoute].self
                  )
            else { return nil }
            let built = fetched.compactMap { entry -> (String, Set<Int64>)? in
                guard let coords = decodeRouteCoordinates(entry.route) else { return nil }
                return (entry.workout_id, signature(coords))
            }
            cache = CachedSignatures(signatures: built, fetchedAt: Date())
            saveDiskCache(built)
            signatures = built
        }

        guard let signatures else { return nil }
        var ids: [String] = []
        var sawSelf = false
        for entry in signatures {
            if entry.id == workoutId { sawSelf = true }
            if isMatch(target, entry.cells) { ids.append(entry.id) }
        }
        // A workout whose route hasn't reached the server yet still counts
        // itself once.
        var count = ids.count
        if !sawSelf { count += 1 }
        return (max(count, 1), ids)
    }
}
