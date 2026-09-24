import SwiftUI

// MOCK — Canvas drawings for every proposed item, in FlameyArt's geometry:
// origin = centre of the figure's size square, u = size × body scale.

typealias GC = GraphicsContext

@inline(__always) func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
func circ(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }
func ell(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path { Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2)) }
func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
    Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .continuous)
}
func moved(_ ctx: GC, _ x: CGFloat, _ y: CGFloat, _ deg: Double = 0) -> GC {
    var g = ctx
    g.translateBy(x: x, y: y)
    if deg != 0 { g.rotate(by: .degrees(deg)) }
    return g
}
func lin(_ colors: [Color], _ a: CGPoint, _ b: CGPoint) -> GraphicsContext.Shading {
    .linearGradient(Gradient(colors: colors), startPoint: a, endPoint: b)
}
func poly(_ pts: [CGPoint]) -> Path {
    var p = Path()
    for (i, q) in pts.enumerated() { if i == 0 { p.move(to: q) } else { p.addLine(to: q) } }
    p.closeSubpath()
    return p
}

/// Ink used for every outline, so line weight reads as one family.
let INK = hex(0x2A1410)

enum Art {
    static func lw(_ u: CGFloat) -> CGFloat { max(1, 0.010 * u) }

    // MARK: - Dispatch

    static func front(_ item: MockItem, _ ctx: inout GC, _ a: FlameyArt.Anchors, _ u: CGFloat, size: CGFloat, arm: Color) {
        switch item.slot {
        case .feet: shoe(item, &ctx, a, u)
        case .head: hat(item, &ctx, a, u)
        case .face: eyewear(item, &ctx, a, u)
        case .neck: neck(item, &ctx, a, u)
        case .held: held(item, &ctx, a, u, arm: arm)
        case .costume: ghostSheet(&ctx, a, u)
        case .back:
            // Cape clasp at the neck.
            if item != .victoryBanner && item != .goldenWings { capeClasp(item, &ctx, a, u) }
        default: break
        }
        if item.slot == .back && (item == .victoryBanner) {
            // Harness strap over the chest.
            var s = Path()
            s.move(to: P(-0.20 * u, a.bottom - 0.20 * u)); s.addQuadCurve(to: P(0.22 * u, a.bottom - 0.02 * u), control: P(0.02 * u, a.bottom - 0.05 * u))
            ctx.stroke(s, with: .color(hex(0x5A3A1E)), style: StrokeStyle(lineWidth: 0.035 * u, lineCap: .round))
            ctx.fill(rrect(-0.03 * u, a.bottom - 0.10 * u, 0.06 * u, 0.05 * u, 0.01 * u), with: .color(hex(0xFFCF40)))
        }
    }

    // MARK: - Shoes

    static func shoePath(w: CGFloat, h: CGFloat, low: Bool = false, pointy: Bool = false) -> Path {
        var p = Path()
        let top: CGFloat = low ? -0.30 : -0.5
        p.move(to: P(-w * 0.5, h * 0.35))
        p.addLine(to: P(-w * 0.5, h * top * 0.2))
        p.addQuadCurve(to: P(-w * 0.15, h * top), control: P(-w * 0.48, h * top))
        p.addLine(to: P(w * 0.05, h * top * 0.9))
        p.addQuadCurve(to: P(w * (pointy ? 0.55 : 0.45), h * 0.10), control: P(w * 0.25, h * -0.05))
        p.addQuadCurve(to: P(w * 0.5, h * 0.35), control: P(w * 0.58, h * 0.22))
        p.closeSubpath()
        return p
    }

    static func shoe(_ item: MockItem, _ ctx: inout GC, _ a: FlameyArt.Anchors, _ u: CGFloat) {
        let w = 0.25 * u, h = 0.11 * u
        let L = lw(u)
        for side in [-1.0, 1.0] as [CGFloat] {
            var g = moved(ctx, side * 0.16 * u, a.bottom - h * 0.35)
            g.scaleBy(x: side, y: 1)
            switch item {
            case .canvasSneakers:
                // High-top: a taller upper, rubber toe cap, stripe, laces, ankle patch.
                var up = Path()
                up.move(to: P(-w * 0.5, h * 0.35)); up.addLine(to: P(-w * 0.5, -h * 1.05))
                up.addQuadCurve(to: P(-w * 0.12, -h * 1.1), control: P(-w * 0.32, -h * 1.22))
                up.addLine(to: P(-w * 0.02, -h * 0.35))
                up.addQuadCurve(to: P(w * 0.46, h * 0.08), control: P(w * 0.30, -h * 0.25))
                up.addQuadCurve(to: P(w * 0.5, h * 0.35), control: P(w * 0.56, h * 0.2))
                up.closeSubpath()
                g.fill(up, with: .color(hex(0x22306E)))
                g.stroke(up, with: .color(INK), lineWidth: L)
                g.fill(ell(w * 0.36, h * 0.1, w * 0.17, h * 0.22), with: .color(hex(0xF6F1E4)))
                g.fill(rrect(-w * 0.53, h * 0.14, w * 1.06, h * 0.30, h * 0.12), with: .color(hex(0xF6F1E4)))
                g.stroke(rrect(-w * 0.53, h * 0.14, w * 1.06, h * 0.30, h * 0.12), with: .color(INK), lineWidth: L)
                g.fill(Path(CGRect(x: -w * 0.53, y: h * 0.25, width: w * 1.06, height: h * 0.06)), with: .color(hex(0xE8384F)))
                g.fill(circ(-w * 0.33, -h * 0.6, h * 0.16), with: .color(hex(0xF6F1E4)))
                for i in 0..<3 {
                    let y = -h * 0.85 + CGFloat(i) * h * 0.28
                    var l = Path(); l.move(to: P(-w * 0.14, y)); l.addLine(to: P(w * 0.02, y + h * 0.08))
                    g.stroke(l, with: .color(.white), style: StrokeStyle(lineWidth: h * 0.09, lineCap: .round))
                }
            case .trainers:
                let s = shoePath(w: w, h: h)
                g.fill(s, with: .color(hex(0xF4F6FA)))
                g.fill(ell(-w * 0.25, -h * 0.08, w * 0.16, h * 0.22), with: .color(hex(0xC9D1DC)))
                var sw = Path(); sw.move(to: P(-w * 0.38, h * 0.02)); sw.addQuadCurve(to: P(w * 0.30, -h * 0.08), control: P(-w * 0.02, h * 0.22))
                g.stroke(sw, with: .color(hex(0x2F7BFF)), style: StrokeStyle(lineWidth: h * 0.16, lineCap: .round))
                g.stroke(s, with: .color(INK), lineWidth: L)
                let sole = rrect(-w * 0.54, h * 0.18, w * 1.08, h * 0.34, h * 0.16)
                g.fill(sole, with: .color(.white))
                g.fill(Path(CGRect(x: -w * 0.54, y: h * 0.36, width: w * 1.08, height: h * 0.05)), with: .color(hex(0xB8C2CF)))
                g.stroke(sole, with: .color(INK), lineWidth: L)
                g.fill(rrect(-w * 0.52, -h * 0.30, w * 0.12, h * 0.46, h * 0.05), with: .color(hex(0x2F7BFF)))
            case .racingFlats:
                let s = shoePath(w: w * 1.05, h: h * 0.9, low: true, pointy: true)
                g.fill(s, with: lin([hex(0xFF9A3C), hex(0xFF4E1A)], P(0, -h * 0.4), P(0, h * 0.3)))
                var st = Path(); st.move(to: P(-w * 0.34, -h * 0.02)); st.addLine(to: P(w * 0.26, -h * 0.02))
                g.stroke(st, with: .color(hex(0x1A1A22)), style: StrokeStyle(lineWidth: h * 0.10, lineCap: .round))
                var st2 = Path(); st2.move(to: P(-w * 0.30, h * 0.12)); st2.addLine(to: P(w * 0.34, h * 0.10))
                g.stroke(st2, with: .color(hex(0x1A1A22)), style: StrokeStyle(lineWidth: h * 0.06, lineCap: .round))
                g.stroke(s, with: .color(INK), lineWidth: L)
                let sole = rrect(-w * 0.55, h * 0.24, w * 1.14, h * 0.16, h * 0.08)
                g.fill(sole, with: .color(.white))
                g.stroke(sole, with: .color(INK), lineWidth: L)
            case .neonSoles:
                var gg = g
                gg.addFilter(.blur(radius: h * 0.35))
                gg.fill(rrect(-w * 0.6, h * 0.12, w * 1.2, h * 0.5, h * 0.2), with: .color(hex(0x39FF88, 0.9)))
                let s = shoePath(w: w, h: h)
                g.fill(s, with: .color(hex(0x1C1C26)))
                g.stroke(s, with: .color(INK), lineWidth: L)
                var lace = Path(); lace.move(to: P(-w * 0.1, -h * 0.35)); lace.addLine(to: P(w * 0.12, -h * 0.12))
                g.stroke(lace, with: .color(hex(0xFF3DAA)), style: StrokeStyle(lineWidth: h * 0.12, lineCap: .round, dash: [h * 0.12, h * 0.1]))
                var sw = Path(); sw.move(to: P(-w * 0.36, h * 0.05)); sw.addQuadCurve(to: P(w * 0.28, -h * 0.04), control: P(-w * 0.04, h * 0.18))
                g.stroke(sw, with: .color(hex(0xFF3DAA)), style: StrokeStyle(lineWidth: h * 0.10, lineCap: .round))
                let sole = rrect(-w * 0.54, h * 0.18, w * 1.08, h * 0.32, h * 0.16)
                g.fill(sole, with: lin([hex(0xB6FFD5), hex(0x39FF88)], P(0, h * 0.18), P(0, h * 0.5)))
            case .trackSpikes:
                let s = shoePath(w: w * 1.05, h: h * 0.95, low: true, pointy: true)
                g.fill(s, with: .color(hex(0xC6FF3D)))
                var z = Path(); z.move(to: P(-w * 0.35, h * 0.12)); z.addLine(to: P(-w * 0.05, -h * 0.25)); z.addLine(to: P(w * 0.02, h * 0.02)); z.addLine(to: P(w * 0.32, -h * 0.02))
                g.stroke(z, with: .color(hex(0x1B2A6B)), style: StrokeStyle(lineWidth: h * 0.12, lineCap: .round, lineJoin: .round))
                g.stroke(s, with: .color(INK), lineWidth: L)
                let plate = rrect(-w * 0.52, h * 0.24, w * 1.1, h * 0.14, h * 0.07)
                g.fill(plate, with: .color(hex(0x1B2A6B)))
                for i in 0..<4 {
                    let x = -w * 0.02 + CGFloat(i) * w * 0.15
                    g.fill(poly([P(x - h * 0.07, h * 0.38), P(x + h * 0.07, h * 0.38), P(x, h * 0.62)]), with: .color(hex(0xDDE3EA)))
                }
            case .rocketBoots:
                // Jets first, so the boot sits over their roots.
                for (dx, sc) in [(-w * 0.28, 1.3), (w * 0.06, 1.0)] as [(CGFloat, CGFloat)] {
                    var flame = Path()
                    flame.move(to: P(dx - h * 0.26, h * 0.45))
                    flame.addQuadCurve(to: P(dx, h * (0.45 + 1.7 * sc)), control: P(dx - h * 0.36, h * (0.45 + 0.9 * sc)))
                    flame.addQuadCurve(to: P(dx + h * 0.26, h * 0.45), control: P(dx + h * 0.36, h * (0.45 + 0.9 * sc)))
                    flame.closeSubpath()
                    var gg = g; gg.addFilter(.blur(radius: h * 0.18))
                    gg.fill(flame, with: .color(hex(0xFF8A1F, 0.8)))
                    g.fill(flame, with: lin([hex(0xFFF3A0), hex(0xFFB020), hex(0xFF4E1A, 0.2)], P(0, h * 0.45), P(0, h * (0.45 + 1.7 * sc))))
                    g.fill(ell(dx, h * 0.62, h * 0.08, h * 0.2), with: .color(hex(0xBFE8FF)))
                }
                var boot = Path()
                boot.move(to: P(-w * 0.5, h * 0.4)); boot.addLine(to: P(-w * 0.5, -h * 0.95))
                boot.addQuadCurve(to: P(-w * 0.05, -h * 0.95), control: P(-w * 0.28, -h * 1.1))
                boot.addLine(to: P(-w * 0.02, -h * 0.3))
                boot.addQuadCurve(to: P(w * 0.5, h * 0.1), control: P(w * 0.4, -h * 0.25))
                boot.addLine(to: P(w * 0.5, h * 0.4)); boot.closeSubpath()
                g.fill(boot, with: lin([hex(0xF2F5F8), hex(0xAAB6C4)], P(0, -h), P(0, h * 0.4)))
                g.fill(Path(CGRect(x: -w * 0.5, y: -h * 0.62, width: w * 0.47, height: h * 0.14)), with: .color(hex(0xE8384F)))
                g.stroke(boot, with: .color(INK), lineWidth: L)
                g.fill(rrect(-w * 0.44, h * 0.30, w * 0.28, h * 0.2, h * 0.05), with: .color(hex(0x4A5563)))
                g.fill(rrect(-w * 0.52, h * 0.24, w * 1.04, h * 0.16, h * 0.06), with: .color(hex(0x5B6675)))
            case .lightningKicks:
                // Crackle.
                for (x0, y0, dir) in [(-w * 0.62, -h * 0.2, -1.0), (w * 0.62, -h * 0.45, 1.0), (w * 0.2, h * 0.75, 1.0)] as [(CGFloat, CGFloat, CGFloat)] {
                    var z = Path()
                    z.move(to: P(x0, y0)); z.addLine(to: P(x0 + dir * h * 0.25, y0 - h * 0.2)); z.addLine(to: P(x0 + dir * h * 0.18, y0 - h * 0.02)); z.addLine(to: P(x0 + dir * h * 0.45, y0 - h * 0.24))
                    var gg = g; gg.addFilter(.blur(radius: h * 0.12))
                    gg.stroke(z, with: .color(hex(0x7FE9FF)), style: StrokeStyle(lineWidth: h * 0.16, lineCap: .round, lineJoin: .round))
                    g.stroke(z, with: .color(.white), style: StrokeStyle(lineWidth: h * 0.06, lineCap: .round, lineJoin: .round))
                }
                let s = shoePath(w: w, h: h)
                g.fill(s, with: .color(hex(0xFFD21F)))
                g.fill(poly([P(-w * 0.28, -h * 0.35), P(w * 0.02, -h * 0.35), P(-w * 0.10, -h * 0.02), P(w * 0.16, -h * 0.02), P(-w * 0.22, h * 0.34), P(-w * 0.10, h * 0.06), P(-w * 0.34, h * 0.06)]), with: .color(hex(0x1A1A22)))
                g.stroke(s, with: .color(INK), lineWidth: L)
                let sole = rrect(-w * 0.54, h * 0.2, w * 1.08, h * 0.3, h * 0.14)
                g.fill(sole, with: .color(hex(0x1A1A22)))
            case .wingedSandals:
                // Sandal: a gold sole, straps over his foot, wings at the heel.
                for (i, ang) in [(0, -18.0), (1, -42.0), (2, -66.0)] as [(Int, Double)] {
                    let wg = moved(g, w * 0.02, -h * 0.25, ang)
                    let len = h * (1.9 - CGFloat(i) * 0.35)
                    let f = ell(len * 0.5, 0, len * 0.55, h * 0.2)
                    wg.fill(f, with: lin([.white, hex(0xDDE8FF)], P(0, -h * 0.2), P(0, h * 0.2)))
                    wg.stroke(f, with: .color(hex(0x8AA0C8)), lineWidth: L * 0.8)
                }
                let sole = rrect(-w * 0.54, h * 0.18, w * 1.08, h * 0.24, h * 0.12)
                g.fill(sole, with: lin([hex(0xFFE58A), hex(0xE0A512)], P(0, h * 0.18), P(0, h * 0.42)))
                g.stroke(sole, with: .color(hex(0x9A6400)), lineWidth: L)
                for (x, ang) in [(-w * 0.18, 60.0), (w * 0.14, -60.0)] as [(CGFloat, Double)] {
                    let sg = moved(g, x, -h * 0.05, ang)
                    sg.fill(rrect(-h * 0.08, -h * 0.35, h * 0.16, h * 0.7, h * 0.08), with: .color(hex(0xFFCF40)))
                    sg.stroke(rrect(-h * 0.08, -h * 0.35, h * 0.16, h * 0.7, h * 0.08), with: .color(hex(0x9A6400)), lineWidth: L * 0.8)
                }
                g.fill(circ(-w * 0.02, -h * 0.05, h * 0.09), with: .color(hex(0xFFF3B0)))
            default: break
            }
        }
    }

    // MARK: - Hats

    static func hat(_ item: MockItem, _ ctx: inout GC, _ a: FlameyArt.Anchors, _ u: CGFloat) {
        let L = lw(u)
        let top = a.topY
        switch item {
        case .ballCap:
            let g = moved(ctx, -0.01 * u, top + 0.15 * u, -6)
            let w = 0.34 * u, h = 0.19 * u
            var dome = Path()
            dome.move(to: P(-w / 2, 0)); dome.addCurve(to: P(w / 2, 0), control1: P(-w / 2, -h * 1.25), control2: P(w / 2, -h * 1.25)); dome.closeSubpath()
            // Brim (3/4 view) swings out to his right.
            var brim = Path()
            brim.move(to: P(w * 0.05, -h * 0.02)); brim.addQuadCurve(to: P(w * 0.95, h * 0.08), control: P(w * 0.62, -h * 0.30))
            brim.addQuadCurve(to: P(w * 0.1, h * 0.14), control: P(w * 0.6, h * 0.30)); brim.closeSubpath()
            g.fill(dome, with: lin([hex(0xFF5A6E), hex(0xD41F3A)], P(0, -h), P(0, 0)))
            var seam = Path(); seam.move(to: P(0, -h * 0.94)); seam.addQuadCurve(to: P(-w * 0.1, 0), control: P(-w * 0.12, -h * 0.5))
            g.stroke(seam, with: .color(hex(0x9E1028)), lineWidth: L * 0.8)
            g.fill(circ(w * 0.08, -h * 0.45, h * 0.22), with: .color(.white))
            g.fill(FlameyArt.star(w * 0.08, -h * 0.45, h * 0.16, inner: 0.45), with: .color(hex(0xD41F3A)))
            g.stroke(dome, with: .color(INK), lineWidth: L)
            g.fill(brim, with: .color(hex(0xB3152F)))
            g.stroke(brim, with: .color(INK), lineWidth: L)
            g.fill(ell(0, -h * 0.93, h * 0.09, h * 0.05), with: .color(hex(0xB3152F)))
        case .visor:
            let g = moved(ctx, 0, top + 0.20 * u, -4)
            let w = 0.36 * u, h = 0.07 * u
            var brim = Path()
            brim.move(to: P(-w * 0.1, 0)); brim.addQuadCurve(to: P(w * 0.92, h * 0.9), control: P(w * 0.6, -h * 1.6))
            brim.addQuadCurve(to: P(w * 0.05, h * 1.2), control: P(w * 0.6, h * 2.2)); brim.closeSubpath()
            let band = FlameyArt.band(w: w, h: h, sag: 0.6)
            g.fill(band, with: .color(.white))
            g.stroke(band, with: .color(INK), lineWidth: L)
            g.fill(brim, with: lin([hex(0x2EE6C8), hex(0x0FA38F)], P(0, -h), P(0, h * 1.5)))
            g.stroke(brim, with: .color(INK), lineWidth: L)
            var st = Path(); st.move(to: P(w * 0.12, h * 0.9)); st.addQuadCurve(to: P(w * 0.78, h * 0.72), control: P(w * 0.5, h * 1.5))
            g.stroke(st, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: L * 0.8, dash: [L * 2, L * 1.5]))
        case .beanie:
            let g = moved(ctx, 0, top + 0.19 * u, -3)
            let w = 0.34 * u, h = 0.24 * u
            var dome = Path()
            dome.move(to: P(-w / 2, 0)); dome.addCurve(to: P(w / 2, 0), control1: P(-w / 2, -h * 1.2), control2: P(w / 2, -h * 1.2)); dome.closeSubpath()
            g.fill(dome, with: .color(hex(0x2F6BFF)))
            var knit = g; knit.clip(to: dome)
            for i in -4...4 {
                var r = Path(); r.move(to: P(CGFloat(i) * w * 0.1, 0)); r.addQuadCurve(to: P(CGFloat(i) * w * 0.02, -h), control: P(CGFloat(i) * w * 0.09, -h * 0.6))
                knit.stroke(r, with: .color(hex(0x1D4FD1)), lineWidth: L * 0.9)
            }
            knit.fill(Path(CGRect(x: -w, y: -h * 0.55, width: w * 2, height: h * 0.1)), with: .color(.white.opacity(0.9)))
            g.stroke(dome, with: .color(INK), lineWidth: L)
            let cuff = rrect(-w * 0.54, -h * 0.12, w * 1.08, h * 0.30, h * 0.12)
            g.fill(cuff, with: .color(hex(0x1D4FD1)))
            for i in 0..<9 {
                let x = -w * 0.46 + CGFloat(i) * w * 0.115
                g.fill(rrect(x, -h * 0.08, w * 0.05, h * 0.22, w * 0.02), with: .color(hex(0x3F7BFF)))
            }
            g.stroke(cuff, with: .color(INK), lineWidth: L)
            // Pom-pom
            for (dx, dy) in [(0.0, 0.0), (-0.3, -0.2), (0.3, -0.2), (0, -0.4), (-0.25, 0.2), (0.25, 0.2)] as [(CGFloat, CGFloat)] {
                g.fill(circ(dx * h * 0.25, -h * 1.0 + dy * h * 0.25, h * 0.14), with: .color(.white))
            }
            g.stroke(circ(0, -h * 1.0, h * 0.2), with: .color(hex(0xC9D6F2)), lineWidth: L * 0.7)
        case .bucketHat:
            let g = moved(ctx, 0, top + 0.18 * u, -3)
            let w = 0.28 * u, h = 0.16 * u
            var brim = Path()
            brim.move(to: P(-w * 0.52, -h * 0.05)); brim.addLine(to: P(w * 0.52, -h * 0.05))
            brim.addQuadCurve(to: P(w * 0.78, h * 0.42), control: P(w * 0.72, h * 0.1))
            brim.addQuadCurve(to: P(-w * 0.78, h * 0.42), control: P(0, h * 0.62))
            brim.addQuadCurve(to: P(-w * 0.52, -h * 0.05), control: P(-w * 0.72, h * 0.1)); brim.closeSubpath()
            var crown = Path()
            crown.move(to: P(-w * 0.5, 0)); crown.addLine(to: P(-w * 0.38, -h * 0.95))
            crown.addQuadCurve(to: P(w * 0.38, -h * 0.95), control: P(0, -h * 1.12)); crown.addLine(to: P(w * 0.5, 0)); crown.closeSubpath()
            g.fill(crown, with: lin([hex(0xA3B86C), hex(0x7E9448)], P(0, -h), P(0, 0)))
            g.stroke(crown, with: .color(INK), lineWidth: L)
            g.fill(Path(CGRect(x: -w * 0.49, y: -h * 0.28, width: w * 0.98, height: h * 0.22)), with: .color(hex(0x5E6E33)))
            g.fill(brim, with: .color(hex(0x93A85C)))
            var stitch = Path(); stitch.move(to: P(-w * 0.66, h * 0.3)); stitch.addQuadCurve(to: P(w * 0.66, h * 0.3), control: P(0, h * 0.5))
            g.stroke(stitch, with: .color(hex(0x5E6E33)), style: StrokeStyle(lineWidth: L * 0.7, dash: [L * 1.8, L * 1.2]))
            g.stroke(brim, with: .color(INK), lineWidth: L)
        case .safariHat:
            let g = moved(ctx, 0, top + 0.17 * u, -4)
            let w = 0.30 * u, h = 0.18 * u
            let brim = ell(0, 0, w * 0.82, h * 0.26)
            g.fill(brim, with: .color(hex(0xC9A465)))
            g.stroke(brim, with: .color(INK), lineWidth: L)
            var dome = Path()
            dome.move(to: P(-w * 0.48, 0)); dome.addCurve(to: P(w * 0.48, 0), control1: P(-w * 0.5, -h * 1.3), control2: P(w * 0.5, -h * 1.3)); dome.closeSubpath()
            g.fill(dome, with: lin([hex(0xF0D9A6), hex(0xD4B06E)], P(-w * 0.3, -h), P(w * 0.3, 0)))
            g.stroke(dome, with: .color(INK), lineWidth: L)
            g.fill(Path(CGRect(x: -w * 0.47, y: -h * 0.26, width: w * 0.94, height: h * 0.2)), with: .color(hex(0x6B4E2A)))
            g.fill(circ(0, -h * 0.98, h * 0.07), with: .color(hex(0xB8914F)))
        case .cowboyHat:
            let g = moved(ctx, 0, top + 0.16 * u, -5)
            let w = 0.30 * u, h = 0.18 * u
            var brim = Path()
            brim.move(to: P(-w * 0.95, -h * 0.35))
            brim.addQuadCurve(to: P(-w * 0.45, h * 0.05), control: P(-w * 0.85, h * 0.05))
            brim.addQuadCurve(to: P(w * 0.45, h * 0.05), control: P(0, h * 0.35))
            brim.addQuadCurve(to: P(w * 0.95, -h * 0.35), control: P(w * 0.85, h * 0.05))
            brim.addQuadCurve(to: P(-w * 0.95, -h * 0.35), control: P(0, h * 0.5))
            brim.closeSubpath()
            var crown = Path()
            crown.move(to: P(-w * 0.45, 0)); crown.addLine(to: P(-w * 0.40, -h * 0.95))
            crown.addQuadCurve(to: P(0, -h * 0.80), control: P(-w * 0.2, -h * 1.12))
            crown.addQuadCurve(to: P(w * 0.40, -h * 0.95), control: P(w * 0.2, -h * 1.12))
            crown.addLine(to: P(w * 0.45, 0)); crown.closeSubpath()
            g.fill(crown, with: lin([hex(0xA86A34), hex(0x7A4520)], P(0, -h), P(0, 0)))
            g.stroke(crown, with: .color(INK), lineWidth: L)
            g.fill(Path(CGRect(x: -w * 0.44, y: -h * 0.26, width: w * 0.88, height: h * 0.18)), with: .color(hex(0x3B2212)))
            g.fill(circ(w * 0.18, -h * 0.17, h * 0.08), with: .color(hex(0xDDE3EA)))
            g.fill(brim, with: lin([hex(0xB87A3E), hex(0x8A5226)], P(0, -h * 0.3), P(0, h * 0.3)))
            g.stroke(brim, with: .color(INK), lineWidth: L)
        case .aviatorCap:
            let g = moved(ctx, 0, top + 0.19 * u, -3)
            let w = 0.34 * u, h = 0.24 * u
            var dome = Path()
            dome.move(to: P(-w / 2, h * 0.05)); dome.addCurve(to: P(w / 2, h * 0.05), control1: P(-w / 2, -h * 1.2), control2: P(w / 2, -h * 1.2)); dome.closeSubpath()
            g.fill(dome, with: lin([hex(0x9A6038), hex(0x6B3E20)], P(-w * 0.3, -h), P(w * 0.3, 0)))
            var seam = Path(); seam.move(to: P(0, -h * 0.86)); seam.addLine(to: P(0, h * 0.02))
            g.stroke(seam, with: .color(hex(0x4A2A14)), style: StrokeStyle(lineWidth: L * 0.8, dash: [L * 1.5, L]))
            g.stroke(dome, with: .color(INK), lineWidth: L)
            g.fill(rrect(-w * 0.55, -h * 0.02, w * 1.1, h * 0.18, h * 0.09), with: .color(hex(0xF3E6CF)))
            // Goggles pushed up on the cap.
            let gy = -h * 0.42
            var strap = Path(); strap.move(to: P(-w * 0.5, gy + h * 0.02)); strap.addQuadCurve(to: P(w * 0.5, gy + h * 0.02), control: P(0, gy + h * 0.12))
            g.stroke(strap, with: .color(hex(0x2B2B33)), lineWidth: h * 0.1)
            for sx in [-1.0, 1.0] as [CGFloat] {
                let c = P(sx * w * 0.2, gy)
                g.fill(circ(c.x, c.y, h * 0.2), with: .color(hex(0xC9953A)))
                g.stroke(circ(c.x, c.y, h * 0.2), with: .color(INK), lineWidth: L)
                g.fill(circ(c.x, c.y, h * 0.14), with: lin([hex(0x9FE3FF), hex(0x3A7BD5)], P(c.x - h * 0.14, c.y - h * 0.14), P(c.x + h * 0.14, c.y + h * 0.14)))
                g.fill(circ(c.x - h * 0.05, c.y - h * 0.05, h * 0.04), with: .color(.white.opacity(0.9)))
            }
        case .headlampHelmet:
            let g = moved(ctx, 0, top + 0.19 * u, -3)
            let w = 0.36 * u, h = 0.23 * u
            // Beam first.
            var beam = Path()
            beam.move(to: P(w * 0.02, -h * 0.40)); beam.addLine(to: P(w * 1.6, -h * 1.6)); beam.addLine(to: P(w * 1.9, -h * 0.2)); beam.closeSubpath()
            g.fill(beam, with: lin([hex(0xFFF6B0, 0.75), hex(0xFFF6B0, 0)], P(0, -h * 0.4), P(w * 1.8, -h * 0.9)))
            var dome = Path()
            dome.move(to: P(-w / 2, 0)); dome.addCurve(to: P(w / 2, 0), control1: P(-w / 2, -h * 1.25), control2: P(w / 2, -h * 1.25)); dome.closeSubpath()
            g.fill(dome, with: lin([hex(0xFFE14D), hex(0xF2A900)], P(-w * 0.3, -h), P(w * 0.3, 0)))
            g.fill(rrect(-w * 0.05, -h * 0.92, w * 0.1, h * 0.88, w * 0.04), with: .color(hex(0xE09A00)))
            g.stroke(dome, with: .color(INK), lineWidth: L)
            g.fill(rrect(-w * 0.58, -h * 0.08, w * 1.16, h * 0.16, h * 0.08), with: .color(hex(0xF2A900)))
            g.stroke(rrect(-w * 0.58, -h * 0.08, w * 1.16, h * 0.16, h * 0.08), with: .color(INK), lineWidth: L)
            g.fill(rrect(-w * 0.16, -h * 0.58, w * 0.32, h * 0.32, h * 0.08), with: .color(hex(0x2B2B33)))
            g.fill(circ(0, -h * 0.42, h * 0.12), with: .color(hex(0xFFFBE0)))
            var glow = g; glow.addFilter(.blur(radius: h * 0.12))
            glow.fill(circ(0, -h * 0.42, h * 0.16), with: .color(hex(0xFFF6B0, 0.8)))
        case .crown:
            var g = ctx
            g.translateBy(x: 0, y: top + 0.08 * u); g.scaleBy(x: 1.45, y: 1.45); g.translateBy(x: 0, y: -(top + 0.08 * u))
            FlameyArt.draw(.crown, in: &g, size: a.bottom * 2, scale: u / (a.bottom * 2))
        case .laurel:
            let g = moved(ctx, 0, top + 0.20 * u, 0)
            let R = 0.17 * u
            for side in [-1.0, 1.0] as [CGFloat] {
                var stem = Path()
                stem.addArc(center: P(0, -R * 0.2), radius: R, startAngle: .degrees(side < 0 ? 100 : 80), endAngle: .degrees(side < 0 ? 215 : -35), clockwise: side > 0)
                g.stroke(stem, with: .color(hex(0x4F7D2A)), lineWidth: L * 1.2)
                for i in 0..<6 {
                    let ang = Double(side < 0 ? 110 + i * 20 : 70 - i * 20) * .pi / 180
                    let c = P(CGFloat(cos(ang)) * R, -R * 0.2 + CGFloat(sin(ang)) * R)
                    let leaf = moved(g, c.x, c.y, ang * 180 / .pi + (side < 0 ? 60 : -60) + 90)
                    let lf = ell(0, -R * 0.14, R * 0.09, R * 0.2)
                    leaf.fill(lf, with: lin([hex(0x9BD35A), hex(0x4F9D2A)], P(0, -R * 0.3), P(0, 0)))
                    leaf.stroke(lf, with: .color(hex(0x2F5E16)), lineWidth: L * 0.7)
                }
            }
            // Ribbon knot at the back-bottom.
            g.fill(circ(0, R * 0.78, R * 0.1), with: .color(hex(0xFFCF40)))
            for sx in [-1.0, 1.0] as [CGFloat] {
                g.fill(poly([P(0, R * 0.78), P(sx * R * 0.3, R * 1.05), P(sx * R * 0.2, R * 1.15)]), with: .color(hex(0xFFCF40)))
            }
        case .vikingHelmet:
            let g = moved(ctx, 0, top + 0.20 * u, -2)
            let w = 0.36 * u, h = 0.24 * u
            for sx in [-1.0, 1.0] as [CGFloat] {
                var horn = Path()
                horn.move(to: P(sx * w * 0.40, -h * 0.35))
                horn.addQuadCurve(to: P(sx * w * 0.95, -h * 1.35), control: P(sx * w * 1.05, -h * 0.45))
                horn.addQuadCurve(to: P(sx * w * 0.42, -h * 0.65), control: P(sx * w * 0.78, -h * 0.6))
                horn.closeSubpath()
                g.fill(horn, with: lin([hex(0xFFF8E6), hex(0xD9C49A)], P(sx * w * 0.4, 0), P(sx * w, -h * 1.3)))
                g.stroke(horn, with: .color(INK), lineWidth: L)
                for t in [0.3, 0.55] as [CGFloat] {
                    var ring = Path(); ring.move(to: P(sx * w * (0.46 + t * 0.4), -h * (0.4 + t * 0.55))); ring.addLine(to: P(sx * w * (0.60 + t * 0.4), -h * (0.62 + t * 0.4)))
                    g.stroke(ring, with: .color(hex(0xB8A276)), lineWidth: L)
                }
            }
            var dome = Path()
            dome.move(to: P(-w / 2, 0)); dome.addCurve(to: P(w / 2, 0), control1: P(-w / 2, -h * 1.3), control2: P(w / 2, -h * 1.3)); dome.closeSubpath()
            g.fill(dome, with: lin([hex(0xE3E9F0), hex(0x8C98A6)], P(-w * 0.3, -h), P(w * 0.3, 0)))
            g.fill(rrect(-w * 0.05, -h * 0.96, w * 0.1, h * 0.96, w * 0.03), with: .color(hex(0xC89B3C)))
            g.stroke(dome, with: .color(INK), lineWidth: L)
            let rim = rrect(-w * 0.54, -h * 0.12, w * 1.08, h * 0.2, h * 0.08)
            g.fill(rim, with: .color(hex(0xC89B3C)))
            g.stroke(rim, with: .color(INK), lineWidth: L)
            for i in 0..<5 { g.fill(circ(-w * 0.4 + CGFloat(i) * w * 0.2, -h * 0.02, h * 0.035), with: .color(hex(0xFFE9A8))) }
        case .astronautHelmet:
            // A fishbowl around his whole upper body, collar at the neck.
            let cy = a.faceY - 0.12 * u
            let R = 0.47 * u
            ctx.fill(circ(0, cy, R), with: .color(hex(0x9FD8FF, 0.16)))
            ctx.stroke(circ(0, cy, R), with: .color(.white.opacity(0.85)), lineWidth: L * 1.6)
            ctx.stroke(circ(0, cy, R - L * 2.2), with: .color(hex(0x9FD8FF, 0.5)), lineWidth: L * 0.8)
            var hl = Path()
            hl.addArc(center: P(0, cy), radius: R * 0.82, startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
            ctx.stroke(hl, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: L * 3, lineCap: .round))
            ctx.fill(circ(R * 0.5, cy - R * 0.55, L * 1.8), with: .color(.white.opacity(0.9)))
            let collar = rrect(-0.40 * u, a.bottom - 0.135 * u, 0.80 * u, 0.09 * u, 0.045 * u)
            ctx.fill(collar, with: lin([.white, hex(0xC9D2DC)], P(0, a.bottom - 0.135 * u), P(0, a.bottom - 0.045 * u)))
            ctx.stroke(collar, with: .color(INK), lineWidth: L)
            for i in 0..<5 { ctx.fill(circ(-0.28 * u + CGFloat(i) * 0.14 * u, a.bottom - 0.09 * u, 0.012 * u), with: .color(hex(0x8C98A6))) }
            // Antenna
            var ant = Path(); ant.move(to: P(0.30 * u, cy - R * 0.84)); ant.addLine(to: P(0.40 * u, cy - R * 1.12))
            ctx.stroke(ant, with: .color(hex(0xC9D2DC)), lineWidth: L * 1.2)
            ctx.fill(circ(0.40 * u, cy - R * 1.12, 0.025 * u), with: .color(hex(0xE8384F)))
        case .beret:
            let g = moved(ctx, 0.02 * u, top + 0.15 * u, -12)
            let w = 0.40 * u, h = 0.13 * u
            var b = Path()
            b.move(to: P(-w * 0.42, h * 0.3))
            b.addCurve(to: P(w * 0.55, h * 0.1), control1: P(-w * 0.62, -h * 1.1), control2: P(w * 0.62, -h * 1.0))
            b.addQuadCurve(to: P(-w * 0.42, h * 0.3), control: P(w * 0.1, h * 0.7))
            b.closeSubpath()
            g.fill(b, with: lin([hex(0x3A3A48), hex(0x14141C)], P(0, -h), P(0, h)))
            g.stroke(b, with: .color(INK), lineWidth: L)
            g.fill(rrect(-w * 0.03, -h * 0.95, w * 0.06, h * 0.3, w * 0.03), with: .color(hex(0x14141C)))
            var band = Path(); band.move(to: P(-w * 0.4, h * 0.26)); band.addQuadCurve(to: P(w * 0.2, h * 0.36), control: P(-w * 0.1, h * 0.6))
            g.stroke(band, with: .color(hex(0xE8384F)), lineWidth: L * 1.4)
        default: break
        }
    }

    // MARK: - Eyewear

    static func eyewear(_ item: MockItem, _ ctx: inout GC, _ a: FlameyArt.Anchors, _ u: CGFloat) {
        let L = lw(u)
        let ey = a.faceY
        switch item {
        case .starStickers:
            for (sx, c, r, rot) in [(-1.0, hex(0xFFCF40), 0.06, -12.0), (1.0, hex(0xFF6FAE), 0.05, 14.0)] as [(CGFloat, Color, CGFloat, Double)] {
                let g = moved(ctx, sx * (a.eyeX + 0.075 * u), ey + 0.10 * u, rot)
                g.fill(FlameyArt.star(0, 0, r * u * 1.3, inner: 0.52), with: .color(.white))
                g.fill(FlameyArt.star(0, 0, r * u, inner: 0.5), with: .color(c))
                g.fill(circ(-r * u * 0.25, -r * u * 0.25, r * u * 0.16), with: .color(.white.opacity(0.7)))
            }
            let g = moved(ctx, 0.20 * u, ey - 0.17 * u, 20)
            g.fill(FlameyArt.star(0, 0, 0.042 * u, inner: 0.5), with: .color(.white))
            g.fill(FlameyArt.star(0, 0, 0.032 * u, inner: 0.5), with: .color(hex(0x5CC8FF)))
        case .roundSpecs:
            let r = 0.098 * u
            for sx in [-1.0, 1.0] as [CGFloat] {
                let c = circ(sx * a.eyeX, ey, r)
                ctx.fill(c, with: .color(.white.opacity(0.14)))
                ctx.stroke(c, with: .color(hex(0x8A5A1E)), lineWidth: L * 1.4)
                var gl = Path(); gl.addArc(center: P(sx * a.eyeX, ey), radius: r * 0.72, startAngle: .degrees(200), endAngle: .degrees(240), clockwise: false)
                ctx.stroke(gl, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: L * 1.1, lineCap: .round))
            }
            var br = Path(); br.move(to: P(-a.eyeX + r, ey - r * 0.1)); br.addQuadCurve(to: P(a.eyeX - r, ey - r * 0.1), control: P(0, ey - r * 0.5))
            ctx.stroke(br, with: .color(hex(0x8A5A1E)), lineWidth: L * 1.4)
            for sx in [-1.0, 1.0] as [CGFloat] {
                var arm = Path(); arm.move(to: P(sx * (a.eyeX + r), ey - r * 0.2)); arm.addLine(to: P(sx * (a.eyeX + r * 1.6), ey - r * 0.35))
                ctx.stroke(arm, with: .color(hex(0x8A5A1E)), lineWidth: L * 1.4)
            }
        case .classicShades:
            FlameyArt.draw(.shades, in: &ctx, size: a.bottom * 2, scale: u / (a.bottom * 2))
        case .aviators:
            let frame = hex(0xD4A43A)
            for sx in [-1.0, 1.0] as [CGFloat] {
                var lens = Path()
                let cx = sx * a.eyeX
                lens.move(to: P(cx - sx * 0.10 * u, ey - 0.075 * u))
                lens.addLine(to: P(cx + sx * 0.10 * u, ey - 0.075 * u))
                lens.addQuadCurve(to: P(cx + sx * 0.03 * u, ey + 0.10 * u), control: P(cx + sx * 0.12 * u, ey + 0.08 * u))
                lens.addQuadCurve(to: P(cx - sx * 0.10 * u, ey - 0.075 * u), control: P(cx - sx * 0.12 * u, ey + 0.09 * u))
                lens.closeSubpath()
                ctx.fill(lens, with: lin([hex(0x3A2410), hex(0xC0741C)], P(0, ey - 0.08 * u), P(0, ey + 0.1 * u)))
                var sh = ctx; sh.clip(to: lens)
                sh.fill(Path(CGRect(x: cx - 0.12 * u, y: ey - 0.08 * u, width: 0.24 * u, height: 0.05 * u)), with: .color(.white.opacity(0.22)))
                ctx.stroke(lens, with: .color(frame), style: StrokeStyle(lineWidth: L * 1.3, lineJoin: .round))
            }
            var b1 = Path(); b1.move(to: P(-a.eyeX + 0.10 * u, ey - 0.07 * u)); b1.addLine(to: P(a.eyeX - 0.10 * u, ey - 0.07 * u))
            ctx.stroke(b1, with: .color(frame), lineWidth: L * 1.3)
            var b2 = Path(); b2.move(to: P(-a.eyeX + 0.09 * u, ey - 0.03 * u)); b2.addQuadCurve(to: P(a.eyeX - 0.09 * u, ey - 0.03 * u), control: P(0, ey - 0.07 * u))
            ctx.stroke(b2, with: .color(frame), lineWidth: L)
        case .heartGlasses:
            for sx in [-1.0, 1.0] as [CGFloat] {
                let hx = sx * a.eyeX, r = 0.085 * u
                var heart = Path()
                heart.move(to: P(hx, ey + r * 1.05))
                heart.addCurve(to: P(hx, ey - r * 0.55), control1: P(hx - r * 1.7, ey - r * 0.1), control2: P(hx - r * 1.0, ey - r * 1.5))
                heart.addCurve(to: P(hx, ey + r * 1.05), control1: P(hx + r * 1.0, ey - r * 1.5), control2: P(hx + r * 1.7, ey - r * 0.1))
                heart.closeSubpath()
                ctx.fill(heart, with: lin([hex(0xFF7AA8), hex(0xE8195A)], P(hx, ey - r), P(hx, ey + r)))
                ctx.stroke(heart, with: .color(.white), style: StrokeStyle(lineWidth: L * 1.5, lineJoin: .round))
                ctx.fill(ell(hx - r * 0.45, ey - r * 0.35, r * 0.22, r * 0.14), with: .color(.white.opacity(0.7)))
            }
            var br = Path(); br.move(to: P(-a.eyeX + 0.07 * u, ey - 0.04 * u)); br.addLine(to: P(a.eyeX - 0.07 * u, ey - 0.04 * u))
            ctx.stroke(br, with: .color(.white), lineWidth: L * 1.5)
        case .cyberVisor:
            let w = 0.52 * u, h = 0.13 * u
            var v = Path()
            v.move(to: P(-w / 2, ey - h * 0.45))
            v.addQuadCurve(to: P(w / 2, ey - h * 0.45), control: P(0, ey - h * 0.75))
            v.addLine(to: P(w * 0.46, ey + h * 0.35))
            v.addQuadCurve(to: P(-w * 0.46, ey + h * 0.35), control: P(0, ey + h * 0.65))
            v.closeSubpath()
            var glow = ctx; glow.addFilter(.blur(radius: 0.03 * u))
            glow.fill(v, with: .color(hex(0x2EF2FF, 0.7)))
            ctx.fill(v, with: lin([hex(0x0E1B3A), hex(0x163A6B)], P(0, ey - h), P(0, ey + h)))
            var sc = ctx; sc.clip(to: v)
            for i in 0..<5 { sc.fill(Path(CGRect(x: -w, y: ey - h * 0.5 + CGFloat(i) * h * 0.22, width: w * 2, height: h * 0.05)), with: .color(hex(0x2EF2FF, 0.25))) }
            var line = Path(); line.move(to: P(-w * 0.34, ey)); line.addLine(to: P(-w * 0.12, ey)); line.move(to: P(w * 0.12, ey)); line.addLine(to: P(w * 0.34, ey))
            sc.stroke(line, with: .color(hex(0x9CFFFF)), style: StrokeStyle(lineWidth: h * 0.16, lineCap: .round))
            ctx.stroke(v, with: .color(hex(0x9CFFFF)), lineWidth: L * 1.2)
        default: break
        }
    }

    // MARK: - Neck

    static func neck(_ item: MockItem, _ ctx: inout GC, _ a: FlameyArt.Anchors, _ u: CGFloat) {
        let L = lw(u)
        let ny = a.bottom - 0.10 * u
        switch item {
        case .bandana:
            FlameyArt.draw(.bandana, in: &ctx, size: a.bottom * 2, scale: u / (a.bottom * 2))
        case .knitScarf:
            let w = 0.66 * u, h = 0.075 * u
            let g = moved(ctx, 0, ny)
            let tail = moved(g, w * 0.20, h * 0.5, -10)
            let tr = rrect(-h * 0.5, 0, h, h * 2.2, h * 0.25)
            tail.fill(tr, with: .color(hex(0xF2B01E)))
            tail.fill(Path(CGRect(x: -h * 0.5, y: h * 0.8, width: h, height: h * 0.35)), with: .color(hex(0xFFF4DE)))
            tail.stroke(tr, with: .color(INK), lineWidth: L)
            for i in 0..<4 { var f = Path(); f.move(to: P(-h * 0.36 + CGFloat(i) * h * 0.24, h * 2.2)); f.addLine(to: P(-h * 0.36 + CGFloat(i) * h * 0.24, h * 2.6)); tail.stroke(f, with: .color(hex(0xF2B01E)), style: StrokeStyle(lineWidth: L * 1.3, lineCap: .round)) }
            let shape = FlameyArt.band(w: w, h: h, sag: 0.5)
            g.fill(shape, with: .color(hex(0xF2B01E)))
            var st = g; st.clip(to: shape)
            for f in [-0.32, -0.12, 0.08, 0.28] as [CGFloat] { st.fill(Path(CGRect(x: f * w, y: -h, width: w * 0.07, height: h * 3)), with: .color(hex(0xFFF4DE))) }
            for i in 0..<12 {
                var c = Path(); let x = -w * 0.46 + CGFloat(i) * w * 0.083
                c.move(to: P(x, -h * 0.1)); c.addLine(to: P(x + w * 0.02, h * 0.4))
                st.stroke(c, with: .color(hex(0xC98A0E, 0.6)), lineWidth: L * 0.7)
            }
            g.stroke(shape, with: .color(INK), lineWidth: L)
        case .bowTie:
            let g = moved(ctx, 0, ny + 0.01 * u)
            let w = 0.11 * u, h = 0.075 * u
            for sx in [-1.0, 1.0] as [CGFloat] {
                var wing = Path()
                wing.move(to: P(0, 0)); wing.addQuadCurve(to: P(sx * w, -h), control: P(sx * w * 0.4, -h * 0.9))
                wing.addQuadCurve(to: P(sx * w, h), control: P(sx * w * 1.2, 0)); wing.addQuadCurve(to: P(0, 0), control: P(sx * w * 0.4, h * 0.9)); wing.closeSubpath()
                g.fill(wing, with: .color(hex(0xE0243A)))
                var dots = g; dots.clip(to: wing)
                for (dx, dy) in [(0.45, -0.4), (0.75, 0.2), (0.4, 0.45), (0.8, -0.55)] as [(CGFloat, CGFloat)] { dots.fill(circ(sx * w * dx, h * dy, h * 0.11), with: .color(.white)) }
                g.stroke(wing, with: .color(INK), lineWidth: L)
            }
            g.fill(rrect(-w * 0.2, -h * 0.4, w * 0.4, h * 0.8, w * 0.1), with: .color(hex(0xB3152F)))
            g.stroke(rrect(-w * 0.2, -h * 0.4, w * 0.4, h * 0.8, w * 0.1), with: .color(INK), lineWidth: L)
        case .finisherMedal:
            for (sx, c) in [(-1.0, hex(0x2F6BFF)), (1.0, hex(0xE0243A))] as [(CGFloat, Color)] {
                var r = Path()
                r.move(to: P(sx * 0.17 * u, ny - 0.03 * u)); r.addLine(to: P(sx * 0.10 * u, ny - 0.04 * u))
                r.addLine(to: P(sx * 0.005 * u, a.bottom - 0.05 * u)); r.addLine(to: P(sx * 0.055 * u, a.bottom - 0.04 * u)); r.closeSubpath()
                ctx.fill(r, with: .color(c)); ctx.stroke(r, with: .color(INK), lineWidth: L * 0.9)
            }
            let my = a.bottom - 0.03 * u, R = 0.058 * u
            var glow = ctx; glow.addFilter(.blur(radius: R * 0.4)); glow.fill(circ(0, my, R), with: .color(hex(0xFFD24A, 0.7)))
            ctx.fill(circ(0, my, R), with: lin([hex(0xFFF1A8), hex(0xE0A512)], P(-R, my - R), P(R, my + R)))
            ctx.stroke(circ(0, my, R), with: .color(hex(0x8A5A00)), lineWidth: L)
            ctx.stroke(circ(0, my, R * 0.72), with: .color(hex(0xB57F0C)), lineWidth: L * 0.7)
            ctx.fill(FlameyArt.star(0, my, R * 0.5, inner: 0.45), with: .color(hex(0xB57F0C)))
        case .sweatTowel:
            let g = moved(ctx, 0, ny - 0.01 * u)
            let w = 0.60 * u, h = 0.07 * u
            for (sx, rot) in [(-1.0, 6.0), (1.0, -6.0)] as [(CGFloat, Double)] {
                let t = moved(g, sx * w * 0.30, 0, rot)
                let r = rrect(-h * 0.7, 0, h * 1.4, h * 2.4, h * 0.3)
                t.fill(r, with: .color(.white))
                t.fill(Path(CGRect(x: -h * 0.7, y: h * 1.7, width: h * 1.4, height: h * 0.3)), with: .color(hex(0x2FB5E8)))
                t.stroke(r, with: .color(INK), lineWidth: L)
                for i in 0..<3 { var f = Path(); f.move(to: P(-h * 0.5 + CGFloat(i) * h * 0.5, h * 2.4)); f.addLine(to: P(-h * 0.5 + CGFloat(i) * h * 0.5, h * 2.7)); t.stroke(f, with: .color(.white), style: StrokeStyle(lineWidth: L * 1.4, lineCap: .round)) }
            }
            let shape = FlameyArt.band(w: w, h: h, sag: 0.5)
            g.fill(shape, with: .color(hex(0xF7F8FA)))
            var tex = g; tex.clip(to: shape)
            for i in 0..<20 { tex.fill(circ(-w * 0.48 + CGFloat(i) * w * 0.05, h * 0.2 + CGFloat(i % 2) * h * 0.2, h * 0.08), with: .color(hex(0xD8DEE6))) }
            g.stroke(shape, with: .color(INK), lineWidth: L)
        case .goldChain:
            var chain = Path(); chain.move(to: P(-0.22 * u, ny - 0.02 * u)); chain.addQuadCurve(to: P(0.22 * u, ny - 0.02 * u), control: P(0, a.bottom + 0.02 * u))
            ctx.stroke(chain, with: .color(hex(0x8A5A00)), style: StrokeStyle(lineWidth: 0.030 * u, lineCap: .round))
            ctx.stroke(chain, with: .color(hex(0xFFD24A)), style: StrokeStyle(lineWidth: 0.022 * u, lineCap: .round, dash: [0.03 * u, 0.012 * u]))
            let py = a.bottom - 0.03 * u
            var glow = ctx; glow.addFilter(.blur(radius: 0.03 * u)); glow.fill(circ(0, py, 0.06 * u), with: .color(hex(0xFFD24A, 0.7)))
            // Pendant: a little gold flame.
            let fl = FlameBuddyOuterShape(wobble: 0).path(in: CGRect(x: -0.045 * u, y: py - 0.065 * u, width: 0.09 * u, height: 0.11 * u))
            ctx.fill(fl, with: lin([hex(0xFFF3B0), hex(0xFFCF40), hex(0xC98A12)], P(0, py - 0.065 * u), P(0, py + 0.045 * u)))
            ctx.stroke(fl, with: .color(hex(0x8A5A00)), lineWidth: L)
            ctx.fill(circ(-0.012 * u, py - 0.01 * u, 0.01 * u), with: .color(.white.opacity(0.8)))
        case .cameraStrap:
            var strap = Path(); strap.move(to: P(-0.20 * u, ny - 0.03 * u)); strap.addQuadCurve(to: P(0.20 * u, ny - 0.03 * u), control: P(0, a.bottom - 0.02 * u))
            ctx.stroke(strap, with: .color(hex(0xC8433A)), style: StrokeStyle(lineWidth: 0.028 * u, lineCap: .round))
            ctx.stroke(strap, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 0.006 * u, dash: [0.02 * u, 0.02 * u]))
            let cy = a.bottom - 0.04 * u
            let body = rrect(-0.10 * u, cy - 0.055 * u, 0.20 * u, 0.11 * u, 0.02 * u)
            ctx.fill(body, with: .color(hex(0x2B2B33)))
            ctx.fill(Path(CGRect(x: -0.10 * u, y: cy - 0.055 * u, width: 0.20 * u, height: 0.03 * u)), with: .color(hex(0xDDE3EA)))
            ctx.stroke(body, with: .color(INK), lineWidth: L)
            ctx.fill(circ(0.01 * u, cy + 0.01 * u, 0.042 * u), with: .color(hex(0x5B6675)))
            ctx.fill(circ(0.01 * u, cy + 0.01 * u, 0.028 * u), with: lin([hex(0x6FB8FF), hex(0x14285A)], P(0, cy - 0.02 * u), P(0, cy + 0.04 * u)))
            ctx.fill(circ(0.0, cy, 0.008 * u), with: .color(.white))
            ctx.fill(rrect(0.055 * u, cy - 0.075 * u, 0.03 * u, 0.02 * u, 0.004 * u), with: .color(hex(0xE8384F)))
        default: break
        }
    }

    // MARK: - Back (drawn behind the body)

    static func back(_ item: MockItem, _ ctx: inout GC, _ a: FlameyArt.Anchors, _ u: CGFloat) {
        let L = lw(u)
        func cape(_ main: Color, _ dark: Color, trim: Color?, ermine: Bool) {
            // Streams off to his LEFT like a superhero's in the wind.
            let sy = a.bottom - 0.50 * u
            var c = Path()
            c.move(to: P(0.16 * u, sy))
            c.addQuadCurve(to: P(-0.10 * u, sy - 0.04 * u), control: P(0.02 * u, sy - 0.06 * u))
            c.addCurve(to: P(-0.92 * u, sy - 0.10 * u), control1: P(-0.40 * u, sy - 0.10 * u), control2: P(-0.70 * u, sy - 0.22 * u))
            // Wavy trailing edge.
            c.addQuadCurve(to: P(-0.84 * u, sy + 0.10 * u), control: P(-0.80 * u, sy - 0.02 * u))
            c.addQuadCurve(to: P(-0.90 * u, sy + 0.26 * u), control: P(-0.96 * u, sy + 0.18 * u))
            c.addQuadCurve(to: P(-0.74 * u, sy + 0.38 * u), control: P(-0.78 * u, sy + 0.30 * u))
            c.addCurve(to: P(-0.10 * u, a.bottom - 0.04 * u), control1: P(-0.55 * u, sy + 0.44 * u), control2: P(-0.30 * u, a.bottom - 0.02 * u))
            c.addLine(to: P(0.20 * u, a.bottom - 0.10 * u))
            c.closeSubpath()
            ctx.fill(c, with: lin([main, dark], P(-0.2 * u, sy - 0.1 * u), P(-0.8 * u, sy + 0.4 * u)))
            var inner = ctx; inner.clip(to: c)
            for (x0, y0, x1, y1) in [(-0.30, -0.02, -0.80, 0.02), (-0.28, 0.12, -0.78, 0.22), (-0.24, 0.26, -0.66, 0.36)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                var f = Path(); f.move(to: P(x0 * u, sy + y0 * u)); f.addQuadCurve(to: P(x1 * u, sy + y1 * u), control: P((x0 + x1) / 2 * u, sy + (y0 + y1) / 2 * u - 0.06 * u))
                inner.stroke(f, with: .color(dark.opacity(0.7)), style: StrokeStyle(lineWidth: L * 1.2, lineCap: .round))
            }
            inner.fill(Path(ellipseIn: CGRect(x: -0.55 * u, y: sy - 0.10 * u, width: 0.35 * u, height: 0.08 * u)), with: .color(.white.opacity(0.18)))
            if let trim {
                var hem = Path()
                hem.move(to: P(-0.92 * u, sy - 0.10 * u))
                hem.addQuadCurve(to: P(-0.84 * u, sy + 0.10 * u), control: P(-0.80 * u, sy - 0.02 * u))
                hem.addQuadCurve(to: P(-0.90 * u, sy + 0.26 * u), control: P(-0.96 * u, sy + 0.18 * u))
                hem.addQuadCurve(to: P(-0.74 * u, sy + 0.38 * u), control: P(-0.78 * u, sy + 0.30 * u))
                hem.addCurve(to: P(-0.10 * u, a.bottom - 0.04 * u), control1: P(-0.55 * u, sy + 0.44 * u), control2: P(-0.30 * u, a.bottom - 0.02 * u))
                var tc = ctx; tc.clip(to: c)
                tc.stroke(hem, with: .color(trim), style: StrokeStyle(lineWidth: ermine ? 0.10 * u : 0.05 * u, lineCap: .round, lineJoin: .round))
                if ermine {
                    for (x, y) in [(-0.86, -0.02), (-0.88, 0.18), (-0.74, 0.34), (-0.50, 0.40), (-0.28, 0.44)] as [(CGFloat, CGFloat)] {
                        ctx.fill(ell(x * u, sy + y * u, 0.010 * u, 0.018 * u), with: .color(.black))
                    }
                }
                if !ermine {
                    ctx.fill(FlameyArt.star(-0.55 * u, sy + 0.16 * u, 0.07 * u, inner: 0.45), with: .color(trim))
                }
            }
            ctx.stroke(c, with: .color(INK), lineWidth: L)
        }
        switch item {
        case .redCape: cape(hex(0xFF4A5E), hex(0xA8122C), trim: nil, ermine: false)
        case .blueCape: cape(hex(0x4F8BFF), hex(0x1239A8), trim: nil, ermine: false)
        case .royalCape: cape(hex(0x9B4DDB), hex(0x4A1580), trim: .white, ermine: true)
        case .championCape: cape(hex(0xE0243A), hex(0x7E0A1E), trim: hex(0xFFCF40), ermine: false)
        case .victoryBanner:
            let px = 0.24 * u
            var pole = Path(); pole.move(to: P(px, a.bottom - 0.10 * u)); pole.addLine(to: P(px + 0.06 * u, a.topY - 0.26 * u))
            ctx.stroke(pole, with: .color(hex(0x6B4E2A)), style: StrokeStyle(lineWidth: 0.03 * u, lineCap: .round))
            ctx.fill(circ(px + 0.06 * u, a.topY - 0.28 * u, 0.03 * u), with: .color(hex(0xFFCF40)))
            let top = a.topY - 0.22 * u
            var flag = Path()
            flag.move(to: P(px + 0.055 * u, top))
            flag.addQuadCurve(to: P(px + 0.52 * u, top + 0.04 * u), control: P(px + 0.28 * u, top - 0.06 * u))
            flag.addLine(to: P(px + 0.42 * u, top + 0.15 * u))
            flag.addLine(to: P(px + 0.50 * u, top + 0.27 * u))
            flag.addQuadCurve(to: P(px + 0.04 * u, top + 0.26 * u), control: P(px + 0.26 * u, top + 0.18 * u))
            flag.closeSubpath()
            ctx.fill(flag, with: lin([hex(0xE0243A), hex(0xA8122C)], P(px, top), P(px + 0.5 * u, top + 0.2 * u)))
            var trim = ctx; trim.clip(to: flag)
            trim.stroke(flag, with: .color(hex(0xFFCF40)), lineWidth: 0.03 * u)
            ctx.stroke(flag, with: .color(INK), lineWidth: L)
            ctx.fill(FlameyArt.star(px + 0.22 * u, top + 0.11 * u, 0.065 * u, inner: 0.45), with: .color(hex(0xFFCF40)))
        case .goldenWings:
            for sx in [-1.0, 1.0] as [CGFloat] {
                let rx = sx * 0.16 * u, ry = a.bottom - 0.46 * u
                var w = Path()
                w.move(to: P(rx, ry))
                w.addCurve(to: P(sx * 0.86 * u, ry - 0.40 * u), control1: P(sx * 0.34 * u, ry - 0.30 * u), control2: P(sx * 0.62 * u, ry - 0.46 * u))
                w.addQuadCurve(to: P(sx * 0.80 * u, ry - 0.10 * u), control: P(sx * 0.90 * u, ry - 0.24 * u))
                // Scalloped feather tips back to the root.
                let tips: [(CGFloat, CGFloat)] = [(0.80, -0.10), (0.70, 0.04), (0.58, 0.12), (0.45, 0.16), (0.32, 0.14)]
                for i in 1..<tips.count {
                    let p0 = tips[i - 1], p1 = tips[i]
                    w.addQuadCurve(to: P(sx * p1.0 * u, ry + p1.1 * u), control: P(sx * (p0.0 + p1.0) / 2 * u + sx * 0.01 * u, ry + max(p0.1, p1.1) * u + 0.07 * u))
                }
                w.addQuadCurve(to: P(rx, ry + 0.06 * u), control: P(sx * 0.22 * u, ry + 0.14 * u))
                w.closeSubpath()
                var glow = ctx; glow.addFilter(.blur(radius: 0.04 * u)); glow.fill(w, with: .color(hex(0xFFD24A, 0.55)))
                ctx.fill(w, with: lin([hex(0xFFF6C8), hex(0xFFD24A), hex(0xE0A512)], P(rx, ry - 0.4 * u), P(sx * 0.6 * u, ry + 0.2 * u)))
                var inner = ctx; inner.clip(to: w)
                for (i, t) in tips.enumerated() where i > 0 {
                    var f = Path(); f.move(to: P(sx * (t.0 - 0.02) * u, ry + (t.1 - 0.02) * u)); f.addQuadCurve(to: P(sx * (0.28 + CGFloat(i) * 0.1) * u, ry - (0.18 + CGFloat(i) * 0.04) * u), control: P(sx * (t.0 - 0.06) * u, ry - 0.08 * u))
                    inner.stroke(f, with: .color(hex(0xB57F0C, 0.8)), style: StrokeStyle(lineWidth: L, lineCap: .round))
                }
                var top = Path(); top.move(to: P(rx, ry)); top.addCurve(to: P(sx * 0.86 * u, ry - 0.40 * u), control1: P(sx * 0.34 * u, ry - 0.30 * u), control2: P(sx * 0.62 * u, ry - 0.46 * u))
                inner.stroke(top, with: .color(.white.opacity(0.7)), lineWidth: 0.03 * u)
                ctx.stroke(w, with: .color(hex(0x8A5A00)), style: StrokeStyle(lineWidth: L, lineJoin: .round))
            }
        default: break
        }
    }

    static func capeClasp(_ item: MockItem, _ ctx: inout GC, _ a: FlameyArt.Anchors, _ u: CGFloat) {
        let cord: Color = item == .royalCape || item == .championCape ? hex(0xFFCF40) : hex(0x2A1410, 0.8)
        var c = Path(); c.move(to: P(-0.19 * u, a.bottom - 0.17 * u)); c.addQuadCurve(to: P(0.19 * u, a.bottom - 0.17 * u), control: P(0, a.bottom - 0.07 * u))
        ctx.stroke(c, with: .color(cord), style: StrokeStyle(lineWidth: 0.014 * u, lineCap: .round))
        let clasp: Color = item == .redCape ? hex(0xC9D2DC) : hex(0xFFCF40)
        ctx.fill(circ(0, a.bottom - 0.12 * u, 0.028 * u), with: .color(clasp))
        ctx.stroke(circ(0, a.bottom - 0.12 * u, 0.028 * u), with: .color(INK), lineWidth: lw(u))
    }

    // MARK: - Held (right hand; pom-poms use both)

    static func armPath(_ sx: CGFloat, _ a: FlameyArt.Anchors, _ u: CGFloat, up: Bool) -> (Path, CGPoint) {
        let s = P(sx * 0.30 * u, a.bottom - 0.24 * u)
        let hand = up ? P(sx * 0.50 * u, a.bottom - 0.46 * u) : P(sx * 0.50 * u, a.bottom - 0.30 * u)
        var p = Path(); p.move(to: s); p.addQuadCurve(to: hand, control: P(sx * 0.46 * u, a.bottom - 0.22 * u))
        return (p, hand)
    }

    static func drawArm(_ sx: CGFloat, _ ctx: inout GC, _ a: FlameyArt.Anchors, _ u: CGFloat, color: Color, up: Bool) -> CGPoint {
        let (p, hand) = armPath(sx, a, u, up: up)
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 0.07 * u, lineCap: .round))
        ctx.stroke(p, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 0.02 * u, lineCap: .round))
        return hand
    }

    static func held(_ item: MockItem, _ ctx: inout GC, _ a: FlameyArt.Anchors, _ u: CGFloat, arm: Color) {
        let L = lw(u)
        switch item {
        case .pomPoms:
            for sx in [-1.0, 1.0] as [CGFloat] {
                let hand = drawArm(sx, &ctx, a, u, color: arm, up: true)
                let R = 0.10 * u
                for i in 0..<18 {
                    let ang = Double(i) / 18 * 2 * .pi
                    var s = Path(); s.move(to: hand)
                    s.addLine(to: P(hand.x + CGFloat(cos(ang)) * R, hand.y + CGFloat(sin(ang)) * R))
                    ctx.stroke(s, with: .color(i % 2 == 0 ? hex(0xE8384F) : .white), style: StrokeStyle(lineWidth: 0.028 * u, lineCap: .round))
                }
                ctx.fill(circ(hand.x, hand.y, R * 0.45), with: .color(hex(0xFF6B7E)))
            }
        case .foamFinger:
            let hand = drawArm(1, &ctx, a, u, color: arm, up: true)
            let g = moved(ctx, hand.x + 0.01 * u, hand.y, 12)
            let palm = rrect(-0.075 * u, -0.10 * u, 0.15 * u, 0.15 * u, 0.04 * u)
            let finger = rrect(-0.035 * u, -0.26 * u, 0.07 * u, 0.20 * u, 0.035 * u)
            g.fill(finger, with: .color(hex(0xFFD21F))); g.stroke(finger, with: .color(INK), lineWidth: L)
            g.fill(palm, with: .color(hex(0xFFD21F))); g.stroke(palm, with: .color(INK), lineWidth: L)
            g.fill(rrect(-0.07 * u, 0.04 * u, 0.14 * u, 0.06 * u, 0.015 * u), with: .color(hex(0x2F6BFF)))
            let t = Text("#1").font(.system(size: 0.07 * u, weight: .black, design: .rounded)).foregroundColor(hex(0x2F6BFF))
            g.draw(t, at: P(0, -0.025 * u))
        case .megaphone:
            let hand = drawArm(1, &ctx, a, u, color: arm, up: false)
            let g = moved(ctx, hand.x, hand.y - 0.02 * u, -18)
            var cone = Path()
            cone.move(to: P(-0.02 * u, -0.035 * u)); cone.addLine(to: P(0.20 * u, -0.10 * u)); cone.addLine(to: P(0.20 * u, 0.10 * u)); cone.addLine(to: P(-0.02 * u, 0.035 * u)); cone.closeSubpath()
            g.fill(cone, with: .color(.white))
            var st = g; st.clip(to: cone)
            for x in [0.04, 0.12] as [CGFloat] { st.fill(Path(CGRect(x: x * u, y: -0.2 * u, width: 0.04 * u, height: 0.4 * u)), with: .color(hex(0xE8384F))) }
            g.stroke(cone, with: .color(INK), lineWidth: L)
            g.fill(ell(0.20 * u, 0, 0.02 * u, 0.10 * u), with: .color(hex(0xB3152F)))
            g.stroke(ell(0.20 * u, 0, 0.02 * u, 0.10 * u), with: .color(INK), lineWidth: L)
            g.fill(rrect(-0.05 * u, -0.03 * u, 0.04 * u, 0.06 * u, 0.01 * u), with: .color(hex(0x2B2B33)))
            for (i, r) in [0.09, 0.14, 0.19].enumerated() {
                var w = Path(); w.addArc(center: P(0.20 * u, 0), radius: CGFloat(r) * u, startAngle: .degrees(-35), endAngle: .degrees(35), clockwise: false)
                g.stroke(w, with: .color(.white.opacity(0.9 - Double(i) * 0.25)), style: StrokeStyle(lineWidth: L * 1.5, lineCap: .round))
            }
        case .confettiCannon:
            let hand = drawArm(1, &ctx, a, u, color: arm, up: false)
            let g = moved(ctx, hand.x, hand.y, -40)
            let tube = rrect(-0.03 * u, -0.045 * u, 0.20 * u, 0.09 * u, 0.02 * u)
            g.fill(tube, with: lin([hex(0x9B4DFF), hex(0x5A1FB8)], P(0, -0.045 * u), P(0, 0.045 * u)))
            var st = g; st.clip(to: tube)
            for x in [0.02, 0.08, 0.14] as [CGFloat] { var s = Path(); s.move(to: P(x * u, -0.05 * u)); s.addLine(to: P(x * u + 0.04 * u, 0.05 * u)); st.stroke(s, with: .color(hex(0xFFCF40)), lineWidth: 0.015 * u) }
            g.stroke(tube, with: .color(INK), lineWidth: L)
            let colors: [Color] = [hex(0xFF4F7B), hex(0xFFCF40), hex(0x3EE0A0), hex(0x4F8BFF), hex(0xFF9A1F), .white]
            for i in 0..<22 {
                let t = CGFloat(i) / 22
                let ang = (-28.0 + Double((i * 37) % 56)) * .pi / 180
                let d = (0.26 + 0.34 * CGFloat((i * 53) % 17) / 17) * u
                let cx = 0.20 * u + CGFloat(cos(ang)) * d, cy = CGFloat(sin(ang)) * d
                let cc = moved(g, cx, cy, Double(i * 47))
                if i % 3 == 0 { cc.fill(circ(0, 0, 0.012 * u), with: .color(colors[i % colors.count])) }
                else { cc.fill(Path(CGRect(x: -0.014 * u, y: -0.007 * u, width: 0.028 * u, height: 0.014 * u)), with: .color(colors[i % colors.count])) }
                _ = t
            }
        case .whistle:
            let hand = drawArm(1, &ctx, a, u, color: arm, up: false)
            let g = moved(ctx, hand.x + 0.02 * u, hand.y - 0.02 * u, -10)
            let bodyP = circ(0.02 * u, 0.0, 0.045 * u)
            var mouth = Path(); mouth.addRect(CGRect(x: -0.07 * u, y: -0.045 * u, width: 0.09 * u, height: 0.035 * u))
            g.fill(mouth, with: .color(hex(0xC9D2DC))); g.stroke(mouth, with: .color(INK), lineWidth: L)
            g.fill(bodyP, with: lin([hex(0xF2F5F8), hex(0x9AA6B4)], P(0, -0.05 * u), P(0, 0.05 * u)))
            g.stroke(bodyP, with: .color(INK), lineWidth: L)
            g.fill(circ(0.02 * u, 0, 0.015 * u), with: .color(hex(0x5B6675)))
            for (i, ang) in [-40.0, -10.0, 20.0].enumerated() {
                let r = moved(g, -0.08 * u, -0.03 * u, 180 + ang)
                var l = Path(); l.move(to: P(0.02 * u, 0)); l.addLine(to: P(0.07 * u + CGFloat(i % 2) * 0.01 * u, 0))
                r.stroke(l, with: .color(.white), style: StrokeStyle(lineWidth: L * 1.4, lineCap: .round))
            }
            var cord = Path(); cord.move(to: P(0.05 * u, 0.03 * u)); cord.addQuadCurve(to: P(-0.10 * u, 0.12 * u), control: P(0.02 * u, 0.14 * u))
            g.stroke(cord, with: .color(hex(0xE8384F)), style: StrokeStyle(lineWidth: L * 1.2, lineCap: .round))
        case .clipboard:
            let hand = drawArm(1, &ctx, a, u, color: arm, up: false)
            let g = moved(ctx, hand.x + 0.04 * u, hand.y - 0.04 * u, 8)
            let board = rrect(-0.09 * u, -0.12 * u, 0.18 * u, 0.24 * u, 0.015 * u)
            g.fill(board, with: .color(hex(0xB8844A))); g.stroke(board, with: .color(INK), lineWidth: L)
            g.fill(Path(CGRect(x: -0.07 * u, y: -0.09 * u, width: 0.14 * u, height: 0.19 * u)), with: .color(.white))
            for i in 0..<3 {
                let y = -0.05 * u + CGFloat(i) * 0.05 * u
                var ck = Path(); ck.move(to: P(-0.055 * u, y)); ck.addLine(to: P(-0.04 * u, y + 0.013 * u)); ck.addLine(to: P(-0.018 * u, y - 0.015 * u))
                g.stroke(ck, with: .color(hex(0x22A45A)), style: StrokeStyle(lineWidth: L * 1.2, lineCap: .round, lineJoin: .round))
                g.fill(rrect(-0.005 * u, y - 0.005 * u, 0.06 * u, 0.01 * u, 0.005 * u), with: .color(hex(0xB8C2CF)))
            }
            g.fill(rrect(-0.04 * u, -0.14 * u, 0.08 * u, 0.04 * u, 0.01 * u), with: .color(hex(0xC9D2DC)))
            g.stroke(rrect(-0.04 * u, -0.14 * u, 0.08 * u, 0.04 * u, 0.01 * u), with: .color(INK), lineWidth: L)
        default: break
        }
    }

    // MARK: - Costume

    static func ghostSheet(_ ctx: inout GC, _ a: FlameyArt.Anchors, _ u: CGFloat) {
        let L = lw(u)
        var s = Path()
        let b = a.bottom + 0.01 * u
        s.move(to: P(0, a.topY - 0.03 * u))
        s.addCurve(to: P(-0.40 * u, b - 0.20 * u), control1: P(-0.30 * u, a.topY + 0.10 * u), control2: P(-0.40 * u, b - 0.55 * u))
        s.addLine(to: P(-0.44 * u, b))
        for i in 0..<5 {
            let x0 = -0.44 * u + CGFloat(i) * 0.176 * u
            s.addQuadCurve(to: P(x0 + 0.176 * u, b), control: P(x0 + 0.088 * u, b - 0.07 * u))
        }
        s.addLine(to: P(0.40 * u, b - 0.20 * u))
        s.addCurve(to: P(0, a.topY - 0.03 * u), control1: P(0.40 * u, b - 0.55 * u), control2: P(0.30 * u, a.topY + 0.10 * u))
        s.closeSubpath()
        var sh = ctx; sh.addFilter(.shadow(color: .black.opacity(0.35), radius: 0.03 * u, x: 0, y: 0.01 * u))
        sh.fill(s, with: lin([.white, hex(0xE9ECF4)], P(0, a.topY), P(0, b)))
        var folds = ctx; folds.clip(to: s)
        for x in [-0.22, 0.24] as [CGFloat] {
            var f = Path(); f.move(to: P(x * u, a.faceY + 0.14 * u)); f.addQuadCurve(to: P(x * u * 1.1, b), control: P(x * u * 1.3, b - 0.08 * u))
            folds.stroke(f, with: .color(hex(0xC9CFDD)), lineWidth: L * 1.2)
        }
        ctx.stroke(s, with: .color(hex(0xB8C0D2)), lineWidth: L)
        // Eye holes — his glow shows through.
        for sx in [-1.0, 1.0] as [CGFloat] {
            let h = ell(sx * a.eyeX, a.faceY, 0.058 * u, 0.078 * u)
            ctx.fill(h, with: .color(hex(0x1A0A10)))
            ctx.fill(circ(sx * a.eyeX + 0.018 * u, a.faceY - 0.025 * u, 0.017 * u), with: .color(.white.opacity(0.9)))
        }
        ctx.fill(ell(0, a.faceY + 0.13 * u, 0.045 * u, 0.035 * u), with: .color(hex(0x1A0A10)))
        for sx in [-1.0, 1.0] as [CGFloat] { ctx.fill(ell(sx * (a.eyeX + 0.06 * u), a.faceY + 0.09 * u, 0.045 * u, 0.022 * u), with: .color(hex(0xFF8FB0, 0.5))) }
        // Flame peeking out of the top hole.
        let tip = FlameBuddyOuterShape(wobble: 0).path(in: CGRect(x: -0.05 * u, y: a.topY - 0.12 * u, width: 0.10 * u, height: 0.14 * u))
        ctx.fill(tip, with: lin([hex(0xFFF3A0), hex(0xFF8A1F)], P(0, a.topY - 0.12 * u), P(0, a.topY + 0.02 * u)))
    }

    // MARK: - Companions (to his left, on the ground)

    static func companion(_ item: MockItem, _ ctx: inout GC, _ a: FlameyArt.Anchors, _ u: CGFloat, size: CGFloat) {
        let L = lw(u)
        let gx = -0.80 * u
        func face(_ g: GC, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, ink: Color = hex(0x2A1410)) {
            for sx in [-1.0, 1.0] as [CGFloat] {
                g.fill(ell(x + sx * r * 0.42, y, r * 0.16, r * 0.22), with: .color(ink))
                g.fill(circ(x + sx * r * 0.42 + r * 0.05, y - r * 0.08, r * 0.06), with: .color(.white))
            }
            var m = Path(); m.move(to: P(x - r * 0.2, y + r * 0.3)); m.addQuadCurve(to: P(x + r * 0.2, y + r * 0.3), control: P(x, y + r * 0.52))
            g.stroke(m, with: .color(ink), style: StrokeStyle(lineWidth: max(1, r * 0.1), lineCap: .round))
        }
        func spark(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: Color) {
            var gl = ctx; gl.addFilter(.blur(radius: r * 0.5)); gl.fill(circ(x, y, r * 1.1), with: .color(c.opacity(0.75)))
            var st = Path()
            for i in 0..<8 {
                let rr = i % 2 == 0 ? r * 1.25 : r * 0.55
                let ang = -Double.pi / 2 + Double(i) * Double.pi / 4
                let q = P(x + rr * CGFloat(cos(ang)), y + rr * CGFloat(sin(ang)))
                if i == 0 { st.move(to: q) } else { st.addLine(to: q) }
            }
            st.closeSubpath()
            ctx.fill(st, with: .radialGradient(Gradient(colors: [.white, c]), center: P(x, y), startRadius: 0, endRadius: r * 1.2))
            face(ctx, x, y + r * 0.05, r * 0.6)
        }
        switch item {
        case .spark:
            spark(gx, a.bottom - 0.42 * u, 0.09 * u, hex(0xFFD24A))
        case .sparkTrio:
            spark(gx - 0.06 * u, a.bottom - 0.30 * u, 0.075 * u, hex(0xFF7A45))
            spark(gx + 0.10 * u, a.bottom - 0.50 * u, 0.085 * u, hex(0xFFD24A))
            spark(gx - 0.14 * u, a.bottom - 0.64 * u, 0.065 * u, hex(0x5CC8FF))
        case .firefly:
            let x = gx, y = a.bottom - 0.46 * u, r = 0.06 * u
            var gl = ctx; gl.addFilter(.blur(radius: r)); gl.fill(circ(x - r * 0.6, y + r * 0.9, r * 1.6), with: .color(hex(0xD8FF5C, 0.8)))
            for sx in [-1.0, 1.0] as [CGFloat] {
                let wg = moved(ctx, x + sx * r * 0.3, y - r * 0.6, Double(sx) * 35)
                wg.fill(ell(0, -r * 0.6, r * 0.45, r * 0.8), with: .color(Color.white.opacity(0.55)))
                wg.stroke(ell(0, -r * 0.6, r * 0.45, r * 0.8), with: .color(hex(0xB8D6FF)), lineWidth: L * 0.7)
            }
            ctx.fill(ell(x - r * 0.55, y + r * 0.85, r * 0.7, r * 0.6), with: .radialGradient(Gradient(colors: [.white, hex(0xE8FF6B), hex(0x9EE22E)]), center: P(x - r * 0.55, y + r * 0.85), startRadius: 0, endRadius: r * 0.7))
            ctx.fill(circ(x, y, r * 0.75), with: .color(hex(0x3A2F4F)))
            face(ctx, x, y, r * 0.72, ink: .white)
            for sx in [-1.0, 1.0] as [CGFloat] {
                var an = Path(); an.move(to: P(x + sx * r * 0.2, y - r * 0.6)); an.addQuadCurve(to: P(x + sx * r * 0.7, y - r * 1.4), control: P(x + sx * r * 0.2, y - r * 1.3))
                ctx.stroke(an, with: .color(hex(0x3A2F4F)), lineWidth: L)
                ctx.fill(circ(x + sx * r * 0.7, y - r * 1.4, r * 0.12), with: .color(hex(0xE8FF6B)))
            }
        case .lantern:
            let x = gx, y = a.bottom - 0.40 * u, r = 0.12 * u
            var gl = ctx; gl.addFilter(.blur(radius: r * 0.6)); gl.fill(circ(x, y, r * 1.3), with: .color(hex(0xFF9A3C, 0.7)))
            var hang = Path(); hang.move(to: P(x, y - r * 1.05)); hang.addLine(to: P(x, y - r * 1.5))
            ctx.stroke(hang, with: .color(hex(0x2B2B33)), lineWidth: L * 1.2)
            ctx.fill(ell(x, y - r * 1.55, r * 0.14, r * 0.08), with: .color(hex(0x2B2B33)))
            let body = ell(x, y, r * 0.95, r * 0.9)
            ctx.fill(body, with: .radialGradient(Gradient(colors: [hex(0xFFE9A8), hex(0xFF8A2E), hex(0xD9431F)]), center: P(x, y + r * 0.1), startRadius: 0, endRadius: r))
            var ribs = ctx; ribs.clip(to: body)
            for f in [-0.5, 0, 0.5] as [CGFloat] {
                var rb = Path(); rb.move(to: P(x + f * r, y - r)); rb.addQuadCurve(to: P(x + f * r, y + r), control: P(x + f * r * 1.7, y))
                ribs.stroke(rb, with: .color(hex(0xB8321A, 0.6)), lineWidth: L)
            }
            ctx.stroke(body, with: .color(INK), lineWidth: L)
            for dy in [-0.9, 0.9] as [CGFloat] { ctx.fill(rrect(x - r * 0.45, y + dy * r - r * 0.1, r * 0.9, r * 0.2, r * 0.05), with: .color(hex(0x2B2B33))) }
            face(ctx, x, y, r * 0.8)
            var tassel = Path(); tassel.move(to: P(x, y + r)); tassel.addLine(to: P(x, y + r * 1.5))
            ctx.stroke(tassel, with: .color(hex(0xE8384F)), style: StrokeStyle(lineWidth: L * 2, lineCap: .round))
        case .phoenixChick:
            let x = gx, y = a.bottom - 0.10 * u, r = 0.11 * u
            // Flame crest.
            for (dx, h, c) in [(-0.3, 0.7, hex(0xFF4E1A)), (0.0, 0.95, hex(0xFFB020)), (0.3, 0.65, hex(0xFF4E1A))] as [(CGFloat, CGFloat, Color)] {
                let fl = FlameBuddyOuterShape(wobble: 0).path(in: CGRect(x: x + dx * r - r * 0.22, y: y - r * 0.8 - h * r, width: r * 0.44, height: h * r))
                ctx.fill(fl, with: .color(c))
            }
            // Tail
            for (i, ang) in [150.0, 170.0, 190.0].enumerated() {
                let t = moved(ctx, x + r * 0.7, y + r * 0.1, ang - 180)
                t.fill(ell(r * 0.45, 0, r * 0.5, r * 0.14), with: .color(i == 1 ? hex(0xFFD24A) : hex(0xFF7A1F)))
            }
            let body = ell(x, y, r, r * 0.95)
            ctx.fill(body, with: .radialGradient(Gradient(colors: [hex(0xFFD98A), hex(0xFF8A2E), hex(0xE0431A)]), center: P(x - r * 0.2, y - r * 0.3), startRadius: 0, endRadius: r * 1.2))
            ctx.stroke(body, with: .color(INK), lineWidth: L)
            ctx.fill(ell(x + r * 0.35, y + r * 0.2, r * 0.35, r * 0.25), with: .color(hex(0xFFB84A)))
            face(ctx, x - r * 0.1, y - r * 0.15, r * 0.62)
            ctx.fill(poly([P(x - r * 0.18, y + r * 0.08), P(x - r * 0.02, y + r * 0.08), P(x - r * 0.1, y + r * 0.24)]), with: .color(hex(0xFFD21F)))
            for sx in [-0.35, 0.25] as [CGFloat] {
                var leg = Path(); leg.move(to: P(x + sx * r, y + r * 0.85)); leg.addLine(to: P(x + sx * r, y + r * 1.0))
                ctx.stroke(leg, with: .color(hex(0xFFB020)), style: StrokeStyle(lineWidth: L * 1.8, lineCap: .round))
            }
        case .cometPup:
            let x = gx, y = a.bottom - 0.13 * u, r = 0.11 * u
            // Comet tail.
            var tail = Path(); tail.move(to: P(x + r * 0.7, y - r * 0.15)); tail.addQuadCurve(to: P(x + r * 2.2, y - r * 1.2), control: P(x + r * 1.6, y - r * 0.2))
            var tg = ctx; tg.addFilter(.blur(radius: r * 0.15))
            tg.stroke(tail, with: lin([hex(0x9FE3FF), hex(0x9FE3FF, 0)], P(x + r, y), P(x + r * 2.2, y - r * 1.2)), style: StrokeStyle(lineWidth: r * 0.55, lineCap: .round))
            ctx.fill(circ(x + r * 2.2, y - r * 1.2, r * 0.18), with: .color(.white))
            let body = ell(x + r * 0.2, y + r * 0.35, r * 0.85, r * 0.55)
            ctx.fill(body, with: lin([hex(0xE8F6FF), hex(0x8CC8F2)], P(x, y), P(x, y + r)))
            ctx.stroke(body, with: .color(hex(0x2A4A6B)), lineWidth: L)
            let head = circ(x - r * 0.35, y - r * 0.25, r * 0.62)
            ctx.fill(head, with: lin([.white, hex(0xBFE2FA)], P(x, y - r), P(x, y + r * 0.3)))
            ctx.stroke(head, with: .color(hex(0x2A4A6B)), lineWidth: L)
            for sx in [-1.0, 1.0] as [CGFloat] {
                let e = moved(ctx, x - r * 0.35 + sx * r * 0.48, y - r * 0.62, Double(sx) * 25)
                e.fill(ell(0, 0, r * 0.18, r * 0.32), with: .color(hex(0x5B8FC8)))
            }
            face(ctx, x - r * 0.35, y - r * 0.28, r * 0.5, ink: hex(0x14283F))
            ctx.fill(ell(x - r * 0.35, y - r * 0.08, r * 0.08, r * 0.06), with: .color(hex(0x14283F)))
            for sx in [-0.35, 0.55] as [CGFloat] { ctx.fill(rrect(x + sx * r - r * 0.12, y + r * 0.7, r * 0.24, r * 0.22, r * 0.1), with: .color(hex(0xBFE2FA))) }
            ctx.fill(FlameyArt.star(x + r * 0.2, y + r * 0.35, r * 0.18, inner: 0.45), with: .color(hex(0xFFD24A)))
        case .friendlyGhost:
            let x = gx, y = a.bottom - 0.34 * u, r = 0.13 * u
            var s = Path()
            s.move(to: P(x - r, y + r * 0.9))
            s.addLine(to: P(x - r, y))
            s.addArc(center: P(x, y), radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            s.addLine(to: P(x + r, y + r * 0.9))
            for i in 0..<4 {
                let x0 = x + r - CGFloat(i) * r * 0.5
                s.addQuadCurve(to: P(x0 - r * 0.5, y + r * 0.9), control: P(x0 - r * 0.25, y + r * (i % 2 == 0 ? 1.25 : 0.6)))
            }
            s.closeSubpath()
            var gl = ctx; gl.addFilter(.blur(radius: r * 0.35)); gl.fill(s, with: .color(hex(0xBFFFEA, 0.6)))
            ctx.fill(s, with: lin([.white, hex(0xDDE6F5)], P(x, y - r), P(x, y + r)))
            ctx.stroke(s, with: .color(hex(0xAAB4CC)), lineWidth: L)
            face(ctx, x, y, r * 0.8)
            for sx in [-1.0, 1.0] as [CGFloat] { ctx.fill(ell(x + sx * r * 0.6, y + r * 0.2, r * 0.13, r * 0.07), with: .color(hex(0xFF8FB0, 0.6))) }
        default: break
        }
    }

    // MARK: - Trails (he's mid-hop, moving RIGHT; trail streams left)

    /// A point on the trail curve: t=0 ground far left, t=1 at his back.
    static func trailPoint(_ t: CGFloat, _ a: FlameyArt.Anchors, _ u: CGFloat, lift: CGFloat) -> CGPoint {
        let p0 = P(-1.30 * u, a.bottom - 0.02 * u)
        let c = P(-0.80 * u, a.bottom - 0.52 * u - lift * 0.6)
        let p1 = P(0.02 * u, a.bottom - 0.40 * u - lift)
        let mt = 1 - t
        return P(mt * mt * p0.x + 2 * mt * t * c.x + t * t * p1.x, mt * mt * p0.y + 2 * mt * t * c.y + t * t * p1.y)
    }

    static func trailCurve(_ a: FlameyArt.Anchors, _ u: CGFloat, lift: CGFloat, from: CGFloat = 0, to: CGFloat = 1, dy: CGFloat = 0) -> Path {
        var p = Path()
        for i in 0...40 {
            let t = from + (to - from) * CGFloat(i) / 40
            var q = trailPoint(t, a, u, lift: lift); q.y += dy
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        return p
    }

    static func trail(_ item: MockItem, _ ctx: inout GC, _ a: FlameyArt.Anchors, _ u: CGFloat, lift: CGFloat, size: CGFloat) {
        let L = lw(u)
        func pt(_ t: CGFloat) -> CGPoint { trailPoint(t, a, u, lift: lift) }
        switch item {
        case .emberSparks:
            let cols = [hex(0xFFD24A), hex(0xFF8A1F), hex(0xFF4E1A)]
            for i in 0..<16 {
                let t = 0.12 + CGFloat(i) / 16 * 0.86
                var q = pt(t)
                q.y += CGFloat((i * 37) % 11 - 5) * 0.012 * u
                let r = (0.014 + 0.026 * t) * u
                var gl = ctx; gl.addFilter(.blur(radius: r)); gl.fill(circ(q.x, q.y, r * 1.6), with: .color(cols[i % 3].opacity(0.7)))
                if i % 4 == 1 { ctx.fill(FlameyArt.star(q.x, q.y, r * 2.2, inner: 0.22), with: .color(hex(0xFFF3B0))) }
                else { ctx.fill(circ(q.x, q.y, r), with: .color(cols[i % 3])) }
            }
        case .dustPuffs:
            let puffs: [(CGFloat, CGFloat)] = [(0.0, 1.0), (0.18, 0.8), (0.36, 0.6), (0.56, 0.45), (0.74, 0.32)]
            for (t, s) in puffs {
                let q = pt(t)
                for (dx, dy, r) in [(-0.6, 0.1, 0.55), (0.0, -0.25, 0.7), (0.6, 0.05, 0.5), (0.2, 0.3, 0.45), (-0.25, 0.3, 0.45)] as [(CGFloat, CGFloat, CGFloat)] {
                    let rr = r * s * 0.12 * u
                    ctx.fill(circ(q.x + dx * s * 0.12 * u, q.y + dy * s * 0.12 * u, rr), with: .color(hex(0xD9C8B0, 0.35 + 0.5 * Double(s))))
                }
                ctx.fill(circ(q.x - 0.02 * u * s, q.y - 0.03 * u * s, 0.025 * u * s), with: .color(.white.opacity(0.4)))
            }
        case .speedLines:
            let base = a.bottom - 0.40 * u - lift
            let lines: [(CGFloat, CGFloat, CGFloat)] = [(-0.28, 0.55, 0.9), (-0.14, 0.85, 0.7), (0.0, 0.65, 1.0), (0.14, 0.95, 0.8), (0.28, 0.5, 0.6), (-0.40, 0.35, 0.5)]
            for (dy, len, al) in lines {
                let y = base + dy * u
                let x1 = -0.42 * u
                var l = Path(); l.move(to: P(x1, y)); l.addLine(to: P(x1 - len * u, y))
                ctx.stroke(l, with: lin([.white.opacity(0.95 * Double(al)), .white.opacity(0)], P(x1, y), P(x1 - len * u, y)), style: StrokeStyle(lineWidth: 0.022 * u, lineCap: .round))
            }
        case .cometTail:
            var tail = Path()
            let tip = pt(1)
            tail.move(to: P(tip.x, tip.y - 0.16 * u))
            tail.addQuadCurve(to: pt(0.0), control: P(-0.75 * u, a.bottom - 0.70 * u - lift * 0.6))
            tail.addQuadCurve(to: P(tip.x, tip.y + 0.16 * u), control: P(-0.70 * u, a.bottom - 0.36 * u - lift * 0.6))
            tail.closeSubpath()
            var gl = ctx; gl.addFilter(.blur(radius: 0.04 * u))
            gl.fill(tail, with: lin([hex(0x7FE9FF, 0.9), hex(0x4F7BFF, 0.0)], tip, pt(0)))
            ctx.fill(tail, with: lin([.white.opacity(0.85), hex(0x9FE3FF, 0.5), hex(0x4F7BFF, 0.0)], tip, pt(0.05)))
            for i in 0..<6 { let q = pt(0.2 + CGFloat(i) * 0.12); ctx.fill(circ(q.x, q.y + CGFloat(i % 2 == 0 ? -1 : 1) * 0.07 * u, 0.012 * u), with: .color(.white)) }
        case .smokeRings:
            for (i, t) in [0.12, 0.34, 0.56, 0.78].enumerated() {
                let q = pt(CGFloat(t))
                let s = 1.0 - CGFloat(t) * 0.55
                let rr = ell(q.x, q.y, 0.14 * u * s, 0.10 * u * s)
                ctx.stroke(rr, with: .color(hex(0xD6D0E2, 0.45 + 0.15 * Double(i))), lineWidth: 0.045 * u * s)
                ctx.stroke(rr, with: .color(.white.opacity(0.35)), lineWidth: 0.008 * u * s)
            }
        case .starTrail:
            for i in 0..<9 {
                let t = 0.05 + CGFloat(i) / 9 * 0.9
                var q = pt(t); q.y += CGFloat(i % 2 == 0 ? -1 : 1) * 0.04 * u
                let r = (0.02 + 0.05 * t) * u
                var gl = ctx; gl.addFilter(.blur(radius: r * 0.4)); gl.fill(circ(q.x, q.y, r), with: .color(hex(0xFFD24A, 0.6)))
                let g = moved(ctx, q.x, q.y, Double(i * 23))
                g.fill(FlameyArt.star(0, 0, r, inner: 0.45), with: lin([hex(0xFFF6C8), hex(0xFFC21F)], P(0, -r), P(0, r)))
                g.stroke(FlameyArt.star(0, 0, r, inner: 0.45), with: .color(hex(0xD98A00)), style: StrokeStyle(lineWidth: L * 0.7, lineJoin: .round))
            }
        case .rainbowStreak:
            let cols = [hex(0xFF4F5E), hex(0xFF9A1F), hex(0xFFE14D), hex(0x3EE08A), hex(0x3FA9FF), hex(0x9B6BFF)]
            let w = 0.034 * u
            for (i, c) in cols.enumerated() {
                let p = trailCurve(a, u, lift: lift, from: 0.0, to: 0.97, dy: (CGFloat(i) - 2.5) * w)
                ctx.stroke(p, with: lin([c.opacity(0), c], pt(0), pt(0.6)), style: StrokeStyle(lineWidth: w + 0.5, lineCap: .butt))
            }
            let q = pt(0.12)
            for (dx, dy, r) in [(-0.05, 0.02, 0.06), (0.02, -0.02, 0.07), (0.08, 0.03, 0.05)] as [(CGFloat, CGFloat, CGFloat)] {
                ctx.fill(circ(q.x + dx * u, q.y + dy * u + 0.06 * u, r * u), with: .color(.white.opacity(0.95)))
            }
        case .lightningTrail:
            var z = Path()
            let n = 9
            for i in 0...n {
                let t = CGFloat(i) / CGFloat(n)
                var q = pt(0.05 + t * 0.93)
                q.y += (i % 2 == 0 ? -1 : 1) * 0.07 * u * (i == n ? 0 : 1)
                if i == 0 { z.move(to: q) } else { z.addLine(to: q) }
            }
            var gl = ctx; gl.addFilter(.blur(radius: 0.03 * u))
            gl.stroke(z, with: .color(hex(0x7FE9FF)), style: StrokeStyle(lineWidth: 0.07 * u, lineCap: .round, lineJoin: .round))
            ctx.stroke(z, with: .color(hex(0xFFE14D)), style: StrokeStyle(lineWidth: 0.035 * u, lineCap: .round, lineJoin: .round))
            ctx.stroke(z, with: .color(.white), style: StrokeStyle(lineWidth: 0.012 * u, lineCap: .round, lineJoin: .round))
            var fork = Path(); let f0 = pt(0.4); fork.move(to: P(f0.x, f0.y + 0.07 * u)); fork.addLine(to: P(f0.x - 0.08 * u, f0.y + 0.2 * u)); fork.addLine(to: P(f0.x - 0.04 * u, f0.y + 0.22 * u)); fork.addLine(to: P(f0.x - 0.12 * u, f0.y + 0.34 * u))
            ctx.stroke(fork, with: .color(hex(0xFFE14D)), style: StrokeStyle(lineWidth: 0.018 * u, lineCap: .round, lineJoin: .round))
        case .fireworks:
            let bursts: [(CGFloat, CGFloat, Color)] = [(0.25, 0.14, hex(0xFF4F7B)), (0.5, 0.18, hex(0xFFD24A)), (0.78, 0.11, hex(0x5CC8FF))]
            for (t, r0, c) in bursts {
                var q = pt(t); q.y -= 0.12 * u
                let r = r0 * u
                var gl = ctx; gl.addFilter(.blur(radius: r * 0.3)); gl.fill(circ(q.x, q.y, r * 0.5), with: .color(c.opacity(0.5)))
                for i in 0..<12 {
                    let ang = Double(i) / 12 * 2 * .pi
                    let d0 = r * 0.35, d1 = r
                    var l = Path(); l.move(to: P(q.x + CGFloat(cos(ang)) * d0, q.y + CGFloat(sin(ang)) * d0)); l.addLine(to: P(q.x + CGFloat(cos(ang)) * d1, q.y + CGFloat(sin(ang)) * d1))
                    ctx.stroke(l, with: .color(c), style: StrokeStyle(lineWidth: 0.012 * u, lineCap: .round))
                    ctx.fill(circ(q.x + CGFloat(cos(ang)) * d1 * 1.12, q.y + CGFloat(sin(ang)) * d1 * 1.12, 0.01 * u), with: .color(.white))
                }
                ctx.fill(circ(q.x, q.y, 0.018 * u), with: .color(.white))
            }
            ctx.stroke(trailCurve(a, u, lift: lift, from: 0.0, to: 0.95), with: .color(hex(0xFFD24A, 0.35)), style: StrokeStyle(lineWidth: 0.01 * u, dash: [0.02 * u, 0.03 * u]))
        case .phoenixFeathers:
            for i in 0..<8 {
                let t = 0.08 + CGFloat(i) / 8 * 0.86
                var q = pt(t); q.y += CGFloat((i * 29) % 9 - 4) * 0.018 * u
                let s = 0.6 + 0.6 * t
                let g = moved(ctx, q.x, q.y, Double(-70 + (i * 41) % 60))
                var f = Path()
                f.move(to: P(0, -0.10 * u * s))
                f.addQuadCurve(to: P(0, 0.10 * u * s), control: P(0.07 * u * s, 0))
                f.addQuadCurve(to: P(0, -0.10 * u * s), control: P(-0.07 * u * s, 0))
                var gl = g; gl.addFilter(.blur(radius: 0.02 * u)); gl.fill(f, with: .color(hex(0xFF7A1F, 0.6)))
                g.fill(f, with: lin([hex(0xFFE36B), hex(0xFF7A1F), hex(0xE0243A)], P(0, -0.1 * u * s), P(0, 0.1 * u * s)))
                var spine = Path(); spine.move(to: P(0, -0.08 * u * s)); spine.addLine(to: P(0, 0.12 * u * s))
                g.stroke(spine, with: .color(hex(0x8A2A0A, 0.8)), lineWidth: L * 0.8)
            }
        case .auroraRibbon:
            for (i, c) in [hex(0x3DFFB0), hex(0x55C8FF), hex(0xB46BFF)].enumerated() {
                var p = Path()
                for j in 0...40 {
                    let t = CGFloat(j) / 40 * 0.97
                    var q = pt(t); q.y += CGFloat(i) * 0.05 * u + 0.05 * u * sin(t * 12 + CGFloat(i))
                    if j == 0 { p.move(to: q) } else { p.addLine(to: q) }
                }
                var gl = ctx; gl.addFilter(.blur(radius: 0.03 * u))
                gl.stroke(p, with: lin([c.opacity(0), c.opacity(0.85)], pt(0), pt(0.7)), style: StrokeStyle(lineWidth: 0.11 * u, lineCap: .round))
                ctx.stroke(p, with: lin([c.opacity(0), c.opacity(0.9)], pt(0), pt(0.7)), style: StrokeStyle(lineWidth: 0.03 * u, lineCap: .round))
            }
        case .meteorShower:
            let ms: [(CGFloat, CGFloat, CGFloat)] = [(-0.55, -0.80, 1.0), (-0.95, -0.55, 0.75), (-0.35, -0.40, 0.6), (-1.15, -0.95, 0.55), (-0.80, -0.20, 0.5)]
            for (x, y, s) in ms {
                let hx = x * u, hy = a.bottom + y * u - lift * 0.5
                var tl = Path(); tl.move(to: P(hx, hy)); tl.addLine(to: P(hx - 0.30 * u * s, hy - 0.22 * u * s))
                var gl = ctx; gl.addFilter(.blur(radius: 0.015 * u))
                gl.stroke(tl, with: lin([hex(0xFFB547), hex(0xFF4E1A, 0)], P(hx, hy), P(hx - 0.3 * u * s, hy - 0.22 * u * s)), style: StrokeStyle(lineWidth: 0.05 * u * s, lineCap: .round))
                ctx.stroke(tl, with: lin([.white, hex(0xFFD24A, 0)], P(hx, hy), P(hx - 0.3 * u * s, hy - 0.22 * u * s)), style: StrokeStyle(lineWidth: 0.018 * u * s, lineCap: .round))
                ctx.fill(circ(hx, hy, 0.028 * u * s), with: .color(.white))
                ctx.fill(circ(hx, hy, 0.018 * u * s), with: .color(hex(0xFFE9A8)))
            }
        default: break
        }
    }
}
