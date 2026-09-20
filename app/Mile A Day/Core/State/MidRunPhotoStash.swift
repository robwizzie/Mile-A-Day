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

    // MARK: FRONT & BACK

    /// A snap can be TWO frames — one shutter press, both cameras — and the
    /// pair has to survive the walk to reach the composer, or a mid-walk
    /// front-and-back would publish as an ordinary photo of whichever way the
    /// phone happened to be pointing.
    ///
    /// The second frame is a sibling file named for the CAMERA THAT TOOK IT,
    /// `<stamp>-front.jpg` or `<stamp>-back.jpg`, which is what makes the
    /// arrangement recoverable from the directory alone: the companion is by
    /// definition the other lens, so a `-back` companion means the frame the
    /// user actually framed was the selfie. A bare flag in the name would say
    /// something about the sibling rather than about the file it is on, and
    /// the two drift the first time one of them is written by mistake.
    private enum Companion: String {
        case front = "-front"
        case back = "-back"

        /// The primary is whatever the companion is NOT.
        var primaryWasFront: Bool { self == .back }
    }

    /// The timestamp a file belongs to, for BOTH shapes of name. Nil for
    /// anything that isn't ours — never treat that as an ancient timestamp,
    /// which is how a stray file becomes a deletion.
    private static func stamp(of url: URL) -> Double? {
        let stem = url.deletingPathExtension().lastPathComponent
        if let exact = Double(stem) { return exact }
        for kind in [Companion.front, Companion.back] where stem.hasSuffix(kind.rawValue) {
            return Double(String(stem.dropLast(kind.rawValue.count)))
        }
        return nil
    }

    private static func companionURL(for primary: URL, _ kind: Companion) -> URL {
        let stem = primary.deletingPathExtension().lastPathComponent
        return directory.appendingPathComponent("\(stem)\(kind.rawValue).jpg")
    }

    /// The second frame beside a primary, if this snap has one.
    private static func companion(of primary: URL) -> (url: URL, kind: Companion)? {
        for kind in [Companion.front, Companion.back] {
            let url = companionURL(for: primary, kind)
            if FileManager.default.fileExists(atPath: url.path) { return (url, kind) }
        }
        return nil
    }

    /// Remove a snap and any second frame with it. The pair is ONE photo to
    /// the user, so it is never half-deleted — an orphan companion would sit
    /// in the sandbox until the age prune and belongs to nothing.
    private static func deleteSnap(_ primary: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: primary)
        if let pair = companion(of: primary) { try? fm.removeItem(at: pair.url) }
    }

    /// PRIMARY files only, oldest first — the companions are part of their
    /// snap, not snaps of their own, so nothing that counts, shows or pages
    /// photos ever sees them. Prunes stale snaps (both frames) on the way
    /// past, plus any companion whose primary is gone.
    private static func fileURLs() -> [URL] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }

        let cutoff = Date().timeIntervalSince1970 - maxAge
        let sorted = urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        let primaries = sorted.filter { Double($0.deletingPathExtension().lastPathComponent) != nil }
        let primaryStems = Set(primaries.map { $0.deletingPathExtension().lastPathComponent })

        var live: [URL] = []
        for url in primaries {
            if (stamp(of: url) ?? 0) < cutoff {
                deleteSnap(url)
            } else {
                live.append(url)
            }
        }
        // A companion with no primary left can only be litter — a crash
        // between the two writes, or a half-finished delete.
        for url in sorted where Double(url.deletingPathExtension().lastPathComponent) == nil {
            let stem = url.deletingPathExtension().lastPathComponent
            let owner = [Companion.front, Companion.back]
                .first { stem.hasSuffix($0.rawValue) }
                .map { String(stem.dropLast($0.rawValue.count)) }
            if let owner, primaryStems.contains(owner) { continue }
            try? fm.removeItem(at: url)
        }
        return live
    }

    /// Consumer-facing count: snaps taken TODAY only (the tray badge, the
    /// "photo waiting" nudge, and the post-run prompt all read the today-scoped
    /// views), so a leftover from yesterday is never counted.
    static var count: Int { todayURLs().count }

    /// Whether the current device-local day owns the snap. Mile A Day photos are
    /// strictly today's; the 24h prune alone would let one taken yesterday
    /// evening survive into this morning.
    private static func isFromToday(_ url: URL) -> Bool {
        let taken = stamp(of: url) ?? 0
        return Calendar.current.isDateInToday(Date(timeIntervalSince1970: taken))
    }

    /// Physical snaps taken TODAY, oldest first. EVERY consumer-facing read
    /// funnels through this so a snap left over from yesterday is never shown or
    /// offered — even before the 24h prune or a workout-start cleanup runs, and
    /// regardless of which surface (tray / nudge / prompt) asks first.
    private static func todayURLs() -> [URL] {
        fileURLs().filter(isFromToday)
    }

    /// True only when a snap taken TODAY is stashed. Drives the "photo waiting"
    /// nudge so a leftover from yesterday (a finished workout whose prompt never
    /// resolved, then the app reopened next day) can't nag against a brand new,
    /// untouched day's mile.
    static func hasEntriesToday() -> Bool {
        !todayURLs().isEmpty
    }

    /// Drop snaps not taken today. Called when a fresh workout begins so a new
    /// day's effort never inherits (or re-shares) yesterday's leftover snaps,
    /// while same-day snaps from an earlier sub-goal effort are kept.
    static func dropBeforeToday() {
        for url in fileURLs() where !isFromToday(url) {
            deleteSnap(url)
        }
    }

    /// Save a snap. Downscaled to a sane pixel size before writing — the
    /// composer flattens to 1080 wide anyway, and full 48MP camera output
    /// would burn sandbox space for nothing. Returns the created `Entry`
    /// (nil on failure) so callers can correlate a camera-roll save with this
    /// snap's stable id.
    /// `secondary` is the other lens from a FRONT & BACK press. It rides with
    /// the primary as one snap: written under the same timestamp, deleted
    /// with it, counted as one photo everywhere.
    @discardableResult
    static func add(
        _ image: UIImage,
        secondary: UIImage? = nil,
        primaryWasFront: Bool = false
    ) -> Entry? {
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

        // The second frame, named for the camera that took it. Written AFTER
        // the primary so a failure here leaves an ordinary usable snap rather
        // than a companion pointing at nothing — half a pair is a photo, half
        // a photo is a bug.
        var storedSecondary: UIImage?
        if let secondary {
            let sizedSecond = downscaled(secondary, maxDimension: 2160)
            let kind: Companion = primaryWasFront ? .back : .front
            if let secondData = sizedSecond.jpegData(compressionQuality: 0.85) {
                do {
                    try secondData.write(to: companionURL(for: url, kind))
                    storedSecondary = sizedSecond
                } catch {
                    // Leaves an ordinary single snap, which is usable.
                }
            }
        }

        // Enforce the cap: drop the oldest beyond maxPhotos, pairs and all.
        let files = fileURLs()
        if files.count > maxPhotos {
            for old in files.prefix(files.count - maxPhotos) {
                deleteSnap(old)
            }
        }
        return Entry(
            url: url,
            image: sized,
            secondary: storedSecondary,
            primaryWasFront: storedSecondary == nil ? false : primaryWasFront
        )
    }

    /// A stashed snap with a stable identity, so galleries can page and
    /// DELETE individual shots (mid-run review) instead of all-or-nothing.
    struct Entry: Identifiable, Equatable {
        let url: URL
        /// The frame the user framed and triggered — what every surface that
        /// predates FRONT & BACK draws, unchanged.
        let image: UIImage
        /// The other lens, when this snap was a FRONT & BACK press.
        var secondary: UIImage? = nil
        /// True when the deliberate shot was the selfie camera. Meaningless
        /// without `secondary`, and false there by construction.
        var primaryWasFront: Bool = false
        var id: String { url.lastPathComponent }

        /// One press, two frames — the pair is ONE photo everywhere it is
        /// counted, shown or used.
        var isDual: Bool { secondary != nil }

        static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.url == rhs.url }
    }

    /// Today's stashed snaps with identities, oldest first. Scoped to today so
    /// the post-run prompt never offers a photo from a previous day's mile.
    static func entries() -> [Entry] {
        todayURLs().compactMap { url in
            guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else {
                return nil
            }
            guard let pair = companion(of: url),
                  let secondData = try? Data(contentsOf: pair.url),
                  let second = UIImage(data: secondData)
            else { return Entry(url: url, image: img) }
            return Entry(
                url: url,
                image: img,
                secondary: second,
                primaryWasFront: pair.kind.primaryWasFront
            )
        }
    }

    /// Drop one snap (mid-run "actually, not that one").
    static func remove(_ entry: Entry) {
        deleteSnap(entry.url)
    }

    /// Cheap small thumbnail of the NEWEST snap for the tracking screen's
    /// tray button — downsampled at decode so a 1Hz-updating screen never
    /// holds full-size bitmaps for a 40pt chip.
    static func latestThumbnail(maxPixel: CGFloat = 160) -> UIImage? {
        guard let url = todayURLs().last else { return nil }
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
