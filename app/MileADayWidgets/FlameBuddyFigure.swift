import SwiftUI

// Widget-target copy of the flame figure. KEEP IN SYNC with
// app/Mile A Day/Views/Components/FlameBuddyFigure.swift — the Streak Flame
// widget drives it with `vigor` so the flame burns down in lock-step with the
// dashboard. Widgets render statically, so callers pass flickerPhase 0 / no
// blink; the size + palette still track time left via `vigor`.

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
    /// The Modern flame renders faceless; the Fun buddy keeps its face.
    var showsFace: Bool = true
    /// Continuous time-left driver (1 = full day ahead, 0 = midnight). When set,
    /// the flame's size, palette and glow burn down with the day — matching the
    /// dashboard. When nil the figure keeps its stage-based look.
    var vigor: CGFloat? = nil
    /// Grounded flames (the Fun buddy) shrink toward their base and cast a
    /// ground shadow; a non-grounded flame (the Modern ring) shrinks toward its
    /// center so it stays framed in the circle.
    var grounded: Bool = true
    /// Flamey's wardrobe colour (`FlameyPalette`, FlameyPalettes.swift). nil
    /// = the lifecycle palette above, byte-identical to before the wardrobe —
    /// every caller that isn't dressing him passes nothing. Ignored on a dead
    /// flame (the coal is grey whatever he wears).
    var palette: FlameyPalette? = nil
    /// How far he hovers (rocket jets, winged sandals), as a fraction of
    /// `size`. The body lifts; the ground shadow stays on the floor and
    /// shrinks. Zero is byte-identical.
    var lift: CGFloat = 0
    /// His legs, in body units: stubby flame legs under him, drawn only
    /// when he wears shoes (`FlameyLook.standLift`). `lift` already raises
    /// the body by this much; the legs fill the gap down to his feet, and
    /// the ground shadow treats them as standing, not hovering. Drawn HERE,
    /// under the body and over the glow, so they burn in his exact colours
    /// (the day's burn-down included) and a stuffed belly overlaps them.
    /// Zero — every caller that isn't dressing him — is byte-identical.
    var legLength: CGFloat = 0
    /// The mascot's limbs for a caller that draws the bare figure rather
    /// than `FlameBuddyView` (celebrations, the feed's cheerleader, the
    /// streak-risk Live Activity): stands him on his legs (adding their
    /// lift itself) and draws his arms in this pose, static. nil — every
    /// other caller — is byte-identical.
    var limbs: FlameArmPose? = nil

    /// Where each leg meets the floor, ±x from his centre, in body units.
    /// The wardrobe plants the shoes on this.
    static let legSpread: CGFloat = 0.11

    var activePalette: FlameyPalette? { health == .dead ? nil : palette }

    /// Legs and lift as drawn: `limbs` stands a bare-figure caller on the
    /// mascot's legs without it having to know his body scale.
    var resolvedLegLength: CGFloat {
        limbs != nil && legLength == 0 ? Self.mascotLegLength : legLength
    }
    var resolvedLift: CGFloat {
        limbs != nil && legLength == 0 ? lift + Self.mascotLegLength * effectiveBodyScale : lift
    }

    var body: some View {
        ZStack {
            glowLayer
            groundLayer
            legsLayer

            ZStack {
                FlameBuddyOuterShape(wobble: wobble)
                    .fill(outerStyle)
                    .overlay {
                        if let activePalette {
                            FlameyPaletteBodyFX(palette: activePalette, size: size, wobble: wobble)
                        }
                    }
                    .shadow(color: glowColor.opacity(effectiveGlowOpacity), radius: size * 0.16)
                    .overlay(
                        FlameBuddyOuterShape(wobble: wobble)
                            .stroke(activePalette?.rim ?? Color.white.opacity(health == .dead ? 0.10 : 0.28), lineWidth: max(1.5, size * 0.012))
                    )

                FlameBuddyInnerShape(wobble: -wobble * 0.6)
                    .fill(innerFill)
                    .overlay {
                        if let activePalette {
                            FlameyPaletteInnerFX(palette: activePalette, size: size)
                        }
                    }
                    .frame(width: size * 0.54, height: size * 0.58)
                    .offset(y: size * 0.13)
                    .opacity(health == .dead ? 0 : (activePalette?.innerOpacity ?? innerOpacity))

                if showsFace {
                    face
                        .offset(y: size * 0.18)
                }
            }
            .frame(width: size * 0.82, height: size)
            .opacity(activePalette?.bodyOpacity ?? 1)
            .scaleEffect(effectiveBodyScale, anchor: grounded ? .bottom : .center)
            .offset(y: (health == .dead ? size * 0.16 : 0) - resolvedLift * size)

            if let limbs, health != .dead {
                FlameBuddyArms(figure: self, pose: limbs)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Clamped vigor, only honored for states that represent a live flame.
    private var vigorValue: CGFloat? {
        guard let vigor, health != .dead, health != .blazing else { return nil }
        return min(max(vigor, 0), 1)
    }

    var effectiveBodyScale: CGFloat {
        if let v = vigorValue { return StreakFlameClock.flameScale(vigor: Double(v)) }
        return health.bodyScale
    }

    private var effectiveGlowOpacity: Double {
        if let v = vigorValue, health != .critical { return 0.16 + Double(v) * 0.36 }
        return health.glowOpacity
    }

    private var wobble: CGFloat {
        guard health != .dead else { return 0 }
        return sin(flickerPhase) * (health == .critical ? 0.07 : 0.045)
    }

    private var outerFill: LinearGradient {
        LinearGradient(colors: outerColors, startPoint: .top, endPoint: .bottom)
    }

    private var innerFill: LinearGradient {
        LinearGradient(colors: activePalette?.inner ?? innerColors, startPoint: .top, endPoint: .bottom)
    }

    /// The outer fill: the wardrobe colour when he wears one (a conic sweep
    /// for Prism), else the lifecycle gradient.
    private var outerStyle: AnyShapeStyle {
        guard let p = activePalette else { return AnyShapeStyle(outerFill) }
        if p.angular {
            return AnyShapeStyle(AngularGradient(colors: p.outer + [p.outer[0]], center: UnitPoint(x: 0.5, y: 0.66)))
        }
        return AnyShapeStyle(LinearGradient(colors: p.outer, startPoint: p.start, endPoint: p.end))
    }

    var outerColors: [Color] {
        if let v = vigorValue, health != .critical {
            return FlamePalette.outer(vigor: v)
        }
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
        if let v = vigorValue, health != .critical {
            return FlamePalette.inner(vigor: v)
        }
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
        if let v = vigorValue, health != .critical {
            return 0.36 + Double(v) * 0.52
        }
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
        if let activePalette { return activePalette.glow }
        switch health {
        case .dead: return .gray
        case .low: return Color(red: 0.42, green: 0.32, blue: 0.95)
        case .critical: return .red
        default: return .orange
        }
    }

    /// Light and shadow follow the flame's real size so a guttering wisp casts
    /// a small pool of light, not a full-size halo.
    private var lightSpread: CGFloat {
        vigorValue == nil ? 1 : 0.45 + effectiveBodyScale * 0.55
    }

    /// How far the glow sinks toward the base as the flame shrinks. A grounded
    /// flame's light pool follows it down; a centered flame keeps it centered.
    private var glowSink: CGFloat {
        grounded ? (1 - lightSpread) : 0
    }

    private var glowLayer: some View {
        ZStack {
            Circle()
                .fill(glowColor.opacity(effectiveGlowOpacity * 0.45))
                .blur(radius: size * 0.18 * lightSpread)
                .frame(width: size * 1.1 * lightSpread, height: size * 0.92 * lightSpread)
                .offset(y: size * 0.46 * glowSink)
            Circle()
                .fill((activePalette?.core ?? Color.yellow).opacity(health == .dead ? 0 : 0.16 * Double(lightSpread)))
                .blur(radius: size * 0.09)
                .frame(width: size * 0.62 * lightSpread, height: size * 0.62 * lightSpread)
                .offset(y: size * (grounded ? 0.12 : 0) + size * 0.30 * glowSink)
        }
    }

    /// The part of `lift` that is a real hover (legs stand on the floor).
    private var hoverLift: CGFloat { max(0, resolvedLift - resolvedLegLength * effectiveBodyScale) }

    @ViewBuilder
    private var legsLayer: some View {
        let legLength = resolvedLegLength, lift = resolvedLift
        if legLength > 0, health != .dead {
            let colors = activePalette?.outer ?? outerColors
            let upper = colors[max(0, colors.count - 2)], lower = colors[colors.count - 1]
            let rim = activePalette?.rim ?? Color.white.opacity(0.28)
            Canvas { ctx, canvas in
                let u = size * effectiveBodyScale
                let cx = canvas.width / 2
                let bottom = canvas.height - lift * size
                let top = bottom - 0.10 * u
                let ankle = bottom + legLength * u - 0.06 * u
                let thick = 0.10 * u
                let spread = Self.legSpread
                for side in [-1.0, 1.0] as [CGFloat] {
                    let hip = CGPoint(x: cx + side * (spread - 0.025) * u, y: top)
                    let foot = CGPoint(x: cx + side * spread * u, y: ankle)
                    let knee = CGPoint(x: cx + side * (spread + 0.02) * u, y: (top + ankle) / 2)
                    // A little rounded foot, toes out — bare, it reads as
                    // his foot; shod, the shoe covers it.
                    let rimW = max(1.5, size * 0.012)
                    let toe = CGRect(x: foot.x - 0.062 * u + side * 0.022 * u, y: ankle - 0.012 * u, width: 0.124 * u, height: 0.066 * u)
                    ctx.fill(Path(ellipseIn: toe.insetBy(dx: -rimW, dy: -rimW)), with: .color(rim))
                    ctx.fill(Path(ellipseIn: toe), with: .linearGradient(Gradient(colors: [upper, lower]),
                                                                          startPoint: CGPoint(x: 0, y: toe.minY), endPoint: CGPoint(x: 0, y: toe.maxY)))
                    ctx.fill(Path(ellipseIn: CGRect(x: toe.minX + toe.width * 0.22, y: toe.minY + toe.height * 0.14,
                                                     width: toe.width * 0.34, height: toe.height * 0.3)),
                             with: .color(.white.opacity(0.28)))
                    var p = Path()
                    p.move(to: hip)
                    p.addQuadCurve(to: foot, control: knee)
                    ctx.stroke(p, with: .color(rim), style: StrokeStyle(lineWidth: thick + max(1.5, size * 0.012) * 2, lineCap: .round))
                    ctx.stroke(p, with: .linearGradient(Gradient(colors: [upper, lower]), startPoint: CGPoint(x: 0, y: top),
                                                        endPoint: CGPoint(x: 0, y: ankle)),
                               style: StrokeStyle(lineWidth: thick, lineCap: .round))
                    // Lit from the top-left: a soft highlight down the left.
                    var hl = Path()
                    hl.move(to: CGPoint(x: knee.x - thick * 0.28 - side * thick * 0.08, y: bottom + 0.02 * u))
                    hl.addLine(to: CGPoint(x: foot.x - thick * 0.26, y: foot.y - thick * 0.2))
                    ctx.stroke(hl, with: .color(.white.opacity(0.32)), style: StrokeStyle(lineWidth: thick * 0.18, lineCap: .round))
                }
            }
            .frame(width: size, height: size)
            .opacity(activePalette?.bodyOpacity ?? 1)
        }
    }

    @ViewBuilder
    private var groundLayer: some View {
        if grounded {
            VStack {
                Spacer()
                Ellipse()
                    .fill(Color.black.opacity(0.24))
                    .frame(width: size * 0.78 * lightSpread * (1 - min(hoverLift, 0.3) * 1.6),
                           height: size * 0.16 * lightSpread * (1 - min(hoverLift, 0.3) * 1.6))
                    .blur(radius: 3)
                    .offset(y: size * 0.02)
            }
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
                .fill(activePalette?.eye ?? Color(red: 0.20, green: 0.07, blue: 0.04))
                .frame(width: size * 0.12, height: blink ? size * 0.018 : eyeHeight)
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

    /// Wide-open eyes are half of a startled expression, so the happy states
    /// wear theirs a little softer.
    private var eyeHeight: CGFloat {
        switch health {
        case .blazing, .healthy: return size * 0.155
        default: return size * 0.18
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch health {
        case .blazing, .healthy:
            // A grin, not a gasp. This was a plain Capsule TALLER than it was
            // wide, which reads as an "o" of surprise no matter what the rest
            // of the face is doing.
            FlameBuddySmileShape()
                .fill(Color(red: 0.24, green: 0.04, blue: 0.04))
                .frame(width: size * 0.27, height: size * 0.115)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(Color(red: 1.0, green: 0.42, blue: 0.34))
                        .frame(width: size * 0.11, height: size * 0.045)
                }
                .clipShape(FlameBuddySmileShape())
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

/// An open grin: the corners are the highest points, the top lip dips between
/// them, and the bottom rounds out wide. Happy mouths are wider than they are
/// tall — that ratio is what separates a smile from a gasp.
private struct FlameBuddySmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.62)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.maxY + rect.height * 0.34),
            control2: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.maxY + rect.height * 0.34)
        )
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

// MARK: - LIMBS (identical in both FlameBuddyFigure copies — edit one, copy)

extension FlameBuddyFigure {
    /// The mascot's leg length, in body units (`FlameyArt.legLength`).
    static let mascotLegLength: CGFloat = 0.15
}

/// How the Fun mascot's arms are held. ONE arm system: a pose is an angle
/// and a length per arm, hinged at his shoulder, so every change between
/// poses is a ROTATION — transform-only, animatable for free.
enum FlameArmPose: Equatable {
    /// Relaxed at his sides, a little out.
    case rest
    /// Both up: party, the goal cheer.
    case cheer
    /// His right (the viewer's right) arm raised for the high five.
    case highFive
    /// Hands on his cheeks — nervous.
    case cheeks
    /// Tucked in on his tummy — asleep.
    case tucked
    /// Right arm out, holding the treat up.
    case feedOut
    /// Right hand at his mouth.
    case feed
    /// Both up and waving — being tickled (the flail rides `flail:`).
    case flail

    /// (outward angle from straight down in degrees, length scale), for
    /// the viewer-left and viewer-right arm.
    var arms: (left: FlameArmAngle, right: FlameArmAngle) {
        switch self {
        case .rest: return (.init(30, 1), .init(30, 1))
        case .cheer: return (.init(148, 1.02), .init(148, 1.02))
        case .highFive: return (.init(26, 1), .init(168, 1.1))
        case .cheeks: return (.init(-74, 0.74), .init(-74, 0.74))
        case .tucked: return (.init(-38, 0.82), .init(-38, 0.82))
        case .feedOut: return (.init(26, 1), .init(112, 1.05))
        case .feed: return (.init(26, 1), .init(-64, 0.98))
        case .flail: return (.init(122, 1), .init(122, 1))
        }
    }
}

struct FlameArmAngle: Equatable {
    /// Degrees out from straight down; positive swings the hand away from
    /// his body, negative across it.
    var angle: Double
    /// Length relative to the resting arm.
    var length: CGFloat
    init(_ angle: Double, _ length: CGFloat) {
        self.angle = angle
        self.length = length
    }
}

/// An arm reaching a held prop: the hand target in body units from his
/// centre-line and base (y negative is UP), for either side. The wardrobe
/// (`FlameyArt.heldArmTargets`) computes these from the prop, so the prop
/// and the hand holding it are placed by one set of numbers.
struct FlameArmHold: Equatable {
    var left: CGPoint? = nil
    var right: CGPoint? = nil
    /// false = the hand is inside the prop (the foam finger IS a glove).
    var leftHand: Bool = true
    var rightHand: Bool = true
}

/// The Fun mascot's arms, drawn as their own layer so a caller can put them
/// ABOVE his outfit (a hand closes over a prop's handle; capes hang behind).
/// Colours, size, body scale and lift come from the SAME figure value the
/// body is drawn with, so the arms burn down with him through the day.
/// Motion is transform-only: the pose is a rotation about the shoulder
/// (animated by whoever changes it), `sway` is the caller's repeatForever
/// phase flag, `flail` an extra swing in degrees (the tickle wiggle).
struct FlameBuddyArms: View {
    let figure: FlameBuddyFigure
    var pose: FlameArmPose = .rest
    var hold: FlameArmHold? = nil
    var sway: Bool = false
    var flail: Double = 0

    /// Resting arm length and thickness, in body units.
    static let armLength: CGFloat = 0.145
    static let shoulderX: CGFloat = 0.285
    static let shoulderY: CGFloat = -0.27

    /// Below this his arms are drawn a touch shorter and thicker, and still.
    static let compactSize: CGFloat = 60

    private var compact: Bool { figure.size < Self.compactSize }
    private var u: CGFloat { figure.size * figure.effectiveBodyScale }

    /// Where the shoulder sits in the figure's frame (origin at its centre).
    private func shoulder(_ side: CGFloat) -> CGPoint {
        CGPoint(x: side * Self.shoulderX * u,
                y: figure.size / 2 - figure.resolvedLift * figure.size + Self.shoulderY * u)
    }

    /// The angle/length that puts a hand on `target` (body units).
    static func reaching(_ target: CGPoint, side: CGFloat) -> FlameArmAngle {
        let dx = (target.x - side * shoulderX) * side
        let dy = target.y - shoulderY
        let dist = sqrt(dx * dx + dy * dy)
        let angle = atan2(Double(dx), Double(dy)) * 180 / .pi
        return FlameArmAngle(angle, min(1.6, max(0.55, dist / armLength)))
    }

    /// Where a pose puts a hand, in body units (for props that ride it).
    static func hand(for pose: FlameArmPose, side: CGFloat) -> CGPoint {
        let a = side < 0 ? pose.arms.left : pose.arms.right
        let r = a.angle * .pi / 180
        return CGPoint(x: side * (shoulderX + CGFloat(sin(r)) * armLength * a.length),
                       y: shoulderY + CGFloat(cos(r)) * armLength * a.length)
    }

    var body: some View {
        ZStack {
            if figure.health != .dead {
                arm(side: -1)
                arm(side: 1)
            }
        }
        .frame(width: figure.size, height: figure.size)
        .opacity(figure.activePalette?.bodyOpacity ?? 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func angle(side: CGFloat) -> (FlameArmAngle, Bool) {
        if let hold {
            if side < 0, let t = hold.left { return (Self.reaching(t, side: -1), hold.leftHand) }
            // A reaction (high five, feeding) takes the free RIGHT arm even
            // from a two-handed prop.
            if side > 0, let t = hold.right, ![.highFive, .feedOut, .feed, .flail].contains(pose) {
                return (Self.reaching(t, side: 1), hold.rightHand)
            }
        }
        return (side < 0 ? pose.arms.left : pose.arms.right, true)
    }

    @ViewBuilder
    private func arm(side: CGFloat) -> some View {
        let (a, showsHand) = angle(side: side)
        let s = shoulder(side)
        let length = Self.armLength * u * a.length * (compact ? 0.9 : 1)
        let thick = (compact ? 0.11 : 0.098) * u
        let box = (Self.armLength * 1.7 + 0.1) * u * 2
        let swayDeg: Double = compact ? 0 : (sway ? 4 : -2)
        let flailDeg = flail * (side < 0 ? 2.6 : -2.6)
        FlameArmLimb(length: length, thickness: thick, handRadius: showsHand ? (compact ? 0.06 : 0.056) * u : 0,
                     colors: armColors, handColor: handColor, rim: rim, rimWidth: rimWidth, side: side)
            .frame(width: box, height: box)
            .rotationEffect(.degrees(-Double(side) * a.angle + flailDeg))
            .rotationEffect(.degrees(-Double(side) * swayDeg))
            .offset(x: s.x, y: s.y)
    }

    private var bodyColors: [Color] { figure.activePalette?.outer ?? figure.outerColors }
    private var armColors: [Color] {
        let c = bodyColors
        return [c[max(0, c.count - 2)], c[c.count - 1]]
    }
    private var handColor: Color { bodyColors[max(0, bodyColors.count - 2)] }
    private var rim: Color { figure.activePalette?.rim ?? Color.white.opacity(0.30) }
    private var rimWidth: CGFloat { max(1.2, figure.size * 0.011) }
}

/// One stubby arm, drawn pointing straight DOWN from the centre of its frame
/// (the shoulder) — the caller rotates it into its pose. The length is
/// animatable so a pose that shortens the arm eases rather than pops.
struct FlameArmLimb: View, Animatable {
    var length: CGFloat
    let thickness: CGFloat
    let handRadius: CGFloat
    let colors: [Color]
    let handColor: Color
    let rim: Color
    let rimWidth: CGFloat
    let side: CGFloat

    var animatableData: CGFloat {
        get { length }
        set { length = newValue }
    }

    var body: some View {
        Canvas { ctx, canvas in
            let o = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let end = CGPoint(x: o.x, y: o.y + length)
            // A sausage that tapers a little toward the wrist, with a hint
            // of an elbow bend away from his body.
            let bend = -side * thickness * 0.35
            var p = Path()
            p.move(to: o)
            p.addQuadCurve(to: end, control: CGPoint(x: o.x + bend, y: o.y + length * 0.5))
            // The rim only on the part of the arm clear of his body: the
            // root blends into his side instead of reading as a seam.
            ctx.stroke(p.trimmedPath(from: 0.38, to: 1), with: .color(rim),
                       style: StrokeStyle(lineWidth: thickness + rimWidth * 2, lineCap: .round))
            ctx.stroke(p, with: .linearGradient(Gradient(colors: colors), startPoint: o, endPoint: end),
                       style: StrokeStyle(lineWidth: thickness, lineCap: .round))
            // Lit from the top-left, like his legs.
            var hl = Path()
            hl.move(to: CGPoint(x: o.x - thickness * 0.22, y: o.y + thickness * 0.2))
            hl.addQuadCurve(to: CGPoint(x: end.x - thickness * 0.22, y: end.y - thickness * 0.3),
                            control: CGPoint(x: o.x + bend - thickness * 0.22, y: o.y + length * 0.5))
            ctx.stroke(hl, with: .color(.white.opacity(0.26)), style: StrokeStyle(lineWidth: thickness * 0.16, lineCap: .round))
            guard handRadius > 0 else { return }
            // A round mitten with a thumb.
            let r = handRadius
            let hand = Path(ellipseIn: CGRect(x: end.x - r, y: end.y - r, width: r * 2, height: r * 2))
            ctx.fill(hand, with: .color(rim))
            let inner = Path(ellipseIn: CGRect(x: end.x - r + rimWidth, y: end.y - r + rimWidth,
                                               width: (r - rimWidth) * 2, height: (r - rimWidth) * 2))
            ctx.fill(inner, with: .color(handColor))
            ctx.fill(inner, with: .radialGradient(Gradient(colors: [.white.opacity(0.5), .white.opacity(0)]),
                                                  center: CGPoint(x: end.x - r * 0.35, y: end.y - r * 0.35),
                                                  startRadius: 0, endRadius: r * 1.1))
            var thumb = Path()
            thumb.addArc(center: CGPoint(x: end.x + side * r * 0.1, y: end.y - r * 0.05), radius: r * 0.55,
                         startAngle: .degrees(side > 0 ? 200 : -20), endAngle: .degrees(side > 0 ? 290 : -110),
                         clockwise: side < 0)
            ctx.stroke(thumb, with: .color(.black.opacity(0.22)), style: StrokeStyle(lineWidth: max(0.8, r * 0.16), lineCap: .round))
        }
    }
}
