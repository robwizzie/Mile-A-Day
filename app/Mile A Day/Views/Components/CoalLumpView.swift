import SwiftUI

/// A cold piece of coal — the streak flame when there is no streak to burn.
///
/// The coal is an invitation, not a punishment: faint ember light breathes in
/// its cracks, and `warmth` (today's partial mile progress) makes the glow
/// build until the mile completes and ignition takes over. `showsFace` adds
/// the Fun dashboard's sleeping buddy face; the Modern dashboard renders the
/// bare lump.
struct CoalLumpView: View {
    var size: CGFloat = 150
    var showsFace: Bool = false
    /// Today's partial mile progress (0-1). Warms the cracks before ignition.
    var warmth: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                coal(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { timeline in
                    coal(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: size, height: size * 0.80)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func coal(at t: TimeInterval) -> some View {
        let pulse = (sin(t * 1.15) + 1) / 2
        let crackGlow = min(1, 0.14 + pulse * 0.20 + warmth * 0.55)
        let breath = showsFace ? 1 + CGFloat(sin(t * 1.15)) * 0.012 : 1

        return ZStack {
            groundShadow

            if warmth > 0.02 {
                underglow
            }

            lump(crackGlow: crackGlow)
                .scaleEffect(breath, anchor: .bottom)
        }
    }

    private func lump(crackGlow: Double) -> some View {
        ZStack {
            CoalLumpShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.30, blue: 0.34),
                            Color(red: 0.16, green: 0.15, blue: 0.18),
                            Color(red: 0.07, green: 0.06, blue: 0.09)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    CoalFacetLines()
                        .stroke(Color.white.opacity(0.07), lineWidth: max(1, size * 0.008))
                )
                .overlay(
                    CoalLumpShape()
                        .stroke(Color.white.opacity(0.10), lineWidth: max(1, size * 0.010))
                )
                .shadow(color: Color.orange.opacity(0.10 + warmth * 0.30), radius: size * 0.09, x: 0, y: size * 0.02)

            cracks(glow: crackGlow)

            if showsFace {
                sleepingFace
            }
        }
        .frame(width: size * 0.92, height: size * 0.62)
        .offset(y: size * 0.055)
    }

    private var groundShadow: some View {
        Ellipse()
            .fill(Color.black.opacity(0.30))
            .frame(width: size * 0.74, height: size * 0.12)
            .blur(radius: 3)
            .offset(y: size * 0.345)
    }

    private var underglow: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.45, blue: 0.10).opacity(0.42 * warmth),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 1,
                    endRadius: size * 0.30
                )
            )
            .frame(width: size * 0.80, height: size * 0.30)
            .offset(y: size * 0.28)
            .blur(radius: 2)
    }

    private func cracks(glow: Double) -> some View {
        ZStack {
            crackStroke(Self.mainCrack, glow: glow, width: max(1.5, size * 0.014))
            crackStroke(Self.lowerCrack, glow: glow * 0.85, width: max(1.2, size * 0.011))
            crackStroke(Self.upperCrack, glow: glow * 0.6, width: max(1, size * 0.009))

            Circle()
                .fill(crackColor.opacity(glow * 0.9))
                .frame(width: size * 0.045, height: size * 0.045)
                .blur(radius: 1.5)
                .offset(x: -size * 0.155, y: size * 0.115)
        }
    }

    private func crackStroke(_ points: [CGPoint], glow: Double, width: CGFloat) -> some View {
        ZStack {
            CoalCrackShape(points: points)
                .stroke(
                    crackColor.opacity(glow * 0.55),
                    style: StrokeStyle(lineWidth: width * 2.6, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: width * 1.4)
            CoalCrackShape(points: points)
                .stroke(
                    crackColor.opacity(glow),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
                )
        }
    }

    private var crackColor: Color {
        FlamePalette.lerp((1.0, 0.50, 0.12), (1.0, 0.78, 0.28), min(1, warmth))
    }

    private var sleepingFace: some View {
        ZStack {
            HStack(spacing: size * 0.155) {
                CoalSleepEyeShape()
                    .stroke(Color.white.opacity(0.60), style: StrokeStyle(lineWidth: max(1.5, size * 0.016), lineCap: .round))
                    .frame(width: size * 0.115, height: size * 0.055)
                CoalSleepEyeShape()
                    .stroke(Color.white.opacity(0.60), style: StrokeStyle(lineWidth: max(1.5, size * 0.016), lineCap: .round))
                    .frame(width: size * 0.115, height: size * 0.055)
            }
            .offset(y: -size * 0.015)

            CoalFrownShape()
                .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: max(1.5, size * 0.016), lineCap: .round))
                .frame(width: size * 0.16, height: size * 0.055)
                .offset(y: size * 0.10)
        }
    }

    private var accessibilityText: String {
        if warmth > 0.25 {
            return "Coal warming up. Keep moving to reignite your streak."
        }
        return "Cold coal. Run a mile to ignite your streak."
    }

    private static let mainCrack = [
        CGPoint(x: 0.26, y: 0.58),
        CGPoint(x: 0.38, y: 0.48),
        CGPoint(x: 0.46, y: 0.56),
        CGPoint(x: 0.58, y: 0.46),
        CGPoint(x: 0.70, y: 0.54)
    ]

    private static let lowerCrack = [
        CGPoint(x: 0.38, y: 0.78),
        CGPoint(x: 0.50, y: 0.68),
        CGPoint(x: 0.60, y: 0.76)
    ]

    private static let upperCrack = [
        CGPoint(x: 0.52, y: 0.22),
        CGPoint(x: 0.60, y: 0.30),
        CGPoint(x: 0.70, y: 0.26)
    ]
}

private struct CoalLumpShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            CGPoint(x: 0.30, y: 0.10),
            CGPoint(x: 0.64, y: 0.02),
            CGPoint(x: 0.90, y: 0.22),
            CGPoint(x: 0.98, y: 0.52),
            CGPoint(x: 0.84, y: 0.84),
            CGPoint(x: 0.52, y: 0.98),
            CGPoint(x: 0.16, y: 0.90),
            CGPoint(x: 0.02, y: 0.56),
            CGPoint(x: 0.10, y: 0.26)
        ]
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }
        path.closeSubpath()
        return path
    }
}

private struct CoalFacetLines: Shape {
    func path(in rect: CGRect) -> Path {
        let segments: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 0.30, y: 0.10), CGPoint(x: 0.47, y: 0.44)),
            (CGPoint(x: 0.88, y: 0.24), CGPoint(x: 0.56, y: 0.46)),
            (CGPoint(x: 0.16, y: 0.80), CGPoint(x: 0.45, y: 0.52))
        ]
        var path = Path()
        for (a, b) in segments {
            path.move(to: CGPoint(x: rect.minX + a.x * rect.width, y: rect.minY + a.y * rect.height))
            path.addLine(to: CGPoint(x: rect.minX + b.x * rect.width, y: rect.minY + b.y * rect.height))
        }
        return path
    }
}

private struct CoalCrackShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }
        return path
    }
}

private struct CoalSleepEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.30))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.30),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}

private struct CoalFrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.82))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY * 0.82),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        return path
    }
}
