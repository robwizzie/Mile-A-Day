import AppKit
import SwiftUI

// A stand-in for SwiftUI's `GraphicsContext` that RECORDS what the Flamey art
// draws instead of drawing it. `run.sh` compiles a copy of FlameyArt.swift
// with `GraphicsContext` renamed to `RecContext` (and the enum to
// `FlameyArtRec`), so the shipping art code runs unchanged and every fill,
// stroke, clip, blur and shadow it makes lands here with its exact colours,
// alpha and geometry. (Quartz PDF export loses gradient alpha; this doesn't.)
//
// Recorded coordinates are BODY UNITS: origin at the centre of Flamey's
// square, y down, 1 = u. Geometry is baked through the current transform —
// exact for any affine transform. Paint and stroke width are baked too when
// the transform is a similarity (scale + rotate + translate); otherwise the
// op keeps its local coordinates and carries `m`, the local → body matrix,
// so a squeezed cape's outline keeps its uneven width and an elliptical
// gradient stays elliptical.
//
// Op shapes (see docs/flamey-skins.md):
//   {"op":"fill",   "d", "paint", "eo"?, "m"?, "a"?, "fx"?, "clip"?}
//   {"op":"stroke", "d", "paint", "w", "cap"?, "join"?, "miter"?, "dash"?, "phase"?, "m"?, "a"?, "fx"?, "clip"?}
//   {"op":"image",  "src", "rect", "m", "a"?, "fx"?, "clip"?}
// paint: "#RRGGBBAA" | {"lin":[x0,y0,x1,y1],"stops":[[t,"#…"],…]}
//                    | {"rad":[cx,cy,r0,r1],"stops"} | {"conic":[cx,cy,deg],"stops"}
// fx:    [{"blur":r}] | [{"shadow":["#…",r,dx,dy]}]   (body units, in order)
// clip:  indices into the recording's "clips": [{"d","eo"?,"inv"?}]

final class RecSink {
    let u: CGFloat
    var ops: [[String: Any]] = []
    var clips: [[String: Any]] = []
    private var clipIndex: [String: Int] = [:]
    var images: [String: String] = [:]

    init(u: CGFloat) { self.u = u }

    func clipId(_ clip: [String: Any]) -> Int {
        let key = (clip["d"] as? String ?? "") + "|\(clip["eo"] ?? false)|\(clip["inv"] ?? false)"
        if let i = clipIndex[key] { return i }
        clips.append(clip)
        clipIndex[key] = clips.count - 1
        return clips.count - 1
    }

    var recording: [String: Any] {
        var r: [String: Any] = ["ops": ops]
        if !clips.isEmpty { r["clips"] = clips }
        if !images.isEmpty { r["images"] = images }
        return r
    }
}

struct RecContext {
    let sink: RecSink
    var ctm: CGAffineTransform = .identity
    var opacity: Double = 1
    var filters: [[String: Any]] = []
    var clipIds: [Int] = []

    init(sink: RecSink) { self.sink = sink }

    // MARK: Types mirroring GraphicsContext's

    struct ClipOptions: OptionSet {
        let rawValue: Int
        init(rawValue: Int) { self.rawValue = rawValue }
        static let inverse = ClipOptions(rawValue: 1)
    }

    struct GradientOptions: OptionSet {
        let rawValue: Int
        init(rawValue: Int) { self.rawValue = rawValue }
        static let `repeat` = GradientOptions(rawValue: 1)
        static let mirror = GradientOptions(rawValue: 2)
        static let linearColor = GradientOptions(rawValue: 4)
    }

    struct BlurOptions: OptionSet {
        let rawValue: Int
        init(rawValue: Int) { self.rawValue = rawValue }
        static let opaque = BlurOptions(rawValue: 1)
        static let dithersResult = BlurOptions(rawValue: 2)
    }

    struct ShadowOptions: OptionSet {
        let rawValue: Int
        init(rawValue: Int) { self.rawValue = rawValue }
        static let shadowAbove = ShadowOptions(rawValue: 1)
        static let shadowOnly = ShadowOptions(rawValue: 2)
        static let invertsAlpha = ShadowOptions(rawValue: 4)
        static let disablesGroup = ShadowOptions(rawValue: 8)
    }

    struct FilterOptions: OptionSet {
        let rawValue: Int
        init(rawValue: Int) { self.rawValue = rawValue }
    }

    struct Shading {
        enum Kind {
            case color(Color)
            case linear(Gradient, CGPoint, CGPoint)
            case radial(Gradient, CGPoint, CGFloat, CGFloat)
            case conic(Gradient, CGPoint, Angle)
        }
        let kind: Kind

        static func color(_ c: Color) -> Shading { Shading(kind: .color(c)) }
        static func linearGradient(_ g: Gradient, startPoint: CGPoint, endPoint: CGPoint,
                                   options: GradientOptions = []) -> Shading {
            Shading(kind: .linear(g, startPoint, endPoint))
        }
        static func radialGradient(_ g: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat,
                                   options: GradientOptions = []) -> Shading {
            Shading(kind: .radial(g, center, startRadius, endRadius))
        }
        static func conicGradient(_ g: Gradient, center: CGPoint, angle: Angle = .zero,
                                  options: GradientOptions = []) -> Shading {
            Shading(kind: .conic(g, center, angle))
        }

        var isGradient: Bool {
            if case .color = kind { return false }
            return true
        }
    }

    struct Filter {
        enum Kind { case blur(CGFloat), shadow(Color, CGFloat, CGFloat, CGFloat) }
        let kind: Kind
        static func blur(radius: CGFloat, options: BlurOptions = []) -> Filter { Filter(kind: .blur(radius)) }
        static func shadow(color: Color = .black.opacity(0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0,
                           options: ShadowOptions = []) -> Filter {
            Filter(kind: .shadow(color, radius, x, y))
        }
    }

    // MARK: State

    mutating func translateBy(x: CGFloat, y: CGFloat) {
        ctm = CGAffineTransform(translationX: x, y: y).concatenating(ctm)
    }

    mutating func scaleBy(x: CGFloat, y: CGFloat) {
        ctm = CGAffineTransform(scaleX: x, y: y).concatenating(ctm)
    }

    mutating func rotate(by angle: Angle) {
        ctm = CGAffineTransform(rotationAngle: CGFloat(angle.radians)).concatenating(ctm)
    }

    mutating func concatenate(_ m: CGAffineTransform) {
        ctm = m.concatenating(ctm)
    }

    mutating func addFilter(_ filter: Filter, options: FilterOptions = []) {
        let s = scale / sink.u
        switch filter.kind {
        case .blur(let r):
            filters.append(["blur": num(r * s)])
        case .shadow(let c, let r, let x, let y):
            let v = CGPoint(x: x, y: y).applying(linear)
            filters.append(["shadow": [hex(c), num(r * s), num(v.x / sink.u), num(v.y / sink.u)] as [Any]])
        }
    }

    mutating func clip(to path: Path, style: FillStyle = FillStyle(), options: ClipOptions = []) {
        var c: [String: Any] = ["d": svg(path, body)]
        if style.isEOFilled { c["eo"] = true }
        if options.contains(.inverse) { c["inv"] = true }
        clipIds.append(sink.clipId(c))
    }

    // MARK: Drawing

    func fill(_ path: Path, with shading: Shading, style: FillStyle = FillStyle()) {
        var o: [String: Any] = ["op": "fill"]
        if shading.isGradient && !isSimilarity {
            o["d"] = svg(path, .identity)
            o["m"] = mat(body)
            o["paint"] = paint(shading, .identity, 1, 0)
        } else {
            o["d"] = svg(path, body)
            o["paint"] = paint(shading, body, scale / sink.u, rotation)
        }
        if style.isEOFilled { o["eo"] = true }
        emit(o)
    }

    func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
        stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
    }

    func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
        var o: [String: Any] = ["op": "stroke"]
        if isSimilarity {
            o["d"] = svg(path, body)
            o["paint"] = paint(shading, body, scale / sink.u, rotation)
            o["w"] = num(style.lineWidth * scale / sink.u)
            if !style.dash.isEmpty {
                o["dash"] = style.dash.map { num($0 * scale / sink.u) }
                o["phase"] = num(style.dashPhase * scale / sink.u)
            }
        } else {
            o["d"] = svg(path, .identity)
            o["m"] = mat(body)
            o["paint"] = paint(shading, .identity, 1, 0)
            o["w"] = num(style.lineWidth)
            if !style.dash.isEmpty {
                o["dash"] = style.dash.map { num($0) }
                o["phase"] = num(style.dashPhase)
            }
        }
        switch style.lineCap {
        case .round: o["cap"] = "round"
        case .square: o["cap"] = "square"
        default: break
        }
        switch style.lineJoin {
        case .round: o["join"] = "round"
        case .bevel: o["join"] = "bevel"
        default: break
        }
        if style.miterLimit != 10 { o["miter"] = num(style.miterLimit) }
        emit(o)
    }

    /// Text (two items draw a little): rasterised at 4×, placed exactly.
    func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint = .center) {
        let rendered: CGImage? = MainActor.assumeIsolated {
            let r = ImageRenderer(content: text)
            r.scale = 4
            return r.cgImage
        }
        guard let cg = rendered,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        let w = CGFloat(cg.width) / 4, h = CGFloat(cg.height) / 4
        let id = "img\(sink.images.count)"
        sink.images[id] = "data:image/png;base64," + png.base64EncodedString()
        let o: [String: Any] = [
            "op": "image", "src": id,
            "rect": [num(point.x - w * anchor.x), num(point.y - h * anchor.y), num(w), num(h)],
            "m": mat(body),
        ]
        emit(o)
    }

    private func emit(_ o: [String: Any]) {
        var o = o
        if opacity < 0.9999 { o["a"] = num(opacity) }
        if !filters.isEmpty { o["fx"] = filters }
        if !clipIds.isEmpty { o["clip"] = clipIds }
        sink.ops.append(o)
    }

    // MARK: Geometry

    /// Local → body units.
    private var body: CGAffineTransform { ctm.concatenating(CGAffineTransform(scaleX: 1 / sink.u, y: 1 / sink.u)) }
    private var linear: CGAffineTransform { CGAffineTransform(a: ctm.a, b: ctm.b, c: ctm.c, d: ctm.d, tx: 0, ty: 0) }
    private var scale: CGFloat { sqrt(abs(ctm.a * ctm.d - ctm.b * ctm.c)) }
    private var rotation: Double { atan2(Double(ctm.b), Double(ctm.a)) * 180 / .pi }

    /// Scale + rotation + translation, no reflection.
    private var isSimilarity: Bool {
        let e: CGFloat = 1e-6
        return abs(ctm.a - ctm.d) < e && abs(ctm.b + ctm.c) < e && (ctm.a * ctm.d - ctm.b * ctm.c) > 0
    }

    private func paint(_ s: Shading, _ t: CGAffineTransform, _ k: CGFloat, _ deg: Double) -> Any {
        switch s.kind {
        case .color(let c):
            return hex(c)
        case .linear(let g, let p0, let p1):
            let a = p0.applying(t), b = p1.applying(t)
            return ["lin": [num(a.x), num(a.y), num(b.x), num(b.y)], "stops": stops(g)] as [String: Any]
        case .radial(let g, let c, let r0, let r1):
            let p = c.applying(t)
            return ["rad": [num(p.x), num(p.y), num(r0 * k), num(r1 * k)], "stops": stops(g)] as [String: Any]
        case .conic(let g, let c, let ang):
            let p = c.applying(t)
            return ["conic": [num(p.x), num(p.y), num(ang.degrees + deg)], "stops": stops(g)] as [String: Any]
        }
    }

    private func stops(_ g: Gradient) -> [[Any]] {
        g.stops.map { [num($0.location), hex($0.color)] }
    }

    private func svg(_ path: Path, _ t: CGAffineTransform) -> String {
        var out: [String] = []
        func p(_ q: CGPoint) -> String { let r = q.applying(t); return "\(fmt(r.x)) \(fmt(r.y))" }
        path.forEach { e in
            switch e {
            case .move(let to): out.append("M" + p(to))
            case .line(let to): out.append("L" + p(to))
            case .quadCurve(let to, let c): out.append("Q" + p(c) + " " + p(to))
            case .curve(let to, let c1, let c2): out.append("C" + p(c1) + " " + p(c2) + " " + p(to))
            case .closeSubpath: out.append("Z")
            }
        }
        return out.joined()
    }

    private func mat(_ m: CGAffineTransform) -> [Double] {
        [m.a, m.b, m.c, m.d, m.tx, m.ty].map { num($0) }
    }
}

// MARK: - Number and colour formatting

func num(_ v: CGFloat) -> Double { (Double(v) * 1e5).rounded() / 1e5 }
func num(_ v: Double) -> Double { (v * 1e5).rounded() / 1e5 }

func fmt(_ v: CGFloat) -> String {
    let r = (Double(v) * 1e4).rounded() / 1e4
    if r == r.rounded() { return String(Int(r)) }
    var s = String(format: "%.4f", r)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasPrefix("0.") { s.removeFirst() } else if s.hasPrefix("-0.") { s = "-" + s.dropFirst(2) }
    return s
}

/// "#RRGGBBAA", sRGB.
func hex(_ c: Color) -> String {
    guard let ns = NSColor(c).usingColorSpace(.sRGB) else { return "#000000FF" }
    func b(_ v: CGFloat) -> Int { max(0, min(255, Int((v * 255).rounded()))) }
    return String(format: "#%02X%02X%02X%02X", b(ns.redComponent), b(ns.greenComponent), b(ns.blueComponent),
                  b(ns.alphaComponent))
}
