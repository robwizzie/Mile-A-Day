import SwiftUI
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider else { return }

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    guard let image = image as? UIImage else { return }
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image
                    }
                }
            }
        }
    }
}

// MARK: - Profile Image Cropper

struct ProfileImageCropper: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let cropSize: CGFloat = 300
    private let outputSize: CGFloat = 512

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

                        // Dark overlay with circular cutout
                        CropOverlay(cropSize: cropSize)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .allowsHitTesting(false)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
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

    private func imageDisplaySize(in geometry: GeometryProxy) -> CGSize {
        let imageAspect = image.size.width / image.size.height
        let containerSize = geometry.size

        // Fill the crop area at minimum
        let fillWidth = cropSize
        let fillHeight = cropSize

        if imageAspect > 1 {
            // Landscape: height fills crop, width extends
            let height = max(fillHeight, containerSize.height)
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        } else {
            // Portrait or square: width fills crop, height extends
            let width = max(fillWidth, containerSize.width)
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        }
    }

    private func clampOffset(in geometry: GeometryProxy) {
        let imgSize = imageDisplaySize(in: geometry)
        let scaledWidth = imgSize.width * scale
        let scaledHeight = imgSize.height * scale
        let halfCrop = cropSize / 2

        let maxX = max(0, (scaledWidth - cropSize) / 2)
        let maxY = max(0, (scaledHeight - cropSize) / 2)

        withAnimation(.easeOut(duration: 0.2)) {
            offset.width = min(maxX, max(-maxX, offset.width))
            offset.height = min(maxY, max(-maxY, offset.height))
        }
        lastOffset = offset
    }

    private func cropAndReturn() {
        // Calculate the crop region in image pixel coordinates
        let imgWidth = image.size.width
        let imgHeight = image.size.height
        let imageAspect = imgWidth / imgHeight

        // Determine the display size at scale=1
        let baseDisplaySize: CGSize
        if imageAspect > 1 {
            let height = max(cropSize, UIScreen.main.bounds.height)
            baseDisplaySize = CGSize(width: height * imageAspect, height: height)
        } else {
            let width = max(cropSize, UIScreen.main.bounds.width)
            baseDisplaySize = CGSize(width: width, height: width / imageAspect)
        }

        let scaledDisplayWidth = baseDisplaySize.width * scale
        let scaledDisplayHeight = baseDisplaySize.height * scale

        // Pixels per display point
        let pxPerPtX = imgWidth / scaledDisplayWidth
        let pxPerPtY = imgHeight / scaledDisplayHeight

        // The crop circle center in display coordinates is at center - offset
        let cropCenterX = scaledDisplayWidth / 2 - offset.width
        let cropCenterY = scaledDisplayHeight / 2 - offset.height

        // Convert to pixel coordinates
        let pixelCenterX = cropCenterX * pxPerPtX
        let pixelCenterY = cropCenterY * pxPerPtY
        let pixelCropSize = cropSize * pxPerPtX

        let cropRect = CGRect(
            x: pixelCenterX - pixelCropSize / 2,
            y: pixelCenterY - pixelCropSize / 2,
            width: pixelCropSize,
            height: pixelCropSize
        ).intersection(CGRect(origin: .zero, size: image.size))

        guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
            onCrop(image)
            return
        }

        // Resize to output size
        let croppedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize))
        let resized = renderer.image { _ in
            croppedImage.draw(in: CGRect(origin: .zero, size: CGSize(width: outputSize, height: outputSize)))
        }

        onCrop(resized)
    }
}

// MARK: - Crop Overlay

private struct CropOverlay: View {
    let cropSize: CGFloat

    var body: some View {
        Canvas { context, size in
            // Fill entire area with dark overlay
            let fullRect = CGRect(origin: .zero, size: size)
            context.fill(Path(fullRect), with: .color(.black.opacity(0.6)))

            // Cut out the circle
            let circleRect = CGRect(
                x: (size.width - cropSize) / 2,
                y: (size.height - cropSize) / 2,
                width: cropSize,
                height: cropSize
            )
            context.blendMode = .destinationOut
            context.fill(Path(ellipseIn: circleRect), with: .color(.white))

            // Draw circle border
            context.blendMode = .normal
            context.stroke(Path(ellipseIn: circleRect), with: .color(.white.opacity(0.8)), lineWidth: 1.5)
        }
    }
}

#Preview {
    ImagePicker(selectedImage: .constant(nil))
}
