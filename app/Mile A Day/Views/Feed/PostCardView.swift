import SwiftUI

/// A single post in the social feed: author header, photo (overlay already
/// baked in), caption, hype + social-proof tally, and a report/block/delete menu.
struct PostCardView: View {
    let post: PostItem
    var isHyping: Bool = false
    let onHype: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            header
            photo
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
            Spacer()
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

    private var photo: some View {
        AsyncImage(url: post.mediaURL) { phase in
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
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))
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
