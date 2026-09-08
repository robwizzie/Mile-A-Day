import SwiftUI
import PhotosUI
import Photos
import UIKit

struct ImagePicker: UIViewControllerRepresentable {
    /// What happens between tapping a photo and the picker going away.
    ///
    /// The reason this lives INSIDE the picker: a confirmation presented by
    /// the caller can only appear once the picker has been dismissed, and a
    /// dismissed `PHPickerViewController` is gone for good — it runs
    /// out-of-process and there is no API to reopen one where it was. So
    /// "that's not the one" cost the user their place in their own library
    /// and dropped them back on the edit screen. Presented over the picker
    /// instead, backing out dismisses only the confirmation: the library
    /// underneath is the SAME instance, still scrolled exactly where they
    /// left it, ready for the next photo.
    enum Confirmation: Equatable {
        /// Report the pick immediately and close. The picker is a one-shot.
        case immediate
        /// Circular crop editor, for an avatar.
        case circleCrop
        /// Preview at the shape the banner is actually stored in.
        case banner
    }

    @Binding var selectedImage: UIImage?
    var confirmation: Confirmation = .immediate

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // The coordinator is built once and outlives every re-render, so it
        // must be handed the current struct or it writes through a binding
        // from the first one.
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: ImagePicker
        /// A pick is on screen being confirmed. `PHPickerViewController` stays
        /// live underneath and keeps delivering taps, so without this a tap
        /// landing behind the confirmation would stack a second one.
        private var isConfirming = false

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                // Empty results is the picker's own Cancel button. Nothing was
                // chosen, so the whole thing goes.
                dismissEverything(from: picker)
                return
            }

            guard parent.confirmation != .immediate else {
                // Unconfirmed callers keep the original one-shot behaviour.
                picker.dismiss(animated: true)
                if provider.canLoadObject(ofClass: UIImage.self) {
                    provider.loadObject(ofClass: UIImage.self) { image, _ in
                        guard let image = image as? UIImage else { return }
                        DispatchQueue.main.async {
                            self.parent.selectedImage = image
                        }
                    }
                }
                return
            }

            guard !isConfirming, provider.canLoadObject(ofClass: UIImage.self) else { return }
            isConfirming = true
            // Deliberately NOT dismissed — see `Confirmation`.
            provider.loadObject(ofClass: UIImage.self) { [weak picker] image, _ in
                DispatchQueue.main.async {
                    guard let picker, let image = image as? UIImage else {
                        self.isConfirming = false
                        return
                    }
                    self.presentConfirmation(over: picker, image: image)
                }
            }
        }

        /// Puts the confirmation on top of the live picker.
        private func presentConfirmation(over picker: PHPickerViewController, image: UIImage) {
            let use: (UIImage) -> Void = { [weak picker] chosen in
                self.isConfirming = false
                self.parent.selectedImage = chosen
                guard let picker else { return }
                // Dismissing the picker carries the confirmation sitting on it
                // away too, so the stack closes in one animation.
                self.dismissEverything(from: picker)
            }
            let cancel: () -> Void = { [weak picker] in
                self.isConfirming = false
                // ONLY the confirmation. Everything below it is untouched.
                picker?.presentedViewController?.dismiss(animated: true)
            }

            let host: UIViewController
            switch parent.confirmation {
            case .immediate:
                return
            case .circleCrop:
                host = UIHostingController(
                    rootView: ProfileImageCropper(image: image, onCrop: use, onCancel: cancel)
                )
            case .banner:
                // The same editor as the avatar, in the banner's shape. It
                // used to be a PREVIEW — the server's 1500x500 cover picked
                // the crop and the user only got to accept or reject it, which
                // is no help when the part they want is not the middle.
                host = UIHostingController(
                    rootView: ProfileImageCropper(
                        image: image,
                        aspect: 3,
                        isCircular: false,
                        // Exactly what the server stores, so its COVER is a
                        // no-op and this framing is the one that survives.
                        outputSize: CGSize(width: 1500, height: 500),
                        // A 3:1 strip capped at 300pt would be 100pt tall.
                        maxCropWidth: nil,
                        hint: "Drag and pinch to choose the strip that shows.",
                        onCrop: use,
                        onCancel: cancel
                    )
                )
            }
            host.modalPresentationStyle = .fullScreen
            picker.present(host, animated: true)
        }

        /// Closes the picker and anything presented over it.
        ///
        /// `picker.dismiss` would dismiss the CONFIRMATION when one is up
        /// (a view controller's `dismiss` acts on what it presented), which is
        /// the opposite of what this means. Going through the presenter is
        /// unambiguous in both states.
        private func dismissEverything(from picker: PHPickerViewController) {
            // Falling back to the picker itself matters: a sheet that fails to
            // close is the worst outcome this file can produce.
            if let presenter = picker.presentingViewController {
                presenter.dismiss(animated: true)
            } else {
                picker.dismiss(animated: true)
            }
        }
    }
}

// MARK: - Camera-roll auto-save

/// Saves in-app camera captures to the user's photo library (add-only
/// access), so the app is never the only holder of a photo — posts and
/// stories can be deleted, but the user always keeps their own copy in the
/// camera roll. Best-effort: a denied permission or save failure never
/// interrupts the capture flow.
enum PhotoRollSaver {
    /// Saves `image` to the photo library (add-only). `completion` reports —
    /// on the main queue — whether the asset actually landed in the library, so
    /// callers can reflect a real "Saved" state (a denied permission or write
    /// failure reports `false`, never `true`).
    static func save(_ image: UIImage, completion: ((Bool) -> Void)? = nil) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { ok, error in
                if let error {
                    print("[PhotoRollSaver] Save failed: \(error.localizedDescription)")
                }
                DispatchQueue.main.async { completion?(ok && error == nil) }
            }
        }
    }

    /// As `save`, but records `ledgerKey` in `SavedPhotoLibraryLedger` on a
    /// confirmed save so a review gallery can show "Saved" and refuse a
    /// duplicate. `ledgerKey` is a `MidRunPhotoStash.Entry.id`.
    static func save(_ image: UIImage, ledgerKey: String, completion: ((Bool) -> Void)? = nil) {
        save(image) { ok in
            if ok { SavedPhotoLibraryLedger.shared.markSaved(ledgerKey) }
            completion?(ok)
        }
    }
}

// MARK: - Camera Capture

// In-app camera capture lives in MADCameraView (Views/Components/MADCameraView.swift) —
// an AVFoundation camera with full flash control and a self-timer, which
// replaced the UIImagePickerController-based CameraPicker that used to be here.

// MARK: - Profile Image Cropper

/// Move-and-scale, for any crop shape.
///
/// Generalised from the avatar's square/circle rather than copied for the
/// banner: the pixel maths here (cover-fit at scale 1, clamp, display→pixel
/// conversion) is the part that is easy to get subtly wrong, and two copies of
/// it would drift the moment either shape changed.
///
/// NOTE for callers: the memberwise init is declaration-ordered, so the shape
/// parameters sit between `image` and the two closures — every existing call
/// site names its arguments in that order and keeps working.
struct ProfileImageCropper: View {
    let image: UIImage
    /// Crop window aspect, width / height. 1 = the avatar, 3 = the banner.
    var aspect: CGFloat = 1
    /// A circular mask for a face, a rounded rectangle for a strip.
    var isCircular: Bool = true
    /// What the caller gets back. The banner's is the 1500x500 the server
    /// stores, so its own COVER becomes a no-op and the framing survives
    /// exactly as it was set here.
    var outputSize: CGSize = CGSize(width: 512, height: 512)
    /// Cap on the crop window's width; nil fills whatever it is given. The
    /// avatar's has always been 300pt, but a 3:1 strip at 300pt is 100pt tall
    /// and you cannot frame a photograph in it.
    var maxCropWidth: CGFloat? = 300
    /// One line under the window, when the shape needs explaining.
    var hint: String? = nil
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    /// The crop window as actually laid out. `cropAndReturn` runs from a
    /// toolbar button, outside the GeometryReader, and the whole display→pixel
    /// conversion is expressed in this window's points.
    @State private var measuredWindow: CGSize = .zero

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                GeometryReader { geometry in
                    ZStack {
                        // Draggable/zoomable image
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(
                                width: imageDisplaySize(in: geometry).width * scale,
                                height: imageDisplaySize(in: geometry).height * scale
                            )
                            .offset(offset)
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let newScale = lastScale * value
                                            scale = max(1.0, min(newScale, 5.0))
                                        }
                                        .onEnded { _ in
                                            lastScale = scale
                                            clampOffset(in: geometry)
                                        },
                                    DragGesture()
                                        .onChanged { value in
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                        .onEnded { _ in
                                            clampOffset(in: geometry)
                                            lastOffset = offset
                                        }
                                )
                            )

                        // Dark overlay with the crop window cut out of it
                        CropOverlay(
                            cropSize: cropWindow(in: geometry),
                            isCircular: isCircular
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(false)

                        if let hint {
                            VStack {
                                Spacer()
                                Text(hint)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, MADTheme.Spacing.xl)
                                    .padding(.bottom, MADTheme.Spacing.xl)
                            }
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .allowsHitTesting(false)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .onAppear { measuredWindow = cropWindow(in: geometry) }
                    .onChange(of: geometry.size) { _, _ in
                        measuredWindow = cropWindow(in: geometry)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .principal) {
                    Text("Move and Scale")
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Choose") { cropAndReturn() }
                        .fontWeight(.semibold)
                        .foregroundColor(MADTheme.Colors.madRed)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    /// The window the photo is framed in, in points.
    private func cropWindow(in geometry: GeometryProxy) -> CGSize {
        let availableWidth = max(80, geometry.size.width - 32)
        let availableHeight = max(80, geometry.size.height - 32)
        // Fit the aspect inside what there is, then apply the caller's cap.
        var width = min(availableWidth, availableHeight * aspect)
        if let maxCropWidth { width = min(width, maxCropWidth) }
        return CGSize(width: width, height: width / aspect)
    }

    /// The photo at scale 1: the smallest size that COVERS the window, so
    /// there is never a gap at the edge and zooming only ever goes inward.
    private func imageDisplaySize(in geometry: GeometryProxy) -> CGSize {
        let window = cropWindow(in: geometry)
        guard image.size.width > 0, image.size.height > 0 else { return window }
        let cover = max(window.width / image.size.width, window.height / image.size.height)
        return CGSize(width: image.size.width * cover, height: image.size.height * cover)
    }

    private func clampOffset(in geometry: GeometryProxy) {
        let window = cropWindow(in: geometry)
        let imgSize = imageDisplaySize(in: geometry)
        let maxX = max(0, (imgSize.width * scale - window.width) / 2)
        let maxY = max(0, (imgSize.height * scale - window.height) / 2)

        withAnimation(.easeOut(duration: 0.2)) {
            offset.width = min(maxX, max(-maxX, offset.width))
            offset.height = min(maxY, max(-maxY, offset.height))
        }
        lastOffset = offset
    }

    private func cropAndReturn() {
        let window = measuredWindow
        // The source is normalised FIRST: `cgImage.cropping` works in raw
        // pixels and ignores `imageOrientation`, so a photo shot in portrait
        // (orientation `.right`, as the camera hands them over) would have had
        // its crop rectangle applied to a sideways bitmap — the framing the
        // user set and the region taken would be ninety degrees apart.
        let source = normalizedImage()
        guard window.width > 0, window.height > 0,
              source.size.width > 0, source.size.height > 0,
              let cgImage = source.cgImage
        else {
            onCrop(image)
            return
        }

        // Display size at scale 1 is the cover fit; multiply by the live zoom.
        let cover = max(window.width / source.size.width,
                        window.height / source.size.height)
        let displayWidth = source.size.width * cover * scale
        let displayHeight = source.size.height * cover * scale
        guard displayWidth > 0, displayHeight > 0 else {
            onCrop(image)
            return
        }

        // Source pixels per display point — uniform, because a cover fit
        // preserves the aspect.
        let pxPerPt = source.size.width / displayWidth

        // Where the window's centre falls on the image, in display points.
        let centerX = displayWidth / 2 - offset.width
        let centerY = displayHeight / 2 - offset.height

        let cropWidth = window.width * pxPerPt
        let cropHeight = window.height * pxPerPt
        let cropRect = CGRect(
            x: centerX * pxPerPt - cropWidth / 2,
            y: centerY * pxPerPt - cropHeight / 2,
            width: cropWidth,
            height: cropHeight
        ).intersection(CGRect(origin: .zero, size: source.size))

        guard !cropRect.isNull, cropRect.width >= 1, cropRect.height >= 1,
              let cropped = cgImage.cropping(to: cropRect)
        else {
            onCrop(source)
            return
        }

        // Normalised, so scale 1 / `.up` are the right thing to rebuild with.
        let croppedImage = UIImage(cgImage: cropped)
        let renderer = UIGraphicsImageRenderer(size: outputSize)
        onCrop(renderer.image { _ in
            croppedImage.draw(in: CGRect(origin: .zero, size: outputSize))
        })
    }

    /// A `.up`, scale-1 copy, so the image's points and its `cgImage`'s pixels
    /// are the same numbers and the crop rectangle means what it says.
    private func normalizedImage() -> UIImage {
        guard image.imageOrientation != .up || image.scale != 1 else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

private struct CropOverlay: View {
    let cropSize: CGSize
    var isCircular: Bool = true

    var body: some View {
        Canvas { context, size in
            // Fill entire area with dark overlay
            let fullRect = CGRect(origin: .zero, size: size)
            context.fill(Path(fullRect), with: .color(.black.opacity(0.6)))

            let windowRect = CGRect(
                x: (size.width - cropSize.width) / 2,
                y: (size.height - cropSize.height) / 2,
                width: cropSize.width,
                height: cropSize.height
            )
            // A circle for a face; the banner's own corner radius for a strip,
            // so the window is the shape the profile actually draws.
            let window: Path = isCircular
                ? Path(ellipseIn: windowRect)
                : Path(roundedRect: windowRect,
                       cornerRadius: MADTheme.CornerRadius.medium,
                       style: .continuous)

            // Cut it out
            context.blendMode = .destinationOut
            context.fill(window, with: .color(.white))

            // Draw its border
            context.blendMode = .normal
            context.stroke(window, with: .color(.white.opacity(0.8)), lineWidth: 1.5)
        }
    }
}

#Preview {
    ImagePicker(selectedImage: .constant(nil))
}
