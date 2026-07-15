import CoreGraphics

/// Shared route-line smoothing so the live feed overlay (SwiftUI Path) and the
/// baked auto-post image (CGContext) draw the SAME curve.
///
/// A centripetal Catmull-Rom spline (α = 0.5) through the GPS points: the line
/// passes through every point — no corner-cutting, so distance/shape stay
/// honest — but curves between them instead of a hard polyline. Centripetal
/// parameterization is deliberate: uniform Catmull-Rom overshoots into little
/// self-intersecting loops at hairpins (the tip of an out-and-back), exactly
/// where a route bends hardest.
enum RouteSmoothing {
    static func smoothedPath(through points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count >= 3 else {
            for p in points.dropFirst() { path.addLine(to: p) }
            return path
        }

        for i in 0..<(points.count - 1) {
            let p0 = points[i == 0 ? 0 : i - 1]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[i + 2 < points.count ? i + 2 : points.count - 1]

            // Knot spacing = distance^0.5 (centripetal); guard coincident
            // points so a zero spacing can't blow up the division.
            let d1 = max(sqrt(sqDist(p0, p1)), 1e-4)
            let d2 = max(sqrt(sqDist(p1, p2)), 1e-4)
            let d3 = max(sqrt(sqDist(p2, p3)), 1e-4)

            // Segment tangents (Barry-Goldman), scaled to this segment.
            var m1 = CGPoint(
                x: (p2.x - p1.x) / d2 - (p2.x - p0.x) / (d1 + d2) + (p1.x - p0.x) / d1,
                y: (p2.y - p1.y) / d2 - (p2.y - p0.y) / (d1 + d2) + (p1.y - p0.y) / d1
            )
            var m2 = CGPoint(
                x: (p2.x - p1.x) / d2 - (p3.x - p1.x) / (d2 + d3) + (p3.x - p2.x) / d3,
                y: (p2.y - p1.y) / d2 - (p3.y - p1.y) / (d2 + d3) + (p3.y - p2.y) / d3
            )
            m1.x *= d2; m1.y *= d2
            m2.x *= d2; m2.y *= d2

            let c1 = CGPoint(x: p1.x + m1.x / 3, y: p1.y + m1.y / 3)
            let c2 = CGPoint(x: p2.x - m2.x / 3, y: p2.y - m2.y / 3)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    private static func sqDist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
    }
}
