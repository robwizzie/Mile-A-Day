import SwiftUI

/// The flame buddy while a streak is paused for injury: frowning, head wrapped
/// 🤕-style, on crutches crossed behind him.
///
/// Deliberately NOT a `StreakFlamePhase` case. The phase enum drives the live
/// day-long candle (coal → burning → blazing) and is switched over in several
/// places; a paused streak isn't a point on that lifecycle, it's the lifecycle
/// suspended. Keeping it a sibling view also means `.coal` stays the only
/// "your flame went out" look — a returning 412-day user must never be shown
/// the revival animation, which reads as "your streak died and came back".
///
/// The body is the REAL `FlameBuddyFigure` rather than a redrawn lookalike, so
/// this can't drift from the live buddy. Two of its knobs do specific work:
///   - `health: .low` — the only stage that draws `FlameBuddyFrownShape`.
///   - `vigor:`       — palette comes from the continuous vigor ramp, which
///                      `.low`'s own stage colours (a dull brown) would not
///                      give. `outerColors` prefers vigor whenever health
///                      isn't `.critical`, so the two compose.
///
/// GEOMETRY. Prop constants live in one 130 × 116 design space, which is this
/// view's own frame in units where `size` = 100. Two facts about where the body
/// actually lands have each cost a round of rework, so they're spelled out in
/// `bodyRect`: the body frame is `figureSize * 0.82` wide (not the full frame),
/// and it is then SCALED by vigor about its bottom edge.
///
/// Retune in the mockup sandbox (`/m/injury-pause`), which draws the real
/// bezier with this same math and puts every constant on a slider — not by eye.
struct InjuredFlameBuddyView: View {
    var size: CGFloat = 170
    var grounded: Bool = true
    /// Crutches and wrap are the whole point at hero size, but they turn to
    /// mush below ~60pt — the caller can drop the props and keep the frown.
    var showsProps: Bool = true

    /// Warm amber, a touch below a full day's blaze. The "banked" palette
    /// picked in review — lit, just turned down.
    private let pausedVigor: CGFloat = 0.78

    /// The body renders slightly smaller than the live buddy, which is what
    /// clears room for the crutch ends to show either side.
    private var figureSize: CGFloat { size * 0.86 }

    private var containerSize: CGSize {
        CGSize(width: size * 1.30, height: size * 1.16)
    }

    var body: some View {
        ZStack {
            if showsProps {
                CrossedCrutches(size: size)
            }

            FlameBuddyFigure(
                health: .low,
                size: figureSize,
                showsFace: true,
                vigor: pausedVigor,
                grounded: grounded
            )

            if showsProps {
                HeadWrap(size: size)
                    .frame(width: containerSize.width, height: containerSize.height)
                    // The wrap follows the flame's OUTLINE rather than hanging
                    // off it — bands are drawn oversized on purpose and the
                    // silhouette decides where they stop.
                    .clipShape(FlameSilhouette(bodyRect: bodyRect, wobble: bodyWobble))
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flame buddy on crutches. Streak paused for injury.")
    }

    /// Where `FlameBuddyFigure` actually draws its silhouette, in this view's
    /// coordinate space.
    ///
    /// Two corrections live here, both of which produced visibly wrong props
    /// when assumed away:
    ///  1. the body frame is `figureSize * 0.82` WIDE, not the full frame;
    ///  2. it is then `.scaleEffect`-ed by `flameScale(vigor:)` — 0.816 at our
    ///     vigor, not 1 — anchored to the frame's BOTTOM when grounded, so the
    ///     top edge moves down while the bottom stays put.
    private var bodyRect: CGRect {
        let scale = StreakFlameClock.flameScale(vigor: Double(pausedVigor))
        let w = figureSize * 0.82 * scale
        let h = figureSize * scale
        let x = containerSize.width / 2 - w / 2
        // scaleEffect(anchor: .bottom) pins the UNSCALED frame's bottom edge.
        let unscaledBottom = containerSize.height / 2 + figureSize / 2
        let y = grounded ? unscaledBottom - h : containerSize.height / 2 - h / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The silhouette's wobble, taken from the figure's own formula rather than
    /// assumed to be zero — `flickerPhase: 0` is NOT wobble 0, and a clip built
    /// on zero leaves slivers of bandage hanging past the body edge.
    private var bodyWobble: CGFloat {
        FlameBuddyFigure.wobble(health: .low, vigor: pausedVigor, flickerPhase: 0)
    }
}

/// The flame's outline, positioned in the parent's coordinate space so the
/// bandages can be masked to exactly what the body covers.
private struct FlameSilhouette: Shape {
    let bodyRect: CGRect
    let wobble: CGFloat

    func path(in rect: CGRect) -> Path {
        FlameBuddyOuterShape(wobble: wobble).path(in: bodyRect)
    }
}

// MARK: - Crutches

/// Two axillary crutches crossed BEHIND the body. Each is a real crutch shape:
/// underarm pad, two rails forking down from it, a hand grip between them, and
/// a single shaft below where they converge. A plain stick with three crossbars
/// reads as a tent pole.
private struct CrossedCrutches: View {
    let size: CGFloat

    // All in the shared 130 × 116 design space.
    private static let topInset: CGFloat = 31.5
    private static let topY: CGFloat = 50
    private static let tipInset: CGFloat = 42
    private static let tipY: CGFloat = 103.5
    private static let padWidth: CGFloat = 20
    private static let railSpread: CGFloat = 7.8
    /// Where the hand grip sits, as a fraction of the shaft's length.
    private static let gripT: CGFloat = 0.16
    /// Where the two rails meet the single lower shaft.
    private static let convergeT: CGFloat = 0.8
    private static let tipWidth: CGFloat = 3
    private static let thickness: CGFloat = 5

    private static let shafts: [(CGPoint, CGPoint)] = [
        (CGPoint(x: topInset, y: topY), CGPoint(x: 130 - tipInset, y: tipY)),
        (CGPoint(x: 130 - topInset, y: topY), CGPoint(x: tipInset, y: tipY)),
    ]

    private static let shaftColor = Color(red: 0.78, green: 0.80, blue: 0.83)
    private static let cuffColor = Color(red: 0.60, green: 0.64, blue: 0.68)
    private static let tipColor = Color(red: 0.25, green: 0.27, blue: 0.31)

    /// Design-space widths converted to points.
    private func w(_ units: CGFloat) -> CGFloat { max(1, units * size / 100) }

    var body: some View {
        ZStack {
            CrutchLines(lines: Self.part { p, q in
                [Self.P(p, q, 1, 0), Self.P(p, q, Self.convergeT, 0)]
            })
            .stroke(Self.shaftColor, style: .init(lineWidth: w(Self.thickness), lineCap: .round))

            CrutchLines(lines: Self.rails)
                .stroke(
                    Self.shaftColor,
                    style: .init(
                        lineWidth: w(Self.thickness * 0.85),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            CrutchLines(lines: Self.part { p, q in
                [
                    Self.P(p, q, Self.gripT, -Self.railSpread),
                    Self.P(p, q, Self.gripT, Self.railSpread),
                ]
            })
            .stroke(Self.cuffColor, style: .init(lineWidth: w(Self.thickness * 1.15), lineCap: .round))

            CrutchLines(lines: Self.part { p, q in
                [Self.P(p, q, 0, -Self.padWidth / 2), Self.P(p, q, 0, Self.padWidth / 2)]
            })
            .stroke(Self.cuffColor, style: .init(lineWidth: w(Self.thickness * 1.5), lineCap: .round))

            CrutchLines(lines: Self.part { p, q in
                [Self.P(p, q, 1, -Self.tipWidth / 2), Self.P(p, q, 1, Self.tipWidth / 2)]
            })
            .stroke(Self.tipColor, style: .init(lineWidth: w(Self.thickness * 1.5), lineCap: .round))
        }
        .frame(width: size * 1.30, height: size * 1.16)
    }

    /// A point `t` of the way down a shaft, `off` perpendicular to it.
    ///
    /// Every part is derived from the shaft this way rather than hand-placed:
    /// hand-placed endpoints drift out of square the moment the shaft angle is
    /// retuned, which is exactly what the sliders exist to do.
    private static func P(_ p: CGPoint, _ q: CGPoint, _ t: CGFloat, _ off: CGFloat) -> CGPoint {
        let dx = q.x - p.x
        let dy = q.y - p.y
        let len = max(0.0001, sqrt(dx * dx + dy * dy))
        let ux = dx / len
        let uy = dy / len
        return CGPoint(
            x: p.x + ux * (t * len) - uy * off,
            y: p.y + uy * (t * len) + ux * off
        )
    }

    private static func part(_ build: (CGPoint, CGPoint) -> [CGPoint]) -> [[CGPoint]] {
        shafts.map { build($0.0, $0.1) }
    }

    /// The forked upper section: one rail either side, each running from under
    /// the pad, past the grip, in to where they meet the shaft.
    private static var rails: [[CGPoint]] {
        // Explicit .0/.1 rather than `{ p, q in }` — a closure over an array of
        // TUPLES takes one argument, not two, and destructuring it in the
        // parameter list stopped being legal Swift years ago.
        shafts.flatMap { shaft -> [[CGPoint]] in
            let p = shaft.0
            let q = shaft.1
            return [-railSpread, railSpread].map { side in
                [
                    P(p, q, 0.03, side),
                    P(p, q, gripT + 0.08, side),
                    P(p, q, convergeT, 0),
                ]
            }
        }
    }
}

/// Polylines in the 130 × 116 design space, scaled into whatever rect the view
/// gets. One shape per colour keeps this to five strokes rather than a few
/// dozen separately positioned capsules.
private struct CrutchLines: Shape {
    let lines: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 130
        let sy = rect.height / 116
        for line in lines {
            guard let first = line.first else { continue }
            path.move(to: CGPoint(x: rect.minX + first.x * sx, y: rect.minY + first.y * sy))
            for point in line.dropFirst() {
                path.addLine(to: CGPoint(x: rect.minX + point.x * sx, y: rect.minY + point.y * sy))
            }
        }
        return path
    }
}

// MARK: - Head wrap

/// The 🤕 wrap: a flat band across the head plus a second crossing it at an
/// angle. Plain gauze — no seam lines, no knot.
///
/// Both bands are deliberately drawn WIDER than the head. They're clipped to
/// the silhouette by the caller, so their width only has to be enough to reach
/// the edges and the outline does the shaping. That's also why there's no drop
/// shadow here: it would be clipped away with everything else outside the body.
private struct HeadWrap: View {
    let size: CGFloat

    /// Flat band.
    private static let flat = BandSpec(width: 0.49, height: 0.10, x: -0.005, y: 0.09, angle: -2)
    /// Second band, angled across it.
    private static let angled = BandSpec(width: 0.62, height: 0.10, x: -0.02, y: 0.075, angle: -20)

    struct BandSpec {
        let width: CGFloat
        let height: CGFloat
        let x: CGFloat
        let y: CGFloat
        let angle: CGFloat
    }

    var body: some View {
        ZStack {
            band(Self.angled)
            band(Self.flat)
        }
    }

    private func band(_ spec: BandSpec) -> some View {
        RoundedRectangle(cornerRadius: size * spec.height * 0.42, style: .continuous)
            .fill(Color(red: 0.96, green: 0.95, blue: 0.92))
            .frame(width: size * spec.width, height: size * spec.height)
            .rotationEffect(.degrees(spec.angle))
            .offset(x: size * spec.x, y: size * spec.y)
    }
}

#Preview {
    VStack(spacing: 32) {
        InjuredFlameBuddyView(size: 170)
        HStack(spacing: 24) {
            InjuredFlameBuddyView(size: 90)
            InjuredFlameBuddyView(size: 56, showsProps: false)
        }
    }
    .padding(40)
    .background(Color(red: 0.10, green: 0.10, blue: 0.10))
}
