import SwiftUI

/// ONE post, opened directly — the app's single destination for "show me that
/// post". A tap on the profile grid, an @mention push, a shared link and a
/// comment notification all land here rather than dropping the user into a
/// feed that then hunts for the right card.
///
/// The list opens ON the tapped post, but keeps the posts around it mounted so
/// the profile behaves like Instagram: tap a grid cell, then scroll up to the
/// newer posts before it or down into older ones.
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
    /// True only when `posts` IS the viewer's own profile GRID. Removing a
    /// collab from your grid then has to drop it from this list too, or the
    /// user taps "Remove from my grid" and watches the post sit exactly where
    /// it was.
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
    /// A hyper tapped in the hypes list: the list dismisses first, then this
    /// becomes `profileUser` (two sheets can't swap in one step).
    @State private var pendingProfileUser: BackendUser?
    /// One stable service for profiles opened from this sheet (same pattern as
    /// SocialFeedView — recreating it per presentation wipes loaded friends).
    @StateObject private var profileFriendService = FriendService()
    /// Post currently being shared as a link.
    @State private var sharingURL: ShareURL?
    @State private var didScrollToInitialPost = false

    var body: some View {
        NavigationStack {
            ZStack {
                MADTheme.Colors.appBackgroundGradient.ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(posts.enumerated()), id: \.element.post_id) { index, post in
                                card(post)
                                    .id(post.post_id)
                                    .onAppear {
                                        if post.id == posts.last?.id { onNeedMore() }
                                    }
                                if index < posts.count - 1 {
                                    PostTimelineSeparator()
                                        .padding(.vertical, MADTheme.Spacing.md)
                                }
                            }
                        }
                        .padding(MADTheme.Spacing.md)
                        .padding(.bottom, MADTheme.Spacing.xl)
                    }
                    .onAppear { scrollToInitialPost(proxy) }
                    .onChange(of: posts.count) { _, _ in scrollToInitialPost(proxy) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // A bare chevron: iOS 26 wraps toolbar items in its own
                    // glass capsule, so a chevron carrying a circle of its own
                    // read as two stacked buttons.
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Back")
                }
            }
            .sheet(item: $sharingURL) { share in
                ShareLinkSheet(url: share.url)
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $hypersContext, onDismiss: {
                if let pending = pendingProfileUser {
                    pendingProfileUser = nil
                    profileUser = pending
                }
            }) { context in
                // Every name in the list opens that person's profile, the way
                // a likes list does.
                HypersListSheet(context: context) { hyper in
                    guard hyper.user_id != currentUserId else { return }
                    pendingProfileUser = BackendUser(
                        user_id: hyper.user_id,
                        username: hyper.username,
                        email: nil,
                        first_name: hyper.first_name,
                        last_name: hyper.last_name,
                        bio: nil,
                        profile_image_url: hyper.profile_image_url,
                        apple_id: nil,
                        auth_provider: nil,
                        role: nil
                    )
                }
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

    private func scrollToInitialPost(_ proxy: ScrollViewProxy) {
        guard !didScrollToInitialPost,
              posts.contains(where: { $0.post_id == initialPostId }) else { return }
        didScrollToInitialPost = true
        DispatchQueue.main.async {
            proxy.scrollTo(initialPostId, anchor: .top)
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
                : nil,
            onSetCollabOnFeed: (post.hasAcceptedCoauthor && post.coauthor_user_id == currentUserId)
                ? { onFeed in Task { await setCollabOnFeed(post, onFeed: onFeed) } }
                : nil,
            // Offered to any credited participant, not just the mirrored
            // coauthor: on a buddy walk everyone's trace is on the card, and
            // everyone's trace is theirs.
            onSetMyCollabRoute: post.acceptedCoauthors.contains { $0.user_id == currentUserId }
                ? { include in Task { await setMyCollabRoute(post, include: include) } }
                : nil,
            onSetIncludeRoute: post.is_self
                ? { include in Task { await setIncludeRoute(post, include: include) } }
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

    /// Accepted coauthor keeps the tag but stops the post reaching THEIR
    /// friends' feeds. Nothing else moves — the author's circle keeps it, the
    /// tag stays visible, and it stays on the coauthor's own grid.
    private func setCollabOnFeed(_ post: PostItem, onFeed: Bool) async {
        await MainActor.run {
            MADHaptics.tap()
            updatePost(post.post_id) { $0.coauthor_on_feed = onFeed }
        }
        do {
            try await PostService.setCoauthorOnFeed(postId: post.post_id, onFeed: onFeed)
        } catch {
            await MainActor.run { updatePost(post.post_id) { $0.coauthor_on_feed = !onFeed } }
        }
    }

    /// A credited participant's own route consent for THIS post, above their
    /// global "Share route maps" setting.
    private func setMyCollabRoute(_ post: PostItem, include: Bool) async {
        await MainActor.run {
            MADHaptics.tap()
            updatePost(post.post_id) { item in
                guard let idx = item.coauthors?.firstIndex(where: { $0.user_id == currentUserId })
                else { return }
                item.coauthors?[idx].include_route = include
            }
        }
        try? await PostService.setCoauthorRoute(postId: post.post_id, includeRoute: include)
    }

    /// The author adds or withdraws the route slide after posting. The trace
    /// itself is untouched, so this is reversible either way.
    private func setIncludeRoute(_ post: PostItem, include: Bool) async {
        await MainActor.run {
            MADHaptics.tap()
            updatePost(post.post_id) { $0.include_route = include }
        }
        do {
            try await PostService.setPostIncludeRoute(postId: post.post_id, includeRoute: include)
        } catch {
            await MainActor.run { updatePost(post.post_id) { $0.include_route = !include } }
        }
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
                    // If the reader opened on the post that just left the
                    // grid, close instead — landing back on the grid it left is
                    // the clearest confirmation anyway.
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
        // Own posts take a hype too — self-hypes are allowed server-side.
        guard !hypingIds.contains(post.post_id) else { return }
        let context = HypeContext(
            contextType: "post",
            contextId: post.post_id,
            contextLabel: post.caption ?? post.displayName
        )
        if post.is_hyped {
            await MainActor.run {
                _ = hypingIds.insert(post.post_id)
                updatePost(post.post_id) { item in
                    guard item.is_hyped else { return }
                    item.is_hyped = false
                    item.hype_count = max(0, (item.hype_count ?? 1) - 1)
                }
            }
            defer { Task { @MainActor in hypingIds.remove(post.post_id) } }
            do {
                _ = try await HypeService.removeHype(
                    targetUserId: post.user_id,
                    context: context
                )
                await MainActor.run { MADHaptics.tap() }
            } catch {
                await MainActor.run {
                    updatePost(post.post_id) { item in
                        guard !item.is_hyped else { return }
                        item.is_hyped = true
                        item.hype_count = (item.hype_count ?? 0) + 1
                    }
                }
            }
            return
        }
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
                context: context
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

}

private struct PostTimelineSeparator: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
            Circle()
                .fill(Color.white.opacity(0.20))
                .frame(width: 4, height: 4)
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
    }
}
