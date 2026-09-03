import SwiftUI
import CoreLocation

// Pure geometry for the Route Art canvas — no views. `RouteArtView` (and the
// indoor track card) build on these.

/// Lat/lng → canvas points for the branded route canvas.
///
/// Unlike `RouteMapSnapshot.point(for:)` this is OUR projection, not MapKit's:
/// there is no basemap under the line, so nothing external dictates where a
/// coordinate "really" landed. The route is aspect-FIT into the canvas with
/// padding — fit, never fill, so the whole trace is always inside the frame
/// and the ios.md aspect-fill crop trap can't apply. Equirectangular with the
/// longitude axis scaled by cos(midLatitude); at route scale (a few km) the
/// error against Mercator is sub-pixel.
struct RouteArtProjection {
    private let midLat: Double
    private let midLon: Double
    private let cosMid: Double
    private let scale: CGFloat
    private let center: CGPoint

    /// - Parameter coordinates: EVERY trace that will be drawn (author +
    ///   companions) — same frame-the-whole-crew rule as
    ///   `WorkoutRouteMapView.region`.
    init(coordinates: [CLLocationCoordinate2D], size: CGSize, padding: CGFloat = 28) {
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        guard let first = coordinates.first else {
            midLat = 0; midLon = 0; cosMid = 1; scale = 1
            return
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        midLat = (minLat + maxLat) / 2
        midLon = (minLon + maxLon) / 2
        cosMid = max(0.01, cos(midLat * .pi / 180))
        // Both spans are in latitude-equivalent degrees (x pre-multiplied by
        // cosMid), floored at ~55m — the same 0.0005° minimum the map region
        // uses — so a GPS blip doesn't zoom into noise.
        let spanX = max((maxLon - minLon) * cosMid, 0.0005)
        let spanY = max(maxLat - minLat, 0.0005)
        let fitW = max(size.width - 2 * padding, 1)
        let fitH = max(size.height - 2 * padding, 1)
        scale = min(fitW / CGFloat(spanX), fitH / CGFloat(spanY))
    }

    func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
        CGPoint(
            x: center.x + CGFloat((coordinate.longitude - midLon) * cosMid) * scale,
            y: center.y - CGFloat(coordinate.latitude - midLat) * scale
        )
    }
}

/// One mile boundary along the route, located both on the canvas and as a
/// fraction of the PROJECTED path length — the same measure `Path.trim`
/// animates — so a tick can reveal exactly as the line crosses it.
struct RouteMileMark: Identifiable {
    let mile: Int
    let fraction: CGFloat
    let point: CGPoint
    var id: Int { mile }
}

/// Everything the riders and mile ticks need, computed ONCE per layout (never
/// per frame): the projected polyline, cumulative projected arc length per
/// vertex, and cumulative geographic meters per vertex.
///
/// Projected arc length is deliberately the position metric: it is what
/// `Path.trim` measures on the identical polyline, so a rider positioned by
/// it can never drift off the drawing tip.
struct RouteArtMetrics {
    let points: [CGPoint]
    private let cumulativeProjected: [CGFloat]
    private let cumulativeMeters: [Double]
    let totalProjected: CGFloat
    let totalMeters: Double

    /// A line worth drawing at all — two distinct points with some length.
    var isDrawable: Bool { points.count >= 2 && totalProjected > 0.5 }

    var totalMiles: Double { totalMeters / 1609.344 }

    init(coordinates: [CLLocationCoordinate2D], projection: RouteArtProjection) {
        self.init(coordinates: coordinates, project: projection.point(for:))
    }

    /// Projector-agnostic form: the art canvas passes its own aspect-fit
    /// projection, the ghost-map underlay passes the SNAPSHOT's projection
    /// (streets behind the line ⇒ the line must land on those streets — the
    /// ios.md snapshot-projection rule).
    init(coordinates: [CLLocationCoordinate2D], project: (CLLocationCoordinate2D) -> CGPoint) {
        let projected = coordinates.map(project)
        var cumProj: [CGFloat] = []
        var cumMeters: [Double] = []
        cumProj.reserveCapacity(projected.count)
        cumMeters.reserveCapacity(projected.count)
        var proj: CGFloat = 0
        var meters: Double = 0
        for (i, p) in projected.enumerated() {
            if i > 0 {
                let prev = projected[i - 1]
                proj += hypot(p.x - prev.x, p.y - prev.y)
                // Inline haversine, not CLLocation.distance: this init runs
                // on every body evaluation of every route card in the feed,
                // and two CLLocation allocations per segment × 300 segments ×
                // N people was measurable churn for identical output.
                meters += Self.haversineMeters(coordinates[i - 1], coordinates[i])
            }
            cumProj.append(proj)
            cumMeters.append(meters)
        }
        points = projected
        cumulativeProjected = cumProj
        cumulativeMeters = cumMeters
        totalProjected = proj
        totalMeters = meters
    }

    /// Synthetic-polyline variant (no geography) — the indoor track card's
    /// stadium is a plain point loop, but its rider runs through the same
    /// arc-length machinery as a real route's.
    init(points canvasPoints: [CGPoint]) {
        var cumProj: [CGFloat] = []
        cumProj.reserveCapacity(canvasPoints.count)
        var proj: CGFloat = 0
        for (i, p) in canvasPoints.enumerated() {
            if i > 0 {
                let prev = canvasPoints[i - 1]
                proj += hypot(p.x - prev.x, p.y - prev.y)
            }
            cumProj.append(proj)
        }
        points = canvasPoints
        cumulativeProjected = cumProj
        cumulativeMeters = Array(repeating: 0, count: canvasPoints.count)
        totalProjected = proj
        totalMeters = 0
    }

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

    /// Point at `fraction` (0…1) of the projected path length. Called per
    /// FRAME while a rider animates, hence the binary search.
    func point(atFraction fraction: CGFloat) -> CGPoint {
        guard let first = points.first else { return .zero }
        guard points.count > 1, totalProjected > 0 else { return first }
        let target = min(max(fraction, 0), 1) * totalProjected
        // First index whose cumulative length reaches the target.
        var lo = 0, hi = points.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulativeProjected[mid] < target { lo = mid + 1 } else { hi = mid }
        }
        let i = max(lo, 1)
        let segment = cumulativeProjected[i] - cumulativeProjected[i - 1]
        let t = segment > 0 ? (target - cumulativeProjected[i - 1]) / segment : 0
        let a = points[i - 1], b = points[i]
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// Whole-mile boundaries along the route (geographic miles), each carrying
    /// the projected-length fraction the trim crosses it at.
    func mileMarks(limit: Int = 30) -> [RouteMileMark] {
        guard points.count > 1, totalMeters > 0, totalProjected > 0 else { return [] }
        let wholeMiles = Int(totalMeters / 1609.344)
        guard wholeMiles >= 1 else { return [] }
        var marks: [RouteMileMark] = []
        var index = 1
        for mile in 1...min(wholeMiles, limit) {
            let targetMeters = Double(mile) * 1609.344
            while index < points.count - 1, cumulativeMeters[index] < targetMeters {
                index += 1
            }
            let segMeters = cumulativeMeters[index] - cumulativeMeters[index - 1]
            let t = segMeters > 0
                ? CGFloat((targetMeters - cumulativeMeters[index - 1]) / segMeters) : 0
            let a = points[index - 1], b = points[index]
            let point = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            let projAt = cumulativeProjected[index - 1]
                + (cumulativeProjected[index] - cumulativeProjected[index - 1]) * t
            marks.append(RouteMileMark(mile: mile, fraction: projAt / totalProjected, point: point))
        }
        return marks
    }
}

/// Carries a view along the route as the line draws.
///
/// The ios.md `.trim` rule is why this exists: a `Shape`'s trim animates
/// INSIDE the shape, so the parent body sees the driving `@State` only at 0
/// and 1 — any expression on it can't move a view mid-draw. A `GeometryEffect`
/// is itself `Animatable`, so attaching this with the SAME
/// `.animation(RouteDrawTiming.lineAnimation(index:), value:)` as the line's
/// trims interpolates `progress` frame-by-frame on the identical curve and
/// delay: the rider is welded to the drawing tip by construction.
struct RouteRiderEffect: GeometryEffect {
    var progress: CGFloat
    let metrics: RouteArtMetrics
    /// The indoor track laps the same closed shape N times: progress runs
    /// 0→laps and wraps INSIDE the effect, where it IS interpolated per frame
    /// (an outside `truncatingRemainder` on the state would only ever see the
    /// endpoints).
    var wraps: Bool = false

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let fraction: CGFloat
        if wraps {
            let wrapped = progress.truncatingRemainder(dividingBy: 1)
            // Exactly N.0 laps means "at the finish", not "back at the start".
            fraction = (wrapped == 0 && progress > 0) ? 1 : wrapped
        } else {
            fraction = progress
        }
        let p = metrics.point(atFraction: fraction)
        return ProjectionTransform(CGAffineTransform(
            translationX: p.x - size.width / 2,
            y: p.y - size.height / 2
        ))
    }
}

/// Pops a mile tick the moment the drawing line crosses it — same Animatable
/// mechanism as `RouteRiderEffect`, driven by the same animation, keyed on the
/// tick's own projected fraction. A 0.02 fade band so it pops rather than
/// flickers on the exact frame.
struct TickRevealModifier: ViewModifier, Animatable {
    var progress: CGFloat
    let threshold: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let reveal = min(max((progress - threshold) / 0.02, 0), 1)
        content
            .opacity(reveal)
            .scaleEffect(0.4 + 0.6 * reveal)
    }
}

// MARK: - Lanes (screen space)

/// Side-by-side lanes for crew lines on the CANVAS, in points.
///
/// The flyover lanes companions by metres (`FlyoverTrack.laneOffset`), which
/// works at cruise altitude and is invisible on a card: a whole mile spans
/// ~250pt there, so 3m is half a point and two people who walked the same
/// loop draw as ONE line — whoever was painted last. Offsetting the projected
/// polyline instead keeps every walker visible at any zoom, and the offset is
/// tiny enough (≈5pt) that genuinely different routes look untouched. Each
/// point moves along the local normal (from its neighbours), so the lane
/// follows every bend. The author stays on lane 0; companions alternate
/// +1, −1, +2, −2 so a pair straddles the author's line.
enum RouteLaneOffset {
    static func lane(index: Int, unit: CGFloat) -> CGFloat {
        let step = CGFloat(index / 2 + 1)
        return (index % 2 == 0 ? 1 : -1) * step * unit
    }

    static func offset(_ points: [CGPoint], by distance: CGFloat) -> [CGPoint] {
        guard abs(distance) > 0.01, points.count >= 2 else { return points }
        var out: [CGPoint] = []
        out.reserveCapacity(points.count)
        for i in points.indices {
            let prev = points[max(i - 1, 0)]
            let next = points[min(i + 1, points.count - 1)]
            var dx = next.x - prev.x
            var dy = next.y - prev.y
            let length = hypot(dx, dy)
            guard length > 0.001 else {
                out.append(points[i])
                continue
            }
            dx /= length
            dy /= length
            out.append(CGPoint(x: points[i].x - dy * distance, y: points[i].y + dx * distance))
        }
        return out
    }
}
