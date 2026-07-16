import SwiftUI
import CoreLocation

/// A single post in the social feed: author header, media, caption, hype +
/// social-proof tally, and a report/block/delete menu. The media is a single
/// photo, or a swipeable full-size carousel when the run has more to show —
/// always the real PHOTO first, then the route/stats card, then the route map
/// (each slide full 4:5, with page dots).
///
/// Media interactions are Instagram's: pinch a photo to zoom it in place
/// (no modal — it floats over the UI and springs back), and double-tap a
/// friend's photo to hype it with a clap burst.
struct PostCardView: View {
    let post: PostItem
    /// The run's story-only photo, when different from the post media.
    var storyPhotoURL: URL? = nil
    /// The viewer's OWN post that went out during the 10-min fresh window —
    /// wears a "Fresh" chip. Client-derived, so it shows only to the poster.
    var isFresh: Bool = false
    var isHyping: Bool = false
    /// Daily hype allowance spent (never true for unlimited roles) — dims the
    /// unspent Hype button, same as the friends list.
    var isOutOfHypes: Bool = false
    let onHype: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    let onDelete: () -> Void
    /// Own posts: opens the caption editor (hidden from the menu when nil).
    var onEditCaption: (() -> Void)? = nil
    /// Tap the author's avatar or name to open their profile.
    var onTapAuthor: (() -> Void)? = nil
    /// Tap the hype tally to see who hyped (Instagram-likes style).
    var onTapHypeCount: (() -> Void)? = nil

    @State private var hypeBurst = 0
    /// Collapses the same physical double-tap arriving from two recognizers
    /// (the card-level SwiftUI gesture AND the zoom host's UIKit one) into a
    /// single burst + hype.
    @State private var lastDoubleTapAt = Date.distantPast
    /// The route slide's raw map snapshot (~400×300) — the only piece kept
    /// around; the zoom's floating composite is rendered on demand from it.
    @State private var routeSnapshot: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            header
            // Instagram behavior: double-tap ANYWHERE on the post body —
            // photo, route map, stats, caption, or the space between — hypes.
            // `simultaneousGesture` so single taps (paging dots, horizontal
            // swipes, pinch zoom) are untouched. The header and footer stay
            // out so double-tapping a button can't hype by accident.
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                media
                if let stats = post.stats_snapshot {
                    PostStatStrip(stats: stats).padding(.horizontal, 2)
                }
                if let caption = post.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 2)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { doubleTapHype() }
            )
            footer
        }
        .padding(MADTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    /// "Fresh" chip for a post shared inside the run's 10-minute window.
    private var freshChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .black))
            Text("FRESH")
                .font(.system(size: 10, weight: .black, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(MADTheme.Colors.madRed))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                onTapAuthor?()
            } label: {
                HStack(spacing: 10) {
                    AvatarView(name: post.displayName, imageURL: post.profile_image_url, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(post.displayName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(post.relativeTime)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(onTapAuthor == nil)
            if isFresh { freshChip }
            Spacer()
            if let type = post.workout_type {
                Image(systemName: ActivityCardView.icon(type))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(ActivityCardView.color(type))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(ActivityCardView.color(type).opacity(0.15)))
            }
            Menu {
                if post.is_self {
                    if let onEditCaption {
                        Button(action: onEditCaption) {
                            Label("Edit caption", systemImage: "pencil")
                        }
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label(post.share_to_feed == false ? "Delete story" : "Delete post",
                              systemImage: "trash")
                    }
                } else {
                    Button(action: onReport) { Label("Report", systemImage: "flag") }
                    Button(role: .destructive, action: onBlock) {
                        Label("Block \(post.displayName)", systemImage: "hand.raised")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(6)
                    .contentShape(Rectangle())
            }
        }
    }

    /// Route slide coordinates — hidden for auto posts, whose media already IS
    /// the rendered route/stats card (a second identical slide would be noise).
    private var routeSlideCoordinates: [CLLocationCoordinate2D]? {
        guard post.is_auto != true else { return nil }
        return post.routeCoordinates
    }

    /// Image slides, real moment first: when the run has a story photo it
    /// leads, and the post media (photo or route/stats card) becomes the
    /// second slide — never a cramped corner thumbnail. Photos the server
    /// withheld arrive blank and drop out here; `mediaSlides` puts a single
    /// lock in their place, ahead of whatever survived.
    private var photoURLs: [URL] {
        if let storyPhotoURL {
            return [storyPhotoURL, post.mediaURL].compactMap { $0 }
        }
        return [post.mediaURL].compactMap { $0 }
    }

    /// Whether to append a branded workout-stats card as the run's second
    /// slide. Only when there's no route map to show instead, the media isn't
    /// already a stats card (auto post), and we actually have stats — so every
    /// photo post reads "photo → the run", not a lone photo.
    private var workoutCardStats: PostStats? {
        guard post.is_auto != true,
              routeSlideCoordinates == nil,
              storyPhotoURL == nil,
              let stats = post.stats_snapshot,
              (stats.distance ?? 0) > 0
        else { return nil }
        return stats
    }

    /// The celebration both hype paths share — the Instagram-style clap
    /// burst + haptic, then the hype call if this post isn't hyped yet.
    /// Double-tap AND the footer HypeButton land here so tapping the button
    /// feels identical to double-tapping the photo.
    private func celebrateAndHype() {
        hypeBurst += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if !post.is_hyped {
            onHype()
        }
    }

    /// Double-tap anywhere on the post body: clap burst + hype (friends'
    /// posts only, once — a re-double-tap replays the burst without
    /// double-counting).
    private func doubleTapHype() {
        guard !post.is_self else { return }
        let now = Date()
        guard now.timeIntervalSince(lastDoubleTapAt) > 0.35 else { return }
        lastDoubleTapAt = now
        celebrateAndHype()
    }

    /// Shown in place of a WITHHELD PHOTO — a frosted "run to unlock" card,
    /// matching the app's earn-to-view story gate. It's one slide among the
    /// rest, so it clips like a photo slide rather than squaring off next to
    /// them.
    private var lockedMediaCard: some View {
        ZStack {
            LinearGradient(
                colors: [MADTheme.Colors.madRed.opacity(0.30), Color.black.opacity(0.65)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Text("Finish your mile to unlock")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Today's photos open up once you complete your own mile.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
    }

    /// One page of the media carousel.
    private enum MediaSlide {
        /// Stands in for the photo(s) the server withheld.
        case locked
        case photo(url: URL, badged: Bool)
        case route(coords: [CLLocationCoordinate2D])
        case statsCard(stats: PostStats)
    }

    /// The carousel's pages in swipe order: the lock (standing in for ANY
    /// withheld photo, however many were held back) → the photos that survived
    /// the gate → the route map, or the stats card when there's no route.
    ///
    /// The lock only ever replaces a picture. An auto route/stats card, a route
    /// map, and the page dots all survive it — so a viewer who hasn't run yet
    /// can still swipe a friend's run, just not see their photo.
    private var mediaSlides: [MediaSlide] {
        var slides: [MediaSlide] = []
        if post.isPhotoLocked { slides.append(.locked) }
        for url in photoURLs {
            // Badge an auto route/stats card that trails a photo (or its lock)
            // so the swipe reads "photo → stats".
            slides.append(.photo(url: url, badged: !slides.isEmpty && post.is_auto == true))
        }
        if let coords = routeSlideCoordinates {
            slides.append(.route(coords: coords))
        } else if let stats = workoutCardStats {
            slides.append(.statsCard(stats: stats))
        }
        return slides
    }

    @ViewBuilder
    private func slideView(_ slide: MediaSlide) -> some View {
        switch slide {
        case .locked:
            lockedMediaCard
        case .photo(let url, let badged):
            ZoomablePhotoSlide(
                url: url,
                badge: badged ? ("Stats", "chart.bar.fill") : nil,
                onDoubleTap: post.is_self ? nil : doubleTapHype
            )
        case .route(let coords):
            routeSlide(coords)
        case .statsCard(let stats):
            workoutCardSlide(stats)
        }
    }

    /// A single slide, or a full-size swipeable carousel. The hype burst plays
    /// centered over whichever slide is showing.
    @ViewBuilder
    private var media: some View {
        let slides = mediaSlides
        Group {
            if slides.count > 1 {
                TabView {
                    ForEach(Array(slides.enumerated()), id: \.offset) { _, slide in
                        slideView(slide)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                .frame(maxWidth: .infinity)
                .aspectRatio(4.0 / 5.0, contentMode: .fit)
            } else if let only = slides.first {
                slideView(only)
            } else {
                // No media at all — the empty-state placeholder.
                ZoomablePhotoSlide(
                    url: nil,
                    badge: nil,
                    onDoubleTap: post.is_self ? nil : doubleTapHype
                )
            }
        }
        .overlay(HypeBurstView(trigger: hypeBurst))
    }

    /// The run itself as a branded stats card — the second slide when a photo
    /// post has no GPS route to show. The card-level double-tap covers it.
    /// Zooms like every other slide; the card is pure SwiftUI so its zoom
    /// copy renders on demand at pinch-begin from the same inputs.
    private func workoutCardSlide(_ stats: PostStats) -> some View {
        FeedWorkoutCard(stats: stats, workoutType: post.workout_type)
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .instagramZoomable(
                imageProvider: {
                    let renderer = ImageRenderer(content:
                        FeedWorkoutCard(stats: stats, workoutType: post.workout_type)
                            .frame(width: RunStatsCardView.designSize.width,
                                   height: RunStatsCardView.designSize.height)
                    )
                    renderer.scale = 2
                    renderer.isOpaque = true
                    return renderer.uiImage
                },
                onDoubleTap: post.is_self ? nil : doubleTapHype
            )
    }

    /// Stats to overlay on the live route slide — same band the auto post
    /// bakes into its image, so a route NEVER shows as a bare map when the
    /// post carries numbers.
    private var routeOverlayStats: RunStatsInput? {
        guard let stats = post.stats_snapshot, let distance = stats.distance, distance > 0
        else { return nil }
        return RunStatsInput(
            distance: distance,
            paceSecondsPerMile: stats.pace,
            durationSeconds: stats.duration,
            streak: stats.streak,
            calories: stats.calories,
            steps: stats.steps,
            workoutId: nil,
            dateText: stats.date
        )
    }

    private func routeSlide(_ coords: [CLLocationCoordinate2D]) -> some View {
        WorkoutRouteMapView(
            coordinates: coords,
            routeColor: ActivityCardView.color(post.workout_type),
            onSnapshot: { routeSnapshot = $0 }
        )
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .overlay {
            if let stats = routeOverlayStats {
                // The overlay lays out at the baked card's 360×450 design
                // size; the slide is the same 4:5, so scaling by width alone
                // reproduces the auto post's look pixel-for-pixel.
                GeometryReader { geo in
                    RouteStatsOverlayView(stats: stats, workoutType: post.workout_type ?? "running")
                        .scaleEffect(geo.size.width / RunStatsCardView.designSize.width,
                                     anchor: .topLeading)
                }
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
        .overlay(alignment: .topLeading) {
            // The stats band carries its own activity chip up top; only badge
            // the bare-map fallback (posts without a stats snapshot).
            if routeOverlayStats == nil {
                slideBadge("Route", icon: "map.fill")
            }
        }
        // Same pinch-zoom as the photo slides. The floating copy (map +
        // route + stats band) is composed at pinch-begin from the small
        // retained snapshot — nothing big is baked per card up front.
        .instagramZoomable(
            imageProvider: { routeZoomComposite(coords) },
            onDoubleTap: post.is_self ? nil : doubleTapHype
        )
    }

    /// The route slide's floating zoom copy, on demand. 720×900 keeps the
    /// photo slides' 4:5 so the lift is pixel-identical.
    private func routeZoomComposite(_ coords: [CLLocationCoordinate2D]) -> UIImage? {
        guard let snapshot = routeSnapshot else { return nil }
        let type = post.workout_type ?? "running"
        let stats = routeOverlayStats
        return WorkoutRouteMapView.zoomComposite(
            snapshot: snapshot,
            coordinates: coords,
            routeColor: ActivityCardView.color(post.workout_type),
            size: CGSize(width: 720, height: 900)
        ) {
            if let stats {
                RouteStatsOverlayView(stats: stats, workoutType: type)
                    .frame(width: RunStatsCardView.designSize.width,
                           height: RunStatsCardView.designSize.height,
                           alignment: .topLeading)
                    .scaleEffect(720 / RunStatsCardView.designSize.width, anchor: .topLeading)
            }
        }
    }

    private func slideBadge(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .padding(10)
        .allowsHitTesting(false)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let count = post.hype_count, count > 0 {
                Button { onTapHypeCount?() } label: {
                    HypeTally(count: count, showsLabel: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onTapHypeCount == nil)
            }
            Spacer()
            if !post.is_self {
                HypeButton(
                    isHyped: post.is_hyped,
                    isBusy: isHyping,
                    isOutOfHypes: isOutOfHypes && !post.is_hyped,
                    action: celebrateAndHype
                )
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }
}

/// One 4:5 media slide with cached loading and Instagram pinch-zoom. The
/// loaded UIImage feeds the zoom overlay so the floating copy is pixel-
/// identical to what's in the card.
struct ZoomablePhotoSlide: View {
    let url: URL?
    var badge: (text: String, icon: String)? = nil
    var onDoubleTap: (() -> Void)? = nil

    @State private var loadedImage: UIImage?

    var body: some View {
        FeedImageView(url: url, loadedImage: $loadedImage)
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
            .instagramZoomable(image: loadedImage, onDoubleTap: onDoubleTap)
            .overlay(alignment: .topLeading) {
                if let badge {
                    HStack(spacing: 5) {
                        Image(systemName: badge.icon)
                            .font(.system(size: 11, weight: .bold))
                        Text(badge.text)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(10)
                    .allowsHitTesting(false)
                }
            }
    }
}
