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
    @State private var appeared = false
    @State private var didAct = false
    /// Photos captured during the run via the tracking screen's camera button.
    @State private var midRunSnaps: [UIImage] = []
    /// Composer launch request — carries the tapped snap (nil = fresh camera).
    /// Item-based so the cover is always built from THIS value; the old
    /// isPresented + separate-selection pair could build the composer with a
    /// stale nil snap and wrongly launch the live camera.
    @State private var composerLaunch: ComposerLaunch?

    private var isWalk: Bool { workoutType == "walking" }
    private var accent: Color { isWalk ? .blue : MADTheme.Colors.madRed }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.06, blue: 0.10), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: MADTheme.Spacing.lg) {
                Spacer()

                if midRunSnaps.isEmpty {
                    cameraHero
                } else {
                    midRunSnapStrip
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
        }
        .onAppear {
            midRunSnaps = MidRunPhotoStash.loadAll()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appeared = true }
        }
        .fullScreenCover(item: $composerLaunch) { launch in
            PostComposerView(
                stats: RunPostService.todayStats(workoutId: workoutId),
                destination: .story,
                // A chosen mid-run snap goes straight onto the canvas; only a
                // fresh capture launches the camera.
                autoOpenCamera: launch.image == nil,
                initialImage: launch.image
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
                ForEach(Array(midRunSnaps.enumerated()), id: \.offset) { index, snap in
                    snapCard(index: index, snap: snap)
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(Array(midRunSnaps.enumerated()), id: \.offset) { index, snap in
                        snapCard(index: index, snap: snap)
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

    private func snapCard(index: Int, snap: UIImage) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            composerLaunch = ComposerLaunch(image: snap)
        } label: {
            Image(uiImage: snap)
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
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.7).delay(Double(index) * 0.06),
            value: appeared
        )
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
