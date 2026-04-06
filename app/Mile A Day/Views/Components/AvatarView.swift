import SwiftUI

/// Simple in-memory image cache for avatar URLs.
private final class AvatarImageCache {
    static let shared = AvatarImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    init() {
        cache.countLimit = 100
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

/// Universal avatar component. Shows profile image if available, falls back to initials on red gradient.
/// Borders are intentionally excluded ��� call sites add their own context-specific borders via .overlay().
struct AvatarView: View {
    let name: String
    let imageURL: String?
    let size: CGFloat

    @State private var cachedImage: UIImage?

    var body: some View {
        Group {
            if let urlPath = imageURL, !urlPath.isEmpty,
               let url = ProfileImageService.fullImageURL(for: urlPath) {
                if let img = cachedImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .onAppear {
                                    // Cache the downloaded image as UIImage via renderer
                                    let renderer = ImageRenderer(content: image.resizable().aspectRatio(contentMode: .fill).frame(width: size, height: size))
                                    if let uiImage = renderer.uiImage {
                                        AvatarImageCache.shared.store(uiImage, for: url)
                                        cachedImage = uiImage
                                    }
                                }
                        } else if case .failure = phase {
                            initialsView
                        } else {
                            initialsView
                        }
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .onAppear {
            if let urlPath = imageURL, !urlPath.isEmpty,
               let url = ProfileImageService.fullImageURL(for: urlPath) {
                cachedImage = AvatarImageCache.shared.image(for: url)
            }
        }
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(MADTheme.Colors.redGradient)
    }

    private var initials: String {
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
