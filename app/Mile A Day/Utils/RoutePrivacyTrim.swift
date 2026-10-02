import Foundation
import CoreLocation

/// Hide start & end — the phone's mirror of the SERVER's route privacy trim.
///
/// The server is the authority: every route it serves to someone other than
/// its owner is trimmed at READ (`mad_route_view_bounds`, migration 0085;
/// `backend/src/services/routePrivacy.ts`), so nothing here protects a
/// friend-facing surface. This mirror exists for the two places the phone
/// draws the user's OWN route and must tell the truth about the trim:
///   - the owner's detail sheet, which shows the full line with the hidden
///     stretches dimmed ("Start & end hidden from friends"), and
///   - the share studio, which publishes the user's own route to the open
///     web and so applies the same trim to the picture.
///
/// The hash, the jitter and the distance formula are copied from the SQL
/// exactly — change one side, change both. The owner's own HealthKit trace is
/// denser than the server's simplified copy, so the hint lands within a few
/// metres of the served cut rather than on the same point; the cut DISTANCES
/// are identical.
enum RoutePrivacyTrim {
    /// The offered settings in metres, Off first. Mirrors the server's
    /// `ROUTE_PRIVACY_OPTIONS` — the server 400s anything else.
    static let options: [Int] = NotificationPreferences.routePrivacyOptions
    /// What an unset preference means (1/8 mile). Same default as the server.
    static let defaultMeters = NotificationPreferences.defaultRoutePrivacyMeters
    /// Below this many metres of kept line (or under 40% of the walk) nothing
    /// is served at all.
    static let minimumKeptMeters = 300.0
    static let minimumKeptFraction = 0.4

    /// The user's own setting, as last written or read from the server.
    static var currentSettingMeters: Int {
        NotificationPreferences.load().routePrivacyMeters
    }

    // MARK: - The server's arithmetic

    /// FNV-1a (32-bit) over the workout id's UTF-8 bytes — `mad_route_jitter_hash`.
    static func jitterHash(_ workoutId: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for byte in workoutId.utf8 {
            h = (h ^ UInt32(byte)) &* 16_777_619
        }
        return h
    }

    /// The actual cut at each end: the setting × 0.9–1.3, start from the low
    /// 16 bits of the hash, end from the next 16 — `mad_route_privacy_cuts`.
    static func cuts(workoutId: String, settingMeters: Int) -> (start: Double, end: Double) {
        let h = jitterHash(workoutId)
        let setting = Double(settingMeters)
        let start = setting * (0.9 + 0.4 * (Double(h & 0xFFFF) / 65535.0))
        let end = setting * (0.9 + 0.4 * (Double((h >> 16) & 0xFFFF) / 65535.0))
        return (start, end)
    }

    /// Equirectangular metres — the same formula the SQL uses.
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = 0.017453292519943295
        let k = cos((a.latitude + b.latitude) * 0.5 * r)
        let dy = (b.latitude - a.latitude) * r
        let dx = (b.longitude - a.longitude) * r * k
        return 6_371_008.8 * (dy * dy + dx * dx).squareRoot()
    }

    /// The 0-based, inclusive range of points a friend is served, or nil when
    /// what's left would be a sliver (then they're served NO route) —
    /// `mad_route_trim_bounds`. A boundary point is at least the cut from its
    /// true endpoint both along the path and in a straight line.
    static func keptRange(
        coordinates: [CLLocationCoordinate2D],
        cutStart: Double,
        cutEnd: Double
    ) -> ClosedRange<Int>? {
        let n = coordinates.count
        guard n >= 3 else { return nil }
        let first = coordinates[0]
        let last = coordinates[n - 1]

        var startIndex: Int?
        var startPath = 0.0
        var c = 0.0
        for i in 1..<n {
            c += distance(coordinates[i - 1], coordinates[i])
            if c >= cutStart, distance(first, coordinates[i]) >= cutStart {
                startIndex = i
                startPath = c
                break
            }
        }
        guard let s = startIndex else { return nil }

        var endIndex: Int?
        var endPath = 0.0
        c = 0
        for i in stride(from: n - 2, through: 0, by: -1) {
            c += distance(coordinates[i + 1], coordinates[i])
            if c >= cutEnd, distance(last, coordinates[i]) >= cutEnd {
                endIndex = i
                endPath = c
                break
            }
        }
        guard let e = endIndex, e > s else { return nil }

        // kept >= 0.4 × (start + kept + end)  ⇔  kept >= (2/3)(start + end)
        let threshold = max(minimumKeptMeters, (startPath + endPath) * 2.0 / 3.0)
        var kept = 0.0
        for i in (s + 1)...e {
            kept += distance(coordinates[i - 1], coordinates[i])
            if kept >= threshold { break }
        }
        return kept >= threshold ? s...e : nil
    }

    // MARK: - What a friend sees

    enum Outcome: Equatable {
        /// Setting Off (or nothing to trim): friends see the whole line.
        case full
        /// Friends see only these points.
        case trimmed(ClosedRange<Int>)
        /// The walk is too short to show any of it — friends get the stats
        /// card, exactly as with maps off.
        case hidden
    }

    static func outcome(
        coordinates: [CLLocationCoordinate2D],
        workoutId: String,
        settingMeters: Int = currentSettingMeters
    ) -> Outcome {
        guard settingMeters > 0, coordinates.count >= 2 else { return .full }
        let cut = cuts(workoutId: workoutId, settingMeters: settingMeters)
        guard let range = keptRange(coordinates: coordinates, cutStart: cut.start, cutEnd: cut.end)
        else { return .hidden }
        return .trimmed(range)
    }

    /// The route as it may leave the phone: trimmed exactly as friends see
    /// it, empty when they'd see none. `key` is the workout id when the
    /// caller has one; without it the route itself seeds the jitter, which
    /// keeps the cut stable across shares of the same walk.
    static func shareable(
        _ coordinates: [CLLocationCoordinate2D],
        key: String?,
        settingMeters: Int = currentSettingMeters
    ) -> [CLLocationCoordinate2D] {
        let seed = key ?? fallbackKey(coordinates)
        switch outcome(coordinates: coordinates, workoutId: seed, settingMeters: settingMeters) {
        case .full: return coordinates
        case .hidden: return []
        case .trimmed(let range): return Array(coordinates[range])
        }
    }

    private static func fallbackKey(_ coordinates: [CLLocationCoordinate2D]) -> String {
        guard let first = coordinates.first, let last = coordinates.last else { return "" }
        return String(format: "%.5f,%.5f|%.5f,%.5f|%d",
                      first.latitude, first.longitude, last.latitude, last.longitude,
                      coordinates.count)
    }
}

/// The owner's own view of the trim, for a detail sheet: which points friends
/// never see. Built by the caller (it knows the workout id) and handed to the
/// route views, which dim everything outside `kept`.
struct RoutePrivacyHint: Equatable {
    /// 0-based inclusive range of points friends are shown.
    let kept: ClosedRange<Int>

    /// nil when there is nothing to hint: setting Off, or a walk too short to
    /// share a route at all (that case gets its own caption, not a dim).
    static func forOwnRoute(
        coordinates: [CLLocationCoordinate2D],
        workoutId: String?,
        settingMeters: Int = RoutePrivacyTrim.currentSettingMeters
    ) -> RoutePrivacyHint? {
        guard let workoutId else { return nil }
        if case .trimmed(let range) = RoutePrivacyTrim.outcome(
            coordinates: coordinates, workoutId: workoutId, settingMeters: settingMeters) {
            return RoutePrivacyHint(kept: range)
        }
        return nil
    }
}

extension MADStoryContent {
    /// The content with its route trimmed by the user's own hide-start-&-end
    /// setting — what `ShareStudioView` actually draws and exports. A share
    /// card is the user publishing their route to the open web, so it gets
    /// the same treatment as a friend's view; a route too short to survive
    /// the trim is dropped, which removes the Route templates entirely.
    func trimmedForSharing(settingMeters: Int = RoutePrivacyTrim.currentSettingMeters) -> MADStoryContent {
        guard coordinates.count >= 2, settingMeters > 0 else { return self }
        var out = self
        out.coordinates = RoutePrivacyTrim.shareable(coordinates, key: workoutId, settingMeters: settingMeters)
        out.mapUnderlay = nil
        return out
    }
}
