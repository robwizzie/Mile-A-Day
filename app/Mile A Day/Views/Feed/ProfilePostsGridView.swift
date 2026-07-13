import SwiftUI

/// Instagram-style 3-column grid of a user's permanent posts, used on both the
/// owner's profile and a friend's profile. Tapping a thumbnail opens the
/// person's posts as a scrollable feed (starting at the tapped post) so you can
/// keep swiping through their history. Paginates as the user scrolls.
struct ProfilePostsGridView: View {
    let userId: String
    var isSelf: Bool = false

    @State private var posts: [PostItem] = []
    /// Own story posts whose run never made the feed (self view only) — shown
    /// in their own strip so the owner can add one to the feed or let it be.
    @State private var storyPosts: [PostItem] = []
    @State private var nextBefore: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var loaded = false
    @State private var selectedPost: PostItem?
    @State private var selectedStoryPost: PostItem?
    @State private var addingToFeedIds: Set<String> = []
    @State private var addToFeedError: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        Group {
            if isLoading && posts.isEmpty && storyPosts.isEmpty {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                    .padding(.top, MADTheme.Spacing.xl)
            } else if posts.isEmpty && storyPosts.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                    if isSelf && !storyPosts.isEmpty {
                        storySection
                    }
                    if !posts.isEmpty {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(posts) { post in
                                Button { selectedPost = post } label: { thumbnail(post) }
                                    .buttonStyle(.plain)
                                    .onAppear {
                                        if post.id == posts.last?.id { Task { await loadMore() } }
                                    }
                            }
                        }
                    }
                    if isLoadingMore {
                        ProgressView().tint(.white).padding(.vertical, MADTheme.Spacing.md)
                    }
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
        .sheet(item: $selectedStoryPost) { post in
            ProfilePostsFeedSheet(
                title: "Your Stories",
                posts: $storyPosts,
                initialPostId: post.post_id,
                onNeedMore: {}
            )
        }
        .alert("Couldn't add to feed", isPresented: Binding(
            get: { addToFeedError != nil },
            set: { if !$0 { addToFeedError = nil } }
        )) {
            Button("OK", role: .cancel) { addToFeedError = nil }
        } message: {
            Text(addToFeedError ?? "")
        }
    }

    // MARK: - Story-only strip (own profile)

    /// Horizontal strip of story photos that never made the feed, each with a
    /// one-tap "Add to feed" — promoted posts keep their original date and
    /// stats and slide straight into the grid below.
    private var storySection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                Text("STORIES NOT ON YOUR FEED")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.6))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MADTheme.Spacing.sm) {
                    ForEach(storyPosts) { post in
                        storyCard(post)
                    }
                }
            }
        }
    }

    private func storyCard(_ post: PostItem) -> some View {
        VStack(spacing: 6) {
            Button { selectedStoryPost = post } label: {
                AsyncImage(url: post.mediaURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure:
                        ZStack { Color.white.opacity(0.05); Image(systemName: "photo").foregroundColor(.white.opacity(0.3)) }
                    default:
                        ZStack { Color.white.opacity(0.05); ProgressView().tint(.white) }
                    }
                }
                .frame(width: 108, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .overlay(alignment: .bottomLeading) {
                    if let date = storyDateText(post) {
                        Text(date)
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .padding(6)
                    }
                }
            }
            .buttonStyle(.plain)

            Button { addToFeed(post) } label: {
                HStack(spacing: 4) {
                    if addingToFeedIds.contains(post.post_id) {
                        ProgressView().tint(.white).scaleEffect(0.6)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    Text("Add to feed")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(width: 108)
                .padding(.vertical, 7)
                .background(Capsule().fill(MADTheme.Colors.redGradient))
            }
            .buttonStyle(.plain)
            .disabled(addingToFeedIds.contains(post.post_id))
        }
    }

    private static let storyDateParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let storyDateDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private func storyDateText(_ post: PostItem) -> String? {
        guard let localDate = post.local_date,
              let date = Self.storyDateParser.date(from: localDate) else { return nil }
        return Self.storyDateDisplay.string(from: date)
    }

    private func addToFeed(_ post: PostItem) {
        guard !addingToFeedIds.contains(post.post_id) else { return }
        addingToFeedIds.insert(post.post_id)
        Task {
            do {
                try await PostService.addPostToFeed(postId: post.post_id)
                // Reload so the promoted post re-splits into the grid.
                await load()
            } catch {
                await MainActor.run {
                    addToFeedError = "This run may already have a feed post. Pull to refresh and try again."
                }
            }
            _ = await MainActor.run { addingToFeedIds.remove(post.post_id) }
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
        await MainActor.run { isLoading = posts.isEmpty && storyPosts.isEmpty }
        let response = try? await PostService.fetchUserPosts(
            userId: userId, before: nil, includeStories: isSelf
        )
        await MainActor.run {
            if let response {
                posts = response.items.filter { $0.share_to_feed != false }
                storyPosts = response.items.filter { $0.share_to_feed == false }
                nextBefore = response.next_before
            }
            isLoading = false
            loaded = true
        }
    }

    private func loadMore() async {
        guard let before = nextBefore, !isLoadingMore else { return }
        await MainActor.run { isLoadingMore = true }
        let response = try? await PostService.fetchUserPosts(
            userId: userId, before: before, includeStories: isSelf
        )
        await MainActor.run {
            if let response {
                let existing = Set(posts.map(\.post_id) + storyPosts.map(\.post_id))
                let fresh = response.items.filter { !existing.contains($0.post_id) }
                posts.append(contentsOf: fresh.filter { $0.share_to_feed != false })
                storyPosts.append(contentsOf: fresh.filter { $0.share_to_feed == false })
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
    /// Own post being caption-edited / pending delete confirmation.
    @State private var editingPost: PostItem?
    @State private var deletingPost: PostItem?
    @State private var reportingPost: PostItem?
    @State private var hypingIds: Set<String> = []

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
            .sheet(item: $reportingPost) { post in
                ReportPostSheet(postId: post.post_id) {
                    reportingPost = nil
                }
            }
            .sheet(item: $editingPost) { post in
                EditCaptionSheet(post: post) { newCaption in
                    if let idx = posts.firstIndex(where: { $0.post_id == post.post_id }) {
                        posts[idx].caption = newCaption
                    }
                }
            }
            .alert(
                "Delete this post?",
                isPresented: Binding(
                    get: { deletingPost != nil },
                    set: { if !$0 { deletingPost = nil } }
                ),
                presenting: deletingPost
            ) { post in
                Button("Delete", role: .destructive) {
                    Task {
                        try? await PostService.deletePost(postId: post.post_id)
                        await MainActor.run {
                            posts.removeAll { $0.post_id == post.post_id }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This removes it from your feed and profile for good.")
            }
        }
    }

    private func card(_ post: PostItem) -> some View {
        PostCardView(
            post: post,
            storyPhotoURL: post.storyPhotoURL,
            isHyping: hypingIds.contains(post.post_id),
            onHype: { Task { await hype(post) } },
            onReport: { reportingPost = post },
            onBlock: { Task { await block(post) } },
            onDelete: { deletingPost = post },
            onEditCaption: post.is_self ? { editingPost = post } : nil,
            onTapAuthor: nil,
            onTapHypeCount: {
                hypersContext = HypersListContext(
                    contextType: "post",
                    contextId: post.post_id,
                    targetUserId: post.user_id
                )
            }
        )
    }

    private func hype(_ post: PostItem) async {
        guard !post.is_self, !post.is_hyped, !hypingIds.contains(post.post_id) else { return }
        await MainActor.run {
            _ = hypingIds.insert(post.post_id)
            updatePost(post.post_id) { item in
                guard !item.is_hyped else { return }
                item.is_hyped = true
                item.hype_count = (item.hype_count ?? 0) + 1
            }
        }
        defer { Task { @MainActor in hypingIds.remove(post.post_id) } }

        let revert: @MainActor () -> Void = {
            updatePost(post.post_id) { item in
                guard item.is_hyped else { return }
                item.is_hyped = false
                item.hype_count = max(0, (item.hype_count ?? 1) - 1)
            }
        }

        do {
            _ = try await HypeService.sendHype(
                targetUserId: post.user_id,
                context: HypeContext(
                    contextType: "post",
                    contextId: post.post_id,
                    contextLabel: post.caption ?? post.displayName
                )
            )
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch APIError.conflict {
            // Already hyped server-side — keep the optimistic state.
        } catch {
            await MainActor.run { revert() }
        }
    }

    private func block(_ post: PostItem) async {
        do {
            try await BlockService.block(userId: post.user_id)
            await MainActor.run { posts.removeAll { $0.user_id == post.user_id } }
        } catch {}
    }

    private func updatePost(_ postId: String, _ mutate: (inout PostItem) -> Void) {
        guard let idx = posts.firstIndex(where: { $0.post_id == postId }) else { return }
        mutate(&posts[idx])
    }
}
