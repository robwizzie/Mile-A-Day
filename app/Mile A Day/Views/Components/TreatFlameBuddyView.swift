import SwiftUI

/// Flamey enjoying what your miles earned: tipsy on wine or beer, stuffed on
/// burgers, pizza or donuts, wired on lattes — the more units, the more so.
/// He is having a GREAT time on all three: the grin is the face he wears
/// whenever there's something to enjoy.
///
/// EARNED semantics, so the scene tells the same story as the number: the
/// unit in his hand FILLS as you earn it (a 0.4-glass day is a glass 40%
/// full), whole units already earned are the empties on the ground, and a
/// day with nothing earned is its own reaction — an upside-down glass, a
/// clean plate, a "waiting" face and an "earn it!" bubble — never a flame
/// holding a full glass doing nothing.
///
/// A SIBLING of `InjuredFlameBuddyView`, built the same way: the body is the
/// REAL `FlameBuddyFigure` (never a redrawn lookalike), rendered ONCE with a
/// fixed `flickerPhase`, and everything that moves is a transform under
/// `repeatForever`. No `TimelineView`, no per-frame redraw of shadowed
/// content (ios.md); the candle-like "flicker" is a y-scale breath for the
/// same reason. `startMotion` is idempotent (re-assigning an at-target phase
/// is a no-op): it runs on appear and whenever the level crosses a gag's
/// threshold, because the count usually arrives a beat after the view.
/// Callers `.id(model.sceneKey)` the view — a new treat, or a flip between
/// empty and earned, is a NEW set of timings and must start clean.
///
/// The belly is an OVERLAY — a round tummy with a highlight and a belly
/// button, grown with the level — not a wider silhouette, which read as a
/// bigger flame. `bellyBulge` on the shape is kept to a hint.
///
/// GEOMETRY is the injured buddy's: props live in a 130 × 116 design space
/// (this view's own frame in units where `size` = 100), the body frame is
/// `figureSize * 0.82` wide, scaled by `flameScale(vigor:)` about its bottom
/// edge — see `bodyRect`. Vigor varies with the level, so face landmarks are
/// derived from `scale`.
///
/// Cartoon only, by design and by App Review (1.4.3): blush, sway, a "hic!"
/// and a lampshade — never sick, never passed out.
struct TreatFlameBuddyView: View {
    var size: CGFloat = 170
    let treat: CalorieTreat
    let count: Double
    /// Finished frame (Reduce Motion, snapshots): nothing is animated.
    var still: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // One phase per motion, each flipped once under its own repeatForever.
    @State private var breathe = false
    @State private var sway = false
    @State private var stumble = false
    @State private var bob = false
    @State private var sip = false
    @State private var jiggle = false
    @State private var dash = false
    @State private var pop = false
    @State private var steam = false

    private var level: Double { CalorieTreat.level(for: count) }
    private var effect: TreatEffect { treat.effect }
    private var isEmpty: Bool { count <= 0.0001 }
    private var figureSize: CGFloat { size * 0.86 }
    private var containerSize: CGSize { CGSize(width: size * 1.30, height: size * 1.16) }
    private var animate: Bool { !still && !reduceMotion }
    private var whole: Int { Int(max(0, count).rounded(.down)) }
    private var fraction: Double { max(0, count) - Double(whole) }
    /// The unit in hand fills as it's earned; a whole count means the last
    /// one is in hand, full, about to be enjoyed.
    private var heldFill: Double {
        if fraction > 0 { return fraction }
        return whole > 0 ? 1 : 0
    }
    /// Units already enjoyed — on the ground.
    private var empties: Int { fraction > 0 ? whole : max(0, whole - 1) }
    /// Level, bucketed: a change re-runs `startMotion` so a gag whose
    /// threshold a late-arriving count crossed still starts.
    private var motionKey: Int { Int(level * 20) }

    // MARK: Figure knobs

    private var health: FlameHealth {
        // The grin whenever there's something to enjoy; the flat mouth is the
        // "waiting" face for an empty day. Both honour `vigor`, so neither
        // wears a dull stage colour.
        isEmpty ? .dimming : .healthy
    }

    private var vigor: CGFloat {
        switch effect {
        case .tipsy: return 1 - 0.22 * CGFloat(level) // ≥ 0.78: never smaller than the injured buddy
        case .stuffed: return 0.92
        case .wired: return 1.0
        }
    }

    private var blink: Bool { effect == .tipsy && level >= 0.6 }
    /// The outline's paunch (FlameBuddyOuterShape) — the tummy overlay sits
    /// inside it, clipped to it.
    private var bellyBulge: CGFloat { effect == .stuffed ? CGFloat(level) : 0 }
    private var scale: CGFloat { StreakFlameClock.flameScale(vigor: Double(vigor)) }

    // Face landmarks in design units, from the figure's own layout: the face
    // sits 0.18·size below the figure's centre inside a group scaled about its
    // bottom, and the mouth 0.13·size below that.
    private var bodyTopY: CGFloat { 101 - 86 * scale }
    private var faceY: CGFloat { 101 - 27.5 * scale }
    private var mouthY: CGFloat { faceY + 11.2 * scale }

    // MARK: Body

    var body: some View {
        ZStack {
            groundProps
            figureGroup
                .scaleEffect(x: 1, y: breatheScale, anchor: .bottom)
                .rotationEffect(.degrees(swayDegrees), anchor: .bottom)
                .offset(x: xOffset, y: yOffset)
            if effect == .wired && !isEmpty { speedLines }
            bubbles
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .onAppear(perform: startMotion)
        .onChange(of: motionKey) { _, _ in startMotion() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if isEmpty { return "Flame buddy waiting — nothing earned yet." }
        return "Flame buddy enjoying \(TreatFormat.count(count)) \(treat.unitName(count: count))."
    }

    /// Body + everything attached to it, so the sway carries the props.
    private var figureGroup: some View {
        ZStack {
            FlameBuddyFigure(
                health: health,
                flickerPhase: 0.35,
                blink: blink,
                size: figureSize,
                showsFace: true,
                vigor: vigor,
                bellyBulge: bellyBulge,
                grounded: true
            )
            if !isEmpty {
                cheeks
                    .clipShape(TreatFlameSilhouette(
                        bodyRect: bodyRect, wobble: bodyWobble, bellyBulge: bellyBulge))
            }
            if effect == .stuffed && !isEmpty { belly }
            if effect == .tipsy && level >= 0.85 { lampshade }
            heldProp
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }

    // MARK: Motion values (rest pose when not animating)

    private var breatheScale: CGFloat {
        guard animate else { return 1 }
        return breathe ? 1.035 : 0.97
    }

    private var swayDegrees: Double {
        guard animate else { return 0 }
        if isEmpty { return sway ? 3 : -3 } // a slow, expectant head-tilt
        switch effect {
        case .tipsy:
            let amplitude = 4 + 9 * level
            return sway ? amplitude : -amplitude
        case .stuffed:
            let lean: Double = level >= 0.7 ? -5 : 0 // leans back once properly full
            return lean + (sway ? 3 : -3)
        case .wired:
            return 0
        }
    }

    private var xOffset: CGFloat {
        guard animate, !isEmpty else { return 0 }
        switch effect {
        case .tipsy:
            let amplitude = w(2 + 6 * CGFloat(level))
            return stumble ? amplitude : -amplitude
        case .stuffed:
            return 0
        case .wired:
            let amplitude = w(3 + 7 * CGFloat(level))
            return dash ? amplitude : -amplitude
        }
    }

    private var yOffset: CGFloat {
        guard animate else { return 0 }
        if isEmpty { return jiggle ? -w(1) : 0 } // a foot-tap
        switch effect {
        case .tipsy: return bob ? -w(2) : w(2)
        case .stuffed: return 0
        case .wired: return jiggle ? -w(1) : w(1)
        }
    }

    private func startMotion() {
        guard animate else { return }
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { breathe = true }
        if isEmpty {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { sway = true }
            withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) { jiggle = true }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pop = true }
            return
        }
        switch effect {
        case .tipsy:
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { sway = true }
            withAnimation(.easeInOut(duration: 2.3).repeatForever(autoreverses: true)) { stumble = true }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) { bob = true }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { sip = true }
            if bubbleLabel != nil {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pop = true }
            }
        case .stuffed:
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) { sway = true }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { jiggle = true }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { sip = true }
            if bubbleLabel != nil {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pop = true }
            }
        case .wired:
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { dash = true }
            withAnimation(.easeInOut(duration: 0.12).repeatForever(autoreverses: true)) { jiggle = true }
            withAnimation(.easeInOut(duration: 0.15).repeatForever(autoreverses: true)) { sip = true }
            // Set OUTSIDE withAnimation: each wisp carries its own
            // `.animation(value:)` timing; an enclosing transaction would weld
            // them together.
            steam = true
            if bubbleLabel != nil {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { pop = true }
            }
        }
    }

    // MARK: Geometry

    /// Design-space units → points.
    private func w(_ units: CGFloat) -> CGFloat { max(1, units * size / 100) }
    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * size / 100, y: y * size / 100)
    }

    /// Where `FlameBuddyFigure` actually draws its silhouette (the injured
    /// buddy's two corrections: 0.82-wide body frame, then vigor-scaled about
    /// the bottom edge).
    private var bodyRect: CGRect {
        let width = figureSize * 0.82 * scale
        let height = figureSize * scale
        let x = containerSize.width / 2 - width / 2
        let unscaledBottom = containerSize.height / 2 + figureSize / 2
        return CGRect(x: x, y: unscaledBottom - height, width: width, height: height)
    }

    private var bodyWobble: CGFloat {
        FlameBuddyFigure.wobble(health: health, vigor: vigor, flickerPhase: 0.35)
    }

    /// The body's own colour, for arms, cheeks and the belly's rim.
    private var bodyColor: Color {
        let colors = FlamePalette.outer(vigor: vigor)
        return colors.count > 1 ? colors[1] : (colors.first ?? .orange)
    }

    // MARK: Face overlays (clipped to the silhouette)

    @ViewBuilder
    private var cheeks: some View {
        switch effect {
        case .tipsy:
            // Blush deepens with the level.
            ForEach([-1, 1] as [CGFloat], id: \.self) { side in
                Ellipse()
                    .fill(Color(red: 1.0, green: 0.45, blue: 0.55))
                    .frame(width: w(14), height: w(9))
                    .position(pt(65 + side * 17 * scale, faceY + 6 * scale))
            }
            .opacity(0.15 + 0.55 * level)
        case .stuffed:
            // Chipmunk cheeks: small, lighter bulges at the MOUTH corners (not
            // blobs at eye level), in the inner palette so they read as the
            // face puffing out.
            let cheek = FlamePalette.inner(vigor: vigor).first ?? .yellow
            ForEach([-1, 1] as [CGFloat], id: \.self) { side in
                Ellipse()
                    .fill(cheek)
                    .frame(width: w(9), height: w(7))
                    .scaleEffect(0.5 + 0.5 * level)
                    .position(pt(65 + side * 14 * scale, mouthY - 1))
            }
            .opacity(0.55)
        case .wired:
            EmptyView()
        }
    }

    /// The tummy: a round overlay UNDER the chin — below the mouth, inside
    /// the outline's paunch and clipped to it — in the flame's inner palette,
    /// shaded like a ball (lighter top, a soft crease where it meets the
    /// body), with a small belly button. Grows with the level and jiggles as
    /// he rocks. The first version sat mid-body and covered the mouth; a
    /// flame this short only has room for a belly at the very bottom.
    private var belly: some View {
        let grow = 0.35 + 0.65 * CGFloat(level)
        let width = w(30) * grow
        let height = w(15) * grow
        let inner = FlamePalette.inner(vigor: vigor)
        let top = inner.first ?? .yellow
        let bottom = inner.count > 1 ? inner[1] : .orange
        let jiggleX: CGFloat = animate ? (jiggle ? 1.05 : 0.97) : 1
        let jiggleY: CGFloat = animate ? (jiggle ? 0.96 : 1.03) : 1
        return ZStack {
            Ellipse()
                .fill(RadialGradient(
                    colors: [top, bottom],
                    center: UnitPoint(x: 0.42, y: 0.32),
                    startRadius: 0,
                    endRadius: width * 0.7))
            // The crease: a soft shadow along the top edge where the tummy
            // meets the body, which is what makes it read as a separate bulge.
            Ellipse()
                .strokeBorder(bodyColor.opacity(0.45), lineWidth: max(1, w(1.4)))
                .mask(alignment: .top) { Rectangle().frame(height: height * 0.45) }
            Ellipse()
                .fill(Color.white.opacity(0.22))
                .frame(width: width * 0.28, height: height * 0.24)
                .offset(x: -width * 0.18, y: -height * 0.2)
            Ellipse()
                .fill(bodyColor.opacity(0.7))
                .frame(width: w(2.6), height: w(1.8))
                .offset(y: height * 0.22)
        }
        .frame(width: width, height: height)
        .scaleEffect(x: jiggleX, y: jiggleY, anchor: .bottom)
        // Below the mouth, resting on the paunch the outline grew.
        .position(pt(65, mouthY + 6 * scale + height * 0.55 / (size / 100)))
        .clipShape(TreatFlameSilhouette(
            bodyRect: bodyRect, wobble: bodyWobble, bellyBulge: bellyBulge))
    }

    /// The classic: a lampshade on the head, once properly tipsy.
    private var lampshade: some View {
        let shade = Path { path in
            path.move(to: CGPoint(x: w(6), y: 0))
            path.addLine(to: CGPoint(x: w(16), y: 0))
            path.addLine(to: CGPoint(x: w(22), y: w(12)))
            path.addLine(to: CGPoint(x: 0, y: w(12)))
            path.closeSubpath()
        }
        let paper = Color(red: 0.96, green: 0.87, blue: 0.62)
        let trim = Color(red: 0.55, green: 0.42, blue: 0.22)
        return ZStack {
            shade.fill(paper)
            shade.stroke(trim, lineWidth: max(1, w(0.8)))
            Rectangle()
                .fill(trim.opacity(0.5))
                .frame(width: w(22), height: max(1, w(1)))
                .position(x: w(11), y: w(10.5))
        }
        .frame(width: w(22), height: w(12))
        .rotationEffect(.degrees(18))
        .position(pt(70, bodyTopY + 1))
    }

    // MARK: Props

    /// Flamey has no arms, so a stub in the body's own colour reaches the
    /// prop — the crutch-line language: a stroked polyline in design space.
    /// Positions hang off the mouth so they follow the body's scale.
    @ViewBuilder
    private var heldProp: some View {
        let armFrom = pt(65 + 26 * scale, mouthY + 2)
        let armTo = pt(65 + 36 * scale, mouthY - 3)
        let hand = pt(65 + 41 * scale, mouthY - 7)
        Path { path in
            path.move(to: armFrom)
            path.addLine(to: armTo)
        }
        .stroke(bodyColor, style: StrokeStyle(lineWidth: w(4), lineCap: .round))
        if isEmpty {
            emptyProp(at: hand)
        } else {
            switch effect {
            case .tipsy:
                // The glass tips toward the mouth: a sip, and back.
                TreatGlyph(treat: treat, size: w(24), fill: heldFill)
                    .rotationEffect(.degrees(animate ? (sip ? -28 : 6) : 4), anchor: .bottom)
                    .position(hand)
            case .stuffed:
                // The food hops to the mouth — chewing, in transforms.
                TreatGlyph(treat: treat, size: w(22), fill: heldFill)
                    .rotationEffect(.degrees(animate ? (sip ? -12 : 4) : 0))
                    .offset(x: animate ? (sip ? -w(6) : 0) : 0, y: animate ? (sip ? -w(3) : 0) : 0)
                    .position(hand)
            case .wired:
                TreatGlyph(treat: treat, size: w(24), fill: heldFill)
                    .rotationEffect(.degrees(animate ? (sip ? 8 : -8) : 0))
                    .position(hand)
                steamWisps(above: hand)
            }
        }
    }

    /// Nothing earned yet: the drink upside down and empty, or a clean plate.
    @ViewBuilder
    private func emptyProp(at hand: CGPoint) -> some View {
        switch effect {
        case .tipsy, .wired:
            TreatGlyph(treat: treat, size: w(24), fill: 0)
                .rotationEffect(.degrees(180))
                .position(hand)
        case .stuffed:
            ZStack {
                Ellipse().fill(Color.white.opacity(0.85))
                Ellipse()
                    .fill(Color.white.opacity(0.55))
                    .scaleEffect(0.62)
                Ellipse()
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: max(1, w(0.8)))
            }
            .frame(width: w(24), height: w(10))
            .position(hand)
        }
    }

    private func steamWisps(above hand: CGPoint) -> some View {
        ForEach(0..<3, id: \.self) { index in
            let x = hand.x + w([-6, 0, 6][index])
            let top = hand.y - w(13)
            let duration = [0.9, 1.1, 1.3][index]
            Path { path in
                path.move(to: CGPoint(x: x, y: top + w(8)))
                path.addQuadCurve(
                    to: CGPoint(x: x, y: top),
                    control: CGPoint(x: x + w(index == 1 ? -4 : 4), y: top + w(4)))
            }
            .stroke(TreatInk.steam, style: StrokeStyle(lineWidth: w(2), lineCap: .round))
            .offset(y: (animate && steam) ? -w(4) : 0)
            .opacity((animate && steam) ? 0.15 : 0.6)
            .animation(
                animate ? .easeInOut(duration: duration).repeatForever(autoreverses: true) : nil,
                value: steam)
        }
    }

    /// Zoomies: motion lines that flicker beside the dash.
    private var speedLines: some View {
        ForEach(0..<3, id: \.self) { index in
            let y = faceY + CGFloat(index - 1) * 8 * scale
            let length: CGFloat = [10, 14, 10][index]
            Path { path in
                path.move(to: pt(30 - length, y))
                path.addLine(to: pt(30, y))
            }
            .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: w(1.6), lineCap: .round))
            .opacity(animate ? (dash ? 0.65 : 0.05) : 0.3)
        }
    }

    /// Empties, crumbs and a "×N" once the ground is full.
    @ViewBuilder
    private var groundProps: some View {
        switch effect {
        case .tipsy, .wired:
            let spots: [CGFloat] = [9, 20, 110, 121]
            ForEach(0..<min(empties, spots.count), id: \.self) { index in
                TreatGlyph(treat: treat, size: w(11), fill: 0)
                    .rotationEffect(.degrees(index % 2 == 0 ? -12 : 9))
                    .position(pt(spots[index], 107))
            }
            if empties > spots.count { overflowCaption }
        case .stuffed:
            let spots: [CGFloat] = [14, 26, 38, 92, 104, 116, 20, 110]
            ForEach(0..<min(empties, spots.count), id: \.self) { index in
                Circle()
                    .fill(TreatInk.bun)
                    .frame(width: w(3), height: w(3))
                    .position(pt(spots[index], index >= 6 ? 105 : 109))
            }
            if empties > spots.count { overflowCaption }
        }
    }

    private var overflowCaption: some View {
        Text("×\(empties)")
            .font(.system(size: max(8, size * 0.09), weight: .heavy, design: .rounded))
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, w(4))
            .padding(.vertical, w(2))
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .position(pt(118, 94))
    }

    // MARK: Bubbles

    /// What he says, and from which level. Equivalence-era copy only.
    private var bubbleLabel: String? {
        if isEmpty { return "earn it!" }
        switch effect {
        case .tipsy:
            if level >= 0.8 { return "hic!" }
            return level >= 0.2 ? "cheers!" : nil
        case .stuffed:
            if level >= 0.9 { return "burp" }
            return level >= 0.3 ? "nom nom" : nil
        case .wired:
            if level >= 0.9 { return "ZOOM!" }
            return level >= 0.4 ? "!!!" : nil
        }
    }

    @ViewBuilder
    private var bubbles: some View {
        if let label = bubbleLabel {
            let shown = animate ? pop : true
            Text(label)
                .font(.system(size: max(8, size * 0.10), weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, w(5))
                .padding(.vertical, w(2.5))
                .background(Capsule().fill(Color.white.opacity(0.16)))
                .scaleEffect(shown ? 1 : 0.7)
                .opacity(shown ? 1 : 0)
                .offset(x: effect == .wired ? xOffset * 0.4 : 0, y: shown ? -w(3) : w(2))
                .position(pt(102, bodyTopY + 6))
            if effect == .tipsy && level >= 0.8 {
                ForEach(0..<2, id: \.self) { index in
                    let dot: (CGFloat, CGFloat, CGFloat) = index == 0 ? (92, 50, 5) : (98, 44, 3)
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: max(1, w(0.8)))
                        .frame(width: w(dot.2), height: w(dot.2))
                        .offset(y: shown ? -w(8) : 0)
                        .opacity(shown ? 0 : 0.7)
                        .position(pt(dot.0, dot.1))
                }
            }
        }
    }
}

/// The flame's outline in the parent's coordinate space — with the belly
/// bulge, so a stuffed Flamey's cheeks clip to the shape he actually has.
private struct TreatFlameSilhouette: Shape {
    let bodyRect: CGRect
    let wobble: CGFloat
    let bellyBulge: CGFloat

    func path(in rect: CGRect) -> Path {
        FlameBuddyOuterShape(wobble: wobble, bellyBulge: bellyBulge).path(in: bodyRect)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            ForEach(CalorieTreat.allCases) { treat in
                HStack(spacing: 8) {
                    ForEach([0.0, 0.4, 3.4, 12.0], id: \.self) { count in
                        TreatFlameBuddyView(size: 70, treat: treat, count: count)
                    }
                }
            }
        }
        .padding(20)
    }
    .background(Color(red: 0.08, green: 0.08, blue: 0.09))
}
