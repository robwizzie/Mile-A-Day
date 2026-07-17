import ImageIO
import UIKit

/// Transient holding pen for photos snapped DURING a tracked walk/run. The
/// mid-run camera button drops shots here; the post-run photo prompt offers
/// them back ("use one of these, take a fresh one, or skip"). Everything about
/// it is deliberately ephemeral:
/// - Files live in the app sandbox only — never the user's photo library,
///   preserving the camera-only authenticity of posts.
/// - Capped at `maxPhotos` (oldest dropped) so a snap-happy run can't balloon.
/// - Cleared when a new workout starts and when the post-run prompt resolves;
///   anything older than 24h is pruned on read as a crash backstop.
enum MidRunPhotoStash {
    static let maxPhotos = 5
    private static let maxAge: TimeInterval = 24 * 60 * 60

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MidRunPhotos", isDirectory: true)
    }

    /// Timestamp-named files sort chronologically; prunes stale ones first.
    private static func fileURLs() -> [URL] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }

        let cutoff = Date().timeIntervalSince1970 - maxAge
        var live: [URL] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let stamp = Double(url.deletingPathExtension().lastPathComponent) ?? 0
            if stamp < cutoff {
                try? fm.removeItem(at: url)
            } else {
                live.append(url)
            }
        }
        return live
    }

    static var count: Int { fileURLs().count }

    /// Save a snap. Downscaled to a sane pixel size before writing — the
    /// composer flattens to 1080 wide anyway, and full 48MP camera output
    /// would burn sandbox space for nothing. Returns the created `Entry`
    /// (nil on failure) so callers can correlate a camera-roll save with this
    /// snap's stable id.
    @discardableResult
    static func add(_ image: UIImage) -> Entry? {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let sized = downscaled(image, maxDimension: 2160)
        guard let data = sized.jpegData(compressionQuality: 0.85) else { return nil }

        let name = String(format: "%.3f", Date().timeIntervalSince1970)
        let url = directory.appendingPathComponent("\(name).jpg")
        do {
            try data.write(to: url)
        } catch {
            return nil
        }

        // Enforce the cap: drop the oldest beyond maxPhotos.
        let files = fileURLs()
        if files.count > maxPhotos {
            for old in files.prefix(files.count - maxPhotos) {
                try? fm.removeItem(at: old)
            }
        }
        return Entry(url: url, image: sized)
    }

    /// A stashed snap with a stable identity, so galleries can page and
    /// DELETE individual shots (mid-run review) instead of all-or-nothing.
    struct Entry: Identifiable, Equatable {
        let url: URL
        let image: UIImage
        var id: String { url.lastPathComponent }

        static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.url == rhs.url }
    }

    /// All stashed snaps with identities, oldest first.
    static func entries() -> [Entry] {
        fileURLs().compactMap { url in
            guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else {
                return nil
            }
            return Entry(url: url, image: img)
        }
    }

    /// Drop one snap (mid-run "actually, not that one").
    static func remove(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.url)
    }

    /// Cheap small thumbnail of the NEWEST snap for the tracking screen's
    /// tray button — downsampled at decode so a 1Hz-updating screen never
    /// holds full-size bitmaps for a 40pt chip.
    static func latestThumbnail(maxPixel: CGFloat = 160) -> UIImage? {
        guard let url = fileURLs().last else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let largest = max(image.size.width, image.size.height)
        guard largest > maxDimension, largest > 0 else { return image }
        let scale = maxDimension / largest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
