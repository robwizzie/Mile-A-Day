import AppKit
import SwiftUI

// FLAMEY EXPORTER — runs TODAY's Flamey art code and saves what it draws, so
// the skin files come from the real art instead of being redrawn by hand.
// `run.sh` compiles the widget extension's Flamey files, a renamed copy of
// FlameyArt.swift drawing into `RecContext` (RecContext.swift), and this file
// into a command-line tool. macOS + Xcode only; no project, no simulator.
//
// out/
//   meta.json                     catalog-wide numbers (stage, constants, plain anchors)
//   skins-raw/<id>.json           one item: its rules + every recorded layer
//   ref/<surface>/<id>.png        the dressed figure as the app draws it today —
//                                 the match-check baseline
//   log.txt                       what was written, what needs attention
//
// A recorded layer is in BODY UNITS (origin at the centre of Flamey's square,
// y down, 1 = u) — the op format is documented at the top of RecContext.swift.
// Layer keys name the part and the conditions it was drawn under, e.g.
// "behind@reach=0.62,low=1" or "companion-body@pose=cheer".

@main
struct FlameyExportMain {
    @MainActor static func main() {
        let args = CommandLine.arguments
        let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "out", isDirectory: true)
        FlameyExporter(out: out).run()
    }
}

@MainActor
final class FlameyExporter {
    /// Flamey's square for the reference PNGs, in points.
    let S: CGFloat = 128
    let pngScale: CGFloat = 2
    let out: URL
    var log: [String] = []
    var written = 0
    var failures: [String] = []
    var attention: [String] = []

    /// The reaches surfaces actually pass (`wardrobeReach` / `reach:`):
    /// cards and shares 0.9, Closet tiles 0.8, the dashboard hero 0.62.
    let reaches: [CGFloat] = [0.9, 0.8, 0.62]

    struct Surface {
        let name: String
        let reach: CGFloat
        let detail: FlameyRenderDetail
    }

    let surfaces = [
        Surface(name: "card", reach: 0.9, detail: .full),
        Surface(name: "tile", reach: 0.8, detail: .full),
        Surface(name: "hero", reach: 0.62, detail: .full),
        Surface(name: "widget", reach: 0.9, detail: .compact),
    ]

    let poses: [FlameArmPose] = [.rest, .cheer, .highFive, .cheeks, .tucked, .feedOut, .feed, .flail]

    /// A day that is no holiday anywhere (Mar 4), noon UTC: `resolve` puts on
    /// exactly the one item chosen.
    let date: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 3; c.day = 4; c.hour = 12
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()
    let utc = TimeZone(identifier: "UTC")!

    /// A palette of marker colours: art drawn with it shows which of its
    /// colours come from his palette (→ `{"tok": "outer.1"}` in the skin).
    static let markerHex: [(String, UInt32)] = [
        ("outer.0", 0xF10001), ("outer.1", 0xF10002), ("outer.2", 0xF10003), ("outer.3", 0xF10004),
        ("inner.0", 0xF10011), ("inner.1", 0xF10012), ("inner.2", 0xF10013),
        ("glow", 0xF10021), ("core", 0xF10022), ("eye", 0xF10023), ("rim", 0xF10024),
    ]
    let markerPalette: FlameyPalette = {
        func m(_ v: UInt32) -> Color { FlameyPalette.hex(v) }
        return FlameyPalette(outer: [m(0xF10001), m(0xF10002), m(0xF10003), m(0xF10004)],
                             inner: [m(0xF10011), m(0xF10012), m(0xF10013)],
                             glow: m(0xF10021), core: m(0xF10022), eye: m(0xF10023), rim: m(0xF10024))
    }()
    lazy var markerNames: [String: String] = {
        var d: [String: String] = [:]
        for (name, v) in Self.markerHex { d[String(format: "#%06X", v)] = name }
        return d
    }()

    init(out: URL) { self.out = out }

    // MARK: - Run

    func run() {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for s in surfaces { reference(nil, id: "_plain", s) }
        for item in FlameyItem.allCases {
            var skin = itemMeta(item)
            let (art, pivots) = record(item)
            skin["art"] = art
            if !pivots.isEmpty { skin["pivots"] = pivots }
            write(json: skin, to: "skins-raw/\(item.rawValue).json")
            for s in surfaces { reference(item, id: item.rawValue, s) }
        }
        write(json: catalogMeta(), to: "meta.json")

        log.append("items: \(FlameyItem.allCases.count)  files: \(written)  failures: \(failures.count)  attention: \(attention.count)")
        for f in failures { log.append("FAILED \(f)") }
        for a in attention { log.append("CHECK \(a)") }
        try? log.joined(separator: "\n").write(to: out.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        print(log.suffix(1 + failures.count).joined(separator: "\n"))
    }

    // MARK: - Recording one item's art

    var u: CGFloat { S }

    func anchors(lift: CGFloat = 0) -> FlameyArtRec.Anchors {
        FlameyArtRec.anchors(size: S, scale: 1, lift: lift, stand: FlameyArtRec.legLength)
    }

    func rec(_ draw: (inout RecContext) -> Void) -> [String: Any] {
        let sink = RecSink(u: u)
        var ctx = RecContext(sink: sink)
        draw(&ctx)
        return sink.recording
    }

    func key(_ v: CGFloat) -> String { String(format: "%g", Double(v)) }

    /// Every layer the item draws, under every condition that changes it.
    func record(_ item: FlameyItem) -> ([String: Any], [String: Any]) {
        var art: [String: Any] = [:]
        var pivots: [String: Any] = [:]
        let a = anchors()
        let u = self.u

        switch item.slot {
        case .color:
            if item == .jackOLantern || item == .twinkleLights {
                art["crown"] = rec { FlameyArtRec.drawMonthCrown(item, in: &$0, a: a, u: u) }
            }

        case .head, .eyes, .chest, .costume:
            art["front"] = paletteAware(item) { ctx, palette in
                FlameyArtRec.drawFront(item, in: &ctx, a: a, u: u, palette: palette, jets: true)
            }
            if item == .heartBopper {
                let seat = a.topY + FlameyArtRec.bopperSeat * u
                art["bopper-band"] = rec { c in
                    c.translateBy(x: 0, y: seat)
                    FlameyArtRec.drawHeartBopperBand(in: &c, u: u)
                }
                // The springs' canvas (0.7u square, offset up 0.30u) puts its
                // drawing origin at (0, seat) and sways about its bottom edge.
                art["bopper-springs"] = rec { c in
                    c.translateBy(x: 0, y: seat)
                    FlameyArtRec.drawHeartBopper(in: &c, u: u)
                }
                pivots["bopper-springs"] = [0, num((seat + 0.05 * u) / u)]
            }

        case .feet:
            for jets in [true, false] {
                let lift = jets ? item.hoverLift : 0
                let fa = anchors(lift: lift)
                art["front@jets=\(jets ? 1 : 0)"] = rec { FlameyArtRec.drawFront(item, in: &$0, a: fa, u: u, palette: nil, jets: jets) }
            }

        case .back:
            for r in reaches {
                for glow in (item == .goldenWings ? [true, false] : [false]) {
                    let k = "behind@reach=\(key(r))" + (item == .goldenWings ? ",glow=\(glow ? 1 : 0)" : "")
                    art[k] = rec { FlameyArtRec.drawBack(item, in: &$0, a: a, u: u, reach: r, glow: glow) }
                }
            }

        case .trail:
            for r in reaches {
                for low in [false, true] {
                    art["behind@reach=\(key(r)),low=\(low ? 1 : 0)"] = rec {
                        FlameyArtRec.drawTrail(item, in: &$0, a: a, u: u, reach: r, low: low)
                    }
                }
            }

        case .held:
            for r in reaches {
                art["held-body@reach=\(key(r))"] = rec { c in
                    FlameyArtRec.applyHeldTight(item, &c, a: a, u: u, reach: r)
                    FlameyArtRec.held(item, &c, a, u, layer: .body)
                }
                let grip = FlameyArtRec.heldPoint(item, FlameyArtRec.heldGrip(item), a: a, u: u, reach: r)
                pivots["held-body@reach=\(key(r))"] = [num(grip.x / u), num(grip.y / u)]
                if let p = FlameyArtRec.heldAccentPivot(item) {
                    art["held-accent@reach=\(key(r))"] = rec { c in
                        FlameyArtRec.applyHeldTight(item, &c, a: a, u: u, reach: r)
                        FlameyArtRec.held(item, &c, a, u, layer: .accent)
                    }
                    let q = FlameyArtRec.heldPoint(item, p, a: a, u: u, reach: r)
                    pivots["held-accent@reach=\(key(r))"] = [num(q.x / u), num(q.y / u)]
                }
            }

        case .companion:
            let floats = FlameyOutfitLayer.floats(item)
            art["companion-shadow"] = rec { FlameyArtRec.drawCompanionShadow(item, in: &$0, a: a, u: u, floats: floats) }
            for pose in poses {
                art["companion-body@pose=\(String(describing: pose))"] = paletteAware(item) { ctx, palette in
                    FlameyArtRec.drawCompanion(item, in: &ctx, a: a, u: u, palette: palette, pose: pose)
                }
            }

        case .aura, .bubble:
            break // built-in effect pieces: no geometry of their own (see docs)
        }
        return (art, pivots)
    }

    /// Records the art twice — with no palette (his own lifecycle colours)
    /// and with the marker palette — and turns every colour that came from
    /// the palette into a token whose fallback is the no-palette colour.
    func paletteAware(_ item: FlameyItem, _ draw: (inout RecContext, FlameyPalette?) -> Void) -> [String: Any] {
        var plain = rec { draw(&$0, nil) }
        let marked = rec { draw(&$0, markerPalette) }
        guard var ops = plain["ops"] as? [[String: Any]], let mops = marked["ops"] as? [[String: Any]] else { return plain }
        if ops.count != mops.count {
            attention.append("\(item.rawValue): draws a different number of shapes with a palette (\(ops.count) vs \(mops.count)) — palette tokens skipped")
            return plain
        }
        var mapped = 0, derived = 0
        for i in ops.indices {
            if let p = ops[i]["paint"], let mp = mops[i]["paint"] {
                let (np, m, d) = tokenize(p, mp)
                ops[i]["paint"] = np
                mapped += m; derived += d
            }
        }
        plain["ops"] = ops
        if derived > 0 { attention.append("\(item.rawValue): \(derived) colour(s) derived from the palette but not equal to one of its colours") }
        if mapped > 0 { plain["palette_tokens"] = mapped }
        return plain
    }

    /// (paint, mapped, derived)
    func tokenize(_ p: Any, _ mp: Any) -> (Any, Int, Int) {
        if let s = p as? String, let ms = mp as? String {
            if s == ms { return (s, 0, 0) }
            let rgb = String(ms.prefix(7))
            if let name = markerNames[rgb] {
                return (["tok": name, "a": alpha(ms), "fb": s] as [String: Any], 1, 0)
            }
            return (s, 0, 1)
        }
        if var d = p as? [String: Any], let md = mp as? [String: Any],
           let stops = d["stops"] as? [[Any]], let mstops = md["stops"] as? [[Any]], stops.count == mstops.count {
            var mapped = 0, derived = 0
            var out: [[Any]] = []
            for (s, ms) in zip(stops, mstops) {
                let (c, m, dv) = tokenize(s[1], ms[1])
                out.append([s[0], c]); mapped += m; derived += dv
            }
            d["stops"] = out
            return (d, mapped, derived)
        }
        return (p, 0, 0)
    }

    func alpha(_ hex8: String) -> Double {
        guard hex8.count == 9, let v = UInt8(hex8.suffix(2), radix: 16) else { return 1 }
        return num(Double(v) / 255)
    }

    // MARK: - Reference PNGs (today's app, the match-check baseline)

    func makeLook(_ item: FlameyItem?, _ detail: FlameyRenderDetail) -> FlameyLook {
        guard let item else {
            var l = FlameyLook()
            l.detail = detail
            return l
        }
        if item.isMoodProp {
            var l = FlameyLook()
            l.detail = detail
            l.wear(item)
            return l
        }
        var choice = FlameyLookChoice()
        choice[item.slot] = item
        return FlameyLook.resolve(owned: [item], choice: choice, date: date, detail: detail, timeZone: utc)
    }

    func figure(_ look: FlameyLook) -> FlameBuddyFigure {
        let probe = FlameyDressedBody<EmptyView, EmptyView>.figure(look: look, health: .healthy, size: S, scale: 1)
        return FlameyDressedBody<EmptyView, EmptyView>.figure(look: look, health: .healthy, size: S,
                                                              scale: probe.effectiveBodyScale)
    }

    func reference(_ item: FlameyItem?, id: String, _ s: Surface) {
        let look = makeLook(item, s.detail)
        if let item, look.items.isEmpty, item.slot != .color { return }
        let fig = figure(look)
        let view = ZStack {
            Group {
                if look.detail == .compact {
                    FlameyDressedFigure(look: look, health: .healthy, size: S, scale: fig.effectiveBodyScale)
                } else {
                    FlameyDressedBody<EmptyView, EmptyView>(look: look, arms: .rest, reach: s.reach, still: true, figure: fig)
                }
            }
            .frame(width: S, height: S)
        }
        .frame(width: 3 * S, height: 3 * S)
        let r = ImageRenderer(content: view)
        r.scale = pngScale
        var ok = false
        if let cg = r.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            ok = (try? data.write(to: url("ref/\(s.name)/\(id).png"))) != nil
        }
        record(ok, "ref/\(s.name)/\(id).png")
    }

    // MARK: - Metadata

    func itemMeta(_ item: FlameyItem) -> [String: Any] {
        var m: [String: Any] = [
            "id": item.rawValue,
            "slot": item.slot.rawValue,
            "name": item.displayName,
            "family": item.family.rawValue,
            "unlock": unlockMeta(item.unlock),
            "unlock_copy": item.unlockCopy,
            "holidays": item.holidays.map(\.rawValue),
            "hides": item.hides.map(\.rawValue).sorted(),
            "clashes": FlameyItem.allCases.filter { $0 != item && item.clashes(with: $0) }.map(\.rawValue),
            "mood_prop": item.isMoodProp,
            "compact": item.slot.survivesCompact,
            "hover_lift": num(item.hoverLift),
            "head_rise": num(FlameyArtRec.headRise(item)),
            "head_scale": num(FlameyArtRec.headScale(item)),
            "is_cape": FlameyArtRec.isCape(item),
        ]
        if item.slot == .held {
            let hm = FlameyArtRec.heldMotion(item)
            m["held"] = [
                "up": FlameyArtRec.heldUp(item),
                "hand": pt(FlameyArtRec.heldHand(item)),
                "tight_hand": pt(FlameyArtRec.tightHeldHand(item)),
                "grip": pt(FlameyArtRec.heldGrip(item)),
                "accent_pivot": FlameyArtRec.heldAccentPivot(item).map { pt($0) as Any } ?? NSNull(),
                "tight_scale": num(FlameyArtRec.tightHeldScale(item)),
                "wobble": hm.wobble, "period": hm.period, "accent": String(describing: hm.accent),
                "tile_framing": tuple3(FlameyArtRec.heldTileFraming(item)),
            ] as [String: Any]
        }
        if item.slot == .companion { m["floats"] = FlameyOutfitLayer.floats(item) }
        if let p = FlameyPalette.palette(for: item) { m["palette"] = reflect(p) }
        if item.slot == .head || item.slot == .costume {
            m["month_crown_rise"] = num(FlameyArtRec.monthCrownRise(item))
        }
        return m
    }

    func unlockMeta(_ u: FlameyUnlock) -> Any {
        switch u {
        case .always: return "always"
        case .badge(let id): return ["badge": id]
        default: return String(describing: u)
        }
    }

    func catalogMeta() -> [String: Any] {
        var plain: [String: Any] = [:]
        let a = anchors()
        plain["anchors_u"] = ["bottom": num(a.bottom / u), "ground": num(a.ground / u), "face_y": num(a.faceY / u),
                              "eye_x": num(a.eyeX / u), "top_y": num(a.topY / u), "feet": num(a.feet / u)]
        return [
            "format": 1,
            "units": "body units: origin at the centre of Flamey's square, y down, 1 = u (= S × body scale)",
            "reference": ["S": S, "stage": 3 * S, "png_scale": pngScale,
                          "surfaces": surfaces.map { ["name": $0.name, "reach": $0.reach,
                                                      "detail": $0.detail.rawValue] as [String: Any] }] as [String: Any],
            "reaches": reaches,
            "poses": poses.map { String(describing: $0) },
            "plain": plain,
            "markers": Dictionary(uniqueKeysWithValues: Self.markerHex.map { ($0.0, String(format: "#%06X", $0.1)) }),
            "constants": [
                "leg_length": num(FlameyArtRec.legLength),
                "leg_spread": num(FlameyArtRec.legSpread),
                "tight_reach": num(FlameyArtRec.tightReach),
                "tight_art_bounds": [num(FlameyArtRec.tightArtBounds.left), num(FlameyArtRec.tightArtBounds.right)],
                "tight_mask_bounds": [num(FlameyArtRec.tightMaskBounds.left), num(FlameyArtRec.tightMaskBounds.right)],
                "tight_top_bound": num(FlameyArtRec.tightTopBound as CGFloat),
                "cape_tuck": num(FlameyArtRec.capeTuck),
                "cape_tight_scale": num(FlameyArtRec.capeTightScale),
                "trail_tuck": num(FlameyArtRec.trailTuck),
                "float_height": num(FlameyArtRec.floatHeight),
                "bopper_seat": num(FlameyArtRec.bopperSeat),
                "chest_top": num(FlameyArtRec.chestTop),
                "ink": hex(FlameyArtRec.ink),
                "compact_threshold": num(FlameyRenderDetail.compactThreshold),
            ] as [String: Any],
        ]
    }

    func pt(_ p: CGPoint) -> [Double] { [num(p.x), num(p.y)] }

    func tuple3(_ t: (CGFloat, CGFloat, CGFloat)) -> [Double] { [num(t.0), num(t.1), num(t.2)] }

    /// Every stored field of a value, colours as hex — survives the palette
    /// struct growing fields without this file changing.
    func reflect(_ value: Any) -> Any {
        if let c = value as? Color { return hex(c) }
        if let cs = value as? [Color] { return cs.map(hex) }
        if let p = value as? UnitPoint { return [num(p.x), num(p.y)] }
        if let b = value as? Bool { return b }
        if let d = value as? Double { return num(d) }
        if let f = value as? CGFloat { return num(f) }
        if let s = value as? String { return s }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let child = mirror.children.first else { return NSNull() }
            return reflect(child.value)
        }
        if mirror.displayStyle == .set || mirror.displayStyle == .collection {
            return mirror.children.map { String(describing: $0.value) }.sorted()
        }
        if mirror.displayStyle == .struct {
            var out: [String: Any] = [:]
            for child in mirror.children {
                if let label = child.label { out[label] = reflect(child.value) }
            }
            return out
        }
        return String(describing: value)
    }

    // MARK: - Writers

    func url(_ rel: String) -> URL {
        let u = out.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        return u
    }

    func write(json: Any, to rel: String) {
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url(rel))
            record(true, rel)
        } catch {
            failures.append("\(rel): \(error)")
        }
    }

    func record(_ ok: Bool, _ rel: String) {
        if ok { written += 1; log.append("ok \(rel)") } else { failures.append(rel) }
    }
}
