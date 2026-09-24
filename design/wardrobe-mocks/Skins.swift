import SwiftUI

// MOCK — wardrobe flame colours (streak-days family).

func hex(_ v: UInt32, _ o: Double = 1) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255).opacity(o)
}

enum SkinFX: Hashable { case sheen, stars, denseStars, lava, ribbons, candy, halo, embers, nebula, prismRim, hotCore }

enum SkinTier: String { case solid = "Solids", gradient = "Gradients", legendary = "Legendary" }

struct FlameSkin: Hashable {
    var id: String
    var name: String
    var days: Int
    var tier: SkinTier
    var outer: [Color]
    var inner: [Color]
    var glow: Color
    var core: Color = hex(0xFFF3B0)
    var eye: Color? = nil
    var rim: Color? = nil
    var fx: Set<SkinFX> = []
    var angular: Bool = false
    var start: UnitPoint = .top
    var end: UnitPoint = .bottom
    var bodyOpacity: Double = 1
    var innerOpacity: Double? = nil
    var swatch: [Color] { outer }
}

extension FlameSkin {
    static let classic = FlameSkin(id: "classic", name: "Classic", days: 0, tier: .solid,
        outer: [.white, hex(0xFFE047), .orange, hex(0xFF3319)], inner: [.white, hex(0xFFEB4D), hex(0xFF8014)], glow: .orange)

    // MARK: Solids
    static let ember = FlameSkin(id: "ember", name: "Ember", days: 3, tier: .solid,
        outer: [hex(0xFFB066), hex(0xF2561D), hex(0xA3200D)], inner: [hex(0xFFE2B0), hex(0xFF8F40)], glow: hex(0xFF5A1F))
    static let tangerine = FlameSkin(id: "tangerine", name: "Tangerine", days: 5, tier: .solid,
        outer: [hex(0xFFD98A), hex(0xFFA024), hex(0xEE6A00)], inner: [hex(0xFFF3CF), hex(0xFFC766)], glow: hex(0xFF9A1F))
    static let ruby = FlameSkin(id: "ruby", name: "Ruby", days: 7, tier: .solid,
        outer: [hex(0xFF7A96), hex(0xE3194B), hex(0x8A0A2C)], inner: [hex(0xFFD2DC), hex(0xFF7593)], glow: hex(0xFF2D55), core: hex(0xFFC2D0))
    static let coral = FlameSkin(id: "coral", name: "Coral", days: 10, tier: .solid,
        outer: [hex(0xFFC0A8), hex(0xFF7F5E), hex(0xD8443A)], inner: [hex(0xFFEDE4), hex(0xFFAC92)], glow: hex(0xFF7A5C), core: hex(0xFFE0D0))
    static let sunflower = FlameSkin(id: "sunflower", name: "Sunflower", days: 14, tier: .solid,
        outer: [hex(0xFFF59A), hex(0xFFD420), hex(0xE59F00)], inner: [hex(0xFFFDE3), hex(0xFFEC7A)], glow: hex(0xFFD21F))
    static let mint = FlameSkin(id: "mint", name: "Mint", days: 21, tier: .solid,
        outer: [hex(0xC6FFE6), hex(0x3FE0A2), hex(0x0C9A6A)], inner: [hex(0xF0FFF8), hex(0xA2F6D2)], glow: hex(0x3EE0A0), core: hex(0xCFFFEA),
        eye: hex(0x0B3326))
    static let sapphire = FlameSkin(id: "sapphire", name: "Sapphire", days: 30, tier: .solid,
        outer: [hex(0xA8D8FF), hex(0x2F7BFF), hex(0x1236B0)], inner: [hex(0xE8F4FF), hex(0x93C7FF)], glow: hex(0x3D8BFF), core: hex(0xCFE6FF),
        eye: hex(0x0A1640))
    static let violet = FlameSkin(id: "violet", name: "Violet", days: 45, tier: .solid,
        outer: [hex(0xDDB6FF), hex(0x9B4DFF), hex(0x541CB0)], inner: [hex(0xF5EAFF), hex(0xCCA3FF)], glow: hex(0x9B4DFF), core: hex(0xE8D6FF),
        eye: hex(0x220A45))
    static let rose = FlameSkin(id: "rose", name: "Rose", days: 50, tier: .solid,
        outer: [hex(0xFFC8E0), hex(0xFF5FA2), hex(0xC21A69)], inner: [hex(0xFFEEF6), hex(0xFFA3CC)], glow: hex(0xFF5FA2), core: hex(0xFFD8EA),
        eye: hex(0x3D0A22))
    static let teal = FlameSkin(id: "teal", name: "Teal", days: 60, tier: .solid,
        outer: [hex(0xA6F4F2), hex(0x17C0BE), hex(0x08707C)], inner: [hex(0xE6FFFE), hex(0x86EBE8)], glow: hex(0x19C2C0), core: hex(0xCFFFFD),
        eye: hex(0x06302F))
    static let arctic = FlameSkin(id: "arctic", name: "Arctic", days: 75, tier: .solid,
        outer: [.white, hex(0xD6EEFF), hex(0x86BCEA)], inner: [.white, hex(0xE8F6FF)], glow: hex(0xBFE6FF), core: .white,
        eye: hex(0x10284A), rim: Color.white.opacity(0.7))
    static let midnight = FlameSkin(id: "midnight", name: "Midnight", days: 90, tier: .solid,
        outer: [hex(0x4557C0), hex(0x1B2470), hex(0x0A0F36)], inner: [hex(0xF0FAFF), hex(0x76D3FF)], glow: hex(0x4A6BFF), core: hex(0x9FE2FF),
        eye: hex(0x0A1030), rim: hex(0x9FC6FF, 0.55), innerOpacity: 1)

    // MARK: Gradients
    static let sunset = FlameSkin(id: "sunset", name: "Sunset", days: 100, tier: .gradient,
        outer: [hex(0xFFE07A), hex(0xFF7A45), hex(0xE8386F), hex(0x6E2A8C)], inner: [hex(0xFFF5D1), hex(0xFFB478)], glow: hex(0xFF6A5C))
    static let aurora = FlameSkin(id: "aurora", name: "Aurora", days: 120, tier: .gradient,
        outer: [hex(0x8CFFBE), hex(0x2FD3B5), hex(0x4F7BFF), hex(0x9B4DFF)], inner: [hex(0xF2FFF8), hex(0xA6F5D6)], glow: hex(0x4FD9C0), core: hex(0xD6FFEF),
        eye: hex(0x10203A))
    static let ocean = FlameSkin(id: "ocean", name: "Ocean", days: 150, tier: .gradient,
        outer: [hex(0xB0F4FF), hex(0x1FB5E8), hex(0x1765C9), hex(0x0B2A6B)], inner: [hex(0xEFFCFF), hex(0x96E6FF)], glow: hex(0x1FB5E8), core: hex(0xCFF6FF),
        eye: hex(0x06203F))
    static let lavaLamp = FlameSkin(id: "lava", name: "Lava Lamp", days: 180, tier: .gradient,
        outer: [hex(0xFF9A4A), hex(0xE8386F), hex(0x6E1A5C)], inner: [hex(0xFFEDB8), hex(0xFFB24D)], glow: hex(0xFF5A6A), fx: [.lava])
    static let galaxy = FlameSkin(id: "galaxy", name: "Galaxy", days: 200, tier: .gradient,
        outer: [hex(0x9C7BFF), hex(0x4B22B8), hex(0x1A0A4A)], inner: [hex(0xF6EEFF), hex(0xBFA3FF)], glow: hex(0x7E5BFF), core: hex(0xE0D2FF),
        eye: hex(0x1A0A40), rim: hex(0xC9B6FF, 0.5), fx: [.stars])
    static let candy = FlameSkin(id: "candy", name: "Candy", days: 250, tier: .gradient,
        outer: [hex(0xFFB8E8), hex(0xC9A6FF), hex(0x8ED8FF)], inner: [.white, hex(0xFFDDF2)], glow: hex(0xFF9FDC), core: hex(0xFFE6F6),
        eye: hex(0x3A1438), fx: [.candy], start: .topLeading, end: .bottomTrailing)
    static let northernLights = FlameSkin(id: "northern", name: "Northern Lights", days: 300, tier: .gradient,
        outer: [hex(0x2A3F8F), hex(0x121A4F), hex(0x070B26)], inner: [hex(0xEDFFF6), hex(0x8DFFC8)], glow: hex(0x38E6A0), core: hex(0xB8FFDD),
        eye: hex(0x0A1A20), rim: hex(0x8DFFC8, 0.5), fx: [.ribbons], innerOpacity: 1)

    // MARK: Legendary
    static let gold = FlameSkin(id: "gold", name: "Gold", days: 365, tier: .legendary,
        outer: [hex(0xFFF7C8), hex(0xFFD24A), hex(0xD9970C), hex(0x8A5A00)], inner: [hex(0xFFFDEB), hex(0xFFE488)], glow: hex(0xFFC83A), core: hex(0xFFF3B0),
        eye: hex(0x3A2400), rim: hex(0xFFF6C8, 0.8), fx: [.sheen, .embers], start: .topLeading, end: .bottom)
    static let prism = FlameSkin(id: "prism", name: "Prism", days: 500, tier: .legendary,
        outer: [hex(0xFF5A5A), hex(0xFFB03A), hex(0xFFE94A), hex(0x4ADE80), hex(0x38BDF8), hex(0x8B5CF6), hex(0xF472B6)],
        inner: [.white, hex(0xFFF0FA)], glow: .white, core: .white, eye: hex(0x2A1030), rim: Color.white.opacity(0.75),
        fx: [.sheen, .halo], angular: true)
    static let cosmic = FlameSkin(id: "cosmic", name: "Cosmic", days: 730, tier: .legendary,
        outer: [hex(0x3A1A80), hex(0x160A40), hex(0x05030F)], inner: [.white, hex(0xCDB8FF)], glow: hex(0x8E6BFF), core: hex(0xD8C8FF),
        eye: hex(0x14082E), rim: hex(0xD6C4FF, 0.65), fx: [.denseStars, .nebula, .halo], innerOpacity: 1)
    static let eternal = FlameSkin(id: "eternal", name: "Eternal", days: 1000, tier: .legendary,
        outer: [.white, hex(0xFFF8DC), hex(0xFFDE8A), hex(0xFFB547)], inner: [.white, .white], glow: hex(0xFFE8A8), core: .white,
        eye: hex(0x3A2410), rim: Color.white.opacity(0.9), fx: [.halo, .embers, .hotCore], innerOpacity: 1)

    // MARK: Spooky
    static let phantom = FlameSkin(id: "phantom", name: "Phantom", days: 0, tier: .gradient,
        outer: [hex(0xF2FFFB), hex(0xB8F0E6), hex(0x6FA8C8)], inner: [.white, hex(0xE0FBF4)], glow: hex(0x9FFFE0), core: hex(0xE8FFF8),
        eye: hex(0x10283A), rim: Color.white.opacity(0.8), bodyOpacity: 0.72)

    static let solids: [FlameSkin] = [ember, tangerine, ruby, coral, sunflower, mint, sapphire, violet, rose, teal, arctic, midnight]
    static let gradients: [FlameSkin] = [sunset, aurora, ocean, lavaLamp, galaxy, candy, northernLights]
    static let legendaries: [FlameSkin] = [gold, prism, cosmic, eternal]
}

/// Clip everything to the outer silhouette, in the outer shape's own frame.
struct SkinOuterFX: View {
    let skin: FlameSkin?
    let size: CGFloat

    var body: some View {
        if let skin, !skin.fx.isEmpty {
            Canvas { ctx, sz in
                let w = sz.width, h = sz.height
                let shape = FlameBuddyOuterShape(wobble: 0).path(in: CGRect(origin: .zero, size: sz))
                ctx.clip(to: shape)
                func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
                if skin.fx.contains(.nebula) {
                    var g = ctx
                    g.addFilter(.blur(radius: size * 0.05))
                    g.fill(Path(ellipseIn: CGRect(x: 0.05 * w, y: 0.45 * h, width: 0.55 * w, height: 0.30 * h)), with: .color(hex(0xB5389A, 0.55)))
                    g.fill(Path(ellipseIn: CGRect(x: 0.45 * w, y: 0.25 * h, width: 0.45 * w, height: 0.30 * h)), with: .color(hex(0x3A6BFF, 0.5)))
                }
                if skin.fx.contains(.lava) {
                    let blobs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0.22, 0.60, 0.16, 0.11), (0.70, 0.40, 0.12, 0.10), (0.46, 0.22, 0.08, 0.07), (0.78, 0.74, 0.10, 0.07), (0.30, 0.86, 0.12, 0.06)]
                    for b in blobs {
                        let r = CGRect(x: (b.0 - b.2) * w, y: (b.1 - b.3) * h, width: b.2 * 2 * w, height: b.3 * 2 * h)
                        ctx.fill(Path(ellipseIn: r), with: .linearGradient(Gradient(colors: [hex(0xFFE36B), hex(0xFFA23A)]), startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
                        ctx.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * 0.2, y: r.minY + r.height * 0.15, width: r.width * 0.3, height: r.height * 0.25)), with: .color(.white.opacity(0.45)))
                    }
                }
                if skin.fx.contains(.ribbons) {
                    let cols: [(Color, CGFloat, CGFloat)] = [(hex(0x3DFFB0, 0.85), 0.28, 0.0), (hex(0xFF6FD8, 0.6), 0.44, 1.3), (hex(0x55C8FF, 0.7), 0.60, 2.2)]
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
                if skin.fx.contains(.candy) {
                    var g = ctx
                    g.rotate(by: .degrees(-30))
                    for i in -6...10 {
                        let x = CGFloat(i) * 0.16 * w
                        g.fill(Path(CGRect(x: x, y: -h, width: 0.05 * w, height: h * 3)), with: .color(.white.opacity(0.35)))
                    }
                }
                if skin.fx.contains(.stars) || skin.fx.contains(.denseStars) {
                    let dense = skin.fx.contains(.denseStars)
                    let pts: [(CGFloat, CGFloat, CGFloat)] = [
                        (0.50, 0.14, 1.0), (0.40, 0.30, 0.6), (0.62, 0.34, 0.8), (0.30, 0.50, 0.9), (0.74, 0.55, 0.6),
                        (0.18, 0.68, 0.7), (0.84, 0.70, 0.9), (0.24, 0.84, 0.5), (0.70, 0.88, 0.7), (0.54, 0.46, 0.5),
                        (0.12, 0.76, 0.5), (0.88, 0.80, 0.5)]
                    let extra: [(CGFloat, CGFloat, CGFloat)] = dense ? [(0.45, 0.22, 0.4), (0.58, 0.24, 0.5), (0.35, 0.40, 0.4), (0.68, 0.44, 0.45),
                        (0.22, 0.58, 0.4), (0.80, 0.62, 0.4), (0.15, 0.62, 0.5), (0.35, 0.92, 0.45), (0.60, 0.95, 0.4), (0.88, 0.62, 0.35), (0.48, 0.60, 0.3)] : []
                    for (x, y, r) in pts + extra {
                        let rr = size * 0.012 * r
                        ctx.fill(Path(ellipseIn: CGRect(x: x * w - rr, y: y * h - rr, width: rr * 2, height: rr * 2)), with: .color(.white.opacity(0.95)))
                    }
                    for (x, y) in [(0.36, 0.24), (0.70, 0.62), (0.22, 0.76)] as [(CGFloat, CGFloat)] {
                        ctx.fill(FlameyArt.star(x * w, y * h, size * 0.035, inner: 0.25), with: .color(.white))
                    }
                }
                if skin.fx.contains(.sheen) {
                    var g = ctx
                    g.rotate(by: .degrees(-24))
                    g.fill(Path(CGRect(x: -0.05 * w, y: 0.10 * h, width: 0.16 * w, height: h * 1.4)), with: .color(.white.opacity(0.38)))
                    g.fill(Path(CGRect(x: 0.16 * w, y: 0.10 * h, width: 0.05 * w, height: h * 1.4)), with: .color(.white.opacity(0.26)))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

struct SkinInnerFX: View {
    let skin: FlameSkin?
    let size: CGFloat
    var body: some View {
        if let skin, skin.fx.contains(.hotCore) {
            FlameBuddyInnerShape(wobble: 0)
                .fill(RadialGradient(colors: [.white, .white.opacity(0)], center: UnitPoint(x: 0.5, y: 0.7), startRadius: 0, endRadius: size * 0.3))
        }
    }
}
