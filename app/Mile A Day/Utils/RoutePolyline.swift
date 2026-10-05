import CoreGraphics

/// Shared route-line path so the live feed overlay (SwiftUI Path) and the
/// baked auto-post image (CGContext) draw the SAME line.
///
/// A straight polyline through the GPS points — the line Apple Fitness draws,
/// which is the reference for "the route I actually took". This was a
/// Catmull-Rom spline once, and that's what made routes read as rounded blobs:
/// every stored route is corner-preserving simplified (Douglas-Peucker at
/// finish, the ≤300-point sync budget), so the surviving points are mostly
/// corners sitting far apart, and a spline through sparse corners INVENTS
/// curvature — each street corner rendered as a wide arc the walker never
/// took. Round joins/caps in the stroke style soften the vertices without
/// ever moving the line off the streets; don't reintroduce a curve here.
enum RoutePolyline {
    /// - Parameter breakingAfter: indices after which the points are NOT
    ///   joined by walked ground (`RouteGaps`) — the path lifts the pen and
    ///   starts a new subpath there instead of drawing a line nobody walked.
    ///   `Path.trim` measures the TOTAL length of all subpaths, and a gap
    ///   contributes none, so the draw animation and the bead cross it as a
    ///   jump-cut with no other change. Empty for every ordinary route.
    static func path(through points: [CGPoint], breakingAfter breaks: Set<Int> = []) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for (index, p) in points.enumerated().dropFirst() {
            if breaks.contains(index - 1) {
                path.move(to: p)
            } else {
                path.addLine(to: p)
            }
        }
        return path
    }
}
