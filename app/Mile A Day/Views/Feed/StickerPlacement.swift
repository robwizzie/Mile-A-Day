import SwiftUI
import UIKit
import Vision

// MARK: - Photo analysis
//
// What the composer knows about a photo so stickers can be placed and drawn
// to suit it: where the subject is (Vision's attention saliency, fully
// on-device — no permission, nothing leaves the phone) and how bright each
// part of the 4:5 canvas is. Both are in CANVAS space: normalized 0…1, y
// down, after the same aspect-FILL crop `PostCanvas` draws the photo with.

struct PhotoAnalysis {
    /// Where the subject is, as canvas rects.
    let salient: [CGRect]
    /// Luminance 0…1 on a `gridWidth` × `gridHeight` grid over the canvas,
    /// row-major from the top-left.
    let luma: [Float]

    static let gridWidth = 16
    static let gridHeight = 20

    /// Mean brightness of a canvas rect.
    func brightness(in rect: CGRect) -> Float {
        let w = Self.gridWidth, h = Self.gridHeight
        let x0 = max(0, min(w - 1, Int(rect.minX * CGFloat(w))))
        let x1 = max(x0, min(w - 1, Int(rect.maxX * CGFloat(w))))
        let y0 = max(0, min(h - 1, Int(rect.minY * CGFloat(h))))
        let y1 = max(y0, min(h - 1, Int(rect.maxY * CGFloat(h))))
        var sum: Float = 0
        var n: Float = 0
        for y in y0...y1 {
            for x in x0...x1 {
                sum += luma[y * w + x]
                n += 1
            }
        }
        return n > 0 ? sum / n : 0
    }

    /// Off the main thread: a 16×20 draw and one Vision request.
    static func analyze(_ image: UIImage) async -> PhotoAnalysis {
        await Task.detached(priority: .userInitiated) {
            PhotoAnalysis(salient: PhotoAnalysis.saliency(image), luma: PhotoAnalysis.lumaGrid(image))
        }.value
    }

    /// The aspect-fill crop: the fraction of the image each canvas axis shows.
    private static func visibleFraction(_ size: CGSize) -> (x: CGFloat, y: CGFloat) {
        guard size.width > 0, size.height > 0 else { return (1, 1) }
        let aspect = size.width / size.height
        let canvas: CGFloat = 4.0 / 5.0
        return aspect > canvas ? (canvas / aspect, 1) : (1, aspect / canvas)
    }

    private static func saliency(_ image: UIImage) -> [CGRect] {
        guard let cg = image.cgImage else { return [] }
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: image.imageOrientation.cgOrientation)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first else { return [] }
        let f = visibleFraction(image.size)
        return (observation.salientObjects ?? []).compactMap { object in
            // Vision is normalized to the ORIENTED image with y up.
            let b = object.boundingBox
            let rect = CGRect(x: (b.minX - (1 - f.x) / 2) / f.x,
                              y: ((1 - b.maxY) - (1 - f.y) / 2) / f.y,
                              width: b.width / f.x,
                              height: b.height / f.y)
            let clipped = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            return clipped.isNull || clipped.isEmpty ? nil : clipped
        }
    }

    private static func lumaGrid(_ image: UIImage) -> [Float] {
        let w = gridWidth, h = gridHeight
        let size = CGSize(width: w, height: h)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // UIKit drawing honours the image's orientation, which a raw
        // CGContext draw would not.
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let f = visibleFraction(image.size)
            let drawW = CGFloat(w) / f.x, drawH = CGFloat(h) / f.y
            image.draw(in: CGRect(x: (CGFloat(w) - drawW) / 2, y: (CGFloat(h) - drawH) / 2,
                                  width: drawW, height: drawH))
        }
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let cg = small.cgImage else { return [Float](repeating: 0.4, count: w * h) }
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h,
                                          bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.draw(cg, in: CGRect(origin: .zero, size: size))
            return true
        }
        guard drawn else { return [Float](repeating: 0.4, count: w * h) }
        return pixels.map { Float($0) / 255 }
    }
}

private extension UIImage.Orientation {
    var cgOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

// MARK: - Placement

enum StickerPlacement {
    /// A sticker's rough footprint before it has been measured, as a canvas
    /// fraction. Only for choosing a spot and judging the photo under it —
    /// the editor clamps against the real size once it's drawn.
    static func footprint(of kind: PostStickerKind, scale: CGFloat = 1) -> CGSize {
        let base: CGSize
        switch kind {
        case .stats: base = CGSize(width: 0.6, height: 0.3)
        case .flamey: base = CGSize(width: 0.42, height: 0.4)
        case .route: base = CGSize(width: 0.5, height: 0.42)
        case .number: base = CGSize(width: 0.42, height: 0.16)
        }
        return CGSize(width: base.width * scale, height: base.height * scale)
    }

    static func box(of kind: PostStickerKind, at center: CGPoint, scale: CGFloat = 1) -> CGRect {
        let s = footprint(of: kind, scale: scale)
        return CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2,
                      width: s.width, height: s.height)
    }

    /// The emptiest good spot for a new sticker: off the photo's subject, off
    /// the stickers already there, out of the FRONT & BACK inset and the
    /// editor's top controls — preferring the kind's own default spot when
    /// that is as good as anywhere.
    static func bestSpot(for kind: PostStickerKind, analysis: PhotoAnalysis?,
                         existing: [PlacedSticker], inset: CGRect?) -> CGPoint {
        let preferred = kind.defaultPosition
        var best = preferred
        var bestScore = CGFloat.greatestFiniteMagnitude
        for x in [0.3, 0.5, 0.7] as [CGFloat] {
            for y in stride(from: CGFloat(0.2), through: 0.82, by: 0.06) {
                let center = CGPoint(x: x, y: y)
                let box = Self.box(of: kind, at: center)
                var score: CGFloat = 0
                for subject in analysis?.salient ?? [] { score += overlap(box, subject) * 1.0 }
                for other in existing { score += overlap(box, Self.box(of: other.kind, at: other.pos, scale: other.scale)) * 1.6 }
                if let inset { score += overlap(box, inset) * 2.5 }
                // The Save / Change pills along the top edge — full size even
                // when a short screen shrinks the photo, so they claim more of
                // it there.
                score += overlap(box, CGRect(x: 0, y: 0, width: 1, height: 0.15)) * 1.0
                // A gentle pull home, so a blank photo still puts things
                // where people expect them.
                score += hypot(x - preferred.x, y - preferred.y) * 0.05
                if score < bestScore {
                    bestScore = score
                    best = center
                }
            }
        }
        return best
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    /// Brightness above which white text needs a dark treatment to read.
    static let brightThreshold: Float = 0.66
}

// MARK: - Undo

/// A sticker the bin just took, with where it was, for the undo toast.
struct RemovedSticker: Equatable {
    let sticker: PlacedSticker
    let index: Int
    /// It came off the FRONT view's own set.
    let frontLayer: Bool
    let token = UUID()
}

// MARK: - Memory

/// What the poster put on their last post, so the next one starts there:
/// which stickers (beyond the stats sticker, whose style and spot live in
/// `StickerConfig`) and exactly where. Saved at publish only — browsing the
/// tray and backing out never rewrites it.
struct StickerMemory: Codable {
    struct Item: Codable {
        var kind: String
        var posX: Double
        var posY: Double
        var scale: Double
        var rotation: Double
    }

    var items: [Item]
    /// Whether the stats sticker was on. Optional: absent = on, which is
    /// how every post before this memory existed was made.
    var statsOn: Bool?

    private static let key = "post.sticker.memory.v1"

    static func load() -> StickerMemory? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StickerMemory.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    init(stickers: [PlacedSticker]) {
        items = stickers.compactMap { s in
            guard s.kind != .stats else { return nil }
            return Item(kind: s.kind.memoryKey, posX: s.pos.x, posY: s.pos.y,
                        scale: s.scale, rotation: s.rotation.degrees)
        }
        statsOn = stickers.contains { $0.kind == .stats }
    }

    /// The remembered sticker in `slot`, rebuilt — clamped like
    /// `StickerConfig` clamps its own transform.
    func sticker(in slot: PostStickerKind.Slot) -> PlacedSticker? {
        for item in items {
            guard let kind = PostStickerKind(memoryKey: item.kind), kind.slot == slot else { continue }
            return PlacedSticker(
                kind: kind,
                pos: CGPoint(x: CGFloat(item.posX).clamped(to: StickerConfig.posXRange),
                             y: CGFloat(item.posY).clamped(to: StickerConfig.posYRange)),
                scale: CGFloat(item.scale).clamped(to: StickerConfig.scaleRange),
                rotation: .degrees(item.rotation))
        }
        return nil
    }

    var slots: [PostStickerKind.Slot] {
        items.compactMap { PostStickerKind(memoryKey: $0.kind)?.slot }
    }
}

extension PostStickerKind {
    /// Stable string form for `StickerMemory` — never the Swift case name
    /// directly, so renaming a case can't silently forget everyone's choice.
    var memoryKey: String {
        switch self {
        case .stats: return "stats"
        case .flamey(let f): return "flamey.\(f.rawValue)"
        case .route(let s): return "route.\(s.rawValue)"
        case .number(let k): return "number.\(k.rawValue)"
        }
    }

    init?(memoryKey: String) {
        if memoryKey == "stats" { self = .stats; return }
        let parts = memoryKey.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let raw = parts[1]
        switch parts[0] {
        case "flamey":
            guard let f = FlameySticker(rawValue: raw) else { return nil }
            self = .flamey(f)
        case "route":
            guard let s = RouteStickerStyle(rawValue: raw) else { return nil }
            self = .route(s)
        case "number":
            guard let k = RunStatKind(rawValue: raw) else { return nil }
            self = .number(k)
        default:
            return nil
        }
    }
}
