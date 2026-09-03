import SwiftUI
import UIKit

/// The circular avatar that rides a route line and settles as its end marker.
///
/// Deliberately NOT `AvatarView`: that renders through `AsyncImage`, which
/// (1) produces nothing inside `ImageRenderer` — the zoom composite and the
/// baked auto-post image would ship empty circles — and (2) flickers back to
/// initials every time a feed cell is recycled. This takes an already-loaded
/// `UIImage` (see `RouteAvatarImageLoader`) and falls back to the same
/// initials-on-red-gradient face `AvatarView` draws, so the two are visually
/// one component.
struct RouteAvatarBadge: View {
    let name: String
    let image: UIImage?
    let size: CGFloat
    /// The line's colour — ring + glow, so the badge reads as that line's
    /// endpoint the same way the old coloured end dot did.
    let ring: Color

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Text(AvatarView.initials(for: name))
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: size, height: size)
                    .background(MADTheme.Colors.redGradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 1.5))
        .overlay(Circle().stroke(ring, lineWidth: 2).padding(-1.5))
        .shadow(color: ring.opacity(0.7), radius: 5)
    }

}

/// Resolves a profile-image path to a `UIImage` through `FeedImageCache` —
/// the same cache feed media uses, keyed by host+path so signed-URL query
/// rotation doesn't re-download (see FeedMediaViews.swift).
enum RouteAvatarImageLoader {
    /// Cache-only, synchronous — what zoom composites and baked renders use
    /// (they run at pinch-begin / post time and must not wait on a download;
    /// the initials fallback is the miss behaviour).
    static func cachedImage(for imageURL: String?) -> UIImage? {
        guard let url = resolved(imageURL) else { return nil }
        return FeedImageCache.image(for: url)
    }

    /// Cache-through download — what live views `.task` on appear.
    static func loadImage(for imageURL: String?) async -> UIImage? {
        guard let url = resolved(imageURL) else { return nil }
        if let cached = FeedImageCache.image(for: url) { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        FeedImageCache.store(image, for: url)
        return image
    }

    private static func resolved(_ imageURL: String?) -> URL? {
        guard let imageURL, !imageURL.isEmpty else { return nil }
        return ProfileImageService.fullImageURL(for: imageURL)
    }
}
