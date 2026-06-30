import SwiftUI

/// Instagram-style 3-column grid of a user's permanent posts, used on both the
/// owner's profile and a friend's profile. Tapping a thumbnail opens a detail
/// sheet. Paginates as the user scrolls.
struct ProfilePostsGridView: View {
    let userId: String
    var isSelf: Bool = false

    @State private var posts: [PostItem] = []
    @State private var nextBefore: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var loaded = false
    @State private var selectedPost: PostItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        Group {
            if isLoading && posts.isEmpty {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                    .padding(.top, MADTheme.Spacing.xl)
            } else if posts.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(posts) { post in
                        Button { selectedPost = post } label: { thumbnail(post) }
                            .buttonStyle(.plain)
                            .onAppear {
                                if post.id == posts.last?.id { Task { await loadMore() } }
                            }
                    }
                }
                if isLoadingMore {
                    ProgressView().tint(.white).padding(.vertical, MADTheme.Spacing.md)
                }
            }
        }
        .task { if !loaded { await load() } }
        .sheet(item: $selectedPost) { post in PostDetailSheet(post: post) }
    }

    private func thumbnail(_ post: PostItem) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                AsyncImage(url: post.mediaURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure:
                        ZStack { Color.white.opacity(0.05); Image(systemName: "photo").foregroundColor(.white.opacity(0.3)) }
                    default:
                        ZStack { Color.white.opacity(0.05); ProgressView().tint(.white) }
                    }
                }
            )
            .clipped()
            .overlay(alignment: .topTrailing) {
                if post.stats_snapshot?.streak != nil {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(4)
                        .background(Circle().fill(.black.opacity(0.4)))
                        .padding(4)
                }
            }
    }

    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 34))
                .foregroundColor(.white.opacity(0.3))
            Text(isSelf ? "No posts yet" : "No posts to show")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            if isSelf {
                Text("Share a photo of your walk or run from the Feed tab.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, MADTheme.Spacing.xl)
        .padding(.horizontal, MADTheme.Spacing.lg)
    }

    private func load() async {
        await MainActor.run { isLoading = posts.isEmpty }
        let response = try? await PostService.fetchUserPosts(userId: userId, before: nil)
        await MainActor.run {
            if let response {
                posts = response.items
                nextBefore = response.next_before
            }
            isLoading = false
            loaded = true
        }
    }

    private func loadMore() async {
        guard let before = nextBefore, !isLoadingMore else { return }
        await MainActor.run { isLoadingMore = true }
        let response = try? await PostService.fetchUserPosts(userId: userId, before: before)
        await MainActor.run {
            if let response {
                let existing = Set(posts.map(\.post_id))
                posts.append(contentsOf: response.items.filter { !existing.contains($0.post_id) })
                nextBefore = response.next_before
            }
            isLoadingMore = false
        }
    }
}

/// Read-only detail for a single post opened from the grid: the photo, caption,
/// and a stat strip. (Hype/moderation live on the main feed.)
struct PostDetailSheet: View {
    let post: PostItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                        HStack(spacing: 10) {
                            AvatarView(name: post.displayName, imageURL: post.profile_image_url, size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(post.displayName)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text(post.relativeTime)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            Spacer()
                        }

                        AsyncImage(url: post.mediaURL) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFit()
                            default: ZStack { Color.white.opacity(0.05); ProgressView().tint(.white) }
                                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium, style: .continuous))

                        if let stats = post.stats_snapshot {
                            PostStatStrip(stats: stats)
                        }
                        if let caption = post.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.white)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
