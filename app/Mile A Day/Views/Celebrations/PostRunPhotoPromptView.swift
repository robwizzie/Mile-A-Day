import SwiftUI
import CoreLocation

/// The finale after a walk or run: "make it a post".
///
/// The hero is a preview of what gets posted — the walk's real route card
/// with an empty photo frame clipped onto it — because the thing people
/// didn't get is that a photo JOINS the walk's route and stats as one post,
/// rather than being something separate. Cards fan in and the frame floats;
/// on the Fun dashboard the user's own Flamey stands by.
///
/// Mechanics are unchanged: taking a photo publishes it through the composer;
/// skipping hands the walk to `RunPostService.autoPostMile`, which follows the
/// "Post my route when I skip" setting. Snaps taken MID-run lead the screen
/// when there are any; the stash is cleared once this prompt resolves,
/// whichever path is taken.
struct PostRunPhotoPromptView: View {
    let workoutId: String
    let workoutType: String

    @ObservedObject private var manager = CelebrationManager.shared
    @ObservedObject private var freshWindow = FreshPostWindowManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    /// Drives the idle float/pulse. Started on the NEXT turn after appear and
    /// reset without animation on disappear (a `repeatForever` attached to the
    /// first commit leaks into every later layout change — ios.md).
    @State private var floating = false
    @State private var didAct = false
    /// Photos captured during the run via the tracking screen's camera button.
    @State private var midRunSnaps: [MidRunPhotoStash.Entry] = []
    /// Composer launch request — carries the tapped snap (nil = fresh camera).
    /// Item-based so the cover is always built from THIS value; the old
    /// isPresented + separate-selection pair could build the composer with a
    /// stale nil snap and wrongly launch the live camera.
    @State private var composerLaunch: ComposerLaunch?
    /// Full-screen review of the run's snaps (save / delete / pick one).
    @State private var showGallery = false
    @State private var galleryStartIndex = 0
    /// "Use this photo" chosen INSIDE the gallery — the composer presents
    /// after the gallery cover fully dismisses (two covers in one transaction
    /// race and drop, see .claude/rules/ios.md).
    @State private var pendingUse: ComposerLaunch?
    /// Import a photo taken on this walk/run from the library (time-windowed).
    @State private var showLibraryImport = false
    @State private var importError: String?

    /// The walk's own stats, resolved once — the same figures the card bakes.
    @State private var stats: RunStatsInput?
    /// The walk's real GPS trace for the preview card, when friends will
    /// actually get one (not Stealth, route maps on).
    @State private var routeCoords: [CLLocationCoordinate2D]?

    private var isWalk: Bool { workoutType == "walking" }
    private var noun: String { isWalk ? "walk" : "run" }
    /// App-wide type language: walks blue, runs red.
    private var accent: Color { MADTheme.workoutColor(workoutType) }

    /// May a fresh shot still be taken for THIS run? Scoped to the workout so a
    /// later walk's window can't quietly re-offer the camera on an old prompt.
    private var cameraOpen: Bool { freshWindow.isCameraOpen(forWorkout: workoutId) }

    /// Fun dashboard only — nil on Modern, where Flamey doesn't exist.
    private var flameyLook: FlameyLook? { FlameyFacts.look(mood: .done, detail: .compact) }

    /// Does skipping still put a route/stats card on the feed? Read so the
    /// note under Skip can't promise something the setting has turned off —
    /// `RunPostService.autoPostMile` is what enforces it.
    private var postsCardOnSkip: Bool {
        NotificationPreferences.load().autoPostWithoutPhoto
    }

    private static let cardSize = CGSize(width: 140, height: 175)

    var body: some View {
        ZStack {
            backdrop
                // Snap review rides on the backdrop node — the composer
                // cover owns the ZStack, and two covers on one node drop one.
                .fullScreenCover(isPresented: $showGallery, onDismiss: {
                    // Refresh after deletions; a "Use this photo" choice made
                    // inside the gallery presents the composer only now, after
                    // this cover is fully gone (same-transaction covers race).
                    midRunSnaps = MidRunPhotoStash.entries()
                    if let launch = pendingUse {
                        pendingUse = nil
                        composerLaunch = launch
                    }
                }) {
                    SnapGalleryView(
                        title: "Your snaps",
                        initialIndex: galleryStartIndex,
                        onUse: { pendingUse = ComposerLaunch(entry: $0) },
                        onStashChanged: { midRunSnaps = MidRunPhotoStash.entries() }
                    )
                }

            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    header
                        .padding(.top, MADTheme.Spacing.xl)

                    if midRunSnaps.isEmpty {
                        previewStack
                    } else {
                        midRunSnapStrip
                    }

                    // The CAMERA is open for this run. A real deadline for
                    // shooting, not for sharing — the caption says so, so the
                    // timer reads as an invitation rather than a threat.
                    if cameraOpen {
                        countdownPill
                            .opacity(appeared ? 1 : 0)
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.lg)
                .padding(.bottom, MADTheme.Spacing.md)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
            // Import cover rides the ScrollView node — the backdrop owns the
            // gallery cover and the ZStack owns the composer cover; a third
            // cover on the ZStack would silently drop one (.claude/rules/ios.md).
            .fullScreenCover(isPresented: $showLibraryImport, onDismiss: {
                // Launch the composer only AFTER this cover is gone — a second
                // cover in the same dismiss transaction races and drops.
                if let launch = pendingUse {
                    pendingUse = nil
                    composerLaunch = launch
                }
            }) {
                WorkoutPhotoImportPicker(
                    window: importWindow,
                    activityNoun: noun
                ) { result in
                    handleImportResult(result)
                    showLibraryImport = false
                }
            }
        }
        // Once they've reached for the camera, the library or a snap, this
        // prompt is theirs: nothing that arrives later may pull it out from
        // under them (CelebrationManager only preempts an untouched prompt).
        .onChange(of: composerLaunch != nil) { _, open in if open { manager.photoPromptEngaged = true } }
        .onChange(of: showGallery) { _, open in if open { manager.photoPromptEngaged = true } }
        .onChange(of: showLibraryImport) { _, open in if open { manager.photoPromptEngaged = true } }
        .onAppear {
            midRunSnaps = MidRunPhotoStash.entries()
            if stats == nil { stats = RunPostService.todayStats(workoutId: workoutId) }
            // This prompt is the LAST celebration in the queue, so a slow walk
            // through goal/badges/leaderboard — or a backgrounded app — can
            // easily outlast the 10-minute camera window. That no longer means
            // there's nothing to offer: the walk's own photos are still
            // postable, so the screen stays and swaps its primary button (see
            // `cameraOpen`). Only a day with no qualifying workout at all takes
            // the skip path, where the walk still gets its card per the
            // setting (an `is_auto` post, exempt from both tiers). Deferred a
            // tick because resolving a celebration from inside its own
            // onAppear mutates the manager mid-update.
            guard freshWindow.canPostToday else {
                DispatchQueue.main.async { skip() }
                return
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { appeared = true }
            guard !reduceMotion else { return }
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    floating = true
                }
            }
        }
        .onDisappear {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { floating = false }
        }
        .task { await loadRoutePreview() }
        .alert("Couldn't add that photo", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .fullScreenCover(item: $composerLaunch) { launch in
            PostComposerView(
                stats: stats ?? RunPostService.todayStats(workoutId: workoutId),
                // A chosen mid-run snap goes straight onto the canvas; only a
                // fresh capture launches the camera.
                autoOpenCamera: launch.image == nil,
                initialImage: launch.image,
                initialSecondary: launch.secondary,
                initialPrimaryWasFront: launch.primaryWasFront,
                // Leaving returns to this prompt with the snaps intact —
                // "‹ Back", not "Cancel", so nobody fears losing photos.
                backNavigation: true
            ) { outcome in
                composerLaunch = nil
                switch outcome {
                case .cancelled:
                    // Backed out — of the camera, the canvas or the share step.
                    // Nothing is finalized: this screen is still the decision,
                    // so they land back here to try again, pick another snap,
                    // or skip. (It used to post the route card and close when
                    // there were no snaps, so a camera opened by mistake and
                    // closed again had already published the walk.)
                    return
                case .published(let toFeed, _):
                    didAct = true
                    if !toFeed {
                        // Photo to a story only — the feed still gets the
                        // walk's route/stats card (per the setting).
                        Task {
                            await RunPostService.autoPostMile(workoutId: workoutId, workoutType: workoutType)
                        }
                    }
                    finish()
                }
            }
        }
    }

    // MARK: - Background

    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.05, blue: 0.10), .black],
                           startPoint: .top, endPoint: .bottom)
            // A soft glow in the activity colour behind the hero.
            RadialGradient(colors: [accent.opacity(0.35), .clear],
                           center: .init(x: 0.5, y: 0.28),
                           startRadius: 10, endRadius: 320)
                .scaleEffect(floating ? 1.06 : 0.96)
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: isWalk ? "figure.walk" : "figure.run")
                    .font(.system(size: 11, weight: .heavy))
                Text(eyebrow)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(accent.opacity(0.85)))
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)
            .accessibilityElement(children: .combine)

            Text(headline)
                .madFont(size: 28, weight: .black, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text(subheadline)
                .madFont(size: 14, weight: .medium, design: .rounded, maxScale: 1.4)
                .foregroundColor(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(appeared ? 1 : 0)
    }

    private var eyebrow: String {
        let done = isWalk ? "WALK DONE" : "RUN DONE"
        if let streak = stats?.streak, streak > 0 { return "\(done) · DAY \(streak)" }
        return done
    }

    private var headline: String {
        if !midRunSnaps.isEmpty { return "Pick your shot" }
        return cameraOpen ? "Make it a post" : "Add a photo from your \(noun)"
    }

    private var subheadline: String {
        if !midRunSnaps.isEmpty {
            let lead = midRunSnaps.count == 1
                ? "You snapped a photo out there."
                : "You snapped \(midRunSnaps.count) photos out there."
            return "\(lead) Tap one to add it to your post."
        }
        return cameraOpen
            ? "Add a photo and it joins your route and stats in one post."
            : "Any photo you took on this \(noun) can still go up today."
    }

    // MARK: - Hero: a preview of the post

    /// The walk's route card at the back, the photo frame clipped on in
    /// front: "your photo goes HERE, on THIS". Fanned apart on appear.
    private var previewStack: some View {
        let size = Self.cardSize
        return ZStack {
            walkCard
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) { cardTag("ROUTE & STATS", icon: "map.fill") }
                .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
                .rotationEffect(.degrees(appeared ? -7 : 0))
                .offset(x: appeared ? -68 : 0, y: appeared ? 6 : 0)

            photoFrame
                .frame(width: size.width, height: size.height)
                .shadow(color: accent.opacity(0.35), radius: 18, y: 8)
                .rotationEffect(.degrees(appeared ? 6 : 0))
                .offset(x: appeared ? 68 : 0, y: (appeared ? -6 : 0) + (floating ? -4 : 2))

            // The "+" that says these two become one.
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .black))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(accent))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 3))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                .scaleEffect(appeared ? 1 : 0.2)
                .offset(y: 4)
                .accessibilityHidden(true)

            if let look = flameyLook {
                FlameyDressedFigure(look: look, health: .healthy, size: 64, scale: 1, mood: .done)
                    .frame(width: 64, height: 64)
                    .offset(x: appeared ? 126 : 60, y: 84 + (floating ? -3 : 0))
                    .opacity(appeared ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: size.height + 30)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: your photo joins your \(noun)'s route and stats as one post")
    }

    /// The walk side of the post: its real route art with the feed's stats
    /// band when friends will get a route, else a stats card.
    @ViewBuilder
    private var walkCard: some View {
        if let coords = routeCoords, coords.count >= 2, let stats {
            RouteArtView(
                coordinates: coords,
                routeColor: accent,
                authorAvatar: RouteArtAvatar(
                    name: UserManager.shared.currentUser.name,
                    imageURL: UserManager.shared.currentUser.profileImageUrl
                ),
                showsMileMarkers: false
            )
            .overlay {
                // Same band as the feed's route slide; it lays out at the
                // baked card's design width, so scaling by width reproduces it.
                GeometryReader { geo in
                    RouteStatsOverlayView(stats: stats, workoutType: workoutType)
                        .scaleEffect(geo.size.width / RunStatsCardView.designSize.width,
                                     anchor: .topLeading)
                }
                .allowsHitTesting(false)
            }
        } else {
            statsCard
        }
    }

    /// Routeless walks (and the moment before the route loads).
    private var statsCard: some View {
        ZStack {
            LinearGradient(colors: [accent, accent.opacity(0.35), Color.black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 4) {
                Image(systemName: isWalk ? "figure.walk" : "figure.run")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.bottom, 4)
                Text((stats?.distance ?? 0).distanceText)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundColor(.white)
                Text(DistanceUnits.current.abbreviation.uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.75))
                if let detail = statsDetailLine {
                    Text(detail)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 6)
                }
            }
            .padding(12)
        }
    }

    /// "12:41 /mi · 13:05" — pace in the display unit, then time.
    private var statsDetailLine: String? {
        guard let stats else { return nil }
        var parts: [String] = []
        if let pace = stats.paceSecondsPerMile, pace > 0 {
            parts.append("\(RunStatsStickerView.paceText(pace.pacePerDisplayUnit)) /\(DistanceUnits.current.abbreviation)")
        }
        if let d = stats.durationSeconds, d > 0 {
            parts.append(RunStatsStickerView.durationText(d))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The photo side: an empty frame that invites the tap.
    private var photoFrame: some View {
        Button {
            MADHaptics.action()
            openPrimaryAction()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                                         startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.75),
                                  style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(accent.opacity(0.6), lineWidth: 2)
                            .frame(width: 54, height: 54)
                            .scaleEffect(floating ? 1.25 : 1)
                            .opacity(floating ? 0 : 0.9)
                        Circle()
                            .fill(accent)
                            .frame(width: 46, height: 46)
                        Image(systemName: cameraOpen ? "camera.fill" : "photo.on.rectangle.angled")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("Your photo\nhere")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cameraOpen ? "Take a photo" : "Choose a photo from this \(noun)")
    }

    private func cardTag(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 8, weight: .heavy))
            Text(text)
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundColor(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .padding(8)
    }

    // MARK: - Actions

    private var actionBar: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            if cameraOpen {
                Button {
                    composerLaunch = ComposerLaunch(image: nil)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text(midRunSnaps.isEmpty ? "Take a photo" : "Take a new photo")
                    }
                    .frame(maxWidth: .infinity)
                }
                .madPrimaryButton(fullWidth: true)

                // Use a photo captured on this walk with the system camera.
                Button {
                    showLibraryImport = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Choose from this \(noun)")
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
            } else {
                Button {
                    showLibraryImport = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                        Text("Choose from this \(noun)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .madPrimaryButton(fullWidth: true)
            }

            Button { skip() } label: {
                VStack(spacing: 2) {
                    Text("Skip")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                    // Skipping still posts the walk when the setting says so —
                    // said quietly here so it's never a surprise later.
                    if postsCardOnSkip {
                        Text("Your route and stats will still post")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MADTheme.Spacing.lg)
        .padding(.top, MADTheme.Spacing.md)
        .padding(.bottom, MADTheme.Spacing.sm)
        .background(
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.92), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
        .opacity(appeared ? 1 : 0)
    }

    /// The photo frame does what the primary button does.
    private func openPrimaryAction() {
        if cameraOpen {
            composerLaunch = ComposerLaunch(image: nil)
        } else {
            showLibraryImport = true
        }
    }

    // MARK: - Fresh-window countdown

    /// Self-ticking countdown for the run's 10-minute CAMERA window. Uses the
    /// native `Text(timerInterval:)` (no manual timer) so it stays cheap.
    ///
    /// The caption under it is load-bearing, not decoration: a bare countdown
    /// on a sharing screen reads as "post now or lose it", which is exactly the
    /// pressure the all-day library tier exists to remove.
    private var countdownPill: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Camera closes in")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
                Text(
                    timerInterval: (freshWindow.windowOpenedAt ?? Date())...freshWindow.windowEndDate,
                    countsDown: true
                )
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .overlay(Capsule().strokeBorder(accent.opacity(0.7), lineWidth: 1))

            Text("Photos from this \(noun) stay postable all day.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Mid-run snaps

    /// The run's snaps as big tappable cards. One or two fit centered on any
    /// screen; three-plus scroll horizontally.
    ///
    /// LAZY, now that nothing caps how many there can be: an eager `HStack`
    /// builds — and draws — every card at once, and a thirty-photo walk
    /// would decode thirty images to show three.
    @ViewBuilder
    private var midRunSnapStrip: some View {
        if midRunSnaps.count <= 2 {
            HStack(spacing: MADTheme.Spacing.sm) {
                ForEach(Array(midRunSnaps.enumerated()), id: \.element.id) { index, entry in
                    snapCard(index: index, entry: entry)
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(Array(midRunSnaps.enumerated()), id: \.element.id) { index, entry in
                        snapCard(index: index, entry: entry)
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.lg)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Bleed past the content's gutter so cards scroll edge to edge.
            .padding(.horizontal, -MADTheme.Spacing.lg)
        }
    }

    /// One snap gets a big hero card; multiples shrink so two still sit side
    /// by side on the smallest screens. Always 4:5, like the post.
    private var snapCardSize: CGSize {
        midRunSnaps.count == 1
            ? CGSize(width: 200, height: 250)
            : CGSize(width: 150, height: 187)
    }

    private func snapCard(index: Int, entry: MidRunPhotoStash.Entry) -> some View {
        Button {
            MADHaptics.action()
            composerLaunch = ComposerLaunch(entry: entry)
        } label: {
            // Drawn as ONE photo, second frame inset — a front-and-back snap
            // that looks like an ordinary picture until it's published is a
            // surprise on the card, not a feature.
            DualPhotoFill(big: entry.image, small: entry.secondary)
                .frame(width: snapCardSize.width, height: snapCardSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )
                // An unmissable "this is the button" label — the old corner
                // arrow read as decoration and people hunted for a tap target.
                .overlay(alignment: .bottom) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(midRunSnaps.count == 1 ? "Use this photo" : "Use photo")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(accent))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    .padding(.bottom, 10)
                }
                .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        // Peek before you post: full-screen review with save/delete. A
        // SIBLING overlay (not nested in the card button's label) so its
        // taps can never double-fire the use-photo action.
        .overlay(alignment: .topTrailing) {
            Button {
                MADHaptics.tap()
                galleryStartIndex = index
                showGallery = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("View full screen")
        }
        .rotationEffect(.degrees(appeared ? (index.isMultiple(of: 2) ? -2 : 2) : 0))
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.7).delay(Double(index) * 0.06),
            value: appeared
        )
    }

    // MARK: - Route preview

    /// The route friends will actually get — none for a Stealth walk (the
    /// server never stores one) or when route maps are switched off, so the
    /// preview can't promise a map the post won't have.
    private func loadRoutePreview() async {
        guard routeCoords == nil,
              NotificationPreferences.load().shareRouteMaps,
              let workout = HealthKitManager.shared.todaysWorkouts
                .first(where: { $0.uuid.uuidString == workoutId }),
              !StealthModeStore.shared.isStealth(workout) else { return }
        let locations = await HealthKitManager.shared.fetchAllRouteLocations(for: workout)
        guard locations.count >= 2 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            routeCoords = locations.map(\.coordinate)
        }
    }

    // MARK: - Library import (photo taken on this walk/run)

    /// Accepted capture-time window from the workout's own start/end (HealthKit),
    /// with grace on both ends: a shot at the trailhead just before starting,
    /// or right after finishing before this prompt appeared, both count.
    ///
    /// When the just-finished workout hasn't synced into `todaysWorkouts` yet
    /// (async fetch / Watch lag), we do NOT fall back to the whole day — that
    /// would let an unrelated earlier photo pass. Instead we bound to a
    /// generous recent window (a daily mile is minutes; even a long hike fits
    /// 3h), so authenticity holds even without the exact workout.
    private var importWindow: ClosedRange<Date> {
        let now = Date()
        guard let workout = HealthKitManager.shared.todaysWorkouts
            .first(where: { $0.uuid.uuidString == workoutId }) else {
            return now.addingTimeInterval(-3 * 60 * 60)...now.addingTimeInterval(2 * 60)
        }
        let start = workout.startDate.addingTimeInterval(-5 * 60)
        let end = workout.endDate.addingTimeInterval(30 * 60)
        return start...max(start, end)
    }

    private func handleImportResult(_ result: WorkoutPhotoImportResult) {
        switch result {
        case .accepted(let image):
            // Deferred to the import cover's onDismiss (composer is a second
            // cover — presenting it now would race this one's dismissal).
            pendingUse = ComposerLaunch(image: image)
        case .failed:
            importError = "Couldn't load that photo. Try another one."
        case .cancelled:
            break
        }
    }

    private func skip() {
        guard !didAct else { return }
        didAct = true
        Task { await RunPostService.autoPostMile(workoutId: workoutId, workoutType: workoutType) }
        finish()
    }

    private func finish() {
        // The run's snaps are one-shot offers: whatever wasn't chosen is gone
        // once the prompt resolves (posted, skipped, or composer dismissed).
        MidRunPhotoStash.clear()
        manager.dismissCurrentCelebration()
    }
}

/// Identifiable wrapper for launching the composer, so the fullScreenCover is
/// built from the exact tapped value instead of separately-tracked state.
private struct ComposerLaunch: Identifiable {
    let id = UUID()
    /// The chosen mid-run snap; nil means open the live camera for a fresh shot.
    let image: UIImage?
    /// The other lens, when the chosen snap was a FRONT & BACK press. Carried
    /// all the way to the composer or the pair is lost between the gallery
    /// and the canvas — the post would publish whichever frame was showing
    /// and silently drop the other.
    let secondary: UIImage?
    let primaryWasFront: Bool

    init(image: UIImage?) {
        self.image = image
        self.secondary = nil
        self.primaryWasFront = false
    }

    /// Reads the ORIGINAL off disk, not the entry's display copy: `entries()`
    /// decodes at a thumbnail size so an uncapped walk's worth of snaps can
    /// be listed, and that is exactly the resolution a post must not inherit.
    /// Falls back to what's in hand if the file can't be re-read.
    init(entry: MidRunPhotoStash.Entry) {
        let full = MidRunPhotoStash.fullImage(for: entry)
        self.image = full?.primary ?? entry.image
        self.secondary = full?.secondary ?? entry.secondary
        self.primaryWasFront = entry.primaryWasFront
    }
}
