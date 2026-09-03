import SwiftUI

/// The six treats as small vector glyphs — shared by Flamey's held props, the
/// Modern dashboard's shelf and the picker chips, so ONE drawing is the whole
/// visual vocabulary. Built from `Path`s in a unit square scaled by `size`.
/// `fill` (0…1) is how much of the unit is LEFT: a liquid level for drinks, a
/// bite for the burger and donut, the tip for a slice, a fading cup for the
/// latte. Pure vector, no assets — Flamey himself is vector, and an emoji
/// beside him reads as a sticker.
struct TreatGlyph: View {
    let treat: CalorieTreat
    var size: CGFloat = 24
    var fill: Double = 1

    var body: some View {
        let f = min(max(fill, 0), 1)
        Group {
            switch treat {
            case .wine: WineGlassGlyph(size: size, fill: f)
            case .beer: BeerMugGlyph(size: size, fill: f)
            case .cheeseburger: BurgerGlyph(size: size, fill: f)
            case .pizza: PizzaGlyph(size: size, fill: f)
            case .donut: DonutGlyph(size: size, fill: f)
            case .coffee: CoffeeGlyph(size: size, fill: f)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The glyphs' palette, in one place so the shelf and the props match.
enum TreatInk {
    static let glass = Color.white.opacity(0.55)
    static let glassFill = Color.white.opacity(0.10)
    static let wine = Color(red: 0.58, green: 0.09, blue: 0.26)
    static let beer = Color(red: 0.94, green: 0.64, blue: 0.16)
    static let foam = Color.white.opacity(0.92)
    static let bun = Color(red: 0.87, green: 0.61, blue: 0.31)
    static let sesame = Color.white.opacity(0.75)
    static let lettuce = Color(red: 0.36, green: 0.71, blue: 0.31)
    static let cheese = Color(red: 1.0, green: 0.78, blue: 0.20)
    static let patty = Color(red: 0.42, green: 0.23, blue: 0.12)
    static let pizzaCheese = Color(red: 0.98, green: 0.80, blue: 0.36)
    static let crust = Color(red: 0.80, green: 0.52, blue: 0.24)
    static let pepperoni = Color(red: 0.78, green: 0.18, blue: 0.14)
    static let dough = Color(red: 0.90, green: 0.68, blue: 0.40)
    static let glaze = Color(red: 0.96, green: 0.46, blue: 0.66)
    static let sprinkles: [Color] = [
        Color(red: 0.35, green: 0.78, blue: 0.95),
        Color(red: 1.0, green: 0.86, blue: 0.25),
        Color(red: 0.45, green: 0.85, blue: 0.45),
        Color.white.opacity(0.9),
    ]
    static let cup = Color(red: 0.93, green: 0.92, blue: 0.90)
    static let lid = Color(red: 0.30, green: 0.30, blue: 0.33)
    static let sleeve = Color(red: 0.63, green: 0.43, blue: 0.28)
    static let steam = Color.white.opacity(0.5)
}

/// A rectangle with a circular bite taken out of it — the mask for the burger
/// and the donut. `radius` 0 is no bite at all.
private struct BiteMask: View {
    let size: CGFloat
    let center: CGPoint
    let radius: CGFloat

    var body: some View {
        Path { path in
            path.addRect(CGRect(x: 0, y: 0, width: size, height: size))
            if radius > 0.5 {
                path.addEllipse(in: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2))
            }
        }
        .fill(Color.black, style: FillStyle(eoFill: true))
    }
}

/// Everything below a horizontal line — the mask for liquid levels.
private struct BelowLineMask: View {
    let size: CGFloat
    let top: CGFloat

    var body: some View {
        Path(CGRect(x: 0, y: top, width: size, height: size)).fill(Color.black)
    }
}

private struct WineGlassGlyph: View {
    let size: CGFloat
    let fill: Double

    private var bowl: Path {
        let s = size
        var path = Path()
        path.move(to: CGPoint(x: 0.24 * s, y: 0.08 * s))
        path.addLine(to: CGPoint(x: 0.24 * s, y: 0.36 * s))
        path.addQuadCurve(
            to: CGPoint(x: 0.76 * s, y: 0.36 * s),
            control: CGPoint(x: 0.50 * s, y: 0.82 * s))
        path.addLine(to: CGPoint(x: 0.76 * s, y: 0.08 * s))
        path.closeSubpath()
        return path
    }

    var body: some View {
        let s = size
        // The bowl spans y 0.08…~0.59; the liquid never reaches the rim.
        let liquidTop = (0.14 + 0.45 * (1 - fill)) * s
        ZStack {
            bowl.fill(TreatInk.glassFill)
            bowl.fill(TreatInk.wine)
                .mask(BelowLineMask(size: s, top: liquidTop))
            bowl.stroke(TreatInk.glass, lineWidth: max(1, s * 0.04))
            Rectangle()
                .fill(TreatInk.glass)
                .frame(width: s * 0.06, height: s * 0.24)
                .position(x: 0.50 * s, y: 0.70 * s)
            Ellipse()
                .fill(TreatInk.glass)
                .frame(width: s * 0.40, height: s * 0.09)
                .position(x: 0.50 * s, y: 0.86 * s)
        }
        .frame(width: s, height: s)
    }
}

private struct BeerMugGlyph: View {
    let size: CGFloat
    let fill: Double

    var body: some View {
        let s = size
        let mug = CGRect(x: 0.14 * s, y: 0.20 * s, width: 0.54 * s, height: 0.66 * s)
        let inner = mug.insetBy(dx: 0.05 * s, dy: 0.05 * s)
        let liquidTop = inner.minY + inner.height * (1 - fill)
        ZStack {
            // Handle, behind the body.
            RoundedRectangle(cornerRadius: 0.07 * s, style: .continuous)
                .strokeBorder(TreatInk.glass, lineWidth: max(1, s * 0.06))
                .frame(width: 0.26 * s, height: 0.36 * s)
                .position(x: 0.76 * s, y: 0.52 * s)
            RoundedRectangle(cornerRadius: 0.08 * s, style: .continuous)
                .fill(TreatInk.glassFill)
                .frame(width: mug.width, height: mug.height)
                .position(x: mug.midX, y: mug.midY)
            RoundedRectangle(cornerRadius: 0.05 * s, style: .continuous)
                .fill(TreatInk.beer)
                .frame(width: inner.width, height: inner.height)
                .position(x: inner.midX, y: inner.midY)
                .mask(BelowLineMask(size: s, top: liquidTop))
            if fill > 0.85 {
                ForEach(0..<3, id: \.self) { index in
                    let x = (0.26 + 0.15 * CGFloat(index)) * s
                    let y = (index == 1 ? 0.15 : 0.19) * s
                    Circle()
                        .fill(TreatInk.foam)
                        .frame(width: 0.19 * s, height: 0.19 * s)
                        .position(x: x, y: y)
                }
            }
            RoundedRectangle(cornerRadius: 0.08 * s, style: .continuous)
                .strokeBorder(TreatInk.glass, lineWidth: max(1, s * 0.04))
                .frame(width: mug.width, height: mug.height)
                .position(x: mug.midX, y: mug.midY)
        }
        .frame(width: s, height: s)
    }
}

private struct BurgerGlyph: View {
    let size: CGFloat
    let fill: Double

    var body: some View {
        let s = size
        ZStack {
            RoundedRectangle(cornerRadius: 0.09 * s, style: .continuous)
                .fill(TreatInk.bun)
                .frame(width: 0.76 * s, height: 0.22 * s)
                .position(x: 0.50 * s, y: 0.78 * s)
            RoundedRectangle(cornerRadius: 0.05 * s, style: .continuous)
                .fill(TreatInk.patty)
                .frame(width: 0.80 * s, height: 0.14 * s)
                .position(x: 0.50 * s, y: 0.63 * s)
            // Cheese with the drooping corner.
            Path { path in
                path.move(to: CGPoint(x: 0.12 * s, y: 0.50 * s))
                path.addLine(to: CGPoint(x: 0.88 * s, y: 0.50 * s))
                path.addLine(to: CGPoint(x: 0.88 * s, y: 0.57 * s))
                path.addLine(to: CGPoint(x: 0.81 * s, y: 0.67 * s))
                path.addLine(to: CGPoint(x: 0.74 * s, y: 0.57 * s))
                path.addLine(to: CGPoint(x: 0.12 * s, y: 0.57 * s))
                path.closeSubpath()
            }
            .fill(TreatInk.cheese)
            RoundedRectangle(cornerRadius: 0.03 * s, style: .continuous)
                .fill(TreatInk.lettuce)
                .frame(width: 0.84 * s, height: 0.08 * s)
                .position(x: 0.50 * s, y: 0.47 * s)
            Path { path in
                path.move(to: CGPoint(x: 0.12 * s, y: 0.45 * s))
                path.addQuadCurve(
                    to: CGPoint(x: 0.88 * s, y: 0.45 * s),
                    control: CGPoint(x: 0.50 * s, y: 0.02 * s))
                path.closeSubpath()
            }
            .fill(TreatInk.bun)
            ForEach(0..<3, id: \.self) { index in
                let x = (0.36 + 0.14 * CGFloat(index)) * s
                let y = (index == 1 ? 0.22 : 0.28) * s
                Ellipse()
                    .fill(TreatInk.sesame)
                    .frame(width: 0.08 * s, height: 0.05 * s)
                    .position(x: x, y: y)
            }
        }
        .frame(width: s, height: s)
        .mask(BiteMask(
            size: s, center: CGPoint(x: 0.93 * s, y: 0.40 * s),
            radius: 0.38 * s * (1 - fill)))
    }
}

private struct PizzaGlyph: View {
    let size: CGFloat
    let fill: Double

    var body: some View {
        let s = size
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0.50 * s, y: 0.95 * s))
                path.addLine(to: CGPoint(x: 0.10 * s, y: 0.24 * s))
                path.addLine(to: CGPoint(x: 0.90 * s, y: 0.24 * s))
                path.closeSubpath()
            }
            .fill(TreatInk.pizzaCheese)
            Path { path in
                path.move(to: CGPoint(x: 0.10 * s, y: 0.24 * s))
                path.addQuadCurve(
                    to: CGPoint(x: 0.90 * s, y: 0.24 * s),
                    control: CGPoint(x: 0.50 * s, y: 0.06 * s))
            }
            .stroke(TreatInk.crust, style: StrokeStyle(lineWidth: max(1.5, s * 0.11), lineCap: .round))
            ForEach(0..<3, id: \.self) { index in
                let spots: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.38, 0.38, 0.14), (0.62, 0.44, 0.13), (0.50, 0.62, 0.12),
                ]
                let spot = spots[index]
                Circle()
                    .fill(TreatInk.pepperoni)
                    .frame(width: spot.2 * s, height: spot.2 * s)
                    .position(x: spot.0 * s, y: spot.1 * s)
            }
        }
        .frame(width: s, height: s)
        // Eaten from the tip: the crust is what's left last.
        .mask(Path(CGRect(x: 0, y: 0, width: s, height: s * (0.12 + 0.86 * fill))).fill(Color.black))
    }
}

private struct DonutGlyph: View {
    let size: CGFloat
    let fill: Double

    /// Split out with explicit types — the inline Double/CGFloat trig inside
    /// the view chain tipped the type-checker past its time budget.
    private func sprinkle(index: Int) -> some View {
        let angle: Double = -160.0 + 32.0 * Double(index)
        let radians: Double = angle * Double.pi / 180.0
        let radius: CGFloat = 0.31 * size
        let x: CGFloat = 0.5 * size + CGFloat(cos(radians)) * radius
        let y: CGFloat = 0.5 * size + CGFloat(sin(radians)) * radius
        let width: CGFloat = 0.11 * size
        let height: CGFloat = 0.035 * size
        let color = TreatInk.sprinkles[index % TreatInk.sprinkles.count]
        return Capsule()
            .fill(color)
            .frame(width: width, height: height)
            .rotationEffect(.degrees(angle + 90))
            .position(x: x, y: y)
    }

    private var ring: Path {
        let s = size
        var path = Path()
        path.addEllipse(in: CGRect(x: 0.08 * s, y: 0.08 * s, width: 0.84 * s, height: 0.84 * s))
        path.addEllipse(in: CGRect(x: 0.36 * s, y: 0.36 * s, width: 0.28 * s, height: 0.28 * s))
        return path
    }

    var body: some View {
        let s = size
        ZStack {
            ring.fill(TreatInk.dough, style: FillStyle(eoFill: true))
            ring.fill(TreatInk.glaze, style: FillStyle(eoFill: true))
                .mask(Path(CGRect(x: 0, y: 0, width: s, height: 0.56 * s)).fill(Color.black))
            ForEach(0..<6, id: \.self) { index in
                sprinkle(index: index)
            }
        }
        .frame(width: s, height: s)
        .mask(BiteMask(
            size: s, center: CGPoint(x: 0.88 * s, y: 0.14 * s),
            radius: 0.40 * s * (1 - fill)))
    }
}

private struct CoffeeGlyph: View {
    let size: CGFloat
    let fill: Double

    private var cup: some View {
        let s = size
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0.22 * s, y: 0.32 * s))
                path.addLine(to: CGPoint(x: 0.78 * s, y: 0.32 * s))
                path.addLine(to: CGPoint(x: 0.70 * s, y: 0.93 * s))
                path.addLine(to: CGPoint(x: 0.30 * s, y: 0.93 * s))
                path.closeSubpath()
            }
            .fill(TreatInk.cup)
            Path { path in
                path.move(to: CGPoint(x: 0.245 * s, y: 0.52 * s))
                path.addLine(to: CGPoint(x: 0.755 * s, y: 0.52 * s))
                path.addLine(to: CGPoint(x: 0.73 * s, y: 0.72 * s))
                path.addLine(to: CGPoint(x: 0.27 * s, y: 0.72 * s))
                path.closeSubpath()
            }
            .fill(TreatInk.sleeve)
            RoundedRectangle(cornerRadius: 0.03 * s, style: .continuous)
                .fill(TreatInk.lid)
                .frame(width: 0.64 * s, height: 0.11 * s)
                .position(x: 0.50 * s, y: 0.28 * s)
        }
        .frame(width: s, height: s)
    }

    var body: some View {
        let s = size
        ZStack {
            // A drunk latte fades: the ghost is always there, the full cup is
            // masked from the bottom by what's left.
            cup.opacity(0.22)
            cup.mask(BelowLineMask(size: s, top: (0.22 + 0.72 * (1 - fill)) * s))
            ForEach(0..<2, id: \.self) { index in
                let x = (index == 0 ? 0.41 : 0.59) * s
                Path { path in
                    path.move(to: CGPoint(x: x, y: 0.20 * s))
                    path.addQuadCurve(
                        to: CGPoint(x: x, y: 0.04 * s),
                        control: CGPoint(x: x + (index == 0 ? 0.08 : -0.08) * s, y: 0.12 * s))
                }
                .stroke(TreatInk.steam, style: StrokeStyle(lineWidth: max(1, s * 0.045), lineCap: .round))
                .opacity(fill > 0.05 ? 1 : 0)
            }
        }
        .frame(width: s, height: s)
    }
}

#Preview {
    VStack(spacing: 16) {
        ForEach([1.0, 0.65, 0.3, 0.0], id: \.self) { fill in
            HStack(spacing: 14) {
                ForEach(CalorieTreat.allCases) { treat in
                    TreatGlyph(treat: treat, size: 40, fill: fill)
                }
            }
        }
    }
    .padding(30)
    .background(Color(red: 0.08, green: 0.08, blue: 0.09))
}
