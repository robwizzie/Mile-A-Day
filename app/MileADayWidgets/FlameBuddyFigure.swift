import SwiftUI

enum FlameHealth: String, CaseIterable {
    case blazing
    case healthy
    case dimming
    case low
    case critical
    case dead

    static func forState(
        isCompleted: Bool,
        distanceIsFresh: Bool,
        isAtRisk: Bool,
        secondsToReset: TimeInterval?,
        streak: Int
    ) -> FlameHealth {
        if isCompleted && distanceIsFresh { return .blazing }
        if streak == 0 && distanceIsFresh { return .dead }
        if isAtRisk { return .critical }

        guard let secondsToReset else { return .healthy }
        let hours = secondsToReset / 3600
        if hours >= 8 { return .healthy }
        if hours >= 4 { return .dimming }
        return .low
    }

    var glowOpacity: Double {
        switch self {
        case .blazing: return 0.66
        case .healthy: return 0.48
        case .dimming: return 0.32
        case .low: return 0.20
        case .critical: return 0.52
        case .dead: return 0.05
        }
    }

    var bodyScale: CGFloat {
        switch self {
        case .blazing: return 1.05
        case .healthy: return 1.0
        case .dimming: return 0.92
        case .low: return 0.82
        case .critical: return 0.90
        case .dead: return 0.70
        }
    }
}

struct FlameBuddyFigure: View {
    let health: FlameHealth
    var flickerPhase: CGFloat = 0
    var blink: Bool = false
    var size: CGFloat = 170

    var body: some View {
        ZStack {
            glowLayer
            groundLayer

            ZStack {
                FlameBuddyOuterShape(wobble: wobble)
                    .fill(outerFill)
                    .shadow(color: glowColor.opacity(health.glowOpacity), radius: size * 0.16)
                    .overlay(
                        FlameBuddyOuterShape(wobble: wobble)
                            .stroke(Color.white.opacity(health == .dead ? 0.10 : 0.28), lineWidth: max(1.5, size * 0.012))
                    )

                FlameBuddyInnerShape(wobble: -wobble * 0.6)
                    .fill(innerFill)
                    .frame(width: size * 0.54, height: size * 0.58)
                    .offset(y: size * 0.13)
                    .opacity(health == .dead ? 0 : innerOpacity)

                face
                    .offset(y: size * 0.18)
            }
            .frame(width: size * 0.82, height: size)
            .scaleEffect(health.bodyScale, anchor: .bottom)
            .offset(y: health == .dead ? size * 0.16 : 0)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var wobble: CGFloat {
        guard health != .dead else { return 0 }
        return sin(flickerPhase) * (health == .critical ? 0.07 : 0.045)
    }

    private var outerFill: LinearGradient {
        LinearGradient(colors: outerColors, startPoint: .top, endPoint: .bottom)
    }

    private var innerFill: LinearGradient {
        LinearGradient(colors: innerColors, startPoint: .top, endPoint: .bottom)
    }

    private var outerColors: [Color] {
        switch health {
        case .blazing:
            return [.white, Color(red: 1, green: 0.88, blue: 0.28), .orange, Color(red: 1, green: 0.20, blue: 0.10)]
        case .healthy:
            return [Color(red: 1, green: 0.95, blue: 0.32), .orange, Color(red: 1, green: 0.22, blue: 0.10)]
        case .dimming:
            return [Color(red: 1, green: 0.72, blue: 0.22), Color(red: 0.95, green: 0.36, blue: 0.18), Color(red: 0.52, green: 0.12, blue: 0.14)]
        case .low:
            return [Color(red: 0.72, green: 0.42, blue: 0.22), Color(red: 0.42, green: 0.16, blue: 0.18), Color(red: 0.10, green: 0.10, blue: 0.14)]
        case .critical:
            return [Color(red: 1, green: 0.62, blue: 0.18), Color(red: 1, green: 0.17, blue: 0.16), Color(red: 0.52, green: 0.04, blue: 0.08)]
        case .dead:
            return [Color.white.opacity(0.40), Color.gray.opacity(0.55), Color.black.opacity(0.45)]
        }
    }

    private var innerColors: [Color] {
        switch health {
        case .blazing:
            return [.white, Color(red: 1, green: 0.92, blue: 0.30), Color(red: 1, green: 0.50, blue: 0.08)]
        case .healthy:
            return [Color(red: 1, green: 0.98, blue: 0.44), Color(red: 1, green: 0.65, blue: 0.12)]
        case .dimming:
            return [Color(red: 1, green: 0.68, blue: 0.18), Color(red: 0.82, green: 0.22, blue: 0.10)]
        case .low, .critical:
            return [Color(red: 1, green: 0.46, blue: 0.16), Color(red: 0.28, green: 0.18, blue: 0.40)]
        case .dead:
            return [.clear]
        }
    }

    private var innerOpacity: Double {
        switch health {
        case .blazing: return 0.95
        case .healthy: return 0.82
        case .dimming: return 0.54
        case .low: return 0.30
        case .critical: return 0.58
        case .dead: return 0
        }
    }

    private var glowColor: Color {
        switch health {
        case .dead: return .gray
        case .low: return Color(red: 0.42, green: 0.32, blue: 0.95)
        case .critical: return .red
        default: return .orange
        }
    }

    private var glowLayer: some View {
        ZStack {
            Circle()
                .fill(glowColor.opacity(health.glowOpacity * 0.45))
                .blur(radius: size * 0.18)
                .frame(width: size * 1.1, height: size * 0.92)
            Circle()
                .fill(Color.yellow.opacity(health == .dead ? 0 : 0.16))
                .blur(radius: size * 0.09)
                .frame(width: size * 0.62, height: size * 0.62)
                .offset(y: size * 0.12)
        }
    }

    private var groundLayer: some View {
        VStack {
            Spacer()
            Ellipse()
                .fill(Color.black.opacity(0.24))
                .frame(width: size * 0.78, height: size * 0.16)
                .blur(radius: 3)
                .offset(y: size * 0.02)
        }
    }

    private var face: some View {
        ZStack {
            HStack(spacing: size * 0.17) {
                eye(isLeft: true)
                eye(isLeft: false)
            }

            mouth
                .offset(y: size * 0.13)
        }
    }

    @ViewBuilder
    private func eye(isLeft: Bool) -> some View {
        if health == .dead {
            ZStack {
                Capsule().fill(Color.white.opacity(0.86)).frame(width: size * 0.085, height: size * 0.018).rotationEffect(.degrees(42))
                Capsule().fill(Color.white.opacity(0.86)).frame(width: size * 0.085, height: size * 0.018).rotationEffect(.degrees(-42))
            }
            .frame(width: size * 0.13, height: size * 0.13)
        } else {
            Ellipse()
                .fill(Color(red: 0.20, green: 0.07, blue: 0.04))
                .frame(width: size * 0.12, height: blink ? size * 0.018 : size * 0.18)
                .overlay(alignment: .topLeading) {
                    if !blink {
                        Circle()
                            .fill(Color.white.opacity(0.92))
                            .frame(width: size * 0.035, height: size * 0.035)
                            .offset(x: size * 0.024, y: size * 0.030)
                    }
                }
                .offset(y: health == .critical ? size * 0.02 : 0)
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch health {
        case .blazing, .healthy:
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color(red: 0.24, green: 0.04, blue: 0.04))
                    .frame(width: size * 0.22, height: size * 0.14)
                Capsule()
                    .fill(Color(red: 1.0, green: 0.42, blue: 0.34))
                    .frame(width: size * 0.12, height: size * 0.045)
                    .offset(y: size * 0.08)
            }
        case .dimming:
            Capsule()
                .fill(Color(red: 0.24, green: 0.04, blue: 0.04).opacity(0.82))
                .frame(width: size * 0.15, height: size * 0.030)
        case .low, .critical:
            FlameBuddyFrownShape()
                .stroke(Color(red: 0.24, green: 0.04, blue: 0.04).opacity(0.86), style: StrokeStyle(lineWidth: max(2, size * 0.018), lineCap: .round))
                .frame(width: size * 0.20, height: size * 0.075)
        case .dead:
            EmptyView()
        }
    }

    private var accessibilityText: String {
        switch health {
        case .blazing: return "Flame buddy blazing. Today's mile is complete."
        case .healthy: return "Flame buddy healthy."
        case .dimming: return "Flame buddy dimming."
        case .low: return "Flame buddy low."
        case .critical: return "Flame buddy worried. Streak at risk."
        case .dead: return "Flame buddy out."
        }
    }
}

struct FlameBuddyOuterShape: Shape {
    var wobble: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let x = { (v: CGFloat) in rect.minX + v * w }
        let y = { (v: CGFloat) in rect.minY + v * h }

        path.move(to: CGPoint(x: x(0.50 + wobble * 0.10), y: y(0.02)))
        path.addCurve(to: CGPoint(x: x(0.28 + wobble * 0.35), y: y(0.42)), control1: CGPoint(x: x(0.35 + wobble), y: y(0.13)), control2: CGPoint(x: x(0.27 - wobble * 0.3), y: y(0.25)))
        path.addCurve(to: CGPoint(x: x(0.18 - wobble * 0.2), y: y(0.56)), control1: CGPoint(x: x(0.20), y: y(0.36)), control2: CGPoint(x: x(0.15), y: y(0.46)))
        path.addCurve(to: CGPoint(x: x(0.08), y: y(0.72)), control1: CGPoint(x: x(0.12), y: y(0.61)), control2: CGPoint(x: x(0.08), y: y(0.66)))
        path.addCurve(to: CGPoint(x: x(0.50), y: y(0.98)), control1: CGPoint(x: x(0.08), y: y(0.90)), control2: CGPoint(x: x(0.24), y: y(0.98)))
        path.addCurve(to: CGPoint(x: x(0.92), y: y(0.72)), control1: CGPoint(x: x(0.76), y: y(0.98)), control2: CGPoint(x: x(0.92), y: y(0.90)))
        path.addCurve(to: CGPoint(x: x(0.69 + wobble * 0.25), y: y(0.35)), control1: CGPoint(x: x(0.92), y: y(0.55)), control2: CGPoint(x: x(0.75 + wobble), y: y(0.48)))
        path.addCurve(to: CGPoint(x: x(0.50 + wobble * 0.10), y: y(0.02)), control1: CGPoint(x: x(0.78), y: y(0.20)), control2: CGPoint(x: x(0.62), y: y(0.11)))
        path.closeSubpath()
        return path
    }
}

struct FlameBuddyInnerShape: Shape {
    var wobble: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let x = { (v: CGFloat) in rect.minX + v * w }
        let y = { (v: CGFloat) in rect.minY + v * h }

        path.move(to: CGPoint(x: x(0.52 + wobble * 0.20), y: y(0.02)))
        path.addCurve(to: CGPoint(x: x(0.32), y: y(0.48)), control1: CGPoint(x: x(0.35), y: y(0.20)), control2: CGPoint(x: x(0.37), y: y(0.34)))
        path.addCurve(to: CGPoint(x: x(0.18), y: y(0.72)), control1: CGPoint(x: x(0.22), y: y(0.54)), control2: CGPoint(x: x(0.18), y: y(0.62)))
        path.addCurve(to: CGPoint(x: x(0.50), y: y(0.98)), control1: CGPoint(x: x(0.18), y: y(0.90)), control2: CGPoint(x: x(0.34), y: y(0.98)))
        path.addCurve(to: CGPoint(x: x(0.82), y: y(0.72)), control1: CGPoint(x: x(0.66), y: y(0.98)), control2: CGPoint(x: x(0.82), y: y(0.90)))
        path.addCurve(to: CGPoint(x: x(0.60 + wobble * 0.22), y: y(0.38)), control1: CGPoint(x: x(0.82), y: y(0.56)), control2: CGPoint(x: x(0.62), y: y(0.52)))
        path.addCurve(to: CGPoint(x: x(0.52 + wobble * 0.20), y: y(0.02)), control1: CGPoint(x: x(0.72), y: y(0.24)), control2: CGPoint(x: x(0.60), y: y(0.14)))
        path.closeSubpath()
        return path
    }
}

private struct FlameBuddyFrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}
