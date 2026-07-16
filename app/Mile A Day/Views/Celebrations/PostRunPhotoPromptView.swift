import SwiftUI

/// BeReal-style prompt shown as the finale after finishing today's mile: snap a
/// photo of your run, or skip. Either way the run becomes one feed item — taking
/// a photo publishes it with the photo; skipping publishes the route map (or a
/// stats card) via `RunPostService`. Friends get one merged notification ~10 min
/// later (handled server-side), so there's a window to add a photo.
///
/// If the user snapped photos MID-run (camera button on the tracking screen),
/// those lead here: pick one, take a fresh shot instead, or skip. The stash is
/// cleared once this prompt resolves, whichever path is taken.
struct PostRunPhotoPromptView: View {
    let workoutId: String
    let workoutType: String

    @ObservedObject private var manager = CelebrationManager.shared
    @ObservedObject private var freshWindow = FreshPostWindowManager.shared
    @State private var appeared = false
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
    @State private var pendingUseImage: UIImage?
    /// Import a photo taken on this walk/run from the library (time-windowed).
    @State private var showLibraryImport = false
    @State private var importError: String?

    private var isWalk: Bool { workoutType == "walking" }
    /// App-wide type language: walks blue, runs red.
    private var accent: Color { MADTheme.workoutColor(workoutType) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.06, blue: 0.10), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                // Snap review rides on the gradient node — the composer cover
                // owns the ZStack, and two covers on one node drop one.
                .fullScreenCover(isPresented: $showGallery, onDismiss: {
                    // Refresh after deletions; a "Use this photo" choice made
                    // inside the gallery presents the composer only now, after
                    // this cover is fully gone (same-transaction covers race).
                    midRunSnaps = MidRunPhotoStash.entries()
                    if let image = pendingUseImage {
                        pendingUseImage = nil
                        composerLaunch = ComposerLaunch(image: image)
                    }
                }) {
                    SnapGalleryView(
                        title: "Your snaps",
                        initialIndex: galleryStartIndex,
                        onUse: { pendingUseImage = $0.image },
                        onStashChanged: { midRunSnaps = MidRunPhotoStash.entries() }
                    )
                }

            VStack(spacing: MADTheme.Spacing.lg) {
                Spacer()

                if midRunSnaps.isEmpty {
                    cameraHero
                } else {
                    midRunSnapStrip
                }

                // Countdown pill — the fresh window is open for this run. Purely
                // an in-the-moment nudge; posting stays available after it ends.
                if freshWindow.isOpen(forWorkout: workoutId) {
                    countdownPill
                        .opacity(appeared ? 1 : 0)
                }

                VStack(spacing: 8) {
                    Text(headline)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text(subheadline)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, MADTheme.Spacing.xl)
                }
                .opacity(appeared ? 1 : 0)

                Spacer()

                VStack(spacing: MADTheme.Spacing.sm) {
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
                            Text("Choose from this \(isWalk ? "walk" : "run")")
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

                    Button { skip() } label: {
                        Text("Skip")
                            .font(MADTheme.Typography.headline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, MADTheme.Spacing.lg)
                .padding(.bottom, MADTheme.Spacing.xl)
            }
            // Import cover rides the VStack node — the gradient owns the
            // gallery cover and the ZStack owns the composer cover; a third
            // cover on the ZStack would silently drop one (.claude/rules/ios.md).
            .fullScreenCover(isPresented: $showLibraryImport, onDismiss: {
                // Launch the composer only AFTER this cover is gone — a second
                // cover in the same dismiss transaction races and drops.
                if let image = pendingUseImage {
                    pendingUseImage = nil
                    composerLaunch = ComposerLaunch(image: image)
                }
            }) {
                WorkoutPhotoImportPicker(
                    window: importWindow,
                    activityNoun: isWalk ? "walk" : "run"
                ) { result in
                    handleImportResult(result)
                    showLibraryImport = false
                }
            }
        }
        .onAppear {
            midRunSnaps = MidRunPhotoStash.entries()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appeared = true }
        }
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
                stats: RunPostService.todayStats(workoutId: workoutId),
                // A chosen mid-run snap goes straight onto the canvas; only a
                // fresh capture launches the camera.
                autoOpenCamera: launch.image == nil,
                initialImage: launch.image,
                // Leaving returns to this prompt with the snaps intact —
                // "‹ Back", not "Cancel", so nobody fears losing photos.
                backNavigation: true
            ) { outcome in
                composerLaunch = nil
                switch outcome {
                case .cancelled where !midRunSnaps.isEmpty:
                    // Backed out with snaps still to consider — return to this
                    // prompt so they can pick a different one or Skip. Nothing
                    // is finalized yet.
                    return
                case .published(let toFeed, _) where toFeed:
                    // The photo went to the feed, so it IS the feed item.
                    didAct = true
                case .published, .cancelled:
                    // Photo to a story only, or cancelled with no snaps to
                    // reconsider — the feed still gets the run's route/stats card.
                    didAct = true
                    Task { await RunPostService.autoPostMile(workoutId: workoutId, workoutType: workoutType) }
                }
                finish()
            }
        }
    }

    private var headline: String {
        if midRunSnaps.isEmpty {
            return isWalk ? "Capture your walk" : "Capture your run"
        }
        return "Use a photo from your \(isWalk ? "walk" : "run")?"
    }

    private var subheadline: String {
        if midRunSnaps.isEmpty {
            return "Snap a photo for your story — it disappears in 24 hours. Your run's route and stats post to the feed either way."
        }
        let count = midRunSnaps.count
        return count == 1
            ? "You snapped a photo out there — tap it to share it, or take a fresh one."
            : "You snapped \(count) photos out there — tap your favorite to share it, or take a fresh one."
    }

    // MARK: - Fresh-window countdown

    /// Self-ticking countdown for the run's 10-minute fresh window. Uses the
    /// native `Text(timerInterval:)` (no manual timer) so it stays cheap.
    private var countdownPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
            Text("Post now — fresh for")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
        .background(Capsule().fill(accent.opacity(0.9)))
        .shadow(color: accent.opacity(0.4), radius: 8, y: 2)
    }

    // MARK: - Hero (no mid-run snaps)

    private var cameraHero: some View {
        ZStack {
            Circle().fill(accent.opacity(0.18)).frame(width: 150, height: 150)
            Circle().strokeBorder(accent.opacity(0.4), lineWidth: 1).frame(width: 150, height: 150)
            Image(systemName: "camera.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.white, accent],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: accent.opacity(0.5), radius: 16)
        }
        .scaleEffect(appeared ? 1 : 0.6)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Mid-run snaps

    /// The run's snaps as big tappable cards. One or two fit centered on any
    /// screen; three-plus scroll horizontally so five never overflow.
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
                HStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(Array(midRunSnaps.enumerated()), id: \.element.id) { index, entry in
                        snapCard(index: index, entry: entry)
                    }
                }
                .padding(.horizontal, MADTheme.Spacing.lg)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// One snap gets a big hero card; multiples shrink so two still sit side
    /// by side on the smallest screens. Always 4:5, like the post.
    private var snapCardSize: CGSize {
        midRunSnaps.count == 1
            ? CGSize(width: 216, height: 270)
            : CGSize(width: 150, height: 187)
    }

    private func snapCard(index: Int, entry: MidRunPhotoStash.Entry) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            composerLaunch = ComposerLaunch(image: entry.image)
        } label: {
            Image(uiImage: entry.image)
                .resizable()
                .scaledToFill()
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
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        }
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.7).delay(Double(index) * 0.06),
            value: appeared
        )
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
            pendingUseImage = image
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
}
