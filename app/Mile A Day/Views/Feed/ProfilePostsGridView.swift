import SwiftUI

/// Instagram-style 3-column grid of a user's permanent posts, used on both the
/// owner's profile and a friend's profile. Tapping a thumbnail opens the
/// person's posts as a scrollable feed (starting at the tapped post) so you can
/// keep swiping through their history. Paginates as the user scrolls.
struct ProfilePostsGridView: View {
    let userId: String
    var isSelf: Bool = false

    /// Which grid is showing: the user's own posts, or posts they're tagged
    /// in (accepted collabs + caption @mentions) — Instagram's two profile tabs.
    private enum GridSection { case posts, tagged }
    @State private var section: GridSection = .posts

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
    /// Observed so the "Add to feed" pills disappear when the walk's posting
    /// window lapses while the grid is on screen.
    @ObservedObject private var freshWindow = FreshPostWindowManager.shared

    // Tagged grid — loaded lazily the first time the section is opened.
    @State private var taggedPosts: [PostItem] = []
    @State private var taggedNextBefore: String?
    @State private var isTaggedLoading = false
    @State private var isTaggedLoadingMore = false
    @State private var taggedLoaded = false
    @State private var selectedTaggedPost: PostItem?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            sectionPicker
            switch section {
            case .posts: postsContent
            case .tagged: taggedContent
            }
        }
        .task { if !loaded { await load() } }
        // The "Tagged posts on my profile" switch lives in Settings, which is
        // pushed FROM here — so popping back lands on a grid that's still
        // alive and still holding the tags the user just turned off. Without
        // this the setting reads as broken at the exact moment it's used.
        .onReceive(NotificationCenter.default.publisher(
            for: NSNotification.Name("MAD_TaggedPostsOnProfileChanged")
        )) { _ in
            guard isSelf else { return }
            Task { await load() }
        }
        .sheet(item: $selectedPost) { post in
            PostDetailView(
                title: isSelf ? "Your Posts" : "Posts",
                posts: $posts,
                initialPostId: post.post_id,
                onNeedMore: { Task { await loadMore() } },
                // This list IS a profile grid, so a collab hidden from the
                // viewer's grid has to leave it. Only on their OWN profile —
                // someone else's grid isn't theirs to curate.
                dropsCollabsHiddenFromProfile: isSelf
            )
        }
        .sheet(item: $selectedStoryPost) { post in
            PostDetailView(
                title: "Your Stories",
                posts: $storyPosts,
                initialPostId: post.post_id,
                onNeedMore: {}
            )
        }
        .sheet(item: $selectedTaggedPost) { post in
            // Tagged posts belong to OTHER authors — let taps on their names
            // (and @mentions) open profiles from inside the sheet.
            PostDetailView(
                title: "Tagged",
                posts: $taggedPosts,
                initialPostId: post.post_id,
                onNeedMore: { Task { await loadMoreTagged() } },
                showsAuthorProfiles: true
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

    // MARK: - Section picker (Posts | Tagged)

    private var sectionPicker: some View {
        HStack(spacing: 8) {
            segmentButton(.posts, icon: "square.grid.3x3", label: "Posts")
            segmentButton(.tagged, icon: "person.crop.square", label: "Tagged")
            Spacer()
        }
    }

    private func segmentButton(_ target: GridSection, icon: String, label: String) -> some View {
        let isActive = section == target
        return Button {
            guard section != target else { return }
            section = target
            if target == .tagged && !taggedLoaded {
                Task { await loadTagged() }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundColor(isActive ? .white : .white.opacity(0.45))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isActive ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Posts grid

    @ViewBuilder
    private var postsContent: some View {
        if isLoading && posts.isEmpty && storyPosts.isEmpty {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                .frame(maxWidth: .infinity)
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
                            gridThumbnail(post) { selectedPost = post }
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

    // MARK: - Tagged grid

    @ViewBuilder
    private var taggedContent: some View {
        if isTaggedLoading && taggedPosts.isEmpty {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                .frame(maxWidth: .infinity)
                .padding(.top, MADTheme.Spacing.xl)
        } else if taggedPosts.isEmpty {
            taggedEmptyState
        } else {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(taggedPosts) { post in
                        gridThumbnail(post) { selectedTaggedPost = post }
                            .onAppear {
                                if post.id == taggedPosts.last?.id {
                                    Task { await loadMoreTagged() }
                                }
                            }
                    }
                }
                if isTaggedLoadingMore {
                    ProgressView().tint(.white).padding(.vertical, MADTheme.Spacing.md)
                }
            }
        }
    }

    private var taggedEmptyState: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: "person.crop.square")
                .font(.system(size: 34))
                .foregroundColor(.white.opacity(0.3))
            Text(isSelf ? "No tagged posts yet" : "No tagged posts")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(isSelf
                 ? "When friends collab with you or @mention you, those posts show up here."
                 : "Collabs and @mentions of them will show up here.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MADTheme.Spacing.xl)
        .padding(.horizontal, MADTheme.Spacing.lg)
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

            // Promoting a story puts a photo on the feed, so it answers to the
            // same 10-minute window as posting one — offering it after the
            // window has closed would only earn a 403.
            if freshWindow.isOpen {
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
            } catch let APIError.apiError(message) where message == "post_window_closed" {
                await MainActor.run {
                    addToFeedError = "Photos reach the feed in the 10 minutes after a walk or run, and that window has closed. Your story stays on your profile."
                }
            } catch {
                await MainActor.run {
                    addToFeedError = "This run may already have a feed post. Pull to refresh and try again."
                }
            }
            _ = await MainActor.run { addingToFeedIds.remove(post.post_id) }
        }
    }

    private func thumbnail(_ post: PostItem) -> some View {
        // The real picture leads when the run has one; the workout card is only
        // the face of the post when no photo exists.
        let url = post.storyPhotoURL ?? post.mediaURL
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                // The lock tile is for when the withheld photo WAS the tile —
                // an auto route/stats card that survived the gate still shows
                // its face, since only the picture is locked.
                Group {
                    if url == nil, post.isPhotoLocked {
                        ZStack {
                            LinearGradient(
                                colors: [MADTheme.Colors.madRed.opacity(0.30), Color.black.opacity(0.6)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                            Image(systemName: "lock.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    } else {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill()
                            case .failure:
                                ZStack { Color.white.opacity(0.05); Image(systemName: "photo").foregroundColor(.white.opacity(0.3)) }
                            default:
                                ZStack { Color.white.opacity(0.05); ProgressView().tint(.white) }
                            }
                        }
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
        .frame(maxWidth: .infinity)
        .padding(.top, MADTheme.Spacing.xl)
        .padding(.horizontal, MADTheme.Spacing.lg)
    }

    // MARK: - Curating tags off the grid

    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: "backendUserId")
    }

    /// A grid cell, carrying the collab long-press ONLY where it applies — an
    /// empty `contextMenu` still pops a blank panel on long-press, so the
    /// modifier is branched rather than the menu left to build nothing. The
    /// branch is stable per post, so it can't thrash view identity inside the
    /// ForEach.
    @ViewBuilder
    private func gridThumbnail(_ post: PostItem, onTap: @escaping () -> Void) -> some View {
        if canCurateOnProfile(post) {
            Button(action: onTap) { thumbnail(post) }
                .buttonStyle(.plain)
                .contextMenu { collabProfileMenu(post) }
        } else {
            Button(action: onTap) { thumbnail(post) }
                .buttonStyle(.plain)
        }
    }

    /// Is this a collab the VIEWER is tagged in, on their own profile, from a
    /// server that knows about the grid split?
    private func canCurateOnProfile(_ post: PostItem) -> Bool {
        isSelf
            && post.hasAcceptedCoauthor
            && post.coauthor_user_id == currentUserId
            && post.coauthor_on_profile != nil
    }

    /// Long-press a collab you're tagged in to pin it on or off your own Posts
    /// grid — the one-gesture version of the card's ⋯ menu, offered from both
    /// tabs because that's where people actually go to tidy their profile.
    /// Deliberately not destructive language: the tag survives either way and
    /// the post never leaves the Tagged tab.
    @ViewBuilder
    private func collabProfileMenu(_ post: PostItem) -> some View {
        if let onProfile = post.coauthor_on_profile {
            Button {
                Task { await setCollabOnProfile(post, onProfile: !onProfile) }
            } label: {
                Label(onProfile ? "Hide from my profile" : "Show on my profile",
                      systemImage: onProfile ? "eye.slash" : "square.grid.2x2")
            }
        }
    }

    private func setCollabOnProfile(_ post: PostItem, onProfile: Bool) async {
        await MainActor.run {
            MADHaptics.tap()
            // Both grids can be showing the same collab, so keep them in step
            // or the Tagged tab offers "Hide" on something already hidden.
            for idx in taggedPosts.indices where taggedPosts[idx].post_id == post.post_id {
                taggedPosts[idx].coauthor_on_profile = onProfile
            }
            if !onProfile { posts.removeAll { $0.post_id == post.post_id } }
        }
        do {
            try await PostService.setCoauthorOnProfile(
                postId: post.post_id, onProfile: onProfile
            )
            // Re-pinned: it belongs back in date order, which only a reload
            // can place correctly (this page may not even reach that far back).
            if onProfile { await load() }
        } catch {
            await MainActor.run {
                for idx in taggedPosts.indices where taggedPosts[idx].post_id == post.post_id {
                    taggedPosts[idx].coauthor_on_profile = !onProfile
                }
            }
            if !onProfile { await load() }
        }
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

    private func loadTagged() async {
        await MainActor.run { isTaggedLoading = taggedPosts.isEmpty }
        let response = try? await PostService.fetchUserTaggedPosts(userId: userId)
        await MainActor.run {
            if let response {
                taggedPosts = response.items
                taggedNextBefore = response.next_before
            }
            isTaggedLoading = false
            taggedLoaded = true
        }
    }

    private func loadMoreTagged() async {
        guard let before = taggedNextBefore, !isTaggedLoadingMore else { return }
        await MainActor.run { isTaggedLoadingMore = true }
        let response = try? await PostService.fetchUserTaggedPosts(userId: userId, before: before)
        await MainActor.run {
            if let response {
                let existing = Set(taggedPosts.map(\.post_id))
                taggedPosts.append(contentsOf: response.items.filter { !existing.contains($0.post_id) })
                taggedNextBefore = response.next_before
            }
            isTaggedLoadingMore = false
        }
    }
}
