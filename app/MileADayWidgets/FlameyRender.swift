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
    /// Flamey's arm pose right now — Flamey Jr. copies it (arms and face).
    var companionPose: FlameArmPose = .rest

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false
    /// The held prop's own beat (a flag waves faster than a trail drifts).
    @State private var heldPhase = false

    private var moving: Bool { !still && !reduceMotion }
    private var palette: FlameyPalette? { FlameyPalette.palette(for: look.color) }
    private var u: CGFloat { size * scale }
    private var anchors: FlameyArt.Anchors { FlameyArt.anchors(size: size, scale: scale, lift: look.hoverLift, stand: look.standLift) }

    var body: some View {
        ZStack {
            if !look.isPlain {
                switch side {
                case .behind: behind
                case .front: front
                }
            }
        }
        .mask { tightMask }
        .mask { tightTopMask }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { start() }
        .onChange(of: look) { old, new in
            if old[.held] != new[.held] { restartHeld() } else { start() }
        }
    }

    /// Idempotent: re-assigning an already-true phase is a no-op, so a
    /// re-fired appear can't stack a second repeat. Off the appear commit —
    /// a repeatForever started inside onAppear attaches to the view's first
    /// transaction (see FlameBuddyView).
    private func start() {
        guard moving else { return }
        if !phase, needsMotion {
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { phase = true }
            }
        }
        if !heldPhase, let held = look[.held] {
            let period = FlameyArt.heldMotion(held).period
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) { heldPhase = true }
            }
        }
    }

    /// A new prop is a new tempo: land the beat without animation, then
    /// start it again (re-assigning an at-target phase keeps the old timing).
    private func restartHeld() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { heldPhase = false }
        DispatchQueue.main.async { start() }
    }

    private var tight: Bool { FlameyArt.isTight(reach) }

    /// On a tight surface (the hero's column) NOTHING he wears may cross the
    /// card edge or the stat column. The art is fitted to stay inside; this
    /// is the guarantee — a band exactly as wide as his room, its edges
    /// feathered so anything that still reaches them fades instead of being
    /// cut. Unbounded vertically. Elsewhere it's a plain full mask.
    @ViewBuilder
    private var tightMask: some View {
        if tight {
            let bounds = FlameyArt.tightMaskBounds
            let width = (bounds.right - bounds.left) * size
            let feather = min(0.5, 0.022 / (bounds.right - bounds.left))
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: feather),
                                   .init(color: .black, location: 1 - feather), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: width, height: size * 4)
                .offset(x: (bounds.left + bounds.right) / 2 * size)
                .frame(width: size, height: size)
        } else {
            Color.black.frame(width: size * 4, height: size * 4).frame(width: size, height: size)
        }
    }

    /// ...and nothing may leave the card's TOP edge (a banner's pole, a
    /// camera flash). A hard edge: anything reaching it is fitted first.
    @ViewBuilder
    private var tightTopMask: some View {
        if tight {
            let top = FlameyArt.tightTopBound(for: look, scale: scale)
            VStack(spacing: 0) {
                Color.clear.frame(height: max(0, (top + 2) * size))
                Color.black.frame(height: size * 4)
            }
            .frame(width: size * 4, height: size * 4, alignment: .top)
            .offset(y: 0)
            .frame(width: size, height: size)
        } else {
            Color.black.frame(width: size * 4, height: size * 4).frame(width: size, height: size)
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
                    // A tight surface shortens the stream so it only peeks
                    // out from behind him.
                    if FlameyArt.isTight(reach) { ctx.scaleBy(x: FlameyArt.trailTuck, y: 1) }
                    // ...and a busy look (cape + prop) shortens it a touch.
                    ctx.scaleBy(x: FlameyArt.trailScale(for: look), y: 1)
                    FlameyArt.drawTrail(trail, in: &ctx, a: a, u: u, reach: reach,
                                        low: look[.back].map(FlameyArt.isCape) ?? false)
                }
                .frame(width: size * 3, height: size * 3)
                // Streaming: drifts back from him and breathes.
                .offset(x: moving && phase ? -(tight ? 0.015 : 0.035) * u : 0)
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
                        .offset(x: -(tight ? 0.05 + 0.04 * CGFloat(i) : 0.17 + 0.15 * CGFloat(i)) * u, y: a.bottom - 0.5 * u)
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
                .scaleEffect(x: tight ? 0.66 : 1, y: 1)
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
            }
            .frame(width: size * 3, height: size * 3)

            if let held = look[.held] {
                heldProp(held, a: a)
            }

            if look.wears(.heartBopper) {
                // The band sits still on his head; only the springs sway.
                let seat = a.topY + FlameyArt.bopperSeat * u
                Canvas { ctx, canvas in
                    ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                    FlameyArt.drawHeartBopperBand(in: &ctx, u: u)
                }
                .frame(width: u * 0.6, height: u * 0.6)
                .offset(y: seat)
                Canvas { ctx, canvas in
                    ctx.translateBy(x: canvas.width / 2, y: canvas.height - 0.05 * u)
                    FlameyArt.drawHeartBopper(in: &ctx, u: u)
                }
                .frame(width: u * 0.7, height: u * 0.7)
                .rotationEffect(.degrees(moving ? (phase ? 6 : -6) : 0), anchor: .bottom)
                .offset(y: seat - u * 0.30)
            }

            if let companion = look[.companion] {
                // A tight surface (the hero, a stat column just to his right)
                // keeps the companion small and CLOSE: walkers in front of
                // his feet, floaters up by his shoulder — inside his own
                // column, clear of the numbers.
                let tight = self.tight
                let floats = Self.floats(companion)
                let k: CGFloat = tight ? 0.60 : FlameyArt.companionScale(for: look)
                let x = tight ? (floats ? 0.30 : 0.26) * u : FlameyArt.companionX(u, reach: reach, look: look)
                let lift = tight && floats ? -0.42 * u : 0
                if !(tight && floats) {
                    // Its shadow stays on the floor while it bobs.
                    Canvas { ctx, canvas in
                        ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                        ctx.translateBy(x: 0, y: a.ground); ctx.scaleBy(x: k, y: k); ctx.translateBy(x: 0, y: -a.ground)
                        FlameyArt.drawCompanionShadow(companion, in: &ctx, a: a, u: u, floats: floats)
                    }
                    .frame(width: size * 1.6, height: size * 3)
                    .offset(x: x)
                }
                Canvas { ctx, canvas in
                    ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                    ctx.translateBy(x: 0, y: a.ground); ctx.scaleBy(x: k, y: k); ctx.translateBy(x: 0, y: -a.ground)
                    FlameyArt.drawCompanion(companion, in: &ctx, a: a, u: u, palette: palette, pose: companionPose)
                }
                .frame(width: size * 1.6, height: size * 3)
                // Floaters bob; walkers bounce a little.
                .offset(x: x, y: lift + (moving && phase ? -(floats ? 0.05 : 0.02) * u : 0))
            }

            if look.glow == .aura(.paparazzi) {
                FlameyPaparazzi(u: u, flash: moving && phase, spread: tight ? 0.56 : 1, rise: tight ? 0.78 : 1)
                    .offset(y: a.bottom - 0.5 * u)
            }
        }
    }

    /// What he holds, in its own two layers so it can MOVE without a clock
    /// (see `FlameyArt.HeldMotion`): the prop swings about his fist as one
    /// piece — the handle turns inside the hand the arms layer closes over
    /// it — and its accent (the flag's cloth, the sweep hand, the sound
    /// rings, the burst) moves about its own pivot. Both ride `heldPhase`,
    /// one `repeatForever` at the prop's own tempo; a still draws phase 0.
    @ViewBuilder
    private func heldProp(_ item: FlameyItem, a: FlameyArt.Anchors) -> some View {
        let u = self.u
        let reach = self.reach
        let motion = FlameyArt.heldMotion(item)
        let on = moving && heldPhase
        let grip = unitPoint(FlameyArt.heldPoint(item, FlameyArt.heldGrip(item), a: a, u: u, reach: reach))
        let accentAt = FlameyArt.heldAccentPivot(item).map { unitPoint(FlameyArt.heldPoint(item, $0, a: a, u: u, reach: reach)) }
        ZStack {
            Canvas { ctx, canvas in
                ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                FlameyArt.applyHeldTight(item, &ctx, a: a, u: u, reach: reach)
                FlameyArt.held(item, &ctx, a, u, layer: .body)
            }
            .frame(width: size * 3, height: size * 3)
            if let accentAt {
                Canvas { ctx, canvas in
                    ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                    FlameyArt.applyHeldTight(item, &ctx, a: a, u: u, reach: reach)
                    FlameyArt.held(item, &ctx, a, u, layer: .accent)
                }
                .frame(width: size * 3, height: size * 3)
                .modifier(FlameyHeldAccent(kind: moving ? motion.accent : .none, on: on, anchor: accentAt))
            }
        }
        // Pom-poms shake (a quick pump up and out) rather than swing.
        .scaleEffect(item == .pomPoms && on ? 1.07 : 1, anchor: grip)
        .offset(y: item == .pomPoms && on ? -0.012 * u : 0)
        // A still (widget, share card, Reduce Motion) draws the prop at rest.
        .rotationEffect(.degrees(!moving ? 0 : (on ? motion.wobble : -motion.wobble * 0.35)), anchor: grip)
    }

    /// A point in the outfit canvas (origin at his square's centre) as a
    /// UnitPoint of the 3×size canvas the props are drawn in.
    private func unitPoint(_ p: CGPoint) -> UnitPoint {
        UnitPoint(x: (1.5 * size + p.x) / (3 * size), y: (1.5 * size + p.y) / (3 * size))
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
    /// Horizontal spread (a tight surface pulls the flashes in).
    var spread: CGFloat = 1
    /// Vertical spread (a tight surface keeps the top flash on the card).
    var rise: CGFloat = 1

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
                .offset(x: f.0 * spread * u, y: f.1 * rise * u)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - The dressed figure, still (widgets, Live Activity)

/// The whole dressed Flamey as ONE static view — for surfaces that render
/// statically (the flame widget, the Live Activity). Behind + figure + front,
/// the figure in his colour and hovering when the look says so.
///
/// `mood` makes it the SAME Flamey the Fun hero is drawing: his eyes shut
/// when that mood sleeps, his arms in its pose, and its props (zzz, sweat
/// drop, sparkles, confetti) in their still frame — every piece of that from
/// FlameyMoodCore.swift, the code the hero itself calls. Pass the look
/// resolved WITH `mood.props` (nightcap / shades / party hat) so the head is
/// dressed by the look, never twice.
struct FlameyDressedFigure: View {
    let look: FlameyLook
    let health: FlameHealth
    let size: CGFloat
    var vigor: CGFloat? = nil
    /// The scale the figure draws at (its effective body scale).
    var scale: CGFloat
    /// How his arms are held; nil = the mood's pose (`.rest` without one).
    var arms: FlameArmPose? = nil
    var mood: FlameMoodKind? = nil

    var body: some View {
        let asleep = mood?.eyesShut() ?? false
        let pose = arms ?? mood?.armPose(eyesShut: asleep) ?? .rest
        ZStack {
            FlameyDressedBody(look: look, arms: pose,
                              figure: FlameyDressedBody.figure(look: look, health: health, size: size, vigor: vigor,
                                                               scale: scale, asleep: asleep))
            if let mood {
                FlameMoodProps(kind: mood, eyesShut: asleep, size: size, scale: scale, still: true,
                               drawsWornProps: false, lift: look.bodyLift * scale, peak: true)
            }
        }
        // A compact surface (widget, Live Activity) was fitted to him
        // before he had legs: there he stands the same height as ever.
        .scaleEffect(look.detail == .compact ? 1 / (1 + look.standLift) : 1, anchor: .bottom)
        .frame(width: size, height: size)
    }
}

/// The ONE dressed stack every Flamey surface draws — behind layer, the
/// figure, anything ON his skin, front layer, anything in his hand, then his
/// arms over it — around a figure the CALLER builds. That is what lets a
/// surface with figure knobs only the app has (the celebration's blaze, the
/// treats card's belly, the reignite's flicker) still wear exactly the look
/// the hero wears: the look owns the colour (`palette`), the legs
/// (`legLength`) and the lift, so the caller builds its figure through
/// `figure(look:…)` or passes those same three values. `skin` sits right on
/// the body, UNDER the outfit (the treats card's blush and full tummy — a bow
/// tie goes over a belly, not under it); `prop` sits between the outfit and
/// the arms, so a hand closes OVER whatever the surface puts in it.
struct FlameyDressedBody<Skin: View, Prop: View>: View {
    let look: FlameyLook
    var arms: FlameArmPose = .rest
    /// Where each hand goes, overriding the look's own held prop (nil = the
    /// look's `armHold`).
    var hold: FlameArmHold? = nil
    var reach: CGFloat = 0.9
    var still: Bool = true
    let figure: FlameBuddyFigure
    var skin: Skin
    var prop: Prop

    init(look: FlameyLook, arms: FlameArmPose = .rest, hold: FlameArmHold? = nil, reach: CGFloat = 0.9,
         still: Bool = true, figure: FlameBuddyFigure, @ViewBuilder skin: () -> Skin, @ViewBuilder prop: () -> Prop) {
        self.look = look
        self.arms = arms
        self.hold = hold
        self.reach = reach
        self.still = still
        self.figure = figure
        self.skin = skin()
        self.prop = prop()
    }

    var body: some View {
        let scale = figure.effectiveBodyScale
        return ZStack {
            FlameyOutfitLayer(look: look, size: figure.size, scale: scale, side: .behind, still: still, reach: reach)
            figure
            skin
            FlameyOutfitLayer(look: look, size: figure.size, scale: scale, side: .front, still: still, reach: reach,
                              companionPose: arms)
            prop
            if look.showsArms {
                FlameBuddyArms(figure: figure, pose: arms, hold: hold ?? look.armHold(reach: reach))
            }
        }
        .frame(width: figure.size, height: figure.size)
    }
}

extension FlameyDressedBody where Skin == EmptyView {
    init(look: FlameyLook, arms: FlameArmPose = .rest, hold: FlameArmHold? = nil, reach: CGFloat = 0.9,
         still: Bool = true, figure: FlameBuddyFigure, @ViewBuilder prop: () -> Prop) {
        self.init(look: look, arms: arms, hold: hold, reach: reach, still: still, figure: figure,
                  skin: { EmptyView() }, prop: prop)
    }
}

extension FlameyDressedBody where Skin == EmptyView, Prop == EmptyView {
    init(look: FlameyLook, arms: FlameArmPose = .rest, hold: FlameArmHold? = nil, reach: CGFloat = 0.9,
         still: Bool = true, figure: FlameBuddyFigure) {
        self.init(look: look, arms: arms, hold: hold, reach: reach, still: still, figure: figure,
                  skin: { EmptyView() }, prop: { EmptyView() })
    }

    /// A figure dressed in `look`: his colour, his legs, his lift.
    static func figure(look: FlameyLook, health: FlameHealth, size: CGFloat, flickerPhase: CGFloat = 0,
                       blink: Bool = false, vigor: CGFloat? = nil, scale: CGFloat,
                       asleep: Bool = false) -> FlameBuddyFigure {
        FlameBuddyFigure(health: health, flickerPhase: flickerPhase, blink: blink, size: size,
                         showsFace: !look.wears(.ghostSheet), vigor: vigor, asleep: asleep, grounded: true,
                         palette: health == .dead ? nil : FlameyPalette.palette(for: look.color),
                         lift: look.bodyLift * scale, legLength: look.standLift)
    }
}

extension FlameyLook {
    /// This look with `slots` taken off — what a scene with props of its
    /// own (the treats card's treat and empties, the injured buddy's
    /// crutches and head wrap) dresses him in: everything that is HIM, none
    /// of what would stand where the scene's props already are.
    func trimmed(removing slots: [FlameySlot]) -> FlameyLook {
        var l = self
        for slot in slots { l.takeOff(slot) }
        switch l.glow {
        case .aura where l[.aura] == nil: l.glow = .none
        case .wings where !l.wears(.goldenWings): l.glow = .none
        default: break
        }
        return l
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
    /// Width cap as a fraction of `size` (the hero passes less).
    var widthFraction: CGFloat = 0.78

    private var fontSize: CGFloat { max(10, size * 0.07) }
    private var maxWidth: CGFloat { size * widthFraction }
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

/// The held prop's accent motion: the flag's cloth flutters about the pole
/// top, the stopwatch hand sweeps round, the megaphone's rings pulse out of
/// the bell, the cannon's burst blooms from the muzzle. Transform/opacity
/// only, about `anchor`, on the prop's `heldPhase`.
struct FlameyHeldAccent: ViewModifier {
    let kind: FlameyArt.HeldMotion.Accent
    let on: Bool
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        switch kind {
        case .flutter:
            content.scaleEffect(x: on ? 0.9 : 1.02, y: on ? 1.04 : 0.98, anchor: anchor)
        case .sweep:
            content.rotationEffect(.degrees(on ? 150 : 0), anchor: anchor)
        case .pulse:
            content.scaleEffect(on ? 1.14 : 0.9, anchor: anchor).opacity(on ? 0.55 : 1)
        case .burst:
            content.scaleEffect(on ? 1.1 : 0.92, anchor: anchor).opacity(on ? 0.8 : 1)
        case .none:
            content
        }
    }
}
