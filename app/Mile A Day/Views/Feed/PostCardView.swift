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
    let onHype: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    let onDelete: () -> Void
    /// Tap the author's avatar or name to open their profile.
    var onTapAuthor: (() -> Void)? = nil

    @State private var hypeBurst = 0

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            header
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
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete post", systemImage: "trash")
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

    /// Double-tap on any media slide: clap burst + hype (friends' posts only,
    /// once — a re-double-tap replays the burst without double-counting).
    private func doubleTapHype() {
        guard !post.is_self else { return }
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
    /// post has no GPS route to show. Double-tap hypes, matching the photo.
    private func workoutCardSlide(_ stats: PostStats) -> some View {
        FeedWorkoutCard(stats: stats, workoutType: post.workout_type)
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { if !post.is_self { doubleTapHype() } }
    }

    private func routeSlide(_ coords: [CLLocationCoordinate2D]) -> some View {
        WorkoutRouteMapView(
            coordinates: coords,
            routeColor: ActivityCardView.color(post.workout_type)
        )
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
        .overlay(
            // The map is display-only, so a clear layer can own the
            // double-tap without stealing anything the map needs.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { doubleTapHype() }
        )
        .overlay(alignment: .topLeading) {
            slideBadge("Route", icon: "map.fill")
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
                HypeTally(count: count)
            }
            Spacer()
            if !post.is_self {
                HypeButton(isHyped: post.is_hyped, isBusy: isHyping, action: onHype)
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
