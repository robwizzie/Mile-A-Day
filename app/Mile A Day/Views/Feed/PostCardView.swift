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
    /// second slide — never a cramped corner thumbnail.
    private var photoURLs: [URL?] {
        if let storyPhotoURL {
            return [storyPhotoURL, post.mediaURL]
        }
        return [post.mediaURL]
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

    /// Double-tap anywhere on the post body: clap burst + hype (friends'
    /// posts only, once — a re-double-tap replays the burst without
    /// double-counting).
    private func doubleTapHype() {
        guard !post.is_self else { return }
        let now = Date()
        guard now.timeIntervalSince(lastDoubleTapAt) > 0.35 else { return }
        lastDoubleTapAt = now
        hypeBurst += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if !post.is_hyped {
            onHype()
        }
    }

    /// A single photo, or a full-size swipeable carousel:
    /// photo → route/stats card → route map. The hype burst plays centered
    /// over whichever slide is showing.
    @ViewBuilder
    private var media: some View {
        let slides = photoURLs
        let coords = routeSlideCoordinates
        let cardStats = workoutCardStats
        Group {
            if slides.count > 1 || coords != nil || cardStats != nil {
                TabView {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, url in
                        // When the story photo leads, badge the trailing auto
                        // route/stats card so the swipe reads as "photo → stats".
                        ZoomablePhotoSlide(
                            url: url,
                            badge: index > 0 && post.is_auto == true ? ("Stats", "chart.bar.fill") : nil,
                            onDoubleTap: post.is_self ? nil : doubleTapHype
                        )
                    }
                    if let coords {
                        routeSlide(coords)
                    } else if let cardStats {
                        workoutCardSlide(cardStats)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                .frame(maxWidth: .infinity)
                .aspectRatio(4.0 / 5.0, contentMode: .fit)
            } else {
                ZoomablePhotoSlide(
                    url: post.mediaURL,
                    badge: nil,
                    onDoubleTap: post.is_self ? nil : doubleTapHype
                )
            }
        }
        .overlay(HypeBurstView(trigger: hypeBurst))
    }

    /// The run itself as a branded stats card — the second slide when a photo
    /// post has no GPS route to show. The card-level double-tap covers it.
    private func workoutCardSlide(_ stats: PostStats) -> some View {
        FeedWorkoutCard(stats: stats, workoutType: post.workout_type)
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
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
            routeColor: ActivityCardView.color(post.workout_type)
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
                    action: onHype
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
