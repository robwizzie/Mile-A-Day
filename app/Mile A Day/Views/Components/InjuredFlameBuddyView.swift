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
/// GEOMETRY. Every prop constant below is expressed in one 130 × 116 design
/// space, which is this view's own frame in units where `size` = 100. That is
/// not decorative: the props have to be placed against where `FlameBuddyFigure`
/// actually puts its body — `figureSize * 0.82` wide by `figureSize` tall,
/// CENTRED, not the full frame. Guessing that cost a round, with the bandage up
/// by the flame's tip and both crutches buried behind the silhouette.
///
/// These numbers were dialled in against a preview that draws the real
/// `FlameBuddyOuterShape` bezier with the same layout math — mockup sandbox,
/// `/m/injury-pause`, every constant on a slider. Retune there, not by eye.
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
    /// clears room for the crutch ends to show either side. Without it the
    /// silhouette covers the shafts almost end to end and the crossbones read
    /// as two little floating T-shapes.
    private var figureSize: CGFloat { size * 0.86 }

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
            }
        }
        .frame(width: size * 1.30, height: size * 1.16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flame buddy on crutches. Streak paused for injury.")
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
    private static let topInset: CGFloat = 32.2
    private static let topY: CGFloat = 22.9
    private static let tipInset: CGFloat = 26.0
    private static let tipY: CGFloat = 103.7
    private static let padWidth: CGFloat = 15
    private static let railSpread: CGFloat = 5.6
    /// Where the hand grip sits, as a fraction of the shaft's length.
    private static let gripT: CGFloat = 0.34
    /// Where the two rails meet the single lower shaft.
    private static let convergeT: CGFloat = 0.54
    private static let tipWidth: CGFloat = 9
    private static let thickness: CGFloat = 2.9

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
            CrutchLines(lines: Self.part { p, q in [Self.P(p, q, 1, 0), Self.P(p, q, Self.convergeT, 0)] })
                .stroke(Self.shaftColor, style: .init(lineWidth: w(Self.thickness), lineCap: .round))

            CrutchLines(lines: Self.rails)
                .stroke(
                    Self.shaftColor,
                    style: .init(lineWidth: w(Self.thickness * 0.85), lineCap: .round, lineJoin: .round)
                )

            CrutchLines(lines: Self.part { p, q in
                [Self.P(p, q, Self.gripT, -Self.railSpread), Self.P(p, q, Self.gripT, Self.railSpread)]
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
        // Explicit .0/.1 rather than `{ p, q in }` — a closure over an array
        // of TUPLES takes one argument, not two, and destructuring it in the
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

/// The 🤕 wrap: a flat band across the brow plus a second band crossing it at
/// an angle, with the knot tied at one end of the flat one.
///
/// The angled band is drawn UNDER the flat one so the flat band reads as the
/// outer layer, and the knot sits on top of both. Both are centred on the
/// container rather than offset up: the eyes sit `figureSize * 0.18` BELOW the
/// centre, so this lands on the brow and clears them. A band any lower crosses
/// the eyes and reads unmistakably as a surgical mask — wrong injury entirely.
private struct HeadWrap: View {
    let size: CGFloat

    /// Flat band across the brow.
    private static let flat = BandSpec(width: 0.42, height: 0.095, x: 0, y: 0, angle: -4)
    /// Second band, angled over the skull.
    private static let angled = BandSpec(width: 0.36, height: 0.085, x: 0, y: -0.03, angle: -35)
    /// Knot position as a fraction of the flat band's own width/height.
    private static let knotX: CGFloat = 0.55
    private static let knotY: CGFloat = 0
    private static let knotScale: CGFloat = 1.0

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
            knot
        }
        .shadow(color: .black.opacity(0.18), radius: size * 0.010, y: size * 0.005)
    }

    private func band(_ spec: BandSpec) -> some View {
        let w = size * spec.width
        let h = size * spec.height
        return RoundedRectangle(cornerRadius: h * 0.42, style: .continuous)
            .fill(Color(red: 0.96, green: 0.95, blue: 0.92))
            .frame(width: w, height: h)
            .overlay {
                ZStack {
                    Capsule()
                        .fill(Color(red: 0.86, green: 0.84, blue: 0.78))
                        .frame(width: w * 0.84, height: max(0.8, size * 0.005))
                    HStack(spacing: w * 0.20) {
                        fold(h)
                        fold(h)
                    }
                }
            }
            .rotationEffect(.degrees(spec.angle))
            .offset(x: size * spec.x, y: size * spec.y)
    }

    private var knot: some View {
        let flat = Self.flat
        let w = size * flat.width
        let h = size * flat.height
        return RoundedRectangle(cornerRadius: h * 0.30 * Self.knotScale, style: .continuous)
            .fill(Color(red: 0.96, green: 0.95, blue: 0.92))
            .frame(width: h * 0.95 * Self.knotScale, height: h * 1.20 * Self.knotScale)
            .offset(x: w * Self.knotX, y: h * Self.knotY)
            .rotationEffect(.degrees(flat.angle))
            .offset(x: size * flat.x, y: size * flat.y)
    }

    private func fold(_ h: CGFloat) -> some View {
        Capsule()
            .fill(Color(red: 0.89, green: 0.87, blue: 0.82))
            .frame(width: max(0.8, size * 0.006), height: h * 0.88)
            .rotationEffect(.degrees(10))
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
