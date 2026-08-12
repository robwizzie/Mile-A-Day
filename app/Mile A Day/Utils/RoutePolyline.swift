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
    static func path(through points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        return path
    }
}
