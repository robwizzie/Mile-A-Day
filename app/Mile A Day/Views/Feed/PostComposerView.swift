import SwiftUI

/// Run stats handed to the composer to seed the overlay sticker. Carries every
/// stat we can show; `datum(for:)` formats one and returns nil when there's no
/// data, so unavailable stats simply don't appear (and aren't offered as toggles).
struct RunStatsInput: Equatable {
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

    /// Shared decimal formatter — allocating a `NumberFormatter` per render was
    /// a needless per-frame cost. Rendering is @MainActor, so sharing is safe.
    private static let stepsFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private static func grouped(_ n: Int) -> String {
        stepsFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
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
    /// Where the post goes. Starts nil ON PURPOSE — the user must make the
    /// story/feed/both choice themselves before Share enables, so nobody
    /// posts somewhere they didn't mean to.
    @Published var destination: PostDestination?
    @Published var stickerEnabled: Bool = true
    /// Sticker center in normalized canvas coordinates (0…1).
    @Published var stickerPos: CGPoint = CGPoint(x: 0.5, y: 0.82)
    @Published var stickerScale: CGFloat = 1.0
    /// Sticker rotation (two-finger twist), baked into the shared image.
    @Published var stickerRotation: Angle = .zero
    @Published var config: StickerConfig
    @Published var isPublishing = false
    @Published var errorMessage: String?
    /// Whether the linked workout has a GPS route to offer alongside the photo.
    @Published var hasRoute = false
    /// User choice: show the route map with this post (carousel slide 2).
    @Published var includeRoute = true
    /// Collab post: the friend this mile was run with. They get an invite and,
    /// once accepted, the post shows both names and lands on both profiles.
    @Published var coauthor: BackendUser?
    /// Publish was rejected server-side for unaccepted guidelines — the view
    /// re-presents the gate when this flips true.
    @Published var needsTermsGate = false

    let stats: RunStatsInput
    /// Captured on-screen canvas size (points), reused to render the composite.
    var canvasSize: CGSize = .zero

    init(stats: RunStatsInput, initialImage: UIImage? = nil) {
        self.stats = stats
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
        self.stickerRotation = Angle(degrees: cfg.rotation)
        // Seed a pre-chosen photo (mid-run snap) AFTER all stored properties
        // are initialized — the @Published setter touches self.
        self.pickedImage = initialImage
    }

    var canPublish: Bool {
        pickedImage != nil && destination != nil && !isPublishing
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
            stickerRotation: stickerRotation,
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
        guard let destination else {
            errorMessage = "Choose where to share — story, feed, or both."
            return false
        }
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }

        do {
            let mediaUrl = try await PostService.uploadMedia(flat)
            let created = try await PostService.createPost(
                mediaUrl: mediaUrl,
                caption: caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : caption,
                workoutId: stats.workoutId,
                shareToFeed: destination.toFeed,
                shareToStory: destination.toStory,
                stats: stats.snapshot,
                isAuto: false,
                includeRoute: includeRoute,
                // Feed posts only — the server ignores it otherwise anyway.
                coauthorUserId: destination.toFeed ? coauthor?.user_id : nil
            )
            // Reward posts shared inside the run's 10-min fresh window with a
            // "Fresh" badge. No-op when the window is closed.
            FreshPostWindowManager.shared.markPostedLive(
                postId: created.post_id,
                workoutId: created.workout_id ?? stats.workoutId
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
                toSave.rotation = stickerRotation.degrees
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
        } catch APIError.badRequest("invalid_coauthor") {
            errorMessage = "You can only co-post with an accepted friend."
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
    var stickerRotation: Angle = .zero
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
                        .rotationEffect(stickerRotation)
                        .position(x: stickerPos.x * geo.size.width, y: stickerPos.y * geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

/// The live, manipulable sticker in the composer editor. Holds the in-flight
/// drag / pinch / twist as transient `@GestureState` and applies it directly to
/// the sticker, committing to the bindings ONLY on `.onEnded`. Because the
/// committed VM values aren't touched mid-gesture, the rest of the composer
/// never re-renders during a manipulation — this is what makes it feel as
/// smooth as Instagram instead of re-laying-out the whole screen every frame.
/// The sticker is wrapped in `.equatable()` (outside the transforms) so its own
/// body — drop shadow, number formatting — is rendered once and only its cheap
/// transform matrix changes per frame.
private struct StickerEditorLayer: View {
    let input: RunStatsInput
    let config: StickerConfig
    /// Canvas size in points — the SAME value `flatten()` renders at, so the
    /// live sticker and the baked image land pixel-identically.
    let canvas: CGSize
    @Binding var pos: CGPoint      // normalized 0…1 center (committed)
    @Binding var scale: CGFloat    // committed
    @Binding var rotation: Angle   // committed

    // Identity-at-rest transients — SwiftUI auto-resets these when the gesture
    // ends, in the same transaction the `.onEnded` commit lands, so there's no
    // jump between "committed ∘ transient" and the new committed value.
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var magnifyFactor: CGFloat = 1
    @GestureState private var twist: Angle = .zero

    var body: some View {
        RunStatsStickerView(input: input, config: config)
            .equatable()                       // MUST stay OUTSIDE the transforms
            .scaleEffect(liveScale)
            .rotationEffect(liveRotation)
            // Generous, invisible hit margin so a shrunk-down sticker stays easy
            // to grab. After the transforms → a fixed screen-space margin.
            .padding(20)
            .contentShape(Rectangle())
            .gesture(manipulation)             // BEFORE .position → grab the sticker itself
            .position(liveCenter)
    }

    // Live = committed ∘ transient, clamped IDENTICALLY to the `.onEnded` commit
    // so releasing never snaps the sticker to a different spot/size.
    private var liveScale: CGFloat {
        (scale * magnifyFactor).clamped(to: StickerConfig.scaleRange)
    }
    private var liveRotation: Angle { rotation + twist }
    private var liveCenter: CGPoint {
        CGPoint(x: committedX(addingDrag: dragTranslation.width) * canvas.width,
                y: committedY(addingDrag: dragTranslation.height) * canvas.height)
    }

    private func committedX(addingDrag dx: CGFloat) -> CGFloat {
        (pos.x + dx / max(canvas.width, 1)).clamped(to: StickerConfig.posXRange)
    }
    private func committedY(addingDrag dy: CGFloat) -> CGFloat {
        (pos.y + dy / max(canvas.height, 1)).clamped(to: StickerConfig.posYRange)
    }

    private var manipulation: some Gesture {
        // Measure the drag in GLOBAL (screen) space, not the default `.local`.
        // The sticker is moved every frame by `.position(liveCenter)` and sits
        // below `.scaleEffect`/`.rotationEffect`, so its local space moves AND
        // rotates with it — a local-space translation feeds back on itself and
        // makes the sticker jitter (and drags along the rotated axis). Global
        // space is fixed to the screen, so `translation` is the true finger
        // delta: smooth, straight, and rotation-independent.
        let drag = DragGesture(coordinateSpace: .global)
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
                pos = CGPoint(x: committedX(addingDrag: value.translation.width),
                              y: committedY(addingDrag: value.translation.height))
            }
        let magnify = MagnifyGesture()
            .updating($magnifyFactor) { value, state, _ in state = value.magnification }
            .onEnded { value in
                scale = (scale * value.magnification).clamped(to: StickerConfig.scaleRange)
            }
        let rotate = RotateGesture()
            .updating($twist) { value, state, _ in state = value.rotation }
            .onEnded { value in
                rotation = rotation + value.rotation
            }
        return drag.simultaneously(with: magnify).simultaneously(with: rotate)
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
    @StateObject private var friendService = FriendService()
    @State private var showCoauthorPicker = false
    @State private var showCamera = false
    // Library import of a photo captured DURING this walk/run (window-filtered
    // for authenticity, same as the post-run prompt). Its cover rides the
    // `canvasSection` node — a third cover on the ScrollView or the ZStack
    // (which already own the terms + camera covers) would silently drop one.
    @State private var showLibraryImport = false
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
    /// "Saved to Photos" confirmation for the canvas Save button.
    @State private var showSavedToPhotos = false
    @FocusState private var captionFocused: Bool
    /// Launch straight into the camera on first appear (post-run prompt flow) —
    /// the user already tapped "Take a photo" once to get here.
    let autoOpenCamera: Bool
    /// Post-run prompt flow: leaving returns to the snap picker with nothing
    /// lost, so the exit reads "‹ Back" instead of "Cancel" (which made
    /// people fear their photos would be discarded).
    let backNavigation: Bool
    let onFinished: (PostComposeOutcome) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        stats: RunStatsInput,
        autoOpenCamera: Bool = false,
        initialImage: UIImage? = nil,
        backNavigation: Bool = false,
        onFinished: @escaping (PostComposeOutcome) -> Void
    ) {
        _vm = StateObject(wrappedValue: PostComposerViewModel(
            stats: stats, initialImage: initialImage))
        self.autoOpenCamera = autoOpenCamera
        self.backNavigation = backNavigation
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        canvasSection
                            // Distinct node from the ScrollView (terms gate) and
                            // the ZStack (camera) — see showLibraryImport.
                            .fullScreenCover(isPresented: $showLibraryImport) {
                                WorkoutPhotoImportPicker(window: importWindow) { result in
                                    showLibraryImport = false
                                    switch result {
                                    case .accepted(let image):
                                        vm.pickedImage = image
                                    case .failed:
                                        vm.errorMessage = "Couldn't load that photo. Try another one."
                                    case .cancelled:
                                        break
                                    }
                                }
                            }
                        // A photo snapped DURING this walk/run is a valid post,
                        // not just a fresh camera shot — mirrors the post-run
                        // prompt's "Choose from this walk". Only offered when the
                        // post is tied to a workout (empty state only).
                        if vm.pickedImage == nil, vm.stats.workoutId != nil {
                            chooseFromLibraryButton
                        }
                        if vm.pickedImage != nil {
                            overlayEditor
                            if vm.hasRoute { routeToggle }
                            captionField
                            // Collabs are a feed concept — shown once the user
                            // picks a destination that includes the feed
                            // (destination starts nil until they choose).
                            if vm.destination?.toFeed == true { coauthorRow }
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
                    Button { onFinished(.cancelled); dismiss() } label: {
                        if backNavigation {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                            }
                        } else {
                            Text("Cancel")
                        }
                    }
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
                                    if ok, let dest = vm.destination {
                                        onFinished(.published(
                                            toFeed: dest.toFeed,
                                            toStory: dest.toStory
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
            .task { try? await friendService.loadFriends() }
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
                        // Photo only. The sticker is a SEPARATE, isolated layer
                        // (StickerEditorLayer) so dragging/pinching/rotating it
                        // never re-renders this canvas or the rest of the
                        // composer — the key to an Instagram-smooth feel.
                        PostCanvas(
                            image: image,
                            showSticker: false,
                            stickerPos: vm.stickerPos,
                            stickerScale: vm.stickerScale,
                            input: vm.stats,
                            config: vm.config
                        )
                        if vm.stickerEnabled {
                            // Pass geo.size — the exact value flatten() renders
                            // at (via vm.canvasSize) — for pixel-perfect parity.
                            StickerEditorLayer(
                                input: vm.stats,
                                config: vm.config,
                                canvas: geo.size,
                                pos: $vm.stickerPos,
                                scale: $vm.stickerScale,
                                rotation: $vm.stickerRotation
                            )
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
                    // Keep a copy exactly as composed — stats sticker baked
                    // in (the camera already saved the RAW shot at capture).
                    .overlay(alignment: .topLeading) {
                        Button {
                            guard let flat = vm.flatten() else { return }
                            PhotoRollSaver.save(flat)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showSavedToPhotos = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation(.easeOut(duration: 0.25)) { showSavedToPhotos = false }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: showSavedToPhotos
                                    ? "checkmark.circle.fill" : "square.and.arrow.down")
                                    .font(.system(size: 12, weight: .bold))
                                Text(showSavedToPhotos ? "Saved" : "Save")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(showSavedToPhotos ? .green : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(.black.opacity(0.5)))
                        }
                        .padding(10)
                        .disabled(showSavedToPhotos)
                    }
                    .overlay(alignment: .bottom) {
                        if vm.stickerEnabled {
                            Text("Drag · pinch · twist")
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

    /// Secondary CTA in the empty state: pick a photo the user already took on
    /// this walk/run (the window-filtered library importer). Styled to sit
    /// below the camera placeholder without competing with it.
    private var chooseFromLibraryButton: some View {
        Button { showLibraryImport = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("Choose a photo from this walk or run")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.white.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule().fill(Color.white.opacity(0.1))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    /// Accepted capture-time window for the library importer, from the linked
    /// workout's own start/end (HealthKit) with grace on both ends. Mirrors the
    /// post-run prompt: when the workout hasn't synced into `todaysWorkouts` yet
    /// we bound to a generous recent window rather than the whole day, so an
    /// unrelated earlier photo still can't slip in.
    private var importWindow: ClosedRange<Date> {
        let now = Date()
        guard let wid = vm.stats.workoutId,
              let workout = HealthKitManager.shared.todaysWorkouts
                .first(where: { $0.uuid.uuidString == wid }) else {
            return now.addingTimeInterval(-3 * 60 * 60)...now.addingTimeInterval(2 * 60)
        }
        let start = workout.startDate.addingTimeInterval(-5 * 60)
        let end = workout.endDate.addingTimeInterval(30 * 60)
        return start...max(start, end)
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

    /// Friends matching an @token being typed at the end of the caption.
    /// Explicit types — inference across filter/prefix chains slows the
    /// type checker to a crawl.
    private var captionMentionCandidates: [BackendUser] {
        guard let token = vm.caption.split(separator: " ").last, token.hasPrefix("@") else { return [] }
        let query: String = String(token.dropFirst()).lowercased()
        let matches: [BackendUser] = friendService.friends.filter { friend in
            guard let name = friend.username?.lowercased() else { return false }
            return query.isEmpty || name.hasPrefix(query)
        }
        return Array(matches.prefix(8))
    }

    private func completeCaptionMention(_ friend: BackendUser) {
        var parts = vm.caption.split(separator: " ", omittingEmptySubsequences: false)
        if let last = parts.last, last.hasPrefix("@") { parts.removeLast() }
        vm.caption = (parts + ["@\(friend.username ?? "") "]).joined(separator: " ")
    }

    private func mentionChip(_ friend: BackendUser) -> some View {
        Button {
            completeCaptionMention(friend)
        } label: {
            HStack(spacing: 6) {
                AvatarView(name: friend.username ?? "?",
                           imageURL: friend.profile_image_url, size: 22)
                Text("@\(friend.username ?? "")")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("", text: $vm.caption, prompt: Text("Add a caption… (@ to tag a friend)").foregroundColor(.white.opacity(0.4)), axis: .vertical)
                .lineLimit(1...4)
                .focused($captionFocused)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .padding(MADTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                        .fill(Color.white.opacity(0.06))
                )
            if !captionMentionCandidates.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(captionMentionCandidates, id: \.user_id) { friend in
                            mentionChip(friend)
                        }
                    }
                }
            }
            HStack {
                // Anchored to the field it dismisses (a keyboard-toolbar Done
                // floated as a detached pill over the counter on iOS 26) —
                // Return adds newlines in this multi-line field, so this is
                // THE way to put the keyboard away.
                if captionFocused {
                    Button {
                        captionFocused = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 11, weight: .bold))
                            Text("Done")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(MADTheme.Colors.redGradient))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                Spacer()
                Text("\(vm.caption.count)/280")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(vm.caption.count > 280 ? MADTheme.Colors.error : .white.opacity(0.4))
            }
            .animation(.easeInOut(duration: 0.15), value: captionFocused)
        }
        .onChange(of: vm.caption) { _, newValue in
            if newValue.count > 280 { vm.caption = String(newValue.prefix(280)) }
        }
    }

    /// "Ran it together?" — pick ONE friend to co-post with. They're invited
    /// on share and the post goes dual-author once they accept.
    private var coauthorRow: some View {
        Button { showCoauthorPicker = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(MADTheme.Colors.madRed)
                if let coauthor = vm.coauthor {
                    AvatarView(name: coauthor.username ?? "?",
                               imageURL: coauthor.profile_image_url, size: 26)
                    Text("Co-posting with @\(coauthor.username ?? "")")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        vm.coauthor = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.4))
                    }
                } else {
                    Text("Ran it together? Add a co-poster")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showCoauthorPicker) {
            CoauthorPickerSheet(friends: friendService.friends) { picked in
                vm.coauthor = picked
            }
        }
    }

    /// Story / Feed / Both — a single deliberate destination choice, so the
    /// story stays the ephemeral moment and the feed stays the curated record.
    /// Nothing is preselected: Share stays disabled until the user picks, and
    /// the picked card is unmistakable (gradient fill + checkmark badge).
    private var destinationToggles: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            editorLabel("SHARE TO")
            HStack(spacing: MADTheme.Spacing.sm) {
                ForEach(PostDestination.allCases) { dest in
                    destinationCard(dest, selected: vm.destination == dest)
                }
            }
            if let dest = vm.destination {
                Text(dest.footnote)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Pick where this goes — Share unlocks once you choose.",
                      systemImage: "hand.tap.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(MADTheme.Colors.madRed.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .fill(Color.white.opacity(0.04))
        )
        // Until a destination is chosen this section is the one thing left to
        // do — a soft accent border pulls the eye to it.
        .overlay(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                .strokeBorder(
                    MADTheme.Colors.madRed.opacity(vm.destination == nil ? 0.45 : 0),
                    lineWidth: 1.5
                )
        )
        .animation(.easeInOut(duration: 0.2), value: vm.destination)
    }

    private func destinationCard(_ dest: PostDestination, selected: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.15)) { vm.destination = dest }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: dest.icon)
                    .font(.system(size: 16, weight: .bold))
                Text(dest.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(selected ? .white : .white.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                    .fill(selected
                        ? AnyShapeStyle(MADTheme.Colors.redGradient)
                        : AnyShapeStyle(Color.white.opacity(0.06)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0 : 0.1), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white, .black.opacity(0.35))
                        .padding(5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Pick one accepted friend as the post's co-author (Instagram collab style).
struct CoauthorPickerSheet: View {
    let friends: [BackendUser]
    let onPick: (BackendUser) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [BackendUser] {
        guard !search.isEmpty else { return friends }
        let q = search.lowercased()
        return friends.filter {
            ($0.username?.lowercased().contains(q) ?? false)
                || ($0.first_name?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()
                if friends.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .font(.system(size: 34))
                            .foregroundColor(.white.opacity(0.3))
                        Text("Add friends to co-post")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered, id: \.user_id) { friend in
                                Button {
                                    onPick(friend)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        AvatarView(name: friend.username ?? "?",
                                                   imageURL: friend.profile_image_url, size: 42)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(friend.username ?? friend.first_name ?? "Friend")
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                            if let first = friend.first_name, !first.isEmpty {
                                                Text(first)
                                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                                    .foregroundColor(.white.opacity(0.5))
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, MADTheme.Spacing.md)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, MADTheme.Spacing.sm)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Co-post with")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $search, prompt: "Search friends")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
