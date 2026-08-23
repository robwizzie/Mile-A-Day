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
struct InjuredFlameBuddyView: View {
    var size: CGFloat = 170
    var grounded: Bool = true
    /// Crutches and bandage are the whole point at hero size, but they turn to
    /// mush below ~60pt — the caller can drop the props and keep the frown.
    var showsProps: Bool = true

    /// Warm amber, a touch below a full day's blaze. Matches the "banked"
    /// palette picked in mockup review — lit, just turned down.
    private let pausedVigor: CGFloat = 0.78

    var body: some View {
        ZStack {
            if showsProps {
                CrossedCrutches(size: size)
            }

            FlameBuddyFigure(
                health: .low,
                size: size,
                showsFace: true,
                vigor: pausedVigor,
                grounded: grounded
            )

            if showsProps {
                HeadBandage(size: size)
                    // Sits on the brow. A band any lower crosses the eyes and
                    // reads unmistakably as a surgical mask — wrong injury.
                    .offset(y: -size * 0.13)
            }
        }
        .frame(width: size * 1.30, height: size * 1.16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flame buddy on crutches. Streak paused for injury.")
    }
}

/// Two crutches crossed BEHIND the body, crossbones-style: the shafts meet
/// under the flame so only the four ends show. Drawn from a fixed 210×132
/// design space so the proportions survive any `size`.
private struct CrossedCrutches: View {
    let size: CGFloat

    private var w: CGFloat { size * 1.30 }
    private var h: CGFloat { size * 1.16 }

    var body: some View {
        ZStack {
            // shafts
            CrutchLines(lines: [
                [CGPoint(x: 70, y: 38), CGPoint(x: 142, y: 118)],
                [CGPoint(x: 140, y: 38), CGPoint(x: 68, y: 118)],
            ])
            .stroke(Color(red: 0.78, green: 0.80, blue: 0.83),
                    style: StrokeStyle(lineWidth: max(2, size * 0.026), lineCap: .round))

            // armpit cuffs
            CrutchLines(lines: [
                [CGPoint(x: 65, y: 42), CGPoint(x: 75, y: 33)],
                [CGPoint(x: 135, y: 33), CGPoint(x: 145, y: 42)],
            ])
            .stroke(Color(red: 0.60, green: 0.64, blue: 0.68),
                    style: StrokeStyle(lineWidth: max(3, size * 0.037), lineCap: .round))

            // hand grips
            CrutchLines(lines: [
                [CGPoint(x: 74, y: 51), CGPoint(x: 83, y: 43)],
                [CGPoint(x: 127, y: 43), CGPoint(x: 136, y: 51)],
            ])
            .stroke(Color(red: 0.78, green: 0.80, blue: 0.83),
                    style: StrokeStyle(lineWidth: max(2, size * 0.024), lineCap: .round))

            // rubber tips
            CrutchLines(lines: [
                [CGPoint(x: 138, y: 122), CGPoint(x: 147, y: 114)],
                [CGPoint(x: 63, y: 114), CGPoint(x: 72, y: 122)],
            ])
            .stroke(Color(red: 0.25, green: 0.27, blue: 0.31),
                    style: StrokeStyle(lineWidth: max(3, size * 0.033), lineCap: .round))
        }
        .frame(width: w, height: h)
    }
}

/// Straight segments in a 210×132 design space, scaled into whatever rect the
/// view gets. One shape for all of a crutch's same-coloured parts keeps this to
/// four strokes instead of sixteen rotated capsules.
private struct CrutchLines: Shape {
    let lines: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 210
        let sy = rect.height / 132
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

    private var bandWidth: CGFloat { size * 0.60 }
    private var bandHeight: CGFloat { size * 0.115 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: bandHeight * 0.42, style: .continuous)
                .fill(Color(red: 0.96, green: 0.95, blue: 0.92))
                .frame(width: bandWidth, height: bandHeight)
                .overlay {
                    // seam + two wrap folds
                    ZStack {
                        Capsule()
                            .fill(Color(red: 0.86, green: 0.84, blue: 0.78))
                            .frame(width: bandWidth * 0.84, height: max(0.8, size * 0.006))
                        HStack(spacing: bandWidth * 0.17) {
                            fold
                            fold
                        }
                    }
                }

            RoundedRectangle(cornerRadius: bandHeight * 0.30, style: .continuous)
                .fill(Color(red: 0.96, green: 0.95, blue: 0.92))
                .frame(width: bandHeight * 0.95, height: bandHeight * 1.10)
                .offset(x: bandWidth * 0.50)
        }
        .rotationEffect(.degrees(-11))
        .shadow(color: .black.opacity(0.18), radius: size * 0.012, y: size * 0.006)
    }

    private var fold: some View {
        Capsule()
            .fill(Color(red: 0.89, green: 0.87, blue: 0.82))
            .frame(width: max(0.8, size * 0.007), height: bandHeight * 0.86)
            .rotationEffect(.degrees(12))
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
