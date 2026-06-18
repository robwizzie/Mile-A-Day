import SwiftUI
import VisionKit
import AVFoundation

/// Full-screen in-app QR scanner (VisionKit `DataScannerViewController`).
/// Reads a friend's profile QR (`mileaday://u/<username>`) and hands the raw
/// payload back via `onCode`; the caller resolves it and dismisses.
struct QRScannerView: View {
    /// Called once with the raw payload string of the first QR scanned.
    let onCode: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    /// nil = still asking, true/false = camera authorization result.
    @State private var cameraAuthorized: Bool?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("Scan Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                }
            }
            .task { await requestCameraAccess() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch cameraAuthorized {
        case .some(true):
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                DataScannerContainer(onCode: onCode)
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) { hintBanner }
            } else {
                message("Scanning isn't available on this device.")
            }
        case .some(false):
            message("Camera access is off.\nEnable it in Settings → Mile A Day → Camera to scan a friend's code.")
        case .none:
            ProgressView().tint(.white)
        }
    }

    private var hintBanner: some View {
        Text("Point at a friend's Mile A Day QR code")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(.black.opacity(0.55)))
            .padding(.bottom, 40)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundColor(.white.opacity(0.85))
            .multilineTextAlignment(.center)
            .padding(32)
    }

    private func requestCameraAccess() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true
        case .notDetermined:
            cameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            cameraAuthorized = false
        }
    }
}

// MARK: - VisionKit wrapper

private struct DataScannerContainer: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        try? uiViewController.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (String) -> Void
        // Fire exactly once — the delegate streams updates many times/sec.
        private var handled = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            guard !handled else { return }
            for case let .barcode(barcode) in items {
                if let payload = barcode.payloadStringValue, !payload.isEmpty {
                    handled = true
                    onCode(payload)
                    return
                }
            }
        }
    }
}
