import ImageIO
import SwiftUI

// FLAMEY'S SKINS — every wardrobe item as data (docs/flamey-skins.md).
// BYTE-IDENTICAL in app/Mile A Day/Views/Components/ and app/MileADayWidgets/
// (see FlameyWardrobe.swift). SwiftUI + Foundation + ImageIO only.
//
// A skin's art is a list of recorded drawing ops in BODY UNITS (origin at the
// centre of Flamey's square, y down, 1 = u). `FlameySkinArt.draw` replays them
// into a `GraphicsContext` whose origin is that centre, at any u — the same
// fills, strokes, clips, blurs and shadows the Swift art code made, because
// they were recorded from it (app/FlameyExport).
//
// The catalog is the bundled copy (`FlameySkins.json`, generated from
// backend/flamey-skins) overlaid with the last copy downloaded from
// `GET /flamey/skins` (saved in the App Group container, so the widgets see
// it too). A skin whose `format` is newer than `FlameySkinCatalog.format` is
// ignored: an older renderer never draws a skin it doesn't understand.

// MARK: - Model

final class FlameySkin {
    let id: String
    let order: Int
    let format: Int
    let slot: String
    let name: String
    let family: String
    let unlock: Any
    let unlockCopy: String
    let holidays: [String]
    let moodProp: Bool
    let compact: Bool
    let rules: [String: Any]
    let palette: [String: Any]?
    let effects: [String]
    let pivots: [String: CGPoint]
    let motion: [String: [String: Any]]
    private let artRaw: [String: [String: Any]]
    private var artCache: [String: FlameySkinLayer] = [:]
    private let lock = NSLock()

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String, let slot = json["slot"] as? String,
              let format = json["format"] as? Int else { return nil }
        self.id = id
        self.slot = slot
        self.format = format
        order = json["order"] as? Int ?? Int.max
        name = json["name"] as? String ?? id
        family = json["family"] as? String ?? ""
        unlock = json["unlock"] ?? "always"
        unlockCopy = json["unlock_copy"] as? String ?? ""
        holidays = json["holidays"] as? [String] ?? []
        moodProp = json["mood_prop"] as? Bool ?? false
        compact = json["compact"] as? Bool ?? false
        rules = json["rules"] as? [String: Any] ?? [:]
        palette = json["palette"] as? [String: Any]
        effects = json["effects"] as? [String] ?? []
        motion = json["motion"] as? [String: [String: Any]] ?? [:]
        artRaw = json["art"] as? [String: [String: Any]] ?? [:]
        var p: [String: CGPoint] = [:]
        for (k, v) in json["pivots"] as? [String: [Double]] ?? [:] where v.count == 2 {
            p[k] = CGPoint(x: v[0], y: v[1])
        }
        pivots = p
    }

    var layerKeys: [String] { Array(artRaw.keys) }

    /// A layer by its exact key ("front", "behind@reach=0.62,low=0").
    func layer(_ key: String) -> FlameySkinLayer? {
        lock.lock(); defer { lock.unlock() }
        if let l = artCache[key] { return l }
        guard let raw = artRaw[key] else { return nil }
        let l = FlameySkinLayer(raw)
        artCache[key] = l
        return l
    }

    /// The layer for `part` whose conditions match: every condition given
    /// must match exactly, except `reach`, which picks the nearest recorded
    /// one. A key without a condition matches any value of it.
    func layer(_ part: String, _ conditions: [String: String] = [:]) -> FlameySkinLayer? {
        layerKey(part, conditions).flatMap { layer($0) }
    }

    /// The key `layer(_:_:)` would pick (pivots are stored under it).
    func layerKey(_ part: String, _ conditions: [String: String] = [:]) -> String? {
        var best: (key: String, score: Double)?
        for key in artRaw.keys {
            let (name, conds) = Self.split(key)
            guard name == part else { continue }
            var score = 0.0
            var ok = true
            for (k, v) in conds {
                guard let want = conditions[k] else { continue }
                if k == "reach" {
                    score += abs((Double(want) ?? 0) - (Double(v) ?? 0))
                } else if want != v {
                    ok = false
                    break
                }
            }
            if ok, best == nil || score < best!.score || (score == best!.score && key < best!.key) {
                best = (key, score)
            }
        }
        return best?.key
    }

    static func split(_ key: String) -> (String, [String: String]) {
        let parts = key.split(separator: "@", maxSplits: 1)
        var conds: [String: String] = [:]
        if parts.count == 2 {
            for pair in parts[1].split(separator: ",") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { conds[String(kv[0])] = String(kv[1]) }
            }
        }
        return (String(parts[0]), conds)
    }

    // Typed rules.
    func rule(_ k: String) -> Double? { (rules[k] as? NSNumber)?.doubleValue }
    func ruleBool(_ k: String) -> Bool? { rules[k] as? Bool }
    func ruleStrings(_ k: String) -> [String] { rules[k] as? [String] ?? [] }
    func ruleString(_ k: String) -> String? { rules[k] as? String }
}

// MARK: - A recorded layer, parsed for drawing

final class FlameySkinLayer {
    enum PaintColor {
        case color(Color)
        case token(String, Double, Color)
    }

    enum Paint {
        case solid(PaintColor)
        case linear([(Double, PaintColor)], CGPoint, CGPoint)
        case radial([(Double, PaintColor)], CGPoint, CGFloat, CGFloat)
        case conic([(Double, PaintColor)], CGPoint, Double)
    }

    enum FX {
        case blur(CGFloat)
        case shadow(Color, CGFloat, CGFloat, CGFloat)
    }

    enum Kind {
        case fill(Path, Paint, eo: Bool)
        case stroke(Path, Paint, width: CGFloat, cap: CGLineCap, join: CGLineJoin, miter: CGFloat, dash: [CGFloat], phase: CGFloat)
        case image(String, CGRect)
    }

    struct Op {
        let kind: Kind
        let m: CGAffineTransform?
        let alpha: Double
        let fx: [FX]
        let clips: [Int]
    }

    struct Clip {
        let path: Path
        let eo: Bool
        let inverse: Bool
    }

    let ops: [Op]
    let clips: [Clip]
    let images: [String: CGImage]

    init(_ raw: [String: Any]) {
        clips = (raw["clips"] as? [[String: Any]] ?? []).map {
            Clip(path: FlameySkinLayer.path($0["d"] as? String ?? ""), eo: $0["eo"] as? Bool ?? false,
                 inverse: $0["inv"] as? Bool ?? false)
        }
        var imgs: [String: CGImage] = [:]
        for (k, v) in raw["images"] as? [String: String] ?? [:] {
            if let comma = v.firstIndex(of: ","), let data = Data(base64Encoded: String(v[v.index(after: comma)...])),
               let src = CGImageSourceCreateWithData(data as CFData, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                imgs[k] = img
            }
        }
        images = imgs
        ops = (raw["ops"] as? [[String: Any]] ?? []).compactMap(FlameySkinLayer.op)
    }

    static func op(_ o: [String: Any]) -> Op? {
        let m: CGAffineTransform? = (o["m"] as? [Double]).flatMap { v in
            v.count == 6 ? CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]) : nil
        }
        let alpha = (o["a"] as? NSNumber)?.doubleValue ?? 1
        var fx: [FX] = []
        for f in o["fx"] as? [[String: Any]] ?? [] {
            if let r = (f["blur"] as? NSNumber)?.doubleValue { fx.append(.blur(r)) }
            if let s = f["shadow"] as? [Any], s.count == 4, let c = s[0] as? String {
                func n(_ i: Int) -> CGFloat { CGFloat((s[i] as? NSNumber)?.doubleValue ?? 0) }
                fx.append(.shadow(color(c), n(1), n(2), n(3)))
            }
        }
        let clipIds = o["clip"] as? [Int] ?? []
        let kind: Kind
        switch o["op"] as? String {
        case "fill":
            guard let d = o["d"] as? String, let p = o["paint"].flatMap(paint) else { return nil }
            kind = .fill(path(d), p, eo: o["eo"] as? Bool ?? false)
        case "stroke":
            guard let d = o["d"] as? String, let p = o["paint"].flatMap(paint) else { return nil }
            let cap: CGLineCap = { switch o["cap"] as? String { case "round": return .round; case "square": return .square; default: return .butt } }()
            let join: CGLineJoin = { switch o["join"] as? String { case "round": return .round; case "bevel": return .bevel; default: return .miter } }()
            kind = .stroke(path(d), p, width: CGFloat((o["w"] as? NSNumber)?.doubleValue ?? 0.01), cap: cap, join: join,
                           miter: CGFloat((o["miter"] as? NSNumber)?.doubleValue ?? 10),
                           dash: (o["dash"] as? [Double] ?? []).map { CGFloat($0) },
                           phase: CGFloat((o["phase"] as? NSNumber)?.doubleValue ?? 0))
        case "image":
            guard let src = o["src"] as? String, let r = o["rect"] as? [Double], r.count == 4 else { return nil }
            kind = .image(src, CGRect(x: r[0], y: r[1], width: r[2], height: r[3]))
        default:
            return nil
        }
        return Op(kind: kind, m: m, alpha: alpha, fx: fx, clips: clipIds)
    }

    static func paintColor(_ v: Any) -> PaintColor? {
        if let s = v as? String { return .color(color(s)) }
        if let t = v as? [String: Any], let tok = t["tok"] as? String {
            return .token(tok, (t["a"] as? NSNumber)?.doubleValue ?? 1, color(t["fb"] as? String ?? "#000000FF"))
        }
        return nil
    }

    static func paint(_ v: Any) -> Paint? {
        if let c = paintColor(v) { return .solid(c) }
        guard let g = v as? [String: Any] else { return nil }
        let stops: [(Double, PaintColor)] = (g["stops"] as? [[Any]] ?? []).compactMap { s in
            guard s.count == 2, let t = (s[0] as? NSNumber)?.doubleValue, let c = paintColor(s[1]) else { return nil }
            return (t, c)
        }
        if let l = g["lin"] as? [Double], l.count == 4 {
            return .linear(stops, CGPoint(x: l[0], y: l[1]), CGPoint(x: l[2], y: l[3]))
        }
        if let r = g["rad"] as? [Double], r.count == 4 {
            return .radial(stops, CGPoint(x: r[0], y: r[1]), r[2], r[3])
        }
        if let c = g["conic"] as? [Double], c.count == 3 {
            return .conic(stops, CGPoint(x: c[0], y: c[1]), c[2])
        }
        return nil
    }

    /// "#RRGGBBAA" (or "#RRGGBB"), sRGB.
    static func color(_ s: String) -> Color {
        var h = s.hasPrefix("#") ? String(s.dropFirst()) : s
        if h.count == 6 { h += "FF" }
        guard h.count == 8, let v = UInt64(h, radix: 16) else { return .black }
        return Color(.sRGB, red: Double((v >> 24) & 0xFF) / 255, green: Double((v >> 16) & 0xFF) / 255,
                     blue: Double((v >> 8) & 0xFF) / 255, opacity: Double(v & 0xFF) / 255)
    }

    /// SVG path data limited to M L Q C Z with absolute coordinates.
    static func path(_ d: String) -> Path {
        var p = Path()
        var nums: [CGFloat] = []
        var cmd: Character = " "
        func flush() {
            switch cmd {
            case "M": if nums.count >= 2 { p.move(to: CGPoint(x: nums[0], y: nums[1])) }
            case "L": if nums.count >= 2 { p.addLine(to: CGPoint(x: nums[0], y: nums[1])) }
            case "Q": if nums.count >= 4 { p.addQuadCurve(to: CGPoint(x: nums[2], y: nums[3]), control: CGPoint(x: nums[0], y: nums[1])) }
            case "C": if nums.count >= 6 {
                p.addCurve(to: CGPoint(x: nums[4], y: nums[5]), control1: CGPoint(x: nums[0], y: nums[1]),
                           control2: CGPoint(x: nums[2], y: nums[3]))
            }
            case "Z": p.closeSubpath()
            default: break
            }
            nums.removeAll(keepingCapacity: true)
        }
        var token = ""
        func endNumber() {
            if !token.isEmpty, let v = Double(token) { nums.append(CGFloat(v)) }
            token = ""
        }
        for ch in d {
            if ch == "M" || ch == "L" || ch == "Q" || ch == "C" || ch == "Z" {
                endNumber(); flush(); cmd = ch
            } else if ch == " " || ch == "," {
                endNumber()
            } else if ch == "-" {
                if !token.isEmpty && !token.hasSuffix("e") { endNumber() }
                token.append(ch)
            } else if ch == "." && token.contains(".") && !token.contains("e") {
                endNumber(); token.append(ch)
            } else {
                token.append(ch)
            }
        }
        endNumber(); flush()
        return p
    }
}

// MARK: - Drawing

enum FlameySkinArt {
    /// Replays `layer` into `ctx` (origin at the centre of Flamey's square)
    /// at `u` points per body unit. `palette` resolves palette tokens (nil =
    /// his own lifecycle colours: each token's recorded fallback).
    static func draw(_ layer: FlameySkinLayer?, in ctx: inout GraphicsContext, u: CGFloat, palette: FlameyPalette?) {
        guard let layer else { return }
        let toPoints = CGAffineTransform(scaleX: u, y: u)
        for op in layer.ops {
            var c = ctx
            for id in op.clips where id < layer.clips.count {
                let clip = layer.clips[id]
                let p = clip.path.applying(toPoints)
                if clip.inverse {
                    c.clip(to: p, style: FillStyle(eoFill: clip.eo), options: .inverse)
                } else {
                    c.clip(to: p, style: FillStyle(eoFill: clip.eo))
                }
            }
            if op.alpha < 0.9999 { c.opacity *= op.alpha }
            for f in op.fx {
                switch f {
                case .blur(let r): c.addFilter(.blur(radius: r * u))
                case .shadow(let col, let r, let x, let y): c.addFilter(.shadow(color: col, radius: r * u, x: x * u, y: y * u))
                }
            }
            if let m = op.m {
                // Local coordinates: draw through m (local → body) and u.
                c.concatenate(m.concatenating(toPoints))
                render(op.kind, in: &c, k: 1, layer: layer, palette: palette)
            } else {
                render(op.kind, in: &c, k: u, layer: layer, palette: palette)
            }
        }
    }

    private static func render(_ kind: FlameySkinLayer.Kind, in c: inout GraphicsContext, k: CGFloat,
                               layer: FlameySkinLayer, palette: FlameyPalette?) {
        let t = CGAffineTransform(scaleX: k, y: k)
        switch kind {
        case .fill(let path, let paint, let eo):
            c.fill(path.applying(t), with: shading(paint, k, palette), style: FillStyle(eoFill: eo))
        case .stroke(let path, let paint, let w, let cap, let join, let miter, let dash, let phase):
            c.stroke(path.applying(t), with: shading(paint, k, palette),
                     style: StrokeStyle(lineWidth: w * k, lineCap: cap, lineJoin: join, miterLimit: miter,
                                        dash: dash.map { $0 * k }, dashPhase: phase * k))
        case .image(let src, let rect):
            if let img = layer.images[src] {
                let r = CGRect(x: rect.minX * k, y: rect.minY * k, width: rect.width * k, height: rect.height * k)
                c.draw(Image(decorative: img, scale: 1), in: r)
            }
        }
    }

    private static func shading(_ p: FlameySkinLayer.Paint, _ k: CGFloat, _ palette: FlameyPalette?) -> GraphicsContext.Shading {
        func pt(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x * k, y: q.y * k) }
        func grad(_ stops: [(Double, FlameySkinLayer.PaintColor)]) -> Gradient {
            Gradient(stops: stops.map { Gradient.Stop(color: resolve($0.1, palette), location: $0.0) })
        }
        switch p {
        case .solid(let c): return .color(resolve(c, palette))
        case .linear(let s, let a, let b): return .linearGradient(grad(s), startPoint: pt(a), endPoint: pt(b))
        case .radial(let s, let c, let r0, let r1):
            return .radialGradient(grad(s), center: pt(c), startRadius: r0 * k, endRadius: r1 * k)
        case .conic(let s, let c, let deg): return .conicGradient(grad(s), center: pt(c), angle: .degrees(deg))
        }
    }

    static func resolve(_ c: FlameySkinLayer.PaintColor, _ palette: FlameyPalette?) -> Color {
        switch c {
        case .color(let col): return col
        case .token(let name, let a, let fallback):
            guard let palette, let base = token(name, palette) else { return fallback }
            return base.opacity(a)
        }
    }

    static func token(_ name: String, _ p: FlameyPalette) -> Color? {
        let parts = name.split(separator: ".")
        switch parts.first {
        case "outer": return pick(p.outer, parts)
        case "inner": return pick(p.inner, parts)
        case "glow": return p.glow
        case "core": return p.core
        case "eye": return p.eye
        case "rim": return p.rim
        default: return nil
        }
    }

    private static func pick(_ cs: [Color], _ parts: [Substring]) -> Color? {
        guard !cs.isEmpty else { return nil }
        let i = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return cs[min(max(0, i), cs.count - 1)]
    }
}

// MARK: - The catalog

final class FlameySkinCatalog {
    /// The skin format this renderer draws. Bump with every new op, paint,
    /// motion or effect kind; older skins keep drawing.
    static let format = 1

    static let shared = FlameySkinCatalog()

    private let lock = NSLock()
    private var skins: [String: FlameySkin] = [:]
    private(set) var version: String = ""

    /// The App Group container's copy of the last download.
    static var cacheURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.mileaday.shared")?
            .appendingPathComponent("FlameySkins.json")
    }

    /// Posted (main thread) after a download changes the catalog.
    static let didChange = Notification.Name("FlameySkinCatalogDidChange")

    /// `bundled: false` = an empty catalog (to validate a download before
    /// it replaces anything).
    init(bundled: Bool = true) {
        guard bundled else { return }
        // ONE parse, not two (the widgets' memory is tight): the download is
        // the server's whole set, so when it is newer than this build's copy
        // it is all we need; an older one (from before an app update) loses.
        let bundle = Bundle.main.url(forResource: "FlameySkins", withExtension: "json")
        let cache = Self.cacheURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        func modified(_ u: URL?) -> Date {
            u.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate } ?? .distantPast
        }
        let source = cache != nil && modified(cache) > modified(bundle) ? cache : bundle
        if let source, let data = try? Data(contentsOf: source), load(data, replacing: true) > 0 { return }
        // The chosen copy was unreadable: fall back to the other.
        if let other = source == cache ? bundle : cache, let data = try? Data(contentsOf: other) {
            load(data, replacing: true)
        }
    }

    subscript(id: String) -> FlameySkin? {
        lock.lock(); defer { lock.unlock() }
        return skins[id]
    }

    /// Every skin this renderer can draw, in Closet order.
    var all: [FlameySkin] {
        lock.lock(); defer { lock.unlock() }
        return skins.values.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }

    /// Loads `{ "version", "skins": [...] }` (or a bare array). Skins with a
    /// newer format are skipped; a later load overrides earlier skins by id.
    @discardableResult
    func load(_ data: Data, replacing: Bool) -> Int {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return 0 }
        let list: [[String: Any]]
        var v = ""
        if let dict = obj as? [String: Any] {
            list = dict["skins"] as? [[String: Any]] ?? []
            v = dict["version"] as? String ?? ""
        } else {
            list = obj as? [[String: Any]] ?? []
        }
        var parsed: [String: FlameySkin] = [:]
        for j in list {
            if let s = FlameySkin(json: j), s.format <= Self.format { parsed[s.id] = s }
        }
        lock.lock()
        if replacing { skins = parsed } else { skins.merge(parsed) { _, new in new } }
        if !v.isEmpty { version = v }
        lock.unlock()
        return parsed.count
    }

    /// Loads every `<id>.json` in a folder (the match check, the exporter).
    func loadDirectory(_ url: URL) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        var list: [Any] = []
        for f in files where f.pathExtension == "json" {
            if let d = try? Data(contentsOf: f), let j = try? JSONSerialization.jsonObject(with: d) { list.append(j) }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: list) else { return 0 }
        return load(data, replacing: true)
    }
}
