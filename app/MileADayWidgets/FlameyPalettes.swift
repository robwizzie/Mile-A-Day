import SwiftUI

// FLAMEY'S COLOURS — what his flame is made of. BYTE-IDENTICAL in
// app/Mile A Day/Views/Components/ and app/MileADayWidgets/ (see
// FlameyWardrobe.swift). SwiftUI + Foundation only.
//
// Every colour keeps a LIGHT inner core and a dark eye, so the face reads on
// all of them. Solids early, gradients mid-ladder, legendary effects at the
// top. Neighbours on the ladder must read as different colours at 44pt:
// Ember is RED-orange (Classic owns orange), Lime is yellow-green (Mint is
// blue-green), Lavender is pale lilac (Violet is saturated), Ocean is an
// aqua-to-navy gradient with waves (Sapphire is one royal blue), Sunflower is
// flat petal-yellow (Gold is metallic, with a sheen and a dark ochre base).

/// A colour's effect. `sheen` … `hotCore` live INSIDE his silhouette and are
/// part of the colour everywhere; `halo` and `embers` are OUTSIDE him and are
/// the colour's glow — subject to `FlameyGlow` precedence.
enum FlameyPaletteEffect: Hashable, CaseIterable {
    case sheen, stars, denseStars, lava, ribbons, candy, waves, nebula, hotCore, prismCycle
    case halo, embers
    // Monthly Flames — patterns inside his outline, so every outfit still fits.
    case snowflakes, hearts, clovers, raindrops, rainbow, flowers, sunRays, flagStripes, melon,
         leaves, pumpkinRibs, knit, stringLights

    /// By the name a skin file uses (the case name: "stars", "denseStars").
    init?(name: String) {
        guard let e = Self.allCases.first(where: { String(describing: $0) == name }) else { return nil }
        self = e
    }
}

struct FlameyPalette: Hashable {
    var outer: [Color]
    var inner: [Color]
    var glow: Color
    var core: Color = FlameyPalette.hex(0xFFF3B0)
    var eye: Color? = nil
    var rim: Color? = nil
    var effects: Set<FlameyPaletteEffect> = []
    var angular: Bool = false
    var start: UnitPoint = .top
    var end: UnitPoint = .bottom
    var bodyOpacity: Double = 1
    var innerOpacity: Double? = nil

    var hasHalo: Bool { effects.contains(.halo) || effects.contains(.embers) }

    /// The swatch a picker draws: the outer stops.
    var swatch: [Color] { outer }

    /// A mid-tone for things that grow out of him (arms, Flamey Jr.).
    var bodyTone: Color { outer[min(1, outer.count - 1)] }

    static func hex(_ v: UInt32, _ o: Double = 1) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255).opacity(o)
    }

    /// Classic returns nil: the figure's own lifecycle palette (it burns
    /// down through the day), byte-identical to before the wardrobe. Every
    /// other colour is its skin's `palette` (backend/flamey-skins).
    static func palette(for item: FlameyItem) -> FlameyPalette? {
        item.skin?.flameyPalette
    }

}

extension FlameyPalette {
    /// A palette from a skin file's `palette` object (field names as here,
    /// colours "#RRGGBBAA", points [x, y], effects by name).
    init?(json: [String: Any]) {
        func color(_ k: String) -> Color? { (json[k] as? String).map(FlameySkinLayer.color) }
        func colors(_ k: String) -> [Color] { (json[k] as? [String] ?? []).map(FlameySkinLayer.color) }
        func point(_ k: String) -> UnitPoint? {
            guard let v = json[k] as? [Double], v.count == 2 else { return nil }
            return UnitPoint(x: v[0], y: v[1])
        }
        let outer = colors("outer"), inner = colors("inner")
        guard !outer.isEmpty, !inner.isEmpty, let glow = color("glow") else { return nil }
        self.init(outer: outer, inner: inner, glow: glow)
        if let c = color("core") { core = c }
        eye = color("eye")
        rim = color("rim")
        effects = Set((json["effects"] as? [String] ?? []).compactMap(FlameyPaletteEffect.init(name:)))
        angular = json["angular"] as? Bool ?? false
        if let p = point("start") { start = p }
        if let p = point("end") { end = p }
        bodyOpacity = (json["bodyOpacity"] as? NSNumber)?.doubleValue ?? 1
        innerOpacity = (json["innerOpacity"] as? NSNumber)?.doubleValue
    }
}

// MARK: - Body effects (inside his silhouette)

/// The colour's effects that live INSIDE him, clipped to his outline and
/// overlaid on the outer fill by the figure. Drawn once (Canvas); the only
/// motion is Prism's colour cycle — a rotation of a gradient layer under the
/// same clip, `repeatForever`, started once, off under Reduce Motion and in
/// an `ImageRenderer` still (which drives no lifecycle, so it never starts).
struct FlameyPaletteBodyFX: View {
    let palette: FlameyPalette
    let size: CGFloat
    let wobble: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    var body: some View {
        ZStack {
            if palette.effects.contains(.prismCycle) {
                AngularGradient(colors: palette.outer + [palette.outer[0]], center: UnitPoint(x: 0.5, y: 0.62))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .scaleEffect(1.6)
                    .opacity(0.55)
                    .mask(FlameBuddyOuterShape(wobble: wobble))
                    .onAppear {
                        guard !reduceMotion, !spin else { return }
                        DispatchQueue.main.async {
                            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { spin = true }
                        }
                    }
            }
            Canvas { ctx, sz in
                Self.draw(palette, in: &ctx, size: sz, unit: size, wobble: wobble)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Every effect this layer paints (the rest draw elsewhere: halo, embers,
    /// hot core, Prism's spin).
    static let drawnHere: Set<FlameyPaletteEffect> = Set<FlameyPaletteEffect>(
        [.sheen, .stars, .denseStars, .lava, .ribbons, .candy, .waves, .nebula]
    ).union(FlameyMonthlyFX.effects)

    static func draw(_ palette: FlameyPalette, in ctx: inout GraphicsContext, size sz: CGSize, unit size: CGFloat,
                     wobble: CGFloat) {
        let fx = palette.effects
        guard !fx.isDisjoint(with: Self.drawnHere) else { return }
        let w = sz.width, h = sz.height
        let shape = FlameBuddyOuterShape(wobble: wobble).path(in: CGRect(origin: .zero, size: sz))
        ctx.clip(to: shape)
        let hx = FlameyPalette.hex
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        FlameyMonthlyFX.draw(fx, in: &ctx, w: w, h: h, unit: size)
        if fx.contains(.nebula) {
            var g = ctx
            g.addFilter(.blur(radius: size * 0.05))
            g.fill(Path(ellipseIn: CGRect(x: 0.05 * w, y: 0.45 * h, width: 0.55 * w, height: 0.30 * h)), with: .color(hx(0xB5389A, 0.55)))
            g.fill(Path(ellipseIn: CGRect(x: 0.45 * w, y: 0.25 * h, width: 0.45 * w, height: 0.30 * h)), with: .color(hx(0x3A6BFF, 0.5)))
        }
        if fx.contains(.waves) {
            for (i, yy) in [0.52, 0.66, 0.80].enumerated() {
                var path = Path()
                path.move(to: p(-0.05, CGFloat(yy)))
                for j in 0...24 {
                    let t = CGFloat(j) / 24
                    path.addLine(to: p(-0.05 + t * 1.1, CGFloat(yy) + 0.025 * sin(t * 14 + CGFloat(i) * 1.3)))
                }
                ctx.stroke(path, with: .color(.white.opacity(0.42 - Double(i) * 0.08)),
                           style: StrokeStyle(lineWidth: size * 0.022, lineCap: .round))
            }
        }
        if fx.contains(.lava) {
            let blobs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0.22, 0.60, 0.16, 0.11), (0.70, 0.40, 0.12, 0.10),
                                                                  (0.46, 0.22, 0.08, 0.07), (0.78, 0.74, 0.10, 0.07),
                                                                  (0.30, 0.86, 0.12, 0.06)]
            for b in blobs {
                let r = CGRect(x: (b.0 - b.2) * w, y: (b.1 - b.3) * h, width: b.2 * 2 * w, height: b.3 * 2 * h)
                ctx.fill(Path(ellipseIn: r), with: .linearGradient(Gradient(colors: [hx(0xFFE36B, 1), hx(0xFFA23A, 1)]),
                                                                    startPoint: CGPoint(x: r.minX, y: r.minY),
                                                                    endPoint: CGPoint(x: r.maxX, y: r.maxY)))
                ctx.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * 0.2, y: r.minY + r.height * 0.15,
                                                width: r.width * 0.3, height: r.height * 0.25)),
                         with: .color(.white.opacity(0.45)))
            }
        }
        if fx.contains(.ribbons) {
            let cols: [(Color, CGFloat, CGFloat)] = [(hx(0x3DFFB0, 0.85), 0.28, 0.0), (hx(0xFF6FD8, 0.6), 0.44, 1.3),
                                                     (hx(0x55C8FF, 0.7), 0.60, 2.2)]
            for (c, yy, ph) in cols {
                var path = Path()
                path.move(to: p(-0.1, yy))
                for i in 0...24 {
                    let t = CGFloat(i) / 24
                    path.addLine(to: p(-0.1 + t * 1.2, yy + 0.05 * sin(t * 9 + ph) - t * 0.08))
                }
                var g = ctx
                g.addFilter(.blur(radius: size * 0.018))
                g.stroke(path, with: .color(c), style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                ctx.stroke(path, with: .color(c.opacity(0.9)), style: StrokeStyle(lineWidth: size * 0.012, lineCap: .round))
            }
        }
        if fx.contains(.candy) {
            var g = ctx
            g.rotate(by: .degrees(-30))
            for i in -6...10 {
                let x = CGFloat(i) * 0.16 * w
                g.fill(Path(CGRect(x: x, y: -h, width: 0.05 * w, height: h * 3)), with: .color(.white.opacity(0.35)))
            }
        }
        if fx.contains(.stars) || fx.contains(.denseStars) {
            let dense = fx.contains(.denseStars)
            var pts: [(CGFloat, CGFloat, CGFloat)] = [
                (0.50, 0.14, 1.0), (0.40, 0.30, 0.6), (0.62, 0.34, 0.8), (0.30, 0.50, 0.9), (0.74, 0.55, 0.6),
                (0.18, 0.68, 0.7), (0.84, 0.70, 0.9), (0.24, 0.84, 0.5), (0.70, 0.88, 0.7), (0.54, 0.46, 0.5),
                (0.12, 0.76, 0.5), (0.88, 0.80, 0.5)]
            if dense {
                pts += [(0.45, 0.22, 0.4), (0.58, 0.24, 0.5), (0.35, 0.40, 0.4), (0.68, 0.44, 0.45),
                        (0.22, 0.58, 0.4), (0.80, 0.62, 0.4), (0.15, 0.62, 0.5), (0.35, 0.92, 0.45),
                        (0.60, 0.95, 0.4), (0.88, 0.62, 0.35), (0.48, 0.60, 0.3)]
            }
            for (x, y, r) in pts {
                let rr = max(0.5, size * 0.012 * r)
                ctx.fill(Path(ellipseIn: CGRect(x: x * w - rr, y: y * h - rr, width: rr * 2, height: rr * 2)),
                         with: .color(.white.opacity(0.95)))
            }
            for (x, y) in [(0.36, 0.24), (0.70, 0.62), (0.22, 0.76)] as [(CGFloat, CGFloat)] {
                ctx.fill(FlameyArt.star(x * w, y * h, size * 0.035, inner: 0.25), with: .color(.white))
            }
        }
        if fx.contains(.sheen) {
            var g = ctx
            g.rotate(by: .degrees(-24))
            g.fill(Path(CGRect(x: -0.05 * w, y: 0.10 * h, width: 0.16 * w, height: h * 1.4)), with: .color(.white.opacity(0.40)))
            g.fill(Path(CGRect(x: 0.16 * w, y: 0.10 * h, width: 0.05 * w, height: h * 1.4)), with: .color(.white.opacity(0.28)))
        }
    }
}

/// Eternal's white-hot core, over the inner flame.
struct FlameyPaletteInnerFX: View {
    let palette: FlameyPalette
    let size: CGFloat

    var body: some View {
        if palette.effects.contains(.hotCore) {
            FlameBuddyInnerShape(wobble: 0)
                .fill(RadialGradient(colors: [.white, .white.opacity(0)], center: UnitPoint(x: 0.5, y: 0.7),
                                     startRadius: 0, endRadius: size * 0.3))
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Monthly Flames (patterns inside his outline)

/// The Monthly Flames' patterns. Every one is painted INSIDE his silhouette
/// (the caller has already clipped to it) in the body's own unit square, so
/// his outline, face and anchors never move — every hat, cape, shoe and prop
/// fits a Monthly Flame exactly as it fits Classic. Static art, no motion.
enum FlameyMonthlyFX {
    static let effects: Set<FlameyPaletteEffect> = [
        .snowflakes, .hearts, .clovers, .raindrops, .rainbow, .flowers, .sunRays, .flagStripes, .melon,
        .leaves, .pumpkinRibs, .knit, .stringLights,
    ]

    static func draw(_ fx: Set<FlameyPaletteEffect>, in ctx: inout GraphicsContext, w: CGFloat, h: CGFloat,
                     unit size: CGFloat) {
        guard !fx.isDisjoint(with: effects) else { return }
        func hx(_ v: UInt32, _ o: Double = 1) -> Color { FlameyPalette.hex(v, o) }
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        let s = size

        if fx.contains(.sunRays) {
            // Soft wedges fanning out from behind his smile.
            let c = p(0.5, 0.66)
            for i in 0..<12 where i % 2 == 0 {
                let a0 = Double(i) * .pi / 6, a1 = a0 + .pi / 6
                var wedge = Path()
                wedge.move(to: c)
                wedge.addLine(to: CGPoint(x: c.x + CGFloat(cos(a0)) * s * 1.2, y: c.y + CGFloat(sin(a0)) * s * 1.2))
                wedge.addLine(to: CGPoint(x: c.x + CGFloat(cos(a1)) * s * 1.2, y: c.y + CGFloat(sin(a1)) * s * 1.2))
                wedge.closeSubpath()
                ctx.fill(wedge, with: .color(.white.opacity(0.16)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.22, y: c.y - s * 0.22, width: s * 0.44, height: s * 0.44)),
                     with: .radialGradient(Gradient(colors: [hx(0xFFFBE0, 0.7), hx(0xFFFBE0, 0)]),
                                           center: c, startRadius: 0, endRadius: s * 0.22))
        }
        if fx.contains(.pumpkinRibs) {
            // A carved pumpkin's ribs: curved seams from his crown to his base,
            // darker in the creases, a soft highlight on each lobe.
            for x in [0.20, 0.35, 0.65, 0.80] as [CGFloat] {
                var rib = Path()
                rib.move(to: p(0.5 + (x - 0.5) * 0.3, 0.06))
                rib.addQuadCurve(to: p(0.5 + (x - 0.5) * 0.8, 1.02), control: p(x + (x - 0.5) * 0.35, 0.58))
                ctx.stroke(rib, with: .color(hx(0x8A3A06, 0.55)), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
            }
            for x in [0.28, 0.72] as [CGFloat] {
                ctx.fill(Path(ellipseIn: CGRect(x: (x - 0.04) * w, y: 0.42 * h, width: 0.06 * w, height: 0.26 * h)),
                         with: .color(hx(0xFFD08A, 0.35)))
            }
        }
        if fx.contains(.melon) {
            // Rind along his base (dark stripes on light), seeds above it.
            let rindTop: CGFloat = 0.86
            ctx.fill(Path(CGRect(x: 0, y: rindTop * h, width: w, height: h)), with: .color(hx(0x2E8B3A)))
            ctx.fill(Path(CGRect(x: 0, y: (rindTop - 0.03) * h, width: w, height: 0.035 * h)), with: .color(hx(0xF2FFE6)))
            for i in 0..<9 {
                let x = CGFloat(i) * 0.13 * w
                ctx.fill(Path(CGRect(x: x, y: rindTop * h, width: 0.05 * w, height: 0.2 * h)), with: .color(hx(0x1A5E24)))
            }
            let seeds: [(CGFloat, CGFloat, Double)] = [(0.30, 0.40, -20), (0.52, 0.30, 10), (0.70, 0.46, 25),
                                                       (0.24, 0.66, -15), (0.46, 0.74, 5), (0.76, 0.70, 20),
                                                       (0.60, 0.56, -10)]
            for (x, y, r) in seeds {
                var g = ctx
                g.translateBy(x: x * w, y: y * h)
                g.rotate(by: .degrees(r))
                g.fill(drop(0, 0, s * 0.028), with: .color(hx(0x2A0E0E)))
                g.fill(Path(ellipseIn: CGRect(x: -s * 0.006, y: -s * 0.012, width: s * 0.008, height: s * 0.012)),
                       with: .color(.white.opacity(0.6)))
            }
        }
        if fx.contains(.flagStripes) {
            // Stripes below, a blue field with white stars up top-left.
            for i in 0..<4 {
                let y = (0.50 + CGFloat(i) * 0.13) * h
                ctx.fill(Path(CGRect(x: 0, y: y, width: w, height: 0.065 * h)), with: .color(.white.opacity(0.85)))
            }
            let field = CGRect(x: 0, y: 0, width: 0.56 * w, height: 0.50 * h)
            ctx.fill(Path(field), with: .color(hx(0x1E3A8A)))
            for (x, y) in [(0.16, 0.30), (0.30, 0.22), (0.44, 0.30), (0.22, 0.42), (0.38, 0.42), (0.30, 0.12)] as [(CGFloat, CGFloat)] {
                ctx.fill(FlameyArt.star(x * w, y * h, s * 0.035, inner: 0.42), with: .color(.white))
            }
        }
        if fx.contains(.knit) {
            // Cable-knit: V stitches all over, one cream band of hearts-and-dots.
            for row in 0..<14 {
                let y = (0.04 + CGFloat(row) * 0.072) * h
                for col in 0..<10 {
                    let x = (CGFloat(col) * 0.11 + (row % 2 == 0 ? 0 : 0.055)) * w
                    var v = Path()
                    v.move(to: CGPoint(x: x, y: y))
                    v.addLine(to: CGPoint(x: x + 0.025 * w, y: y + 0.035 * h))
                    v.addLine(to: CGPoint(x: x + 0.05 * w, y: y))
                    ctx.stroke(v, with: .color(.white.opacity(0.16)), style: StrokeStyle(lineWidth: s * 0.01, lineCap: .round))
                }
            }
            let band = CGRect(x: 0, y: 0.70 * h, width: w, height: 0.11 * h)
            ctx.fill(Path(band), with: .color(hx(0xFFF4E6, 0.92)))
            for i in 0..<8 {
                let x = (0.06 + CGFloat(i) * 0.125) * w
                ctx.fill(i % 2 == 0 ? heart(x, band.midY, s * 0.04) : Path(ellipseIn: CGRect(x: x - s * 0.012, y: band.midY - s * 0.012, width: s * 0.024, height: s * 0.024)),
                         with: .color(hx(0xC0384A)))
            }
        }
        if fx.contains(.rainbow) {
            let c = p(0.5, 1.08)
            let bands: [UInt32] = [0xFF6B6B, 0xFFB347, 0xFFE66B, 0x7FE08A, 0x6BB8FF, 0xB08AFF]
            for (i, col) in bands.enumerated() {
                let r = s * (0.52 - CGFloat(i) * 0.045)
                var arc = Path()
                arc.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                ctx.stroke(arc, with: .color(hx(col, 0.75)), lineWidth: s * 0.045)
            }
        }
        if fx.contains(.snowflakes) {
            let flakes: [(CGFloat, CGFloat, CGFloat)] = [(0.50, 0.16, 0.9), (0.30, 0.36, 0.7), (0.72, 0.40, 0.8),
                                                         (0.22, 0.66, 0.6), (0.80, 0.70, 0.7), (0.52, 0.86, 0.6),
                                                         (0.40, 0.56, 0.4), (0.64, 0.24, 0.45)]
            for (x, y, k) in flakes {
                ctx.stroke(snowflake(x * w, y * h, s * 0.06 * k), with: .color(.white.opacity(0.85)),
                           style: StrokeStyle(lineWidth: max(0.6, s * 0.011 * k), lineCap: .round))
            }
        }
        if fx.contains(.hearts) {
            let spots: [(CGFloat, CGFloat, CGFloat, Double)] = [(0.50, 0.16, 0.8, 0), (0.28, 0.38, 0.7, -15),
                                                                 (0.74, 0.40, 0.8, 12), (0.20, 0.68, 0.6, -10),
                                                                 (0.80, 0.70, 0.7, 15), (0.50, 0.88, 0.6, 0),
                                                                 (0.62, 0.26, 0.45, 20), (0.36, 0.82, 0.45, -20)]
            for (i, (x, y, k, r)) in spots.enumerated() {
                var g = ctx
                g.translateBy(x: x * w, y: y * h)
                g.rotate(by: .degrees(r))
                g.fill(heart(0, 0, s * 0.07 * k), with: .color(i % 2 == 0 ? .white.opacity(0.8) : hx(0xFFB3C9, 0.9)))
            }
        }
        if fx.contains(.clovers) {
            let spots: [(CGFloat, CGFloat, CGFloat, Double)] = [(0.50, 0.18, 0.8, 0), (0.28, 0.42, 0.7, -20),
                                                                 (0.74, 0.44, 0.7, 15), (0.22, 0.72, 0.6, 10),
                                                                 (0.78, 0.74, 0.6, -10), (0.50, 0.88, 0.55, 5)]
            for (x, y, k, r) in spots {
                var g = ctx
                g.translateBy(x: x * w, y: y * h)
                g.rotate(by: .degrees(r))
                clover(&g, s * 0.06 * k, color: hx(0xE8FFD2, 0.75))
            }
            for (x, y) in [(0.40, 0.30), (0.64, 0.62), (0.34, 0.58), (0.60, 0.80)] as [(CGFloat, CGFloat)] {
                ctx.fill(FlameyArt.star(x * w, y * h, s * 0.022, inner: 0.3), with: .color(hx(0xFFD84A)))
            }
        }
        if fx.contains(.raindrops) {
            let drops: [(CGFloat, CGFloat, CGFloat)] = [(0.46, 0.14, 0.8), (0.30, 0.30, 0.7), (0.66, 0.28, 0.9),
                                                        (0.22, 0.50, 0.6), (0.78, 0.52, 0.7), (0.50, 0.44, 0.5),
                                                        (0.36, 0.66, 0.55), (0.64, 0.68, 0.6)]
            for (x, y, k) in drops {
                ctx.fill(drop(x * w, y * h, s * 0.05 * k), with: .color(.white.opacity(0.8)))
            }
        }
        if fx.contains(.flowers) {
            let spots: [(CGFloat, CGFloat, CGFloat, UInt32)] = [(0.50, 0.18, 0.8, 0xFFFFFF), (0.28, 0.40, 0.7, 0xFF8FB8),
                                                                 (0.74, 0.42, 0.8, 0xFFE066), (0.22, 0.70, 0.6, 0xB89BFF),
                                                                 (0.78, 0.72, 0.7, 0xFFFFFF), (0.50, 0.86, 0.6, 0xFF8FB8)]
            for (x, y, k, col) in spots {
                flower(&ctx, x * w, y * h, s * 0.06 * k, petal: hx(col, 0.92), heart: hx(0xFFB020))
            }
        }
        if fx.contains(.leaves) {
            let spots: [(CGFloat, CGFloat, CGFloat, Double, UInt32)] = [
                (0.50, 0.18, 0.8, -15, 0xFFE07A), (0.28, 0.42, 0.75, 25, 0xB8320E), (0.74, 0.44, 0.8, -30, 0xFFD24A),
                (0.22, 0.72, 0.6, 40, 0xFFE07A), (0.78, 0.74, 0.65, -10, 0x8A2A08), (0.50, 0.86, 0.6, 15, 0xB8320E)]
            for (x, y, k, r, col) in spots {
                var g = ctx
                g.translateBy(x: x * w, y: y * h)
                g.rotate(by: .degrees(r))
                g.fill(leaf(s * 0.07 * k), with: .color(hx(col, 0.9)))
                var vein = Path()
                vein.move(to: CGPoint(x: 0, y: s * 0.07 * k))
                vein.addLine(to: CGPoint(x: 0, y: -s * 0.05 * k))
                g.stroke(vein, with: .color(hx(0x5A1A04, 0.55)), lineWidth: max(0.5, s * 0.006))
            }
        }
        if fx.contains(.stringLights) {
            // Two swags of wire, a glowing bulb at every sag.
            let bulbs: [UInt32] = [0xFF4F5E, 0xFFD24A, 0x4FA8FF, 0xFF8FD0, 0xFFFFFF]
            var k = 0
            for (y0, y1) in [(0.30, 0.42), (0.62, 0.74)] as [(CGFloat, CGFloat)] {
                var wire = Path()
                wire.move(to: p(-0.05, y0))
                wire.addQuadCurve(to: p(1.05, y0), control: p(0.5, y1 * 2 - y0))
                ctx.stroke(wire, with: .color(hx(0x0A2A14, 0.85)), lineWidth: max(0.6, s * 0.01))
                for t in [0.12, 0.31, 0.5, 0.69, 0.88] as [CGFloat] {
                    let x = -0.05 + t * 1.1
                    let y = y0 + (y1 - y0) * 4 * t * (1 - t) * 1.0
                    let col = hx(bulbs[k % bulbs.count])
                    k += 1
                    let c = p(x, y + 0.02)
                    var glow = ctx
                    glow.addFilter(.blur(radius: s * 0.025))
                    glow.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.045, y: c.y - s * 0.045, width: s * 0.09, height: s * 0.09)),
                              with: .color(col.opacity(0.7)))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.018, y: c.y - s * 0.012, width: s * 0.036, height: s * 0.05)),
                             with: .color(col))
                }
            }
        }
    }

    // MARK: Shapes (centred on x, y)

    static func heart(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x, y: y + r * 0.9))
        p.addCurve(to: CGPoint(x: x - r, y: y - r * 0.15), control1: CGPoint(x: x - r * 0.5, y: y + r * 0.5),
                   control2: CGPoint(x: x - r, y: y + r * 0.25))
        p.addArc(center: CGPoint(x: x - r * 0.5, y: y - r * 0.3), radius: r * 0.52,
                 startAngle: .degrees(160), endAngle: .degrees(340), clockwise: false)
        p.addArc(center: CGPoint(x: x + r * 0.5, y: y - r * 0.3), radius: r * 0.52,
                 startAngle: .degrees(200), endAngle: .degrees(20), clockwise: false)
        p.addCurve(to: CGPoint(x: x, y: y + r * 0.9), control1: CGPoint(x: x + r, y: y + r * 0.25),
                   control2: CGPoint(x: x + r * 0.5, y: y + r * 0.5))
        p.closeSubpath()
        return p
    }

    /// A raindrop / seed: round at the bottom, pointed on top.
    static func drop(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: x, y: y - r * 1.2))
        p.addQuadCurve(to: CGPoint(x: x + r * 0.6, y: y + r * 0.2), control: CGPoint(x: x + r * 0.55, y: y - r * 0.35))
        p.addArc(center: CGPoint(x: x, y: y + r * 0.2), radius: r * 0.6, startAngle: .degrees(0), endAngle: .degrees(180),
                 clockwise: false)
        p.addQuadCurve(to: CGPoint(x: x, y: y - r * 1.2), control: CGPoint(x: x - r * 0.55, y: y - r * 0.35))
        p.closeSubpath()
        return p
    }

    static func snowflake(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        var p = Path()
        for i in 0..<6 {
            let a = Double(i) * .pi / 3
            let tip = CGPoint(x: x + CGFloat(cos(a)) * r, y: y + CGFloat(sin(a)) * r)
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: tip)
            let mid = CGPoint(x: x + CGFloat(cos(a)) * r * 0.6, y: y + CGFloat(sin(a)) * r * 0.6)
            for side in [-1.0, 1.0] as [Double] {
                let b = a + side * .pi / 4
                p.move(to: mid)
                p.addLine(to: CGPoint(x: mid.x + CGFloat(cos(b)) * r * 0.3, y: mid.y + CGFloat(sin(b)) * r * 0.3))
            }
        }
        return p
    }

    static func clover(_ ctx: inout GraphicsContext, _ r: CGFloat, color: Color) {
        for i in 0..<3 {
            let a = Double(i) * 2 * .pi / 3 - .pi / 2
            let c = CGPoint(x: CGFloat(cos(a)) * r * 0.55, y: CGFloat(sin(a)) * r * 0.55)
            ctx.fill(heart(c.x, c.y, r * 0.6), with: .color(color))
        }
        var stem = Path()
        stem.move(to: CGPoint(x: 0, y: r * 0.2))
        stem.addQuadCurve(to: CGPoint(x: r * 0.35, y: r * 1.3), control: CGPoint(x: 0, y: r))
        ctx.stroke(stem, with: .color(color), style: StrokeStyle(lineWidth: max(0.6, r * 0.18), lineCap: .round))
    }

    static func flower(_ ctx: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, petal: Color, heart: Color) {
        for i in 0..<5 {
            let a = Double(i) * 2 * .pi / 5 - .pi / 2
            let c = CGPoint(x: x + CGFloat(cos(a)) * r * 0.55, y: y + CGFloat(sin(a)) * r * 0.55)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.42, y: c.y - r * 0.42, width: r * 0.84, height: r * 0.84)),
                     with: .color(petal))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: x - r * 0.32, y: y - r * 0.32, width: r * 0.64, height: r * 0.64)),
                 with: .color(heart))
    }

    /// A maple-ish leaf pointing up, centred on the origin.
    static func leaf(_ r: CGFloat) -> Path {
        let pts: [(CGFloat, CGFloat)] = [(0, -1.0), (0.18, -0.55), (0.62, -0.72), (0.45, -0.25), (0.95, -0.05),
                                         (0.45, 0.20), (0.55, 0.62), (0.08, 0.42), (0, 0.9),
                                         (-0.08, 0.42), (-0.55, 0.62), (-0.45, 0.20), (-0.95, -0.05),
                                         (-0.45, -0.25), (-0.62, -0.72), (-0.18, -0.55)]
        var p = Path()
        p.move(to: CGPoint(x: pts[0].0 * r, y: pts[0].1 * r))
        for (x, y) in pts.dropFirst() { p.addLine(to: CGPoint(x: x * r, y: y * r)) }
        p.closeSubpath()
        return p
    }
}

extension FlameyLook {
    /// The palette his FIGURE is drawn in — body, arms, legs and glow: his
    /// colour, unless a costume skins all of him. Every surface that builds
    /// a `FlameBuddyFigure` (or a glow) from a look reads this, never
    /// `FlameyPalette.palette(for: color)`, so a suit can't leave flame-
    /// coloured limbs poking out of it.
    var figurePalette: FlameyPalette? {
        // A costume that skins all of him (the skeleton suit) says so in its
        // skin's `rules.figure_palette`.
        for item in items where item.slot != .color {
            if let p = item.skin?.figurePalette { return p }
        }
        return FlameyPalette.palette(for: color)
    }
}
