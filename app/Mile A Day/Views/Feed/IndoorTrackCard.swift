import SwiftUI
import UIKit

/// The routeless face: the workout as laps of a glowing stadium track — the
/// runner's badge circles the lane with a comet tail while the lap counter
/// and headline count up. Distance → laps is a real mapping (1 mile ≈ 4 laps
/// of a 400m track), so the scene is earned, not canned.
///
/// A Fun AUTHOR's card (`funLook` set) is the same scene warmed up: their
/// Flamey takes the infield beside the lap counter, a "GO SPARKY!" cheer
/// rides the top straight, and embers rise off the canvas. A Modern author's
/// card is the clean track.
///
/// A walk HealthKit flagged OUTDOOR (`isIndoor == false`) that reached the
/// card without its map draws a decorative trail over hills instead — laps
/// of a stadium misdescribed every outdoor walk whose map wasn't shared.
struct IndoorTrackCard: View {
    let stats: PostStats
    let workoutType: String?
    var splits: [WorkoutSplitBar] = []
    var avatar: RouteArtAvatar? = nil
    /// nil = unknown — the scaffold's chip doesn't draw then.
    var isIndoor: Bool? = nil
    /// The AUTHOR's Flamey when they're on Fun — the Fun scene. nil = the
    /// Modern track. Motion is transform/opacity only (the feed-cell rule).
    var funLook: FlameyLook? = nil
    /// The author's name for him ("Sparky"), nil = unnamed/"Flamey".
    var funName: String? = nil
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
                           isIndoor: isIndoor, still: still, revealDuration: runDuration,
                           fun: funLook != nil) {
            Group {
                // OUTDOOR only when HealthKit said so: a walk outside whose
                // map didn't come along (maps off, a bridged app with no
                // GPS, a multi-leg day) is not laps of a track. nil and
                // indoor keep the stadium.
                if isIndoor == false {
                    outdoorHero
                } else {
                    trackHero
                }
            }
            // Compressible: on the smallest screens the 4:5 card hasn't
            // 130pt to spare once the pace wave row is present — both
            // scenes derive everything from their geometry, so they shrink
            // instead of overflowing the card.
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

                if let funLook {
                    // Fun: Flamey owns the infield, the laps beside him, and
                    // his cheer rides the top straight (the runner passes
                    // OVER it — it's drawn first).
                    HStack(spacing: 8) {
                        TrackFlamey(look: funLook, still: effectiveStill,
                                    size: min(56, rect.height * 0.62))
                        lapCounter(shownLaps, numberSize: 22)
                    }
                    .position(x: rect.midX, y: rect.midY + 2)
                    TrackCheerBubble(text: FeedCardFlamey.cheer(name: funName), still: effectiveStill)
                        .position(x: rect.midX, y: rect.minY - 3)
                } else {
                    // Lap counter in the infield.
                    lapCounter(shownLaps, numberSize: 26)
                        .position(x: rect.midX, y: rect.midY)
                }

                runner
                    .modifier(RouteRiderEffect(progress: shownLaps, metrics: metrics, wraps: true))
                    .animation(effectiveStill ? nil : lapAnimation, value: lapProgress)
            }
        }
    }

    /// The runner: their badge, or a bright dot when no identity was handed in.
    @ViewBuilder
    private var runner: some View {
        if let avatar {
            // Cache fallback so a still render (ImageRenderer runs no tasks)
            // and a freshly recycled cell both get the photo when it's
            // already warm.
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

    /// The OUTDOOR face for a walk whose map isn't on the card: a winding
    /// trail over rolling hills that draws on while the runner rides it to a
    /// finish flag. The trail is DECORATIVE — the same shape for every walk,
    /// never a hint of where anyone went (the card can be mapless because
    /// its owner keeps maps private). A Fun author's Flamey waits at the
    /// flag, cheering.
    private var outdoorHero: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size).insetBy(dx: 16, dy: 14)
            let points = Self.trailPoints(in: rect)
            let metrics = RouteArtMetrics(points: points)
            let trail = Path(RoutePolyline.path(through: points))
            // 0 → 1 over the same clock the headline counts on; the Shape's
            // trim and the rider's effect interpolate between the two
            // endpoints this expression is evaluated at.
            let drawn: CGFloat = effectiveStill ? 1 : min(1, lapProgress / CGFloat(laps))
            let finish = points.last ?? CGPoint(x: rect.maxX, y: rect.minY)
            ZStack(alignment: .topLeading) {
                Self.hills(in: geo.size, height: 0.42, phase: 0)
                    .fill(Color.white.opacity(0.05))
                Self.hills(in: geo.size, height: 0.26, phase: 1.7)
                    .fill(Color.white.opacity(0.07))

                // The whole trail, faint and dotted — where the walk is headed.
                trail.stroke(Color.white.opacity(0.16),
                             style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 7]))

                // The walked part — same glow/casing/line recipe as a route.
                Group {
                    trail.trim(from: 0, to: drawn)
                        .stroke(accent.opacity(0.3),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                        .blur(radius: 3)
                    trail.trim(from: 0, to: drawn)
                        .stroke(Color.black.opacity(0.45),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    trail.trim(from: 0, to: drawn)
                        .stroke(accent,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
                .animation(effectiveStill ? nil : lapAnimation, value: lapProgress)

                if let start = points.first {
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 7, height: 7)
                        .position(start)
                }

                Image(systemName: "flag.checkered")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .position(x: finish.x + 6, y: finish.y - 12)
                    .accessibilityHidden(true)

                if let funLook {
                    // Waiting just under the flag, cheering the walker home.
                    TrackFlamey(look: funLook, still: effectiveStill,
                                size: min(46, rect.height * 0.5))
                        .position(x: finish.x - 34, y: min(rect.maxY - 18, finish.y + 34))
                    TrackCheerBubble(text: FeedCardFlamey.cheer(name: funName), still: effectiveStill)
                        .position(x: rect.midX, y: rect.minY + 2)
                }

                runner
                    .modifier(RouteRiderEffect(progress: drawn, metrics: metrics))
                    .animation(effectiveStill ? nil : lapAnimation, value: lapProgress)
            }
        }
    }

    /// The decorative trail: a gentle S rising from bottom-left to the top
    /// right, sampled densely so the rider's arc length is smooth.
    static func trailPoints(in rect: CGRect, samples: Int = 96) -> [CGPoint] {
        guard rect.width > 0, rect.height > 0 else { return [] }
        let amplitude = rect.height * 0.2
        return (0...samples).map { i -> CGPoint in
            let t = CGFloat(i) / CGFloat(samples)
            let x = rect.minX + rect.width * t
            let rise = rect.maxY - 6 - (rect.height - 20) * t
            let y = rise + amplitude * sin(t * .pi * 2.4) * (1 - t * 0.5)
            return CGPoint(x: x, y: min(rect.maxY - 4, max(rect.minY + 10, y)))
        }
    }

    /// A band of rolling hills along the bottom of the scene.
    static func hills(in size: CGSize, height: CGFloat, phase: CGFloat) -> Path {
        Path { p in
            let base = size.height
            let top = size.height * (1 - height)
            p.move(to: CGPoint(x: 0, y: base))
            let steps = 48
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let wave = (sin(t * .pi * 3 + phase) + 1) / 2
                p.addLine(to: CGPoint(x: size.width * t,
                                      y: top + (base - top) * 0.45 * wave))
            }
            p.addLine(to: CGPoint(x: size.width, y: base))
            p.closeSubpath()
        }
    }

    private func lapCounter(_ shownLaps: CGFloat, numberSize: CGFloat) -> some View {
        VStack(spacing: 1) {
            Text(String(format: "%.1f", laps))
                .modifier(CountUpNumberModifier(value: Double(shownLaps), format: "%.1f"))
                .font(.system(size: numberSize, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .animation(effectiveStill ? nil : lapAnimation, value: lapProgress)
            Text("LAPS")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundColor(.white.opacity(0.5))
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

/// The Fun author's Flamey in the infield, both arms up, hopping the laps
/// on. The figure renders ONCE and everything that moves is a compositor
/// transform on that layer — no TimelineView, no per-frame redraw (the
/// retired treadmill face's mistake). The hop starts on the next turn, never
/// inside `onAppear`'s own commit (ios.md).
private struct TrackFlamey: View {
    let look: FlameyLook
    let still: Bool
    var size: CGFloat = 52
    @State private var hop = false

    var body: some View {
        FlameyDressedFigure(look: look, health: .healthy, size: size,
                            scale: FlameHealth.healthy.bodyScale, arms: .cheer)
            .rotationEffect(.degrees(still ? 0 : (hop ? 5 : -5)), anchor: .bottom)
            .offset(y: still ? 0 : (hop ? -4 : 0))
            .onAppear {
                guard !still else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.32).repeatForever(autoreverses: true)) {
                        hop = true
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// "GO SPARKY!" on the top straight — a warm capsule that pulses by scale
/// and opacity only.
private struct TrackCheerBubble: View {
    let text: String
    let still: Bool
    @State private var pulse = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(0.6)
            .foregroundColor(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(LinearGradient(
                    colors: [MADTheme.Colors.warning, MADTheme.Colors.madRed],
                    startPoint: .leading, endPoint: .trailing))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
            .scaleEffect(still ? 1 : (pulse ? 1.06 : 0.96))
            .onAppear {
                guard !still else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
