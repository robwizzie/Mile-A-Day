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
/// STRICTLY ascending samples, which `strictlyAscending` establishes up front
/// (the persisted route comes back with second-resolution timestamps) and every
/// later step only ever drops points, never reorders them.
enum WorkoutRouteCleanup {
    static func cleaned(_ points: [CLLocation]) -> [CLLocation] {
        let ordered = strictlyAscending(points)
        guard ordered.count >= 3 else { return ordered }
        let despiked = droppingSpikes(ordered)
        let smoothed = smoothing(despiked)
        return simplified(smoothed, toleranceMeters: 5)
    }

    /// Enforce `HKWorkoutRouteBuilder.insertRouteData`'s hard precondition:
    /// timestamps strictly ascending. It rejects the WHOLE batch otherwise, and
    /// the only trace is a completion flag nobody sees — the walk just saves
    /// without a map.
    ///
    /// Fixes are delivered in order, so this is not about GPS: the route is
    /// persisted through `JSONEncoder`'s `.iso8601` strategy, which writes whole
    /// seconds and drops the fractional part. Two points kept inside the same
    /// second — routine at running pace, where the 4 m displacement floor clears
    /// in well under a second — come back from disk with EQUAL timestamps, which
    /// is not ascending. Nudging the duplicate forward by a millisecond keeps the
    /// batch insertable and moves the drawn line by nothing.
    static func strictlyAscending(_ points: [CLLocation]) -> [CLLocation] {
        guard points.count >= 2 else { return points }
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        var out: [CLLocation] = []
        out.reserveCapacity(sorted.count)
        for point in sorted {
            guard let previous = out.last else {
                out.append(point)
                continue
            }
            if point.timestamp > previous.timestamp {
                out.append(point)
                continue
            }
            out.append(point.withTimestamp(previous.timestamp.addingTimeInterval(0.001)))
        }
        return out
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
            out.append(point.withCoordinate(coordinate))
        }
        out.append(points[points.count - 1])
        return out
    }

    /// Corner-preserving downsample to at most `maxPoints`: Douglas-Peucker
    /// with the tolerance doubled until the result fits the budget. This is
    /// what the sync upload uses instead of a uniform stride — a stride
    /// spends points evenly along the trace regardless of shape, so a street
    /// corner that falls between two samples simply disappears, which is what
    /// made feed routes read rounder than the HealthKit original.
    static func simplified(_ points: [CLLocation], toMaxPoints maxPoints: Int) -> [CLLocation] {
        guard maxPoints >= 2, points.count > maxPoints else { return points }
        var tolerance = 2.0
        var result = simplified(points, toleranceMeters: tolerance)
        // Terminates: once the tolerance exceeds the route's largest
        // deviation, Douglas-Peucker returns just the endpoints.
        while result.count > maxPoints {
            tolerance *= 2
            result = simplified(result, toleranceMeters: tolerance)
        }
        return result
    }

    /// Iterative Douglas-Peucker on a local flat-earth projection — meters of
    /// perpendicular error, fine at walk/run route scale.
    static func simplified(_ points: [CLLocation], toleranceMeters: Double) -> [CLLocation] {
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

/// Rebuilding a `CLLocation` to change ONE field has to carry the other eight,
/// and the two accuracy fields are the easy ones to lose: the
/// `course:speed:timestamp:` initializer silently sets `courseAccuracy` and
/// `speedAccuracy` to -1, and CoreLocation treats a negative accuracy as "this
/// measurement is invalid" — so dropping them un-measures the very speed you
/// were preserving. These copy everything and vary one thing.
private extension CLLocation {
    func withCoordinate(_ coordinate: CLLocationCoordinate2D) -> CLLocation {
        copying(coordinate: coordinate, timestamp: timestamp)
    }

    func withTimestamp(_ timestamp: Date) -> CLLocation {
        copying(coordinate: coordinate, timestamp: timestamp)
    }

    private func copying(coordinate: CLLocationCoordinate2D, timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: course,
            courseAccuracy: courseAccuracy,
            speed: speed,
            speedAccuracy: speedAccuracy,
            timestamp: timestamp
        )
    }
}
