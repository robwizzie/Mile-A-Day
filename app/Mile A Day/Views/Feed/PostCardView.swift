import SwiftUI
import CoreLocation

/// A single post in the social feed: author header, media, caption, hype +
/// social-proof tally, and a report/block/delete menu. The media is a single
/// photo, or a swipeable full-size carousel when the run has more to show —
/// always the real PHOTO first, then the route/stats card, then the route map
/// (each slide full 4:5, with page dots). Tapping a photo slide opens the
/// pinch-to-zoom lightbox.
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

    /// The tapped slide's image, presented in the zoom lightbox.
    private struct LightboxItem: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }
    @State private var lightboxItem: LightboxItem?

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
        .fullScreenCover(item: $lightboxItem) { item in
            PhotoLightboxView(url: item.url)
        }
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
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(ActivityCardView.color(type))
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

    /// A single photo, or a full-size swipeable carousel:
    /// photo → route/stats card → route map.
    @ViewBuilder
    private var media: some View {
        let slides = photoURLs
        let coords = routeSlideCoordinates
        if slides.count > 1 || coords != nil {
            TabView {
                ForEach(Array(slides.enumerated()), id: \.offset) { index, url in
                    // When the story photo leads, badge the trailing auto
                    // route/stats card so the swipe reads as "photo → stats".
                    photoSlide(url, badge: index > 0 && post.is_auto == true ? "Stats" : nil)
                }
                if let coords {
                    routeSlide(coords)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
        } else {
            photoSlide(post.mediaURL)
        }
    }

    private func routeSlide(_ coords: [CLLocationCoordinate2D]) -> some View {
        WorkoutRouteMapView(
            coordinates: coords,
            routeColor: ActivityCardView.color(post.workout_type)
        )
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
        .overlay(alignment: .topLeading) {
            slideBadge("Route", icon: "map.fill")
        }
    }

    private func photoSlide(_ url: URL?, badge: String? = nil) -> some View {
        cardImage(url)
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
            .onTapGesture {
                if let url { lightboxItem = LightboxItem(url: url) }
            }
            .overlay(alignment: .topLeading) {
                if let badge {
                    slideBadge(badge, icon: "chart.bar.fill")
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
    }

    @ViewBuilder
    private func cardImage(_ url: URL?) -> some View {
        if url == nil {
            // AsyncImage(url: nil) never leaves .empty — show the broken-photo
            // placeholder instead of an eternal spinner.
            ZStack {
                Color.white.opacity(0.05)
                Image(systemName: "photo").foregroundColor(.white.opacity(0.3))
            }
        } else {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    ZStack {
                        Color.white.opacity(0.05)
                        Image(systemName: "photo").foregroundColor(.white.opacity(0.3))
                    }
                default:
                    ZStack { Color.white.opacity(0.05); ProgressView().tint(.white) }
                }
            }
        }
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
