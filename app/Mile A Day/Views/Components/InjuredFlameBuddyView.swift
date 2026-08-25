import SwiftUI

/// The flame buddy while a streak is paused for injury: frowning, head
/// bandaged, on crutches crossed behind him.
///
/// Deliberately NOT a `StreakFlamePhase` case. The phase enum drives the live
/// day-long candle (coal → burning → blazing) and is switched over in several
/// places; a paused streak isn't a point on that lifecycle, it's the lifecycle
/// suspended. Keeping it a sibling view also means `.coal` stays the only
/// "your flame went out" look — a returning 412-day user must never be shown
/// the revival animation, which reads as "your streak died and came back".
///
/// The body is the REAL `FlameBuddyFigure` rather than a redrawn lookalike, so
/// this can't drift from the live buddy. Two of its knobs are doing specific
/// work:
///   - `health: .low` — the only stage that draws `FlameBuddyFrownShape`.
///   - `vigor:`       — palette comes from the continuous vigor ramp, which
///                      `.low`'s own stage colours (a dull brown) would not
///                      give. `outerColors` prefers vigor whenever health
///                      isn't `.critical`, so the two compose: warm from
///                      vigor, frown from health.
///
/// GEOMETRY. Everything here is expressed in a 130 × 116 design space, which is
/// this view's own frame in units where `size` = 100. That is not decorative:
/// the props have to be placed against where `FlameBuddyFigure` actually puts
/// its body, which is `figureSize * 0.82` wide by `figureSize` tall, CENTRED —
/// not the full frame. Guessing that cost a round: the first pass put the
/// bandage near the flame's tip and buried both crutches behind the body.
struct InjuredFlameBuddyView: View {
    var size: CGFloat = 170
    var grounded: Bool = true
    /// Crutches and bandage are the whole point at hero size, but they turn to
    /// mush below ~60pt — the caller can drop the props and keep the frown.
    var showsProps: Bool = true

    /// Warm amber, a touch below a full day's blaze. Matches the "banked"
    /// palette picked in mockup review — lit, just turned down.
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
                // Centred on the container, which lands it across the brow:
                // the eyes sit at figureSize * 0.18 BELOW centre, so this
                // clears them. A band any lower crosses the eyes and reads
                // unmistakably as a surgical mask — wrong injury entirely.
                HeadBandage(size: size)
            }
        }
        .frame(width: size * 1.30, height: size * 1.16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flame buddy on crutches. Streak paused for injury.")
    }
}

/// Two crutches crossed BEHIND the body, crossbones-style: the shafts meet
/// under the flame, with both ends splayed clear of the silhouette so they
/// actually read as crutches.
private struct CrossedCrutches: View {
    let size: CGFloat

    /// (top, tip) of each shaft in the shared 130 × 116 design space.
    private static let shafts: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 32.2, y: 22.9), CGPoint(x: 104.0, y: 103.7)),
        (CGPoint(x: 97.8, y: 22.9), CGPoint(x: 26.0, y: 103.7)),
    ]

    /// Design-space widths, converted to points against `size`.
    private func w(_ units: CGFloat) -> CGFloat { max(1, units * size / 100) }

    var body: some View {
        ZStack {
            CrutchLines(lines: Self.shafts.map { [$0.0, $0.1] })
                .stroke(Self.shaft, style: .init(lineWidth: w(3.4), lineCap: .round))

            CrutchLines(lines: Self.bars(at: 0, half: 4.6))
                .stroke(Self.cuff, style: .init(lineWidth: w(4.6), lineCap: .round))

            CrutchLines(lines: Self.bars(at: 0.18, half: 3.9))
                .stroke(Self.shaft, style: .init(lineWidth: w(3.2), lineCap: .round))

            CrutchLines(lines: Self.bars(at: 1, half: 3.4))
                .stroke(Self.tip, style: .init(lineWidth: w(4.4), lineCap: .round))
        }
        .frame(width: size * 1.30, height: size * 1.16)
    }

    private static let shaft = Color(red: 0.78, green: 0.80, blue: 0.83)
    private static let cuff = Color(red: 0.60, green: 0.64, blue: 0.68)
    private static let tip = Color(red: 0.25, green: 0.27, blue: 0.31)

    /// The armpit cuff, hand grip and rubber tip are all just bars ACROSS the
    /// shaft, so they're derived from it rather than hand-placed — hand-placed
    /// endpoints drift out of square the moment the shaft angle is retuned.
    private static func bars(at t: CGFloat, half: CGFloat) -> [[CGPoint]] {
        shafts.map { p, q in
            let cx = p.x + (q.x - p.x) * t
            let cy = p.y + (q.y - p.y) * t
            let dx = q.x - p.x
            let dy = q.y - p.y
            let len = max(0.0001, sqrt(dx * dx + dy * dy))
            let nx = -dy / len
            let ny = dx / len
            return [
                CGPoint(x: cx - nx * half, y: cy - ny * half),
                CGPoint(x: cx + nx * half, y: cy + ny * half),
            ]
        }
    }
}

/// Polylines in the 130 × 116 design space, scaled into whatever rect the view
/// gets. One shape per colour keeps this to four strokes instead of sixteen
/// separately positioned capsules.
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

/// 🤕-style wrap across the brow with a knot at one side. No trailing tails —
/// with them the right side fans into an arrowhead, and they're the first
/// detail to turn to mush when the buddy is drawn small.
private struct HeadBandage: View {
    let size: CGFloat

    private var bandWidth: CGFloat { size * 0.42 }
    private var bandHeight: CGFloat { size * 0.095 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: bandHeight * 0.42, style: .continuous)
                .fill(Color(red: 0.96, green: 0.95, blue: 0.92))
                .frame(width: bandWidth, height: bandHeight)
                .overlay {
                    ZStack {
                        Capsule()
                            .fill(Color(red: 0.86, green: 0.84, blue: 0.78))
                            .frame(width: bandWidth * 0.84, height: max(0.8, size * 0.005))
                        HStack(spacing: bandWidth * 0.20) {
                            fold
                            fold
                        }
                    }
                }

            // Knot, sitting just past the band's right end.
            RoundedRectangle(cornerRadius: bandHeight * 0.30, style: .continuous)
                .fill(Color(red: 0.96, green: 0.95, blue: 0.92))
                .frame(width: bandHeight * 0.95, height: bandHeight * 1.20)
                .offset(x: bandWidth * 0.55)
        }
        .rotationEffect(.degrees(-8))
        .shadow(color: .black.opacity(0.18), radius: size * 0.010, y: size * 0.005)
    }

    private var fold: some View {
        Capsule()
            .fill(Color(red: 0.89, green: 0.87, blue: 0.82))
            .frame(width: max(0.8, size * 0.006), height: bandHeight * 0.88)
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
