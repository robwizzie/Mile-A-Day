import SwiftUI

/// Run stats handed to the composer to seed the overlay sticker. Carries every
/// stat we can show; `datum(for:)` formats one and returns nil when there's no
/// data, so unavailable stats simply don't appear (and aren't offered as toggles).
struct RunStatsInput {
    var distance: Double
    var paceSecondsPerMile: Double?
    var durationSeconds: Double?
    var streak: Int?
    var calories: Double?
    var steps: Int?
    var workoutId: String?
    var dateText: String?

    var snapshot: PostStats {
        PostStats(
            distance: distance,
            pace: paceSecondsPerMile,
            duration: durationSeconds,
            streak: streak,
            date: dateText,
            calories: calories,
            steps: steps
        )
    }

    /// Stats that actually have data, in a stable display order.
    func availableStats() -> [RunStatKind] {
        RunStatKind.allCases.filter { datum(for: $0) != nil }
    }

    func datum(for kind: RunStatKind) -> RunStatDatum? {
        switch kind {
        case .distance:
            return RunStatDatum(kind: .distance, value: "\(String(format: "%.2f", distance)) mi")
        case .pace:
            guard let p = paceSecondsPerMile, p > 0 else { return nil }
            return RunStatDatum(kind: .pace, value: "\(RunStatsStickerView.paceText(p)) /mi")
        case .duration:
            guard let d = durationSeconds, d > 0 else { return nil }
            return RunStatDatum(kind: .duration, value: RunStatsStickerView.durationText(d))
        case .streak:
            guard let s = streak, s > 0 else { return nil }
            return RunStatDatum(kind: .streak, value: "\(s)")
        case .calories:
            guard let c = calories, c > 0 else { return nil }
            return RunStatDatum(kind: .calories, value: "\(Int(c.rounded())) cal")
        case .steps:
            guard let st = steps, st > 0 else { return nil }
            return RunStatDatum(kind: .steps, value: "\(Self.grouped(st))")
        case .date:
            guard let d = dateText, !d.isEmpty else { return nil }
            return RunStatDatum(kind: .date, value: d)
        }
    }

    private static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// Where a post goes. Stories are the ephemeral 24h moment; the feed is the
/// permanent record. Cross-posting is a deliberate "Both" choice, not the default.
enum PostDestination: String, CaseIterable, Identifiable {
    case story, feed, both
    var id: String { rawValue }

    var title: String {
        switch self {
        case .story: return "Story"
        case .feed: return "Feed"
        case .both: return "Both"
        }
    }

    var icon: String {
        switch self {
        case .story: return "circle.dashed"
        case .feed: return "square.stack"
        case .both: return "square.on.circle"
        }
    }

    var footnote: String {
        switch self {
        case .story: return "Disappears in 24 hours — friends who've done their mile can watch."
        case .feed: return "Stays on your profile and in friends' feeds."
        case .both: return "Posts to your story and your permanent feed."
        }
    }

    var toStory: Bool { self != .feed }
    var toFeed: Bool { self != .story }
}

/// What the composer did, reported back to the presenter.
enum PostComposeOutcome {
    case cancelled
    case published(toFeed: Bool, toStory: Bool)
}

@MainActor
final class PostComposerViewModel: ObservableObject {
    @Published var pickedImage: UIImage?
    @Published var caption: String = ""
    @Published var destination: PostDestination
    @Published var stickerEnabled: Bool = true
    /// Sticker center in normalized canvas coordinates (0…1).
    @Published var stickerPos: CGPoint = CGPoint(x: 0.5, y: 0.82)
    @Published var stickerScale: CGFloat = 1.0
    @Published var config: StickerConfig
    @Published var isPublishing = false
    @Published var errorMessage: String?
    /// Whether the linked workout has a GPS route to offer alongside the photo.
    @Published var hasRoute = false
    /// User choice: show the route map with this post (carousel slide 2).
    @Published var includeRoute = true
    /// Publish was rejected server-side for unaccepted guidelines — the view
    /// re-presents the gate when this flips true.
    @Published var needsTermsGate = false

    let stats: RunStatsInput
    /// Captured on-screen canvas size (points), reused to render the composite.
    var canvasSize: CGSize = .zero

    init(stats: RunStatsInput, destination: PostDestination, initialImage: UIImage? = nil) {
        self.stats = stats
        self.destination = destination
        var cfg = StickerConfig.load()
        // Drop any remembered stats that aren't available today, and make sure
        // at least one available stat is shown.
        let available = Set(stats.availableStats())
        cfg.enabled = cfg.enabled.filter { available.contains($0) }
        if cfg.enabled.isEmpty { cfg.enabled = Array(available.prefix(1)) }
        self.config = cfg
        // Bring the sticker back at the size and spot it was last posted at
        // (StickerConfig sanitizes on decode; ranges live there too).
        self.stickerScale = cfg.scale
        self.stickerPos = CGPoint(x: cfg.posX, y: cfg.posY)
        // Seed a pre-chosen photo (mid-run snap) AFTER all stored properties
        // are initialized — the @Published setter touches self.
        self.pickedImage = initialImage
    }

    var canPublish: Bool {
        pickedImage != nil && !isPublishing
    }

    /// Check whether the linked workout has GPS route data, enabling the
    /// "Include route map" toggle. No route (indoor/manual) → toggle hidden.
    /// Cheap existence probe — never enumerates the route's locations.
    func checkRouteAvailability() async {
        // Master "Share route maps" setting off → never offer the per-post
        // toggle (the server wouldn't ship the route to friends anyway).
        guard NotificationPreferences.load().shareRouteMaps else { return }
        guard !hasRoute, let workoutId = stats.workoutId else { return }
        let workout = HealthKitManager.shared.todaysWorkouts
            .first { $0.uuid.uuidString == workoutId }
        guard let workout else { return }
        hasRoute = await HealthKitManager.shared.hasRouteData(for: workout)
    }

    /// Render the on-screen canvas (photo + sticker) to a flat JPEG-ready image
    /// at ~1080px wide, baking the overlay in. Returns nil if no photo.
    func flatten() -> UIImage? {
        guard let image = pickedImage, canvasSize.width > 0 else { return nil }
        let canvas = PostCanvas(
            image: image,
            showSticker: stickerEnabled,
            stickerPos: stickerPos,
            stickerScale: stickerScale,
            input: stats,
            config: config
        )
        .frame(width: canvasSize.width, height: canvasSize.height)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = max(1, 1080 / canvasSize.width)
        renderer.isOpaque = true
        return renderer.uiImage
    }

    func publish() async -> Bool {
        guard !isPublishing else { return false }
        guard let flat = flatten() else {
            errorMessage = "Add a photo first."
            return false
        }
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }

        do {
            let mediaUrl = try await PostService.uploadMedia(flat)
            _ = try await PostService.createPost(
                mediaUrl: mediaUrl,
                caption: caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : caption,
                workoutId: stats.workoutId,
                shareToFeed: destination.toFeed,
                shareToStory: destination.toStory,
                stats: stats.snapshot,
                isAuto: false,
                includeRoute: includeRoute
            )
            if stickerEnabled {
                // Remember the user's overlay style — but merge back any stats
                // that were remembered and merely had no data TODAY (init
                // filters those out of the session config); otherwise one
                // treadmill day permanently erases a saved choice like pace.
                var toSave = config
                let available = Set(stats.availableStats())
                let rememberedUnavailable = StickerConfig.load().enabled
                    .filter { !available.contains($0) }
                toSave.enabled = config.enabled + rememberedUnavailable
                // Remember the transform too, so the next post's sticker shows
                // up at this exact size and position.
                toSave.scale = stickerScale
                toSave.posX = stickerPos.x
                toSave.posY = stickerPos.y
                toSave.save()
            }
            return true
        } catch let APIError.apiError(message) where message == "mile_not_completed" {
            errorMessage = "Finish today's mile before you post."
            return false
        } catch let APIError.apiError(message) where message == "terms_not_accepted" {
            // Stale local acceptance — clear the memo and re-gate.
            PostService.cacheTermsAccepted(false)
            needsTermsGate = true
            errorMessage = "Please accept the community guidelines to post."
            return false
        } catch APIError.conflict {
            // One deliberate post per workout — a reward, not a redo.
            errorMessage = "You've already shared a post for this workout. Delete it first if you want to post a new one."
            return false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't share your post. Try again."
            return false
        }
    }
}

/// The photo + sticker canvas (4:5). Shared by the live editor preview and the
/// ImageRenderer flatten so what you see is exactly what's uploaded.
struct PostCanvas: View {
    let image: UIImage
    let showSticker: Bool
    let stickerPos: CGPoint
    let stickerScale: CGFloat
    let input: RunStatsInput
    let config: StickerConfig

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                if showSticker {
                    RunStatsStickerView(input: input, config: config)
                        .scaleEffect(stickerScale)
                        .position(x: stickerPos.x * geo.size.width, y: stickerPos.y * geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

struct PostComposerView: View {
    /// Community-guidelines acceptance, resolved before sharing is allowed
    /// (App Review 1.2 — and the server rejects un-accepted posts anyway, so
    /// gating up front beats a dead-end publish error). The CAMERA is never
    /// blocked on this: capturing preserves the moment (and lands in the
    /// user's camera roll) — only composing/sharing waits for acceptance.
    private enum TermsState { case unknown, accepted, needsAcceptance }

    @StateObject private var vm: PostComposerViewModel
    @State private var showCamera = false
    /// Seeded from the local cache so a returning poster never waits on (or
    /// races) the network check in `resolveTermsIfNeeded`.
    @State private var termsState: TermsState =
        PostService.termsAcceptedCached ? .accepted : .unknown
    @State private var showTermsGate = false
    /// Gate outcome relayed by PostTermsGateView.onAccepted, read in the
    /// cover's onDismiss — deliberately not inferred from the cache so gate
    /// internals can change without silently breaking this flow.
    @State private var gateAccepted = false
    /// The auto camera open must fire exactly once: .onAppear re-fires every
    /// time a fullScreenCover dismisses, and re-opening on each pass would
    /// trap the user in the camera with no way back.
    @State private var didAutoOpenCamera = false
    @State private var gestureBaseScale: CGFloat = 1.0
    /// Sticker position at drag start (normalized) — drags apply translation
    /// relative to this instead of jumping to the touch point.
    @State private var gestureBasePos: CGPoint? = nil
    @FocusState private var captionFocused: Bool
    /// Launch straight into the camera on first appear (post-run prompt flow) —
    /// the user already tapped "Take a photo" once to get here.
    let autoOpenCamera: Bool
    let onFinished: (PostComposeOutcome) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        stats: RunStatsInput,
        destination: PostDestination = .feed,
        autoOpenCamera: Bool = false,
        initialImage: UIImage? = nil,
        onFinished: @escaping (PostComposeOutcome) -> Void
    ) {
        _vm = StateObject(wrappedValue: PostComposerViewModel(
            stats: stats, destination: destination, initialImage: initialImage))
        self.autoOpenCamera = autoOpenCamera
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        canvasSection
                        if vm.pickedImage != nil {
                            overlayEditor
                            if vm.hasRoute { routeToggle }
                            captionField
                            destinationToggles
                        }
                        if let error = vm.errorMessage {
                            Text(error)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(MADTheme.Colors.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                // The guidelines gate rides on the ScrollView so it never
                // collides with the camera cover attached to the ZStack —
                // two covers on one node drop one of the presentations.
                .fullScreenCover(isPresented: $showTermsGate, onDismiss: {
                    if gateAccepted {
                        gateAccepted = false
                        termsState = .accepted
                        vm.errorMessage = nil
                    } else if vm.pickedImage == nil {
                        // Declined with nothing composed — nothing to lose;
                        // back out so the post-run prompt / feed takes over.
                        onFinished(.cancelled)
                        dismiss()
                    } else {
                        // Declined with a draft on screen: NEVER destroy it.
                        // Share stays locked (tapping it re-opens the gate);
                        // Cancel remains the deliberate way out.
                        vm.errorMessage = "Accept the community guidelines to share your post."
                    }
                }) {
                    PostTermsGateView { gateAccepted = true }
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Disabled while publishing: publish() has no cancellation
                    // hook, so a Cancel racing an in-flight upload would fire
                    // onFinished twice with contradictory outcomes (the
                    // post-run prompt would auto-post the route card AND the
                    // photo post would land server-side).
                    Button("Cancel") { onFinished(.cancelled); dismiss() }
                        .foregroundColor(.white.opacity(vm.isPublishing ? 0.4 : 1))
                        .disabled(vm.isPublishing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isPublishing {
                        ProgressView().tint(.white)
                    } else {
                        Button("Share") {
                            switch termsState {
                            case .accepted:
                                Task {
                                    let ok = await vm.publish()
                                    if ok {
                                        onFinished(.published(
                                            toFeed: vm.destination.toFeed,
                                            toStory: vm.destination.toStory
                                        ))
                                        dismiss()
                                    }
                                }
                            case .needsAcceptance:
                                // Not allowed to post yet — the button routes
                                // to the guidelines instead of a dead upload.
                                presentGateIfNeeded()
                            case .unknown:
                                // Still resolving; the gate auto-presents if
                                // the answer comes back unaccepted.
                                break
                            }
                        }
                        .fontWeight(.bold)
                        .foregroundColor(vm.canPublish && termsState == .accepted
                            ? MADTheme.Colors.madRed : .white.opacity(0.3))
                        .disabled(!vm.canPublish)
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .madKeyboardDoneButton(focus: $captionFocused)
            .fullScreenCover(isPresented: $showCamera) {
                MADCameraView(image: $vm.pickedImage)
            }
            .onAppear {
                if autoOpenCamera, !didAutoOpenCamera, vm.pickedImage == nil {
                    didAutoOpenCamera = true
                    requestCamera()
                }
            }
            .task { await resolveTermsIfNeeded() }
            .task { await vm.checkRouteAvailability() }
            // Re-probe once a photo lands — todaysWorkouts may not have been
            // loaded yet when the composer first appeared.
            .onChange(of: vm.pickedImage) { _, newImage in
                guard newImage != nil else { return }
                Task { await vm.checkRouteAvailability() }
            }
            // A gate held back while the camera cover was up presents as soon
            // as the camera closes.
            .onChange(of: showCamera) { _, isUp in
                guard !isUp else { return }
                presentGateIfNeeded()
            }
            // The server rejected a publish for unaccepted terms (stale local
            // state) — re-gate instead of dead-ending on the error label.
            .onChange(of: vm.needsTermsGate) { _, needs in
                guard needs else { return }
                vm.needsTermsGate = false
                termsState = .needsAcceptance
                presentGateIfNeeded()
            }
        }
    }

    // MARK: - Guidelines gate

    /// Opening the camera never waits on the guidelines — see TermsState.
    private func requestCamera() {
        guard MADCameraView.isAvailable else { return }
        showCamera = true
    }

    private func resolveTermsIfNeeded() async {
        guard termsState == .unknown else { return }
        if PostService.termsAcceptedCached {
            termsState = .accepted
            return
        }
        // Failed check (offline) ⇒ treat as not accepted: the gate explains
        // the block and Share stays locked, while the camera keeps working so
        // the moment itself is never lost.
        let accepted = (try? await PostService.termsStatus())?.accepted ?? false
        termsState = accepted ? .accepted : .needsAcceptance
        presentGateIfNeeded()
    }

    /// Present the gate once no other cover is up — presenting while the
    /// camera cover is active would drop the presentation entirely.
    private func presentGateIfNeeded() {
        guard termsState == .needsAcceptance, !showCamera, !showTermsGate else { return }
        showTermsGate = true
    }

    /// Offer to ride the run's GPS route along with the photo (shown as a
    /// second, swipeable slide on the feed card). Only offered when the linked
    /// workout actually has route data.
    private var routeToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $vm.includeRoute.animation(.easeInOut)) {
                Label("Include route map", systemImage: "map.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .tint(MADTheme.Colors.madRed)
            Text("Friends can swipe to see your mile's path next to the photo.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Canvas

    private var canvasSection: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = width * 5 / 4
            Group {
                if let image = vm.pickedImage {
                    ZStack {
                        PostCanvas(
                            image: image,
                            showSticker: vm.stickerEnabled,
                            stickerPos: vm.stickerPos,
                            stickerScale: vm.stickerScale,
                            input: vm.stats,
                            config: vm.config
                        )
                        if vm.stickerEnabled {
                            stickerGestureLayer(canvas: CGSize(width: width, height: height))
                        }
                    }
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous))
                    // Track the LIVE geometry (initial + every later pass) —
                    // a size captured once on appear can go stale (e.g. first
                    // layout while the camera cover is up) and flatten() would
                    // render the sticker at a different relative size than the
                    // preview. geo.size is already 4:5 via the aspectRatio.
                    .onChange(of: geo.size, initial: true) { _, size in
                        guard size.width > 0 else { return }
                        vm.canvasSize = size
                    }
                    .overlay(alignment: .topTrailing) {
                        Button { requestCamera() } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Retake")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(.black.opacity(0.5)))
                        }
                        .padding(10)
                    }
                    .overlay(alignment: .bottom) {
                        if vm.stickerEnabled {
                            Text("Drag to move · pinch to resize")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.65))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(.black.opacity(0.4)))
                                .padding(.bottom, 8)
                        }
                    }
                } else {
                    photoPlaceholder.frame(width: width, height: height)
                }
            }
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
    }

    private var photoPlaceholder: some View {
        Button { requestCamera() } label: {
            VStack(spacing: MADTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(MADTheme.Colors.redGradient)
                        .frame(width: 84, height: 84)
                        .shadow(color: MADTheme.Colors.madRed.opacity(0.4), radius: 16, y: 6)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(spacing: 4) {
                    Text(MADCameraView.isAvailable ? "Take a photo" : "Camera unavailable")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(MADCameraView.isAvailable
                        ? "Snap today's walk or run — camera keeps it real."
                        : "A camera is required to share a post.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MADTheme.Spacing.lg)
                }

                if MADCameraView.isAvailable {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.system(size: 13, weight: .bold))
                        Text("Open camera").font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(MADTheme.Colors.redGradient))
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                            .foregroundColor(.white.opacity(0.2))
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!MADCameraView.isAvailable)
    }

    private func stickerGestureLayer(canvas: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            // Base the first pinch on the RESTORED scale — the default 1.0
            // would make a remembered smaller/larger sticker jump on touch.
            .onAppear { gestureBaseScale = vm.stickerScale }
            .gesture(
                SimultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            // Move RELATIVE to where the sticker started — a
                            // location-based move teleports the sticker to
                            // wherever the finger first lands on the canvas.
                            let base = gestureBasePos ?? vm.stickerPos
                            if gestureBasePos == nil { gestureBasePos = vm.stickerPos }
                            let x = base.x + value.translation.width / canvas.width
                            let y = base.y + value.translation.height / canvas.height
                            vm.stickerPos = CGPoint(
                                x: x.clamped(to: StickerConfig.posXRange),
                                y: y.clamped(to: StickerConfig.posYRange)
                            )
                        }
                        .onEnded { _ in gestureBasePos = nil },
                    MagnificationGesture()
                        .onChanged { value in
                            vm.stickerScale = (gestureBaseScale * value)
                                .clamped(to: StickerConfig.scaleRange)
                        }
                        .onEnded { _ in gestureBaseScale = vm.stickerScale }
                )
            )
    }

    // MARK: - Overlay editor

    private var overlayEditor: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            Toggle(isOn: $vm.stickerEnabled.animation(.easeInOut)) {
                Label("Show run stats", systemImage: "chart.bar.doc.horizontal")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .tint(MADTheme.Colors.madRed)

            if vm.stickerEnabled {
                editorLabel("STYLE")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MADTheme.Spacing.sm) {
                        ForEach(StickerStyle.allCases) { style in
                            chip(
                                title: style.title, icon: style.icon,
                                selected: vm.config.style == style
                            ) { vm.config.style = style }
                        }
                    }
                }

                editorLabel("SHOW")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MADTheme.Spacing.sm) {
                        ForEach(vm.stats.availableStats()) { kind in
                            chip(
                                title: kind.label, icon: kind.icon,
                                selected: vm.config.isOn(kind)
                            ) { vm.config.toggle(kind) }
                        }
                    }
                }

                editorLabel("COLOR")
                HStack(spacing: MADTheme.Spacing.md) {
                    ForEach(StickerAccent.allCases) { accent in
                        Button { vm.config.accent = accent } label: {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Circle().strokeBorder(
                                        Color.white,
                                        lineWidth: vm.config.accent == accent ? 2.5 : 0
                                    )
                                )
                                .overlay(
                                    Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func editorLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.4))
    }

    private func chip(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(selected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                Capsule().fill(selected ? AnyShapeStyle(MADTheme.Colors.redGradient) : AnyShapeStyle(Color.white.opacity(0.07)))
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(selected ? 0 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("", text: $vm.caption, prompt: Text("Add a caption…").foregroundColor(.white.opacity(0.4)), axis: .vertical)
                .lineLimit(1...4)
                .focused($captionFocused)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .padding(MADTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .fill(Color.white.opacity(0.06))
                )
            Text("\(vm.caption.count)/280")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(vm.caption.count > 280 ? MADTheme.Colors.error : .white.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .onChange(of: vm.caption) { _, newValue in
            if newValue.count > 280 { vm.caption = String(newValue.prefix(280)) }
        }
    }

    /// Story / Feed / Both — a single deliberate destination choice, so the
    /// story stays the ephemeral moment and the feed stays the curated record.
    private var destinationToggles: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            editorLabel("SHARE TO")
            HStack(spacing: MADTheme.Spacing.sm) {
                ForEach(PostDestination.allCases) { dest in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.destination = dest }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: dest.icon)
                                .font(.system(size: 16, weight: .bold))
                            Text(dest.title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(vm.destination == dest ? .white : .white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                                .fill(vm.destination == dest
                                    ? AnyShapeStyle(MADTheme.Colors.redGradient)
                                    : AnyShapeStyle(Color.white.opacity(0.06)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                                .strokeBorder(Color.white.opacity(vm.destination == dest ? 0 : 0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(vm.destination.footnote)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.04))
        )
    }
}
