import CoreLocation

/// Finish-time polish for the tracked GPS trace, applied once before the
/// route is written to HealthKit (which is what the feed's maps draw from).
/// The live gate keeps stationary noise out; this pass cleans what's left:
///   1. Spike drop — a point whose implied speed to BOTH neighbors is beyond
///      on-foot plausibility, while its neighbors connect plausibly without
///      it, is a multipath blip the live cap couldn't see (it only ever
///      checks backwards).
///   2. Smoothing — light 25/50/25 positional average on interior points, so
///      residual jitter reads as a clean line. Endpoints stay put.
///   3. Simplification — Douglas-Peucker at 5m keeps the shape with a
///      fraction of the points (smaller HealthKit route and sync payload;
///      the server caps uploads at 300 points anyway).
/// Timestamps/order are preserved throughout — HKWorkoutRoute requires
/// monotonic samples.
enum WorkoutRouteCleanup {
    static func cleaned(_ points: [CLLocation]) -> [CLLocation] {
        guard points.count >= 3 else { return points }
        let despiked = droppingSpikes(points)
        let smoothed = smoothing(despiked)
        return simplified(smoothed, toleranceMeters: 5)
    }

    private static let maxOnFootSpeed: Double = 12

    private static func impliedSpeed(from a: CLLocation, to b: CLLocation) -> Double {
        let dt = abs(b.timestamp.timeIntervalSince(a.timestamp))
        guard dt > 0 else { return .infinity }
        return b.distance(from: a) / dt
    }

    private static func droppingSpikes(_ points: [CLLocation]) -> [CLLocation] {
        guard points.count >= 3 else { return points }
        var kept: [CLLocation] = [points[0]]
        for i in 1..<(points.count - 1) {
            let previous = kept[kept.count - 1]
            let candidate = points[i]
            let next = points[i + 1]
            let isSpike = impliedSpeed(from: previous, to: candidate) > maxOnFootSpeed
                && impliedSpeed(from: candidate, to: next) > maxOnFootSpeed
                && impliedSpeed(from: previous, to: next) <= maxOnFootSpeed
            if !isSpike {
                kept.append(candidate)
            }
        }
        kept.append(points[points.count - 1])
        return kept
    }

    private static func smoothing(_ points: [CLLocation]) -> [CLLocation] {
        guard points.count >= 3 else { return points }
        var out: [CLLocation] = [points[0]]
        for i in 1..<(points.count - 1) {
            let before = points[i - 1].coordinate
            let point = points[i]
            let after = points[i + 1].coordinate
            let coordinate = CLLocationCoordinate2D(
                latitude: before.latitude * 0.25 + point.coordinate.latitude * 0.5 + after.latitude * 0.25,
                longitude: before.longitude * 0.25 + point.coordinate.longitude * 0.5 + after.longitude * 0.25
            )
            out.append(CLLocation(
                coordinate: coordinate,
                altitude: point.altitude,
                horizontalAccuracy: point.horizontalAccuracy,
                verticalAccuracy: point.verticalAccuracy,
                course: point.course,
                speed: point.speed,
                timestamp: point.timestamp
            ))
        }
        out.append(points[points.count - 1])
        return out
    }

    /// Iterative Douglas-Peucker on a local flat-earth projection — meters of
    /// perpendicular error, fine at walk/run route scale.
    private static func simplified(_ points: [CLLocation], toleranceMeters: Double) -> [CLLocation] {
        guard points.count > 2 else { return points }
        let midLatitudeRadians = points[points.count / 2].coordinate.latitude * .pi / 180
        let metersPerDegreeLatitude = 111_132.0
        let metersPerDegreeLongitude = 111_320.0 * cos(midLatitudeRadians)
        let projected: [(x: Double, y: Double)] = points.map {
            (x: $0.coordinate.longitude * metersPerDegreeLongitude,
             y: $0.coordinate.latitude * metersPerDegreeLatitude)
        }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var spans: [(start: Int, end: Int)] = [(0, points.count - 1)]

        while let span = spans.popLast() {
            guard span.end > span.start + 1 else { continue }
            let (x1, y1) = projected[span.start]
            let (x2, y2) = projected[span.end]
            let dx = x2 - x1
            let dy = y2 - y1
            let segmentLengthSquared = dx * dx + dy * dy

            var maxDistance = 0.0
            var maxIndex = span.start
            for i in (span.start + 1)..<span.end {
                let (px, py) = projected[i]
                let distance: Double
                if segmentLengthSquared == 0 {
                    distance = hypot(px - x1, py - y1)
                } else {
                    let t = max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / segmentLengthSquared))
                    distance = hypot(px - (x1 + t * dx), py - (y1 + t * dy))
                }
                if distance > maxDistance {
                    maxDistance = distance
                    maxIndex = i
                }
            }

            if maxDistance > toleranceMeters {
                keep[maxIndex] = true
                spans.append((span.start, maxIndex))
                spans.append((maxIndex, span.end))
            }
        }

        return points.indices.compactMap { keep[$0] ? points[$0] : nil }
    }
}
