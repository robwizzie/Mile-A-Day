import SwiftUI
import UIKit

/// The INDOOR scene (`is_indoor == true`): the workout as laps of a stadium
/// track — the runner's badge circles the lane with a comet tail while the
/// lap counter and headline count up. Distance → laps is a real mapping (a
/// 400 m lap is a quarter mile), so the scene is earned, not canned.
///
/// Styled by the AUTHOR (`RoutelessCardStyle`): Modern draws the track as
/// hairline lanes with one crisp accent lane and no mascot; Fun lays a
/// coloured running surface and an infield, with the author's own Flamey
/// standing trackside cheering. Only ever drawn for a workout HealthKit
/// called indoor — an outdoor walk with no map gets `DistanceRibbonCard`.
struct IndoorTrackCard: View {
    let stats: PostStats
    let workoutType: String?
    var splits: [WorkoutSplitBar] = []
    var avatar: RouteArtAvatar? = nil
    var style: RoutelessCardStyle = .modern
    var still: Bool = false

    /// 0 → `laps`, set once OUTSIDE `withAnimation`; every consumer (comet
    /// shape, rider effect, lap counter) is an Animatable carrying its own
    /// `.animation(_:value:)` — the ios.md `.trim` rule, same as the route
    /// draw. The lap wrap happens INSIDE `RouteRiderEffect`, where it is
    /// interpolated per frame.
    @State private var lapProgress: CGFloat = 0
    @State private var revealed = false
    @State private var hasAnimated = false
    @State private var avatarImage: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var effectiveStill: Bool { still || reduceMotion }

    private var accent: Color { ActivityCardView.color(workoutType) }
    private var distance: Double { max(0, stats.distance ?? 0) }
    /// A 400m lap is a quarter mile.
    private var laps: Double { max(0.1, distance / 0.25) }
    /// A mile's four laps take ~2.2s; capped so an ultramarathon still lands
    /// inside the card's attention span.
    private var runDuration: Double { min(3.0, 1.2 + laps * 0.25) }
    private var lapAnimation: Animation { .easeOut(duration: runDuration) }

    var body: some View {
        VStack(spacing: 0) {
            RoutelessHeaderRow(style: style, accent: accent, workoutType: workoutType,
                               pace: stats.pace, showsIndoor: true)
            trackHero
                .frame(maxWidth: .infinity, minHeight: 90, maxHeight: .infinity)
                .padding(.vertical, 6)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                RoutelessDistanceHeadline(style: style, distance: distance, size: 44,
                                          revealed: revealed, still: effectiveStill,
                                          duration: runDuration)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                RoutelessStatPair(style: style, accent: accent, stats: stats)
            }
            if splits.count >= 2 {
                PaceWaveStrip(bars: splits, accent: accent, height: 30, still: effectiveStill)
                    .padding(.top, 10)
            }
        }
        .padding(16)
        .task { await animateIn() }
        .task(id: avatar?.imageURL) {
            guard let url = avatar?.imageURL, !url.isEmpty else { return }
            avatarImage = await RouteAvatarImageLoader.loadImage(for: url)
        }
    }

    private var trackHero: some View {
        GeometryReader { geo in
            // Fun gives up a strip on the right for Flamey to stand in, past
            // the stadium's end — anywhere on the track he collides with the
            // runner's badge.
            let cheerRoom: CGFloat = style.isFun ? 52 : 0
            let rect = Self.trackRect(in: CGSize(width: geo.size.width - cheerRoom, height: geo.size.height),
                                      aspect: style.isFun ? 2.0 : 2.3)
            let points = Self.stadiumPoints(in: rect)
            let metrics = RouteArtMetrics(points: points)
            let shownLaps: CGFloat = effectiveStill ? CGFloat(laps) : lapProgress
            ZStack(alignment: .topLeading) {
                // The static track, flattened into ONE layer: it never moves,
                // and as live layers a blurred glow is a filter the compositor
                // re-runs every frame of every scroll.
                trackSurface(rect: rect, points: points)
                    .drawingGroup()

                // Start/finish line across the bottom straight.
                if let start = points.first {
                    Rectangle()
                        .fill(Color.white.opacity(style.isFun ? 0.9 : 0.7))
                        .frame(width: 2, height: style.isFun ? 22 : 14)
                        .position(start)
                }

                // The white bead sweeping the lane behind the runner.
                if !effectiveStill {
                    TrackCometShape(lapProgress: lapProgress, points: points)
                        .stroke(Color.white,
                                style: StrokeStyle(lineWidth: style.isFun ? 5 : 3,
                                                   lineCap: .round, lineJoin: .round))
                        .shadow(color: accent, radius: style.isFun ? 6 : 3)
                        .opacity(lapProgress > 0 ? 1 : 0)
                        .animation(lapAnimation, value: lapProgress)
                }

                // Lap counter in the infield.
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", laps))
                        .modifier(CountUpNumberModifier(value: Double(shownLaps), format: "%.1f"))
                        .font(.system(size: 26, weight: style.isFun ? .black : .semibold,
                                      design: style.isFun ? .rounded : .default))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .animation(effectiveStill ? nil : lapAnimation, value: lapProgress)
                    Text(laps < 1.05 && laps > 0.95 ? "LAP · 400 M" : "LAPS · 400 M")
                        .font(.system(size: 8, weight: .heavy, design: style.isFun ? .rounded : .default))
                        .tracking(1.6)
                        .foregroundColor(.white.opacity(0.5))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .position(x: rect.midX, y: rect.midY)

                if case .fun(let look, let name) = style {
                    TrackCheerleader(look: look, name: name, size: 44, still: effectiveStill)
                        .frame(width: 76)
                        // Trackside, just past the stadium's right-hand end.
                        .position(x: geo.size.width - 26, y: rect.maxY - 22)
                }

                // The runner: the author's badge, or a bright dot when no
                // identity was handed in.
                Group {
                    if let avatar {
                        // Cache fallback so a still render (ImageRenderer runs
                        // no tasks) and a freshly recycled cell both get the
                        // photo when it's already warm.
                        RouteAvatarBadge(
                            name: avatar.name,
                            image: avatarImage ?? RouteAvatarImageLoader.cachedImage(for: avatar.imageURL),
                            size: style.isFun ? 24 : 22, ring: accent)
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

    /// The track itself. Modern: three hairline lanes and the accent lane —
    /// nothing filled. Fun: a coloured running surface with white lane lines
    /// round a grass infield, the lane glowing in the activity colour.
    @ViewBuilder
    private func trackSurface(rect: CGRect, points: [CGPoint]) -> some View {
        let lane = Path(RoutePolyline.path(through: points))
        let outer = rect.insetBy(dx: -12, dy: -12)
        let inner = rect.insetBy(dx: 12, dy: 12)
        if style.isFun {
            ZStack {
                // Running surface: the band between the outer and inner edges.
                Self.ring(outer: outer, inner: inner)
                    .fill(accent.opacity(0.24), style: FillStyle(eoFill: true))
                Self.stadiumOutline(in: inner)
                    .fill(Color(red: 0.16, green: 0.42, blue: 0.24).opacity(0.30))
                ForEach([-12.0, -4.0, 4.0, 12.0], id: \.self) { inset in
                    Self.stadiumOutline(in: rect.insetBy(dx: inset, dy: inset))
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                }
                lane.stroke(accent.opacity(0.35),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .blur(radius: 3)
                lane.stroke(accent,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        } else {
            ZStack {
                ForEach([-12.0, -4.0, 4.0, 12.0], id: \.self) { inset in
                    Self.stadiumOutline(in: rect.insetBy(dx: inset, dy: inset))
                        .stroke(Color.white.opacity(inset == -12 || inset == 12 ? 0.14 : 0.07),
                                lineWidth: 1)
                }
                lane.stroke(accent,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    static func ring(outer: CGRect, inner: CGRect) -> Path {
        var p = stadiumOutline(in: outer)
        p.addPath(stadiumOutline(in: inner))
        return p
    }

    private func animateIn() async {
        guard !effectiveStill, !hasAnimated else { return }
        hasAnimated = true
        try? await Task.sleep(for: .milliseconds(300))
        revealed = true
        try? await Task.sleep(for: .milliseconds(100))
        lapProgress = CGFloat(laps)
    }

    /// The stadium footprint, centered — ~2.2:1, a real track's TV framing.
    static func trackRect(in size: CGSize, aspect: CGFloat = 2.4) -> CGRect {
        var w = max(size.width - 28, 1)
        var h = w / aspect
        let maxH = max(size.height - 28, 1)
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

/// The author's Flamey, cheering — trackside on the indoor scene, at the
/// finish of the ribbon on the outdoor one. Fun authors only. The
/// figure renders ONCE (fixed flicker, legacy phase-less form per the
/// dashboard rules) and everything that moves is a compositor transform or
/// opacity on that cached layer: an excited hop + waggle, and a "GO!" bubble
/// pulsing above. No TimelineView, no per-frame redraw (the retired treadmill
/// face's mistake).
struct TrackCheerleader: View {
    let look: FlameyLook
    var name: String? = nil
    var size: CGFloat = 38
    let still: Bool
    @State private var hop = false
    @State private var cheer = false

    var body: some View {
        // Room for a hat between him and his bubble (a crown sat on it).
        VStack(spacing: 2 + FlameyArt.crest(of: look) * size * 0.8) {
            // His name when the author gave him one — "GO SPARKY!" —
            // else (or when it wouldn't fit trackside) the plain cheer.
            Text(name.flatMap { $0.count <= 8 ? "GO \($0.uppercased())!" : nil } ?? "GO!")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.16)))
                .opacity((still || cheer) ? 1 : 0.15)
                .offset(y: cheer ? -1 : 2)
            // The AUTHOR's Flamey (resolved by IndoorWorkoutCard), in his
            // colour and outfit, both arms up cheering. Compact: it's a 38pt
            // figure. FlameyDressedFigure scales a compact look so his legs
            // keep the trackside spot the height it always was.
            FlameyDressedFigure(look: look, health: .healthy, size: size,
                                scale: FlameHealth.healthy.bodyScale, arms: .cheer)
            .rotationEffect(.degrees(still ? 0 : (hop ? 4 : -4)))
            .offset(y: hop ? -3 : 0)
        }
        .onAppear {
            guard !still, !UIAccessibility.isReduceMotionEnabled else { return }
            // Off the appear commit (see FlameBuddyView): a repeatForever
            // started inside onAppear attaches to unrelated layout changes.
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                    hop = true
                }
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    cheer = true
                }
            }
        }
        // Off screen, stop the loops (back to rest, unanimated) so a cell kept
        // alive out of view isn't animating for nobody; onAppear restarts them.
        .onDisappear {
            var rest = Transaction()
            rest.disablesAnimations = true
            withTransaction(rest) {
                hop = false
                cheer = false
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
