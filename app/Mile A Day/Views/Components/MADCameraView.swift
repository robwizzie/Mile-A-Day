import SwiftUI
import AVFoundation
import Observation
import UIKit

/// In-house camera for post + mid-run captures, replacing the stock
/// UIImagePickerController so the capture flow gets the controls users kept
/// reaching for: full flash control (off / auto / on — not just auto) and a
/// self-timer (3s / 10s) for propped-up group shots. Camera-only by design —
/// no library picking — so shared walks/runs stay captured in the moment.
/// By default every capture is also saved to the user's camera roll
/// (PhotoRollSaver), same as the picker it replaces. Callers that need to
/// control the camera-roll save themselves (e.g. to key it to a stash id for
/// duplicate-prevention) pass `autoSaveToPhotos: false` and save the returned
/// image on their own.
struct MADCameraView: View {
    @Binding var image: UIImage?
    /// When true (default), the raw shot is saved straight to the camera roll
    /// at capture. Mid-run capture turns this off so it can save keyed by the
    /// snap's stash id instead (see SavedPhotoLibraryLedger).
    var autoSaveToPhotos: Bool = true
    /// Offer FRONT & BACK — one shutter press, both cameras. Opt-in per
    /// caller and OFF by default, because it changes what the shutter does
    /// and no caller should get that by accident. The post composer and the
    /// mid-walk camera both turn it on; within the camera it is still a
    /// CHOICE, and the rail opens on PHOTO, so one tap mid-stride behaves
    /// exactly as it always has for anyone who doesn't ask for the second
    /// frame.
    var allowsDual: Bool = false
    /// Delivered instead of `image` when a FRONT & BACK capture completes.
    /// Required for `allowsDual` to do anything.
    var onDualCapture: ((DualCapture) -> Void)? = nil
    /// The post prompt's camera: today's photo prompt, tucked into a small
    /// "Today's prompt" button that opens a card (never on the picture), and
    /// the walk's route thumbnail top-right with a caption for that card.
    /// All nil everywhere else.
    var themeLabel: String? = nil
    var companion: AnyView? = nil
    var companionCaption: String? = nil
    /// Bottom-left: the walk's own photos (latest snap as the thumbnail,
    /// how many there are). The camera closes and the caller opens them.
    var walkPhotos: CameraWalkPhotos? = nil
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
    /// Staggered entrance for the chrome so opening feels composed, not popped.
    @State private var controlsAppeared = false
    /// Quick white blink at shutter time — the classic capture acknowledgment.
    @State private var captureFlash = false
    /// Accumulated flip-icon rotation (each flip adds a half turn).
    @State private var flipRotation: Double = 0
    /// Display zoom captured at the start of a pinch, so the gesture scales from
    /// where the user was (not always from 1×). nil when no pinch is active.
    @State private var pinchBaseline: CGFloat?
    /// The tucked-away prompt card is open.
    @State private var showPromptCard = false

    // MARK: FRONT & BACK

    /// The user's choice of capture mode for this session. Deliberately NOT
    /// persisted: the next photo is usually an ordinary one, and silently
    /// firing a selfie because of a choice made yesterday is a surprise.
    @State private var dualMode = false
    /// The deliberate shot, held while the second camera warms up. Non-nil
    /// means we are between the two frames.
    @State private var firstFrame: UIImage?
    /// Which camera took `firstFrame`, so the delivered capture can say.
    @State private var firstWasFront = false
    /// Countdown to the automatic second shot; nil when not waiting.
    @State private var secondCountdown: Int?
    @State private var secondShotTask: Task<Void, Never>?
    private var isDualActive: Bool { allowsDual && onDualCapture != nil }

    /// Whether the device has a camera the controller can actually drive
    /// (false on Simulator). Asks AVFoundation — the same stack that
    /// captures — and only once: camera presence can't change at runtime.
    static let isAvailable: Bool =
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
        || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Preview fades in once frames are actually flowing — no black
            // pop, and a soft spinner while the session spins up.
            MADCameraPreview(session: camera.session)
                .ignoresSafeArea()
                .opacity(camera.isSessionRunning ? 1 : 0)
                .animation(.easeIn(duration: 0.35), value: camera.isSessionRunning)
                // Pinch anywhere on the preview to zoom (two fingers — never
                // conflicts with the one-finger chrome taps layered above).
                .gesture(zoomGesture)

            if !camera.isSessionRunning && !camera.authorizationDenied {
                ProgressView()
                    .tint(.white.opacity(0.6))
                    .scaleEffect(1.2)
            }

            // Legibility scrims behind the chrome — controls read cleanly on
            // any scene without boxing the whole preview.
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.45), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.5)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 190)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Countdown: dim the scene and pop the seconds, Apple-style.
            Color.black.opacity(countdown != nil ? 0.28 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.25), value: countdown != nil)

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

            // The first frame, parked in the corner it is heading for, plus
            // the prompt for the second.
            //
            // UNDER the chrome stack on purpose: the whole overlay is the
            // shutter (tap anywhere to shoot now), and layering it over the
            // top bar would take the X with it — leaving a 2-second state
            // with no way out. The controls it must not compete with are
            // hidden below instead, so what is left above it is exactly the
            // cancel button.
            if let firstFrame, let secondCountdown {
                secondShotOverlay(first: firstFrame, remaining: secondCountdown)
            }

            VStack {
                topBar
                    .opacity(controlsAppeared ? 1 : 0)
                    .offset(y: controlsAppeared ? 0 : -14)
                // Flash, timer and FRONT & BACK: one labelled rail down the
                // right edge, so every setting says what it is and what it's
                // set to. Gone while a second frame is pending.
                if firstFrame == nil {
                    HStack {
                        Spacer(minLength: 0)
                        sideRail
                    }
                    .padding(.trailing, 10)
                    .padding(.top, 10)
                    .opacity(controlsAppeared ? 1 : 0)
                }
                Spacer()
                // While the second frame is pending, every control except
                // cancel goes away: there is exactly one thing to do, and each
                // of the others is a way to lose the shot already taken.
                if firstFrame == nil {
                    if isDualActive, dualMode {
                        // FRONT & BACK changes what the shutter DOES, so the
                        // mode says so right above it.
                        Text("Front & back: one tap shoots both ways")
                            .madFont(size: 12, weight: .bold, design: .rounded, maxScale: 1.15)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                            .padding(.bottom, 10)
                            .transition(.opacity)
                    }
                    if camera.zoomOptions.count > 1 {
                        zoomSelector
                            .padding(.bottom, 14)
                            .opacity(controlsAppeared ? 1 : 0)
                    }
                    bottomBar
                        .opacity(controlsAppeared ? 1 : 0)
                        .offset(y: controlsAppeared ? 0 : 16)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: dualMode)

            if showPromptCard, let themeLabel {
                promptCard(themeLabel)
            }

            // Shutter acknowledgment blink.
            Color.white.opacity(captureFlash ? 0.85 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if showCaptureFailed {
                captureFailedToast
            }
        }
        // Camera chrome is a dark surface regardless of system setting —
        // keeps the material pills consistent over the live preview.
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .onAppear {
            camera.start()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.08)) {
                controlsAppeared = true
            }
        }
        .onDisappear {
            countdownTask?.cancel()
            secondShotTask?.cancel()
            camera.stop()
        }
    }

    // MARK: - Controls

    private var topBar: some View {
        HStack(spacing: 8) {
            glassCircleButton(icon: "xmark", size: 40, iconSize: 16) {
                countdownTask?.cancel()
                secondShotTask?.cancel()
                dismiss()
            }
            .accessibilityLabel("Close camera")

            Spacer(minLength: 0)

            // Found, not shouted: one small button; the prompt itself is on
            // the card it opens.
            if themeLabel != nil, firstFrame == nil {
                Button {
                    MADHaptics.tap()
                    withAnimation(.easeOut(duration: 0.2)) { showPromptCard = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(red: 1, green: 0.7, blue: 0.3))
                            .accessibilityHidden(true)
                        Text("Today's prompt")
                            .madFont(size: 13, weight: .heavy, design: .rounded, maxScale: 1.15)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(CameraControlButtonStyle())
            }

            Spacer(minLength: 0)

            if let companion, firstFrame == nil {
                Button {
                    MADHaptics.tap()
                    withAnimation(.easeOut(duration: 0.2)) { showPromptCard = true }
                } label: {
                    companion
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
                        )
                }
                .buttonStyle(CameraControlButtonStyle())
                .accessibilityLabel("Your route goes on the post")
                .disabled(themeLabel == nil)
            } else {
                // Keeps the prompt button centred.
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.top, MADTheme.Spacing.sm)
    }

    /// Flash, timer and FRONT & BACK, each a round button with what it is
    /// and how it's set written under it ("Flash auto", "Timer off").
    private var sideRail: some View {
        VStack(spacing: 12) {
            if camera.isFlashAvailable {
                railButton(
                    icon: camera.flash.icon,
                    label: "Flash \(camera.flash.label.lowercased())",
                    active: camera.flash != .off
                ) { camera.cycleFlash() }
            }
            railButton(
                icon: "timer",
                label: camera.timerSeconds == 0 ? "Timer off" : "Timer \(camera.timerSeconds)s",
                active: camera.timerSeconds > 0
            ) { camera.cycleTimer() }
            if isDualActive {
                railButton(
                    icon: "person.2.fill",
                    label: "Front & back",
                    active: dualMode
                ) { dualMode.toggle() }
                .accessibilityValue(dualMode ? "On" : "Off")
            }
        }
    }

    private func railButton(
        icon: String, label: String, active: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            MADHaptics.tap()
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(active ? .yellow : .white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(
                        active ? Color.yellow.opacity(0.7) : Color.white.opacity(0.18), lineWidth: 1))
                    .contentTransition(.symbolEffect(.replace))
                Text(label)
                    .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.15)
                    .foregroundColor(active ? .yellow : .white)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(width: 62)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CameraControlButtonStyle())
        .accessibilityLabel(label)
        .animation(.easeInOut(duration: 0.15), value: active)
    }

    /// The prompt, opened: an idea (never a rule) and what rides along on
    /// the post. Dims the preview; any tap outside, or "Got it", closes it.
    private func promptCard(_ theme: String) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showPromptCard = false } }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's prompt")
                        .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.6))
                    Text(theme)
                        .madFont(size: 22, weight: .black, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white)
                        .madBodyLines(2)
                    Text("Just an idea. Post anything you like.")
                        .madFont(size: 14, weight: .semibold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.7))
                        .madBodyLines(2)
                }
                if let companion {
                    Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                    HStack(spacing: 12) {
                        companion
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your route goes on the post")
                                .madFont(size: 15, weight: .heavy, design: .rounded, maxScale: 1.3)
                                .foregroundColor(.white)
                                .madBodyLines(2)
                            if let companionCaption {
                                Text(companionCaption)
                                    .madFont(size: 13, weight: .semibold, design: .rounded, maxScale: 1.3)
                                    .foregroundColor(.white.opacity(0.65))
                                    .madBodyLines(2)
                            }
                        }
                    }
                }
                Button {
                    MADHaptics.tap()
                    withAnimation(.easeOut(duration: 0.2)) { showPromptCard = false }
                } label: {
                    Text("Got it")
                        .madFont(size: 15, weight: .heavy, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.055, blue: 0.065).opacity(0.94))
            )
            .padding(.horizontal, 16)
            .padding(.top, 64)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }

    private func glassCircleButton(
        icon: String, size: CGFloat, iconSize: CGFloat,
        rotation: Double = 0, action: @escaping () -> Void
    ) -> some View {
        Button {
            MADHaptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundColor(.white)
                .rotationEffect(.degrees(rotation))
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(CameraControlButtonStyle())
    }

    /// Walk photos bottom-left, the shutter, a labelled Flip bottom-right.
    private var bottomBar: some View {
        HStack(alignment: .center) {
            Group {
                if let walkPhotos {
                    walkPhotosButton(walkPhotos)
                } else {
                    Color.clear
                }
            }
            .frame(width: 70)

            Spacer(minLength: 0)
            shutterButton
            Spacer(minLength: 0)

            Button {
                MADHaptics.tap()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    flipRotation += 180
                }
                camera.flip()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(flipRotation))
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    bottomLabel("Flip")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(CameraControlButtonStyle())
            .accessibilityLabel("Flip camera")
            .frame(width: 70)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.bottom, 30)
    }

    private func bottomLabel(_ text: String) -> some View {
        Text(text)
            .madFont(size: 11, weight: .heavy, design: .rounded, maxScale: 1.15)
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.6), radius: 3)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// The walk's own photos, one tap away: the latest snap stacked on a
    /// second card with a count, or a plain photos glyph when there are none
    /// yet (the window-filtered library still has the walk's photos).
    private func walkPhotosButton(_ photos: CameraWalkPhotos) -> some View {
        Button {
            MADHaptics.tap()
            photos.open()
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        if photos.thumbnail != nil {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.35))
                                .frame(width: 42, height: 42)
                                .offset(x: 5, y: -5)
                        }
                        Group {
                            if let thumb = photos.thumbnail {
                                Image(uiImage: thumb).resizable().scaledToFill()
                            } else {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.ultraThinMaterial)
                            }
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white, lineWidth: 2)
                        )
                    }
                    .frame(width: 52, height: 52)
                    if photos.count > 0 {
                        Text("\(photos.count)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Capsule().fill(MADTheme.Colors.madRed))
                            .offset(x: 6, y: -6)
                    }
                }
                bottomLabel("Walk photos")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CameraControlButtonStyle())
        .accessibilityLabel(photos.count > 0
            ? "Photos from this walk, \(photos.count)"
            : "Photos from this walk")
    }

    /// Between the two frames: the shot already in hand, parked in the corner
    /// it will end up in, with the countdown to the other camera.
    ///
    /// Showing the first frame ALREADY inset is what makes the mode explain
    /// itself — the composition is visibly assembling, so nobody has to be
    /// told in words what "front and back" is about to produce. It can only
    /// approximate the finished placement (the preview is full-bleed, the
    /// photo is 4:5), which is fine: the job here is "your shot is safe, in
    /// that corner", not a pixel preview.
    private func secondShotOverlay(first: UIImage, remaining: Int) -> some View {
        let thumbWidth: CGFloat = 96
        return ZStack {
            // A wash, so the chrome reads over any scene and the moment feels
            // like a held beat rather than the camera just sitting there.
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 6) {
                Text(firstWasFront ? "Now what you're looking at" : "Now you")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                Text("Tap anywhere to shoot now")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.78))
                Text("\(remaining)")
                    .font(.system(size: 66, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .padding(.top, 4)
            }
            .shadow(color: .black.opacity(0.65), radius: 12)
            .padding(.horizontal, MADTheme.Spacing.lg)
        }
        .overlay(alignment: .topTrailing) {
            Image(uiImage: first)
                .resizable()
                .scaledToFill()
                .frame(width: thumbWidth, height: thumbWidth / DualPhotoLayout.aspect)
                .clipShape(RoundedRectangle(
                    cornerRadius: DualPhotoLayout.cornerRadius(forInsetWidth: thumbWidth),
                    style: .continuous))
                .overlay(
                    RoundedRectangle(
                        cornerRadius: DualPhotoLayout.cornerRadius(forInsetWidth: thumbWidth),
                        style: .continuous)
                        .strokeBorder(Color.white.opacity(0.92),
                                      lineWidth: DualPhotoLayout.borderWidth(forInsetWidth: thumbWidth))
                )
                .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
                .padding(.trailing, MADTheme.Spacing.md)
                .padding(.top, 64)
                .transition(.scale(scale: 2.4).combined(with: .opacity))
        }
        // The whole screen is the shutter here. There is one thing to do, and
        // hunting for a button while the countdown runs is how the second
        // frame gets missed.
        .contentShape(Rectangle())
        .onTapGesture { fireSecondFrameNow() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Second photo in \(remaining) seconds. Activate to shoot now.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { fireSecondFrameNow() }
    }

    // MARK: - Zoom

    /// Native-style lens/zoom selector. Each stop is a pill; the one nearest the
    /// current zoom is highlighted and shows the live factor (e.g. "1.7×").
    private var zoomSelector: some View {
        HStack(spacing: 6) {
            ForEach(camera.zoomOptions, id: \.self) { factor in
                let selected = isSelectedZoom(factor)
                Button {
                    MADHaptics.tap()
                    pinchBaseline = nil
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        camera.setDisplayZoom(factor)
                    }
                } label: {
                    Text(selected ? "\(fmtZoom(camera.displayZoom))×" : fmtZoom(factor))
                        .font(.system(size: selected ? 15 : 13, weight: .bold, design: .rounded))
                        .foregroundColor(selected ? .yellow : .white)
                        .frame(minWidth: selected ? 46 : 34, minHeight: 34)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(CameraControlButtonStyle())
            }
        }
        .animation(.easeInOut(duration: 0.15), value: camera.displayZoom)
    }

    /// Two-finger pinch → continuous zoom, scaled from wherever the user was.
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBaseline ?? camera.displayZoom
                if pinchBaseline == nil { pinchBaseline = base }
                camera.setDisplayZoom(base * value.magnification)
            }
            .onEnded { _ in pinchBaseline = nil }
    }

    /// True for the stop nearest the current zoom, so exactly one pill lights up.
    private func isSelectedZoom(_ factor: CGFloat) -> Bool {
        guard let nearest = camera.zoomOptions.min(by: {
            abs($0 - camera.displayZoom) < abs($1 - camera.displayZoom)
        }) else { return false }
        return nearest == factor
    }

    /// "0.5" / "1" / "1.7" — one decimal only when it isn't a whole number.
    private func fmtZoom(_ z: CGFloat) -> String {
        let r = (z * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", Double(r))
    }

    private var shutterButton: some View {
        Button(action: shutterTapped) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                if countdownTask != nil {
                    // A running countdown turns the shutter into a stop button.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 30, height: 30)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 64, height: 64)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: countdownTask != nil)
        }
        .buttonStyle(ShutterButtonStyle())
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

        MADHaptics.action()
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
                remaining <= 3 ? MADHaptics.action() : MADHaptics.tap()
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
        shutterBlink()
        camera.capturePhoto { captured in
            guard let captured else {
                reportCaptureFailure()
                return
            }
            // Every in-app capture also lands in the camera roll — the user's
            // own copy, independent of what happens to the post. The mid-run
            // path opts out (autoSaveToPhotos == false) so it can save keyed to
            // the snap's stash id and avoid a duplicate on re-save.
            guard isDualActive, dualMode else {
                if autoSaveToPhotos { PhotoRollSaver.save(captured) }
                image = captured
                dismiss()
                return
            }
            // A FRONT & BACK press saves nothing yet: the roll gets ONE
            // picture once both frames are in (see `captureSecondFrame`).
            beginSecondFrame(after: captured)
        }
    }

    private func shutterBlink() {
        withAnimation(.easeIn(duration: 0.06)) { captureFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.2)) { captureFlash = false }
        }
    }

    /// Re-arm the shutter and say so — a silent no-op after a 10s countdown
    /// reads as "the app ate my photo".
    private func reportCaptureFailure() {
        didCapture = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showCaptureFailed = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.25)) { showCaptureFailed = false }
        }
    }

    /// Hold the deliberate shot, flip to the other camera, and count down to
    /// the second frame.
    ///
    /// Sequential rather than simultaneous (`AVCaptureMultiCamSession`): one
    /// session, one output, the flip path this controller already has, and it
    /// works on every device the app runs on rather than the subset multi-cam
    /// supports. The cost is the ~2s gap while the other lens warms up, and
    /// the countdown turns that from dead time into the beat that makes the
    /// second shot EXPECTED — which is the difference between a fun surprise
    /// and a photo of someone frowning at their phone.
    private func beginSecondFrame(after first: UIImage) {
        firstFrame = first
        firstWasFront = camera.isUsingFrontCamera
        camera.flip()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            flipRotation += 180
            secondCountdown = 3
        }
        secondShotTask = Task { @MainActor in
            // 3 → 2 → 1 → shoot. Never renders a 0: the shutter IS the zero,
            // and a beat spent showing it is a beat of people relaxing out of
            // the pose.
            for remaining in [2, 1] {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                MADHaptics.tap()
                withAnimation(.easeOut(duration: 0.2)) { secondCountdown = remaining }
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            captureSecondFrame()
        }
    }

    /// Tapping anywhere during the countdown takes the shot immediately.
    private func fireSecondFrameNow() {
        guard secondCountdown != nil, firstFrame != nil else { return }
        secondShotTask?.cancel()
        secondShotTask = nil
        MADHaptics.action()
        captureSecondFrame()
    }

    private func captureSecondFrame() {
        guard let first = firstFrame else { return }
        secondShotTask?.cancel()
        secondShotTask = nil
        secondCountdown = nil
        shutterBlink()
        camera.capturePhoto { second in
            guard let second else {
                // The second frame is the one that can be lost; the first is
                // already in hand. Hand that one back as an ordinary photo
                // rather than discarding a picture the user took — and say
                // what happened, because a FRONT & BACK that quietly becomes
                // a single is otherwise just a mystery.
                firstFrame = nil
                if autoSaveToPhotos { PhotoRollSaver.save(first) }
                image = first
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showCaptureFailed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { dismiss() }
                return
            }
            // ONE picture for one press, both frames in it, and the pair
            // remembered under that photo — so picking it from the library
            // later restores a real front-and-back post. Two separate saves
            // here left people with two loose photos and no way to post
            // them together once they'd left the composer.
            if autoSaveToPhotos {
                DualPairStore.saveToCameraRoll(
                    primary: first, secondary: second, primaryWasFront: firstWasFront)
            }
            firstFrame = nil
            onDualCapture?(
                DualCapture(primary: first, secondary: second, primaryWasFront: firstWasFront)
            )
            dismiss()
        }
    }
}

// MARK: - Button styles

/// Shutter press: a satisfying squeeze instead of the default opacity dip.
private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Small chrome buttons: subtle press scale, no opacity flash over the preview.
private struct CameraControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Session controller

/// Owns the AVCaptureSession. All session mutation happens on `sessionQueue`;
/// observable UI state is always written back on the main queue.
@Observable
final class MADCameraController {
    @ObservationIgnored let session = AVCaptureSession()

    var authorizationDenied = false
    /// Frames are flowing — the view fades the preview in on this so opening
    /// never black-pops.
    var isSessionRunning = false
    /// Whether the CURRENT camera can flash — front cameras count too on
    /// modern iPhones (Retina screen-flash), per supportedFlashModes.
    var isFlashAvailable = false
    var flash: FlashSetting
    /// Self-timer length in seconds; 0 = off. Deliberately NOT persisted — a
    /// remembered timer silently delaying tomorrow's quick snap is a surprise.
    var timerSeconds = 0
    /// Zoom as the user reads it (native-camera convention: 0.5× is the
    /// ultra-wide lens, 1× the main wide lens). Distinct from the device's raw
    /// `videoZoomFactor`, which is 1.0 at whichever lens is widest.
    var displayZoom: CGFloat = 1.0
    /// Discrete zoom/lens stops to show as buttons for the current camera —
    /// e.g. [0.5, 1, 2] on a phone with an ultra-wide, [1, 2] without one.
    var zoomOptions: [CGFloat] = [1.0]
    /// Which way the attached camera faces. Published rather than read off
    /// `videoInput`, which is session-queue-owned — a FRONT & BACK capture
    /// has to record which lens took the deliberate shot at the instant it
    /// fires, and reading that across the queue boundary is a race.
    var isUsingFrontCamera = false

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "mad.camera.session")
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    /// Session-queue-owned; also the source of truth for the active position.
    @ObservationIgnored private var videoInput: AVCaptureDeviceInput?
    /// `videoZoomFactor` that reads as display 1.0× (the wide lens). On a camera
    /// whose widest lens is ultra-wide this is the UW→W switch-over factor; on a
    /// wide-only camera it's 1.0. Recomputed each time a device is attached.
    @ObservationIgnored private var referenceZoom: CGFloat = 1.0
    @ObservationIgnored private var minDisplayZoom: CGFloat = 1.0
    @ObservationIgnored private var maxDisplayZoom: CGFloat = 1.0
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
            DispatchQueue.main.async { self.isSessionRunning = false }
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
            let running = self.session.isRunning
            DispatchQueue.main.async { self.isSessionRunning = running }
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
        guard let device = Self.bestCamera(for: position),
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
        configureZoom(for: device)
    }

    /// The richest camera for a position: prefer a virtual (fused-lens) device
    /// so zoom is continuous across lenses and 0.5× (ultra-wide) is reachable,
    /// then fall back through to the plain wide lens. The front gets its own
    /// probe order: no iPhone front has an ultra-wide LENS, but a fused front
    /// device would arrive here for free, and configureZoom turns any
    /// zoom-OUT reach the attached device reports into a wide stop.
    private static func bestCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let preferred: [AVCaptureDevice.DeviceType] = position == .back
            ? [
                .builtInTripleCamera,    // ultra-wide + wide + tele  → 0.5×, 1×, 2×/3×
                .builtInDualWideCamera,  // ultra-wide + wide         → 0.5×, 1×
                .builtInDualCamera,      // wide + tele               → 1×, 2×
                .builtInWideAngleCamera, // wide only                 → 1× + digital
            ]
            : [
                .builtInDualWideCamera,  // none shipped yet — picked up if one ever is
                .builtInWideAngleCamera,
            ]
        for type in preferred {
            if let device = AVCaptureDevice.default(type, for: .video, position: position) {
                return device
            }
        }
        return nil
    }

    /// Establish the display↔raw zoom mapping and the available stops for the
    /// just-attached `device`, then open at 1×. Session-queue only. When the
    /// widest lens is the ultra-wide, its raw `videoZoomFactor` of 1.0 reads as
    /// 0.5×, and the wide lens (display 1×) sits at the UW→W switch-over factor.
    private func configureZoom(for device: AVCaptureDevice) {
        let hasUltraWide = device.constituentDevices
            .contains { $0.deviceType == .builtInUltraWideCamera }
        if hasUltraWide, let firstSwitch = device.virtualDeviceSwitchOverVideoZoomFactors.first {
            referenceZoom = CGFloat(firstSwitch.doubleValue)
        } else {
            referenceZoom = 1.0
        }

        let minRaw = device.minAvailableVideoZoomFactor
        // Cap zoom-in at 8× (display) so a huge digital range can't produce a
        // useless, mushy crop.
        let maxRaw = min(device.maxAvailableVideoZoomFactor, referenceZoom * 8)
        minDisplayZoom = minRaw / referenceZoom
        maxDisplayZoom = maxRaw / referenceZoom

        var options: [CGFloat] = []
        if hasUltraWide {
            options.append(0.5)
        } else if minDisplayZoom <= 0.9 {
            // Not just rear ultra-wides: any attached camera that reports
            // zoom-OUT reach below 1× earns a one-tap wide stop — which is
            // what puts "0.5×" on FRONT cameras whose sensor allows the
            // native app's expanded selfie framing. Labeled by what the
            // hardware actually offers (nearest tenth, never below 0.5);
            // pinch could always reach this range, the pill makes it a tap.
            options.append(max(0.5, (minDisplayZoom * 10).rounded() / 10))
        }
        options.append(1.0)
        if maxDisplayZoom >= 2 { options.append(2.0) }

        // Open at 1× (the wide lens), like the stock camera.
        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = max(minRaw, min(referenceZoom, maxRaw))
            device.unlockForConfiguration()
        }

        let opts = options
        DispatchQueue.main.async {
            self.zoomOptions = opts
            self.displayZoom = 1.0
        }
    }

    /// Set the zoom to `factor` in DISPLAY terms (0.5, 1, 2, …), clamped to what
    /// the current lens supports. Drives both the lens buttons and pinch.
    func setDisplayZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }
            let clamped = max(self.minDisplayZoom, min(factor, self.maxDisplayZoom))
            let raw = max(device.minAvailableVideoZoomFactor,
                          min(clamped * self.referenceZoom, device.maxAvailableVideoZoomFactor))
            if (try? device.lockForConfiguration()) != nil {
                device.videoZoomFactor = raw
                device.unlockForConfiguration()
            }
            DispatchQueue.main.async { self.displayZoom = clamped }
        }
    }

    /// Publish everything that depends on WHICH camera is attached. Called
    /// from the same two places an attach happens, so the flash affordance
    /// and the front/back flag can never describe different cameras.
    private func publishFlashAvailability() {
        let supported = photoOutput.supportedFlashModes.contains(.on)
        let front = videoInput?.device.position == .front
        DispatchQueue.main.async {
            self.isFlashAvailable = supported
            self.isUsingFrontCamera = front
        }
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
                let running = self.session.isRunning
                DispatchQueue.main.async { self.isSessionRunning = running }
            }
        }
        // Interruption began (phone call, another app claimed the camera):
        // reflect the stop immediately so the view swaps the frozen frame
        // for the spinner and the shutter reads as not-live.
        sessionObservers.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session, queue: nil
        ) { [weak self] _ in
            self?.publishSessionRunning()
        })
        sessionObservers.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session, queue: nil
        ) { _ in restart() })
        sessionObservers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session, queue: nil
        ) { [weak self] note in
            self?.publishSessionRunning()
            // AVCam's rule: only a media-services reset warrants a restart. A
            // failed startRunning() itself posts a runtime error, so a
            // blanket retry ping-pongs forever under persistent failure.
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            guard error?.code == .mediaServicesWereReset else { return }
            restart()
        })
    }

    /// Re-read the session's actual running state (on its queue) and publish.
    private func publishSessionRunning() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let running = self.session.isRunning
            DispatchQueue.main.async { self.isSessionRunning = running }
        }
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


/// What the camera's bottom-left "Walk photos" button shows and does.
struct CameraWalkPhotos {
    var thumbnail: UIImage?
    var count: Int
    var open: () -> Void
}
