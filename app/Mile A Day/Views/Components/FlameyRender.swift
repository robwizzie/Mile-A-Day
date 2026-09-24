import SwiftUI

// FLAMEY'S WARDROBE — THE VIEWS. BYTE-IDENTICAL in
// app/Mile A Day/Views/Components/ and app/MileADayWidgets/ (see
// FlameyWardrobe.swift). SwiftUI + Foundation only.
//
// Motion rule: no clocks. Everything that moves (the trail's drift, a
// companion's bob, the orbiting embers, the aura's pulse, the heart bopper's
// sway) is ONE `repeatForever` transform or opacity, started once, off the
// appear commit, and never under Reduce Motion or in a still (`still: true`,
// or an `ImageRenderer`, which drives no lifecycle and so never starts it).

// MARK: - The outfit layer

/// Draws a `FlameyLook` on the figure, in `FlameBuddyFigure`'s geometry. ONE
/// layer draws one side of him: `.behind` goes before the figure in the
/// caller's ZStack (aura, halo, back, trail), `.front` after it (feet,
/// costume, chest, eyes, head, held, companion). Reports a `size × size`
/// layout footprint — the drawing overflows it, like the figure's glow — so
/// adding it never moves anything.
struct FlameyOutfitLayer: View {
    enum Side { case behind, front }

    let look: FlameyLook
    let size: CGFloat
    /// The body scale the figure is drawn at right now.
    var scale: CGFloat = 1
    var side: Side = .front
    /// A still frame: share cards, widgets, Reduce Motion.
    var still: Bool = false
    /// How far (in body units) the surface lets him spread sideways — the
    /// hero's column is narrower than a share card. Capes squeeze, the trail
    /// shortens, the companion steps in.
    var reach: CGFloat = 0.9

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    private var moving: Bool { !still && !reduceMotion }
    private var palette: FlameyPalette? { FlameyPalette.palette(for: look.color) }
    private var u: CGFloat { size * scale }
    private var anchors: FlameyArt.Anchors { FlameyArt.anchors(size: size, scale: scale, lift: look.hoverLift) }

    var body: some View {
        ZStack {
            if !look.isPlain {
                switch side {
                case .behind: behind
                case .front: front
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { start() }
        .onChange(of: look) { _, _ in start() }
    }

    /// Idempotent: re-assigning an already-true phase is a no-op, so a
    /// re-fired appear can't stack a second repeat. Off the appear commit —
    /// a repeatForever started inside onAppear attaches to the view's first
    /// transaction (see FlameBuddyView).
    private func start() {
        guard moving, !phase, needsMotion else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { phase = true }
        }
    }

    private var needsMotion: Bool {
        look[.trail] != nil || look[.companion] != nil || look.wears(.heartBopper) || look.glow != .none
    }

    // MARK: Behind

    @ViewBuilder
    private var behind: some View {
        let a = anchors
        let u = self.u
        let reach = self.reach
        let look = self.look
        ZStack {
            glowBehind(a)
            // The trail goes UNDER a cape: both stream to his left, and the
            // cape is the bigger, chosen piece — the trail shows around it.
            if let trail = look[.trail] {
                Canvas { ctx, canvas in
                    ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                    FlameyArt.drawTrail(trail, in: &ctx, a: a, u: u, reach: reach)
                }
                .frame(width: size * 3, height: size * 3)
                // Streaming: drifts back from him and breathes.
                .offset(x: moving && phase ? -0.035 * u : 0)
                .opacity(moving && phase ? 0.78 : 1)
            }
            if let back = look[.back] {
                Canvas { ctx, canvas in
                    ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                    FlameyArt.drawBack(back, in: &ctx, a: a, u: u, reach: reach, glow: look.glow == .wings)
                }
                .frame(width: size * 3, height: size * 3)
            }
        }
    }

    @ViewBuilder
    private func glowBehind(_ a: FlameyArt.Anchors) -> some View {
        let u = self.u
        let centerY = a.bottom - 0.5 * u
        switch look.glow {
        case .colorHalo:
            if let palette {
                if palette.effects.contains(.halo) {
                    FlameyHalo(color: palette.glow, u: u)
                        .offset(y: centerY)
                }
                if palette.effects.contains(.embers) {
                    FlameyOrbitingEmbers(color: palette.glow, u: u, spin: moving && phase)
                        .offset(y: centerY)
                }
            }
        case .aura(let aura):
            switch aura {
            case .spectralGlow:
                FlameBuddyOuterShape(wobble: 0)
                    .fill(FlameyPalette.hex(0x5CFFC8))
                    .frame(width: 0.82 * u * 1.24, height: u * 1.16)
                    .blur(radius: u * 0.07)
                    .opacity(moving && phase ? 0.55 : 0.88)
                    .offset(y: a.bottom - 0.52 * u)
            case .flicker:
                // Afterimages trailing him, flickering like a bad signal.
                ForEach(0..<2, id: \.self) { i in
                    FlameBuddyOuterShape(wobble: 0)
                        .fill(LinearGradient(colors: palette?.outer ?? [.white, .yellow, .orange, FlameyPalette.hex(0xFF3319)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 0.82 * u, height: u)
                        .opacity((i == 0 ? 0.30 : 0.15) * (moving && phase ? 0.45 : 1))
                        .offset(x: -(0.17 + 0.15 * CGFloat(i)) * u, y: a.bottom - 0.5 * u)
                }
            case .spotlight:
                Canvas { ctx, canvas in
                    ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                    let g = a.ground
                    var cone = Path()
                    cone.move(to: CGPoint(x: -0.20 * u, y: g - 1.30 * u))
                    cone.addLine(to: CGPoint(x: 0.04 * u, y: g - 1.30 * u))
                    cone.addLine(to: CGPoint(x: 0.66 * u, y: g + 0.02 * u))
                    cone.addLine(to: CGPoint(x: -0.70 * u, y: g + 0.02 * u))
                    cone.closeSubpath()
                    ctx.fill(cone, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.02), FlameyPalette.hex(0xFFF3C4, 0.36)]),
                                                         startPoint: CGPoint(x: 0, y: g - 1.3 * u), endPoint: CGPoint(x: 0, y: g)))
                    var pool = ctx
                    pool.addFilter(.blur(radius: u * 0.02))
                    pool.fill(Path(ellipseIn: CGRect(x: -0.66 * u, y: g - 0.07 * u, width: 1.32 * u, height: 0.16 * u)),
                              with: .color(FlameyPalette.hex(0xFFF3C4, 0.45)))
                }
                .frame(width: size * 3, height: size * 3)
                .opacity(moving && phase ? 0.8 : 1)
            default:
                EmptyView()
            }
        default:
            EmptyView()
        }
    }

    // MARK: Front

    @ViewBuilder
    private var front: some View {
        let a = anchors
        let u = self.u
        let look = self.look
        let palette = self.palette
        let jets = look.detail == .full
        let reach = self.reach
        ZStack {
            Canvas { ctx, canvas in
                ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                let items = look.frontItems
                for item in items where item.slot == .feet || (item.slot == .costume && item != .astronautHelmet) {
                    FlameyArt.drawFront(item, in: &ctx, a: a, u: u, palette: palette, jets: jets)
                }
                if let back = look[.back] { FlameyArt.drawBackFront(back, in: &ctx, a: a, u: u) }
                for item in items where [.chest, .eyes, .head].contains(item.slot) {
                    FlameyArt.drawFront(item, in: &ctx, a: a, u: u, palette: palette, jets: jets)
                }
                if look.wears(.astronautHelmet) {
                    FlameyArt.drawFront(.astronautHelmet, in: &ctx, a: a, u: u, palette: palette, jets: jets)
                }
                if let held = look[.held] {
                    FlameyArt.drawFront(held, in: &ctx, a: a, u: u, palette: palette, jets: jets, reach: reach)
                }
            }
            .frame(width: size * 3, height: size * 3)

            if look.wears(.heartBopper) {
                Canvas { ctx, canvas in
                    ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                    FlameyArt.drawHeartBopper(in: &ctx, u: u)
                }
                .frame(width: u * 0.5, height: u * 0.5)
                .rotationEffect(.degrees(moving ? (phase ? 7 : -7) : 0), anchor: .center)
                .offset(y: a.topY + 0.03 * u)
            }

            if let companion = look[.companion] {
                // A tight surface (the hero, a stat column just to his right)
                // keeps the companion small and CLOSE: walkers at his feet,
                // floaters up by his shoulder, clear of the numbers.
                let tight = reach < 0.75
                let floats = Self.floats(companion)
                let k: CGFloat = tight ? 0.78 : 1.35
                let x = tight ? (floats ? 0.36 : 0.38) * u : FlameyArt.companionX(u, reach: reach)
                let lift = tight && floats ? -0.42 * u : 0
                Canvas { ctx, canvas in
                    ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                    ctx.translateBy(x: 0, y: a.ground); ctx.scaleBy(x: k, y: k); ctx.translateBy(x: 0, y: -a.ground)
                    FlameyArt.drawCompanion(companion, in: &ctx, a: a, u: u, palette: palette)
                }
                .frame(width: size * 1.6, height: size * 3)
                // Floaters bob; walkers bounce a little.
                .offset(x: x, y: lift + (moving && phase ? -(floats ? 0.05 : 0.02) * u : 0))
            }

            if look.glow == .aura(.paparazzi) {
                FlameyPaparazzi(u: u, flash: moving && phase)
                    .offset(y: a.bottom - 0.5 * u)
            }
        }
    }

    static func floats(_ companion: FlameyItem) -> Bool {
        switch companion {
        case .spark, .sparkTrio, .firefly, .lantern, .friendlyGhost: return true
        default: return false
        }
    }
}

// MARK: - Halo-class effects

/// The legendary colours' halo: a soft disc of their glow and a thin ring
/// that catches the light. Static: the ring is what reads, not its motion.
struct FlameyHalo: View {
    let color: Color
    let u: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.40), color.opacity(0)], center: .center,
                                     startRadius: u * 0.22, endRadius: u * 0.64))
                .frame(width: u * 1.45, height: u * 1.45)
            Circle()
                .strokeBorder(AngularGradient(colors: [color.opacity(0.7), .white.opacity(0.75), color.opacity(0.15),
                                                       .white.opacity(0.85), color.opacity(0.7)], center: .center),
                              lineWidth: max(1.5, u * 0.012))
                .frame(width: u * 1.10, height: u * 1.10)
                .blur(radius: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// Gold and Eternal: embers circling him on a tilted ring. Each ember is a
/// round dot moved along an ellipse by an animatable offset (a transform —
/// no clock), so the dots stay dots instead of being squashed into dashes.
struct FlameyOrbitingEmbers: View {
    let color: Color
    let u: CGFloat
    let spin: Bool

    var body: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                let r = u * (0.03 - 0.003 * CGFloat(i % 3))
                Circle()
                    .fill(RadialGradient(colors: [.white, color, color.opacity(0)], center: .center, startRadius: 0, endRadius: r * 1.6))
                    .frame(width: r * 3.2, height: r * 3.2)
                    .modifier(FlameyOrbit(angle: Double(i) / 7 * 2 * .pi + (spin ? 2 * .pi : 0),
                                          rx: u * 0.62, ry: u * 0.2))
            }
        }
        .animation(spin ? .linear(duration: 9).repeatForever(autoreverses: false) : nil, value: spin)
        .allowsHitTesting(false)
    }
}

/// Places a view on an ellipse at `angle`; animating the angle walks it
/// round the ring. Behind him on the far side, a touch dimmer.
struct FlameyOrbit: GeometryEffect {
    var angle: Double
    let rx: CGFloat
    let ry: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: CGFloat(cos(angle)) * rx, y: CGFloat(sin(angle)) * ry))
    }
}

/// Paparazzi: camera flashes popping around him.
struct FlameyPaparazzi: View {
    let u: CGFloat
    let flash: Bool

    private static let flashes: [(CGFloat, CGFloat, CGFloat, Int)] = [
        (-0.64, -0.16, 1.0, 0), (0.62, -0.40, 0.8, 1), (0.70, 0.16, 0.6, 0), (-0.54, -0.60, 0.55, 1), (0.30, -0.78, 0.45, 0)]

    var body: some View {
        ZStack {
            ForEach(0..<Self.flashes.count, id: \.self) { i in
                let f = Self.flashes[i]
                Canvas { ctx, canvas in
                    let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                    let R = f.2 * u * 0.16
                    var g = ctx
                    g.addFilter(.blur(radius: R * 0.25))
                    g.fill(Path(ellipseIn: CGRect(x: c.x - R * 0.7, y: c.y - R * 0.7, width: R * 1.4, height: R * 1.4)),
                           with: .color(Color.white.opacity(0.55)))
                    ctx.fill(FlameyArt.star(c.x, c.y, R, inner: 0.14, points: 4), with: .color(.white))
                    var s2 = ctx
                    s2.translateBy(x: c.x, y: c.y)
                    s2.rotate(by: .degrees(45))
                    s2.fill(FlameyArt.star(0, 0, R * 0.55, inner: 0.16, points: 4), with: .color(FlameyPalette.hex(0xFFF6C8)))
                }
                .frame(width: u * 0.4, height: u * 0.4)
                .opacity(flash ? (f.3 == 0 ? 0.25 : 1) : (f.3 == 0 ? 1 : 0.55))
                .offset(x: f.0 * u, y: f.1 * u)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - The dressed figure, still (widgets, Live Activity)

/// The whole dressed Flamey as ONE static view — for surfaces that render
/// statically (the flame widget, the Live Activity). Behind + figure + front,
/// the figure in his colour and hovering when the look says so.
struct FlameyDressedFigure: View {
    let look: FlameyLook
    let health: FlameHealth
    let size: CGFloat
    var vigor: CGFloat? = nil
    /// The scale the figure draws at (its effective body scale).
    var scale: CGFloat

    var body: some View {
        ZStack {
            FlameyOutfitLayer(look: look, size: size, scale: scale, side: .behind, still: true)
            FlameBuddyFigure(health: health, size: size, showsFace: !look.wears(.ghostSheet), vigor: vigor,
                             grounded: true, palette: health == .dead ? nil : FlameyPalette.palette(for: look.color),
                             lift: look.hoverLift * scale)
            FlameyOutfitLayer(look: look, size: size, scale: scale, side: .front, still: true)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Speech bubbles

/// His speech bubble in a wardrobe style. The CLASSIC bubble is drawn by the
/// caller (FlameMoodLayer's own, unchanged); this draws the other four, at
/// the same footprint so a style never moves the bubble.
struct FlameyStyledBubble: View {
    let text: String
    let style: FlameyItem
    let size: CGFloat

    private var fontSize: CGFloat { max(10, size * 0.07) }
    private var maxWidth: CGFloat { size * 0.78 }
    private var tail: CGFloat { max(5, size * 0.045) }

    var body: some View {
        switch style {
        case .comic: comic
        case .neon: neon
        case .pixel: pixel
        case .goldBubble: gold
        default: EmptyView()
        }
    }

    private func label(_ font: Font, ink: Color) -> some View {
        Text(text)
            .font(font)
            .foregroundColor(ink)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: maxWidth)
            .padding(.horizontal, size * 0.055)
            .padding(.vertical, size * 0.03)
            .padding(.bottom, tail)
    }

    private var comic: some View {
        let shape = FlameyBubbleShape(cornerRadius: size * 0.08, tailHeight: tail, tailWidth: tail * 1.7)
        return label(.system(size: fontSize * 1.05, weight: .black, design: .default).italic(), ink: .black)
            .background(
                ZStack {
                    shape.fill(Color.white)
                    FlameyHalftone().clipShape(shape).opacity(0.16)
                    shape.stroke(Color.black, lineWidth: max(1.5, size * 0.012))
                }
                .background(shape.fill(FlameyPalette.hex(0xFFD21F)).offset(x: size * 0.016, y: size * 0.016))
            )
            .rotationEffect(.degrees(-4))
    }

    private var neon: some View {
        let shape = FlameyBubbleShape(cornerRadius: size * 0.07, tailHeight: tail, tailWidth: tail * 1.7)
        return label(.system(size: fontSize, weight: .bold, design: .rounded), ink: FlameyPalette.hex(0xC8FFFD))
            .shadow(color: FlameyPalette.hex(0x3DF5FF), radius: 3)
            .background(
                ZStack {
                    shape.fill(FlameyPalette.hex(0x140A24, 0.94))
                    shape.stroke(FlameyPalette.hex(0xFF4FD8), lineWidth: max(1.5, size * 0.011))
                        .shadow(color: FlameyPalette.hex(0xFF4FD8), radius: 4)
                }
            )
    }

    /// 8-bit: a stepped NES-blue box, a black pixel border, a hard yellow
    /// drop shadow, and BIG white lettering — readable, not a tiny mono font.
    private var pixel: some View {
        let step = max(2, size * 0.018)
        let shape = FlameyPixelBubbleShape(step: step, tailHeight: tail)
        return label(.system(size: fontSize * 1.02, weight: .black, design: .rounded), ink: .white)
            .textCase(.uppercase)
            .shadow(color: FlameyPalette.hex(0x001A70), radius: 0, x: step * 0.6, y: step * 0.6)
            .background(
                ZStack {
                    shape.fill(FlameyPalette.hex(0xF8B800)).offset(x: step, y: step)
                    shape.fill(FlameyPalette.hex(0x0058F8))
                    shape.stroke(Color.black, lineWidth: step * 0.9)
                    // A two-pixel highlight in the top-left corner.
                    Rectangle().fill(FlameyPalette.hex(0x3CBCFC))
                        .frame(width: step * 2, height: step)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, step * 2).padding(.top, step * 1.4)
                }
            )
    }

    private var gold: some View {
        let shape = FlameyBubbleShape(cornerRadius: size * 0.08, tailHeight: tail, tailWidth: tail * 1.7)
        return label(.system(size: fontSize, weight: .heavy, design: .serif), ink: FlameyPalette.hex(0x4A2A00))
            .background(
                ZStack {
                    shape.fill(LinearGradient(colors: [FlameyPalette.hex(0xFFF3B0), FlameyPalette.hex(0xFFD24A), FlameyPalette.hex(0xE0A512)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                    shape.stroke(FlameyPalette.hex(0xA86F00), lineWidth: max(1.5, size * 0.01))
                }
                .shadow(color: FlameyPalette.hex(0xFFC83A, 0.7), radius: 5)
            )
            .overlay(alignment: .topTrailing) {
                Canvas { ctx, canvas in
                    let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                    ctx.fill(FlameyArt.star(c.x, c.y, canvas.width / 2, inner: 0.22, points: 4), with: .color(.white))
                }
                .frame(width: fontSize * 0.9, height: fontSize * 0.9)
                .offset(x: fontSize * 0.35, y: -fontSize * 0.4)
            }
            .rotationEffect(.degrees(-2))
    }
}

/// A rounded bubble with a tail off its bottom edge, just right of centre.
struct FlameyBubbleShape: Shape {
    let cornerRadius: CGFloat
    let tailHeight: CGFloat
    let tailWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailHeight)
        var path = Path(roundedRect: body, cornerRadius: min(cornerRadius, body.height / 2), style: .continuous)
        let tailX = body.minX + body.width * 0.58
        var tailPath = Path()
        tailPath.move(to: CGPoint(x: tailX - tailWidth * 0.5, y: body.maxY - 1))
        tailPath.addLine(to: CGPoint(x: tailX + tailWidth * 0.5, y: body.maxY - 1))
        tailPath.addLine(to: CGPoint(x: tailX + tailWidth * 0.12, y: rect.maxY))
        tailPath.closeSubpath()
        path.addPath(tailPath)
        return path
    }
}

/// The 8-bit bubble: corners stepped in pixels, a stepped tail.
struct FlameyPixelBubbleShape: Shape {
    let step: CGFloat
    let tailHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        let s = step
        let b = rect.maxY - tailHeight
        let tx = rect.minX + rect.width * 0.58
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + s * 2, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - s * 2, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - s * 2, y: rect.minY + s))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s * 2))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + s * 2))
        p.addLine(to: CGPoint(x: rect.maxX, y: b - s * 2))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: b - s * 2))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: b - s))
        p.addLine(to: CGPoint(x: rect.maxX - s * 2, y: b - s))
        p.addLine(to: CGPoint(x: rect.maxX - s * 2, y: b))
        p.addLine(to: CGPoint(x: tx + s * 2, y: b))
        p.addLine(to: CGPoint(x: tx + s * 2, y: b + (rect.maxY - b) * 0.5))
        p.addLine(to: CGPoint(x: tx + s, y: b + (rect.maxY - b) * 0.5))
        p.addLine(to: CGPoint(x: tx + s, y: rect.maxY))
        p.addLine(to: CGPoint(x: tx - s, y: rect.maxY))
        p.addLine(to: CGPoint(x: tx - s, y: b))
        p.addLine(to: CGPoint(x: rect.minX + s * 2, y: b))
        p.addLine(to: CGPoint(x: rect.minX + s * 2, y: b - s))
        p.addLine(to: CGPoint(x: rect.minX + s, y: b - s))
        p.addLine(to: CGPoint(x: rect.minX + s, y: b - s * 2))
        p.addLine(to: CGPoint(x: rect.minX, y: b - s * 2))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + s * 2))
        p.addLine(to: CGPoint(x: rect.minX + s, y: rect.minY + s * 2))
        p.addLine(to: CGPoint(x: rect.minX + s, y: rect.minY + s))
        p.addLine(to: CGPoint(x: rect.minX + s * 2, y: rect.minY + s))
        p.closeSubpath()
        return p
    }
}

/// Comic halftone, heavier toward the right edge.
struct FlameyHalftone: View {
    var body: some View {
        Canvas { ctx, c in
            let step: CGFloat = 5
            var y: CGFloat = 0
            var row = 0
            while y < c.height {
                var x: CGFloat = row % 2 == 0 ? 0 : step / 2
                while x < c.width {
                    let r = 1.3 * (x / max(1, c.width))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.black))
                    x += step
                }
                y += step * 0.86
                row += 1
            }
        }
    }
}
