import SwiftUI

// FLAMEY'S WARDROBE — THE DRAWINGS. BYTE-IDENTICAL in
// app/Mile A Day/Views/Components/ and app/MileADayWidgets/ (see
// FlameyWardrobe.swift). SwiftUI + Foundation only.
//
// Every prop is drawn in `FlameBuddyFigure`'s own geometry: the origin is the
// centre of his `size` square, `u` = size × body scale (so gear stays on him as
// he burns down through the day), and `Anchors` places the face, eyes and tip.
// One outline ink for everything, so line weight reads as one family.

enum FlameyArt {
    struct Anchors {
        /// His base (raised by his legs when he wears shoes, lifted again
        /// when he hovers).
        let bottom: CGFloat
        /// The floor — where companions stand and jets land.
        let ground: CGFloat
        let faceY: CGFloat
        let eyeX: CGFloat
        let topY: CGFloat
        /// Where his soles are: the floor, or above it when he hovers.
        var feet: CGFloat = 0
    }

    /// `lift` is the hover (jets, wings), `stand` his legs — both in body
    /// units. The body sits on top of both; the feet only rise by the hover.
    static func anchors(size: CGFloat, scale: CGFloat, lift: CGFloat = 0, stand: CGFloat = 0) -> Anchors {
        let u = size * scale
        let bottom = size / 2 - (lift + stand) * u
        return Anchors(bottom: bottom,
                       ground: size / 2,
                       faceY: bottom - 0.32 * u,
                       eyeX: 0.145 * u,
                       topY: bottom - 0.98 * u,
                       feet: size / 2 - lift * u)
    }

    // MARK: - Legs

    /// How far his legs raise him, in body units. The Fun mascot ALWAYS
    /// stands on his two stubby legs — bare (little rounded feet in his
    /// colour) or shod.
    static let legLength: CGFloat = FlameBuddyFigure.mascotLegLength

    /// Where each leg meets the floor (the figure draws the legs).
    static var legSpread: CGFloat { FlameBuddyFigure.legSpread }

    /// His body's rectangle (the figure's 0.82 × 1 frame, scaled about its
    /// base) — for anything that must clip to his outline.
    static func bodyRect(_ a: Anchors, _ u: CGFloat) -> CGRect {
        CGRect(x: -0.41 * u, y: a.bottom - u, width: 0.82 * u, height: u)
    }

    static let ink = FlameyPalette.hex(0x2A1410)

    static func lw(_ u: CGFloat) -> CGFloat { max(1, 0.010 * u) }

    // MARK: - Geometry helpers

    static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    static func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
    }

    static func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .continuous)
    }

    static func poly(_ pts: [CGPoint]) -> Path {
        var p = Path()
        for (i, q) in pts.enumerated() { if i == 0 { p.move(to: q) } else { p.addLine(to: q) } }
        p.closeSubpath()
        return p
    }

    /// A sub-context moved to (x, y) and turned by `degrees`.
    static func placed(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ degrees: Double = 0) -> GraphicsContext {
        var sub = ctx
        sub.translateBy(x: x, y: y)
        if degrees != 0 { sub.rotate(by: .degrees(degrees)) }
        return sub
    }

    static func lin(_ colors: [Color], _ a: CGPoint, _ b: CGPoint) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: a, endPoint: b)
    }

    static func star(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, inner: CGFloat = 0.45, points: Int = 5) -> Path {
        var p = Path()
        for i in 0..<(points * 2) {
            let rr = i % 2 == 1 ? r * inner : r
            let angle = -Double.pi / 2 + Double(i) * Double.pi / Double(points)
            let q = CGPoint(x: cx + rr * CGFloat(cos(angle)), y: cy + rr * CGFloat(sin(angle)))
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        return p
    }

    /// A band that curves like it wraps a round body: top edge sags by `sag`
    /// of its height, bottom edge by one more.
    static func band(w: CGFloat, h: CGFloat, sag: CGFloat) -> Path {
        var p = Path()
        p.move(to: pt(-w / 2, -h / 2))
        p.addQuadCurve(to: pt(w / 2, -h / 2), control: pt(0, h * sag))
        p.addLine(to: pt(w / 2, h / 2))
        p.addQuadCurve(to: pt(-w / 2, h / 2), control: pt(0, h * (sag + 1)))
        p.closeSubpath()
        return p
    }

    static func hx(_ v: UInt32, _ o: Double = 1) -> Color { FlameyPalette.hex(v, o) }

    // MARK: - Tight surfaces (the dashboard hero's column)

    /// Below this `reach` a surface is TIGHT: the hero, whose stat column
    /// starts just right of his body and whose card edge is just left of it.
    static let tightReach: CGFloat = 0.75

    static func isTight(_ reach: CGFloat) -> Bool { reach < tightReach }

    /// Where a tight surface's room ends, in units of the view's `size`
    /// measured from his centre: the card edge on the left, the stat column
    /// on the right (the hero's own geometry: ~0.52 and ~0.49 at 375–430pt).
    /// Art is FITTED inside `tightArtBounds`; `FlameyOutfitLayer` also masks
    /// to `tightMaskBounds` as a guarantee, feathered so a stray pixel fades.
    static let tightArtBounds: (left: CGFloat, right: CGFloat) = (-0.49, 0.46)
    static let tightMaskBounds: (left: CGFloat, right: CGFloat) = (-0.53, 0.50)

    /// The card's TOP edge on a tight surface, in units of `size` from the
    /// view's centre (the hero's buddy frame starts ~38pt under it).
    static let tightTopBound: CGFloat = -0.72

    /// The top mask for THIS look: never below the head it wears. A crown
    /// or a countdown hat on rocket boots reaches ~1.1 size above centre,
    /// and a fixed -0.72 sliced it flat — the hero reserves headroom for the
    /// whole look instead (`extentAboveView`), so the mask only has to stop
    /// things that are NOT his head (a banner pole, a camera flash).
    static func tightTopBound(for look: FlameyLook, scale: CGFloat) -> CGFloat {
        min(tightTopBound, lookTop(look, scale: scale) - 0.03)
    }

    // MARK: - Headroom (everything above his tip)

    /// How far above his TIP each head piece reaches, in body units —
    /// measured off the drawings (harness `measure.swift`), not guessed.
    /// A new hat that rises needs a row here or the hero clips it.
    static func headRise(_ item: FlameyItem) -> CGFloat {
        switch item {
        case .countdownHat: return 0.29
        case .crown, .vikingHelmet, .partyHat: return 0.25
        case .bunnyEars: return 0.17
        case .headlampHelmet: return 0.15
        case .ghostSheet: return 0.14
        case .leprechaunHat, .starHat, .beanie: return 0.13
        case .heartBopper, .santaHat: return 0.10
        case .pumpkinSuit: return 0.07
        case .cowboyHat, .nightcap: return 0.06
        case .aviatorCap, .directorsBeret, .safariHat: return 0.05
        case .bucketHat, .ballCap, .astronautHelmet: return 0.03
        default: return 0
        }
    }

    /// The crest of the look: how far its highest drawn point sits above
    /// his tip (body units). A bare tip still flickers a little above 0.98.
    static func crest(of look: FlameyLook) -> CGFloat {
        max(0.03, [look[.head], look[.costume]].compactMap { $0 }.map(headRise).max() ?? 0)
    }

    /// The look's top, as a fraction of the view's `size` from its centre
    /// (y down), before any stand-fit: legs, hover, body and crest.
    static func lookTop(_ look: FlameyLook, scale: CGFloat) -> CGFloat {
        0.5 - (look.bodyLift + 0.98 + crest(of: look)) * scale
    }

    /// The speech bubble's reserved height as a fraction of `size`: TWO lines
    /// of the largest style (comic, 1.05× type) + padding + tail + its drop
    /// shadow. Reserved whether or not a bubble is up, so a surface never
    /// jumps when he starts or stops talking.
    /// In POINTS, because the type has a 10pt floor: at a small size the
    /// bubble is proportionally taller (it overran an 80pt Closet stage).
    static func bubbleReserve(_ size: CGFloat) -> CGFloat {
        let font = max(10, size * 0.07)
        return 2 * font * 1.05 * 1.22 + size * 0.06 + max(5, size * 0.045) + size * 0.02 + 2
    }
    /// The gap between his crest and the bubble's tail.
    static let bubbleGap: CGFloat = 0.02

    /// How many POINTS the dressed figure (and, with `bubble`, his speech
    /// bubble over his crest) reaches above the TOP edge of his `size`
    /// square — what a surface must leave free above him. `fit` is the
    /// stand-fit the surface draws him at (the hero: 1/(1+standLift)),
    /// scaled about his feet.
    static func extentAboveView(look: FlameyLook, size: CGFloat, scale: CGFloat, fit: CGFloat, bubble: Bool) -> CGFloat {
        var top = lookTop(look, scale: scale) * size
        if bubble { top -= bubbleGap * size + bubbleReserve(size) }
        let scaled = size / 2 + fit * (top - size / 2)
        return -size / 2 - scaled
    }

    /// How far a back piece's width is squeezed on a tight surface.
    static let capeTuck: CGFloat = 0.53
    /// A cape hangs close behind him, so a tight surface only narrows its
    /// flare — it still shows on both sides.
    static let capeTightScale: CGFloat = 0.82

    static func isCape(_ item: FlameyItem) -> Bool {
        [.redCape, .blueCape, .royalCape, .championCape].contains(item)
    }

    /// How far a trail's length is squeezed on a tight surface.
    static let trailTuck: CGFloat = 0.56

    /// A held prop's scale on a tight surface — by how far it reaches out
    /// (the redesigned props are bigger: the cannon's burst runs to ~1.2u).
    static func tightHeldScale(_ item: FlameyItem) -> CGFloat {
        switch item {
        case .confettiCannon: return 0.50
        case .megaphone: return 0.60
        case .checkeredFlag: return 0.60
        case .pomPoms: return 0.66
        case .foamFinger: return 0.70
        default: return 0.72
        }
    }

    // MARK: - Front (feet, costume, chest, eyes, head, held)

    /// Draws one front item. `palette` is his colour (arms and costume peeks
    /// take it); `jets` is false on a compact surface.
    static func drawFront(_ item: FlameyItem, in ctx: inout GraphicsContext, a: Anchors, u: CGFloat,
                          palette: FlameyPalette?, jets: Bool, reach: CGFloat = 0.9) {
        switch item.slot {
        case .feet: shoe(item, &ctx, a, u, jets: jets)
        case .costume: costume(item, &ctx, a, u, palette: palette)
        case .chest: chest(item, &ctx, a, u)
        case .eyes: eyewear(item, &ctx, a, u)
        case .head: hat(item, &ctx, a, u)
        case .held:
            // A tight surface (the hero's column) holds it a size smaller,
            // scaled about his shoulder, so it stays on the card.
            var h = ctx
            applyHeldTight(item, &h, a: a, u: u, reach: reach)
            held(item, &h, a, u)
        default: break
        }
    }

    /// A tight surface (the hero's column) holds the prop a size smaller,
    /// scaled about the pivot that carries his hand to its tight spot.
    static func applyHeldTight(_ item: FlameyItem, _ h: inout GraphicsContext, a: Anchors, u: CGFloat, reach: CGFloat) {
        if isTight(reach) {
            // Brought in close (his arm hangs nearer his side) and
            // scaled by how far the prop reaches, about the pivot that
            // carries his hand exactly to its tight spot — so the hand
            // the arms layer draws still closes round the handle, and
            // the longest (the cannon, the flag) ends inside the card.
            let k = tightHeldScale(item)
            let base = heldHand(item), tightHand = tightHeldHand(item)
            let px = -(tightHand.x - k * base.x) / (1 - k) * u
            let py = a.bottom + (tightHand.y - k * base.y) / (1 - k) * u
            h.translateBy(x: px, y: py); h.scaleBy(x: k, y: k); h.translateBy(x: -px, y: -py)
        }
    }

    /// The parts of a BACK item that sit in front of him. None today: a
    /// cape is one silhouette behind him (clasps on a neckless flame read
    /// as a second pair of eyes); kept as the hook for a strap or buckle.
    static func drawBackFront(_ item: FlameyItem, in ctx: inout GraphicsContext, a: Anchors, u: CGFloat) {}

    // MARK: Shoes

    static func shoePath(w: CGFloat, h: CGFloat, low: Bool = false, pointy: Bool = false) -> Path {
        var p = Path()
        let top: CGFloat = low ? -0.30 : -0.5
        p.move(to: pt(-w * 0.5, h * 0.35))
        p.addLine(to: pt(-w * 0.5, h * top * 0.2))
        p.addQuadCurve(to: pt(-w * 0.15, h * top), control: pt(-w * 0.48, h * top))
        p.addLine(to: pt(w * 0.05, h * top * 0.9))
        p.addQuadCurve(to: pt(w * (pointy ? 0.55 : 0.45), h * 0.10), control: pt(w * 0.25, h * -0.05))
        p.addQuadCurve(to: pt(w * 0.5, h * 0.35), control: pt(w * 0.58, h * 0.22))
        p.closeSubpath()
        return p
    }

    static func shoe(_ item: FlameyItem, _ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat, jets: Bool) {
        let w = 0.25 * u, h = 0.11 * u
        let L = lw(u)
        let ink = self.ink
        for side in [-1.0, 1.0] as [CGFloat] {
            // Planted on his feet (the leg enters the heel opening, which
            // sits at -0.2w in shoe space; toes point outward).
            var g = placed(ctx, side * (legSpread + 0.05) * u, a.feet - h * 0.46)
            g.scaleBy(x: side, y: 1)
            switch item {
            case .canvasSneakers:
                var up = Path()
                up.move(to: pt(-w * 0.5, h * 0.35)); up.addLine(to: pt(-w * 0.5, -h * 1.05))
                up.addQuadCurve(to: pt(-w * 0.12, -h * 1.1), control: pt(-w * 0.32, -h * 1.22))
                up.addLine(to: pt(-w * 0.02, -h * 0.35))
                up.addQuadCurve(to: pt(w * 0.46, h * 0.08), control: pt(w * 0.30, -h * 0.25))
                up.addQuadCurve(to: pt(w * 0.5, h * 0.35), control: pt(w * 0.56, h * 0.2))
                up.closeSubpath()
                g.fill(up, with: .color(hx(0x22306E)))
                g.stroke(up, with: .color(ink), lineWidth: L)
                g.fill(ellipse(w * 0.36, h * 0.1, w * 0.17, h * 0.22), with: .color(hx(0xF6F1E4)))
                let sole = rrect(-w * 0.53, h * 0.14, w * 1.06, h * 0.30, h * 0.12)
                g.fill(sole, with: .color(hx(0xF6F1E4)))
                g.stroke(sole, with: .color(ink), lineWidth: L)
                g.fill(Path(CGRect(x: -w * 0.53, y: h * 0.25, width: w * 1.06, height: h * 0.06)), with: .color(hx(0xE8384F)))
                g.fill(circle(-w * 0.33, -h * 0.6, h * 0.16), with: .color(hx(0xF6F1E4)))
                for i in 0..<3 {
                    let y = -h * 0.85 + CGFloat(i) * h * 0.28
                    var l = Path(); l.move(to: pt(-w * 0.14, y)); l.addLine(to: pt(w * 0.02, y + h * 0.08))
                    g.stroke(l, with: .color(.white), style: StrokeStyle(lineWidth: h * 0.09, lineCap: .round))
                }
            case .trainers:
                let s = shoePath(w: w, h: h)
                g.fill(s, with: .color(hx(0xF4F6FA)))
                g.fill(ellipse(-w * 0.25, -h * 0.08, w * 0.16, h * 0.22), with: .color(hx(0xC9D1DC)))
                var sw = Path(); sw.move(to: pt(-w * 0.38, h * 0.02)); sw.addQuadCurve(to: pt(w * 0.30, -h * 0.08), control: pt(-w * 0.02, h * 0.22))
                g.stroke(sw, with: .color(hx(0x2F7BFF)), style: StrokeStyle(lineWidth: h * 0.16, lineCap: .round))
                g.stroke(s, with: .color(ink), lineWidth: L)
                let sole = rrect(-w * 0.54, h * 0.18, w * 1.08, h * 0.34, h * 0.16)
                g.fill(sole, with: .color(.white))
                g.fill(Path(CGRect(x: -w * 0.54, y: h * 0.36, width: w * 1.08, height: h * 0.05)), with: .color(hx(0xB8C2CF)))
                g.stroke(sole, with: .color(ink), lineWidth: L)
                g.fill(rrect(-w * 0.52, -h * 0.30, w * 0.12, h * 0.46, h * 0.05), with: .color(hx(0x2F7BFF)))
            case .racingFlats:
                let s = shoePath(w: w * 1.05, h: h * 0.9, low: true, pointy: true)
                g.fill(s, with: lin([hx(0xFF9A3C), hx(0xFF4E1A)], pt(0, -h * 0.4), pt(0, h * 0.3)))
                var st = Path(); st.move(to: pt(-w * 0.34, -h * 0.02)); st.addLine(to: pt(w * 0.26, -h * 0.02))
                g.stroke(st, with: .color(hx(0x1A1A22)), style: StrokeStyle(lineWidth: h * 0.10, lineCap: .round))
                var st2 = Path(); st2.move(to: pt(-w * 0.30, h * 0.12)); st2.addLine(to: pt(w * 0.34, h * 0.10))
                g.stroke(st2, with: .color(hx(0x1A1A22)), style: StrokeStyle(lineWidth: h * 0.06, lineCap: .round))
                g.stroke(s, with: .color(ink), lineWidth: L)
                let sole = rrect(-w * 0.55, h * 0.24, w * 1.14, h * 0.16, h * 0.08)
                g.fill(sole, with: .color(.white))
                g.stroke(sole, with: .color(ink), lineWidth: L)
            case .neonSoles:
                var gg = g
                gg.addFilter(.blur(radius: h * 0.35))
                gg.fill(rrect(-w * 0.6, h * 0.12, w * 1.2, h * 0.5, h * 0.2), with: .color(hx(0x39FF88, 0.9)))
                let s = shoePath(w: w, h: h)
                g.fill(s, with: .color(hx(0x1C1C26)))
                g.stroke(s, with: .color(ink), lineWidth: L)
                var lace = Path(); lace.move(to: pt(-w * 0.1, -h * 0.35)); lace.addLine(to: pt(w * 0.12, -h * 0.12))
                g.stroke(lace, with: .color(hx(0xFF3DAA)), style: StrokeStyle(lineWidth: h * 0.12, lineCap: .round, dash: [h * 0.12, h * 0.1]))
                var sw = Path(); sw.move(to: pt(-w * 0.36, h * 0.05)); sw.addQuadCurve(to: pt(w * 0.28, -h * 0.04), control: pt(-w * 0.04, h * 0.18))
                g.stroke(sw, with: .color(hx(0xFF3DAA)), style: StrokeStyle(lineWidth: h * 0.10, lineCap: .round))
                let sole = rrect(-w * 0.54, h * 0.18, w * 1.08, h * 0.32, h * 0.16)
                g.fill(sole, with: lin([hx(0xB6FFD5), hx(0x39FF88)], pt(0, h * 0.18), pt(0, h * 0.5)))
            case .trackSpikes:
                let s = shoePath(w: w * 1.05, h: h * 0.95, low: true, pointy: true)
                g.fill(s, with: .color(hx(0xC6FF3D)))
                var z = Path(); z.move(to: pt(-w * 0.35, h * 0.12)); z.addLine(to: pt(-w * 0.05, -h * 0.25)); z.addLine(to: pt(w * 0.02, h * 0.02)); z.addLine(to: pt(w * 0.32, -h * 0.02))
                g.stroke(z, with: .color(hx(0x1B2A6B)), style: StrokeStyle(lineWidth: h * 0.12, lineCap: .round, lineJoin: .round))
                g.stroke(s, with: .color(ink), lineWidth: L)
                let plate = rrect(-w * 0.52, h * 0.24, w * 1.1, h * 0.14, h * 0.07)
                g.fill(plate, with: .color(hx(0x1B2A6B)))
                for i in 0..<4 {
                    let x = -w * 0.02 + CGFloat(i) * w * 0.15
                    g.fill(poly([pt(x - h * 0.07, h * 0.38), pt(x + h * 0.07, h * 0.38), pt(x, h * 0.62)]), with: .color(hx(0xDDE3EA)))
                }
            case .rocketBoots:
                // Chunky astronaut boots — tall silver shells, a red cuff,
                // a swept fin and a thick sole — riding ONE tidy jet each out
                // of a nozzle under the sole. Compact surfaces stand on the
                // floor, so there the nozzle and jet are left off.
                if jets {
                    let nozzleTop = h * 0.42, nozzleBottom = h * 0.70
                    let nx = -w * 0.04
                    let floorY = a.ground - a.feet + h * 0.46
                    let len = min(h * 1.25, max(h * 0.45, floorY - nozzleBottom - h * 0.02))
                    var glow = g; glow.addFilter(.blur(radius: h * 0.28))
                    glow.fill(ellipse(nx, nozzleBottom + len * 0.45, w * 0.20, len * 0.55), with: .color(hx(0xFF8A1F, 0.65)))
                    var pool = g; pool.addFilter(.blur(radius: h * 0.22))
                    pool.fill(ellipse(nx, floorY, w * 0.30, h * 0.10), with: .color(hx(0xFFB347, 0.45)))
                    func jet(_ half: CGFloat, _ length: CGFloat) -> Path {
                        var f = Path()
                        f.move(to: pt(nx - half, nozzleBottom))
                        f.addCurve(to: pt(nx, nozzleBottom + length), control1: pt(nx - half * 1.1, nozzleBottom + length * 0.45),
                                   control2: pt(nx - half * 0.35, nozzleBottom + length * 0.85))
                        f.addCurve(to: pt(nx + half, nozzleBottom), control1: pt(nx + half * 0.35, nozzleBottom + length * 0.85),
                                   control2: pt(nx + half * 1.1, nozzleBottom + length * 0.45))
                        f.closeSubpath()
                        return f
                    }
                    g.fill(jet(w * 0.19, len), with: lin([hx(0xFFB020), hx(0xFF5A1F), hx(0xFF3D1A, 0.3)], pt(0, nozzleBottom), pt(0, nozzleBottom + len)))
                    g.fill(jet(w * 0.10, len * 0.62), with: lin([.white, hx(0xFFF3A0)], pt(0, nozzleBottom), pt(0, nozzleBottom + len * 0.62)))
                    // The nozzle: a little flared bell.
                    var bell = Path()
                    bell.move(to: pt(nx - w * 0.13, nozzleTop)); bell.addLine(to: pt(nx + w * 0.13, nozzleTop))
                    bell.addLine(to: pt(nx + w * 0.19, nozzleBottom)); bell.addLine(to: pt(nx - w * 0.19, nozzleBottom))
                    bell.closeSubpath()
                    g.fill(bell, with: lin([hx(0xA9B3C1), hx(0x4A5260)], pt(0, nozzleTop), pt(0, nozzleBottom)))
                    g.stroke(bell, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
                    g.fill(ellipse(nx, nozzleBottom, w * 0.17, h * 0.05), with: .color(hx(0xFFD27A)))
                }
                // A swept fin on the outside of the shaft, behind the shell.
                let fin = poly([pt(w * 0.02, -h * 0.74), pt(w * 0.40, -h * 0.58), pt(w * 0.30, -h * 0.36), pt(w * 0.04, -h * 0.42)])
                g.fill(fin, with: lin([hx(0xFF5A6E), hx(0xB3152F)], pt(0, -h * 0.8), pt(0, h * 0.05)))
                g.stroke(fin, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
                var boot = Path()
                boot.move(to: pt(-w * 0.48, h * 0.30))
                boot.addLine(to: pt(-w * 0.47, -h * 0.76))
                boot.addQuadCurve(to: pt(w * 0.06, -h * 0.76), control: pt(-w * 0.21, -h * 0.98))
                boot.addLine(to: pt(w * 0.08, -h * 0.40))
                boot.addQuadCurve(to: pt(w * 0.52, h * 0.02), control: pt(w * 0.46, -h * 0.34))
                boot.addLine(to: pt(w * 0.52, h * 0.30))
                boot.closeSubpath()
                g.fill(boot, with: lin([.white, hx(0xD4DBE4), hx(0x9AA6B5)], pt(0, -h * 1.1), pt(0, h * 0.3)))
                var shell = g; shell.clip(to: boot)
                // Dark toe cap and a red cuff band.
                shell.fill(ellipse(w * 0.40, h * 0.12, w * 0.24, h * 0.34), with: .color(hx(0x4A5563)))
                shell.fill(Path(CGRect(x: -w * 0.6, y: -h * 0.76, width: w * 0.8, height: h * 0.20)), with: .color(hx(0xE8384F)))
                shell.fill(Path(CGRect(x: -w * 0.6, y: -h * 0.76, width: w * 0.8, height: h * 0.05)), with: .color(.white.opacity(0.45)))
                // A shine down the shell.
                shell.fill(rrect(-w * 0.38, -h * 0.52, w * 0.08, h * 0.44, w * 0.04), with: .color(.white.opacity(0.7)))
                g.stroke(boot, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
                let sole = rrect(-w * 0.54, h * 0.18, w * 1.08, h * 0.26, h * 0.10)
                g.fill(sole, with: lin([hx(0x5B6675), hx(0x2F353F)], pt(0, h * 0.18), pt(0, h * 0.44)))
                g.stroke(sole, with: .color(ink), lineWidth: L)
                g.fill(Path(CGRect(x: -w * 0.48, y: h * 0.22, width: w * 0.96, height: h * 0.04)), with: .color(.white.opacity(0.25)))
            case .lightningKicks:
                for (x0, y0, dir) in [(-w * 0.62, -h * 0.2, -1.0), (w * 0.62, -h * 0.45, 1.0), (w * 0.2, h * 0.75, 1.0)] as [(CGFloat, CGFloat, CGFloat)] {
                    var z = Path()
                    z.move(to: pt(x0, y0)); z.addLine(to: pt(x0 + dir * h * 0.25, y0 - h * 0.2))
                    z.addLine(to: pt(x0 + dir * h * 0.18, y0 - h * 0.02)); z.addLine(to: pt(x0 + dir * h * 0.45, y0 - h * 0.24))
                    var gg = g; gg.addFilter(.blur(radius: h * 0.12))
                    gg.stroke(z, with: .color(hx(0x7FE9FF)), style: StrokeStyle(lineWidth: h * 0.16, lineCap: .round, lineJoin: .round))
                    g.stroke(z, with: .color(.white), style: StrokeStyle(lineWidth: h * 0.06, lineCap: .round, lineJoin: .round))
                }
                let s = shoePath(w: w, h: h)
                g.fill(s, with: .color(hx(0xFFD21F)))
                g.fill(poly([pt(-w * 0.28, -h * 0.35), pt(w * 0.02, -h * 0.35), pt(-w * 0.10, -h * 0.02), pt(w * 0.16, -h * 0.02),
                             pt(-w * 0.22, h * 0.34), pt(-w * 0.10, h * 0.06), pt(-w * 0.34, h * 0.06)]), with: .color(hx(0x1A1A22)))
                g.stroke(s, with: .color(ink), lineWidth: L)
                g.fill(rrect(-w * 0.54, h * 0.2, w * 1.08, h * 0.3, h * 0.14), with: .color(hx(0x1A1A22)))
            case .wingedSandals:
                for (i, ang) in [(0, -18.0), (1, -42.0), (2, -66.0)] as [(Int, Double)] {
                    let wg = placed(g, w * 0.02, -h * 0.25, ang)
                    let len = h * (1.9 - CGFloat(i) * 0.35)
                    let f = ellipse(len * 0.5, 0, len * 0.55, h * 0.2)
                    wg.fill(f, with: lin([.white, hx(0xDDE8FF)], pt(0, -h * 0.2), pt(0, h * 0.2)))
                    wg.stroke(f, with: .color(hx(0x8AA0C8)), lineWidth: L * 0.8)
                }
                let sole = rrect(-w * 0.54, h * 0.18, w * 1.08, h * 0.24, h * 0.12)
                g.fill(sole, with: lin([hx(0xFFE58A), hx(0xE0A512)], pt(0, h * 0.18), pt(0, h * 0.42)))
                g.stroke(sole, with: .color(hx(0x9A6400)), lineWidth: L)
                for (x, ang) in [(-w * 0.18, 60.0), (w * 0.14, -60.0)] as [(CGFloat, Double)] {
                    let sg = placed(g, x, -h * 0.05, ang)
                    let strap = rrect(-h * 0.08, -h * 0.35, h * 0.16, h * 0.7, h * 0.08)
                    sg.fill(strap, with: .color(hx(0xFFCF40)))
                    sg.stroke(strap, with: .color(hx(0x9A6400)), lineWidth: L * 0.8)
                }
                g.fill(circle(-w * 0.02, -h * 0.05, h * 0.09), with: .color(hx(0xFFF3B0)))
            default: break
            }
        }
    }

    // MARK: Hats

    /// Hats grow with their rung: a ball cap is a ball cap; a crown is an
    /// occasion. Scaled about where a hat meets his tip.
    static func headScale(_ item: FlameyItem) -> CGFloat {
        switch item {
        case .sweatband, .ballCap, .visor: return 1.0
        case .directorsBeret, .beanie: return 1.04
        case .bucketHat: return 1.07
        case .safariHat: return 1.10
        case .cowboyHat: return 1.12
        case .aviatorCap: return 1.14
        case .headlampHelmet: return 1.16
        case .crown: return 1.0 // drawn big in its own right
        case .laurelWreath: return 1.22
        case .vikingHelmet: return 1.26
        default: return 1.0
        }
    }

    static func hat(_ item: FlameyItem, _ base: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let L = lw(u)
        let ink = self.ink
        let top = a.topY
        var ctx = base
        let k = headScale(item)
        if k != 1 {
            let pivotY = top + 0.18 * u
            ctx.translateBy(x: 0, y: pivotY); ctx.scaleBy(x: k, y: k); ctx.translateBy(x: 0, y: -pivotY)
        }
        switch item {
        case .sweatband:
            let w = 0.50 * u, h = 0.06 * u
            let g = placed(ctx, -0.005 * u, a.faceY - 0.135 * u)
            let shape = band(w: w, h: h, sag: 0.9)
            g.fill(shape, with: .color(hx(0xF4F4F6)))
            var stripe = Path()
            stripe.move(to: pt(-w / 2, -h * 0.05))
            stripe.addQuadCurve(to: pt(w / 2, -h * 0.05), control: pt(0, h * 1.35))
            var sc = g; sc.clip(to: shape)
            sc.stroke(stripe, with: .color(hx(0xE8384F)), lineWidth: h * 0.28)
            g.stroke(shape, with: .color(ink.opacity(0.55)), lineWidth: L * 0.8)
        case .ballCap:
            let g = placed(ctx, -0.005 * u, top + 0.18 * u, -6)
            let w = 0.37 * u, h = 0.21 * u
            var dome = Path()
            dome.move(to: pt(-w / 2, 0)); dome.addCurve(to: pt(w / 2, 0), control1: pt(-w / 2, -h * 1.25), control2: pt(w / 2, -h * 1.25)); dome.closeSubpath()
            var brim = Path()
            brim.move(to: pt(w * 0.05, -h * 0.02)); brim.addQuadCurve(to: pt(w * 0.95, h * 0.08), control: pt(w * 0.62, -h * 0.30))
            brim.addQuadCurve(to: pt(w * 0.1, h * 0.14), control: pt(w * 0.6, h * 0.30)); brim.closeSubpath()
            g.fill(dome, with: lin([hx(0xFF5A6E), hx(0xD41F3A)], pt(0, -h), pt(0, 0)))
            var seam = Path(); seam.move(to: pt(0, -h * 0.94)); seam.addQuadCurve(to: pt(-w * 0.1, 0), control: pt(-w * 0.12, -h * 0.5))
            g.stroke(seam, with: .color(hx(0x9E1028)), lineWidth: L * 0.8)
            g.fill(circle(w * 0.08, -h * 0.45, h * 0.22), with: .color(.white))
            g.fill(star(w * 0.08, -h * 0.45, h * 0.16, inner: 0.45), with: .color(hx(0xD41F3A)))
            g.stroke(dome, with: .color(ink), lineWidth: L)
            g.fill(brim, with: .color(hx(0xB3152F)))
            g.stroke(brim, with: .color(ink), lineWidth: L)
            g.fill(ellipse(0, -h * 0.93, h * 0.09, h * 0.05), with: .color(hx(0xB3152F)))
        case .visor: visor(&ctx, a, u)
        case .beanie:
            let g = placed(ctx, 0, top + 0.19 * u, -3)
            let w = 0.34 * u, h = 0.24 * u
            var dome = Path()
            dome.move(to: pt(-w / 2, 0)); dome.addCurve(to: pt(w / 2, 0), control1: pt(-w / 2, -h * 1.2), control2: pt(w / 2, -h * 1.2)); dome.closeSubpath()
            g.fill(dome, with: .color(hx(0x2F6BFF)))
            var knit = g; knit.clip(to: dome)
            for i in -4...4 {
                var r = Path(); r.move(to: pt(CGFloat(i) * w * 0.1, 0)); r.addQuadCurve(to: pt(CGFloat(i) * w * 0.02, -h), control: pt(CGFloat(i) * w * 0.09, -h * 0.6))
                knit.stroke(r, with: .color(hx(0x1D4FD1)), lineWidth: L * 0.9)
            }
            knit.fill(Path(CGRect(x: -w, y: -h * 0.55, width: w * 2, height: h * 0.1)), with: .color(.white.opacity(0.9)))
            g.stroke(dome, with: .color(ink), lineWidth: L)
            let cuff = rrect(-w * 0.54, -h * 0.12, w * 1.08, h * 0.30, h * 0.12)
            g.fill(cuff, with: .color(hx(0x1D4FD1)))
            for i in 0..<9 {
                let x = -w * 0.46 + CGFloat(i) * w * 0.115
                g.fill(rrect(x, -h * 0.08, w * 0.05, h * 0.22, w * 0.02), with: .color(hx(0x3F7BFF)))
            }
            g.stroke(cuff, with: .color(ink), lineWidth: L)
            for (dx, dy) in [(0.0, 0.0), (-0.3, -0.2), (0.3, -0.2), (0, -0.4), (-0.25, 0.2), (0.25, 0.2)] as [(CGFloat, CGFloat)] {
                g.fill(circle(dx * h * 0.25, -h * 1.0 + dy * h * 0.25, h * 0.14), with: .color(.white))
            }
            g.stroke(circle(0, -h * 1.0, h * 0.2), with: .color(hx(0xC9D6F2)), lineWidth: L * 0.7)
        case .bucketHat: bucketHat(&ctx, a, u)
        case .safariHat:
            let g = placed(ctx, 0, top + 0.17 * u, -4)
            let w = 0.30 * u, h = 0.18 * u
            let brim = ellipse(0, 0, w * 0.82, h * 0.26)
            g.fill(brim, with: .color(hx(0xC9A465)))
            g.stroke(brim, with: .color(ink), lineWidth: L)
            var dome = Path()
            dome.move(to: pt(-w * 0.48, 0)); dome.addCurve(to: pt(w * 0.48, 0), control1: pt(-w * 0.5, -h * 1.3), control2: pt(w * 0.5, -h * 1.3)); dome.closeSubpath()
            g.fill(dome, with: lin([hx(0xF0D9A6), hx(0xD4B06E)], pt(-w * 0.3, -h), pt(w * 0.3, 0)))
            g.stroke(dome, with: .color(ink), lineWidth: L)
            g.fill(Path(CGRect(x: -w * 0.47, y: -h * 0.26, width: w * 0.94, height: h * 0.2)), with: .color(hx(0x6B4E2A)))
            g.fill(circle(0, -h * 0.98, h * 0.07), with: .color(hx(0xB8914F)))
        case .cowboyHat:
            let g = placed(ctx, 0, top + 0.16 * u, -5)
            let w = 0.30 * u, h = 0.18 * u
            var brim = Path()
            brim.move(to: pt(-w * 0.95, -h * 0.35))
            brim.addQuadCurve(to: pt(-w * 0.45, h * 0.05), control: pt(-w * 0.85, h * 0.05))
            brim.addQuadCurve(to: pt(w * 0.45, h * 0.05), control: pt(0, h * 0.35))
            brim.addQuadCurve(to: pt(w * 0.95, -h * 0.35), control: pt(w * 0.85, h * 0.05))
            brim.addQuadCurve(to: pt(-w * 0.95, -h * 0.35), control: pt(0, h * 0.5))
            brim.closeSubpath()
            var crown = Path()
            crown.move(to: pt(-w * 0.45, 0)); crown.addLine(to: pt(-w * 0.40, -h * 0.95))
            crown.addQuadCurve(to: pt(0, -h * 0.80), control: pt(-w * 0.2, -h * 1.12))
            crown.addQuadCurve(to: pt(w * 0.40, -h * 0.95), control: pt(w * 0.2, -h * 1.12))
            crown.addLine(to: pt(w * 0.45, 0)); crown.closeSubpath()
            g.fill(crown, with: lin([hx(0xA86A34), hx(0x7A4520)], pt(0, -h), pt(0, 0)))
            g.stroke(crown, with: .color(ink), lineWidth: L)
            g.fill(Path(CGRect(x: -w * 0.44, y: -h * 0.26, width: w * 0.88, height: h * 0.18)), with: .color(hx(0x3B2212)))
            g.fill(circle(w * 0.18, -h * 0.17, h * 0.08), with: .color(hx(0xDDE3EA)))
            g.fill(brim, with: lin([hx(0xB87A3E), hx(0x8A5226)], pt(0, -h * 0.3), pt(0, h * 0.3)))
            g.stroke(brim, with: .color(ink), lineWidth: L)
        case .aviatorCap: aviatorCap(&ctx, a, u)
        case .headlampHelmet:
            let g = placed(ctx, 0, top + 0.19 * u, -3)
            let w = 0.36 * u, h = 0.23 * u
            var beam = Path()
            beam.move(to: pt(w * 0.02, -h * 0.40)); beam.addLine(to: pt(w * 1.3, -h * 1.5)); beam.addLine(to: pt(w * 1.55, -h * 0.35)); beam.closeSubpath()
            g.fill(beam, with: lin([hx(0xFFF6B0, 0.75), hx(0xFFF6B0, 0)], pt(0, -h * 0.4), pt(w * 1.5, -h * 0.9)))
            var dome = Path()
            dome.move(to: pt(-w / 2, 0)); dome.addCurve(to: pt(w / 2, 0), control1: pt(-w / 2, -h * 1.25), control2: pt(w / 2, -h * 1.25)); dome.closeSubpath()
            g.fill(dome, with: lin([hx(0xFFE14D), hx(0xF2A900)], pt(-w * 0.3, -h), pt(w * 0.3, 0)))
            g.fill(rrect(-w * 0.05, -h * 0.92, w * 0.1, h * 0.88, w * 0.04), with: .color(hx(0xE09A00)))
            g.stroke(dome, with: .color(ink), lineWidth: L)
            let rim = rrect(-w * 0.58, -h * 0.08, w * 1.16, h * 0.16, h * 0.08)
            g.fill(rim, with: .color(hx(0xF2A900)))
            g.stroke(rim, with: .color(ink), lineWidth: L)
            g.fill(rrect(-w * 0.16, -h * 0.58, w * 0.32, h * 0.32, h * 0.08), with: .color(hx(0x2B2B33)))
            g.fill(circle(0, -h * 0.42, h * 0.12), with: .color(hx(0xFFFBE0)))
            var glow = g; glow.addFilter(.blur(radius: h * 0.12))
            glow.fill(circle(0, -h * 0.42, h * 0.16), with: .color(hx(0xFFF6B0, 0.8)))
        case .crown:
            crown(&ctx, a, u)
        case .laurelWreath:
            let g = placed(ctx, 0, top + 0.20 * u, 0)
            let R = 0.17 * u
            for side in [-1.0, 1.0] as [CGFloat] {
                var stem = Path()
                stem.addArc(center: pt(0, -R * 0.2), radius: R, startAngle: .degrees(side < 0 ? 100 : 80),
                            endAngle: .degrees(side < 0 ? 215 : -35), clockwise: side > 0)
                g.stroke(stem, with: .color(hx(0x4F7D2A)), lineWidth: L * 1.2)
                for i in 0..<6 {
                    let ang = Double(side < 0 ? 110 + i * 20 : 70 - i * 20) * .pi / 180
                    let c = pt(CGFloat(cos(ang)) * R, -R * 0.2 + CGFloat(sin(ang)) * R)
                    let leaf = placed(g, c.x, c.y, ang * 180 / .pi + (side < 0 ? 60 : -60) + 90)
                    let lf = ellipse(0, -R * 0.14, R * 0.09, R * 0.2)
                    leaf.fill(lf, with: lin([hx(0xB6E86A), hx(0x4F9D2A)], pt(0, -R * 0.3), pt(0, 0)))
                    leaf.stroke(lf, with: .color(hx(0x2F5E16)), lineWidth: L * 0.7)
                }
            }
            g.fill(circle(0, R * 0.78, R * 0.1), with: .color(hx(0xFFCF40)))
            for sx in [-1.0, 1.0] as [CGFloat] {
                g.fill(poly([pt(0, R * 0.78), pt(sx * R * 0.3, R * 1.05), pt(sx * R * 0.2, R * 1.15)]), with: .color(hx(0xFFCF40)))
            }
        case .vikingHelmet:
            let g = placed(ctx, 0, top + 0.20 * u, -2)
            let w = 0.36 * u, h = 0.24 * u
            for sx in [-1.0, 1.0] as [CGFloat] {
                var horn = Path()
                horn.move(to: pt(sx * w * 0.40, -h * 0.35))
                horn.addQuadCurve(to: pt(sx * w * 0.95, -h * 1.35), control: pt(sx * w * 1.05, -h * 0.45))
                horn.addQuadCurve(to: pt(sx * w * 0.42, -h * 0.65), control: pt(sx * w * 0.78, -h * 0.6))
                horn.closeSubpath()
                g.fill(horn, with: lin([hx(0xFFF8E6), hx(0xD9C49A)], pt(sx * w * 0.4, 0), pt(sx * w, -h * 1.3)))
                g.stroke(horn, with: .color(ink), lineWidth: L)
                for t in [0.3, 0.55] as [CGFloat] {
                    var ring = Path(); ring.move(to: pt(sx * w * (0.46 + t * 0.4), -h * (0.4 + t * 0.55))); ring.addLine(to: pt(sx * w * (0.60 + t * 0.4), -h * (0.62 + t * 0.4)))
                    g.stroke(ring, with: .color(hx(0xB8A276)), lineWidth: L)
                }
            }
            var dome = Path()
            dome.move(to: pt(-w / 2, 0)); dome.addCurve(to: pt(w / 2, 0), control1: pt(-w / 2, -h * 1.3), control2: pt(w / 2, -h * 1.3)); dome.closeSubpath()
            g.fill(dome, with: lin([hx(0xE3E9F0), hx(0x8C98A6)], pt(-w * 0.3, -h), pt(w * 0.3, 0)))
            g.fill(rrect(-w * 0.05, -h * 0.96, w * 0.1, h * 0.96, w * 0.03), with: .color(hx(0xC89B3C)))
            g.stroke(dome, with: .color(ink), lineWidth: L)
            let rim = rrect(-w * 0.54, -h * 0.12, w * 1.08, h * 0.2, h * 0.08)
            g.fill(rim, with: .color(hx(0xC89B3C)))
            g.stroke(rim, with: .color(ink), lineWidth: L)
            for i in 0..<5 { g.fill(circle(-w * 0.4 + CGFloat(i) * w * 0.2, -h * 0.02, h * 0.035), with: .color(hx(0xFFE9A8))) }
        case .directorsBeret: beret(&ctx, a, u)
        case .santaHat: santaHat(&ctx, a, u)
        case .leprechaunHat: leprechaunHat(&ctx, a, u)
        case .bunnyEars: bunnyEars(&ctx, a, u)
        case .starHat: starHat(&ctx, a, u)
        case .countdownHat: countdownHat(&ctx, a, u)
        case .partyHat: partyHat(&ctx, a, u)
        case .nightcap: nightcap(&ctx, a, u)
        case .heartBopper: break // drawn by the layer, so it can sway
        default: break
        }
    }

    // MARK: Hats that SIT on him
    //
    // A hat sits where his head is as wide as its band — ~0.36u across,
    // 0.18–0.24u under his tip — and its crown covers the tip, so nothing
    // floats and no flame pokes through a hat that should hide it. Light
    // from the top-left: a sheen on the upper-left, shade low-right.

    /// A soft top-left sheen clipped to `shape`.
    static func sheen(_ g: GraphicsContext, _ shape: Path, _ r: CGRect, _ o: Double = 0.30) {
        var c = g
        c.clip(to: shape)
        let center = pt(r.minX + r.width * 0.32, r.minY + r.height * 0.28)
        c.fill(ellipse(center.x, center.y, r.width * 0.30, r.height * 0.22),
               with: .radialGradient(Gradient(colors: [.white.opacity(o), .white.opacity(0)]),
                                     center: center, startRadius: 0, endRadius: r.width * 0.32))
    }

    /// Open-topped sports visor: a terry band round his head (his flame
    /// pokes out of the top, as a visor's should) and a brim out front.
    static func visor(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let L = lw(u), ink = self.ink
        let g = placed(ctx, 0.005 * u, a.topY + 0.25 * u, -3)
        let w = 0.43 * u, h = 0.075 * u
        let bandShape = band(w: w, h: h, sag: 0.55)
        // Brim first: a wide crescent jutting toward us under the band.
        var brim = Path()
        brim.move(to: pt(-w * 0.50, h * 0.30))
        brim.addQuadCurve(to: pt(w * 0.50, h * 0.30), control: pt(0, h * 1.3))
        brim.addQuadCurve(to: pt(-w * 0.50, h * 0.30), control: pt(0, h * 4.4))
        brim.closeSubpath()
        var drop = g
        drop.addFilter(.shadow(color: .black.opacity(0.35), radius: 0.015 * u, y: 0.012 * u))
        drop.fill(brim, with: lin([hx(0x3CF0D2), hx(0x0E9C88)], pt(0, h * 0.4), pt(0, h * 2.6)))
        var bs = g
        bs.clip(to: brim)
        bs.fill(ellipse(-w * 0.16, h * 1.2, w * 0.2, h * 0.34), with: .color(.white.opacity(0.28)))
        var st = Path()
        st.move(to: pt(-w * 0.40, h * 0.95))
        st.addQuadCurve(to: pt(w * 0.40, h * 0.95), control: pt(0, h * 3.3))
        bs.stroke(st, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: L * 0.8, dash: [L * 2, L * 1.5]))
        g.stroke(brim, with: .color(ink), lineWidth: L)
        g.fill(bandShape, with: lin([.white, hx(0xDDE3EA)], pt(0, -h / 2), pt(0, h)))
        var stripe = g
        stripe.clip(to: bandShape)
        var line = Path()
        line.move(to: pt(-w / 2, 0))
        line.addQuadCurve(to: pt(w / 2, 0), control: pt(0, h * 1.1))
        stripe.stroke(line, with: .color(hx(0x14B8A0)), lineWidth: h * 0.26)
        g.stroke(bandShape, with: .color(ink), lineWidth: L)
    }

    /// The director's beret: a big soft disc slouched over his tip, a rolled
    /// edge hugging his head, a little stalk on top.
    static func beret(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let L = lw(u), ink = self.ink
        let g = placed(ctx, 0.02 * u, a.topY + 0.13 * u, -10)
        let rx = 0.265 * u, ry = 0.115 * u
        var disc = Path()
        disc.move(to: pt(-rx * 0.72, ry * 0.62))
        disc.addCurve(to: pt(rx * 1.02, ry * 0.30), control1: pt(-rx * 1.25, -ry * 1.1), control2: pt(rx * 0.85, -ry * 1.45))
        disc.addQuadCurve(to: pt(-rx * 0.72, ry * 0.62), control: pt(rx * 0.30, ry * 1.25))
        disc.closeSubpath()
        g.fill(disc, with: lin([hx(0x4A4A5C), hx(0x1A1A24)], pt(-rx, -ry), pt(rx, ry)))
        sheen(g, disc, CGRect(x: -rx, y: -ry * 1.2, width: rx * 2, height: ry * 2), 0.22)
        g.stroke(disc, with: .color(ink), lineWidth: L)
        // The rolled edge round his head, with a red piping.
        var edge = Path()
        edge.move(to: pt(-rx * 0.70, ry * 0.52))
        edge.addQuadCurve(to: pt(rx * 0.62, ry * 0.62), control: pt(-rx * 0.02, ry * 1.25))
        g.stroke(edge, with: .color(ink), style: StrokeStyle(lineWidth: 0.045 * u + L * 2, lineCap: .round))
        g.stroke(edge, with: .color(hx(0x24242E)), style: StrokeStyle(lineWidth: 0.045 * u, lineCap: .round))
        g.stroke(edge, with: .color(hx(0xE8384F)), style: StrokeStyle(lineWidth: L * 1.3, lineCap: .round))
        var stalk = Path()
        stalk.move(to: pt(rx * 0.05, -ry * 0.78))
        stalk.addQuadCurve(to: pt(rx * 0.16, -ry * 1.28), control: pt(rx * 0.02, -ry * 1.15))
        g.stroke(stalk, with: .color(hx(0x1A1A24)), style: StrokeStyle(lineWidth: 0.022 * u, lineCap: .round))
    }

    /// Bucket hat: a soft canvas crown over his tip, a brim that droops all
    /// the way round (back half behind the crown, front lip over it).
    static func bucketHat(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let L = lw(u), ink = self.ink
        let g = placed(ctx, 0.005 * u, a.topY + 0.19 * u, -3)
        let w = 0.38 * u, h = 0.21 * u
        let back = ellipse(0, h * 0.02, w * 0.80, h * 0.24)
        g.fill(back, with: .color(hx(0x6E8240)))
        g.stroke(back, with: .color(ink), lineWidth: L)
        var crown = Path()
        crown.move(to: pt(-w * 0.50, h * 0.08))
        crown.addLine(to: pt(-w * 0.40, -h * 0.82))
        crown.addQuadCurve(to: pt(w * 0.40, -h * 0.82), control: pt(0, -h * 1.08))
        crown.addLine(to: pt(w * 0.50, h * 0.08))
        crown.closeSubpath()
        g.fill(crown, with: lin([hx(0xB4C878), hx(0x7E9448)], pt(-w * 0.3, -h), pt(w * 0.3, h * 0.1)))
        sheen(g, crown, CGRect(x: -w / 2, y: -h, width: w, height: h), 0.26)
        g.stroke(crown, with: .color(ink), lineWidth: L)
        var hatBand = Path()
        hatBand.move(to: pt(-w * 0.47, -h * 0.20))
        hatBand.addQuadCurve(to: pt(w * 0.47, -h * 0.20), control: pt(0, -h * 0.08))
        hatBand.addLine(to: pt(w * 0.50, h * 0.06))
        hatBand.addQuadCurve(to: pt(-w * 0.50, h * 0.06), control: pt(0, h * 0.2))
        hatBand.closeSubpath()
        g.fill(hatBand, with: .color(hx(0x55652C)))
        var front = Path()
        front.move(to: pt(-w * 0.80, h * 0.04))
        front.addQuadCurve(to: pt(w * 0.80, h * 0.04), control: pt(0, h * 0.30))
        front.addQuadCurve(to: pt(-w * 0.80, h * 0.04), control: pt(0, h * 0.78))
        front.closeSubpath()
        g.fill(front, with: lin([hx(0xA3B86C), hx(0x7E9448)], pt(0, h * 0.1), pt(0, h * 0.5)))
        var stitch = Path()
        stitch.move(to: pt(-w * 0.62, h * 0.20))
        stitch.addQuadCurve(to: pt(w * 0.62, h * 0.20), control: pt(0, h * 0.62))
        g.stroke(stitch, with: .color(hx(0x55652C)), style: StrokeStyle(lineWidth: L * 0.7, dash: [L * 1.8, L * 1.2]))
        g.stroke(front, with: .color(ink), lineWidth: L)
    }

    /// Leather aviator cap: a dome over his tip, fleece-lined earflaps
    /// hugging his sides, goggles pushed up on the front.
    static func aviatorCap(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let L = lw(u), ink = self.ink
        let g = placed(ctx, 0.01 * u, a.topY + 0.22 * u, -2)
        let w = 0.40 * u, h = 0.26 * u
        let leather = lin([hx(0xA86A3C), hx(0x6B3E20)], pt(-w * 0.3, -h), pt(w * 0.3, h * 0.3))
        for sx in [-1.0, 1.0] as [CGFloat] {
            var flap = Path()
            flap.move(to: pt(sx * w * 0.36, -h * 0.05))
            flap.addLine(to: pt(sx * w * 0.52, -h * 0.02))
            flap.addQuadCurve(to: pt(sx * w * 0.48, h * 0.52), control: pt(sx * w * 0.60, h * 0.30))
            flap.addQuadCurve(to: pt(sx * w * 0.32, h * 0.18), control: pt(sx * w * 0.32, h * 0.52))
            flap.closeSubpath()
            g.stroke(flap, with: .color(hx(0xF3E6CF)), style: StrokeStyle(lineWidth: L * 3.2, lineJoin: .round))
            g.fill(flap, with: leather)
            g.stroke(flap, with: .color(ink), lineWidth: L)
            g.fill(circle(sx * w * 0.47, h * 0.40, h * 0.035), with: .color(hx(0xC9953A)))
        }
        var dome = Path()
        dome.move(to: pt(-w / 2, h * 0.06))
        dome.addCurve(to: pt(w / 2, h * 0.06), control1: pt(-w / 2, -h * 1.22), control2: pt(w / 2, -h * 1.22))
        dome.closeSubpath()
        g.fill(dome, with: leather)
        sheen(g, dome, CGRect(x: -w / 2, y: -h * 0.9, width: w, height: h), 0.26)
        var seam = Path()
        seam.move(to: pt(0, -h * 0.88))
        seam.addLine(to: pt(0, h * 0.04))
        g.stroke(seam, with: .color(hx(0x4A2A14)), style: StrokeStyle(lineWidth: L * 0.8, dash: [L * 1.5, L]))
        g.stroke(dome, with: .color(ink), lineWidth: L)
        var trim = Path()
        trim.move(to: pt(-w * 0.50, h * 0.03))
        trim.addQuadCurve(to: pt(w * 0.50, h * 0.03), control: pt(0, h * 0.24))
        g.stroke(trim, with: .color(ink), style: StrokeStyle(lineWidth: h * 0.20 + L * 2, lineCap: .round))
        g.stroke(trim, with: .color(hx(0xF6EAD2)), style: StrokeStyle(lineWidth: h * 0.20, lineCap: .round))
        let gy = -h * 0.42
        var strap = Path()
        strap.move(to: pt(-w * 0.49, gy + h * 0.06))
        strap.addQuadCurve(to: pt(w * 0.49, gy + h * 0.06), control: pt(0, gy + h * 0.16))
        g.stroke(strap, with: .color(hx(0x2B2B33)), lineWidth: h * 0.11)
        for sx in [-1.0, 1.0] as [CGFloat] {
            let c = pt(sx * w * 0.19, gy)
            g.fill(circle(c.x, c.y, h * 0.21), with: .color(hx(0xC9953A)))
            g.stroke(circle(c.x, c.y, h * 0.21), with: .color(ink), lineWidth: L)
            g.fill(circle(c.x, c.y, h * 0.15), with: lin([hx(0x9FE3FF), hx(0x3A7BD5)], pt(c.x - h * 0.14, c.y - h * 0.14), pt(c.x + h * 0.14, c.y + h * 0.14)))
            g.fill(circle(c.x - h * 0.05, c.y - h * 0.05, h * 0.045), with: .color(.white.opacity(0.9)))
        }
    }

    /// A cone hat worn ON his tip: the base is as wide as his head where it
    /// sits, so the tip is inside it — never a cone balanced above him.
    static func cone(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat, tilt: Double,
                     fill: GraphicsContext.Shading, stripes: Color, trim: Color, pom: Color, dark: Bool) {
        let L = lw(u), ink = self.ink
        let bw = 0.30 * u, ht = coneHeight * u
        let g = placed(ctx, 0.01 * u, a.topY + 0.16 * u, tilt)
        var c = Path()
        c.move(to: pt(-bw / 2, 0))
        c.addQuadCurve(to: pt(0, -ht), control: pt(-bw * 0.28, -ht * 0.5))
        c.addQuadCurve(to: pt(bw / 2, 0), control: pt(bw * 0.28, -ht * 0.5))
        c.addQuadCurve(to: pt(-bw / 2, 0), control: pt(0, bw * 0.16))
        c.closeSubpath()
        g.fill(c, with: fill)
        var st = g
        st.clip(to: c)
        for t in [0.30, 0.58] as [CGFloat] {
            var stripe = Path()
            stripe.move(to: pt(-bw, -ht * t + bw * 0.06))
            stripe.addQuadCurve(to: pt(bw, -ht * t + bw * 0.06), control: pt(0, -ht * t + bw * 0.16))
            st.stroke(stripe, with: .color(stripes), lineWidth: ht * 0.09)
        }
        st.fill(ellipse(-bw * 0.16, -ht * 0.55, bw * 0.08, ht * 0.30), with: .color(.white.opacity(dark ? 0.16 : 0.28)))
        g.stroke(c, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
        var t = Path()
        t.move(to: pt(-bw * 0.52, 0))
        t.addQuadCurve(to: pt(bw * 0.52, 0), control: pt(0, bw * 0.17))
        g.stroke(t, with: .color(ink), style: StrokeStyle(lineWidth: 0.04 * u + L * 2, lineCap: .round))
        g.stroke(t, with: .color(trim), style: StrokeStyle(lineWidth: 0.04 * u, lineCap: .round))
        var gl = g
        gl.addFilter(.blur(radius: 0.02 * u))
        gl.fill(circle(0, -ht, 0.05 * u), with: .color(pom.opacity(0.6)))
        g.fill(circle(0, -ht, 0.038 * u), with: .radialGradient(Gradient(colors: [.white, pom]), center: pt(-0.012 * u, -ht - 0.012 * u),
                                                                 startRadius: 0, endRadius: 0.05 * u))
        g.stroke(circle(0, -ht, 0.038 * u), with: .color(ink), lineWidth: L * 0.8)
    }

    static let coneHeight: CGFloat = 0.36

    /// The crown: 1,000 lifetime miles, so it is BIG — five pearl-tipped
    /// points, a jewelled band curving round his tip, red velvet showing
    /// between the points, a metallic gradient with a light edge.
    static func crown(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let L = lw(u)
        let w = 0.50 * u, h = 0.32 * u
        let g = placed(ctx, 0.01 * u, a.topY + 0.11 * u, -7)
        let goldFill = lin([hx(0xFFF6C4), hx(0xFFD24A), hx(0xE0A512), hx(0xB57A0A)], pt(-w * 0.3, -h * 0.9), pt(w * 0.3, h * 0.2))
        let dark = hx(0x7A4E00)
        // Velvet cap behind the points.
        var velvet = Path()
        velvet.move(to: pt(-w * 0.44, -h * 0.02))
        velvet.addQuadCurve(to: pt(w * 0.44, -h * 0.02), control: pt(0, -h * 0.95))
        velvet.closeSubpath()
        g.fill(velvet, with: lin([hx(0xE0243A), hx(0x8A0A20)], pt(0, -h * 0.6), pt(0, 0)))
        // The points: a single outline with five peaks, back ones smaller.
        // Broad, chunky points (valleys sit low, so each point is a real
        // wedge, not a spike) — reads as a crown at 28pt.
        let peaks: [(x: CGFloat, top: CGFloat)] = [(-0.47, -0.74), (-0.24, -0.90), (0.0, -1.0), (0.24, -0.90), (0.47, -0.74)]
        var body = Path()
        body.move(to: pt(-w * 0.5, h * 0.12))
        body.addLine(to: pt(-w * 0.5, -h * 0.10))
        for (i, p) in peaks.enumerated() {
            let valleyX = i == 0 ? -0.5 : (peaks[i - 1].x + p.x) / 2
            if i > 0 { body.addLine(to: pt(w * valleyX, -h * 0.34)) }
            body.addLine(to: pt(w * p.x, h * p.top))
        }
        body.addLine(to: pt(w * 0.5, -h * 0.10))
        body.addLine(to: pt(w * 0.5, h * 0.12))
        body.addQuadCurve(to: pt(-w * 0.5, h * 0.12), control: pt(0, h * 0.34))
        body.closeSubpath()
        g.fill(body, with: goldFill)
        // Light down the left of every point: the metal catching the light.
        var shine = g
        shine.clip(to: body)
        for p in peaks {
            var s = Path()
            s.move(to: pt(w * p.x - w * 0.02, h * p.top + h * 0.12))
            s.addLine(to: pt(w * p.x - w * 0.07, -h * 0.12))
            shine.stroke(s, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: L * 1.4, lineCap: .round))
        }
        // Band.
        var bandPath = Path()
        bandPath.move(to: pt(-w * 0.5, -h * 0.10))
        bandPath.addQuadCurve(to: pt(w * 0.5, -h * 0.10), control: pt(0, h * 0.10))
        bandPath.addLine(to: pt(w * 0.5, h * 0.12))
        bandPath.addQuadCurve(to: pt(-w * 0.5, h * 0.12), control: pt(0, h * 0.34))
        bandPath.closeSubpath()
        g.fill(bandPath, with: lin([hx(0xFFE27A), hx(0xC98A12)], pt(0, -h * 0.1), pt(0, h * 0.25)))
        g.stroke(body, with: .color(dark), style: StrokeStyle(lineWidth: L * 1.1, lineJoin: .round))
        g.stroke(bandPath, with: .color(dark), style: StrokeStyle(lineWidth: L * 0.9, lineJoin: .round))
        // Jewels on the band: ruby centre, sapphires, emeralds.
        let jewels: [(CGFloat, Color, CGFloat)] = [(0, hx(0xE8243F), 0.058), (-0.28, hx(0x2F7BFF), 0.042),
                                                   (0.28, hx(0x2F7BFF), 0.042), (-0.44, hx(0x22B45A), 0.03),
                                                   (0.44, hx(0x22B45A), 0.03)]
        for (x, c, r) in jewels {
            let y = h * 0.05 + h * 0.10 * (1 - (x / 0.5) * (x / 0.5))
            g.fill(circle(w * x, y, r * u), with: .color(c))
            g.stroke(circle(w * x, y, r * u), with: .color(dark), lineWidth: L * 0.7)
            g.fill(circle(w * x - r * u * 0.35, y - r * u * 0.35, r * u * 0.3), with: .color(.white.opacity(0.85)))
        }
        // Pearls on the tips.
        // Pearls SEATED on the tips (centred on the point, not floating).
        for p in peaks {
            let r = (p.top < -0.95 ? 0.036 : 0.029) * u
            let c = pt(w * p.x, h * p.top + r * 0.15)
            g.fill(circle(c.x, c.y, r), with: .radialGradient(Gradient(colors: [.white, hx(0xFFE9A8), hx(0xE0B34A)]),
                                                              center: pt(c.x - r * 0.35, c.y - r * 0.35),
                                                              startRadius: 0, endRadius: r * 1.5))
            g.stroke(circle(c.x, c.y, r), with: .color(dark), lineWidth: L * 0.7)
        }
    }

    // MARK: Eyewear

    static func eyewear(_ item: FlameyItem, _ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let L = lw(u)
        let ey = a.faceY
        switch item {
        case .starStickers:
            for (sx, c, r, rot) in [(-1.0, hx(0xFFCF40), 0.07, -12.0), (1.0, hx(0xFF6FAE), 0.06, 14.0)] as [(CGFloat, Color, CGFloat, Double)] {
                let g = placed(ctx, sx * (a.eyeX + 0.075 * u), ey + 0.10 * u, rot)
                g.fill(star(0, 0, r * u * 1.3, inner: 0.52), with: .color(.white))
                g.fill(star(0, 0, r * u, inner: 0.5), with: .color(c))
                g.fill(circle(-r * u * 0.25, -r * u * 0.25, r * u * 0.16), with: .color(.white.opacity(0.7)))
            }
            let g = placed(ctx, 0.20 * u, ey - 0.17 * u, 20)
            g.fill(star(0, 0, 0.048 * u, inner: 0.5), with: .color(.white))
            g.fill(star(0, 0, 0.036 * u, inner: 0.5), with: .color(hx(0x5CC8FF)))
        case .roundSpecs:
            let r = 0.098 * u
            let frame = hx(0x8A5A1E)
            for sx in [-1.0, 1.0] as [CGFloat] {
                let c = circle(sx * a.eyeX, ey, r)
                ctx.fill(c, with: .color(.white.opacity(0.14)))
                ctx.stroke(c, with: .color(frame), lineWidth: L * 1.6)
                var gl = Path(); gl.addArc(center: pt(sx * a.eyeX, ey), radius: r * 0.72, startAngle: .degrees(200), endAngle: .degrees(240), clockwise: false)
                ctx.stroke(gl, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: L * 1.1, lineCap: .round))
            }
            var br = Path(); br.move(to: pt(-a.eyeX + r, ey - r * 0.1)); br.addQuadCurve(to: pt(a.eyeX - r, ey - r * 0.1), control: pt(0, ey - r * 0.5))
            ctx.stroke(br, with: .color(frame), lineWidth: L * 1.6)
            for sx in [-1.0, 1.0] as [CGFloat] {
                var arm = Path(); arm.move(to: pt(sx * (a.eyeX + r), ey - r * 0.2)); arm.addLine(to: pt(sx * (a.eyeX + r * 1.6), ey - r * 0.35))
                ctx.stroke(arm, with: .color(frame), lineWidth: L * 1.6)
            }
        case .classicShades, .moodShades:
            shades(&ctx, a, u)
        case .aviators:
            let frame = hx(0xD4A43A)
            for sx in [-1.0, 1.0] as [CGFloat] {
                var lens = Path()
                let cx = sx * a.eyeX
                lens.move(to: pt(cx - sx * 0.10 * u, ey - 0.075 * u))
                lens.addLine(to: pt(cx + sx * 0.10 * u, ey - 0.075 * u))
                lens.addQuadCurve(to: pt(cx + sx * 0.03 * u, ey + 0.10 * u), control: pt(cx + sx * 0.12 * u, ey + 0.08 * u))
                lens.addQuadCurve(to: pt(cx - sx * 0.10 * u, ey - 0.075 * u), control: pt(cx - sx * 0.12 * u, ey + 0.09 * u))
                lens.closeSubpath()
                ctx.fill(lens, with: lin([hx(0x3A2410), hx(0xC0741C)], pt(0, ey - 0.08 * u), pt(0, ey + 0.1 * u)))
                var sh = ctx; sh.clip(to: lens)
                sh.fill(Path(CGRect(x: cx - 0.12 * u, y: ey - 0.08 * u, width: 0.24 * u, height: 0.05 * u)), with: .color(.white.opacity(0.22)))
                ctx.stroke(lens, with: .color(frame), style: StrokeStyle(lineWidth: L * 1.4, lineJoin: .round))
            }
            var b1 = Path(); b1.move(to: pt(-a.eyeX + 0.10 * u, ey - 0.07 * u)); b1.addLine(to: pt(a.eyeX - 0.10 * u, ey - 0.07 * u))
            ctx.stroke(b1, with: .color(frame), lineWidth: L * 1.4)
            var b2 = Path(); b2.move(to: pt(-a.eyeX + 0.09 * u, ey - 0.03 * u)); b2.addQuadCurve(to: pt(a.eyeX - 0.09 * u, ey - 0.03 * u), control: pt(0, ey - 0.07 * u))
            ctx.stroke(b2, with: .color(frame), lineWidth: L)
        case .heartGlasses:
            for sx in [-1.0, 1.0] as [CGFloat] {
                let hxp = sx * a.eyeX, r = 0.088 * u
                var heart = Path()
                heart.move(to: pt(hxp, ey + r * 1.05))
                heart.addCurve(to: pt(hxp, ey - r * 0.55), control1: pt(hxp - r * 1.7, ey - r * 0.1), control2: pt(hxp - r * 1.0, ey - r * 1.5))
                heart.addCurve(to: pt(hxp, ey + r * 1.05), control1: pt(hxp + r * 1.0, ey - r * 1.5), control2: pt(hxp + r * 1.7, ey - r * 0.1))
                heart.closeSubpath()
                ctx.fill(heart, with: lin([hx(0xFF7AA8), hx(0xE8195A)], pt(hxp, ey - r), pt(hxp, ey + r)))
                ctx.stroke(heart, with: .color(.white), style: StrokeStyle(lineWidth: L * 1.5, lineJoin: .round))
                ctx.fill(ellipse(hxp - r * 0.45, ey - r * 0.35, r * 0.22, r * 0.14), with: .color(.white.opacity(0.7)))
            }
            var br = Path(); br.move(to: pt(-a.eyeX + 0.07 * u, ey - 0.04 * u)); br.addLine(to: pt(a.eyeX - 0.07 * u, ey - 0.04 * u))
            ctx.stroke(br, with: .color(.white), lineWidth: L * 1.5)
        case .cyberVisor:
            let w = 0.54 * u, h = 0.14 * u
            var v = Path()
            v.move(to: pt(-w / 2, ey - h * 0.45))
            v.addQuadCurve(to: pt(w / 2, ey - h * 0.45), control: pt(0, ey - h * 0.75))
            v.addLine(to: pt(w * 0.46, ey + h * 0.35))
            v.addQuadCurve(to: pt(-w * 0.46, ey + h * 0.35), control: pt(0, ey + h * 0.65))
            v.closeSubpath()
            var glow = ctx; glow.addFilter(.blur(radius: 0.03 * u))
            glow.fill(v, with: .color(hx(0x2EF2FF, 0.7)))
            ctx.fill(v, with: lin([hx(0x0E1B3A), hx(0x163A6B)], pt(0, ey - h), pt(0, ey + h)))
            var sc = ctx; sc.clip(to: v)
            for i in 0..<5 {
                sc.fill(Path(CGRect(x: -w, y: ey - h * 0.5 + CGFloat(i) * h * 0.22, width: w * 2, height: h * 0.05)), with: .color(hx(0x2EF2FF, 0.25)))
            }
            var line = Path(); line.move(to: pt(-w * 0.34, ey)); line.addLine(to: pt(-w * 0.12, ey)); line.move(to: pt(w * 0.12, ey)); line.addLine(to: pt(w * 0.34, ey))
            sc.stroke(line, with: .color(hx(0x9CFFFF)), style: StrokeStyle(lineWidth: h * 0.18, lineCap: .round))
            ctx.stroke(v, with: .color(hx(0x9CFFFF)), lineWidth: L * 1.2)
        case .starGlasses:
            let gold = hx(0xFFCF40), dark = hx(0xB8860B)
            for side in [-1.0, 1.0] as [CGFloat] {
                let p = star(side * a.eyeX, ey - 0.005 * u, 0.13 * u, inner: 0.5)
                ctx.fill(p, with: .color(gold))
                ctx.stroke(p, with: .color(dark), style: StrokeStyle(lineWidth: max(1, 0.006 * u), lineJoin: .round))
            }
            ctx.fill(Path(CGRect(x: -0.03 * u, y: ey - 0.02 * u, width: 0.06 * u, height: 0.018 * u)), with: .color(dark))
        default: break
        }
    }

    /// Mile banked (and the Classic Shades): lenses LARGER than the eyes on
    /// every axis, so no eye peeks out around a lens.
    static func shades(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let g = placed(ctx, 0, a.faceY - 0.005 * u)
        let lw = 0.20 * u, lh = 0.185 * u
        let frame = Color(red: 0.18, green: 0.16, blue: 0.20)
        for side in [-1.0, 1.0] as [CGFloat] {
            let rect = CGRect(x: side * a.eyeX - lw / 2, y: -lh / 2, width: lw, height: lh)
            let lens = Path(roundedRect: rect, cornerRadius: lh * 0.45, style: .continuous)
            g.fill(lens, with: .color(Color(red: 0.08, green: 0.07, blue: 0.10)))
            g.fill(lens, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.28), .clear]),
                                               startPoint: rect.origin, endPoint: pt(rect.midX, rect.midY)))
            g.stroke(lens, with: .color(frame), lineWidth: max(1, u * 0.006))
        }
        let bridgeW = max(2, a.eyeX * 2 - lw + u * 0.02)
        let bridgeH = max(1.5, u * 0.012)
        g.fill(Path(roundedRect: CGRect(x: -bridgeW / 2, y: -bridgeH / 2, width: bridgeW, height: bridgeH),
                    cornerRadius: bridgeH / 2), with: .color(frame))
        for side in [-1.0, 1.0] as [CGFloat] {
            let armW = 0.06 * u
            let cx = side * (a.eyeX + lw / 2 + 0.025 * u)
            g.fill(Path(roundedRect: CGRect(x: cx - armW / 2, y: -lh * 0.15 - bridgeH / 2, width: armW, height: bridgeH),
                        cornerRadius: bridgeH / 2), with: .color(frame))
        }
    }

    // MARK: Chest (flat, under the mouth — there is no neck)

    /// The chest band, in body units above his base: his grin ends ~0.13u
    /// above it, so every piece lives between `chestTop` and his base,
    /// CENTRED under the mouth and spanning most of his width — his arms
    /// hinge at ±0.285u well above it, so nothing they do covers it. Bold
    /// shapes and a heavier ink than the hats: the band is only 0.13u tall,
    /// and a chest piece has to read on the 72pt Closet tile and the widget.
    static let chestTop: CGFloat = 0.125

    static func chest(_ item: FlameyItem, _ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let L = max(1.1, 0.013 * u)
        let ink = self.ink
        let b = a.bottom
        let top = b - chestTop * u
        func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { pt(x * u, b + y * u) }
        // His outline at chest height, for anything that wraps round him.
        let body = FlameBuddyOuterShape(wobble: 0).path(in: bodyRect(a, u))
        switch item {
        case .bandana:
            // A cowboy neckerchief: a band snug round him and a big spotted
            // triangle hanging down his middle.
            let blue = hx(0x2563EB), light = hx(0x5B9BFF)
            var band = Path()
            band.move(to: q(-0.34, -0.125)); band.addQuadCurve(to: q(0.34, -0.125), control: q(0, -0.085))
            band.addLine(to: q(0.33, -0.085)); band.addQuadCurve(to: q(-0.33, -0.085), control: q(0, -0.045)); band.closeSubpath()
            var wrap = ctx; wrap.clip(to: body)
            wrap.fill(band, with: .color(blue))
            wrap.stroke(band, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
            var tri = Path()
            tri.move(to: q(-0.19, -0.11))
            tri.addQuadCurve(to: q(0.19, -0.11), control: q(0, -0.075))
            tri.addQuadCurve(to: q(0, 0.005), control: q(0.07, -0.05))
            tri.addQuadCurve(to: q(-0.19, -0.11), control: q(-0.07, -0.05))
            tri.closeSubpath()
            ctx.fill(tri, with: lin([light, blue], q(0, -0.11), q(0, 0.0)))
            var dots = ctx; dots.clip(to: tri)
            for (x, y) in [(-0.11, -0.085), (0.0, -0.075), (0.11, -0.085), (-0.05, -0.045), (0.05, -0.045), (0.0, -0.015)] as [(CGFloat, CGFloat)] {
                dots.fill(circle(x * u, b + y * u, 0.014 * u), with: .color(.white))
            }
            ctx.stroke(tri, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
            // The knot, centred at the top of the point.
            ctx.fill(ellipse(0, b - 0.098 * u, 0.034 * u, 0.026 * u), with: .color(light))
            ctx.stroke(ellipse(0, b - 0.098 * u, 0.034 * u, 0.026 * u), with: .color(ink), lineWidth: L)
        case .bowTie:
            // A big, bold polka-dot bow tie right under his grin.
            let cy = b - 0.085 * u
            let w = 0.17 * u, h = 0.065 * u
            let red = hx(0xE0243A)
            for sx in [-1.0, 1.0] as [CGFloat] {
                var wing = Path()
                wing.move(to: pt(sx * 0.02 * u, cy - h * 0.25))
                wing.addQuadCurve(to: pt(sx * w, cy - h), control: pt(sx * w * 0.45, cy - h * 1.15))
                wing.addQuadCurve(to: pt(sx * w, cy + h), control: pt(sx * w * 1.14, cy))
                wing.addQuadCurve(to: pt(sx * 0.02 * u, cy + h * 0.25), control: pt(sx * w * 0.45, cy + h * 1.15))
                wing.closeSubpath()
                ctx.fill(wing, with: lin([hx(0xFF4D63), red, hx(0xA8122C)], pt(0, cy - h), pt(0, cy + h)))
                var dots = ctx; dots.clip(to: wing)
                for (dx, dy) in [(0.42, -0.45), (0.78, 0.05), (0.40, 0.55), (0.80, -0.75), (0.95, 0.75)] as [(CGFloat, CGFloat)] {
                    dots.fill(circle(sx * w * dx, cy + h * dy, h * 0.17), with: .color(.white))
                }
                // A fold line toward the knot.
                var fold = Path(); fold.move(to: pt(sx * 0.04 * u, cy)); fold.addQuadCurve(to: pt(sx * w * 0.62, cy - h * 0.2), control: pt(sx * w * 0.3, cy + h * 0.2))
                ctx.stroke(fold, with: .color(hx(0x7E0A1E, 0.6)), style: StrokeStyle(lineWidth: L * 0.8, lineCap: .round))
                ctx.stroke(wing, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
            }
            let knot = rrect(-0.034 * u, cy - h * 0.62, 0.068 * u, h * 1.24, 0.018 * u)
            ctx.fill(knot, with: .color(hx(0xB3152F)))
            ctx.stroke(knot, with: .color(ink), lineWidth: L)
        case .finisherMedal:
            // Striped ribbon in a V from his sides, a big gold disc at the point.
            let my = b - 0.02 * u, R = 0.068 * u
            for (sx, c) in [(-1.0, hx(0x2F6BFF)), (1.0, hx(0xE0243A))] as [(CGFloat, Color)] {
                var r = Path()
                r.move(to: q(sx * 0.29, -0.135)); r.addLine(to: q(sx * 0.15, -0.135))
                r.addLine(to: pt(sx * 0.004 * u, my - R * 0.4)); r.addLine(to: pt(sx * 0.085 * u, my - R * 0.75)); r.closeSubpath()
                var wrap = ctx; wrap.clip(to: body)
                wrap.fill(r, with: .color(c))
                var stripe = wrap; stripe.clip(to: r)
                var s = Path(); s.move(to: q(sx * 0.20, -0.14)); s.addLine(to: pt(sx * 0.04 * u, my - R * 0.6))
                stripe.stroke(s, with: .color(.white.opacity(0.85)), lineWidth: 0.014 * u)
                wrap.stroke(r, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
            }
            medal(&ctx, 0, my, R, L)
        case .starBadge:
            // A sheriff's star pinned dead centre, with two ribbon tails.
            let cx: CGFloat = 0, cy = b - 0.062 * u, R = 0.098 * u
            for (dx, c, ang) in [(-0.34, hx(0x2F6BFF), 14.0), (0.34, hx(0xE0243A), -14.0)] as [(CGFloat, Color, Double)] {
                let t = placed(ctx, cx + dx * R, cy + R * 0.35, ang)
                let tail = poly([pt(-R * 0.22, 0), pt(R * 0.22, 0), pt(R * 0.22, R * 0.95), pt(0, R * 0.72), pt(-R * 0.22, R * 0.95)])
                t.fill(tail, with: .color(c)); t.stroke(tail, with: .color(ink), style: StrokeStyle(lineWidth: L * 0.9, lineJoin: .round))
            }
            var glow = ctx; glow.addFilter(.blur(radius: R * 0.35)); glow.fill(circle(cx, cy, R * 0.85), with: .color(hx(0xFFD24A, 0.6)))
            let s = star(cx, cy, R, inner: 0.52)
            ctx.fill(s, with: lin([hx(0xFFF6C4), hx(0xFFCF40), hx(0xD99A10)], pt(cx - R, cy - R), pt(cx + R, cy + R)))
            ctx.stroke(s, with: .color(hx(0x6A4300)), style: StrokeStyle(lineWidth: L, lineJoin: .round))
            for i in 0..<5 {
                let ang = -Double.pi / 2 + Double(i) * 2 * .pi / 5
                ctx.fill(circle(cx + CGFloat(cos(ang)) * R * 0.98, cy + CGFloat(sin(ang)) * R * 0.98, R * 0.1), with: .color(hx(0xFFE27A)))
            }
            ctx.fill(circle(cx, cy, R * 0.30), with: .color(hx(0xFFF8DC)))
            ctx.stroke(circle(cx, cy, R * 0.30), with: .color(hx(0xB57F0C)), lineWidth: L * 0.8)
            ctx.fill(star(cx, cy, R * 0.18, inner: 0.45), with: .color(hx(0xD99A10)))
        case .championSash:
            // Over his shoulder, across his front, under the grin — a wide
            // red band trimmed in gold, clipped to his outline, with a
            // rosette where it crosses his middle.
            var g = ctx; g.clip(to: body)
            let p0 = q(-0.46, -0.13), p1 = q(0.44, 0.005)
            let dx = p1.x - p0.x, dy = p1.y - p0.y
            let len = sqrt(dx * dx + dy * dy)
            let nxv = -dy / len * 0.045 * u, nyv = dx / len * 0.045 * u
            let sash = poly([pt(p0.x - nxv, p0.y - nyv), pt(p1.x - nxv, p1.y - nyv), pt(p1.x + nxv, p1.y + nyv), pt(p0.x + nxv, p0.y + nyv)])
            g.fill(sash, with: lin([hx(0xF0334C), hx(0xB3152F)], p0, p1))
            for s in [-1.0, 1.0] as [CGFloat] {
                var edge = Path()
                edge.move(to: pt(p0.x + s * nxv * 0.72, p0.y + s * nyv * 0.72)); edge.addLine(to: pt(p1.x + s * nxv * 0.72, p1.y + s * nyv * 0.72))
                g.stroke(edge, with: .color(hx(0xFFCF40)), lineWidth: 0.012 * u)
            }
            g.stroke(sash, with: .color(ink), lineWidth: L)
            let rx = 0.06 * u, ry = b - 0.055 * u, rr = 0.055 * u
            for i in 0..<12 {
                let ang = Double(i) / 12 * 2 * .pi
                ctx.fill(circle(rx + CGFloat(cos(ang)) * rr * 0.74, ry + CGFloat(sin(ang)) * rr * 0.74, rr * 0.36),
                         with: .color(i % 2 == 0 ? hx(0xFFCF40) : hx(0xFFE27A)))
            }
            ctx.stroke(circle(rx, ry, rr * 1.07), with: .color(hx(0x8A5A00, 0.8)), lineWidth: L * 0.8)
            ctx.fill(circle(rx, ry, rr * 0.55), with: .color(hx(0xE0243A)))
            ctx.stroke(circle(rx, ry, rr * 0.55), with: .color(ink), lineWidth: L * 0.9)
            ctx.fill(star(rx, ry, rr * 0.38, inner: 0.45), with: .color(hx(0xFFF3B0)))
        case .goldChain:
            // A heavy rope chain and a big gold flame medallion.
            chain(&ctx, a, u, body)
            let py = b - 0.035 * u
            var glow = ctx; glow.addFilter(.blur(radius: 0.035 * u)); glow.fill(circle(0, py, 0.07 * u), with: .color(hx(0xFFD24A, 0.7)))
            let disc = circle(0, py, 0.062 * u)
            ctx.fill(disc, with: lin([hx(0xFFF3B0), hx(0xFFCF40), hx(0xC98A12)], pt(0, py - 0.062 * u), pt(0, py + 0.062 * u)))
            ctx.stroke(disc, with: .color(hx(0x6A4300)), lineWidth: L)
            let fl = FlameBuddyOuterShape(wobble: 0).path(in: CGRect(x: -0.032 * u, y: py - 0.045 * u, width: 0.064 * u, height: 0.08 * u))
            ctx.fill(fl, with: lin([hx(0xFFB020), hx(0xD9431F)], pt(0, py - 0.045 * u), pt(0, py + 0.035 * u)))
            ctx.stroke(fl, with: .color(hx(0x6A4300)), lineWidth: L * 0.7)
            ctx.fill(circle(-0.028 * u, py - 0.03 * u, 0.012 * u), with: .color(.white.opacity(0.9)))
        case .trophyPendant:
            chain(&ctx, a, u, body)
            let py = b - 0.04 * u
            var glow = ctx; glow.addFilter(.blur(radius: 0.035 * u)); glow.fill(circle(0, py, 0.075 * u), with: .color(hx(0xFFD24A, 0.75)))
            let goldFill = lin([hx(0xFFF3B0), hx(0xFFCF40), hx(0xC98A12)], pt(-0.07 * u, py - 0.06 * u), pt(0.07 * u, py + 0.06 * u))
            for sx in [-1.0, 1.0] as [CGFloat] {
                var handle = Path()
                handle.addArc(center: pt(sx * 0.058 * u, py - 0.022 * u), radius: 0.026 * u,
                              startAngle: .degrees(sx < 0 ? 90 : -90), endAngle: .degrees(sx < 0 ? 270 : 90), clockwise: false)
                ctx.stroke(handle, with: .color(hx(0x6A4300)), lineWidth: 0.016 * u + L)
                ctx.stroke(handle, with: .color(hx(0xFFCF40)), lineWidth: 0.016 * u)
            }
            var cup = Path()
            cup.move(to: pt(-0.065 * u, py - 0.06 * u)); cup.addLine(to: pt(0.065 * u, py - 0.06 * u))
            cup.addQuadCurve(to: pt(0.014 * u, py + 0.03 * u), control: pt(0.065 * u, py + 0.012 * u))
            cup.addLine(to: pt(-0.014 * u, py + 0.03 * u))
            cup.addQuadCurve(to: pt(-0.065 * u, py - 0.06 * u), control: pt(-0.065 * u, py + 0.012 * u))
            cup.closeSubpath()
            ctx.fill(cup, with: goldFill)
            ctx.stroke(cup, with: .color(hx(0x6A4300)), style: StrokeStyle(lineWidth: L, lineJoin: .round))
            let foot = rrect(-0.045 * u, py + 0.028 * u, 0.09 * u, 0.028 * u, 0.008 * u)
            ctx.fill(foot, with: goldFill)
            ctx.stroke(foot, with: .color(hx(0x6A4300)), lineWidth: L)
            ctx.fill(star(0, py - 0.022 * u, 0.024 * u, inner: 0.45), with: .color(.white.opacity(0.95)))
        case .polaroid:
            // A snapshot on a cord round his neck, a touch askew.
            var cord = Path()
            cord.move(to: q(-0.26, -0.13)); cord.addQuadCurve(to: q(-0.02, -0.10), control: q(-0.14, -0.08))
            cord.move(to: q(0.26, -0.13)); cord.addQuadCurve(to: q(0.02, -0.10), control: q(0.14, -0.08))
            var wrap = ctx; wrap.clip(to: body)
            wrap.stroke(cord, with: .color(hx(0x2B2B33)), style: StrokeStyle(lineWidth: 0.014 * u, lineCap: .round))
            let g = placed(ctx, 0, b - 0.045 * u, -7)
            let fw = 0.19 * u, fh = 0.15 * u
            let frame = rrect(-fw / 2, -fh / 2, fw, fh, 0.01 * u)
            var shadow = g; shadow.addFilter(.shadow(color: .black.opacity(0.4), radius: 0.012 * u, y: 0.006 * u))
            shadow.fill(frame, with: .color(hx(0xFBFAF6)))
            let photo = CGRect(x: -fw / 2 + 0.016 * u, y: -fh / 2 + 0.016 * u, width: fw - 0.032 * u, height: fh * 0.66)
            g.fill(Path(photo), with: lin([hx(0x5DB8FF), hx(0xFFD9A0)], pt(0, photo.minY), pt(0, photo.maxY)))
            var pic = g; pic.clip(to: Path(photo))
            pic.fill(circle(photo.maxX - photo.width * 0.25, photo.minY + photo.height * 0.32, photo.height * 0.2), with: .color(hx(0xFFE14D)))
            var hill = Path()
            hill.move(to: pt(photo.minX, photo.maxY))
            hill.addQuadCurve(to: pt(photo.maxX, photo.maxY - photo.height * 0.15), control: pt(photo.minX + photo.width * 0.35, photo.maxY - photo.height * 0.8))
            hill.addLine(to: pt(photo.maxX, photo.maxY)); hill.closeSubpath()
            pic.fill(hill, with: .color(hx(0x3FAE5A)))
            g.stroke(Path(photo), with: .color(hx(0x2B2B33, 0.5)), lineWidth: L * 0.6)
            g.stroke(frame, with: .color(ink), lineWidth: L)
            g.fill(rrect(-0.022 * u, -fh / 2 - 0.014 * u, 0.044 * u, 0.024 * u, 0.005 * u), with: .color(hx(0xE8384F)))
        case .holidayScarf:
            // Christmas: a chunky striped scarf wrapped round him, the knot
            // and two fringed tails hanging down his front.
            let green = hx(0x1F9D55), red = hx(0xE0243A)
            var wrapPath = Path()
            wrapPath.move(to: q(-0.40, -0.135)); wrapPath.addQuadCurve(to: q(0.40, -0.135), control: q(0, -0.09))
            wrapPath.addLine(to: q(0.39, -0.075)); wrapPath.addQuadCurve(to: q(-0.39, -0.075), control: q(0, -0.03)); wrapPath.closeSubpath()
            var wrap = ctx; wrap.clip(to: body)
            wrap.fill(wrapPath, with: .color(green))
            var stripes = wrap; stripes.clip(to: wrapPath)
            for f in stride(from: -0.40, through: 0.40, by: 0.10) {
                stripes.fill(poly([q(f, -0.2), q(f + 0.04, -0.2), q(f + 0.02, 0.0), q(f - 0.02, 0.0)]), with: .color(red))
            }
            wrap.stroke(wrapPath, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
            for (dx, ang) in [(0.06, -8.0), (0.13, 10.0)] as [(CGFloat, Double)] {
                let t = placed(ctx, dx * u, b - 0.075 * u, ang)
                let hh = 0.10 * u, ww = 0.058 * u
                let r = rrect(-ww / 2, 0, ww, hh, 0.012 * u)
                t.fill(r, with: .color(green))
                var ts = t; ts.clip(to: r)
                ts.fill(Path(CGRect(x: -ww, y: hh * 0.28, width: ww * 2, height: hh * 0.16)), with: .color(red))
                ts.fill(Path(CGRect(x: -ww, y: hh * 0.62, width: ww * 2, height: hh * 0.16)), with: .color(red))
                t.stroke(r, with: .color(ink), lineWidth: L)
                for i in 0..<3 {
                    var fr = Path(); fr.move(to: pt(-ww * 0.3 + CGFloat(i) * ww * 0.3, hh)); fr.addLine(to: pt(-ww * 0.3 + CGFloat(i) * ww * 0.3, hh + 0.02 * u))
                    t.stroke(fr, with: .color(red), style: StrokeStyle(lineWidth: L * 1.1, lineCap: .round))
                }
            }
            let knot = ellipse(0.085 * u, b - 0.085 * u, 0.04 * u, 0.034 * u)
            ctx.fill(knot, with: .color(green))
            var ks = ctx; ks.clip(to: knot)
            ks.fill(Path(CGRect(x: 0.075 * u, y: b - 0.13 * u, width: 0.02 * u, height: 0.1 * u)), with: .color(red))
            ctx.stroke(knot, with: .color(ink), lineWidth: L)
        default: break
        }
    }

    /// A heavy gold rope chain from his sides to a pendant under his grin.
    private static func chain(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat, _ body: Path) {
        var chain = Path()
        chain.move(to: pt(-0.30 * u, a.bottom - 0.13 * u))
        chain.addQuadCurve(to: pt(0.30 * u, a.bottom - 0.13 * u), control: pt(0, a.bottom - 0.01 * u))
        var wrap = ctx; wrap.clip(to: body)
        wrap.stroke(chain, with: .color(hx(0x6A4300)), style: StrokeStyle(lineWidth: 0.034 * u, lineCap: .round))
        wrap.stroke(chain, with: .color(hx(0xFFCF40)), style: StrokeStyle(lineWidth: 0.024 * u, lineCap: .round, dash: [0.022 * u, 0.01 * u]))
        wrap.stroke(chain, with: .color(hx(0xFFF3B0, 0.8)), style: StrokeStyle(lineWidth: 0.007 * u, lineCap: .round, dash: [0.012 * u, 0.02 * u]))
    }

    private static func medal(_ ctx: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ R: CGFloat, _ L: CGFloat) {
        var glow = ctx; glow.addFilter(.blur(radius: R * 0.4)); glow.fill(circle(x, y, R), with: .color(hx(0xFFD24A, 0.7)))
        ctx.fill(circle(x, y, R), with: lin([hx(0xFFF1A8), hx(0xFFCF40), hx(0xD99A10)], pt(x - R, y - R), pt(x + R, y + R)))
        ctx.stroke(circle(x, y, R), with: .color(hx(0x6A4300)), lineWidth: L)
        ctx.stroke(circle(x, y, R * 0.74), with: .color(hx(0xB57F0C)), lineWidth: L * 0.8)
        ctx.fill(star(x, y, R * 0.5, inner: 0.45), with: .color(hx(0xB57F0C)))
        ctx.fill(ellipse(x - R * 0.4, y - R * 0.45, R * 0.18, R * 0.1), with: .color(.white.opacity(0.75)))
    }

    // MARK: Costumes

    static func costume(_ item: FlameyItem, _ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat, palette: FlameyPalette?) {
        switch item {
        case .ghostSheet: ghostSheet(&ctx, a, u, palette: palette)
        case .pumpkinSuit: pumpkin(&ctx, a, u)
        case .astronautHelmet: astronaut(&ctx, a, u)
        default: break
        }
    }

    static func ghostSheet(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat, palette: FlameyPalette?) {
        let L = lw(u)
        var s = Path()
        let b = a.bottom + 0.01 * u
        s.move(to: pt(0, a.topY - 0.03 * u))
        s.addCurve(to: pt(-0.40 * u, b - 0.20 * u), control1: pt(-0.30 * u, a.topY + 0.10 * u), control2: pt(-0.40 * u, b - 0.55 * u))
        s.addLine(to: pt(-0.44 * u, b))
        for i in 0..<5 {
            let x0 = -0.44 * u + CGFloat(i) * 0.176 * u
            s.addQuadCurve(to: pt(x0 + 0.176 * u, b), control: pt(x0 + 0.088 * u, b - 0.07 * u))
        }
        s.addLine(to: pt(0.40 * u, b - 0.20 * u))
        s.addCurve(to: pt(0, a.topY - 0.03 * u), control1: pt(0.40 * u, b - 0.55 * u), control2: pt(0.30 * u, a.topY + 0.10 * u))
        s.closeSubpath()
        // His flame peeking out of the top hole, in his own colour.
        let tipColors = palette.map { [$0.outer.first ?? .white, $0.bodyTone] } ?? [hx(0xFFF3A0), hx(0xFF8A1F)]
        let tip = FlameBuddyOuterShape(wobble: 0).path(in: CGRect(x: -0.055 * u, y: a.topY - 0.14 * u, width: 0.11 * u, height: 0.16 * u))
        ctx.fill(tip, with: lin(tipColors, pt(0, a.topY - 0.14 * u), pt(0, a.topY + 0.02 * u)))
        var sh = ctx; sh.addFilter(.shadow(color: .black.opacity(0.35), radius: 0.03 * u, x: 0, y: 0.01 * u))
        sh.fill(s, with: lin([.white, hx(0xE9ECF4)], pt(0, a.topY), pt(0, b)))
        var folds = ctx; folds.clip(to: s)
        for x in [-0.22, 0.24] as [CGFloat] {
            var f = Path(); f.move(to: pt(x * u, a.faceY + 0.14 * u)); f.addQuadCurve(to: pt(x * u * 1.1, b), control: pt(x * u * 1.3, b - 0.08 * u))
            folds.stroke(f, with: .color(hx(0xC9CFDD)), lineWidth: L * 1.2)
        }
        ctx.stroke(s, with: .color(hx(0xB8C0D2)), lineWidth: L)
        for sx in [-1.0, 1.0] as [CGFloat] {
            ctx.fill(ellipse(sx * a.eyeX, a.faceY, 0.058 * u, 0.078 * u), with: .color(hx(0x1A0A10)))
            ctx.fill(circle(sx * a.eyeX + 0.018 * u, a.faceY - 0.025 * u, 0.017 * u), with: .color(.white.opacity(0.9)))
        }
        ctx.fill(ellipse(0, a.faceY + 0.13 * u, 0.045 * u, 0.035 * u), with: .color(hx(0x1A0A10)))
        for sx in [-1.0, 1.0] as [CGFloat] {
            ctx.fill(ellipse(sx * (a.eyeX + 0.06 * u), a.faceY + 0.09 * u, 0.045 * u, 0.022 * u), with: .color(hx(0xFF8FB0, 0.5)))
        }
    }

    /// 2,500 lifetime miles: a fishbowl round his whole upper body, collar
    /// on his chest. Drawn LAST of the front, over his eyes and face.
    static func astronaut(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let L = lw(u)
        let cy = a.faceY - 0.12 * u
        let R = 0.48 * u
        ctx.fill(circle(0, cy, R), with: .radialGradient(Gradient(colors: [hx(0x9FD8FF, 0.06), hx(0x9FD8FF, 0.24)]),
                                                         center: pt(0, cy), startRadius: R * 0.5, endRadius: R))
        ctx.stroke(circle(0, cy, R), with: .color(.white.opacity(0.9)), lineWidth: L * 1.8)
        ctx.stroke(circle(0, cy, R - L * 2.4), with: .color(hx(0x9FD8FF, 0.5)), lineWidth: L * 0.8)
        var hl = Path()
        hl.addArc(center: pt(0, cy), radius: R * 0.82, startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
        ctx.stroke(hl, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: L * 3, lineCap: .round))
        ctx.fill(circle(R * 0.5, cy - R * 0.55, L * 1.8), with: .color(.white.opacity(0.9)))
        let collar = rrect(-0.42 * u, a.bottom - 0.14 * u, 0.84 * u, 0.10 * u, 0.05 * u)
        ctx.fill(collar, with: lin([.white, hx(0xC9D2DC)], pt(0, a.bottom - 0.14 * u), pt(0, a.bottom - 0.04 * u)))
        ctx.stroke(collar, with: .color(ink), lineWidth: L)
        for i in 0..<5 { ctx.fill(circle(-0.28 * u + CGFloat(i) * 0.14 * u, a.bottom - 0.09 * u, 0.013 * u), with: .color(hx(0x8C98A6))) }
        var ant = Path(); ant.move(to: pt(0.30 * u, cy - R * 0.84)); ant.addLine(to: pt(0.40 * u, cy - R * 1.12))
        ctx.stroke(ant, with: .color(hx(0xC9D2DC)), lineWidth: L * 1.3)
        ctx.fill(circle(0.40 * u, cy - R * 1.12, 0.028 * u), with: .color(hx(0xE8384F)))
    }

    /// Halloween: sat in a carved pumpkin, with its stem on his tip.
    static func pumpkin(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let w = 0.84 * u, h = 0.25 * u
        let top = a.bottom - 0.135 * u
        let g = placed(ctx, 0, top + h / 2)
        var shell = Path()
        shell.move(to: pt(-w * 0.5, 0))
        shell.addCurve(to: pt(0, -h * 0.42), control1: pt(-w * 0.5, -h * 0.62), control2: pt(-w * 0.16, -h * 0.56))
        shell.addCurve(to: pt(w * 0.5, 0), control1: pt(w * 0.16, -h * 0.56), control2: pt(w * 0.5, -h * 0.62))
        shell.addCurve(to: pt(0, h * 0.5), control1: pt(w * 0.5, h * 0.62), control2: pt(w * 0.2, h * 0.6))
        shell.addCurve(to: pt(-w * 0.5, 0), control1: pt(-w * 0.2, h * 0.6), control2: pt(-w * 0.5, h * 0.62))
        shell.closeSubpath()
        g.fill(shell, with: .color(hx(0xF07B1A)))
        for f in [-0.28, 0, 0.28] as [CGFloat] {
            var rib = Path()
            rib.move(to: pt(f * w, -h * 0.45))
            rib.addQuadCurve(to: pt(f * w, h * 0.5), control: pt(f * w * 1.5, 0))
            g.stroke(rib, with: .color(hx(0xC75A0D)), style: StrokeStyle(lineWidth: 0.012 * u, lineCap: .round))
        }
        var rim = Path()
        rim.move(to: pt(-w * 0.36, -h * 0.34))
        for i in 0...8 {
            rim.addLine(to: pt(-w * 0.36 + CGFloat(i) * w * 0.09, -h * 0.34 + (i % 2 == 1 ? h * 0.1 : 0)))
        }
        g.stroke(rim, with: .color(hx(0x8A3A06)), style: StrokeStyle(lineWidth: 0.012 * u, lineJoin: .round))
        g.fill(ellipse(-w * 0.26, -h * 0.05, w * 0.07, h * 0.16), with: .color(hx(0xFFB15C, 0.45)))
        g.stroke(shell, with: .color(hx(0x8A3A06)), lineWidth: lw(u) * 0.8)

        let stem = placed(ctx, 0.01 * u, a.topY + 0.02 * u)
        var stalk = stem
        stalk.rotate(by: .degrees(10))
        stalk.fill(Path(roundedRect: CGRect(x: -0.025 * u, y: -0.09 * u, width: 0.05 * u, height: 0.10 * u),
                        cornerRadius: 0.015 * u), with: .color(hx(0x4F7D2A)))
        var vine = Path()
        vine.move(to: pt(0, -0.04 * u))
        vine.addQuadCurve(to: pt(0.15 * u, -0.04 * u), control: pt(0.10 * u, -0.11 * u))
        stem.stroke(vine, with: .color(hx(0x4F9D2A)), style: StrokeStyle(lineWidth: 0.018 * u, lineCap: .round))
    }

    // MARK: Holiday + mood hats

    /// Christmas: a floppy red cap pulled down over his tip, the fur band
    /// round his head and the bobble flopping off to one side.
    static func santaHat(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let L = lw(u), ink = self.ink
        let w = 0.40 * u, h = 0.36 * u
        let g = placed(ctx, 0.02 * u, a.topY + 0.20 * u, -5)
        var hat = Path()
        hat.move(to: pt(-w * 0.46, 0))
        hat.addQuadCurve(to: pt(w * 0.10, -h * 0.80), control: pt(-w * 0.34, -h * 0.78))
        hat.addQuadCurve(to: pt(w * 0.66, -h * 0.30), control: pt(w * 0.52, -h * 0.82))
        hat.addQuadCurve(to: pt(w * 0.24, -h * 0.40), control: pt(w * 0.44, -h * 0.46))
        hat.addQuadCurve(to: pt(w * 0.46, 0), control: pt(w * 0.40, -h * 0.20))
        hat.closeSubpath()
        g.fill(hat, with: lin([hx(0xFF4A5E), hx(0xB3152F)], pt(-w * 0.3, -h), pt(w * 0.3, 0)))
        sheen(g, hat, CGRect(x: -w * 0.5, y: -h * 0.8, width: w, height: h * 0.8), 0.24)
        g.stroke(hat, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
        fur(g, pt(w * 0.68, -h * 0.28), 0.05 * u, L)
        var bandPath = Path()
        bandPath.move(to: pt(-w * 0.52, -h * 0.02))
        bandPath.addQuadCurve(to: pt(w * 0.52, -h * 0.02), control: pt(0, h * 0.14))
        g.stroke(bandPath, with: .color(ink), style: StrokeStyle(lineWidth: 0.075 * u + L * 2, lineCap: .round))
        g.stroke(bandPath, with: .color(hx(0xFBFAF6)), style: StrokeStyle(lineWidth: 0.075 * u, lineCap: .round))
        var shade = g
        shade.clip(to: bandPath.strokedPath(StrokeStyle(lineWidth: 0.075 * u, lineCap: .round)))
        var low = Path()
        low.move(to: pt(-w * 0.6, h * 0.08))
        low.addQuadCurve(to: pt(w * 0.6, h * 0.08), control: pt(0, h * 0.22))
        shade.stroke(low, with: .color(hx(0xC9CFDD)), lineWidth: 0.035 * u)
    }

    /// A fluffy white pom.
    static func fur(_ g: GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ L: CGFloat) {
        g.fill(circle(c.x, c.y, r), with: .radialGradient(Gradient(colors: [.white, hx(0xDDE3EA)]),
                                                          center: pt(c.x - r * 0.35, c.y - r * 0.35), startRadius: 0, endRadius: r * 1.3))
        g.stroke(circle(c.x, c.y, r), with: .color(ink.opacity(0.7)), lineWidth: L * 0.8)
    }

    /// A little top hat, sat square on his head (brim where he's as wide as
    /// it), the crown covering his tip.
    static func topHat(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat, tilt: Double,
                       body: [Color], brim: Color, drawBand: (GraphicsContext, CGRect) -> Void) {
        let L = lw(u), ink = self.ink
        let g = placed(ctx, 0.02 * u, a.topY + 0.18 * u, tilt)
        let w = 0.26 * u, h = 0.28 * u
        let brimShape = ellipse(0, 0, w * 0.86, 0.042 * u)
        g.fill(brimShape, with: .color(brim))
        g.stroke(brimShape, with: .color(ink), lineWidth: L)
        var crown = Path()
        crown.move(to: pt(-w * 0.48, 0))
        crown.addLine(to: pt(-w * 0.44, -h))
        crown.addQuadCurve(to: pt(w * 0.44, -h), control: pt(0, -h - 0.03 * u))
        crown.addLine(to: pt(w * 0.48, 0))
        crown.addQuadCurve(to: pt(-w * 0.48, 0), control: pt(0, 0.035 * u))
        crown.closeSubpath()
        g.fill(crown, with: lin(body, pt(-w * 0.5, -h), pt(w * 0.5, 0)))
        drawBand(g, CGRect(x: -w * 0.48, y: -h * 0.36, width: w * 0.96, height: h * 0.26))
        sheen(g, crown, CGRect(x: -w / 2, y: -h, width: w, height: h), 0.24)
        g.stroke(crown, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
        var top = Path()
        top.addEllipse(in: CGRect(x: -w * 0.44, y: -h - 0.022 * u, width: w * 0.88, height: 0.04 * u))
        g.stroke(top, with: .color(ink.opacity(0.6)), lineWidth: L * 0.7)
        var front = Path()
        front.move(to: pt(-w * 0.86, 0))
        front.addQuadCurve(to: pt(w * 0.86, 0), control: pt(0, 0.085 * u))
        g.stroke(front, with: .color(ink), lineWidth: L)
    }

    static func leprechaunHat(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        topHat(&ctx, a, u, tilt: -7, body: [hx(0x3CC46A), hx(0x14803A)], brim: hx(0x17803C)) { g, r in
            g.fill(Path(r), with: .color(hx(0x1A1A1A)))
            let b = CGRect(x: r.midX - r.height * 0.55, y: r.minY - r.height * 0.05, width: r.height * 1.1, height: r.height * 1.1)
            g.fill(Path(roundedRect: b, cornerRadius: r.height * 0.12), with: .color(hx(0xFFCF40)))
            g.fill(Path(roundedRect: b.insetBy(dx: b.width * 0.26, dy: b.height * 0.26), cornerRadius: r.height * 0.05), with: .color(hx(0x1A1A1A)))
            // A shamrock tucked in the band.
            let c = CGPoint(x: r.maxX - r.width * 0.12, y: r.minY)
            for ang in [-90.0, 30.0, 150.0] {
                let rad = ang * .pi / 180
                g.fill(circle(c.x + CGFloat(cos(rad)) * r.height * 0.34, c.y + CGFloat(sin(rad)) * r.height * 0.34, r.height * 0.34), with: .color(hx(0x7EE06A)))
            }
        }
    }

    /// Independence Day: stars and stripes.
    static func starHat(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let red = hx(0xE0243A), blue = hx(0x1F3F99)
        topHat(&ctx, a, u, tilt: -7, body: [.white, hx(0xE3E7F0)], brim: blue) { g, r in
            let crownTop = r.minY - r.height * 2.4
            var inner = g
            inner.clip(to: Path(CGRect(x: r.minX, y: crownTop, width: r.width, height: r.minY - crownTop)))
            for i in 0..<3 {
                inner.fill(Path(CGRect(x: r.minX - 10, y: crownTop + CGFloat(i) * r.height * 0.9, width: r.width + 20, height: r.height * 0.42)), with: .color(red))
            }
            g.fill(Path(r), with: .color(blue))
            g.fill(star(r.midX, r.midY, r.height * 0.42), with: .color(.white))
            g.fill(star(r.minX + r.width * 0.2, r.midY, r.height * 0.24), with: .color(.white))
            g.fill(star(r.maxX - r.width * 0.2, r.midY, r.height * 0.24), with: .color(.white))
        }
    }

    /// Easter: a headband over his head with two long ears up off it.
    static func bunnyEars(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let L = lw(u)
        let bandY = a.topY + 0.20 * u
        for side in [-1.0, 1.0] as [CGFloat] {
            let g = placed(ctx, side * 0.085 * u, bandY - 0.04 * u, Double(side) * 14)
            let outer = ellipse(0, -0.16 * u, 0.058 * u, 0.17 * u)
            g.fill(outer, with: lin([.white, hx(0xF4E6EA)], pt(0, -0.33 * u), pt(0, 0)))
            g.stroke(outer, with: .color(ink.opacity(0.75)), lineWidth: L)
            g.fill(ellipse(0, -0.15 * u, 0.028 * u, 0.12 * u), with: lin([hx(0xFFC2D1), hx(0xFF8FAA)], pt(0, -0.27 * u), pt(0, 0)))
        }
        var bandPath = Path()
        bandPath.move(to: pt(-0.20 * u, bandY + 0.03 * u))
        bandPath.addQuadCurve(to: pt(0.21 * u, bandY + 0.03 * u), control: pt(0, bandY - 0.07 * u))
        ctx.stroke(bandPath, with: .color(ink), style: StrokeStyle(lineWidth: 0.034 * u + L * 2, lineCap: .round))
        ctx.stroke(bandPath, with: .color(hx(0xFF9FB5)), style: StrokeStyle(lineWidth: 0.034 * u, lineCap: .round))
    }

    static func countdownHat(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let gold = hx(0xFFCF40)
        cone(&ctx, a, u, tilt: 9, fill: lin([hx(0x3A3A48), hx(0x121218)], pt(0, a.topY - 0.2 * u), pt(0, a.topY + 0.16 * u)),
             stripes: gold, trim: gold, pom: hx(0xFFE27A), dark: true)
        // The clock about to strike midnight, on the front of the cone.
        let g = placed(ctx, 0.01 * u, a.topY + 0.16 * u, 9)
        let c = pt(0, -0.105 * u), r = 0.042 * u
        g.fill(circle(c.x, c.y, r), with: .color(hx(0xFFF6D8)))
        g.stroke(circle(c.x, c.y, r), with: .color(gold), lineWidth: lw(u) * 1.3)
        var hands = Path()
        hands.move(to: c); hands.addLine(to: pt(c.x, c.y - r * 0.72))
        hands.move(to: c); hands.addLine(to: pt(c.x + r * 0.1, c.y - r * 0.5))
        g.stroke(hands, with: .color(hx(0x1A1A22)), style: StrokeStyle(lineWidth: lw(u) * 1.1, lineCap: .round))
        for i in 0..<6 {
            let ray = placed(g, 0, -coneHeight * u, Double(i) * 60)
            ray.fill(Path(roundedRect: CGRect(x: -0.005 * u, y: -0.09 * u, width: 0.01 * u, height: 0.032 * u),
                          cornerRadius: 0.005 * u), with: .color(gold))
        }
    }

    static func partyHat(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        cone(&ctx, a, u, tilt: 12,
             fill: lin([Color(red: 1.0, green: 0.42, blue: 0.62), Color(red: 0.55, green: 0.42, blue: 1.0)],
                       pt(0, a.topY - 0.2 * u), pt(0, a.topY + 0.16 * u)),
             stripes: .white.opacity(0.55), trim: hx(0xFFE27A), pom: hx(0xFFE27A), dark: false)
    }

    /// Bedtime: a long soft cap pulled over his tip, drooping to one side,
    /// with a cuff round his head and a bobble at the end.
    static func nightcap(_ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat) {
        let L = lw(u), ink = self.ink
        let w = 0.40 * u, h = 0.34 * u
        let g = placed(ctx, 0.02 * u, a.topY + 0.20 * u, -4)
        var cap = Path()
        cap.move(to: pt(-w * 0.46, 0))
        cap.addQuadCurve(to: pt(w * 0.14, -h * 0.74), control: pt(-w * 0.36, -h * 0.80))
        cap.addQuadCurve(to: pt(w * 0.74, -h * 0.02), control: pt(w * 0.62, -h * 0.70))
        cap.addQuadCurve(to: pt(w * 0.28, -h * 0.34), control: pt(w * 0.50, -h * 0.30))
        cap.addQuadCurve(to: pt(w * 0.46, 0), control: pt(w * 0.40, -h * 0.14))
        cap.closeSubpath()
        g.fill(cap, with: lin([hx(0x7D8FF0), hx(0x4152B8)], pt(-w * 0.3, -h), pt(w * 0.4, 0)))
        var dots = g
        dots.clip(to: cap)
        for (x, y) in [(-0.22, -0.18), (0.02, -0.45), (0.30, -0.52), (0.10, -0.16), (-0.08, -0.62), (0.52, -0.22)] as [(CGFloat, CGFloat)] {
            dots.fill(star(x * w, y * h, 0.018 * u, inner: 0.5), with: .color(.white.opacity(0.85)))
        }
        sheen(g, cap, CGRect(x: -w * 0.5, y: -h * 0.8, width: w, height: h * 0.8), 0.22)
        g.stroke(cap, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
        g.fill(circle(w * 0.76, 0, 0.042 * u), with: .color(hx(0xE8ECFF)))
        g.stroke(circle(w * 0.76, 0, 0.042 * u), with: .color(ink.opacity(0.7)), lineWidth: L * 0.8)
        var cuff = Path()
        cuff.move(to: pt(-w * 0.52, -h * 0.02))
        cuff.addQuadCurve(to: pt(w * 0.52, -h * 0.02), control: pt(0, h * 0.15))
        g.stroke(cuff, with: .color(ink), style: StrokeStyle(lineWidth: 0.06 * u + L * 2, lineCap: .round))
        g.stroke(cuff, with: .color(hx(0xE8ECFF)), style: StrokeStyle(lineWidth: 0.06 * u, lineCap: .round))
    }

    /// Valentine's boppers — the BAND: an arc over his head, drawn still.
    /// Its springs and hearts are `drawHeartBopper`, which the layer sways.
    /// Both are drawn about the same origin: his head, `bopperSeat` under
    /// the tip.
    static func drawHeartBopperBand(in ctx: inout GraphicsContext, u: CGFloat) {
        let L = lw(u)
        var arc = Path()
        arc.move(to: pt(-0.20 * u, 0.05 * u))
        arc.addQuadCurve(to: pt(0.21 * u, 0.05 * u), control: pt(0, -0.07 * u))
        ctx.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 0.03 * u + L * 2, lineCap: .round))
        ctx.stroke(arc, with: .color(hx(0xFF5C8A)), style: StrokeStyle(lineWidth: 0.03 * u, lineCap: .round))
    }

    /// Where the boppers' band sits under his tip (body units).
    static let bopperSeat: CGFloat = 0.20

    /// Valentine's: two hearts on springy stalks off the band.
    static func drawHeartBopper(in ctx: inout GraphicsContext, u: CGFloat) {
        let L = lw(u)
        for side in [-1.0, 1.0] as [CGFloat] {
            let root = pt(side * 0.09 * u, -0.005 * u)
            let hc = pt(side * 0.15 * u, -0.25 * u)
            var spring = Path()
            spring.move(to: root)
            for i in 1...8 {
                let t = CGFloat(i) / 8
                let x = root.x + (hc.x - root.x) * t + (i % 2 == 0 ? -1 : 1) * 0.014 * u
                let y = root.y + (hc.y - root.y) * t
                spring.addLine(to: pt(x, y))
            }
            ctx.stroke(spring, with: .color(hx(0x2A1410, 0.85)), style: StrokeStyle(lineWidth: max(1, 0.012 * u), lineCap: .round, lineJoin: .round))
            let r = 0.055 * u
            var heart = Path()
            heart.move(to: pt(hc.x, hc.y + r * 0.9))
            heart.addCurve(to: pt(hc.x, hc.y - r * 0.45), control1: pt(hc.x - r * 1.6, hc.y - r * 0.2), control2: pt(hc.x - r * 0.9, hc.y - r * 1.4))
            heart.addCurve(to: pt(hc.x, hc.y + r * 0.9), control1: pt(hc.x + r * 0.9, hc.y - r * 1.4), control2: pt(hc.x + r * 1.6, hc.y - r * 0.2))
            heart.closeSubpath()
            ctx.fill(heart, with: lin([hx(0xFF7AA8), hx(0xE8195A)], pt(hc.x, hc.y - r), pt(hc.x, hc.y + r)))
            ctx.stroke(heart, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
            ctx.fill(ellipse(hc.x - r * 0.42, hc.y - r * 0.3, r * 0.22, r * 0.14), with: .color(.white.opacity(0.75)))
        }
    }

    // MARK: - Held (in front, at his side — the viewer's left)

    /// Props he holds UP (the rest are held out low, at chest height).
    static func heldUp(_ item: FlameyItem) -> Bool {
        [.pomPoms, .foamFinger, .checkeredFlag, .stopwatch].contains(item)
    }

    /// Where his hand is for a prop, in body units: +x AWAY from his body
    /// (the prop is mirrored), y from his base (negative is up). The prop is
    /// drawn round this point and `heldArmTargets` sends his real arm
    /// (`FlameBuddyArms`) to the same point — one set of numbers, so the
    /// hand always closes on the handle. Every point sits ~one arm's length
    /// (0.145u) from his shoulder (0.285, −0.27), so the arm never has to
    /// stretch to a prop floating off to the side.
    static func heldHand(_ item: FlameyItem) -> CGPoint {
        switch item {
        case .pomPoms: return pt(0.40, -0.38)
        case .foamFinger: return pt(0.36, -0.41)
        case .checkeredFlag: return pt(0.40, -0.36)
        case .stopwatch: return pt(0.41, -0.33)
        case .megaphone: return pt(0.42, -0.20)
        case .confettiCannon: return pt(0.41, -0.20)
        default: return pt(0.41, -0.22)
        }
    }

    /// Where the hand goes on a TIGHT surface: nearer his side, so the
    /// prop (scaled by `tightHeldScale`) stays inside his column. Pom-poms
    /// keep x = k·base so one symmetric scale carries BOTH hands.
    static func tightHeldHand(_ item: FlameyItem) -> CGPoint {
        if item == .pomPoms { return pt(heldHand(item).x * tightHeldScale(item), -0.40) }
        return heldUp(item) ? pt(0.34, -0.39) : pt(0.32, -0.15)
    }

    /// His arms' targets for what he's holding, in body units in the
    /// figure's real space (x negative = the viewer's left, his holding
    /// side), for `FlameBuddyArms(hold:)`. A pom-pom and the foam finger
    /// SWALLOW the hand (it's inside them), so no mitten is drawn there.
    static func heldArmTargets(_ item: FlameyItem?, reach: CGFloat) -> FlameArmHold? {
        guard let item else { return nil }
        var p = isTight(reach) ? tightHeldHand(item) : heldHand(item)
        // A prop that swallows the fist: the arm stops where it goes IN
        // (the pom-pom's edge, the finger's cuff), since the arms layer is
        // drawn over the prop and a wrist on top would read as beside it.
        let inset: CGFloat = item == .pomPoms ? 0.085 : (item == .foamFinger ? 0.03 : 0)
        if inset > 0 {
            let k: CGFloat = isTight(reach) ? tightHeldScale(item) : 1
            let dx = p.x - FlameBuddyArms.shoulderX, dy = p.y - FlameBuddyArms.shoulderY
            let d = max(0.001, sqrt(dx * dx + dy * dy))
            p = pt(p.x - dx / d * inset * k, p.y - dy / d * inset * k)
        }
        var hold = FlameArmHold(left: pt(-p.x, p.y))
        if item == .pomPoms {
            hold.right = p
            hold.leftHand = false
            hold.rightHand = false
        }
        if item == .foamFinger { hold.leftHand = false }
        return hold
    }

    /// The hand point in the held item's mirrored drawing space.
    private static func arm(_ a: Anchors, _ u: CGFloat, _ item: FlameyItem) -> CGPoint {
        let h = heldHand(item)
        return pt(h.x * u, a.bottom + h.y * u)
    }

    /// The angle (degrees, clockwise from straight up) his forearm points
    /// at a hand point — so a prop that continues his arm (the foam finger)
    /// or is gripped across it lines up with the limb actually drawn.
    private static func forearmAngle(_ item: FlameyItem) -> Double {
        let h = heldHand(item)
        let dx = Double(h.x - FlameBuddyArms.shoulderX), dy = Double(h.y - FlameBuddyArms.shoulderY)
        return atan2(dx, -dy) * 180 / .pi
    }

    /// The two halves of a held prop, so the live layer can move them apart:
    /// `.body` is the prop in his fist (it wobbles about the grip as ONE
    /// piece), `.accent` is the part with a life of its own — the flag's
    /// cloth, the stopwatch's sweep hand, the megaphone's sound rings, the
    /// cannon's burst. Static surfaces draw `.all`.
    enum HeldLayer { case all, body, accent }

    /// How a held prop moves when live (transform-only, `repeatForever`):
    /// the whole prop swings about his fist by `wobble` degrees every
    /// `period` seconds, and its accent does `accent`.
    struct HeldMotion {
        enum Accent { case none, flutter, sweep, pulse, burst }
        let wobble: Double
        let period: Double
        let accent: Accent
    }

    static func heldMotion(_ item: FlameyItem) -> HeldMotion {
        switch item {
        case .checkeredFlag: return HeldMotion(wobble: 9, period: 0.55, accent: .flutter)
        case .stopwatch: return HeldMotion(wobble: 3, period: 1.2, accent: .sweep)
        case .pomPoms: return HeldMotion(wobble: 0, period: 0.22, accent: .none)
        case .foamFinger: return HeldMotion(wobble: 7, period: 0.45, accent: .none)
        case .megaphone: return HeldMotion(wobble: 3, period: 0.9, accent: .pulse)
        case .confettiCannon: return HeldMotion(wobble: 4, period: 0.7, accent: .burst)
        default: return HeldMotion(wobble: 0, period: 1, accent: .none)
        }
    }

    /// Where a held prop's ACCENT pivots, in the prop's own space (body
    /// units from his base, +x away from him — like `heldHand`).
    static func heldAccentPivot(_ item: FlameyItem) -> CGPoint? {
        let h = heldHand(item)
        switch item {
        case .checkeredFlag: return pt(h.x + 0.075, h.y - 0.52)
        case .stopwatch: return pt(h.x + 0.01, h.y - 0.15)
        case .megaphone: return pt(h.x + 0.33, h.y - 0.14)
        case .confettiCannon: return pt(h.x + 0.17, h.y - 0.20)
        default: return nil
        }
    }

    /// Where the WHOLE prop pivots (his fist; the pom-poms shake about the
    /// point between his two hands).
    static func heldGrip(_ item: FlameyItem) -> CGPoint {
        let h = heldHand(item)
        return item == .pomPoms ? pt(0, h.y - 0.03) : h
    }

    /// A point in held-prop space → the outfit canvas's space (origin at the
    /// centre of his `size` square), through the tight surface's scale-in.
    static func heldPoint(_ item: FlameyItem, _ p: CGPoint, a: Anchors, u: CGFloat, reach: CGFloat) -> CGPoint {
        let q = pt(-p.x * u, a.bottom + p.y * u)
        guard isTight(reach) else { return q }
        let k = tightHeldScale(item), base = heldHand(item), th = tightHeldHand(item)
        let px = -(th.x - k * base.x) / (1 - k) * u
        let py = a.bottom + (th.y - k * base.y) / (1 - k) * u
        return pt(px + k * (q.x - px), py + k * (q.y - py))
    }

    /// How a Closet tile frames a held prop (figure size as a fraction of
    /// the tile, prop centre x/y as fractions of that size from his square's
    /// centre) — per prop, since a flag towers and a stopwatch is compact.
    static func heldTileFraming(_ item: FlameyItem) -> (CGFloat, CGFloat, CGFloat) {
        switch item {
        case .checkeredFlag: return (0.95, -0.62, -0.27)
        case .stopwatch: return (1.45, -0.42, -0.17)
        case .pomPoms: return (0.85, 0, -0.08)
        case .foamFinger: return (1.1, -0.45, -0.27)
        case .megaphone: return (0.95, -0.70, -0.04)
        case .confettiCannon: return (0.95, -0.72, -0.20)
        default: return (0.9, -0.40, 0.06)
        }
    }

    /// One bushy pom-pom, mid-shake: a spiky silhouette of long metallic
    /// streamers (red, white, a little pink) fanning out from the fist
    /// buried in it, lit from the top-left, with two shake marks.
    private static func pomPom(_ ctx: GraphicsContext, _ c: CGPoint, _ R: CGFloat, _ u: CGFloat) {
        let ink = self.ink
        let L = max(1, 0.011 * u)
        var shadow = ctx; shadow.addFilter(.blur(radius: R * 0.2))
        shadow.fill(circle(c.x, c.y + R * 0.12, R * 0.95), with: .color(.black.opacity(0.28)))
        let outline = star(c.x, c.y, R, inner: 0.74, points: 22)
        ctx.fill(outline, with: .color(hx(0xB80F2A)))
        var s = ctx; s.clip(to: outline)
        for i in 0..<66 {
            let ang = Double(i) / 66 * 2 * .pi + 0.05
            let len = R * (0.72 + 0.34 * CGFloat((i * 7) % 5) / 4)
            var st = Path(); st.move(to: pt(c.x + CGFloat(cos(ang)) * R * 0.08, c.y + CGFloat(sin(ang)) * R * 0.08))
            st.addLine(to: pt(c.x + CGFloat(cos(ang)) * len, c.y + CGFloat(sin(ang)) * len))
            let col: Color = i % 3 == 0 ? .white : (i % 3 == 1 ? hx(0xFF2E4D) : (i % 6 == 2 ? hx(0xFF9AAC) : hx(0xE8203A)))
            s.stroke(st, with: .color(col), style: StrokeStyle(lineWidth: R * 0.10, lineCap: .round))
        }
        // Metallic glints: bright strands catching the light top-left.
        for i in 0..<6 {
            let ang = -2.4 + Double(i) * 0.18
            var st = Path(); st.move(to: pt(c.x + CGFloat(cos(ang)) * R * 0.30, c.y + CGFloat(sin(ang)) * R * 0.30))
            st.addLine(to: pt(c.x + CGFloat(cos(ang)) * R * 0.86, c.y + CGFloat(sin(ang)) * R * 0.86))
            s.stroke(st, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: R * 0.05, lineCap: .round))
        }
        s.fill(circle(c.x + R * 0.25, c.y + R * 0.3, R * 0.75), with: .radialGradient(Gradient(colors: [.black.opacity(0.0), .black.opacity(0.22)]),
                                                                                    center: pt(c.x - R * 0.3, c.y - R * 0.3), startRadius: 0, endRadius: R * 1.4))
        ctx.stroke(outline, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
        // Shake marks, off the outer top.
        for (i, ang) in [-2.35, -1.95].enumerated() {
            let r0 = R * (1.18 + CGFloat(i) * 0.02)
            var arc = Path()
            arc.addArc(center: c, radius: r0, startAngle: .radians(ang - 0.16), endAngle: .radians(ang + 0.16), clockwise: false)
            ctx.stroke(arc, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: L * 1.5, lineCap: .round))
        }
    }

    /// Draws the PROP only — his arm and the hand closing round it are
    /// `FlameBuddyArms`, drawn over the outfit, so a handle runs UNDER the
    /// mitten and shows either side of it: gripped, not floating beside it.
    /// Sized to read: every prop is ~a third to a half of his height.
    static func held(_ item: FlameyItem, _ ctx: inout GraphicsContext, _ a: Anchors, _ u: CGFloat, layer: HeldLayer = .all) {
        let L = max(1, 0.012 * u)
        let ink = self.ink
        let body = layer != .accent, accent = layer != .body
        // Mirror so +x runs toward the viewer's LEFT (away from his body).
        var m = ctx
        m.scaleBy(x: -1, y: 1)
        let hand = arm(a, u, item)
        switch item {
        case .pomPoms:
            // One in EACH hand, the fists buried in them.
            guard body else { return }
            for sx in [-1.0, 1.0] as [CGFloat] {
                var side = ctx
                side.scaleBy(x: -sx, y: 1)
                pomPom(side, pt(hand.x + 0.012 * u, hand.y - 0.03 * u), 0.16 * u, u)
            }
        case .foamFinger:
            // WORN: his arm runs into the cuff and the giant glove carries
            // on along his forearm, "#1" to the sky. No mitten — his hand is
            // inside it.
            guard body else { return }
            let ang = forearmAngle(item) * 0.55
            let g = placed(m, hand.x, hand.y, ang)
            let yellow = [hx(0xFFEB7A), hx(0xFFD21F), hx(0xE09A00)]
            var sh = g; sh.addFilter(.blur(radius: 0.015 * u))
            sh.fill(rrect(-0.10 * u, -0.46 * u, 0.22 * u, 0.46 * u, 0.06 * u), with: .color(.black.opacity(0.25)))
            let finger = rrect(-0.052 * u, -0.52 * u, 0.104 * u, 0.34 * u, 0.052 * u)
            g.fill(finger, with: lin(yellow, pt(-0.05 * u, 0), pt(0.05 * u, 0)))
            g.stroke(finger, with: .color(ink), lineWidth: L)
            g.fill(rrect(-0.030 * u, -0.49 * u, 0.020 * u, 0.16 * u, 0.01 * u), with: .color(.white.opacity(0.6)))
            // Nail line near the tip.
            var nail = Path(); nail.move(to: pt(-0.03 * u, -0.455 * u)); nail.addQuadCurve(to: pt(0.03 * u, -0.455 * u), control: pt(0, -0.43 * u))
            g.stroke(nail, with: .color(hx(0xC98400)), style: StrokeStyle(lineWidth: L * 0.8, lineCap: .round))
            let palm = rrect(-0.108 * u, -0.26 * u, 0.216 * u, 0.215 * u, 0.065 * u)
            g.fill(palm, with: lin(yellow, pt(-0.1 * u, 0), pt(0.1 * u, 0)))
            g.stroke(palm, with: .color(ink), lineWidth: L)
            for i in 0..<3 {
                let fx = -0.035 * u + CGFloat(i) * 0.036 * u
                var k = Path(); k.move(to: pt(fx + 0.018 * u, -0.25 * u)); k.addLine(to: pt(fx + 0.018 * u, -0.20 * u))
                g.stroke(k, with: .color(hx(0xC98400)), style: StrokeStyle(lineWidth: L, lineCap: .round))
            }
            let thumb = rrect(-0.158 * u, -0.215 * u, 0.072 * u, 0.13 * u, 0.036 * u)
            g.fill(thumb, with: lin(yellow, pt(-0.16 * u, 0), pt(-0.09 * u, 0))); g.stroke(thumb, with: .color(ink), lineWidth: L)
            let cuff = rrect(-0.082 * u, -0.055 * u, 0.164 * u, 0.09 * u, 0.028 * u)
            g.fill(cuff, with: lin([hx(0x5A8CFF), hx(0x2F6BFF), hx(0x1E48C8)], pt(0, -0.055 * u), pt(0, 0.035 * u)))
            g.fill(Path(CGRect(x: -0.082 * u, y: -0.022 * u, width: 0.164 * u, height: 0.018 * u)), with: .color(.white.opacity(0.95)))
            g.stroke(cuff, with: .color(ink), lineWidth: L)
            // "#1" on the palm, drawn UNmirrored, outlined so it reads small.
            let r = ang * .pi / 180
            let px = hand.x + CGFloat(sin(r)) * 0.15 * u, py = hand.y - CGFloat(cos(r)) * 0.15 * u
            let t = placed(ctx, -px, py, -ang)
            let font = Font.system(size: 0.105 * u, weight: .black, design: .rounded)
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] as [(CGFloat, CGFloat)] {
                t.draw(Text("#1").font(font).foregroundColor(.white), at: pt(dx * 0.009 * u, dy * 0.009 * u))
            }
            t.draw(Text("#1").font(font).foregroundColor(hx(0x1E48C8)), at: .zero)
        case .megaphone:
            // A big cheer megaphone on a pistol grip — his fist round the
            // grip — pointing out and up, sound rings pouring out the bell.
            let g = placed(m, hand.x - 0.04 * u, hand.y - 0.06 * u, -12)
            if body {
                let grip = rrect(0.018 * u, -0.005 * u, 0.05 * u, 0.13 * u, 0.02 * u)
                g.fill(grip, with: lin([hx(0x3A3A44), hx(0x1C1C22)], pt(0.02 * u, 0), pt(0.07 * u, 0)))
                g.stroke(grip, with: .color(ink), lineWidth: L)
                var cone = Path()
                cone.move(to: pt(0, -0.042 * u)); cone.addLine(to: pt(0.38 * u, -0.145 * u))
                cone.addLine(to: pt(0.38 * u, 0.145 * u)); cone.addLine(to: pt(0, 0.042 * u)); cone.closeSubpath()
                g.fill(cone, with: lin([.white, hx(0xE9ECF2), hx(0xB9C0CC)], pt(0, -0.14 * u), pt(0, 0.14 * u)))
                var st = g; st.clip(to: cone)
                for x in [0.10, 0.22, 0.33] as [CGFloat] {
                    st.fill(Path(CGRect(x: x * u, y: -0.2 * u, width: 0.055 * u, height: 0.4 * u)), with: .color(hx(0xE8203A)))
                }
                st.fill(Path(CGRect(x: 0, y: -0.2 * u, width: 0.4 * u, height: 0.07 * u)), with: .color(.white.opacity(0.35)))
                g.stroke(cone, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
                let bell = ellipse(0.38 * u, 0, 0.034 * u, 0.145 * u)
                g.fill(bell, with: lin([hx(0xFF4F5E), hx(0xA8102A)], pt(0, -0.14 * u), pt(0, 0.14 * u)))
                g.stroke(bell, with: .color(ink), lineWidth: L)
                g.fill(ellipse(0.388 * u, 0, 0.016 * u, 0.11 * u), with: .color(hx(0x5A0612)))
                let mouth = rrect(-0.045 * u, -0.036 * u, 0.055 * u, 0.072 * u, 0.016 * u)
                g.fill(mouth, with: .color(hx(0x2B2B33))); g.stroke(mouth, with: .color(ink), lineWidth: L * 0.8)
            }
            if accent {
                for (i, r) in [0.19, 0.265, 0.34].enumerated() {
                    var w = Path()
                    w.addArc(center: pt(0.38 * u, 0), radius: CGFloat(r) * u, startAngle: .degrees(-34), endAngle: .degrees(34), clockwise: false)
                    g.stroke(w, with: .color(ink.opacity(0.35)), style: StrokeStyle(lineWidth: L * 3.4, lineCap: .round))
                    g.stroke(w, with: .color(i == 1 ? hx(0xFFE047) : .white), style: StrokeStyle(lineWidth: L * 2.2, lineCap: .round))
                }
            }
        case .confettiCannon:
            // A party cannon gripped at its base, aimed up and out, MID-BLAST.
            let g = placed(m, hand.x, hand.y, -50)
            if body {
                var tube = Path()
                tube.move(to: pt(-0.06 * u, -0.05 * u)); tube.addLine(to: pt(0.26 * u, -0.078 * u))
                tube.addLine(to: pt(0.26 * u, 0.078 * u)); tube.addLine(to: pt(-0.06 * u, 0.05 * u)); tube.closeSubpath()
                g.fill(tube, with: lin([hx(0xC49BFF), hx(0x8A4FF0), hx(0x4A1FA0)], pt(0, -0.08 * u), pt(0, 0.08 * u)))
                var st = g; st.clip(to: tube)
                for x in [-0.03, 0.05, 0.13, 0.21] as [CGFloat] {
                    var s = Path(); s.move(to: pt(x * u, -0.09 * u)); s.addLine(to: pt(x * u + 0.06 * u, 0.09 * u))
                    st.stroke(s, with: .color(hx(0xFFCF40)), lineWidth: 0.024 * u)
                }
                st.fill(Path(CGRect(x: -0.1 * u, y: -0.09 * u, width: 0.4 * u, height: 0.04 * u)), with: .color(.white.opacity(0.3)))
                g.stroke(tube, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
                let cap = rrect(-0.085 * u, -0.056 * u, 0.04 * u, 0.112 * u, 0.012 * u)
                g.fill(cap, with: .color(hx(0x2B2B33))); g.stroke(cap, with: .color(ink), lineWidth: L)
                let rim = ellipse(0.26 * u, 0, 0.022 * u, 0.08 * u)
                g.fill(rim, with: lin([hx(0xFFF3B0), hx(0xE0A512)], pt(0, -0.08 * u), pt(0, 0.08 * u))); g.stroke(rim, with: .color(ink), lineWidth: L)
            }
            if accent {
                // The burst: a flash, then confetti and streamers fanning out.
                var flash = g; flash.addFilter(.blur(radius: 0.03 * u))
                flash.fill(circle(0.32 * u, 0, 0.09 * u), with: .color(hx(0xFFF3B0, 0.9)))
                g.fill(star(0.31 * u, 0, 0.10 * u, inner: 0.35, points: 8), with: .color(hx(0xFFF6D0)))
                let colors: [Color] = [hx(0xFF4F7B), hx(0xFFCF40), hx(0x3EE0A0), hx(0x4F8BFF), hx(0xFF9A1F), .white, hx(0xB07BFF)]
                for i in 0..<34 {
                    let ang = (-36.0 + Double((i * 37) % 72)) * .pi / 180
                    let d = (0.12 + 0.34 * CGFloat((i * 53) % 17) / 17) * u
                    let cx = 0.28 * u + CGFloat(cos(ang)) * d, cy = CGFloat(sin(ang)) * d
                    let cc = placed(g, cx, cy, Double(i * 47))
                    let col = colors[i % colors.count]
                    switch i % 4 {
                    case 0: cc.fill(circle(0, 0, 0.019 * u), with: .color(col))
                    case 1: cc.fill(star(0, 0, 0.026 * u, inner: 0.45), with: .color(col))
                    default: cc.fill(Path(CGRect(x: -0.024 * u, y: -0.011 * u, width: 0.048 * u, height: 0.022 * u)), with: .color(col))
                    }
                }
                for (i, dy) in [-0.06, 0.0, 0.06].enumerated() {
                    var sp = Path(); sp.move(to: pt(0.28 * u, CGFloat(dy) * 0.3 * u))
                    sp.addCurve(to: pt(0.60 * u, CGFloat(dy) * u * 2.6), control1: pt(0.38 * u, CGFloat(dy) * u * 3.2 + 0.05 * u),
                                control2: pt(0.50 * u, -CGFloat(dy) * u - 0.05 * u))
                    g.stroke(sp, with: .color([hx(0x4F8BFF), hx(0xFFCF40), hx(0xFF4F7B)][i]), style: StrokeStyle(lineWidth: 0.016 * u, lineCap: .round))
                }
            }
        case .checkeredFlag:
            // A RACE flag: the pole runs through his fist — out below it and
            // up past his head — and a big checkered flag billows away from
            // him mid-wave, whoosh lines off its trailing edge.
            let base = pt(hand.x - 0.02 * u, hand.y + 0.11 * u), tip = pt(hand.x + 0.075 * u, hand.y - 0.52 * u)
            if body {
                var pole = Path(); pole.move(to: base); pole.addLine(to: tip)
                m.stroke(pole, with: .color(ink), style: StrokeStyle(lineWidth: 0.034 * u + L, lineCap: .round))
                m.stroke(pole, with: lin([hx(0xEEF2F6), hx(0x8A94A2)], pt(tip.x - 0.017 * u, 0), pt(tip.x + 0.017 * u, 0)),
                         style: StrokeStyle(lineWidth: 0.034 * u, lineCap: .round))
                m.fill(circle(tip.x, tip.y - 0.02 * u, 0.034 * u), with: lin([hx(0xFFF3B0), hx(0xE0A512)], pt(0, tip.y - 0.05 * u), pt(0, tip.y)))
                m.stroke(circle(tip.x, tip.y - 0.02 * u, 0.034 * u), with: .color(ink), lineWidth: L * 0.8)
            }
            if accent {
                let fw = 0.42 * u, fh = 0.28 * u
                let x0 = tip.x + 0.008 * u, y0 = tip.y + 0.01 * u
                func q(_ t: CGFloat, _ s: CGFloat) -> CGPoint {
                    let wave = 0.05 * u * sin(t * .pi * 2.2 - 0.3) * t
                    return pt(x0 + fw * t * (1 - 0.06 * s), y0 + fh * s + wave + 0.05 * u * t * t)
                }
                let cols = 7, rows = 5
                var flag = Path()
                flag.move(to: q(0, 0))
                for i in 1...28 { flag.addLine(to: q(CGFloat(i) / 28, 0)) }
                for i in stride(from: 28, through: 0, by: -1) { flag.addLine(to: q(CGFloat(i) / 28, 1)) }
                flag.closeSubpath()
                var shadow = m; shadow.addFilter(.shadow(color: .black.opacity(0.35), radius: 0.014 * u, y: 0.008 * u))
                shadow.fill(flag, with: .color(.white))
                for r in 0..<rows {
                    for c in 0..<cols where (r + c) % 2 == 0 {
                        let t0 = CGFloat(c) / CGFloat(cols), t1 = CGFloat(c + 1) / CGFloat(cols)
                        let s0 = CGFloat(r) / CGFloat(rows), s1 = CGFloat(r + 1) / CGFloat(rows)
                        var cell = Path()
                        cell.move(to: q(t0, s0))
                        for k in 1...4 { cell.addLine(to: q(t0 + (t1 - t0) * CGFloat(k) / 4, s0)) }
                        for k in stride(from: 4, through: 0, by: -1) { cell.addLine(to: q(t0 + (t1 - t0) * CGFloat(k) / 4, s1)) }
                        cell.closeSubpath()
                        m.fill(cell, with: .color(hx(0x15151C)))
                    }
                }
                // Ripple shading: the troughs of the wave fall into shadow.
                var sh = m; sh.clip(to: flag)
                for i in 0..<12 {
                    let t0 = CGFloat(i) / 12, t1 = CGFloat(i + 1) / 12
                    let slope = cos((t0 + t1) / 2 * .pi * 2.2 - 0.3)
                    guard slope < 0 else { continue }
                    var band = Path()
                    band.move(to: q(t0, -0.1)); band.addLine(to: q(t1, -0.1)); band.addLine(to: q(t1, 1.1)); band.addLine(to: q(t0, 1.1)); band.closeSubpath()
                    sh.fill(band, with: .color(.black.opacity(Double(-slope) * 0.22)))
                }
                m.stroke(flag, with: .color(ink), style: StrokeStyle(lineWidth: L, lineJoin: .round))
                for (i, s) in [0.25, 0.7].enumerated() {
                    let e = q(1, CGFloat(s))
                    var w = Path(); w.move(to: pt(e.x + 0.03 * u, e.y)); w.addQuadCurve(to: pt(e.x + 0.12 * u, e.y - 0.01 * u), control: pt(e.x + 0.075 * u, e.y + 0.02 * u))
                    m.stroke(w, with: .color(.white.opacity(i == 0 ? 0.8 : 0.55)), style: StrokeStyle(lineWidth: L * 1.5, lineCap: .round))
                }
            }
        case .stopwatch:
            // A BIG chrome stopwatch held up to show you the time: his fist
            // round the bottom of the case, the face turned out, the sweep
            // hand racing.
            let c = pt(hand.x + 0.01 * u, hand.y - 0.15 * u)
            let R = 0.15 * u
            let needle = Angle.degrees(28)
            if body {
                var sh = m; sh.addFilter(.blur(radius: R * 0.12))
                sh.fill(circle(c.x, c.y + R * 0.1, R), with: .color(.black.opacity(0.3)))
                // Loop, stem, crown button, side pusher.
                m.stroke(circle(c.x, c.y - R - 0.085 * u, 0.026 * u), with: .color(ink), lineWidth: L * 2.6)
                m.stroke(circle(c.x, c.y - R - 0.085 * u, 0.026 * u), with: .color(hx(0xD8DEE6)), lineWidth: L * 1.4)
                let stem = rrect(c.x - 0.016 * u, c.y - R - 0.06 * u, 0.032 * u, 0.06 * u, 0.008 * u)
                m.fill(stem, with: lin([hx(0xEEF2F6), hx(0x8A94A2)], pt(c.x - 0.016 * u, 0), pt(c.x + 0.016 * u, 0)))
                m.stroke(stem, with: .color(ink), lineWidth: L * 0.8)
                let crown = rrect(c.x - 0.03 * u, c.y - R - 0.045 * u, 0.06 * u, 0.03 * u, 0.01 * u)
                m.fill(crown, with: .color(hx(0xE8203A))); m.stroke(crown, with: .color(ink), lineWidth: L * 0.8)
                let side = placed(m, c.x, c.y, 45)
                let btn = rrect(-0.016 * u, -R - 0.036 * u, 0.032 * u, 0.04 * u, 0.008 * u)
                side.fill(btn, with: .color(hx(0xC9D2DC))); side.stroke(btn, with: .color(ink), lineWidth: L * 0.8)
                // Chrome case + bezel.
                m.fill(circle(c.x, c.y, R), with: .linearGradient(Gradient(colors: [.white, hx(0xC9D2DC), hx(0x6B7380), hx(0xB9C2CC)]),
                                                                  startPoint: pt(c.x - R, c.y - R), endPoint: pt(c.x + R, c.y + R)))
                m.stroke(circle(c.x, c.y, R), with: .color(ink), lineWidth: L * 1.2)
                m.fill(circle(c.x, c.y, R * 0.86), with: .color(hx(0x2B2F38)))
                m.fill(circle(c.x, c.y, R * 0.78), with: .radialGradient(Gradient(colors: [.white, hx(0xF4F1E8)]), center: pt(c.x - R * 0.2, c.y - R * 0.2), startRadius: 0, endRadius: R * 0.8))
                for i in 0..<60 {
                    let ang = Double(i) / 60 * 2 * .pi
                    let bold = i % 5 == 0
                    let r0 = R * (bold ? 0.60 : 0.68), r1 = R * 0.74
                    var tick = Path()
                    tick.move(to: pt(c.x + CGFloat(cos(ang)) * r0, c.y + CGFloat(sin(ang)) * r0))
                    tick.addLine(to: pt(c.x + CGFloat(cos(ang)) * r1, c.y + CGFloat(sin(ang)) * r1))
                    m.stroke(tick, with: .color(hx(0x2B2B33)), lineWidth: L * (bold ? 1.2 : 0.45))
                }
                // A little sub-dial, and the lap sector the hand has swept.
                m.stroke(circle(c.x, c.y + R * 0.34, R * 0.16), with: .color(hx(0x2B2B33, 0.6)), lineWidth: L * 0.6)
                var sub = Path(); sub.move(to: pt(c.x, c.y + R * 0.34)); sub.addLine(to: pt(c.x + R * 0.08, c.y + R * 0.24))
                m.stroke(sub, with: .color(hx(0x2B2B33)), style: StrokeStyle(lineWidth: L * 0.8, lineCap: .round))
                var sweep = Path()
                sweep.move(to: c)
                sweep.addArc(center: c, radius: R * 0.56, startAngle: .degrees(-90), endAngle: needle - .degrees(90), clockwise: false)
                sweep.closeSubpath()
                m.fill(sweep, with: .color(hx(0xE8203A, 0.22)))
                // Glass glare.
                var glare = Path()
                glare.addArc(center: c, radius: R * 0.66, startAngle: .degrees(200), endAngle: .degrees(245), clockwise: false)
                m.stroke(glare, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: L * 1.6, lineCap: .round))
            }
            if accent {
                let dir = needle - .degrees(90)
                let tipP = pt(c.x + CGFloat(cos(dir.radians)) * R * 0.70, c.y + CGFloat(sin(dir.radians)) * R * 0.70)
                let tail = pt(c.x - CGFloat(cos(dir.radians)) * R * 0.18, c.y - CGFloat(sin(dir.radians)) * R * 0.18)
                var hand2 = Path(); hand2.move(to: tail); hand2.addLine(to: tipP)
                m.stroke(hand2, with: .color(hx(0xE8203A)), style: StrokeStyle(lineWidth: L * 1.7, lineCap: .round))
                m.fill(circle(c.x, c.y, R * 0.085), with: .color(hx(0x2B2B33)))
                m.fill(circle(c.x, c.y, R * 0.04), with: .color(hx(0xE8203A)))
            }
        default: break
        }
    }

    // MARK: - Back (behind him)

    /// Draws a back item. `reach` is how far (in `u`) the surface lets him
    /// spread sideways; capes and wings squeeze to fit. `glow` is false when
    /// `FlameyGlow` gave the halo to something else.
    static func drawBack(_ item: FlameyItem, in base: inout GraphicsContext, a: Anchors, u: CGFloat,
                         reach: CGFloat, glow: Bool) {
        let L = lw(u)
        let ink = self.ink
        var ctx = base
        let tight = isTight(reach)
        let squeeze = min(1, (reach + 0.06) / 0.92)
        if tight {
            // The hero's column: a cape tucks in behind him (squeezed until
            // it only peeks past his side); wings are RAISED instead, below.
            if isCape(item) {
                ctx.scaleBy(x: capeTightScale, y: 1)
            } else if item != .goldenWings {
                ctx.scaleBy(x: capeTuck, y: 1)
            }
        } else if squeeze < 1 {
            ctx.scaleBy(x: squeeze, y: 1)
        }
        func cape(_ main: Color, _ dark: Color, lining: Color, trim: Color?, ermine: Bool) {
            // A HERO'S cape, as one clean silhouette BEHIND him: the cloth
            // falling from his shoulders (his arms hang IN FRONT of it) and
            // flaring out below them to a hem just off the floor, behind his
            // legs. The wind lifts the viewer-RIGHT corner and turns its
            // lining out — the side AWAY from his trail, which streams low
            // from under the left edge (`trailPoint(low:)`), and short of
            // where a companion stands (`companionX`). Nothing is drawn on
            // his front: clasps on a neckless flame read as a second pair
            // of eyes.
            let b = a.bottom
            func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { pt(x * u, b + y * u) }
            var c = Path()
            // From his shoulders (hidden behind him) down his left side.
            c.move(to: q(-0.24, -0.44))
            c.addCurve(to: q(-0.50, 0.10), control1: q(-0.36, -0.26), control2: q(-0.50, -0.04))
            // The hem: soft scallops across behind his legs.
            c.addQuadCurve(to: q(-0.26, 0.10), control: q(-0.38, 0.15))
            c.addQuadCurve(to: q(0.0, 0.11), control: q(-0.13, 0.155))
            c.addQuadCurve(to: q(0.24, 0.08), control: q(0.12, 0.15))
            // The right corner, lifted and blown out.
            c.addQuadCurve(to: q(0.53, -0.02), control: q(0.40, 0.11))
            c.addCurve(to: q(0.24, -0.44), control1: q(0.47, -0.16), control2: q(0.36, -0.30))
            c.addQuadCurve(to: q(-0.24, -0.44), control: q(0, -0.36))
            c.closeSubpath()
            // A soft drop shadow so the cloth sits behind him, not on the card.
            var sh = ctx; sh.addFilter(.blur(radius: 0.03 * u))
            sh.fill(c, with: .color(.black.opacity(0.28)))
            ctx.fill(c, with: lin([main, dark], q(0, -0.55), q(0, 0.12)))
            var inner = ctx; inner.clip(to: c)
            // Folds fanning down from under his arms.
            for (x0, x1, y0) in [(-0.33, -0.44, -0.20), (-0.30, -0.24, -0.02), (0.30, 0.20, -0.02), (0.34, 0.44, -0.16)] as [(CGFloat, CGFloat, CGFloat)] {
                var f = Path(); f.move(to: q(x0, y0))
                f.addQuadCurve(to: q(x1, 0.12), control: q((x0 + x1) / 2 + (x1 < 0 ? -0.03 : 0.03), (y0 + 0.12) / 2))
                inner.stroke(f, with: .color(dark.opacity(0.7)), style: StrokeStyle(lineWidth: L * 1.8, lineCap: .round))
            }
            // The lining, turned out at the lifted corner.
            var turn = Path()
            turn.move(to: q(0.53, -0.02))
            turn.addQuadCurve(to: q(0.26, 0.085), control: q(0.40, 0.11))
            turn.addQuadCurve(to: q(0.47, -0.10), control: q(0.36, 0.02))
            turn.closeSubpath()
            inner.fill(turn, with: lin([lining, lining.opacity(0.8)], q(0.3, 0.1), q(0.5, -0.1)))
            // Sheen along the outer edges.
            for sx in [-1.0, 1.0] as [CGFloat] {
                var e = Path(); e.move(to: q(sx * 0.33, -0.38)); e.addQuadCurve(to: q(sx * 0.47, 0.02), control: q(sx * 0.44, -0.18))
                inner.stroke(e, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 0.02 * u, lineCap: .round))
            }
            if let trim {
                var hem = Path()
                hem.move(to: q(-0.50, 0.10))
                hem.addQuadCurve(to: q(-0.26, 0.10), control: q(-0.38, 0.15))
                hem.addQuadCurve(to: q(0.0, 0.11), control: q(-0.13, 0.155))
                hem.addQuadCurve(to: q(0.24, 0.08), control: q(0.12, 0.15))
                hem.addQuadCurve(to: q(0.53, -0.02), control: q(0.40, 0.11))
                inner.stroke(hem, with: .color(trim), style: StrokeStyle(lineWidth: ermine ? 0.075 * u : 0.04 * u, lineCap: .round, lineJoin: .round))
                if ermine {
                    for (x, y) in [(-0.44, 0.10), (-0.30, 0.115), (-0.12, 0.125), (0.08, 0.115), (0.24, 0.085), (0.40, 0.05)] as [(CGFloat, CGFloat)] {
                        inner.fill(ellipse(x * u, b + y * u, 0.011 * u, 0.019 * u), with: .color(.black))
                    }
                } else {
                    // The champion's star, on the flare that shows.
                    let s = star(0.43 * u, b - 0.13 * u, 0.07 * u, inner: 0.45)
                    ctx.fill(s, with: .color(trim))
                    ctx.stroke(s, with: .color(ink), style: StrokeStyle(lineWidth: L * 0.9, lineJoin: .round))
                }
            }
            ctx.stroke(c, with: .color(ink), style: StrokeStyle(lineWidth: L * 1.2, lineJoin: .round))
        }
        switch item {
        case .redCape: cape(hx(0xFF4A5E), hx(0xA8122C), lining: hx(0xFFC24A), trim: nil, ermine: false)
        case .blueCape: cape(hx(0x4F8BFF), hx(0x1239A8), lining: hx(0xE8384F), trim: nil, ermine: false)
        case .royalCape: cape(hx(0x9B4DDB), hx(0x4A1580), lining: hx(0xFFCF40), trim: .white, ermine: true)
        case .championCape: cape(hx(0xE0243A), hx(0x7E0A1E), lining: hx(0x2F2F3A), trim: hx(0xFFCF40), ermine: false)
        case .victoryBanner:
            // Planted right behind him, flying ABOVE his head — high and
            // close in, so it never meets a companion or a stat column.
            let px = 0.14 * u
            var ctx = ctx
            if tight {
                // A size smaller about the pole's foot, so it flies below
                // the card's top edge.
                let fy = a.bottom - 0.30 * u
                ctx.translateBy(x: px, y: fy); ctx.scaleBy(x: 0.8, y: 0.8); ctx.translateBy(x: -px, y: -fy)
            }
            var pole = Path(); pole.move(to: pt(px, a.bottom - 0.30 * u)); pole.addLine(to: pt(px + 0.02 * u, a.topY - 0.30 * u))
            ctx.stroke(pole, with: .color(hx(0x6B4E2A)), style: StrokeStyle(lineWidth: 0.03 * u, lineCap: .round))
            ctx.fill(circle(px + 0.02 * u, a.topY - 0.32 * u, 0.034 * u), with: .color(hx(0xFFCF40)))
            let top = a.topY - 0.27 * u
            let fx = px + 0.02 * u
            var flag = Path()
            flag.move(to: pt(fx, top))
            flag.addQuadCurve(to: pt(fx + 0.44 * u, top + 0.04 * u), control: pt(fx + 0.22 * u, top - 0.06 * u))
            flag.addLine(to: pt(fx + 0.35 * u, top + 0.15 * u))
            flag.addLine(to: pt(fx + 0.42 * u, top + 0.27 * u))
            flag.addQuadCurve(to: pt(fx - 0.005 * u, top + 0.26 * u), control: pt(fx + 0.20 * u, top + 0.18 * u))
            flag.closeSubpath()
            ctx.fill(flag, with: lin([hx(0xE0243A), hx(0xA8122C)], pt(fx, top), pt(fx + 0.44 * u, top + 0.2 * u)))
            var trim = ctx; trim.clip(to: flag)
            trim.stroke(flag, with: .color(hx(0xFFCF40)), lineWidth: 0.03 * u)
            ctx.stroke(flag, with: .color(ink), lineWidth: L)
            ctx.fill(star(fx + 0.17 * u, top + 0.12 * u, 0.068 * u, inner: 0.45), with: .color(hx(0xFFCF40)))
        case .goldenWings:
            for sx in [-1.0, 1.0] as [CGFloat] {
                let rx = sx * 0.16 * u, ry = a.bottom - 0.46 * u
                // Tight surface: each wing swings UP about its root (angel
                // wings over his shoulders) and a size smaller, so the span
                // stays inside his own column instead of over the stats.
                var ctx = ctx
                if tight {
                    ctx.translateBy(x: rx, y: ry)
                    ctx.rotate(by: .degrees(-50 * sx))
                    ctx.scaleBy(x: 0.78, y: 0.78)
                    ctx.translateBy(x: -rx, y: -ry)
                }
                var w = Path()
                w.move(to: pt(rx, ry))
                w.addCurve(to: pt(sx * 0.86 * u, ry - 0.40 * u), control1: pt(sx * 0.34 * u, ry - 0.30 * u), control2: pt(sx * 0.62 * u, ry - 0.46 * u))
                w.addQuadCurve(to: pt(sx * 0.80 * u, ry - 0.10 * u), control: pt(sx * 0.90 * u, ry - 0.24 * u))
                let tips: [(CGFloat, CGFloat)] = [(0.80, -0.10), (0.70, 0.04), (0.58, 0.12), (0.45, 0.16), (0.32, 0.14)]
                for i in 1..<tips.count {
                    let p0 = tips[i - 1], p1 = tips[i]
                    w.addQuadCurve(to: pt(sx * p1.0 * u, ry + p1.1 * u), control: pt(sx * (p0.0 + p1.0) / 2 * u + sx * 0.01 * u, ry + max(p0.1, p1.1) * u + 0.07 * u))
                }
                w.addQuadCurve(to: pt(rx, ry + 0.06 * u), control: pt(sx * 0.22 * u, ry + 0.14 * u))
                w.closeSubpath()
                if glow {
                    var g = ctx; g.addFilter(.blur(radius: 0.05 * u)); g.fill(w, with: .color(hx(0xFFD24A, 0.6)))
                }
                ctx.fill(w, with: lin([hx(0xFFF6C8), hx(0xFFD24A), hx(0xE0A512)], pt(rx, ry - 0.4 * u), pt(sx * 0.6 * u, ry + 0.2 * u)))
                var inner = ctx; inner.clip(to: w)
                for (i, t) in tips.enumerated() where i > 0 {
                    var f = Path(); f.move(to: pt(sx * (t.0 - 0.02) * u, ry + (t.1 - 0.02) * u))
                    f.addQuadCurve(to: pt(sx * (0.28 + CGFloat(i) * 0.1) * u, ry - (0.18 + CGFloat(i) * 0.04) * u), control: pt(sx * (t.0 - 0.06) * u, ry - 0.08 * u))
                    inner.stroke(f, with: .color(hx(0xB57F0C, 0.8)), style: StrokeStyle(lineWidth: L, lineCap: .round))
                }
                var top = Path(); top.move(to: pt(rx, ry)); top.addCurve(to: pt(sx * 0.86 * u, ry - 0.40 * u), control1: pt(sx * 0.34 * u, ry - 0.30 * u), control2: pt(sx * 0.62 * u, ry - 0.46 * u))
                inner.stroke(top, with: .color(.white.opacity(0.7)), lineWidth: 0.03 * u)
                ctx.stroke(w, with: .color(hx(0x8A5A00)), style: StrokeStyle(lineWidth: L, lineJoin: .round))
            }
        case .turkeyFeathers:
            let colors: [UInt32] = [0xC2410C, 0xEA8A1E, 0xE8384F, 0xEA8A1E, 0xC2410C, 0xA16207, 0xA16207]
            let angles: [Double] = [-70, -45, -20, 0, 20, 45, 70]
            let baseY = a.bottom - 0.28 * u
            for (i, angle) in angles.enumerated() {
                let g = placed(ctx, 0, baseY, angle)
                let feather = ellipse(0, -0.33 * u, 0.075 * u, 0.20 * u)
                g.fill(feather, with: .color(hx(colors[i])))
                g.stroke(feather, with: .color(hx(0x7C2D12)), lineWidth: max(0.8, 0.005 * u))
                g.fill(ellipse(0, -0.46 * u, 0.035 * u, 0.05 * u), with: .color(hx(0xFDE68A, 0.8)))
            }
        default: break
        }
    }

    // MARK: - Trails (behind him, streaming to the viewer's LEFT)

    /// A point on the trail curve: t=0 on the ground at the far left, t=1 at
    /// his back. `reach` scales how far left it can go. `low` (he wears a
    /// cape) starts it under the cape's LEFT hem instead of his upper back:
    /// the cape's lifted corner is on the right, so the two never stack.
    static func trailPoint(_ t: CGFloat, _ a: Anchors, _ u: CGFloat, reach: CGFloat, low: Bool = false) -> CGPoint {
        let span = max(0.55, reach) * u
        let p0 = pt(-span - 0.10 * u, a.ground - 0.02 * u)
        let c = low ? pt(-span * 0.66, a.bottom - 0.30 * u) : pt(-span * 0.62, a.bottom - 0.56 * u)
        let p1 = low ? pt(-0.30 * u, a.bottom - 0.08 * u) : pt(-0.06 * u, a.bottom - 0.42 * u)
        let mt = 1 - t
        return pt(mt * mt * p0.x + 2 * mt * t * c.x + t * t * p1.x, mt * mt * p0.y + 2 * mt * t * c.y + t * t * p1.y)
    }

    static func trailCurve(_ a: Anchors, _ u: CGFloat, reach: CGFloat, low: Bool = false, from: CGFloat = 0, to: CGFloat = 1, dy: CGFloat = 0) -> Path {
        var p = Path()
        for i in 0...40 {
            let t = from + (to - from) * CGFloat(i) / 40
            var q = trailPoint(t, a, u, reach: reach, low: low); q.y += dy
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        return p
    }

    static func drawTrail(_ item: FlameyItem, in ctx: inout GraphicsContext, a: Anchors, u: CGFloat, reach: CGFloat, low: Bool = false) {
        let L = lw(u)
        func point(_ t: CGFloat) -> CGPoint { trailPoint(t, a, u, reach: reach, low: low) }
        /// The unit direction of travel back along the trail at `t` (toward
        /// its far, faded end) — what streaks and feathers align to.
        func back(_ t: CGFloat) -> CGPoint {
            let p0 = point(max(0, t - 0.02)), p1 = point(min(1, t + 0.02))
            let dx = p0.x - p1.x, dy = p0.y - p1.y
            let d = max(0.0001, sqrt(dx * dx + dy * dy))
            return pt(dx / d, dy / d)
        }
        switch item {
        case .emberSparks:
            // A hot wake of embers: a glow that burns brightest at his back
            // and cools as it trails away, streaked sparks laid ALONG the
            // direction of travel, and loose embers drifting up out of it.
            let wake = trailCurve(a, u, reach: reach, low: low, from: 0.06, to: 0.98)
            var gl = ctx; gl.addFilter(.blur(radius: 0.05 * u))
            gl.stroke(wake, with: lin([hx(0xFF4E1A, 0), hx(0xFF6A1F, 0.5), hx(0xFFB547, 0.9)], point(0.06), point(0.98)),
                      style: StrokeStyle(lineWidth: 0.13 * u, lineCap: .round))
            ctx.stroke(trailCurve(a, u, reach: reach, low: low, from: 0.35, to: 0.98),
                       with: lin([hx(0xFFB547, 0), hx(0xFFE9A8, 0.85)], point(0.35), point(0.98)),
                       style: StrokeStyle(lineWidth: 0.022 * u, lineCap: .round))
            for i in 0..<16 {
                let t = 0.10 + CGFloat(i) / 16 * 0.86
                let d = back(t)
                let nrm = pt(-d.y, d.x)
                let off = CGFloat((i * 37) % 9 - 4) / 4 * 0.065 * u * (1.15 - t * 0.5)
                let q = pt(point(t).x + nrm.x * off, point(t).y + nrm.y * off)
                let len = (0.05 + 0.07 * t) * u, w = (0.010 + 0.014 * t) * u
                let tail = pt(q.x + d.x * len, q.y + d.y * len)
                var s = Path(); s.move(to: q); s.addLine(to: tail)
                var sg = ctx; sg.addFilter(.blur(radius: w * 0.9))
                sg.stroke(s, with: .color(hx(0xFF7A1F, 0.8)), style: StrokeStyle(lineWidth: w * 2.4, lineCap: .round))
                ctx.stroke(s, with: lin([hx(0xFFF6D0), hx(0xFFB020), hx(0xFF4E1A, 0)], q, tail), style: StrokeStyle(lineWidth: w, lineCap: .round))
                ctx.fill(circle(q.x, q.y, w * 0.75), with: .color(.white))
            }
            // Loose embers rising out of the wake.
            for i in 0..<9 {
                let t = 0.18 + CGFloat(i) / 9 * 0.78
                var q = point(t)
                q.y -= (0.05 + CGFloat((i * 29) % 7) / 7 * 0.12) * u
                q.x += CGFloat((i * 13) % 5 - 2) * 0.015 * u
                let r = (0.010 + 0.016 * t) * u
                var eg = ctx; eg.addFilter(.blur(radius: r * 1.2)); eg.fill(circle(q.x, q.y, r * 2), with: .color(hx(0xFF9A1F, 0.7)))
                if i % 3 == 0 {
                    ctx.fill(star(q.x, q.y, r * 2.2, inner: 0.24, points: 4), with: .color(hx(0xFFF3B0)))
                } else {
                    ctx.fill(circle(q.x, q.y, r), with: .color(i % 2 == 0 ? hx(0xFFE27A) : hx(0xFF8A2E)))
                }
            }
        case .dustPuffs:
            // Kicked up at his HEELS, not his back: a low cloud rolling along
            // the ground behind his feet — biggest where it's thrown up,
            // thinning and settling as it falls behind — with speed ticks
            // over it. Shaded like his other props (lit top, a warm shadow
            // underneath, one soft outline) so it reads as dust, not smoke.
            let g = a.ground
            let span = max(0.55, reach) * u
            let x0 = (low ? -0.40 : -0.24) * u
            let x1 = -span - 0.06 * u
            var clusters: [[(CGFloat, CGFloat, CGFloat)]] = []
            var alphas: [Double] = []
            for i in 0..<6 {
                let f = CGFloat(i) / 5
                let x = x0 + (x1 - x0) * f
                let r = (0.085 - 0.045 * f) * u
                let cy = g - r * 0.85 - f * 0.05 * u
                clusters.append([(x, cy, r), (x - r * 0.8, cy + r * 0.28, r * 0.72), (x + r * 0.75, cy + r * 0.30, r * 0.68),
                                 (x - r * 0.15, cy - r * 0.55, r * 0.66)])
                alphas.append(0.98 - 0.55 * Double(f))
            }
            for (k, cl) in clusters.enumerated().reversed() {
                var puff = Path()
                for (x, y, r) in cl { puff.addPath(circle(x, y, r)) }
                let box = puff.boundingRect
                var g2 = ctx; g2.opacity = alphas[k]
                g2.stroke(puff, with: .color(hx(0x9C8163)), lineWidth: L * 2.2)
                g2.fill(puff, with: lin([hx(0xFBF1DE), hx(0xE6D2B2), hx(0xC4A57F)], pt(0, box.minY), pt(0, box.maxY)))
                let (hx0, hy0, hr) = cl[3]
                g2.fill(circle(hx0 - hr * 0.25, hy0 - hr * 0.25, hr * 0.42), with: .color(.white.opacity(0.55)))
            }
            // Speed ticks over the cloud: which way he's going.
            for (i, dy) in [0.20, 0.30].enumerated() {
                let y = g - CGFloat(dy) * u
                let xs = x0 - 0.06 * u - CGFloat(i) * 0.05 * u
                var l = Path(); l.move(to: pt(xs, y)); l.addLine(to: pt(xs - (0.22 - CGFloat(i) * 0.06) * u, y))
                ctx.stroke(l, with: lin([.white.opacity(0.7), .white.opacity(0)], pt(xs, y), pt(xs - 0.22 * u, y)),
                           style: StrokeStyle(lineWidth: 0.02 * u, lineCap: .round))
            }
        case .speedLines:
            // Anchored to his body: every line starts inside his back edge
            // (drawn behind him, so it emerges FROM him) and runs away left.
            let lines: [(CGFloat, CGFloat, CGFloat)] = [(-0.62, 0.45, 0.6), (-0.52, 0.72, 0.85), (-0.42, 0.95, 1.0),
                                                        (-0.32, 0.8, 0.9), (-0.22, 0.62, 0.75), (-0.12, 0.4, 0.55)]
            for (dy, len, al) in lines {
                let y = a.bottom + dy * u
                let x1 = -0.20 * u
                let x2 = x1 - len * max(0.5, reach) * u
                var l = Path(); l.move(to: pt(x1, y)); l.addLine(to: pt(x2, y))
                ctx.stroke(l, with: lin([.white.opacity(0.95 * Double(al)), .white.opacity(0)], pt(-0.36 * u, y), pt(x2, y)),
                           style: StrokeStyle(lineWidth: 0.032 * u, lineCap: .round))
            }
        case .cometTail:
            var tail = Path()
            let tip = point(1)
            tail.move(to: pt(tip.x, tip.y - 0.17 * u))
            tail.addQuadCurve(to: point(0.0), control: pt(-0.62 * reach * u, a.bottom - 0.74 * u))
            tail.addQuadCurve(to: pt(tip.x, tip.y + 0.17 * u), control: pt(-0.58 * reach * u, a.bottom - 0.38 * u))
            tail.closeSubpath()
            var gl = ctx; gl.addFilter(.blur(radius: 0.04 * u))
            gl.fill(tail, with: lin([hx(0x7FE9FF, 0.9), hx(0x4F7BFF, 0.0)], tip, point(0)))
            ctx.fill(tail, with: lin([.white.opacity(0.85), hx(0x9FE3FF, 0.5), hx(0x4F7BFF, 0.0)], tip, point(0.05)))
            for i in 0..<6 {
                let q = point(0.2 + CGFloat(i) * 0.12)
                ctx.fill(circle(q.x, q.y + CGFloat(i % 2 == 0 ? -1 : 1) * 0.07 * u, 0.013 * u), with: .color(.white))
            }
        case .smokeRings:
            // Puffed out behind him like a little steam engine: rings seen
            // side-on (narrow along the way he's going), each one bigger and
            // fainter than the last as it drifts back, strung on a thin wisp.
            let wisp = trailCurve(a, u, reach: reach, low: low, from: 0.04, to: 0.96)
            var wg = ctx; wg.addFilter(.blur(radius: 0.025 * u))
            wg.stroke(wisp, with: lin([.white.opacity(0), .white.opacity(0.35)], point(0.04), point(0.96)),
                      style: StrokeStyle(lineWidth: 0.035 * u, lineCap: .round))
            for (i, t) in ([0.16, 0.38, 0.60, 0.82] as [CGFloat]).enumerated() {
                let q = point(t)
                let d = back(t)
                let s = 0.62 + (1 - t) * 0.72
                let alpha = 0.40 + Double(t) * 0.60
                let rg = placed(ctx, q.x, q.y, atan2(Double(d.y), Double(d.x)) * 180 / .pi)
                let ring = ellipse(0, 0, 0.055 * u * s, 0.12 * u * s)
                let w = 0.042 * u * s
                var g2 = rg; g2.opacity = alpha
                var soft = g2; soft.addFilter(.blur(radius: w * 0.5))
                soft.stroke(ring, with: .color(hx(0xCFC8E0, 0.6)), lineWidth: w * 1.8)
                g2.stroke(ring, with: .color(hx(0x7D7690)), lineWidth: w + L * 1.6)
                g2.stroke(ring, with: lin([hx(0xFFFFFF), hx(0xE4E0EE), hx(0xABA3C0)], pt(0, -0.12 * u * s), pt(0, 0.12 * u * s)), lineWidth: w)
                var hl = Path()
                hl.addEllipse(in: CGRect(x: -0.055 * u * s, y: -0.12 * u * s, width: 0.11 * u * s, height: 0.24 * u * s))
                g2.stroke(hl.trimmedPath(from: 0.55, to: 0.72), with: .color(.white.opacity(0.9)),
                          style: StrokeStyle(lineWidth: w * 0.28, lineCap: .round))
                _ = i
            }
        case .starTrail:
            for i in 0..<9 {
                let t = 0.05 + CGFloat(i) / 9 * 0.9
                var q = point(t); q.y += CGFloat(i % 2 == 0 ? -1 : 1) * 0.04 * u
                let r = (0.022 + 0.05 * t) * u
                var gl = ctx; gl.addFilter(.blur(radius: r * 0.4)); gl.fill(circle(q.x, q.y, r), with: .color(hx(0xFFD24A, 0.6)))
                let g = placed(ctx, q.x, q.y, Double(i * 23))
                g.fill(star(0, 0, r, inner: 0.45), with: lin([hx(0xFFF6C8), hx(0xFFC21F)], pt(0, -r), pt(0, r)))
                g.stroke(star(0, 0, r, inner: 0.45), with: .color(hx(0xD98A00)), style: StrokeStyle(lineWidth: L * 0.7, lineJoin: .round))
            }
        case .rainbowStreak:
            let cols = [hx(0xFF4F5E), hx(0xFF9A1F), hx(0xFFE14D), hx(0x3EE08A), hx(0x3FA9FF), hx(0x9B6BFF)]
            let w = 0.034 * u
            for (i, c) in cols.enumerated() {
                let p = trailCurve(a, u, reach: reach, low: low, from: 0.0, to: 0.97, dy: (CGFloat(i) - 2.5) * w)
                ctx.stroke(p, with: lin([c.opacity(0), c], point(0), point(0.6)), style: StrokeStyle(lineWidth: w + 0.5, lineCap: .butt))
            }
            let q = point(0.12)
            for (dx, dy, r) in [(-0.05, 0.02, 0.06), (0.02, -0.02, 0.07), (0.08, 0.03, 0.05)] as [(CGFloat, CGFloat, CGFloat)] {
                ctx.fill(circle(q.x + dx * u, q.y + dy * u + 0.06 * u, r * u), with: .color(.white.opacity(0.95)))
            }
        case .lightningTrail:
            var z = Path()
            let n = 9
            for i in 0...n {
                let t = CGFloat(i) / CGFloat(n)
                var q = point(0.05 + t * 0.93)
                q.y += (i % 2 == 0 ? -1 : 1) * 0.07 * u * (i == n ? 0 : 1)
                if i == 0 { z.move(to: q) } else { z.addLine(to: q) }
            }
            var gl = ctx; gl.addFilter(.blur(radius: 0.03 * u))
            gl.stroke(z, with: .color(hx(0x7FE9FF)), style: StrokeStyle(lineWidth: 0.07 * u, lineCap: .round, lineJoin: .round))
            ctx.stroke(z, with: .color(hx(0xFFE14D)), style: StrokeStyle(lineWidth: 0.035 * u, lineCap: .round, lineJoin: .round))
            ctx.stroke(z, with: .color(.white), style: StrokeStyle(lineWidth: 0.012 * u, lineCap: .round, lineJoin: .round))
        case .fireworks:
            let bursts: [(CGFloat, CGFloat, Color)] = [(0.22, 0.13, hx(0xFF4F7B)), (0.5, 0.17, hx(0xFFD24A)), (0.78, 0.11, hx(0x5CC8FF))]
            for (t, r0, c) in bursts {
                var q = point(t); q.y -= 0.12 * u
                let r = r0 * u
                var gl = ctx; gl.addFilter(.blur(radius: r * 0.3)); gl.fill(circle(q.x, q.y, r * 0.5), with: .color(c.opacity(0.5)))
                for i in 0..<12 {
                    let ang = Double(i) / 12 * 2 * .pi
                    let d0 = r * 0.35, d1 = r
                    var l = Path(); l.move(to: pt(q.x + CGFloat(cos(ang)) * d0, q.y + CGFloat(sin(ang)) * d0)); l.addLine(to: pt(q.x + CGFloat(cos(ang)) * d1, q.y + CGFloat(sin(ang)) * d1))
                    ctx.stroke(l, with: .color(c), style: StrokeStyle(lineWidth: 0.013 * u, lineCap: .round))
                    ctx.fill(circle(q.x + CGFloat(cos(ang)) * d1 * 1.12, q.y + CGFloat(sin(ang)) * d1 * 1.12, 0.01 * u), with: .color(.white))
                }
                ctx.fill(circle(q.x, q.y, 0.018 * u), with: .color(.white))
            }
            ctx.stroke(trailCurve(a, u, reach: reach, low: low, from: 0.0, to: 0.95), with: .color(hx(0xFFD24A, 0.35)),
                       style: StrokeStyle(lineWidth: 0.01 * u, dash: [0.02 * u, 0.03 * u]))
        case .phoenixFeathers:
            // A phoenix's tail: a fire-lit wake with long flame feathers
            // streaming back ALONG it (quill toward him, tip away), biggest
            // at his back, and sparks shed off the edges.
            let wake = trailCurve(a, u, reach: reach, low: low, from: 0.08, to: 0.98)
            var gl = ctx; gl.addFilter(.blur(radius: 0.05 * u))
            gl.stroke(wake, with: lin([hx(0xE0243A, 0), hx(0xFF5A1F, 0.55), hx(0xFFC24A, 0.8)], point(0.08), point(0.98)),
                      style: StrokeStyle(lineWidth: 0.12 * u, lineCap: .round))
            for (i, t) in ([0.18, 0.36, 0.54, 0.72, 0.90] as [CGFloat]).enumerated() {
                let d = back(t)
                let side: CGFloat = i % 2 == 0 ? 1 : -1
                let nrm = pt(-d.y, d.x)
                let base = point(t)
                let q = pt(base.x + nrm.x * side * 0.035 * u, base.y + nrm.y * side * 0.035 * u)
                let s = 0.50 + 0.62 * t
                let ang = atan2(Double(d.y), Double(d.x)) * 180 / .pi + Double(side) * 12
                let g = placed(ctx, q.x, q.y, ang)
                let len = 0.30 * u * s, wid = 0.085 * u * s
                var f = Path()
                f.move(to: pt(-0.02 * len, 0))
                f.addCurve(to: pt(len, -0.02 * wid), control1: pt(0.20 * len, -wid * 1.1), control2: pt(0.75 * len, -wid * 0.9))
                f.addCurve(to: pt(-0.02 * len, 0), control1: pt(0.75 * len, wid * 0.8), control2: pt(0.20 * len, wid * 1.0))
                f.closeSubpath()
                var fg = g; fg.addFilter(.blur(radius: 0.025 * u)); fg.fill(f, with: .color(hx(0xFF7A1F, 0.65)))
                g.fill(f, with: lin([hx(0xFFF3A0), hx(0xFFB020), hx(0xFF5A1F), hx(0xC8102E)], pt(0, 0), pt(len, 0)))
                var barbs = g; barbs.clip(to: f)
                for k in 1..<6 {
                    let x = len * CGFloat(k) / 6
                    for sy in [-1.0, 1.0] as [CGFloat] {
                        var b = Path(); b.move(to: pt(x - len * 0.06, 0)); b.addLine(to: pt(x + len * 0.05, sy * wid))
                        barbs.stroke(b, with: .color(hx(0x8A1A0A, 0.45)), lineWidth: max(0.8, L * 0.8))
                    }
                }
                // The eye of the feather: a bright flame drop near the tip.
                barbs.fill(ellipse(len * 0.70, 0, wid * 0.42, wid * 0.36), with: .color(hx(0xFFE36B, 0.9)))
                barbs.fill(ellipse(len * 0.70, 0, wid * 0.18, wid * 0.16), with: .color(hx(0xC8102E)))
                var shaft = Path(); shaft.move(to: pt(-0.06 * len, 0)); shaft.addLine(to: pt(len * 0.95, 0))
                g.stroke(shaft, with: .color(hx(0x7A1408, 0.85)), style: StrokeStyle(lineWidth: max(1, L * 1.1), lineCap: .round))
                g.stroke(f, with: .color(hx(0x6A1206)), style: StrokeStyle(lineWidth: L, lineJoin: .round))
            }
            for i in 0..<8 {
                let t = 0.12 + CGFloat(i) / 8 * 0.82
                var q = point(t); q.y -= CGFloat((i * 31) % 7 - 3) * 0.03 * u
                let r = (0.009 + 0.012 * t) * u
                var sg = ctx; sg.addFilter(.blur(radius: r)); sg.fill(circle(q.x, q.y, r * 1.8), with: .color(hx(0xFFB020, 0.8)))
                ctx.fill(circle(q.x, q.y, r), with: .color(hx(0xFFF3B0)))
            }
        case .auroraRibbon:
            for (i, c) in [hx(0x3DFFB0), hx(0x55C8FF), hx(0xB46BFF)].enumerated() {
                var p = Path()
                for j in 0...40 {
                    let t = CGFloat(j) / 40 * 0.97
                    var q = point(t); q.y += CGFloat(i) * 0.05 * u + 0.05 * u * sin(t * 12 + CGFloat(i))
                    if j == 0 { p.move(to: q) } else { p.addLine(to: q) }
                }
                var gl = ctx; gl.addFilter(.blur(radius: 0.03 * u))
                gl.stroke(p, with: lin([c.opacity(0), c.opacity(0.85)], point(0), point(0.7)), style: StrokeStyle(lineWidth: 0.11 * u, lineCap: .round))
                ctx.stroke(p, with: lin([c.opacity(0), c.opacity(0.9)], point(0), point(0.7)), style: StrokeStyle(lineWidth: 0.03 * u, lineCap: .round))
            }
        case .meteorShower:
            let span = max(0.55, reach)
            let ms: [(CGFloat, CGFloat, CGFloat)] = [(-0.40, -0.84, 1.0), (-0.78, -0.58, 0.75), (-0.30, -0.44, 0.6),
                                                     (-0.95, -0.98, 0.55), (-0.66, -0.22, 0.5)]
            for (x, y, s) in ms {
                let hxp = x * span * u, hy = a.bottom + y * u
                var tl = Path(); tl.move(to: pt(hxp, hy)); tl.addLine(to: pt(hxp - 0.30 * u * s, hy - 0.22 * u * s))
                var gl = ctx; gl.addFilter(.blur(radius: 0.015 * u))
                gl.stroke(tl, with: lin([hx(0xFFB547), hx(0xFF4E1A, 0)], pt(hxp, hy), pt(hxp - 0.3 * u * s, hy - 0.22 * u * s)), style: StrokeStyle(lineWidth: 0.05 * u * s, lineCap: .round))
                ctx.stroke(tl, with: lin([.white, hx(0xFFD24A, 0)], pt(hxp, hy), pt(hxp - 0.3 * u * s, hy - 0.22 * u * s)), style: StrokeStyle(lineWidth: 0.018 * u * s, lineCap: .round))
                ctx.fill(circle(hxp, hy, 0.028 * u * s), with: .color(.white))
                ctx.fill(circle(hxp, hy, 0.018 * u * s), with: .color(hx(0xFFE9A8)))
            }
        default: break
        }
    }

    // MARK: - Companions (standing on the viewer's RIGHT)
    //
    // Little characters drawn in HIS style: a gradient body lit from the
    // top-left, a light rim (not an ink outline — he has none), his eyes
    // (tall dark ovals, a catchlight up-left), an open grin and rosy cheeks.
    // Walkers stand on HIS ground line; floaters hover at shoulder height
    // over a small shadow of their own. Sized at ~40% of his height.

    /// Where a companion stands: clear of his body, inside the surface.
    static func companionX(_ u: CGFloat, reach: CGFloat, look: FlameyLook? = nil) -> CGFloat {
        // A cape's lifted corner reaches ~0.53u on this side: a companion
        // stands a step further out, beside the cape, never over its hem.
        let cape = look?[.back].map(isCape) ?? false
        return (max(0.56, min(0.70, reach - 0.14)) + (cape ? 0.06 : 0)) * u
    }

    /// Balance: with a back piece AND a held prop he is already wide, so the
    /// companion and the trail step down a size — the stage should read as
    /// ONE character, not a pile of everything he owns.
    static func isBusy(_ look: FlameyLook) -> Bool { look[.back] != nil && look[.held] != nil }
    static func companionScale(for look: FlameyLook) -> CGFloat { isBusy(look) ? 1.0 : 1.15 }
    static func trailScale(for look: FlameyLook) -> CGFloat { isBusy(look) ? 0.80 : 1 }

    /// How high a floater's centre hovers over the ground (body units).
    static let floatHeight: CGFloat = 0.50

    /// The companion's shadow on the floor — drawn by the layer on its own,
    /// so the creature can bob over a shadow that stays put.
    static func drawCompanionShadow(_ item: FlameyItem, in ctx: inout GraphicsContext, a: Anchors, u: CGFloat, floats: Bool) {
        var s = ctx
        s.addFilter(.blur(radius: 0.02 * u))
        let w: CGFloat = floats ? 0.16 : (item == .cometPup ? 0.30 : (item == .phoenixChick ? 0.22 : 0.24))
        s.fill(ellipse(0, a.ground - 0.004 * u, w * u / 2, 0.028 * u), with: .color(.black.opacity(floats ? 0.20 : 0.30)))
    }

    static let critterInk = hx(0x331006)

    /// His face, small: eyes, catchlights, a grin with a tongue, cheeks.
    /// `r` is the face's half-width; `glance` shifts the eyes (±r·0.1).
    static func critterFace(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat,
                            eye: Color = critterInk, glance: CGFloat = 0, cheeks: Color = hx(0xFF6F8E), grin: Bool = true) {
        for sx in [-1.0, 1.0] as [CGFloat] {
            let ex = x + sx * r * 0.40 + glance * r
            ctx.fill(ellipse(ex, y, r * 0.15, r * 0.20), with: .color(eye))
            ctx.fill(circle(ex - r * 0.045, y - r * 0.075, r * 0.06), with: .color(.white.opacity(0.95)))
            ctx.fill(ellipse(x + sx * r * 0.70, y + r * 0.28, r * 0.15, r * 0.085), with: .color(cheeks.opacity(0.45)))
        }
        if grin {
            var m = Path()
            m.move(to: pt(x - r * 0.24, y + r * 0.22))
            m.addQuadCurve(to: pt(x + r * 0.24, y + r * 0.22), control: pt(x, y + r * 0.34))
            m.addCurve(to: pt(x - r * 0.24, y + r * 0.22), control1: pt(x + r * 0.22, y + r * 0.62), control2: pt(x - r * 0.22, y + r * 0.62))
            m.closeSubpath()
            ctx.fill(m, with: .color(eye))
            var t = ctx
            t.clip(to: m)
            t.fill(ellipse(x, y + r * 0.50, r * 0.13, r * 0.08), with: .color(hx(0xFF6B5E)))
        } else {
            var m = Path()
            m.move(to: pt(x - r * 0.16, y + r * 0.26))
            m.addQuadCurve(to: pt(x + r * 0.16, y + r * 0.26), control: pt(x, y + r * 0.44))
            ctx.stroke(m, with: .color(eye), style: StrokeStyle(lineWidth: max(1, r * 0.09), lineCap: .round))
        }
    }

    /// Fill + his light rim + a top-left highlight, the house body recipe.
    static func critterBody(_ ctx: GraphicsContext, _ shape: Path, _ colors: [Color], _ box: CGRect, u: CGFloat,
                            rim: Color = .white.opacity(0.45), glow: Color? = nil) {
        if let glow {
            var g = ctx
            g.addFilter(.blur(radius: box.width * 0.22))
            g.fill(shape, with: .color(glow.opacity(0.55)))
        }
        ctx.fill(shape, with: lin(colors, pt(box.minX + box.width * 0.2, box.minY), pt(box.maxX - box.width * 0.2, box.maxY)))
        sheen(ctx, shape, box, 0.40)
        ctx.stroke(shape, with: .color(rim), lineWidth: max(1, 0.009 * u))
    }

    /// A rounded four-point star sprite.
    static func sparkBody(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        var p = Path()
        let n = 4
        for i in 0..<(n * 2) {
            let a0 = -Double.pi / 2 + Double(i) * Double.pi / Double(n)
            let rr = i % 2 == 0 ? r : r * 0.52
            let q = pt(x + rr * CGFloat(cos(a0)), y + rr * CGFloat(sin(a0)))
            if i == 0 { p.move(to: q) } else {
                let am = a0 - Double.pi / Double(n) / 2
                let rc = i % 2 == 0 ? r * 0.62 : r * 0.62
                p.addQuadCurve(to: q, control: pt(x + rc * CGFloat(cos(am)), y + rc * CGFloat(sin(am))))
            }
        }
        let am = -Double.pi / 2 - Double.pi / Double(n) / 2
        p.addQuadCurve(to: pt(x, y - r), control: pt(x + r * 0.62 * CGFloat(cos(am)), y + r * 0.62 * CGFloat(sin(am))))
        p.closeSubpath()
        return p
    }

    static func spark(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: Color, u: CGFloat, glance: CGFloat = -0.08) {
        let body = sparkBody(x, y, r)
        critterBody(ctx, body, [.white, hx(0xFFF3B0), c], CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2), u: u,
                    rim: .white.opacity(0.7), glow: c)
        critterFace(ctx, x, y + r * 0.06, r * 0.46, glance: glance)
    }

    // MARK: Companion characters (big-eyed, his outline + lighting)

    /// What a companion's face is doing. Flamey Jr. mirrors HIS (see
    /// `companionFace(for:)`); the rest just beam.
    enum CritterMood { case grin, cheer, worried, asleep }

    /// Flamey Jr. copies his big brother: the pose Flamey's arms are in
    /// says what mood he's in.
    static func companionFace(for pose: FlameArmPose) -> CritterMood {
        switch pose {
        case .cheer, .highFive, .flail: return .cheer
        case .cheeks: return .worried
        case .tucked: return .asleep
        default: return .grin
        }
    }

    /// A BIG readable face — the one every rebuilt companion wears: tall
    /// eyes with a catchlight (his eyes, scaled for a small character),
    /// blush, and a mouth for the mood. `r` is the face's half-width.
    static func bigFace(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, eye: Color = critterInk,
                        glance: CGFloat = 0, mood: CritterMood = .grin, cheeks: Color = hx(0xFF6F8E), beak: Color? = nil) {
        for sx in [-1.0, 1.0] as [CGFloat] {
            let ex = x + sx * r * 0.42 + glance * r
            switch mood {
            case .asleep:
                var lid = Path()
                lid.move(to: pt(ex - r * 0.17, y + r * 0.02)); lid.addQuadCurve(to: pt(ex + r * 0.17, y + r * 0.02), control: pt(ex, y + r * 0.16))
                ctx.stroke(lid, with: .color(eye), style: StrokeStyle(lineWidth: max(1, r * 0.08), lineCap: .round))
            default:
                let h = mood == .worried ? r * 0.30 : r * 0.27
                ctx.fill(ellipse(ex, y, r * 0.19, h), with: .color(eye))
                ctx.fill(circle(ex - r * 0.06, y - h * 0.42, r * 0.075), with: .color(.white))
                ctx.fill(circle(ex + r * 0.07, y + h * 0.35, r * 0.035), with: .color(.white.opacity(0.8)))
                if mood == .worried {
                    var brow = Path()
                    brow.move(to: pt(ex - sx * r * 0.18, y - h - r * 0.06)); brow.addLine(to: pt(ex + sx * r * 0.14, y - h - r * 0.16))
                    ctx.stroke(brow, with: .color(eye), style: StrokeStyle(lineWidth: max(1, r * 0.06), lineCap: .round))
                }
            }
            ctx.fill(ellipse(x + sx * r * 0.78, y + r * 0.30, r * 0.17, r * 0.10), with: .color(cheeks.opacity(0.55)))
        }
        let my = y + r * 0.40
        if let beak {
            var bk = Path()
            bk.move(to: pt(x - r * 0.16, my - r * 0.10)); bk.addLine(to: pt(x + r * 0.16, my - r * 0.10)); bk.addLine(to: pt(x, my + r * 0.12)); bk.closeSubpath()
            ctx.fill(bk, with: lin([hx(0xFFE45C), hx(0xFFA41F)], pt(x, my - r * 0.1), pt(x, my + r * 0.12)))
            ctx.stroke(bk, with: .color(critterInk.opacity(0.8)), style: StrokeStyle(lineWidth: max(0.8, r * 0.05), lineJoin: .round))
            return
        }
        switch mood {
        case .grin, .cheer:
            let w = mood == .cheer ? r * 0.34 : r * 0.28
            let d = mood == .cheer ? r * 0.36 : r * 0.26
            var m = Path()
            m.move(to: pt(x - w, my - r * 0.06))
            m.addQuadCurve(to: pt(x + w, my - r * 0.06), control: pt(x, my + r * 0.02))
            m.addCurve(to: pt(x - w, my - r * 0.06), control1: pt(x + w * 0.9, my + d), control2: pt(x - w * 0.9, my + d))
            m.closeSubpath()
            ctx.fill(m, with: .color(eye))
            var t = ctx; t.clip(to: m)
            t.fill(ellipse(x, my + d * 0.72, w * 0.55, d * 0.38), with: .color(hx(0xFF6B5E)))
        case .worried:
            ctx.fill(ellipse(x, my + r * 0.04, r * 0.10, r * 0.13), with: .color(eye))
        case .asleep:
            ctx.fill(ellipse(x, my, r * 0.07, r * 0.08), with: .color(eye.opacity(0.85)))
        }
    }

    /// Flamey Jr.: a little HIM — the same outline, inner flame, big eyes and
    /// grin, in his colour, about 40% of his height, with a cowlick curling
    /// off his tip so he's never mistaken for a smaller Flamey. NO arms or
    /// legs (limbs on a character this small read as a stick figure): two
    /// tiny foot nubs peek out under him, and he mirrors Flamey through his
    /// FACE and a small flourish — sparkles when he cheers, a sweat drop when
    /// he frets, a "z" when he sleeps.
    static func flameyJr(_ ctx: GraphicsContext, gy: CGFloat, u: CGFloat, palette: FlameyPalette?, pose: FlameArmPose) {
        let H = 0.34 * u, W = 0.86 * H
        let nub = 0.024 * u
        let base = gy - nub
        let rect = CGRect(x: -W / 2, y: base - H, width: W, height: H)
        let outer = palette?.outer ?? [.white, hx(0xFFE047), .orange, hx(0xFF3319)]
        let innerCols = palette?.inner ?? [.white, hx(0xFFEB4D), hx(0xFF8014)]
        let rim = palette?.rim ?? Color.white.opacity(0.4)
        let deep = [outer[max(0, outer.count - 2)], outer[outer.count - 1]]
        let rw = max(1, 0.009 * u)
        let mood = companionFace(for: pose)
        var gl = ctx
        gl.addFilter(.blur(radius: 0.05 * u))
        gl.fill(circle(0, base - H * 0.42, H * 0.48), with: .color((palette?.glow ?? .orange).opacity(0.5)))
        // Two little foot nubs, tucked half under his base.
        for sx in [-1.0, 1.0] as [CGFloat] {
            let f = ellipse(sx * W * 0.19, gy - nub * 0.95, 0.046 * u, nub * 1.05)
            ctx.fill(f, with: lin(deep, pt(0, gy - nub * 2), pt(0, gy)))
            ctx.stroke(f, with: .color(rim), lineWidth: rw)
        }
        let body = FlameBuddyOuterShape(wobble: -0.03).path(in: rect)
        if palette?.angular == true {
            ctx.fill(body, with: .conicGradient(Gradient(colors: outer + [outer[0]]), center: pt(0, base - H * 0.34)))
        } else {
            ctx.fill(body, with: lin(outer, pt(0, rect.minY), pt(0, rect.maxY)))
        }
        let innerRect = CGRect(x: -W * 0.27, y: base - H * 0.62, width: W * 0.54, height: H * 0.58)
        var inner = ctx; inner.opacity = palette?.innerOpacity ?? 0.9
        inner.fill(FlameBuddyInnerShape(wobble: 0).path(in: innerRect), with: lin(innerCols, pt(0, innerRect.minY), pt(0, innerRect.maxY)))
        sheen(ctx, body, rect, 0.22)
        ctx.stroke(body, with: .color(rim), lineWidth: rw * 1.3)
        // The cowlick: a little curl of flame off his tip.
        var curl = Path()
        let tip = pt(rect.midX + W * 0.02, rect.minY + H * 0.02)
        curl.move(to: pt(tip.x - W * 0.06, tip.y + H * 0.10))
        curl.addQuadCurve(to: pt(tip.x + W * 0.28, tip.y - H * 0.07), control: pt(tip.x + W * 0.02, tip.y - H * 0.15))
        curl.addQuadCurve(to: pt(tip.x + W * 0.12, tip.y + H * 0.02), control: pt(tip.x + W * 0.30, tip.y + H * 0.04))
        curl.addQuadCurve(to: pt(tip.x - W * 0.06, tip.y + H * 0.10), control: pt(tip.x + W * 0.06, tip.y - H * 0.02))
        curl.closeSubpath()
        ctx.fill(curl, with: lin(Array(outer.prefix(3)), pt(tip.x, tip.y - H * 0.1), pt(tip.x, tip.y + H * 0.1)))
        ctx.stroke(curl, with: .color(rim), lineWidth: rw)
        bigFace(ctx, 0, base - H * 0.33, W * 0.36, eye: palette?.eye ?? critterInk, glance: -0.10, mood: mood)
        // His mood's flourish — what his arms used to say.
        switch mood {
        case .cheer:
            for (dx, dy, r) in [(-0.60, 0.70, 0.05), (0.62, 0.55, 0.04)] as [(CGFloat, CGFloat, CGFloat)] {
                let s = star(W * dx, base - H * dy, r * u, inner: 0.3, points: 4)
                ctx.fill(s, with: .color(hx(0xFFF3B0)))
                ctx.stroke(s, with: .color(.white.opacity(0.8)), lineWidth: rw * 0.6)
            }
        case .worried:
            var drop = Path()
            let dx = W * 0.40, dy = base - H * 0.62
            drop.move(to: pt(dx, dy - 0.04 * u))
            drop.addQuadCurve(to: pt(dx, dy + 0.025 * u), control: pt(dx + 0.035 * u, dy + 0.01 * u))
            drop.addQuadCurve(to: pt(dx, dy - 0.04 * u), control: pt(dx - 0.035 * u, dy + 0.01 * u))
            ctx.fill(drop, with: lin([.white, hx(0x7FD3FF)], pt(dx, dy - 0.04 * u), pt(dx, dy + 0.03 * u)))
        case .asleep:
            let z = Text("z").font(.system(size: 0.07 * u, weight: .black, design: .rounded)).foregroundColor(.white.opacity(0.85))
            ctx.draw(z, at: pt(W * 0.52, base - H * 0.95))
        case .grin:
            break
        }
    }

    /// Ember Dragon (`firefly`, ten buddy walks — the LOYAL one): a chubby
    /// baby dragon hovering on little bat wings, horns, a tuft of fire
    /// between them, a spade tail, a peach belly — and a smoke ring puffing
    /// off toward Flamey. Violet, so he never blurs into Flamey's own fire.
    static func emberDragon(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, u: CGFloat) {
        let r = 0.105 * u
        let rw = max(1, 0.009 * u)
        let scale = [hx(0xC3A2FF), hx(0x8F5EF2), hx(0x5A2FC4)]
        let deep = hx(0x3A1A8A)
        // Smoke rings drifting up and away toward him (viewer's left).
        let rings: [(CGFloat, CGFloat, CGFloat)] = [(-1.25, -2.05, 0.40), (-1.95, -2.75, 0.27)]
        for i in 0..<rings.count {
            let (cx, cy, rr) = rings[i]
            let ring = ellipse(x + cx * r, y + cy * r, rr * r, rr * r * 0.82)
            var soft = ctx; soft.addFilter(.blur(radius: r * 0.06))
            soft.stroke(ring, with: .color(hx(0xE9E3F5, i == 0 ? 0.95 : 0.7)), lineWidth: r * (i == 0 ? 0.22 : 0.15))
            ctx.stroke(ring, with: .color(.white.opacity(i == 0 ? 0.55 : 0.35)), lineWidth: r * 0.06)
        }
        // Wings, behind: spread bat wings with a scalloped trailing edge.
        for sx in [-1.0, 1.0] as [CGFloat] {
            var w = Path()
            w.move(to: pt(x + sx * 0.40 * r, y - 0.30 * r))
            w.addQuadCurve(to: pt(x + sx * 1.60 * r, y - 1.35 * r), control: pt(x + sx * 0.75 * r, y - 1.35 * r))
            w.addQuadCurve(to: pt(x + sx * 1.35 * r, y - 0.35 * r), control: pt(x + sx * 1.72 * r, y - 0.80 * r))
            w.addQuadCurve(to: pt(x + sx * 1.00 * r, y - 0.35 * r), control: pt(x + sx * 1.18 * r, y - 0.62 * r))
            w.addQuadCurve(to: pt(x + sx * 0.62 * r, y - 0.05 * r), control: pt(x + sx * 0.80 * r, y - 0.42 * r))
            w.closeSubpath()
            ctx.fill(w, with: lin([hx(0xFFB36B), hx(0xB77BFF), hx(0x7A45E0)], pt(x + sx * 1.5 * r, y - 1.3 * r), pt(x, y)))
            var bone = Path(); bone.move(to: pt(x + sx * 0.42 * r, y - 0.32 * r)); bone.addQuadCurve(to: pt(x + sx * 1.58 * r, y - 1.33 * r), control: pt(x + sx * 0.78 * r, y - 1.30 * r))
            ctx.stroke(bone, with: .color(deep), style: StrokeStyle(lineWidth: r * 0.10, lineCap: .round))
            for (tx, ty) in [(1.35, -0.38), (1.0, -0.38)] as [(CGFloat, CGFloat)] {
                var rib = Path(); rib.move(to: pt(x + sx * 1.05 * r, y - 0.95 * r)); rib.addLine(to: pt(x + sx * tx * r, y + ty * r))
                ctx.stroke(rib, with: .color(deep.opacity(0.55)), lineWidth: rw)
            }
            ctx.stroke(w, with: .color(deep.opacity(0.8)), style: StrokeStyle(lineWidth: rw, lineJoin: .round))
        }
        // Spade tail, curling out behind to the right.
        var tail = Path()
        tail.move(to: pt(x + 0.35 * r, y + 0.85 * r))
        tail.addQuadCurve(to: pt(x + 1.30 * r, y + 0.55 * r), control: pt(x + 1.15 * r, y + 1.20 * r))
        ctx.stroke(tail, with: .color(deep), style: StrokeStyle(lineWidth: r * 0.30 + rw * 2, lineCap: .round))
        ctx.stroke(tail, with: lin(scale, pt(x, y), pt(x + 1.3 * r, y + r)), style: StrokeStyle(lineWidth: r * 0.30, lineCap: .round))
        let spade = poly([pt(x + 1.18 * r, y + 0.62 * r), pt(x + 1.62 * r, y + 0.18 * r), pt(x + 1.52 * r, y + 0.66 * r)])
        ctx.fill(spade, with: .color(hx(0xFF9A3C))); ctx.stroke(spade, with: .color(deep), style: StrokeStyle(lineWidth: rw, lineJoin: .round))
        // Body: a round egg, peach belly with scale bands.
        let body = ellipse(x, y + 0.30 * r, 0.74 * r, 0.76 * r)
        critterBody(ctx, body, scale, CGRect(x: x - 0.74 * r, y: y - 0.46 * r, width: 1.48 * r, height: 1.52 * r), u: u, rim: .white.opacity(0.5))
        let belly = ellipse(x - 0.04 * r, y + 0.40 * r, 0.46 * r, 0.56 * r)
        ctx.fill(belly, with: lin([hx(0xFFF1D6), hx(0xFFC98A)], pt(x, y), pt(x, y + r)))
        var bb = ctx; bb.clip(to: belly)
        for dy in [0.12, 0.38, 0.64] as [CGFloat] {
            var band = Path(); band.move(to: pt(x - 0.5 * r, y + dy * r)); band.addQuadCurve(to: pt(x + 0.5 * r, y + dy * r), control: pt(x, y + (dy + 0.12) * r))
            bb.stroke(band, with: .color(hx(0xD98A4A, 0.5)), lineWidth: rw)
        }
        // Stubby feet and arms.
        for sx in [-1.0, 1.0] as [CGFloat] {
            let foot = ellipse(x + sx * 0.38 * r, y + 1.02 * r, 0.22 * r, 0.14 * r)
            ctx.fill(foot, with: .color(hx(0x7A45E0))); ctx.stroke(foot, with: .color(deep), lineWidth: rw)
            let arm = placed(ctx, x + sx * 0.66 * r, y + 0.18 * r, Double(sx) * -30)
            let a = ellipse(0, 0, 0.13 * r, 0.22 * r)
            arm.fill(a, with: .color(hx(0x9A68F5))); arm.stroke(a, with: .color(deep), lineWidth: rw)
        }
        // Head: big and round, horns and a fire tuft on top.
        let hc = pt(x - 0.06 * r, y - 0.62 * r)
        for sx in [-1.0, 1.0] as [CGFloat] {
            let horn = poly([pt(hc.x + sx * 0.30 * r, hc.y - 0.52 * r), pt(hc.x + sx * 0.62 * r, hc.y - 0.40 * r), pt(hc.x + sx * 0.60 * r, hc.y - 1.08 * r)])
            ctx.fill(horn, with: lin([hx(0xFFF6E0), hx(0xE8C98E)], pt(0, hc.y - 1.1 * r), pt(0, hc.y - 0.4 * r)))
            ctx.stroke(horn, with: .color(hx(0x8A6A2A)), style: StrokeStyle(lineWidth: rw, lineJoin: .round))
        }
        let tuft = FlameBuddyOuterShape(wobble: 0.03).path(in: CGRect(x: hc.x - 0.22 * r, y: hc.y - 1.10 * r, width: 0.44 * r, height: 0.56 * r))
        var tg = ctx; tg.addFilter(.blur(radius: r * 0.1)); tg.fill(tuft, with: .color(hx(0xFF8A1F, 0.8)))
        ctx.fill(tuft, with: lin([.white, hx(0xFFE047), hx(0xFF6A14)], pt(0, hc.y - 1.1 * r), pt(0, hc.y - 0.55 * r)))
        let head = ellipse(hc.x, hc.y, 0.80 * r, 0.68 * r)
        critterBody(ctx, head, scale, CGRect(x: hc.x - 0.8 * r, y: hc.y - 0.68 * r, width: 1.6 * r, height: 1.36 * r), u: u, rim: .white.opacity(0.5))
        // A lighter muzzle and two nostrils.
        ctx.fill(ellipse(hc.x - 0.02 * r, hc.y + 0.30 * r, 0.44 * r, 0.28 * r), with: .color(hx(0xD9C4FF, 0.9)))
        bigFace(ctx, hc.x, hc.y - 0.06 * r, 0.62 * r, eye: hx(0x1E0A4A), glance: -0.12, cheeks: hx(0xFF7FB0))
        for sx in [-1.0, 1.0] as [CGFloat] {
            ctx.fill(ellipse(hc.x + sx * 0.09 * r, hc.y + 0.13 * r, 0.035 * r, 0.025 * r), with: .color(hx(0x3A1A8A, 0.8)))
        }
    }

    /// Blaze the fire fox (`phoenix_chick`, won a buddy RACE — the fast
    /// one): a fox kit standing tall, huge ears, white cheek fluff, a flame
    /// blaze on his brow, a winner's medal — and a big fluffy tail that IS a
    /// flame, curling up behind him.
    static func blazeFox(_ ctx: GraphicsContext, gy: CGFloat, u: CGFloat) {
        let s = 0.1 * u
        let rw = max(1, 0.009 * u)
        let ink = hx(0x5A1406)
        let fur = [hx(0xFFB65C), hx(0xFF7A1F), hx(0xD9401A)]
        let cream = hx(0xFFF3E0)
        var gl = ctx; gl.addFilter(.blur(radius: s * 0.9))
        gl.fill(circle(0.6 * s, gy - 2.0 * s, 1.6 * s), with: .color(hx(0xFF7A1F, 0.35)))
        // The flame tail, behind — rising up his right side to a white-hot tip.
        var tail = Path()
        tail.move(to: pt(0.30 * s, gy - 0.45 * s))
        tail.addQuadCurve(to: pt(2.05 * s, gy - 1.55 * s), control: pt(2.10 * s, gy - 0.35 * s))
        tail.addQuadCurve(to: pt(1.45 * s, gy - 3.55 * s), control: pt(2.30 * s, gy - 2.70 * s))
        tail.addQuadCurve(to: pt(1.25 * s, gy - 2.45 * s), control: pt(1.10 * s, gy - 3.05 * s))
        tail.addQuadCurve(to: pt(0.95 * s, gy - 2.85 * s), control: pt(1.25 * s, gy - 2.70 * s))
        tail.addQuadCurve(to: pt(0.95 * s, gy - 1.70 * s), control: pt(0.70 * s, gy - 2.20 * s))
        tail.addQuadCurve(to: pt(0.35 * s, gy - 1.10 * s), control: pt(1.05 * s, gy - 1.20 * s))
        tail.closeSubpath()
        var tgl = ctx; tgl.addFilter(.blur(radius: s * 0.25))
        tgl.fill(tail, with: .color(hx(0xFF9A1F, 0.7)))
        // Flame licks breaking off its outer edge — fire, not fur.
        for (lx, ly, ang, h) in [(2.10, -2.35, 38.0, 0.95), (2.05, -1.35, 62.0, 0.75), (1.70, -3.05, 18.0, 0.80)] as [(CGFloat, CGFloat, Double, CGFloat)] {
            let g = placed(ctx, lx * s, gy + ly * s, ang)
            let lick = FlameBuddyOuterShape(wobble: 0.04).path(in: CGRect(x: -0.24 * s, y: -h * s, width: 0.48 * s, height: h * s + 0.2 * s))
            g.fill(lick, with: lin([hx(0xFFF3A0), hx(0xFF8A1F)], pt(0, -h * s), pt(0, 0.2 * s)))
            g.stroke(lick, with: .color(ink.opacity(0.6)), lineWidth: rw * 0.8)
        }
        ctx.fill(tail, with: lin([hx(0xFFFBE0), hx(0xFFD84A), hx(0xFF8A1F), hx(0xE8401F)], pt(1.4 * s, gy - 3.5 * s), pt(1.0 * s, gy - 0.5 * s)))
        ctx.stroke(tail, with: .color(ink.opacity(0.8)), style: StrokeStyle(lineWidth: rw, lineJoin: .round))
        // Body.
        let body = ellipse(0, gy - 0.95 * s, 0.78 * s, 0.88 * s)
        critterBody(ctx, body, fur, CGRect(x: -0.78 * s, y: gy - 1.83 * s, width: 1.56 * s, height: 1.76 * s), u: u, rim: .white.opacity(0.45))
        ctx.fill(ellipse(-0.04 * s, gy - 0.82 * s, 0.44 * s, 0.58 * s), with: .color(cream))
        for sx in [-1.0, 1.0] as [CGFloat] {
            let paw = ellipse(sx * 0.40 * s, gy - 0.15 * s, 0.30 * s, 0.17 * s)
            ctx.fill(paw, with: .color(hx(0x3A1A10))); ctx.stroke(paw, with: .color(ink), lineWidth: rw)
        }
        // A winner's medal on a red ribbon.
        var rib = Path()
        rib.move(to: pt(-0.34 * s, gy - 1.72 * s)); rib.addLine(to: pt(-0.02 * s, gy - 1.20 * s)); rib.addLine(to: pt(0.30 * s, gy - 1.72 * s))
        ctx.stroke(rib, with: .color(hx(0xE8384F)), style: StrokeStyle(lineWidth: s * 0.16, lineCap: .round, lineJoin: .round))
        ctx.fill(circle(-0.02 * s, gy - 1.05 * s, 0.24 * s), with: lin([hx(0xFFF3B0), hx(0xFFC21F), hx(0xC98A00)], pt(0, gy - 1.3 * s), pt(0, gy - 0.8 * s)))
        ctx.stroke(circle(-0.02 * s, gy - 1.05 * s, 0.24 * s), with: .color(hx(0x8A5A00)), lineWidth: rw)
        ctx.fill(star(-0.02 * s, gy - 1.05 * s, 0.12 * s, inner: 0.45), with: .color(.white.opacity(0.9)))
        // Head: a fox mask — wide cheek points, big ears.
        let hc = pt(-0.05 * s, gy - 2.25 * s)
        for sx in [-1.0, 1.0] as [CGFloat] {
            let ear = poly([pt(hc.x + sx * 0.92 * s, hc.y - 0.30 * s), pt(hc.x + sx * 0.22 * s, hc.y - 0.82 * s), pt(hc.x + sx * 1.02 * s, hc.y - 1.72 * s)])
            ctx.fill(ear, with: lin(fur, pt(0, hc.y - 1.7 * s), pt(0, hc.y - 0.3 * s)))
            ctx.stroke(ear, with: .color(ink), style: StrokeStyle(lineWidth: rw, lineJoin: .round))
            let innerEar = poly([pt(hc.x + sx * 0.78 * s, hc.y - 0.50 * s), pt(hc.x + sx * 0.42 * s, hc.y - 0.78 * s), pt(hc.x + sx * 0.92 * s, hc.y - 1.42 * s)])
            ctx.fill(innerEar, with: lin([hx(0x3A1A10), hx(0x7A2A14)], pt(0, hc.y - 1.4 * s), pt(0, hc.y - 0.5 * s)))
        }
        var head = Path()
        head.move(to: pt(hc.x, hc.y - 0.95 * s))
        head.addQuadCurve(to: pt(hc.x + 1.18 * s, hc.y + 0.28 * s), control: pt(hc.x + 1.05 * s, hc.y - 0.95 * s))
        head.addQuadCurve(to: pt(hc.x, hc.y + 0.86 * s), control: pt(hc.x + 0.72 * s, hc.y + 0.86 * s))
        head.addQuadCurve(to: pt(hc.x - 1.18 * s, hc.y + 0.28 * s), control: pt(hc.x - 0.72 * s, hc.y + 0.86 * s))
        head.addQuadCurve(to: pt(hc.x, hc.y - 0.95 * s), control: pt(hc.x - 1.05 * s, hc.y - 0.95 * s))
        head.closeSubpath()
        critterBody(ctx, head, fur, CGRect(x: hc.x - 1.18 * s, y: hc.y - 0.95 * s, width: 2.36 * s, height: 1.81 * s), u: u, rim: .white.opacity(0.5))
        // White cheek fluff and muzzle.
        var mask = ctx; mask.clip(to: head)
        for sx in [-1.0, 1.0] as [CGFloat] {
            mask.fill(ellipse(hc.x + sx * 0.62 * s, hc.y + 0.50 * s, 0.62 * s, 0.42 * s), with: .color(cream))
        }
        mask.fill(ellipse(hc.x, hc.y + 0.55 * s, 0.40 * s, 0.34 * s), with: .color(cream))
        // The blaze: a little flame on his brow.
        let blaze = FlameBuddyOuterShape(wobble: 0).path(in: CGRect(x: hc.x - 0.16 * s, y: hc.y - 0.88 * s, width: 0.32 * s, height: 0.44 * s))
        ctx.fill(blaze, with: lin([.white, hx(0xFFE047)], pt(0, hc.y - 0.9 * s), pt(0, hc.y - 0.45 * s)))
        let fr = 0.74 * s, fy = hc.y + 0.02 * s
        bigFace(ctx, hc.x, fy, fr, eye: hx(0x2A0C04), glance: -0.12, cheeks: hx(0xFF5C7A))
        ctx.fill(ellipse(hc.x, fy + fr * 0.40 - 0.10 * s, 0.11 * s, 0.075 * s), with: .color(hx(0x2A0C04)))
    }

    /// Comet Pup (`comet_pup`, ten buddy races won): a round, sitting starlight puppy —
    /// big head, floppy indigo ears, a star-tag collar — whose TAIL is a
    /// comet: a tapered streak of light sweeping up behind him into a
    /// blazing star-ball. The silhouette (head + ears + streak) reads at 60pt.
    static func cometPup(_ ctx: GraphicsContext, gy: CGFloat, u: CGFloat) {
        let r = 0.1 * u
        let rw = max(1, 0.009 * u)
        let fur = [Color.white, hx(0xE6EDFF), hx(0xB4C3F2)]
        let line = hx(0x7C8FD6)
        // The comet: from his rump up to a glowing nucleus, widening as it goes.
        let nucleus = pt(2.05 * r, gy - 2.85 * r)
        var streak = Path()
        streak.move(to: pt(0.55 * r, gy - 0.55 * r))
        streak.addQuadCurve(to: pt(nucleus.x - 0.42 * r, nucleus.y + 0.05 * r), control: pt(1.05 * r, gy - 2.05 * r))
        streak.addQuadCurve(to: pt(nucleus.x + 0.36 * r, nucleus.y + 0.30 * r), control: pt(nucleus.x - 0.10 * r, nucleus.y + 0.60 * r))
        streak.addQuadCurve(to: pt(0.80 * r, gy - 0.45 * r), control: pt(1.95 * r, gy - 1.10 * r))
        streak.closeSubpath()
        var sg = ctx; sg.addFilter(.blur(radius: r * 0.28))
        sg.fill(streak, with: .color(hx(0x7FE0FF, 0.75)))
        ctx.fill(streak, with: lin([hx(0x8E7BFF, 0.35), hx(0x7FE0FF), .white], pt(0.6 * r, gy - 0.5 * r), nucleus))
        var core = Path()
        core.move(to: pt(0.72 * r, gy - 0.62 * r))
        core.addQuadCurve(to: pt(nucleus.x - 0.1 * r, nucleus.y + 0.2 * r), control: pt(1.35 * r, gy - 1.75 * r))
        ctx.stroke(core, with: lin([.white.opacity(0.2), .white], pt(0.7 * r, gy - 0.6 * r), nucleus), style: StrokeStyle(lineWidth: r * 0.10, lineCap: .round))
        var ng = ctx; ng.addFilter(.blur(radius: r * 0.3))
        ng.fill(circle(nucleus.x, nucleus.y, r * 0.62), with: .color(hx(0xFFF3A0, 0.85)))
        ctx.fill(circle(nucleus.x, nucleus.y, r * 0.40), with: .radialGradient(Gradient(colors: [.white, hx(0xFFF3B0), hx(0xFFC21F)]),
                                                                              center: pt(nucleus.x - r * 0.1, nucleus.y - r * 0.1), startRadius: 0, endRadius: r * 0.42))
        ctx.fill(star(nucleus.x, nucleus.y, r * 0.66, inner: 0.16, points: 4), with: .color(.white.opacity(0.9)))
        for (tx, ty, sr) in [(1.25, -1.55, 0.16), (1.72, -2.15, 0.12), (0.95, -2.45, 0.10)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.fill(star(tx * r, gy + ty * r, sr * r * 1.4, inner: 0.25, points: 4), with: .color(.white))
        }
        // Sitting body.
        let bc = pt(0.20 * r, gy - 0.78 * r)
        let body = ellipse(bc.x, bc.y, 0.82 * r, 0.78 * r)
        critterBody(ctx, body, fur, CGRect(x: bc.x - 0.82 * r, y: bc.y - 0.78 * r, width: 1.64 * r, height: 1.56 * r), u: u, rim: line)
        for dx in [-0.40, 0.18] as [CGFloat] {
            let paw = rrect(dx * r - 0.22 * r, gy - 0.36 * r, 0.44 * r, 0.36 * r, 0.18 * r)
            ctx.fill(paw, with: .color(.white)); ctx.stroke(paw, with: .color(line), lineWidth: rw)
        }
        // Head.
        let hc = pt(-0.18 * r, gy - 2.02 * r)
        let head = ellipse(hc.x, hc.y, 1.0 * r, 0.88 * r)
        critterBody(ctx, head, fur, CGRect(x: hc.x - r, y: hc.y - 0.88 * r, width: 2 * r, height: 1.76 * r), u: u, rim: line)
        // Floppy ears hung over the sides of his head.
        for sx in [-1.0, 1.0] as [CGFloat] {
            let e = placed(ctx, hc.x + sx * 0.86 * r, hc.y - 0.30 * r, -Double(sx) * 16)
            let ear = ellipse(0, 0.30 * r, 0.30 * r, 0.56 * r)
            e.fill(ear, with: lin([hx(0x7F88F0), hx(0x4A4FC0)], pt(0, -0.2 * r), pt(0, 0.9 * r)))
            e.stroke(ear, with: .color(hx(0x2E3190)), lineWidth: rw)
        }
        // A star-shaped patch on his brow.
        ctx.fill(star(hc.x + 0.34 * r, hc.y - 0.50 * r, 0.20 * r, inner: 0.5), with: .color(hx(0xFFD24A)))
        // Muzzle, face, nose.
        ctx.fill(ellipse(hc.x - 0.02 * r, hc.y + 0.42 * r, 0.46 * r, 0.32 * r), with: .color(.white))
        let fr = 0.72 * r, fy = hc.y + 0.04 * r
        bigFace(ctx, hc.x, fy, fr, eye: hx(0x16204A), glance: -0.10, cheeks: hx(0xFF8FB0))
        ctx.fill(ellipse(hc.x, fy + fr * 0.40 - 0.10 * r, 0.13 * r, 0.09 * r), with: .color(hx(0x16204A)))
        // Collar + star tag.
        var collar = Path(); collar.move(to: pt(hc.x - 0.62 * r, hc.y + 0.78 * r)); collar.addQuadCurve(to: pt(hc.x + 0.66 * r, hc.y + 0.76 * r), control: pt(hc.x, hc.y + 1.02 * r))
        ctx.stroke(collar, with: .color(hx(0xE8384F)), style: StrokeStyle(lineWidth: r * 0.17, lineCap: .round))
        let tag = star(hc.x + 0.02 * r, hc.y + 1.06 * r, 0.20 * r, inner: 0.5)
        ctx.fill(tag, with: .color(hx(0xFFCF40))); ctx.stroke(tag, with: .color(hx(0xB57F0C)), lineWidth: rw * 0.8)
    }

    /// Friendly Ghost: a round little spook with a wispy tail curling off to
    /// one side (not a sheet with a hem), one stubby arm up in a wave, a big
    /// happy face and a soft minty glow.
    static func friendlyGhost(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, u: CGFloat) {
        let r = 0.14 * u
        let rw = max(1, 0.009 * u)
        var s = Path()
        s.move(to: pt(x - r, y + 0.05 * r))
        s.addArc(center: pt(x, y), radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        s.addQuadCurve(to: pt(x + 0.80 * r, y + 0.95 * r), control: pt(x + 1.02 * r, y + 0.62 * r))
        // The wisp: out and curling up to the right.
        s.addQuadCurve(to: pt(x + 1.42 * r, y + 1.02 * r), control: pt(x + 1.05 * r, y + 1.30 * r))
        s.addQuadCurve(to: pt(x + 0.40 * r, y + 1.22 * r), control: pt(x + 1.10 * r, y + 1.45 * r))
        // Two soft scallops back to the left.
        s.addQuadCurve(to: pt(x - 0.22 * r, y + 1.02 * r), control: pt(x + 0.10 * r, y + 1.02 * r))
        s.addQuadCurve(to: pt(x - 0.80 * r, y + 1.02 * r), control: pt(x - 0.52 * r, y + 1.28 * r))
        s.addQuadCurve(to: pt(x - r, y + 0.05 * r), control: pt(x - 1.02 * r, y + 0.70 * r))
        s.closeSubpath()
        // Waving arm (viewer's left, toward him) and a resting one.
        let wave = placed(ctx, x - 0.95 * r, y + 0.10 * r, -38)
        let wa = ellipse(0, -0.20 * r, 0.17 * r, 0.30 * r)
        wave.fill(wa, with: .color(hx(0xEEF4FA))); wave.stroke(wa, with: .color(hx(0x9FE8D0, 0.9)), lineWidth: rw)
        critterBody(ctx, s, [.white, hx(0xEAF6F2), hx(0xC6E4DC)], CGRect(x: x - r, y: y - r, width: 2 * r, height: 2.2 * r), u: u,
                    rim: hx(0x9FE8D0, 0.9), glow: hx(0xBFFFEA))
        let rest = placed(ctx, x + 0.92 * r, y + 0.42 * r, 28)
        let ra = ellipse(0, 0, 0.14 * r, 0.24 * r)
        rest.fill(ra, with: .color(hx(0xEAF4F0))); rest.stroke(ra, with: .color(hx(0x9FE8D0, 0.9)), lineWidth: rw)
        bigFace(ctx, x - 0.04 * r, y + 0.02 * r, 0.62 * r, eye: hx(0x1A0E24), glance: -0.1, cheeks: hx(0xFF8FB0))
    }

    /// Lantern: a round paper lantern with a candle flame of its own
    /// peeking out of the top — a little cousin of his fire — lit from
    /// inside, gold caps, a swinging tassel and a big happy face.
    static func lantern(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, u: CGFloat) {
        let r = 0.13 * u
        let rw = max(1, 0.009 * u)
        var gl = ctx; gl.addFilter(.blur(radius: r * 0.6))
        gl.fill(circle(x, y, r * 1.25), with: .color(hx(0xFF8A2E, 0.6)))
        // Its own little flame, on top.
        let flame = FlameBuddyOuterShape(wobble: 0.02).path(in: CGRect(x: x - r * 0.24, y: y - r * 1.42, width: r * 0.48, height: r * 0.62))
        var fg = ctx; fg.addFilter(.blur(radius: r * 0.15)); fg.fill(flame, with: .color(hx(0xFFB020, 0.8)))
        ctx.fill(flame, with: lin([.white, hx(0xFFE047), hx(0xFF8014)], pt(x, y - r * 1.42), pt(x, y - r * 0.8)))
        ctx.stroke(flame, with: .color(.white.opacity(0.5)), lineWidth: rw * 0.8)
        let body = ellipse(x, y, r, r * 0.84)
        ctx.fill(body, with: .radialGradient(Gradient(colors: [hx(0xFFF6D0), hx(0xFFB347), hx(0xE8452A), hx(0xB32418)]),
                                            center: pt(x - r * 0.05, y), startRadius: 0, endRadius: r * 1.05))
        var ribs = ctx; ribs.clip(to: body)
        for f in [-0.66, -0.3, 0.3, 0.66] as [CGFloat] {
            var rb = Path()
            rb.move(to: pt(x + f * r * 0.7, y - r))
            rb.addQuadCurve(to: pt(x + f * r * 0.7, y + r), control: pt(x + f * r * 1.35, y))
            ribs.stroke(rb, with: .color(hx(0xA82010, 0.35)), lineWidth: rw)
        }
        sheen(ctx, body, CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2), 0.32)
        ctx.stroke(body, with: .color(hx(0x7A1408)), lineWidth: rw * 1.2)
        for dy in [-0.84, 0.84] as [CGFloat] {
            let cap = rrect(x - r * 0.48, y + dy * r - r * 0.12, r * 0.96, r * 0.24, r * 0.08)
            ctx.fill(cap, with: lin([hx(0xFFE27A), hx(0xE0A512), hx(0xA86F00)], pt(0, y + dy * r - r * 0.12), pt(0, y + dy * r + r * 0.12)))
            ctx.stroke(cap, with: .color(hx(0x6A4300)), lineWidth: rw)
        }
        bigFace(ctx, x, y - r * 0.08, r * 0.66, eye: hx(0x4A0E06), glance: -0.1, cheeks: hx(0xFF3B6B))
        // Tassel.
        var cord = Path(); cord.move(to: pt(x, y + r * 0.96)); cord.addLine(to: pt(x, y + r * 1.14))
        ctx.stroke(cord, with: .color(hx(0xE0A512)), style: StrokeStyle(lineWidth: rw * 1.3, lineCap: .round))
        let tassel = poly([pt(x - r * 0.10, y + r * 1.12), pt(x + r * 0.10, y + r * 1.12), pt(x + r * 0.15, y + r * 1.48), pt(x - r * 0.15, y + r * 1.48)])
        ctx.fill(tassel, with: lin([hx(0xFF4F5E), hx(0xB3152F)], pt(0, y + r * 1.12), pt(0, y + r * 1.48)))
        ctx.stroke(tassel, with: .color(hx(0x7A1408)), lineWidth: rw * 0.8)
        ctx.fill(circle(x, y + r * 1.12, r * 0.08), with: .color(hx(0xFFCF40)))
    }

    /// Draws one companion about (0, ground) — the caller translates to
    /// `companionX`, so the bob can move the whole creature as one.
    static func drawCompanion(_ item: FlameyItem, in ctx: inout GraphicsContext, a: Anchors, u: CGFloat, palette: FlameyPalette?,
                              pose: FlameArmPose = .rest) {
        let gy = a.ground
        let fy = gy - floatHeight * u
        switch item {
        case .spark:
            spark(ctx, 0, fy, 0.15 * u, hx(0xFFC21F), u: u)
        case .sparkTrio:
            // A little huddle, not a scatter: gold in front, the other two
            // peeking over its shoulders.
            spark(ctx, -0.085 * u, fy - 0.10 * u, 0.095 * u, hx(0x5CC8FF), u: u, glance: -0.1)
            spark(ctx, 0.095 * u, fy - 0.06 * u, 0.095 * u, hx(0xFF7A9A), u: u, glance: -0.1)
            spark(ctx, 0, fy + 0.05 * u, 0.12 * u, hx(0xFFC21F), u: u)
        case .firefly:
            emberDragon(ctx, 0, fy + 0.02 * u, u: u)
        case .lantern:
            lantern(ctx, 0, fy + 0.02 * u, u: u)
        case .friendlyGhost:
            friendlyGhost(ctx, 0, fy - 0.03 * u, u: u)
        case .flameyJr:
            flameyJr(ctx, gy: gy, u: u, palette: palette, pose: pose)
        case .phoenixChick:
            blazeFox(ctx, gy: gy, u: u)
        case .cometPup:
            cometPup(ctx, gy: gy, u: u)
        default: break
        }
    }
}

// MARK: - Standing

extension FlameyLook {
    /// How far his legs raise him (body units): the Fun mascot always
    /// stands on two stubby legs, bare or shod, on EVERY surface.
    var standLift: CGFloat { FlameyArt.legLength }

    /// His arms' hold for what's in his hand on a surface of this reach.
    func armHold(reach: CGFloat) -> FlameArmHold? { FlameyArt.heldArmTargets(self[.held], reach: reach) }

    /// Arms hide under a costume that covers him whole.
    var showsArms: Bool { !wears(.ghostSheet) }

    /// The envelope a full (non-tight) surface fits him to, in body units
    /// from his feet: legs + body + a modest hat. Everything taller shrinks
    /// about his feet to this height (`FlameBuddyView.standFit`).
    static let stageEnvelope: CGFloat = FlameyArt.legLength + 0.98 + 0.15

    /// How much a full surface scales him so the tallest looks keep to
    /// `stageEnvelope` — 1 for anything up to a beanie; a crown on rocket
    /// boots draws ~17% smaller rather than out of its stage.
    var stageFit: CGFloat {
        min(1, Self.stageEnvelope / (bodyLift + 0.98 + FlameyArt.crest(of: self)))
    }

    /// What a stage must leave free ABOVE his `size` square for the tallest
    /// fitted look plus a two-line bubble, in points.
    static func stageRoomAbove(_ size: CGFloat) -> CGFloat {
        let top = (0.5 - stageEnvelope - FlameyArt.bubbleGap) * size - FlameyArt.bubbleReserve(size)
        return -0.5 * size - top
    }

    /// Everything that raises his body off the floor — legs, then any hover.
    /// The figure's `lift` and every anchor use this, so the body, the face
    /// props and the outfit move together.
    var bodyLift: CGFloat { standLift + hoverLift }
}
