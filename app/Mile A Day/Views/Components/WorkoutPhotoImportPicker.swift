import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

/// Outcome of importing a library photo into a walk/run.
enum WorkoutPhotoImportResult {
    case accepted(UIImage)
    /// The photo's capture time is outside the workout window.
    case outsideWindow
    /// No embedded capture date (screenshot, stripped EXIF) — can't prove it
    /// was taken on this walk, so we don't accept it.
    case noCaptureDate
    case cancelled
    case failed
}

/// Library import that stays true to the app's "captured on this walk"
/// authenticity: it uses the system photo picker (no library permission — the
/// picker runs out of process) and ACCEPTS a photo only if its embedded EXIF
/// capture time falls inside the workout's time window. So a user who shot a
/// great photo mid-run with the system camera (better controls, Live Photo)
/// can still use it, but a random selfie from last week can't slip in.
struct WorkoutPhotoImportPicker: UIViewControllerRepresentable {
    /// Accepted capture-time window (absolute time). Callers add grace.
    let window: ClosedRange<Date>
    let onResult: (WorkoutPhotoImportResult) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration() // no photoLibrary → no permission
        config.filter = .images
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: WorkoutPhotoImportPicker
        init(_ parent: WorkoutPhotoImportPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                parent.onResult(.cancelled)
                return
            }
            // Load the raw file so EXIF survives (loadObject(UIImage) strips it).
            let types = provider.registeredTypeIdentifiers
            let imageType = types.first { UTType($0)?.conforms(to: .image) == true }
                ?? UTType.image.identifier

            provider.loadDataRepresentation(forTypeIdentifier: imageType) { [weak self] data, _ in
                guard let self else { return }
                guard let data, let image = UIImage(data: data) else {
                    DispatchQueue.main.async { self.parent.onResult(.failed) }
                    return
                }
                let result: WorkoutPhotoImportResult
                if let taken = Self.captureDate(from: data) {
                    result = self.parent.window.contains(taken) ? .accepted(image) : .outsideWindow
                } else {
                    result = .noCaptureDate
                }
                DispatchQueue.main.async { self.parent.onResult(result) }
            }
        }

        /// Read the embedded capture time. EXIF `DateTimeOriginal` (the shutter
        /// moment) is tz-less wall-clock, parsed in the device's current tz —
        /// which matches the phone's clock when the shot was taken.
        static func captureDate(from data: Data) -> Date? {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
            else { return nil }

            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"

            if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let dto = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
               let d = fmt.date(from: dto) { return d }
            if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
               let dt = tiff[kCGImagePropertyTIFFDateTime] as? String,
               let d = fmt.date(from: dt) { return d }
            return nil
        }
    }
}
