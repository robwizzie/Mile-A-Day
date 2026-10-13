import UIKit
import Photos

/// Remembers which camera-roll photo is a FRONT & BACK pair, so the pair can
/// be posted later as a real front-and-back photo instead of one flat picture.
///
/// The camera roll gets ONE picture per front-and-back press: both frames
/// flattened the way the feed draws them (`DualPhotoComposite`). That keeps the
/// user's library honest (one press, one photo), but a flat picture can't be
/// swapped on the card, and nothing in it says it was ever two frames. This
/// store keeps the two ORIGINAL frames beside the composite's PhotoKit
/// identifier, so when that photo is picked from the library later (after
/// skipping the post-walk prompt, say), `WorkoutPhotoImportPicker` hands the
/// composer the pair rather than the flattened copy.
///
/// Before this, the composer's camera saved the two frames as two SEPARATE
/// library photos and nothing linked them, so anyone who left the composer
/// before posting came back to two loose pictures they couldn't post together.
///
/// Local and short-lived on purpose: a library photo can only be posted on
/// the day of the walk it was taken on (the import window), so frames older
/// than `retention` are pruned. Losing a record is harmless — the composite
/// still posts as one photo with both frames in it.
enum DualPairStore {
    struct Pair {
        let primary: UIImage
        let secondary: UIImage
        let primaryWasFront: Bool
    }

    private struct Record: Codable {
        let file: String
        let primaryWasFront: Bool
        let createdAt: Date
    }

    /// Long enough to cover "posted it the next morning" with room to spare;
    /// the import window never reaches further back than the walk itself.
    static let retention: TimeInterval = 72 * 60 * 60
    /// Frames are kept at this long edge — far above what a post uploads,
    /// well below a full sensor image's footprint.
    private static let maxPixel: CGFloat = 2400
    private static let indexKey = "dualPairIndexV1"
    private static let queue = DispatchQueue(label: "mad.dualpairstore")

    private static var directory: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("DualPairs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Saving

    /// Save one FRONT & BACK press to the camera roll — as ONE flattened
    /// picture — and remember its two frames under the new photo's
    /// identifier. `completion` reports (main queue) whether it landed.
    ///
    /// Main actor because the composite is drawn with `ImageRenderer`.
    @MainActor
    static func saveToCameraRoll(
        primary: UIImage,
        secondary: UIImage,
        primaryWasFront: Bool,
        ledgerKey: String? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        let composite = DualPhotoComposite.render(big: primary, small: secondary) ?? primary
        PhotoRollSaver.saveReturningIdentifier(composite) { identifier in
            guard let identifier else {
                completion?(false)
                return
            }
            if let ledgerKey { SavedPhotoLibraryLedger.shared.markSaved(ledgerKey) }
            register(
                assetId: identifier, primary: primary, secondary: secondary,
                primaryWasFront: primaryWasFront)
            completion?(true)
        }
    }

    /// Record a pair under a library photo's identifier. Encoding and disk
    /// writes run off the main thread.
    static func register(
        assetId: String, primary: UIImage, secondary: UIImage, primaryWasFront: Bool
    ) {
        queue.async {
            guard let dir = directory else { return }
            let file = UUID().uuidString
            guard let a = downscaled(primary).jpegData(compressionQuality: 0.88),
                  let b = downscaled(secondary).jpegData(compressionQuality: 0.88),
                  (try? a.write(to: dir.appendingPathComponent("\(file)-primary.jpg"))) != nil,
                  (try? b.write(to: dir.appendingPathComponent("\(file)-secondary.jpg"))) != nil
            else { return }
            var index = loadIndex()
            index[assetId] = Record(file: file, primaryWasFront: primaryWasFront, createdAt: Date())
            saveIndex(prune(index, in: dir))
        }
    }

    // MARK: - Reading

    /// Whether this library photo is a pair we can restore. Cheap — the
    /// index only — so the picker can badge its grid with it.
    static func isPair(assetId: String) -> Bool {
        queue.sync {
            guard let record = loadIndex()[assetId] else { return false }
            return Date().timeIntervalSince(record.createdAt) < retention
        }
    }

    /// The two original frames behind a library photo, or nil when it isn't
    /// one of ours (or the frames have been pruned). Reads from disk; call
    /// it off the main thread.
    static func pair(forAssetId assetId: String) -> Pair? {
        queue.sync {
            guard let dir = directory, let record = loadIndex()[assetId],
                  Date().timeIntervalSince(record.createdAt) < retention,
                  let primary = UIImage(contentsOfFile:
                    dir.appendingPathComponent("\(record.file)-primary.jpg").path),
                  let secondary = UIImage(contentsOfFile:
                    dir.appendingPathComponent("\(record.file)-secondary.jpg").path)
            else { return nil }
            return Pair(primary: primary, secondary: secondary,
                        primaryWasFront: record.primaryWasFront)
        }
    }

    // MARK: - Index

    private static func loadIndex() -> [String: Record] {
        guard let data = UserDefaults.standard.data(forKey: indexKey),
              let index = try? JSONDecoder().decode([String: Record].self, from: data)
        else { return [:] }
        return index
    }

    private static func saveIndex(_ index: [String: Record]) {
        guard let data = try? JSONEncoder().encode(index) else { return }
        UserDefaults.standard.set(data, forKey: indexKey)
    }

    /// Drop records past `retention` and delete their frames.
    private static func prune(_ index: [String: Record], in dir: URL) -> [String: Record] {
        let now = Date()
        var kept: [String: Record] = [:]
        for (key, record) in index {
            if now.timeIntervalSince(record.createdAt) < retention {
                kept[key] = record
            } else {
                for suffix in ["primary", "secondary"] {
                    try? FileManager.default.removeItem(
                        at: dir.appendingPathComponent("\(record.file)-\(suffix).jpg"))
                }
            }
        }
        return kept
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let longEdge = max(image.size.width, image.size.height) * image.scale
        guard longEdge > maxPixel else { return image }
        let factor = maxPixel / longEdge
        let size = CGSize(width: image.size.width * image.scale * factor,
                          height: image.size.height * image.scale * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
