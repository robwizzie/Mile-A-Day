import SwiftUI

/// One-shot ignition burst played the moment the streak flame catches — a
/// white-hot flash at the base, a vertical whoosh, an expanding shockwave and
/// a fan of sparks. Purely parametric over elapsed time, so it renders
/// deterministically at any frame rate and self-completes.
struct FlameIgnitionBurst: View {
    let startDate: Date
    var size: CGFloat = 170
    var intensity: CGFloat = 1

    static let duration: TimeInterval = 1.15

    private static let sparkAngles: [Double] = [-78, -58, -41, -26, -12, -3, 6, 15, 28, 44, 60, 76]
    private static let sparkReach: [CGFloat] = [0.90, 0.55, 1.00, 0.70, 0.85, 0.60, 0.95, 0.75, 0.65, 1.00, 0.55, 0.80]
    private static let sparkLength: [CGFloat] = [11, 8, 13, 9, 12, 8, 14, 10, 9, 13, 8, 11]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let raw = timeline.date.timeIntervalSince(startDate) / Self.duration
            burst(t: CGFloat(min(max(raw, 0), 1)))
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func burst(t: CGFloat) -> some View {
        let baseY = size * 0.40
        return ZStack {
            flash(t: t)
                .offset(y: baseY)
            whoosh(t: t)
            shockRing(t: t)
                .offset(y: size * 0.16)
            sparks(t: t, baseY: baseY)
        }
        .opacity(t >= 1 ? 0 : 1)
    }

    private func flash(t: CGFloat) -> some View {
        let phase = Double(min(t / 0.28, 1))
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color(red: 1.0, green: 0.85, blue: 0.35).opacity(0.75),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.16
                )
            )
            .frame(width: size * 0.32, height: size * 0.32)
            .scaleEffect(0.3 + CGFloat(phase) * 0.9)
            .opacity((1 - phase) * Double(intensity) * 0.9)
    }

    private func whoosh(t: CGFloat) -> some View {
        let phase = Double(min(t / 0.45, 1))
        let eased = 1 - pow(1 - phase, 2)
        let height = size * (0.18 + CGFloat(eased) * 0.62)
        return Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.0),
                        Color(red: 1.0, green: 0.85, blue: 0.40).opacity(0.55),
                        Color(red: 1.0, green: 0.55, blue: 0.10).opacity(0.30)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size * 0.10, height: height)
            .offset(y: size * 0.40 - height / 2)
            .blur(radius: size * 0.02)
            .opacity(sin(.pi * phase) * 0.8 * Double(intensity))
    }

    private func shockRing(t: CGFloat) -> some View {
        let phase = Double(min(t / 0.70, 1))
        let eased = 1 - pow(1 - phase, 2.2)
        return Ellipse()
            .stroke(
                Color(red: 1.0, green: 0.70, blue: 0.20).opacity((1 - eased) * 0.5 * Double(intensity)),
                style: StrokeStyle(lineWidth: max(1.5, size * 0.016), lineCap: .round)
            )
            .frame(
                width: size * (0.24 + CGFloat(eased) * 0.92),
                height: size * (0.19 + CGFloat(eased) * 0.72)
            )
            .blur(radius: 0.8)
    }

    private func sparks(t: CGFloat, baseY: CGFloat) -> some View {
        ZStack {
            ForEach(0..<Self.sparkAngles.count, id: \.self) { index in
                spark(index: index, t: t, baseY: baseY)
            }
        }
    }

    private func spark(index: Int, t: CGFloat, baseY: CGFloat) -> some View {
        let start = Double(index) * 0.016
        let local = min(max((Double(t) - start) / (1 - start), 0), 1)
        let eased = 1 - pow(1 - local, 2.4)
        let angle = Self.sparkAngles[index] * .pi / 180
        let reach = Self.sparkReach[index] * size * 0.52
        let dx = CGFloat(sin(angle) * eased) * reach
        let dy = -CGFloat(cos(angle) * eased) * reach + CGFloat(local * local) * size * 0.10
        let fade = local > 0 ? pow(1 - local, 0.8) * 0.9 : 0

        return Capsule()
            .fill(sparkColor(index: index))
            .frame(width: 3, height: Self.sparkLength[index])
            .rotationEffect(.degrees(Self.sparkAngles[index]))
            .offset(x: dx, y: baseY - size * 0.06 + dy)
            .opacity(fade * Double(intensity))
    }

    private func sparkColor(index: Int) -> Color {
        if index.isMultiple(of: 3) { return Color.white.opacity(0.85) }
        if index.isMultiple(of: 2) { return Color(red: 1.0, green: 0.80, blue: 0.25) }
        return Color(red: 1.0, green: 0.55, blue: 0.12)
    }
}

/// A soft puff of smoke for the moment the flame dies — played only when the
/// dashboard is on screen as midnight passes without a mile.
struct FlameSmokePuff: View {
    let startDate: Date
    var size: CGFloat = 170

    static let duration: TimeInterval = 1.6

    private static let wisps: [(x: CGFloat, delay: Double, scale: CGFloat)] = [
        (-0.06, 0.00, 1.00),
        (0.05, 0.16, 0.80),
        (-0.01, 0.30, 0.65)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let raw = timeline.date.timeIntervalSince(startDate) / Self.duration
            let t = min(max(raw, 0), 1)
            ZStack {
                ForEach(0..<Self.wisps.count, id: \.self) { index in
                    wisp(index: index, t: t)
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func wisp(index: Int, t: Double) -> some View {
        let seed = Self.wisps[index]
        let local = min(max((t - seed.delay) / (1 - seed.delay), 0), 1)
        let eased = 1 - pow(1 - local, 1.8)
        let rise = CGFloat(eased) * size * 0.46

        return Circle()
            .fill(Color(white: 0.62).opacity(sin(.pi * local) * 0.30))
            .frame(width: size * 0.16 * seed.scale, height: size * 0.16 * seed.scale)
            .scaleEffect(0.6 + CGFloat(eased) * 0.9)
            .blur(radius: size * 0.030)
            .offset(
                x: size * seed.x + CGFloat(sin(local * 5 + Double(index) * 2)) * size * 0.03,
                y: size * 0.34 - rise
            )
    }
}
