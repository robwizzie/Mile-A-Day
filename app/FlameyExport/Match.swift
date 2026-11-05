import AppKit
import SwiftUI

// MATCH CHECK — the gate for migrating Flamey's wardrobe to skins. Renders
// every item on every surface twice through the REAL composition code
// (FlameyDressedBody → FlameyOutfitLayer): once with the Swift art code
// (`FlameyOutfitLayer.legacyArt = true`) and once from the skin files in
// backend/flamey-skins, then compares the two pixel by pixel.
//
//   bash app/FlameyExport/match.sh
//
// out/match-swift/report.json   every item × surface: % of its pixels that differ
// out/match-swift/<surface>/<id>.png   [code | skin | diff] for any item ≥ 1%
// out/match-swift/summary.txt   the totals

@main
struct FlameyMatchMain {
    @MainActor static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3 else { print("usage: flamey-match <skins dir> <out dir>"); return }
        FlameyMatch(skins: URL(fileURLWithPath: args[1]), out: URL(fileURLWithPath: args[2])).run()
    }
}

@MainActor
final class FlameyMatch {
    let S: CGFloat = 128
    let scale: CGFloat = 2
    let skinsDir: URL
    let out: URL

    struct Surface { let name: String; let reach: CGFloat; let detail: FlameyRenderDetail }
    let surfaces = [
        Surface(name: "card", reach: 0.9, detail: .full),
        Surface(name: "tile", reach: 0.8, detail: .full),
        Surface(name: "hero", reach: 0.62, detail: .full),
        Surface(name: "widget", reach: 0.9, detail: .compact),
    ]

    let date: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 3; c.day = 4; c.hour = 12
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    init(skins: URL, out: URL) {
        skinsDir = skins
        self.out = out.appendingPathComponent("match-swift")
    }

    func run() {
        try? FileManager.default.removeItem(at: out)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let loaded = FlameySkinCatalog.shared.loadDirectory(skinsDir)
        var rows: [[String: Any]] = []
        var lines: [String] = ["skins loaded: \(loaded)"]
        var under = 0, total = 0, missing: [String] = []
        var codeTime = 0.0, skinTime = 0.0

        for item in FlameyItem.allCases {
            if FlameySkinCatalog.shared[item.rawValue] == nil { missing.append(item.rawValue) }
            for s in surfaces {
                let look = makeLook(item, s.detail)
                if look.items.isEmpty && item.slot != .color { continue }
                var t0 = Date()
                FlameyOutfitLayer.legacyArt = true
                guard let code = render(look, s) else { continue }
                codeTime += Date().timeIntervalSince(t0)
                t0 = Date()
                FlameyOutfitLayer.legacyArt = false
                guard let skin = render(look, s) else { continue }
                skinTime += Date().timeIntervalSince(t0)
                let plain = render(makeLook(nil, s.detail), s)
                let (pct, bad, region) = compare(code, skin, plain)
                total += 1
                if pct < 1 { under += 1 }
                rows.append(["id": item.rawValue, "surface": s.name, "pct": (pct * 100).rounded() / 100,
                             "bad": bad, "region": region])
                if pct >= 1 { writeTriptych(code, skin, "\(s.name)/\(item.rawValue).png") }
            }
        }
        FlameyOutfitLayer.legacyArt = false

        let worst = rows.sorted { ($0["pct"] as! Double) > ($1["pct"] as! Double) }
        lines.append("\(under)/\(total) item renders differ by under 1% from the Swift art")
        lines.append(String(format: "render time: code %.2fs, skins %.2fs", codeTime, skinTime))
        if !missing.isEmpty { lines.append("NO SKIN FILE: " + missing.joined(separator: ", ")) }
        lines.append("worst:")
        for r in worst.prefix(25) {
            lines.append(String(format: "  %6.2f%%  %@ %@", r["pct"] as! Double, r["surface"] as! String, r["id"] as! String))
        }
        let summary = lines.joined(separator: "\n")
        try? summary.write(to: out.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: out.appendingPathComponent("report.json"))
        }
        print(lines.prefix(4).joined(separator: "\n"))
    }

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
        return FlameyLook.resolve(owned: [item], choice: choice, date: date, detail: detail,
                                  timeZone: TimeZone(identifier: "UTC")!)
    }

    func render(_ look: FlameyLook, _ s: Surface) -> CGImage? {
        let probe = FlameyDressedBody<EmptyView, EmptyView>.figure(look: look, health: .healthy, size: S, scale: 1)
        let fig = FlameyDressedBody<EmptyView, EmptyView>.figure(look: look, health: .healthy, size: S,
                                                                 scale: probe.effectiveBodyScale)
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
        r.scale = scale
        return r.cgImage
    }

    func pixels(_ img: CGImage) -> [UInt8] {
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { p in
            let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return buf
    }

    /// (% of the item's pixels that differ, differing, item pixels). A pixel
    /// differs only if no pixel within 1px of it in the other render matches
    /// (antialiasing moves half a pixel); the item's pixels are where either
    /// render differs from the plain figure.
    func compare(_ a: CGImage, _ b: CGImage, _ plain: CGImage?) -> (Double, Int, Int) {
        let w = a.width, h = a.height
        let pa = pixels(a), pb = pixels(b)
        let pp = plain.map(pixels) ?? [UInt8](repeating: 0, count: pa.count)
        let T = 40
        func far(_ x: [UInt8], _ i: Int, _ y: [UInt8], _ j: Int) -> Bool {
            for c in 0..<4 where abs(Int(x[i + c]) - Int(y[j + c])) > T { return true }
            return false
        }
        var region = 0, bad = 0
        for py in 0..<h {
            for px in 0..<w {
                let i = (py * w + px) * 4
                guard far(pa, i, pp, i) || far(pb, i, pp, i) else { continue }
                region += 1
                var off = true
                outer: for dy in -1...1 {
                    for dx in -1...1 {
                        let qx = px + dx, qy = py + dy
                        guard qx >= 0, qy >= 0, qx < w, qy < h else { continue }
                        if !far(pa, i, pb, (qy * w + qx) * 4) { off = false; break outer }
                    }
                }
                if off { bad += 1 }
            }
        }
        return (region == 0 ? 0 : Double(bad) * 100 / Double(region), bad, region)
    }

    func writeTriptych(_ a: CGImage, _ b: CGImage, _ rel: String) {
        let w = a.width, h = a.height
        let pa = pixels(a), pb = pixels(b)
        var diff = [UInt8](repeating: 0, count: w * h * 4)
        for i in stride(from: 0, to: pa.count, by: 4) {
            var d = 0
            for c in 0..<4 { d = max(d, abs(Int(pa[i + c]) - Int(pb[i + c]))) }
            diff[i] = d > 40 ? 255 : 0
            diff[i + 1] = d > 40 ? 0 : UInt8(min(255, (Int(pa[i + 3]) + Int(pb[i + 3])) / 4))
            diff[i + 3] = 255
        }
        guard let ctx = CGContext(data: nil, width: w * 3, height: h, bitsPerComponent: 8, bytesPerRow: w * 12,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w * 3, height: h))
        ctx.draw(a, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(b, in: CGRect(x: w, y: 0, width: w, height: h))
        let dctx = diff.withUnsafeMutableBytes { p in
            CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .makeImage()
        }
        if let d = dctx { ctx.draw(d, in: CGRect(x: w * 2, y: 0, width: w, height: h)) }
        guard let img = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { return }
        let url = out.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: url)
    }
}
