import SwiftUI
import UIKit

/// The Modern indoor face: the workout as laps of a glowing stadium track —
/// the runner's badge circles the lane with a comet tail while the lap
/// counter and headline count up. Distance → laps is a real mapping
/// (1 mile ≈ 4 laps of a 400m track), so the scene is earned, not canned.
struct IndoorTrackCard: View {
    let stats: PostStats
    let workoutType: String?
    var splits: [WorkoutSplitBar] = []
    var avatar: RouteArtAvatar? = nil
    /// nil = unknown — the scaffold's chip doesn't draw then.
    var isIndoor: Bool? = nil
    /// Fun-dashboard viewers get Flamey standing trackside, cheering the
    /// laps on (transform/opacity motion only — the feed-cell perf rule).
    var cheerleader: Bool = false
    var still: Bool = false

    /// 0 → `laps`, set once OUTSIDE `withAnimation`; every consumer (comet
    /// shape, rider effect, lap counter) is an Animatable carrying its own
    /// `.animation(_:value:)` — the ios.md `.trim` rule, same as the route
    /// draw. The lap wrap happens INSIDE `RouteRiderEffect`, where it is
    /// interpolated per frame.
    @State private var lapProgress: CGFloat = 0
    @State private var hasAnimated = false
    @State private var avatarImage: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var effectiveStill: Bool { still || reduceMotion }

    private var accent: Color { ActivityCardView.color(workoutType) }
    /// A 400m lap is a quarter mile.
    private var laps: Double { max(0.1, (stats.distance ?? 0) / 0.25) }
    /// A mile's four laps take ~2.2s; capped so an ultramarathon still lands
    /// inside the card's attention span.
    private var runDuration: Double { min(3.0, 1.2 + laps * 0.25) }
    private var lapAnimation: Animation { .easeOut(duration: runDuration) }

    var body: some View {
        IndoorCardScaffold(stats: stats, workoutType: workoutType, splits: splits,
                           isIndoor: isIndoor, still: still, revealDuration: runDuration) {
            trackHero
                // Compressible: on the smallest screens the 4:5 card hasn't
                // 130pt to spare once the pace wave row is present — the
                // stadium scene derives everything from its geometry, so it
                // shrinks instead of overflowing the card.
                .frame(minHeight: 100, idealHeight: 130, maxHeight: 130)
        }
        .task { await animateIn() }
        .task(id: avatar?.imageURL) {
            guard let url = avatar?.imageURL, !url.isEmpty else { return }
            avatarImage = await RouteAvatarImageLoader.loadImage(for: url)
        }
    }

    private var trackHero: some View {
        GeometryReader { geo in
            let rect = Self.trackRect(in: geo.size)
            let points = Self.stadiumPoints(in: rect)
            let metrics = RouteArtMetrics(points: points)
            let lane = Path(RoutePolyline.path(through: points))
            let shownLaps: CGFloat = effectiveStill ? CGFloat(laps) : lapProgress
            ZStack(alignment: .topLeading) {
                // Lane hints either side of the running line, so it reads as a
                // track and not an abstract loop.
                Self.stadiumOutline(in: rect.insetBy(dx: -9, dy: -9))
                    .stroke(Color.white.opacity(0.05), lineWidth: 2)
                Self.stadiumOutline(in: rect.insetBy(dx: 9, dy: 9))
                    .stroke(Color.white.opacity(0.05), lineWidth: 2)

                // The active lane — same glow/casing/line recipe as a route.
                lane.stroke(accent.opacity(0.3),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .blur(radius: 3)
                lane.stroke(Color.black.opacity(0.45),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                lane.stroke(accent,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                // Start/finish line at the bottom straight.
                if let start = points.first {
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 2.5, height: 10)
                        .position(start)
                }

                // The white bead sweeping the lane behind the runner.
                if !effectiveStill {
                    TrackCometShape(lapProgress: lapProgress, points: points)
                        .stroke(Color.white,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .shadow(color: accent, radius: 6)
                        .opacity(lapProgress > 0 ? 1 : 0)
                        .animation(lapAnimation, value: lapProgress)
                }

                // Lap counter in the infield.
                VStack(spacing: 1) {
                    Text(String(format: "%.1f", laps))
                        .modifier(CountUpNumberModifier(value: Double(shownLaps), format: "%.1f"))
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .animation(effectiveStill ? nil : lapAnimation, value: lapProgress)
                    Text("LAPS")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.5))
                }
                .position(x: rect.midX, y: rect.midY)

                if cheerleader {
                    TrackCheerleader(still: still)
                        // Trackside, tucked into the space the stadium's
                        // rounded end leaves at the bottom-leading corner.
                        .position(x: max(rect.minX + 2, 20), y: rect.maxY - 18)
                }

                // The runner: their badge, or a bright dot when no identity
                // was handed in.
                Group {
                    if let avatar {
                        // Cache fallback so a still render (ImageRenderer runs
                        // no tasks) and a freshly recycled cell both get the
                        // photo when it's already warm.
                        RouteAvatarBadge(
                            name: avatar.name,
                            image: avatarImage ?? RouteAvatarImageLoader.cachedImage(for: avatar.imageURL),
                            size: 22, ring: accent)
                    } else {
                        Circle()
                            .fill(.white)
                            .frame(width: 10, height: 10)
                            .shadow(color: accent, radius: 5)
                    }
                }
                .modifier(RouteRiderEffect(progress: shownLaps, metrics: metrics, wraps: true))
                .animation(effectiveStill ? nil : lapAnimation, value: lapProgress)
            }
        }
    }

    private func animateIn() async {
        guard !effectiveStill, !hasAnimated else { return }
        hasAnimated = true
        try? await Task.sleep(for: .milliseconds(400))
        lapProgress = CGFloat(laps)
    }

    /// The stadium footprint, centered, ~2.4:1 like a real track's TV framing.
    static func trackRect(in size: CGSize) -> CGRect {
        let aspect: CGFloat = 2.4
        var w = max(size.width - 24, 1)
        var h = w / aspect
        let maxH = max(size.height - 24, 1)
        if h > maxH {
            h = maxH
            w = h * aspect
        }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    static func stadiumOutline(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.height / 2)
    }

    /// The stadium as a closed polyline, sampled by arc length from the
    /// start/finish line at bottom-center running toward the right — ONE
    /// parameterization shared by the lane, the comet's trim window and the
    /// rider's arc-length metrics, so they can never disagree (the same trick
    /// `RouteOverlay` uses for its bead).
    static func stadiumPoints(in rect: CGRect, samples: Int = 128) -> [CGPoint] {
        guard rect.width > 0, rect.height > 0 else { return [] }
        let r = rect.height / 2
        let straight = max(0, rect.width - rect.height)
        let arc = CGFloat.pi * r
        let total = 2 * straight + 2 * arc
        let leftCx = rect.minX + r
        let rightCx = rect.maxX - r
        let midY = rect.midY

        func point(at distance: CGFloat) -> CGPoint {
            var d = distance.truncatingRemainder(dividingBy: total)
            if d < 0 { d += total }
            // 1) bottom straight, center → right
            if d < straight / 2 {
                return CGPoint(x: rect.midX + d, y: rect.maxY)
            }
            d -= straight / 2
            // 2) right arc, bottom → top
            if d < arc {
                let theta = CGFloat.pi / 2 - (d / arc) * .pi
                return CGPoint(x: rightCx + r * cos(theta), y: midY + r * sin(theta))
            }
            d -= arc
            // 3) top straight, right → left
            if d < straight {
                return CGPoint(x: rightCx - d, y: rect.minY)
            }
            d -= straight
            // 4) left arc, top → bottom
            if d < arc {
                let theta = -CGFloat.pi / 2 - (d / arc) * .pi
                return CGPoint(x: leftCx + r * cos(theta), y: midY + r * sin(theta))
            }
            d -= arc
            // 5) bottom straight, left → center
            return CGPoint(x: leftCx + d, y: rect.maxY)
        }

        var out: [CGPoint] = []
        out.reserveCapacity(samples + 1)
        for i in 0...samples {
            out.append(point(at: total * CGFloat(i) / CGFloat(samples)))
        }
        return out
    }
}

/// Flamey, trackside — the Fun dashboard's mascot cheering the laps on. The
/// figure renders ONCE (fixed flicker, legacy phase-less form per the
/// dashboard rules) and everything that moves is a compositor transform or
/// opacity on that cached layer: an excited hop + waggle, and a "GO!" bubble
/// pulsing above. No TimelineView, no per-frame redraw (the retired treadmill
/// face's mistake).
private struct TrackCheerleader: View {
    let still: Bool
    @State private var hop = false
    @State private var cheer = false

    var body: some View {
        VStack(spacing: 2) {
            Text("GO!")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.16)))
                .opacity((still || cheer) ? 1 : 0.15)
                .offset(y: cheer ? -1 : 2)
            FlameBuddyFigure(
                health: .healthy,
                flickerPhase: 0.35,
                blink: false,
                size: 38,
                showsFace: true,
                grounded: true
            )
            .rotationEffect(.degrees(hop ? 4 : -4))
            .offset(y: hop ? -3 : 0)
        }
        .onAppear {
            guard !still, !UIAccessibility.isReduceMotionEnabled else { return }
            withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                hop = true
            }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                cheer = true
            }
        }
        .allowsHitTesting(false)
    }
}

/// The comet's sliding window around the track. `.trim(from:to:)` clamps, so
/// a window crossing the start/finish line has to be built as two pieces —
/// which means the window must be computed INSIDE an Animatable `path(in:)`,
/// where `lapProgress` is interpolated per frame.
struct TrackCometShape: Shape {
    var lapProgress: CGFloat
    let points: [CGPoint]
    var tail: CGFloat = 0.1

    var animatableData: CGFloat {
        get { lapProgress }
        set { lapProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard points.count >= 2, lapProgress > 0 else { return Path() }
        let base = Path(RoutePolyline.path(through: points))
        var head = lapProgress.truncatingRemainder(dividingBy: 1)
        if head == 0 { head = 1 }
        // The tail never reaches back before the actual start.
        let tailLength = min(tail, lapProgress)
        let tailPos = head - tailLength
        if tailPos >= 0 {
            return base.trimmedPath(from: tailPos, to: head)
        }
        var p = base.trimmedPath(from: 0, to: head)
        p.addPath(base.trimmedPath(from: 1 + tailPos, to: 1))
        return p
    }
}
