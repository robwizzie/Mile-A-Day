import SwiftUI

/// ONE post, opened directly — the app's single destination for "show me that
/// post". A tap on the profile grid, an @mention push, a shared link and a
/// comment notification all land here rather than dropping the user into a
/// feed that then hunts for the right card.
///
/// The list starts AT the opened post. It used to render from the top and
/// scroll down to it behind an opacity mask with a 300ms settle — which meant
/// a visible lurch, a flash of somebody else's card, and nothing at all for a
/// post too old to be in the loaded page. Slicing instead means the tapped
/// post is simply the first row: it's on screen in the first frame, and the
/// user can keep scrolling into older posts exactly as before.
///
/// `posts` is a binding so hypes, caption edits and deletes made here flow
/// straight back to the grid that opened it. Deep links have no such list —
/// `PostDetailLoaderView` fetches the single post and owns the array itself.
struct PostDetailView: View {
    let title: String
    @Binding var posts: [PostItem]
    let initialPostId: String
    let onNeedMore: () -> Void
    /// True for surfaces showing OTHER people's posts (the Tagged tab):
    /// author/coauthor names and caption @mentions open profiles.
    var showsAuthorProfiles: Bool = false
    /// True only when `posts` IS the viewer's own profile GRID. Hiding a collab
    /// from your grid then has to drop it from this list too, or the user taps
    /// "Hide from my profile" and watches the post sit exactly where it was.
    /// Every other surface (Tagged tab, feed, deep link) keeps showing it —
    /// that's the entire point of the setting.
    var dropsCollabsHiddenFromProfile: Bool = false
    @Environment(\.dismiss) private var dismiss
    /// Tapped hype tally — presents the "who hyped this" sheet.
    @State private var hypersContext: HypersListContext?
    /// Tapped comment bubble — presents the comments sheet.
    @State private var commentsPost: PostItem?
    /// Own post being caption-edited / pending delete confirmation.
    @State private var editingPost: PostItem?
    @State private var deletingPost: PostItem?
    @State private var reportingPost: PostItem?
    @State private var hypingIds: Set<String> = []
    /// Profile opened from a tapped author/coauthor name or @mention.
    @State private var profileUser: BackendUser?
    /// One stable service for profiles opened from this sheet (same pattern as
    /// SocialFeedView — recreating it per presentation wipes loaded friends).
    @StateObject private var profileFriendService = FriendService()
    /// Post currently being shared as a link.
    @State private var sharingURL: ShareURL?

    /// The opened post first, then everything older. Newer posts are dropped
    /// rather than scrolled past: nothing above the fold means no lurch, no
    /// flash of someone else's card, and no dependency on the tapped post
    /// being in the loaded page at all.
    ///
    /// Falls back to the whole array when the id isn't present, which is what
    /// makes the deep-link loader (a one-element array) and any future caller
    /// safe by construction.
    private var visiblePosts: [PostItem] {
        guard let start = posts.firstIndex(where: { $0.post_id == initialPostId })
        else { return posts }
        return Array(posts[start...])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: MADTheme.Spacing.md) {
                        ForEach(visiblePosts) { post in
                            card(post)
                                .id(post.post_id)
                                .onAppear {
                                    if post.id == visiblePosts.last?.id { onNeedMore() }
                                }
                        }
                    }
                    .padding(MADTheme.Spacing.md)
                    .padding(.bottom, MADTheme.Spacing.xl)
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
            .sheet(item: $sharingURL) { share in
                ShareLinkSheet(url: share.url)
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
            .sheet(item: $profileUser) { user in
                NavigationStack {
                    UserProfileDetailView(user: user, friendService: profileFriendService)
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

    private var currentUserId: String? {
        UserDefaults.standard.string(forKey: "backendUserId")
    }

    private func card(_ post: PostItem) -> some View {
        // Profile taps only on surfaces that show other people's posts.
        let openAuthor: (() -> Void)? = (showsAuthorProfiles && !post.is_self)
            ? {
                profileUser = BackendUser(
                    user_id: post.user_id, username: post.username, email: nil,
                    first_name: post.first_name, last_name: post.last_name,
                    bio: nil, profile_image_url: post.profile_image_url,
                    apple_id: nil, auth_provider: nil, role: nil
                )
            }
            : nil
        let openCoauthor: (() -> Void)? =
            (showsAuthorProfiles && post.hasAcceptedCoauthor && post.coauthor_user_id != currentUserId)
            ? {
                profileUser = BackendUser(
                    user_id: post.coauthor_user_id ?? "", username: post.coauthor_username,
                    email: nil, first_name: post.coauthor_first_name,
                    last_name: post.coauthor_last_name, bio: nil,
                    profile_image_url: post.coauthor_profile_image_url,
                    apple_id: nil, auth_provider: nil, role: nil
                )
            }
            : nil
        return PostCardView(
            post: post,
            storyPhotoURL: post.storyPhotoURL,
            isHyping: hypingIds.contains(post.post_id),
            onHype: { Task { await hype(post) } },
            onReport: { reportingPost = post },
            onBlock: { Task { await block(post) } },
            onDelete: { deletingPost = post },
            onEditCaption: post.is_self ? { editingPost = post } : nil,
            onTapAuthor: openAuthor,
            onTapCoauthor: openCoauthor,
            onTapMention: showsAuthorProfiles ? { username in openMentionProfile(username) } : nil,
            onTapHypeCount: {
                hypersContext = HypersListContext(
                    contextType: "post",
                    contextId: post.post_id,
                    targetUserId: post.user_id
                )
            },
            onOpenComments: { commentsPost = post },
            onShare: { sharingURL = ShareURL(url: PostShareLink.url(for: post.post_id)) },
            // Accepted coauthor: a collab has is_self == false for them, so
            // without this the card offers them Hype/Report/Block on a post
            // they co-own. Leaving is the one action that IS theirs.
            onLeaveCollab: (post.hasAcceptedCoauthor && post.coauthor_user_id == currentUserId)
                ? { Task { await leaveCollab(post) } }
                : nil,
            onSetCollabOnProfile: (post.hasAcceptedCoauthor && post.coauthor_user_id == currentUserId)
                ? { onProfile in Task { await setCollabOnProfile(post, onProfile: onProfile) } }
                : nil
        )
    }

    /// Accepted coauthor removes themselves from a collab post — "decline"
    /// after acceptance clears the collab server-side, so the post is no
    /// longer theirs and drops out of this list.
    private func leaveCollab(_ post: PostItem) async {
        try? await PostService.respondToCoauthor(postId: post.post_id, accept: false)
        await MainActor.run { posts.removeAll { $0.post_id == post.post_id } }
    }

    /// Accepted coauthor pins this collab on/off their own profile grid. The
    /// tag itself is untouched — this is the reversible sibling of
    /// `leaveCollab`, and the post stays wherever else it already was.
    private func setCollabOnProfile(_ post: PostItem, onProfile: Bool) async {
        await MainActor.run {
            MADHaptics.tap()
            updatePost(post.post_id) { $0.coauthor_on_profile = onProfile }
        }
        do {
            try await PostService.setCoauthorOnProfile(
                postId: post.post_id, onProfile: onProfile
            )
            // Only the grid itself loses the card; every other host keeps it.
            if dropsCollabsHiddenFromProfile && !onProfile {
                await MainActor.run {
                    posts.removeAll { $0.post_id == post.post_id }
                    // `visiblePosts` slices from `initialPostId`, so removing
                    // the post the sheet OPENED at falls back to the whole
                    // array and silently rewinds the reader to the newest
                    // post. Close instead — landing back on a grid the post
                    // has just left is the clearest confirmation anyway.
                    if post.post_id == initialPostId { dismiss() }
                }
            }
        } catch {
            await MainActor.run {
                updatePost(post.post_id) { $0.coauthor_on_profile = !onProfile }
            }
        }
    }

    @MainActor
    private func updatePost(_ id: String, _ mutate: (inout PostItem) -> Void) {
        guard let idx = posts.firstIndex(where: { $0.post_id == id }) else { return }
        mutate(&posts[idx])
    }

    /// A tapped caption @mention: resolve to the exact user and open their
    /// profile (same behavior as the main feed).
    private func openMentionProfile(_ username: String) {
        let lowered = username.lowercased()
        Task {
            guard let match = try? await profileFriendService.searchUsers(byUsername: lowered)
                .first(where: { $0.username?.lowercased() == lowered }) else { return }
            await MainActor.run {
                guard match.user_id != currentUserId else { return }
                profileUser = match
            }
        }
    }

    private func hype(_ post: PostItem) async {
        guard !post.is_self, !post.is_hyped, !hypingIds.contains(post.post_id) else { return }
        // A collab you're an author on is your own post — the server rejects
        // the hype, so don't play the burst and then silently walk it back.
        guard !(post.hasAcceptedCoauthor && post.coauthor_user_id == currentUserId) else { return }
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
                MADHaptics.success()
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
