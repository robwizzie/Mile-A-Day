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
    /// Display-only composite for the share step's thumbnail. Rendered from the
    /// SAME `flatten()` the upload uses, so the thumbnail is literally the image
    /// that ships — sticker baked in, cropped 4:5 exactly as the feed shows it.
    /// Never read by `publish()`: that re-flattens, so the upload path stays
    /// byte-for-byte what it has always been.
    @Published var previewComposite: UIImage?

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

    /// A photo on the canvas IS the draft — the caption and sticker ride with it.
    /// Gates the discard confirmation.
    var hasDraft: Bool { pickedImage != nil }

    /// The sticker has been moved/resized/tilted off its default placement.
    /// Epsilon-compared because pinch and twist land on irrational values.
    var isStickerTransformed: Bool {
        abs(stickerPos.x - 0.5) > 0.001
            || abs(stickerPos.y - 0.82) > 0.001
            || abs(stickerScale - 1) > 0.001
            || abs(stickerRotation.degrees) > 0.001
    }

    func resetStickerPlacement() {
        stickerPos = CGPoint(x: 0.5, y: 0.82)
        stickerScale = 1
        stickerRotation = .zero
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
                coauthorUserId: destination.toFeed ? coauthor?.user_id : nil,
                // Server-side FRESH: the claim rides with the post so EVERY
                // viewer sees the badge, not just this device.
                postedLive: FreshPostWindowManager.shared.isOpen
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
///
/// Placement aids (centre snap, guides, selection ring) live ENTIRELY in here for
/// the same reason: routing snap state up through a `@Binding` would re-render the
/// whole composer mid-drag and undo the isolation this layer exists to provide.
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
    @GestureState private var isManipulating = false

    /// Natural, untransformed sticker size. Measured under the transforms, so it
    /// only changes when the style / enabled stats change — never per frame.
    @State private var natural: CGSize = .zero
    /// One-shot latch so the snap haptic fires on ENTERING the centre zone rather
    /// than on every frame spent inside it.
    @State private var snappedX = false
    @State private var snappedY = false

    /// Finger travel (points) within which the sticker locks to a centre line.
    private static let snapThreshold: CGFloat = 8

    var body: some View {
        ZStack {
            centerGuides
            sticker
        }
        .frame(width: canvas.width, height: canvas.height)
        // Corrects a position persisted by an older build (which clamped only the
        // centre), and re-corrects whenever the sticker's own size changes — a
        // style switch from the tray, a stat toggled on, or the branded Minimal
        // pill growing. `reclamp()` writes only on a real change, so this is a
        // no-op at rest and can't fire mid-gesture (`natural` is constant then).
        .onChange(of: natural, initial: true) { _, _ in reclamp() }
        .onChange(of: canvas) { _, _ in reclamp() }
    }

    private var sticker: some View {
        RunStatsStickerView(input: input, config: config)
            .equatable()                       // MUST stay OUTSIDE the transforms
            // Probe sits OUTSIDE .equatable() but UNDER the transforms, so it
            // reports the NATURAL size and settles instead of firing per frame.
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: StickerNaturalSizeKey.self, value: geo.size)
                }
            )
            // INSIDE the transforms so the ring tracks the sticker exactly; its
            // stroke divides by liveScale to stay visually constant.
            .overlay { selectionRing }
            .scaleEffect(liveScale)
            .rotationEffect(liveRotation)
            // Generous, invisible hit margin so a shrunk-down sticker stays easy
            // to grab. After the transforms → a fixed screen-space margin.
            .padding(20)
            .contentShape(Rectangle())
            .gesture(manipulation)             // BEFORE .position → grab the sticker itself
            .position(liveCenter)
            .onPreferenceChange(StickerNaturalSizeKey.self) { natural = $0 }
    }

    /// Dashed outline while a gesture is in flight, so it's obvious the sticker —
    /// not the photo — is what's being moved. It sits inside the transforms (so it
    /// tracks scale and rotation) and divides its stroke and dash by `liveScale`,
    /// which cancels the scale back out and keeps the outline visually constant at
    /// any sticker size. Sized by the overlay itself, so it needs no measurement.
    @ViewBuilder
    private var selectionRing: some View {
        if isManipulating {
            let s = max(liveScale, 0.01)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.85),
                    style: StrokeStyle(lineWidth: 1.5 / s, dash: [5 / s, 4 / s])
                )
                .padding(-5)
                .allowsHitTesting(false)
        }
    }

    /// Thin centre lines that appear only while the sticker is locked to them.
    @ViewBuilder
    private var centerGuides: some View {
        if isManipulating {
            ZStack {
                if isSnappedX {
                    Rectangle()
                        .fill(MADTheme.Colors.madRed)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
                if isSnappedY {
                    Rectangle()
                        .fill(MADTheme.Colors.madRed)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
            }
            .opacity(0.9)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    // Live = committed ∘ transient, clamped IDENTICALLY to the `.onEnded` commit
    // so releasing never snaps the sticker to a different spot/size.
    private var liveScale: CGFloat {
        (scale * magnifyFactor).clamped(to: fittedScaleRange)
    }
    private var liveRotation: Angle { rotation + twist }

    /// `StickerConfig.scaleRange` narrowed to what actually fits the canvas, so a
    /// pinch can't grow the sticker past the photo's edges.
    private var fittedScaleRange: ClosedRange<CGFloat> {
        StickerBounds.scaleRange(natural: natural, canvas: canvas)
    }
    private var liveCenter: CGPoint {
        CGPoint(x: committedX(addingDrag: dragTranslation.width) * canvas.width,
                y: committedY(addingDrag: dragTranslation.height) * canvas.height)
    }

    /// Size-aware legal ranges, recomputed from the LIVE scale/rotation so an
    /// in-flight pinch or twist is bounded exactly the way the release will be.
    private var liveRanges: (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        StickerBounds.ranges(natural: natural, scale: liveScale,
                             rotation: liveRotation, canvas: canvas)
    }

    private var isSnappedX: Bool { committedX(addingDrag: dragTranslation.width) == 0.5 }
    private var isSnappedY: Bool { committedY(addingDrag: dragTranslation.height) == 0.5 }

    // Snap BEFORE the clamp, in both the live value and the commit, so the
    // sticker never jumps on release.
    private func committedX(addingDrag dx: CGFloat) -> CGFloat {
        let raw = pos.x + dx / max(canvas.width, 1)
        let snapped = abs(raw - 0.5) * canvas.width < Self.snapThreshold ? 0.5 : raw
        return snapped.clamped(to: liveRanges.x)
    }
    private func committedY(addingDrag dy: CGFloat) -> CGFloat {
        let raw = pos.y + dy / max(canvas.height, 1)
        let snapped = abs(raw - 0.5) * canvas.height < Self.snapThreshold ? 0.5 : raw
        return snapped.clamped(to: liveRanges.y)
    }

    /// Pull the committed scale and position back inside the current legal ranges.
    /// Only writes when something actually moves, so it's inert at rest.
    ///
    /// Scale first, then position — the legal position range depends on the size,
    /// so clamping in the other order would bound against a size that's about to
    /// change. This is also what repairs a transform persisted by an older build,
    /// which clamped the centre only and had no size cap at all.
    private func reclamp() {
        let fittedScale = scale.clamped(to: fittedScaleRange)
        if fittedScale != scale { scale = fittedScale }

        let r = StickerBounds.ranges(natural: natural, scale: fittedScale,
                                     rotation: rotation, canvas: canvas)
        let fixed = CGPoint(x: pos.x.clamped(to: r.x), y: pos.y.clamped(to: r.y))
        if fixed != pos { pos = fixed }
    }

    /// Fire once per snap-line entry, not once per frame spent on it. Reads the
    /// translation straight off the gesture value rather than `dragTranslation` —
    /// `updating` and `onChanged` fire for the same event with no guaranteed
    /// ordering, so the transient could still be a frame behind here.
    private func updateSnapHaptics(for translation: CGSize) {
        let x = committedX(addingDrag: translation.width) == 0.5
        let y = committedY(addingDrag: translation.height) == 0.5
        if x != snappedX { snappedX = x; if x { MADHaptics.tap() } }
        if y != snappedY { snappedY = y; if y { MADHaptics.tap() } }
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
            .updating($isManipulating) { _, state, _ in state = true }
            .onChanged { value in updateSnapHaptics(for: value.translation) }
            .onEnded { value in
                pos = CGPoint(x: committedX(addingDrag: value.translation.width),
                              y: committedY(addingDrag: value.translation.height))
                snappedX = false
                snappedY = false
            }
        let magnify = MagnifyGesture()
            .updating($magnifyFactor) { value, state, _ in state = value.magnification }
            .updating($isManipulating) { _, state, _ in state = true }
            .onEnded { value in
                scale = (scale * value.magnification).clamped(to: fittedScaleRange)
                // Growing while parked against an edge would otherwise leave the
                // committed centre outside the (now tighter) legal range.
                reclamp()
            }
        let rotate = RotateGesture()
            .updating($twist) { value, state, _ in state = value.rotation }
            .updating($isManipulating) { _, state, _ in state = true }
            .onEnded { value in
                rotation = rotation + value.rotation
                reclamp()
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

    /// The composer's second screen. Edit is the stack ROOT, so this enum only
    /// needs the one case: `path` is `[]` on edit and `[.share]` on share.
    private enum ComposerStep: Hashable { case share }

    @StateObject private var vm: PostComposerViewModel
    @StateObject private var friendService = FriendService()
    @State private var showCamera = false
    // Library import of a photo captured DURING this walk/run (window-filtered
    // for authenticity, same as the post-run prompt). Its cover rides the
    // `canvasSection` node — a third cover on the ZStack or the background Color
    // (which already own the camera + terms covers) would silently drop one.
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
    /// Guards against silently destroying a composed draft on Cancel.
    @State private var showDiscardConfirm = false
    /// Empty on the edit step, `[.share]` on the share step.
    @State private var path: [ComposerStep] = []
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
        NavigationStack(path: $path) {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: MADTheme.Spacing.lg) {
                        canvasSection
                            // Distinct node from the NavigationStack (terms gate),
                            // the ZStack (camera) and the ScrollView (discard
                            // dialog) — see showLibraryImport.
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
                            StickerTrayView(
                                input: vm.stats,
                                config: $vm.config,
                                isEnabled: $vm.stickerEnabled,
                                isTransformed: vm.isStickerTransformed
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    vm.resetStickerPlacement()
                                }
                            }
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
                // The ScrollView's own presentation slot — the terms gate that used
                // to live here moved up to the NavigationStack.
                .confirmationDialog("Discard this post?", isPresented: $showDiscardConfirm,
                                    titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { onFinished(.cancelled); dismiss() }
                    Button("Keep editing", role: .cancel) { }
                } message: {
                    Text("Your photo and caption won't be saved.")
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ComposerStep.self) { _ in
                PostShareStepView(
                    vm: vm,
                    friendService: friendService,
                    shareEnabled: vm.canPublish && termsState == .accepted,
                    onShare: share,
                    onEditMedia: { if !path.isEmpty { path.removeLast() } }
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Disabled while publishing: publish() has no cancellation
                    // hook, so a Cancel racing an in-flight upload would fire
                    // onFinished twice with contradictory outcomes (the
                    // post-run prompt would auto-post the route card AND the
                    // photo post would land server-side).
                    Button(action: cancelTapped) {
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
                    Button("Next", action: goToShareStep)
                        .fontWeight(.semibold)
                        .foregroundColor(vm.pickedImage != nil
                            ? MADTheme.Colors.madRed : .white.opacity(0.3))
                        .disabled(vm.pickedImage == nil)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .fullScreenCover(isPresented: $showCamera) {
                MADCameraView(image: $vm.pickedImage)
            }
            // A stale composite must never survive a trip back to the editor.
            .onChange(of: path) { _, newPath in
                if newPath.isEmpty { vm.previewComposite = nil }
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
        // The guidelines gate hangs off the NavigationStack ITSELF, not the root
        // content. Share can trigger it from the pushed share step, and a cover
        // presented from a view that's been navigated away from is unreliable —
        // the stack is the one node that's current on both steps. It's also a
        // node of its own, which matters: the ZStack owns the camera cover, the
        // ScrollView owns the discard dialog, and the canvas owns the library
        // import. Two presentations on one node silently drop one.
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

    // MARK: - Step actions

    /// Advance to the share step, baking the thumbnail from the CURRENT canvas.
    /// Guarded on `canvasSize` so a composite is never rendered before the canvas
    /// has been laid out (which would produce a differently-scaled sticker than
    /// the one that ultimately uploads).
    private func goToShareStep() {
        guard vm.pickedImage != nil, vm.canvasSize.width > 0 else { return }
        MADHaptics.tap()
        vm.previewComposite = vm.flatten()
        path.append(.share)
    }

    /// The one terminal action. Lives HERE, never in `PostShareStepView`: inside a
    /// `navigationDestination`, `dismiss()` pops the push instead of dismissing the
    /// composer, so publishing from there would leave the user on the edit step with
    /// a post already live.
    private func share() {
        switch termsState {
        case .accepted:
            Task {
                let ok = await vm.publish()
                if ok, let dest = vm.destination {
                    onFinished(.published(toFeed: dest.toFeed, toStory: dest.toStory))
                    dismiss()
                }
            }
        case .needsAcceptance:
            // Not allowed to post yet — the button routes to the guidelines
            // instead of a dead upload.
            presentGateIfNeeded()
        case .unknown:
            // Still resolving; the gate auto-presents if the answer comes back
            // unaccepted.
            break
        }
    }

    /// Cancel with a draft asks first. `backNavigation` deliberately skips the
    /// dialog: that button reads "‹ Back", a navigational affordance, and it returns
    /// to the post-run prompt which still holds the mid-run snaps and re-offers them
    /// — nothing is actually lost. "Cancel" was renamed to "Back" on that path
    /// precisely because people feared losing photos; a destructive dialog there
    /// would undo that fix.
    private func cancelTapped() {
        if backNavigation || !vm.hasDraft {
            onFinished(.cancelled)
            dismiss()
        } else {
            showDiscardConfirm = true
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
                        changePhotoControl.padding(10)
                    }
                    // Keep a copy exactly as composed — stats sticker baked
                    // in (the camera already saved the RAW shot at capture).
                    .overlay(alignment: .topLeading) {
                        Button {
                            guard let flat = vm.flatten() else { return }
                            PhotoRollSaver.save(flat)
                            MADHaptics.success()
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

    /// Swapping the photo used to mean "Retake" and nothing else — the library
    /// option vanished the moment a photo existed, so a user who'd picked the wrong
    /// mid-run snap had to go through the camera to get back. A `Menu` offers both.
    ///
    /// `Menu` rides UIKit's context-menu machinery rather than the sheet/cover
    /// presentation slot, so it costs no cover node (see the cover comments above).
    @ViewBuilder
    private var changePhotoControl: some View {
        if vm.stats.workoutId != nil {
            Menu {
                Button { requestCamera() } label: {
                    Label("Take a new photo", systemImage: "camera.fill")
                }
                Button { showLibraryImport = true } label: {
                    Label("Choose from this walk or run", systemImage: "photo.on.rectangle")
                }
            } label: {
                changePhotoPill
            }
        } else {
            Button { requestCamera() } label: { changePhotoPill }
        }
    }

    private var changePhotoPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "camera.fill")
                .font(.system(size: 12, weight: .bold))
            Text("Change")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(.black.opacity(0.5)))
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
