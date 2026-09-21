import CoreLocation
import Foundation

/// Where a recorded route stops being a PATH.
///
/// A walk can be paused, travelled, and resumed somewhere else. The tracker
/// gets the DISTANCE right for that — `resume()` drops the accrual anchor, so
/// the journey in between never counts — and then stores both stretches in one
/// flat array of points. Nothing in that array says the two halves aren't
/// joined, so every surface that draws it drew a straight line across the
/// eighteen miles nobody walked, and the flyover spent most of the flight
/// travelling it at walking pace.
///
/// (The same `resume()` is why the gap exists at all: `lastRoutePoint` is
/// nil'd, which is exactly what disables the 12 m/s teleport cap for the first
/// point after a pause. Keeping the anchor instead would reject the whole of
/// the second stretch, which is real walking — so the break has to be
/// recognised at the drawing end, which also repairs every walk already
/// posted.)
///
/// ## What counts as a gap
///
/// Every rule here is set so that CUTTING A REAL WALK is the thing it won't
/// do. A missed gap leaves a surface exactly as it draws today; a false one
/// puts a hole in somebody's route and takes the distance out from under
/// their odometer. So the bars are deliberately far outside anything a walk
/// produces, and a step has to clear one of three:
///
/// - longer than `maxOnFootStep` — not one step of a walk at any speed;
/// - longer than `dominantStep` AND more than `dominantShare` of the whole
///   route — the scale-relative case, which is what catches a mile walked
///   and a mile driven;
/// - implied speed over `maxOnFootSpeed`, when the route carries a clock.
///
/// The first two need no `route_times`, which matters: clocks only arrive
/// with `SimplifiedRoute` and the `backfillRouteClocks` sweep, so gating the
/// whole thing on one would leave every older walk drawing its straight line
/// across the state. The speed rule is the one that needs it, and simply
/// doesn't run without.
enum RouteGaps {
    /// Faster than anything on foot, over a whole stored step. The same
    /// ceiling `WorkoutRouteCleanup` uses to call a fix a spike, and
    /// deliberately not lower: these thresholds decide whether to CUT a line,
    /// and cutting a real walk is a worse bug than missing a gap. 12 m/s is
    /// 27 mph — no runner is near it, and it leaves every honest sprint
    /// finish alone.
    static let maxOnFootSpeed: Double = 12

    /// A single stored step this long is not one step of a walk however long
    /// it took. ~1.9 miles: Douglas-Peucker at 5m (and the server's
    /// 300-point budget, which can widen the tolerance on a very long route)
    /// can leave a few hundred metres between kept points on straight ground,
    /// so the bar sits an order of magnitude above that.
    static let maxOnFootStep: Double = 3000

    /// A shorter hop still isn't walking when it is most of the "walk": a
    /// mile on foot plus a mile in the car is half its own length in one
    /// step. Scale-relative on purpose — the same 900m step is a quarter of
    /// a short walk and 3% of a long one, and only the first is impossible.
    static let dominantStep: Double = 500
    static let dominantShare: Double = 0.25

    /// Indices `i` where the step from point `i` to point `i + 1` is not
    /// walked ground, so nothing should draw a line along it or fly it.
    ///
    /// `times` is optional and only the speed rule reads it — see above.
    static func breakIndices(
        coordinates: [CLLocationCoordinate2D],
        times: [Double]?
    ) -> Set<Int> {
        guard coordinates.count >= 2 else { return [] }
        // A clock only counts when it describes THESE points.
        let clock: [Double]? = (times?.count == coordinates.count) ? times : nil
        var steps: [Double] = []
        steps.reserveCapacity(coordinates.count - 1)
        var total = 0.0
        for i in 0..<(coordinates.count - 1) {
            let metres = haversineMeters(coordinates[i], coordinates[i + 1])
            steps.append(metres)
            total += metres
        }
        var breaks: Set<Int> = []
        for (i, metres) in steps.enumerated() {
            if metres > maxOnFootStep {
                breaks.insert(i)
                continue
            }
            if metres > dominantStep, total > 0, metres / total > dominantShare {
                breaks.insert(i)
                continue
            }
            // Non-advancing time can't imply a speed. Times are monotonic by
            // construction (`SimplifiedRoute`), so this is belt and braces.
            guard let clock else { continue }
            let dt = clock[i + 1] - clock[i]
            guard dt > 0 else { continue }
            if metres / dt > maxOnFootSpeed { breaks.insert(i) }
        }
        return breaks
    }

    /// Inline, not `CLLocation.distance` — this runs on every body evaluation
    /// of every route card in the feed, and two CLLocation allocations per
    /// segment × 300 segments × N people was measurable churn for identical
    /// output (the same reason `RouteArtMetrics` carries its own copy).
    private static func haversineMeters(
        _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D
    ) -> Double {
        let r = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let la = a.latitude * .pi / 180, lb = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la) * cos(lb) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// The contiguous stretches a route actually consists of, as index ranges
    /// into the original array. One range covering everything when there are
    /// no breaks, which is the overwhelmingly common case.
    ///
    /// Single points are kept as ranges rather than dropped: a caller drawing
    /// lines skips them naturally (they have no segment), and a caller
    /// measuring must still see that something was recorded there.
    static func pieces(count: Int, breaks: Set<Int>) -> [ClosedRange<Int>] {
        guard count > 0 else { return [] }
        guard !breaks.isEmpty else { return [0...(count - 1)] }
        var out: [ClosedRange<Int>] = []
        var start = 0
        for i in 0..<(count - 1) where breaks.contains(i) {
            out.append(start...i)
            start = i + 1
        }
        out.append(start...(count - 1))
        return out
    }

    /// How long a gap is allowed to take on the replay clock. Small enough
    /// to read as a jump-cut, not zero: two points sharing a timestamp make
    /// the clock's own binary search ambiguous, and the eye needs a frame to
    /// notice the rider has moved.
    static let gapReplaySeconds: Double = 1

    /// `times` with the wall clock spent inside each gap taken out, so the
    /// replay spends its seconds on the ground that was walked.
    ///
    /// Without this a mile walked either side of a two-hour pause plays as
    /// a rider standing still for all but a moment of the flight: the shared
    /// clock is the WALK's duration, and almost none of that duration was
    /// walking. It also fixes the HUD's elapsed readout, which was reporting
    /// the errand as part of the walk.
    static func collapsingGaps(times: [Double], breaks: Set<Int>) -> [Double] {
        guard !breaks.isEmpty, times.count >= 2 else { return times }
        var out: [Double] = [times[0]]
        out.reserveCapacity(times.count)
        var shift = 0.0
        for i in 1..<times.count {
            let step = times[i] - times[i - 1]
            if breaks.contains(i - 1), step > gapReplaySeconds {
                shift += step - gapReplaySeconds
            }
            out.append(times[i] - shift)
        }
        return out
    }
}
