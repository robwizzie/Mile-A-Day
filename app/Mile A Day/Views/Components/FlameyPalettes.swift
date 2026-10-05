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
enum FlameyPaletteEffect: Hashable {
    case sheen, stars, denseStars, lava, ribbons, candy, waves, nebula, hotCore, prismCycle
    case halo, embers
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
    /// down through the day), byte-identical to before the wardrobe.
    static func palette(for item: FlameyItem) -> FlameyPalette? {
        func h(_ v: UInt32, _ o: Double = 1) -> Color { hex(v, o) }
        switch item {
        case .classic: return nil
        // MARK: Solids
        case .ember:
            return FlameyPalette(outer: [h(0xFF9A6B), h(0xF03A1C), h(0x9A1206)],
                                 inner: [h(0xFFE0C8), h(0xFF8052)], glow: h(0xFF3D1A), core: h(0xFFD0B8),
                                 eye: h(0x3A0A04))
        case .lime:
            return FlameyPalette(outer: [h(0xF0FFA8), h(0xA8E02A), h(0x4E8C06)],
                                 inner: [h(0xFBFFE6), h(0xD6F77E)], glow: h(0xB4F03A), core: h(0xEFFFC4),
                                 eye: h(0x1E3300))
        case .ruby:
            return FlameyPalette(outer: [h(0xFF7A96), h(0xE3194B), h(0x8A0A2C)],
                                 inner: [h(0xFFD2DC), h(0xFF7593)], glow: h(0xFF2D55), core: h(0xFFC2D0),
                                 eye: h(0x3A0414))
        case .lavender:
            return FlameyPalette(outer: [h(0xF6EEFF), h(0xCDB6F4), h(0x9477CF)],
                                 inner: [h(0xFFFFFF), h(0xE6DAFF)], glow: h(0xC7AEF8), core: h(0xF4ECFF),
                                 eye: h(0x2A1A48), rim: Color.white.opacity(0.6))
        case .sunflower:
            return FlameyPalette(outer: [h(0xFFF27A), h(0xFFD000), h(0xFF9500)],
                                 inner: [h(0xFFFDE8), h(0xFFEE70)], glow: h(0xFFC800), core: h(0xFFF8C8),
                                 eye: h(0x3A1E00))
        case .mint:
            return FlameyPalette(outer: [h(0xC6FFE6), h(0x3FE0A2), h(0x0C9A6A)],
                                 inner: [h(0xF0FFF8), h(0xA2F6D2)], glow: h(0x3EE0A0), core: h(0xCFFFEA),
                                 eye: h(0x0B3326))
        case .sapphire:
            return FlameyPalette(outer: [h(0x9CC8FF), h(0x2F6BFF), h(0x1230A8)],
                                 inner: [h(0xE8F4FF), h(0x93C7FF)], glow: h(0x3D7BFF), core: h(0xCFE6FF),
                                 eye: h(0x0A1640))
        case .violet:
            return FlameyPalette(outer: [h(0xDDB6FF), h(0x9B4DFF), h(0x541CB0)],
                                 inner: [h(0xF5EAFF), h(0xCCA3FF)], glow: h(0x9B4DFF), core: h(0xE8D6FF),
                                 eye: h(0x220A45))
        case .rose:
            return FlameyPalette(outer: [h(0xFFC8E0), h(0xFF5FA2), h(0xC21A69)],
                                 inner: [h(0xFFEEF6), h(0xFFA3CC)], glow: h(0xFF5FA2), core: h(0xFFD8EA),
                                 eye: h(0x3D0A22))
        case .teal:
            return FlameyPalette(outer: [h(0xA6F4F2), h(0x17C0BE), h(0x08707C)],
                                 inner: [h(0xE6FFFE), h(0x86EBE8)], glow: h(0x19C2C0), core: h(0xCFFFFD),
                                 eye: h(0x06302F))
        case .arctic:
            return FlameyPalette(outer: [.white, h(0xD6EEFF), h(0x86BCEA)],
                                 inner: [.white, h(0xE8F6FF)], glow: h(0xBFE6FF), core: .white,
                                 eye: h(0x10284A), rim: Color.white.opacity(0.7))
        case .midnight:
            return FlameyPalette(outer: [h(0x4557C0), h(0x1B2470), h(0x0A0F36)],
                                 inner: [h(0xF0FAFF), h(0x76D3FF)], glow: h(0x4A6BFF), core: h(0x9FE2FF),
                                 eye: h(0x0A1030), rim: h(0x9FC6FF, 0.55), innerOpacity: 1)
        case .phantom:
            return FlameyPalette(outer: [h(0xF2FFFB), h(0xB8F0E6), h(0x6FA8C8)],
                                 inner: [.white, h(0xE0FBF4)], glow: h(0x9FFFE0), core: h(0xE8FFF8),
                                 eye: h(0x10283A), rim: Color.white.opacity(0.8), bodyOpacity: 0.74)
        // MARK: Gradients
        case .sunset:
            return FlameyPalette(outer: [h(0xFFE07A), h(0xFF7A45), h(0xE8386F), h(0x6E2A8C)],
                                 inner: [h(0xFFF5D1), h(0xFFB478)], glow: h(0xFF6A5C))
        case .aurora:
            return FlameyPalette(outer: [h(0x8CFFBE), h(0x2FD3B5), h(0x4F7BFF), h(0x9B4DFF)],
                                 inner: [h(0xF2FFF8), h(0xA6F5D6)], glow: h(0x4FD9C0), core: h(0xD6FFEF),
                                 eye: h(0x10203A))
        case .ocean:
            return FlameyPalette(outer: [h(0xB6FFF2), h(0x22D3C8), h(0x137FC0), h(0x0A2A66)],
                                 inner: [h(0xEFFFFC), h(0x9EF0EA)], glow: h(0x22C8D0), core: h(0xCFFFF8),
                                 eye: h(0x05203A), effects: [.waves])
        case .lavaLamp:
            return FlameyPalette(outer: [h(0xFF9A4A), h(0xE8386F), h(0x6E1A5C)],
                                 inner: [h(0xFFEDB8), h(0xFFB24D)], glow: h(0xFF5A6A), effects: [.lava])
        case .galaxy:
            return FlameyPalette(outer: [h(0x9C7BFF), h(0x4B22B8), h(0x1A0A4A)],
                                 inner: [h(0xF6EEFF), h(0xBFA3FF)], glow: h(0x7E5BFF), core: h(0xE0D2FF),
                                 eye: h(0x1A0A40), rim: h(0xC9B6FF, 0.5), effects: [.stars])
        case .candy:
            return FlameyPalette(outer: [h(0xFFB8E8), h(0xC9A6FF), h(0x8ED8FF)],
                                 inner: [.white, h(0xFFDDF2)], glow: h(0xFF9FDC), core: h(0xFFE6F6),
                                 eye: h(0x3A1438), effects: [.candy], start: .topLeading, end: .bottomTrailing)
        case .northernLights:
            return FlameyPalette(outer: [h(0x2A3F8F), h(0x121A4F), h(0x070B26)],
                                 inner: [h(0xEDFFF6), h(0x8DFFC8)], glow: h(0x38E6A0), core: h(0xB8FFDD),
                                 eye: h(0x0A1A20), rim: h(0x8DFFC8, 0.5), effects: [.ribbons], innerOpacity: 1)
        // MARK: Legendary
        case .gold:
            return FlameyPalette(outer: [h(0xFFF4C0), h(0xF2C230), h(0xB67A08), h(0x5E3A00)],
                                 inner: [h(0xFFFDEB), h(0xFFE08A)], glow: h(0xFFC83A), core: h(0xFFF3B0),
                                 eye: h(0x3A2400), rim: h(0xFFF6C8, 0.85), effects: [.sheen, .embers],
                                 start: .topLeading, end: .bottom)
        case .prism:
            return FlameyPalette(outer: [h(0xFF5A5A), h(0xFFB03A), h(0xFFE94A), h(0x4ADE80), h(0x38BDF8),
                                         h(0x8B5CF6), h(0xF472B6)],
                                 inner: [.white, h(0xFFF0FA)], glow: .white, core: .white, eye: h(0x2A1030),
                                 rim: Color.white.opacity(0.75), effects: [.sheen, .prismCycle, .halo], angular: true)
        case .cosmic:
            return FlameyPalette(outer: [h(0x3A1A80), h(0x160A40), h(0x05030F)],
                                 inner: [.white, h(0xCDB8FF)], glow: h(0x8E6BFF), core: h(0xD8C8FF),
                                 eye: h(0x14082E), rim: h(0xD6C4FF, 0.65), effects: [.denseStars, .nebula, .halo],
                                 innerOpacity: 1)
        case .eternal:
            return FlameyPalette(outer: [.white, h(0xFFF8DC), h(0xFFDE8A), h(0xFFB547)],
                                 inner: [.white, .white], glow: h(0xFFE8A8), core: .white,
                                 eye: h(0x3A2410), rim: Color.white.opacity(0.9), effects: [.halo, .embers, .hotCore],
                                 innerOpacity: 1)
        default:
            return nil
        }
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

    static func draw(_ palette: FlameyPalette, in ctx: inout GraphicsContext, size sz: CGSize, unit size: CGFloat,
                     wobble: CGFloat) {
        let fx = palette.effects
        guard !fx.isDisjoint(with: [.sheen, .stars, .denseStars, .lava, .ribbons, .candy, .waves, .nebula]) else { return }
        let w = sz.width, h = sz.height
        let shape = FlameBuddyOuterShape(wobble: wobble).path(in: CGRect(origin: .zero, size: sz))
        ctx.clip(to: shape)
        let hx = FlameyPalette.hex
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
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
