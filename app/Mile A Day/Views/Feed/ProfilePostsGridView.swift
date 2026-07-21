import SwiftUI

/// Instagram-style 3-column grid of a user's permanent posts, used on both the
/// owner's profile and a friend's profile. Tapping a thumbnail opens the
/// person's posts as a scrollable feed (starting at the tapped post) so you can
/// keep swiping through their history. Paginates as the user scrolls.
struct ProfilePostsGridView: View {
    let userId: String
    var isSelf: Bool = false

    @State private var posts: [PostItem] = []
    @State private var nextBefore: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var loaded = false
    @State private var selectedPost: PostItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        Group {
            if isLoading && posts.isEmpty {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                    .padding(.top, MADTheme.Spacing.xl)
            } else if posts.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
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
        .sheet(item: $selectedPost) { post in
            ProfilePostsFeedSheet(
                title: isSelf ? "Your Posts" : "Posts",
                posts: $posts,
                initialPostId: post.post_id,
                onNeedMore: { Task { await loadMore() } }
            )
        }
    }

    private func thumbnail(_ post: PostItem) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                // The real picture leads when the run has one; the workout
                // card is only the face of the post when no photo exists.
                AsyncImage(url: post.storyPhotoURL ?? post.mediaURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure:
                        ZStack { Color.white.opacity(0.05); Image(systemName: "photo").foregroundColor(.white.opacity(0.3)) }
                    default:
                        ZStack { Color.white.opacity(0.05); ProgressView().tint(.white) }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
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
            .overlay(alignment: .bottomLeading) {
                if let type = post.workout_type {
                    Image(systemName: ActivityCardView.icon(type))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ActivityCardView.color(type))
                        .padding(4)
                        .background(Circle().fill(.black.opacity(0.45)))
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

/// A user's posts as a scrollable, read-only feed — opened from the profile
/// grid at the tapped post, so browsing someone's history feels like reading a
/// feed instead of opening photos one at a time. Shares the grid's post array
/// (and its pagination) via a binding; photos pinch-zoom in place like the
/// main feed.
struct ProfilePostsFeedSheet: View {
    let title: String
    @Binding var posts: [PostItem]
    let initialPostId: String
    let onNeedMore: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// Tapped hype tally — presents the "who hyped this" sheet.
    @State private var hypersContext: HypersListContext?
    /// Tapped comment bubble — presents the comments sheet.
    @State private var commentsPost: PostItem?

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: MADTheme.Spacing.md) {
                            ForEach(posts) { post in
                                card(post)
                                    .id(post.post_id)
                                    .onAppear {
                                        if post.id == posts.last?.id { onNeedMore() }
                                    }
                            }
                        }
                        .padding(MADTheme.Spacing.md)
                        .padding(.bottom, MADTheme.Spacing.xl)
                    }
                    .onAppear {
                        // LazyVStack hasn't laid out far-down cards yet when
                        // onAppear fires, so a single scrollTo can land short
                        // for deep taps — jump, then correct once layout has
                        // caught up.
                        proxy.scrollTo(initialPostId, anchor: .top)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            proxy.scrollTo(initialPostId, anchor: .top)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $hypersContext) { context in
                HypersListSheet(context: context)
            }
            .sheet(item: $commentsPost) { post in
                // Coauthors moderate too: on their own profile the collab post
                // has is_self == false but the server allows their deletes.
                CommentsSheet(
                    post: post,
                    canModerate: post.is_self ||
                        (post.coauthor_status == "accepted"
                         && post.coauthor_user_id == UserDefaults.standard.string(forKey: "backendUserId"))
                ) { newCount in
                    if let index = posts.firstIndex(where: { $0.post_id == post.post_id }) {
                        posts[index].comment_count = newCount
                    }
                }
            }
        }
    }

    /// Same media treatment as the feed card: the real photo leads, the
    /// workout card is the second slide (badged "Stats"), page dots when
    /// there's more than one. Slides pinch-zoom in place (no hype here —
    /// this surface is read-only).
    @ViewBuilder
    private func media(_ post: PostItem) -> some View {
        if let storyPhoto = post.storyPhotoURL {
            TabView {
                ZoomablePhotoSlide(url: storyPhoto)
                ZoomablePhotoSlide(
                    url: post.mediaURL,
                    badge: post.is_auto == true ? ("Stats", "chart.bar.fill") : nil
                )
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
        } else {
            ZoomablePhotoSlide(url: post.mediaURL)
        }
    }

    private func card(_ post: PostItem) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
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
                if let type = post.workout_type {
                    Image(systemName: ActivityCardView.icon(type))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ActivityCardView.color(type))
                }
            }

            media(post)

            if let stats = post.stats_snapshot {
                PostStatStrip(stats: stats).padding(.horizontal, 2)
            }
            if let caption = post.caption, !caption.isEmpty {
                Text(MentionText.attributed(caption))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 2)
            }
            HStack(spacing: 12) {
                if let count = post.hype_count, count > 0 {
                    Button {
                        hypersContext = HypersListContext(
                            contextType: "post",
                            contextId: post.post_id,
                            targetUserId: post.user_id
                        )
                    } label: {
                        HypeTally(count: count, showsLabel: true).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button { commentsPost = post } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 15, weight: .semibold))
                        if let count = post.comment_count, count > 0 {
                            Text("\(count)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
        }
        .padding(MADTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}
