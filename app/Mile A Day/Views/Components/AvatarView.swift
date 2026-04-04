import SwiftUI

/// Universal avatar component. Shows profile image if available, falls back to initials on red gradient.
/// Borders are intentionally excluded — call sites add their own context-specific borders via .overlay().
struct AvatarView: View {
    let name: String
    let imageURL: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let urlPath = imageURL, !urlPath.isEmpty,
               let url = ProfileImageService.fullImageURL(for: urlPath) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsView
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
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
