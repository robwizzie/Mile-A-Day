import AppKit
import SwiftUI

// FLAMEY EXPORTER — draws every wardrobe item with TODAY's Swift code and
// saves what it drew, so the skin files are generated from the real art
// rather than redrawn by hand. Run by `run.sh` (macOS, no Xcode project):
// it compiles this file together with the widget extension's Flamey files
// (SwiftUI + Foundation only, by design) into a command-line tool.
//
// Every drawing lands in the same 3S × 3S stage with Flamey's S × S square in
// the middle, exactly where `FlameyOutfitLayer` puts it, so one transform maps
// any file back to body units: x_u = (x - 1.5S) / u, y_u = (y - 1.5S) / u
// (y down), u = S × scale. Both numbers are in meta.json.
//
// out/
//   meta.json                         every item's rules + every variant's anchors
//   ref/<variant>/<id>.png            the dressed figure, still — the match-check baseline
//   pdf/<variant>/<id>.dressed.pdf    the same, as vectors
//   pdf/<variant>/<id>.behind.pdf     FlameyOutfitLayer(side: .behind) alone
//   pdf/<variant>/<id>.front.pdf      FlameyOutfitLayer(side: .front) alone
//   pdf/<variant>/<id>.<part>.pdf     the parts that move on their own:
//                                     held body/accent, companion body/shadow,
//                                     heart-bopper band/springs
//   log.txt                           what was written, what failed

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
    /// Flamey's square, in points. Vectors don't care; it sets PNG detail.
    let S: CGFloat = 128
    let pngScale: CGFloat = 2
    let out: URL
    var log: [String] = []
    var written = 0
    var failures: [String] = []

    struct Variant {
        let name: String
        let reach: CGFloat
        let detail: FlameyRenderDetail
    }

    /// The three surfaces the art changes between: a wide card, the hero's
    /// narrow column (`FlameyArt.isTight`), and a widget (`.compact`).
    let variants = [
        Variant(name: "wide", reach: 0.9, detail: .full),
        Variant(name: "tight", reach: 0.6, detail: .full),
        Variant(name: "compact", reach: 0.9, detail: .compact),
    ]

    /// A day that is no holiday anywhere (Mar 4), at noon UTC, so `resolve`
    /// puts on exactly the one item chosen.
    let date: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 3; c.day = 4; c.hour = 12
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()
    let utc = TimeZone(identifier: "UTC")!

    init(out: URL) { self.out = out }

    // MARK: - Run

    func run() {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var items: [[String: Any]] = []
        let all = FlameyItem.allCases

        for v in variants {
            exportOne(nil, id: "_plain", v)
        }
        for item in all {
            var entry = itemMeta(item)
            var perVariant: [String: Any] = [:]
            for v in variants {
                if let m = exportOne(item, id: item.rawValue, v) { perVariant[v.name] = m }
            }
            entry["variants"] = perVariant
            items.append(entry)
        }

        let meta: [String: Any] = [
            "format": 1,
            "stage": ["S": S, "size": 3 * S, "png_scale": pngScale,
                      "note": "x_u = (x - 1.5S)/u, y_u = (y - 1.5S)/u, y down; PDF y is up, flip first"] as [String: Any],
            "date": ISO8601DateFormatter().string(from: date),
            "plain": plainMeta(),
            "items": items,
            "constants": constants(),
        ]
        write(json: meta, to: out.appendingPathComponent("meta.json"))
        log.append("items: \(all.count)  files: \(written)  failures: \(failures.count)")
        for f in failures { log.append("FAILED \(f)") }
        try? log.joined(separator: "\n").write(to: out.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        print(log.suffix(1 + failures.count).joined(separator: "\n"))
    }

    // MARK: - Looks

    func makeLook(_ item: FlameyItem?, _ detail: FlameyRenderDetail) -> FlameyLook {
        guard let item else {
            var l = FlameyLook()
            l.detail = detail
            return l
        }
        if item.isMoodProp {
            // Mood dressing can't be chosen; it goes on by mood. Wear it bare.
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

    // MARK: - One item on one surface

    @discardableResult
    func exportOne(_ item: FlameyItem?, id: String, _ v: Variant) -> [String: Any]? {
        let look = makeLook(item, v.detail)
        if let item, look.items.isEmpty, item.slot != .color {
            return nil // this surface drops the slot (compact) — nothing to draw
        }
        let fig = figure(look)
        let scale = fig.effectiveBodyScale
        let u = S * scale
        let a = FlameyArt.anchors(size: S, scale: scale, lift: look.hoverLift, stand: look.standLift)
        let dir = "\(v.name)"

        // The dressed figure, as a user sees it on that surface.
        let dressed = stage(dressedView(look, fig: fig, reach: v.reach))
        png(dressed, "ref/\(dir)/\(id).png")
        pdf(dressed, "pdf/\(dir)/\(id).dressed.pdf")

        if item != nil {
            pdf(stage(FlameyOutfitLayer(look: look, size: S, scale: scale, side: .behind, still: true, reach: v.reach)),
                "pdf/\(dir)/\(id).behind.pdf")
            pdf(stage(FlameyOutfitLayer(look: look, size: S, scale: scale, side: .front, still: true, reach: v.reach)),
                "pdf/\(dir)/\(id).front.pdf")
        }

        var parts: [String: Any] = [:]
        if let item, look.wears(item) {
            switch item.slot {
            case .held: parts = heldParts(item, look: look, a: a, u: u, reach: v.reach, dir: dir)
            case .companion: parts = companionParts(item, look: look, a: a, u: u, reach: v.reach, dir: dir)
            default: break
            }
            if item == .heartBopper { parts = bopperParts(a: a, u: u, dir: dir) }
        }

        return [
            "worn": look.items.map(\.rawValue),
            "glow": String(describing: look.glow),
            "scale": scale,
            "u": u,
            "hover_lift": look.hoverLift,
            "stand_lift": look.standLift,
            "body_lift": look.bodyLift,
            "shows_arms": look.showsArms,
            "anchors": anchorsMeta(a),
            "parts": parts,
        ]
    }

    @ViewBuilder
    func dressedView(_ look: FlameyLook, fig: FlameBuddyFigure, reach: CGFloat) -> some View {
        if look.detail == .compact {
            FlameyDressedFigure(look: look, health: .healthy, size: S, scale: fig.effectiveBodyScale)
        } else {
            FlameyDressedBody<EmptyView, EmptyView>(look: look, arms: .rest, reach: reach, still: true, figure: fig)
        }
    }

    /// Flamey's S × S square, centred in the 3S × 3S stage.
    func stage<V: View>(_ v: V) -> some View {
        ZStack { v.frame(width: S, height: S) }
            .frame(width: 3 * S, height: 3 * S)
    }

    // MARK: - Parts that move on their own (mirrors FlameyOutfitLayer)

    func heldParts(_ item: FlameyItem, look: FlameyLook, a: FlameyArt.Anchors, u: CGFloat, reach: CGFloat,
                   dir: String) -> [String: Any] {
        let S = self.S
        func layer(_ l: FlameyArt.HeldLayer) -> AnyView {
            AnyView(
                Canvas { ctx, canvas in
                    ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                    FlameyArt.applyHeldTight(item, &ctx, a: a, u: u, reach: reach)
                    FlameyArt.held(item, &ctx, a, u, layer: l)
                }
                .frame(width: 3 * S, height: 3 * S)
            )
        }
        pdf(layer(.body), "pdf/\(dir)/\(item.rawValue).held-body.pdf")
        let accentPivot = FlameyArt.heldAccentPivot(item)
        if accentPivot != nil {
            pdf(layer(.accent), "pdf/\(dir)/\(item.rawValue).held-accent.pdf")
        }
        let m = FlameyArt.heldMotion(item)
        let grip = FlameyArt.heldPoint(item, FlameyArt.heldGrip(item), a: a, u: u, reach: reach)
        var out: [String: Any] = [
            "held-body": ["pivot_stage": point(grip), "motion": "wobble", "degrees": m.wobble,
                          "period": m.period] as [String: Any],
        ]
        if let p = accentPivot {
            let q = FlameyArt.heldPoint(item, p, a: a, u: u, reach: reach)
            out["held-accent"] = ["pivot_stage": point(q), "motion": String(describing: m.accent),
                                  "period": m.period] as [String: Any]
        }
        return out
    }

    func companionParts(_ item: FlameyItem, look: FlameyLook, a: FlameyArt.Anchors, u: CGFloat, reach: CGFloat,
                        dir: String) -> [String: Any] {
        let tight = FlameyArt.isTight(reach)
        let floats = FlameyOutfitLayer.floats(item)
        let k: CGFloat = tight ? 0.60 : FlameyArt.companionScale(for: look)
        let x = tight ? (floats ? 0.30 : 0.26) * u : FlameyArt.companionX(u, reach: reach, look: look)
        let lift = tight && floats ? -0.42 * u : 0
        let palette = FlameyPalette.palette(for: look.color)
        let shadow = ZStack {
            if !(tight && floats) {
                Canvas { ctx, canvas in
                    ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                    ctx.translateBy(x: 0, y: a.ground); ctx.scaleBy(x: k, y: k); ctx.translateBy(x: 0, y: -a.ground)
                    FlameyArt.drawCompanionShadow(item, in: &ctx, a: a, u: u, floats: floats)
                }
                .frame(width: S * 1.6, height: S * 3)
                .offset(x: x)
            }
        }
        .frame(width: 3 * S, height: 3 * S)
        let body = ZStack {
            Canvas { ctx, canvas in
                ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                ctx.translateBy(x: 0, y: a.ground); ctx.scaleBy(x: k, y: k); ctx.translateBy(x: 0, y: -a.ground)
                FlameyArt.drawCompanion(item, in: &ctx, a: a, u: u, palette: palette, pose: .rest)
            }
            .frame(width: S * 1.6, height: S * 3)
            .offset(x: x, y: lift)
        }
        .frame(width: 3 * S, height: 3 * S)
        pdf(shadow, "pdf/\(dir)/\(item.rawValue).companion-shadow.pdf")
        pdf(body, "pdf/\(dir)/\(item.rawValue).companion-body.pdf")
        return [
            "companion-body": ["motion": "bob", "amount_u": floats ? 0.05 : 0.02, "period": 1.6, "floats": floats,
                               "scale": k, "x_stage": x, "lift_stage": lift] as [String: Any],
            "companion-shadow": ["motion": "none"] as [String: Any],
        ]
    }

    func bopperParts(a: FlameyArt.Anchors, u: CGFloat, dir: String) -> [String: Any] {
        let seat = a.topY + FlameyArt.bopperSeat * u
        let band = ZStack {
            Canvas { ctx, canvas in
                ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                FlameyArt.drawHeartBopperBand(in: &ctx, u: u)
            }
            .frame(width: u * 0.6, height: u * 0.6)
            .offset(y: seat)
        }
        .frame(width: 3 * S, height: 3 * S)
        let springs = ZStack {
            Canvas { ctx, canvas in
                ctx.translateBy(x: canvas.width / 2, y: canvas.height - 0.05 * u)
                FlameyArt.drawHeartBopper(in: &ctx, u: u)
            }
            .frame(width: u * 0.7, height: u * 0.7)
            .offset(y: seat - u * 0.30)
        }
        .frame(width: 3 * S, height: 3 * S)
        pdf(band, "pdf/\(dir)/heart_bopper.bopper-band.pdf")
        pdf(springs, "pdf/\(dir)/heart_bopper.bopper-springs.pdf")
        // The springs sway ±6° about the bottom-centre of their 0.7u box.
        let pivot = CGPoint(x: 0, y: seat - u * 0.30 + u * 0.35)
        return [
            "bopper-band": ["motion": "none"] as [String: Any],
            "bopper-springs": ["motion": "sway", "degrees": 6, "period": 1.6, "pivot_stage": point(pivot)] as [String: Any],
        ]
    }

    // MARK: - Metadata

    func itemMeta(_ item: FlameyItem) -> [String: Any] {
        var m: [String: Any] = [
            "id": item.rawValue,
            "slot": item.slot.rawValue,
            "name": item.displayName,
            "family": item.family.rawValue,
            "unlock": unlockMeta(item.unlock) as Any,
            "unlock_copy": item.unlockCopy,
            "holidays": item.holidays.map(\.rawValue),
            "hides": item.hides.map(\.rawValue).sorted(),
            "clashes": FlameyItem.allCases.filter { $0 != item && item.clashes(with: $0) }.map(\.rawValue),
            "mood_prop": item.isMoodProp,
            "survives_compact": item.slot.survivesCompact,
            "hover_lift": item.hoverLift,
            "head_rise": FlameyArt.headRise(item),
            "head_scale": FlameyArt.headScale(item),
            "is_cape": FlameyArt.isCape(item),
        ]
        if item.slot == .held {
            let m2 = FlameyArt.heldMotion(item)
            m["held"] = [
                "up": FlameyArt.heldUp(item),
                "hand": point(FlameyArt.heldHand(item)),
                "tight_hand": point(FlameyArt.tightHeldHand(item)),
                "grip": point(FlameyArt.heldGrip(item)),
                "accent_pivot": FlameyArt.heldAccentPivot(item).map { point($0) as Any } ?? NSNull(),
                "tight_scale": FlameyArt.tightHeldScale(item),
                "wobble": m2.wobble, "period": m2.period, "accent": String(describing: m2.accent),
                "tile_framing": tuple3(FlameyArt.heldTileFraming(item)),
            ] as [String: Any]
        }
        if item.slot == .companion {
            m["floats"] = FlameyOutfitLayer.floats(item)
        }
        if let p = FlameyPalette.palette(for: item) {
            m["palette"] = reflect(p)
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

    func plainMeta() -> [String: Any] {
        var out: [String: Any] = [:]
        for v in variants {
            let l = makeLook(nil, v.detail)
            let fig = figure(l)
            let a = FlameyArt.anchors(size: S, scale: fig.effectiveBodyScale, lift: l.hoverLift, stand: l.standLift)
            out[v.name] = ["u": S * fig.effectiveBodyScale, "scale": fig.effectiveBodyScale,
                           "anchors": anchorsMeta(a)] as [String: Any]
        }
        return out
    }

    func constants() -> [String: Any] {
        [
            "leg_length": FlameyArt.legLength,
            "leg_spread": FlameyArt.legSpread,
            "tight_reach": FlameyArt.tightReach,
            "tight_art_bounds": [FlameyArt.tightArtBounds.left, FlameyArt.tightArtBounds.right],
            "tight_mask_bounds": [FlameyArt.tightMaskBounds.left, FlameyArt.tightMaskBounds.right],
            "tight_top_bound": FlameyArt.tightTopBound as CGFloat,
            "cape_tuck": FlameyArt.capeTuck,
            "cape_tight_scale": FlameyArt.capeTightScale,
            "trail_tuck": FlameyArt.trailTuck,
            "float_height": FlameyArt.floatHeight,
            "bopper_seat": FlameyArt.bopperSeat,
            "chest_top": FlameyArt.chestTop,
            "ink": hex(FlameyArt.ink),
            "compact_threshold": FlameyRenderDetail.compactThreshold,
        ]
    }

    func anchorsMeta(_ a: FlameyArt.Anchors) -> [String: Any] {
        ["bottom": a.bottom, "ground": a.ground, "face_y": a.faceY, "eye_x": a.eyeX, "top_y": a.topY, "feet": a.feet]
    }

    func point(_ p: CGPoint) -> [Double] { [Double(p.x), Double(p.y)] }

    func tuple3(_ t: (CGFloat, CGFloat, CGFloat)) -> [Double] { [Double(t.0), Double(t.1), Double(t.2)] }

    /// Every stored field of a value, colours as hex — survives the palette
    /// struct growing new fields without this file changing.
    func reflect(_ value: Any) -> Any {
        if let c = value as? Color { return hex(c) }
        if let cs = value as? [Color] { return cs.map(hex) }
        if let p = value as? UnitPoint { return [Double(p.x), Double(p.y)] }
        if let b = value as? Bool { return b }
        if let d = value as? Double { return d }
        if let f = value as? CGFloat { return Double(f) }
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

    func hex(_ c: Color) -> String {
        guard let ns = NSColor(c).usingColorSpace(.sRGB) else { return String(describing: c) }
        let r = Int((ns.redComponent * 255).rounded()), g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        let base = String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
        return ns.alphaComponent < 0.999 ? base + String(format: "@%.3f", ns.alphaComponent) : base
    }

    // MARK: - Writers

    func url(_ rel: String) -> URL {
        let u = out.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        return u
    }

    func pdf<V: View>(_ view: V, _ rel: String) {
        let target = url(rel)
        let renderer = ImageRenderer(content: view)
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(target as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            ok = true
        }
        record(ok, rel)
    }

    func png<V: View>(_ view: V, _ rel: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = pngScale
        var ok = false
        if let cg = renderer.cgImage,
           let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            ok = (try? data.write(to: url(rel))) != nil
        }
        record(ok, rel)
    }

    func write(json: Any, to target: URL) {
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: target)
            written += 1
        } catch {
            failures.append("meta.json: \(error)")
        }
    }

    func record(_ ok: Bool, _ rel: String) {
        if ok { written += 1; log.append("ok \(rel)") } else { failures.append(rel) }
    }
}
