import SwiftUI
import AVFoundation
import Observation
import UIKit

/// In-house camera for post + mid-run captures, replacing the stock
/// UIImagePickerController so the capture flow gets the controls users kept
/// reaching for: full flash control (off / auto / on — not just auto) and a
/// self-timer (3s / 10s) for propped-up group shots. Camera-only by design —
/// no library picking — so shared walks/runs stay captured in the moment.
/// Every capture is also saved to the user's camera roll (PhotoRollSaver),
/// same as the picker it replaces.
struct MADCameraView: View {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var camera = MADCameraController()
    /// Seconds left on a running self-timer; nil when idle.
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    /// One-shot latch, set the moment a capture is requested so a double-tap
    /// can't fire two captures; reset only if the capture fails.
    @State private var didCapture = false
    /// A capture attempt produced nothing (session interrupted, processing
    /// error) — surfaced instead of silently doing nothing.
    @State private var showCaptureFailed = false

    /// Whether the device has a camera the controller can actually drive
    /// (false on Simulator). Asks AVFoundation — the same stack that
    /// captures — and only once: camera presence can't change at runtime.
    static let isAvailable: Bool =
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
        || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MADCameraPreview(session: camera.session)
                .ignoresSafeArea()

            if camera.authorizationDenied {
                permissionDeniedView
            }

            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: 110, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 12)
                    .transition(.scale.combined(with: .opacity))
                    .id(countdown)
            }

            VStack {
                topBar
                Spacer()
                bottomBar
            }

            if showCaptureFailed {
                captureFailedToast
            }
        }
        .statusBarHidden()
        .onAppear { camera.start() }
        .onDisappear {
            countdownTask?.cancel()
            camera.stop()
        }
    }

    // MARK: - Controls

    private var topBar: some View {
        HStack {
            glassCircleButton(icon: "xmark", size: 40, iconSize: 16) {
                countdownTask?.cancel()
                dismiss()
            }

            Spacer()

            HStack(spacing: 10) {
                if camera.isFlashAvailable {
                    controlPill(
                        icon: camera.flash.icon,
                        label: camera.flash.label,
                        active: camera.flash != .off
                    ) { camera.cycleFlash() }
                }
                controlPill(
                    icon: "timer",
                    label: camera.timerSeconds == 0 ? "Off" : "\(camera.timerSeconds)s",
                    active: camera.timerSeconds > 0
                ) { camera.cycleTimer() }
            }
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.top, MADTheme.Spacing.sm)
    }

    private func glassCircleButton(
        icon: String, size: CGFloat, iconSize: CGFloat, action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func controlPill(
        icon: String, label: String, active: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(active ? .yellow : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        ZStack {
            shutterButton
            HStack {
                Spacer()
                glassCircleButton(icon: "arrow.triangle.2.circlepath.camera.fill", size: 48, iconSize: 18) {
                    camera.flip()
                }
            }
            .padding(.trailing, MADTheme.Spacing.lg)
        }
        .padding(.bottom, 36)
    }

    private var shutterButton: some View {
        Button(action: shutterTapped) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                if countdownTask != nil {
                    // A running countdown turns the shutter into a stop button.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 30, height: 30)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 64, height: 64)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(camera.authorizationDenied || didCapture)
    }

    private var captureFailedToast: some View {
        VStack {
            Text("Couldn't take the photo — try again")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.75))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                )
                .padding(.top, 64)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var permissionDeniedView: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
            Text("Camera access is off")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text("Turn on camera access in Settings to snap a photo of your walk or run.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, MADTheme.Spacing.xl)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
            }
            .madPrimaryButton()
        }
    }

    // MARK: - Capture flow

    private func shutterTapped() {
        // Tapping the shutter mid-countdown cancels the timer, Apple-style.
        if let task = countdownTask {
            task.cancel()
            countdownTask = nil
            withAnimation(.easeOut(duration: 0.15)) { countdown = nil }
            return
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard camera.timerSeconds > 0 else {
            capture()
            return
        }

        let seconds = camera.timerSeconds
        countdownTask = Task { @MainActor in
            for remaining in stride(from: seconds, through: 1, by: -1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    countdown = remaining
                }
                UIImpactFeedbackGenerator(style: remaining <= 3 ? .medium : .light).impactOccurred()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
            }
            countdown = nil
            countdownTask = nil
            capture()
        }
    }

    private func capture() {
        guard !didCapture else { return }
        // Latch immediately — the shutter disables and a second tap during
        // the capture round-trip can't start a competing capture.
        didCapture = true
        camera.capturePhoto { captured in
            guard let captured else {
                // Failed (session interrupted, processing error): re-arm the
                // shutter and say so — a silent no-op after a 10s countdown
                // reads as "the app ate my photo".
                didCapture = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showCaptureFailed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    withAnimation(.easeOut(duration: 0.25)) { showCaptureFailed = false }
                }
                return
            }
            image = captured
            // Every in-app capture also lands in the camera roll — the user's
            // own copy, independent of what happens to the post.
            PhotoRollSaver.save(captured)
            dismiss()
        }
    }
}

// MARK: - Session controller

/// Owns the AVCaptureSession. All session mutation happens on `sessionQueue`;
/// observable UI state is always written back on the main queue.
@Observable
final class MADCameraController {
    @ObservationIgnored let session = AVCaptureSession()

    var authorizationDenied = false
    /// Whether the CURRENT camera can flash — front cameras count too on
    /// modern iPhones (Retina screen-flash), per supportedFlashModes.
    var isFlashAvailable = false
    var flash: FlashSetting
    /// Self-timer length in seconds; 0 = off. Deliberately NOT persisted — a
    /// remembered timer silently delaying tomorrow's quick snap is a surprise.
    var timerSeconds = 0

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "mad.camera.session")
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    /// Session-queue-owned; also the source of truth for the active position.
    @ObservationIgnored private var videoInput: AVCaptureDeviceInput?
    @ObservationIgnored private var configured = false
    /// True between stop() and the next start() — blocks lifecycle-observer
    /// restarts from reviving a session the user already closed.
    @ObservationIgnored private var userStopped = false
    /// In-flight capture delegates keyed by settings id — AVCapturePhotoOutput
    /// does NOT retain its delegate, and a single slot would let overlapping
    /// captures free each other mid-flight. Session-queue-owned.
    @ObservationIgnored private var inFlightDelegates: [Int64: MADPhotoCaptureDelegate] = [:]
    @ObservationIgnored private var sessionObservers: [NSObjectProtocol] = []

    private static let flashKey = "mad.camera.flash"

    enum FlashSetting: String, CaseIterable {
        case off, auto, on

        var next: FlashSetting {
            switch self {
            case .off: return .auto
            case .auto: return .on
            case .on: return .off
            }
        }

        var avMode: AVCaptureDevice.FlashMode {
            switch self {
            case .off: return .off
            case .auto: return .auto
            case .on: return .on
            }
        }

        var icon: String {
            switch self {
            case .off: return "bolt.slash.fill"
            case .auto: return "bolt.badge.a.fill"
            case .on: return "bolt.fill"
            }
        }

        var label: String {
            switch self {
            case .off: return "Off"
            case .auto: return "Auto"
            case .on: return "On"
            }
        }
    }

    init() {
        flash = FlashSetting(rawValue: UserDefaults.standard.string(forKey: Self.flashKey) ?? "") ?? .auto
        observeSessionLifecycle()
    }

    deinit {
        sessionObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.startSession()
                } else {
                    DispatchQueue.main.async { self?.authorizationDenied = true }
                }
            }
        default:
            authorizationDenied = true
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.userStopped = true
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Flip between back and front. The target is computed ON the session
    /// queue from the actually-attached input, so rapid double-taps queue two
    /// real flips instead of re-deriving the same target from a stale
    /// published value.
    func flip() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let current = self.videoInput?.device.position ?? .back
            let target: AVCaptureDevice.Position = current == .back ? .front : .back
            self.session.beginConfiguration()
            self.attachInput(position: target)
            self.session.commitConfiguration()
            self.publishFlashAvailability()
        }
    }

    func cycleFlash() {
        flash = flash.next
        UserDefaults.standard.set(flash.rawValue, forKey: Self.flashKey)
    }

    func cycleTimer() {
        timerSeconds = timerSeconds == 0 ? 3 : (timerSeconds == 3 ? 10 : 0)
    }

    /// Completion runs on the main queue; nil means the capture failed.
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        let flashMode = flash.avMode
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let settings = AVCapturePhotoSettings()
            if self.photoOutput.supportedFlashModes.contains(flashMode) {
                settings.flashMode = flashMode
            }
            if let connection = self.photoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }

            // Mirror front-camera shots so the saved photo matches what the
            // preview showed — an unmirrored selfie reads as "flipped".
            let mirror = self.videoInput?.device.position == .front
            let settingsId = settings.uniqueID
            let delegate = MADPhotoCaptureDelegate { [weak self] image in
                let final: UIImage? = {
                    guard let image else { return nil }
                    return mirror ? MADCameraController.mirroredHorizontally(image) : image
                }()
                self?.sessionQueue.async { self?.inFlightDelegates[settingsId] = nil }
                DispatchQueue.main.async { completion(final) }
            }
            self.inFlightDelegates[settingsId] = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    // MARK: Session-queue internals

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.userStopped = false
            self.configureIfNeeded()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .photo
        attachInput(position: .back)
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        session.commitConfiguration()
        publishFlashAvailability()
    }

    /// Swap (or attach) the camera for `position`. Session-queue only, inside
    /// a begin/commitConfiguration pair (configureIfNeeded provides its own).
    private func attachInput(position: AVCaptureDevice.Position) {
        let previous = videoInput
        if let previous {
            session.removeInput(previous)
            videoInput = nil
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            // Couldn't attach the requested camera — put the previous one back
            // rather than going black.
            if let previous, session.canAddInput(previous) {
                session.addInput(previous)
                videoInput = previous
            }
            return
        }
        session.addInput(input)
        videoInput = input
    }

    private func publishFlashAvailability() {
        let supported = photoOutput.supportedFlashModes.contains(.on)
        DispatchQueue.main.async { self.isFlashAvailable = supported }
    }

    /// UIImagePickerController used to handle these for us: restart the
    /// session when an interruption (phone call, another app claiming the
    /// camera) ends or a runtime error stops it — otherwise the user comes
    /// back to a frozen preview with a dead shutter.
    private func observeSessionLifecycle() {
        let center = NotificationCenter.default
        let restart: () -> Void = { [weak self] in
            guard let self else { return }
            self.sessionQueue.async { [weak self] in
                guard let self, self.configured, !self.userStopped,
                      !self.session.isRunning else { return }
                self.session.startRunning()
            }
        }
        sessionObservers.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session, queue: nil
        ) { _ in restart() })
        sessionObservers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session, queue: nil
        ) { note in
            // AVCam's rule: only a media-services reset warrants a restart. A
            // failed startRunning() itself posts a runtime error, so a
            // blanket retry ping-pongs forever under persistent failure.
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            guard error?.code == .mediaServicesWereReset else { return }
            restart()
        })
    }

    private static func mirroredHorizontally(_ image: UIImage) -> UIImage {
        // Fast path: with the capture connection rotated to portrait the
        // decoded image is normally .up, and the flip is a metadata-only
        // orientation swap — no pixel copy.
        if image.imageOrientation == .up, let cg = image.cgImage {
            return UIImage(cgImage: cg, scale: image.scale, orientation: .upMirrored)
        }
        // Fallback for EXIF-rotated variants: re-render. Orientation-flag
        // arithmetic for the rotated+mirrored cases is easy to get wrong, and
        // a slow correct selfie beats a fast sideways one.
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: image.size.width, y: 0)
            ctx.cgContext.scaleBy(x: -1, y: 1)
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

/// One-shot capture delegate. The controller keeps a strong reference (in
/// `inFlightDelegates`) until the callback fires — AVCapturePhotoOutput does
/// not retain its delegate.
private final class MADPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data)
        else {
            completion(nil)
            return
        }
        completion(image)
    }
}

// MARK: - Preview layer host

private struct MADCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        // Re-runs whenever the hosting view re-renders (e.g. after the async
        // session config flips an observable flag) — by then the connection
        // exists even if the initial layout pass beat it.
        uiView.pinToPortrait()
    }

    final class PreviewHostView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            pinToPortrait()
        }

        // The app is portrait-only; pin the preview to portrait once the
        // connection exists (it forms only after inputs attach).
        func pinToPortrait() {
            if let connection = previewLayer.connection,
               connection.isVideoRotationAngleSupported(90),
               connection.videoRotationAngle != 90 {
                connection.videoRotationAngle = 90
            }
        }
    }
}
