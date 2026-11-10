import SwiftUI

// FLAMEY'S WARDROBE — WHERE THINGS GO. BYTE-IDENTICAL in
// app/Mile A Day/Views/Components/ and app/MileADayWidgets/ (see
// FlameyWardrobe.swift). SwiftUI + Foundation only.
//
// The drawings themselves are skins (FlameySkin.swift, backend/flamey-skins),
// recorded from the Swift art this file used to hold. What stays here is the
// geometry every surface shares: the figure's anchors (origin at the centre
// of his `size` square, `u` = size × body scale, so gear stays on him as he
// burns down), the tight-surface rules, headroom, and where held props and
// companions go. Per-item numbers come from each skin's `rules`.

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

    /// How far above his TIP a head piece or costume reaches, in body units
    /// (the skin's `rules.head_rise`, measured off the drawings). A new hat
    /// that rises needs it set or the hero clips it.
    static func headRise(_ item: FlameyItem) -> CGFloat {
        CGFloat(item.skin?.rule("head_rise") ?? 0)
    }

    /// The crest of the look: how far its highest drawn point sits above
    /// his tip (body units). A bare tip still flickers a little above 0.98.
    static func crest(of look: FlameyLook) -> CGFloat {
        let crown = monthCrown(of: look).map(monthCrownRise) ?? 0
        return max(0.03, crown, [look[.head], look[.costume]].compactMap { $0 }.map(headRise).max() ?? 0)
    }

    // MARK: - Colour crowns

    /// A colour that tops his tip (October's pumpkin stem, December's
    /// tree-top star): its skin has a `crown` layer, shown only while none of
    /// `rules.crown_unless` (head, costume) is worn — any hat or costume
    /// wins, so every head piece still sits exactly where it always does.
    static func monthCrown(of look: FlameyLook) -> FlameyItem? {
        guard let color = look[.color], let skin = color.skin, skin.layer("crown") != nil else { return nil }
        for slot in skin.ruleStrings("crown_unless") {
            if let s = FlameySlot(rawValue: slot), look[s] != nil { return nil }
        }
        return color
    }

    static func monthCrownRise(_ item: FlameyItem) -> CGFloat {
        CGFloat(item.skin?.rule("crown_rise") ?? 0.07)
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

    /// How far a back piece's width is squeezed on a tight surface (baked
    /// into each back skin's per-reach recordings; kept for layout).
    static let capeTuck: CGFloat = 0.53
    /// A cape hangs close behind him, so a tight surface only narrows its
    /// flare — it still shows on both sides.
    static let capeTightScale: CGFloat = 0.82

    /// A back piece that hangs like a cape (`rules.is_cape`): a trail under
    /// it streams low and a companion stands a step further out.
    static func isCape(_ item: FlameyItem) -> Bool {
        item.skin?.ruleBool("is_cape") ?? false
    }

    /// How far a trail's length is squeezed on a tight surface.
    static let trailTuck: CGFloat = 0.56

    // MARK: - Held (in front, at his side — the viewer's left)
    //
    // Every number is the skin's `rules.held` (body units, +x AWAY from his
    // body, y from his base, negative up), recorded from the props' code.

    private static func held(_ item: FlameyItem) -> [String: Any] {
        item.skin?.rules["held"] as? [String: Any] ?? [:]
    }

    private static func heldNumber(_ item: FlameyItem, _ key: String, _ fallback: Double) -> CGFloat {
        CGFloat((held(item)[key] as? NSNumber)?.doubleValue ?? fallback)
    }

    private static func heldPointValue(_ item: FlameyItem, _ key: String) -> CGPoint? {
        guard let v = held(item)[key] as? [Double], v.count == 2 else { return nil }
        return pt(v[0], v[1])
    }

    /// A held prop's scale on a tight surface.
    static func tightHeldScale(_ item: FlameyItem) -> CGFloat { heldNumber(item, "tight_scale", 0.72) }

    /// Props he holds UP (the rest are held out low, at chest height).
    static func heldUp(_ item: FlameyItem) -> Bool { held(item)["up"] as? Bool ?? false }

    /// Where his hand is for a prop. The prop is drawn round this point and
    /// his real arm (`FlameBuddyArms`) goes to the same point.
    static func heldHand(_ item: FlameyItem) -> CGPoint { heldPointValue(item, "hand") ?? pt(0.41, -0.22) }

    /// Where the hand goes on a TIGHT surface: nearer his side.
    static func tightHeldHand(_ item: FlameyItem) -> CGPoint {
        heldPointValue(item, "tight_hand") ?? (heldUp(item) ? pt(0.34, -0.39) : pt(0.32, -0.15))
    }

    /// His arms' targets for what he's holding (figure space: x negative =
    /// the viewer's left, his holding side), for `FlameBuddyArms(hold:)` —
    /// the skin's `rules.arm_hold`, recorded per reach; tight and wide
    /// surfaces differ, nothing else does.
    /// `carryMitts: false` is the hold as builds before mitts drew it (the
    /// prop's `held-body` at its grip) — the Closet tile, which has no arms.
    static func heldArmTargets(_ item: FlameyItem?, reach: CGFloat, carryMitts: Bool = true) -> FlameArmHold? {
        guard let item else { return nil }
        let mitts = carryMitts && wornOnHands(item)
        // Gloves: the arms keep whatever pose he's in and carry the mitts.
        if mitts, item.skin?.ruleBool("mitt_follows_pose") == true {
            return FlameArmHold(mitt: item, mittReach: reach)
        }
        guard var hold = recordedArmTargets(item, reach: reach) else {
            return mitts ? FlameArmHold(mitt: item, mittReach: reach) : nil
        }
        if mitts {
            hold.mitt = item
            hold.mittReach = reach
        }
        return hold
    }

    private static func recordedArmTargets(_ item: FlameyItem, reach: CGFloat) -> FlameArmHold? {
        guard let holds = item.skin?.rules["arm_hold"] as? [String: Any] else { return nil }
        let want = isTight(reach) ? reach : max(reach, tightReach)
        let key = holds.keys.min { a, b in
            func score(_ k: String) -> Double {
                let v = Double(k) ?? 0
                // Same side of the tight line first, then the nearest reach.
                return (isTight(CGFloat(v)) == isTight(reach) ? 0 : 10) + abs(v - Double(want))
            }
            return score(a) < score(b)
        }
        guard let key, let h = holds[key] as? [String: Any] else { return nil }
        func p(_ k: String) -> CGPoint? {
            guard let v = h[k] as? [Double], v.count == 2 else { return nil }
            return pt(v[0], v[1])
        }
        var hold = FlameArmHold(left: p("left"), right: p("right"))
        hold.leftHand = h["left_hand"] as? Bool ?? true
        hold.rightHand = h["right_hand"] as? Bool ?? true
        return hold
    }

    /// A held item worn ON his hands: its skin records a `mitt` layer, which
    /// the arms draw at each wrist (`FlameArmLimb`); its `held-body` is the
    /// same pair at rest, for the Closet tile and older builds.
    static func wornOnHands(_ item: FlameyItem) -> Bool { item.skin?.layerKey("mitt") != nil }

    /// A look that throws its fists up now and then once he is done for the
    /// day (`rules.raises_when_lit`) — the boxing gloves' champ salute.
    static func raisesWhenLit(_ look: FlameyLook?) -> Bool {
        guard let look, look.showsArms else { return false }
        return look.items.contains { $0.skin?.ruleBool("raises_when_lit") == true }
    }

    /// How a held prop moves when live (transform-only, `repeatForever`):
    /// the whole prop swings about his fist by `wobble` degrees every
    /// `period` seconds, and its accent does `accent`.
    struct HeldMotion {
        enum Accent: String { case none, flutter, sweep, pulse, burst }
        let wobble: Double
        let period: Double
        let accent: Accent
    }

    static func heldMotion(_ item: FlameyItem) -> HeldMotion {
        let h = held(item)
        return HeldMotion(wobble: (h["wobble"] as? NSNumber)?.doubleValue ?? 0,
                          period: (h["period"] as? NSNumber)?.doubleValue ?? 1,
                          accent: HeldMotion.Accent(rawValue: h["accent"] as? String ?? "none") ?? .none)
    }

    /// Where a held prop's ACCENT pivots, in the prop's own space.
    static func heldAccentPivot(_ item: FlameyItem) -> CGPoint? { heldPointValue(item, "accent_pivot") }

    /// Where the WHOLE prop pivots (his fist; the pom-poms shake about the
    /// point between his two hands).
    static func heldGrip(_ item: FlameyItem) -> CGPoint { heldPointValue(item, "grip") ?? heldHand(item) }

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
        guard let v = held(item)["tile_framing"] as? [Double], v.count == 3 else { return (0.9, -0.40, 0.06) }
        return (v[0], v[1], v[2])
    }

    // MARK: - Companions (standing on the viewer's RIGHT)

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

    /// A companion that floats (by his shoulder) rather than walks.
    static func floats(_ item: FlameyItem) -> Bool { item.skin?.ruleBool("floats") ?? false }
}

// MARK: - Standing

extension FlameyLook {
    /// How far his legs raise him (body units): the Fun mascot always
    /// stands on two stubby legs, bare or shod, on EVERY surface.
    var standLift: CGFloat { FlameyArt.legLength }

    /// His arms' hold for what's in his hand on a surface of this reach.
    func armHold(reach: CGFloat, carryMitts: Bool = true) -> FlameArmHold? {
        FlameyArt.heldArmTargets(self[.held], reach: reach, carryMitts: carryMitts)
    }

    /// Arms hide under a costume that covers him whole (`rules.shows_arms`).
    var showsArms: Bool { !items.contains { $0.skin?.ruleBool("shows_arms") == false } }

    /// His face hides the same way (`rules.shows_face`: the ghost sheet).
    var showsFace: Bool { !items.contains { $0.skin?.ruleBool("shows_face") == false } }

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
