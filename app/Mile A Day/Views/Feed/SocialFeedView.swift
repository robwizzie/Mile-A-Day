import SwiftUI

/// The social surface inside the Friends tab: a stories rail on top, a paginated
/// photo feed below, and a compose button. Posting is gated on completing the
/// daily mile (cosmetic here — the server re-verifies) and on a one-time terms
/// acceptance. Reads the shared HealthKit/User singletons for stats + gating.
struct SocialFeedView: View {
    @StateObject private var healthManager = HealthKitManager.shared
    @StateObject private var userManager = UserManager.shared

    @State private var feed: [PostItem] = []
    @State private var stories: [StoryGroup] = []
    @State private var nextBefore: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var loadedOnce = false

    @State private var hypingPostIds: Set<String> = []
    @State private var termsAccepted: Bool?

    // Presentation
    @State private var presentingComposer = false
    @State private var viewerGroup: StoryGroup?
    @State private var reportingPost: PostItem?
    @State private var showTermsGate = false
    @State private var showMileHint = false

    private var currentUserId: String? { UserDefaults.standard.string(forKey: "backendUserId") }
    private var canPost: Bool { healthManager.todaysDistance >= userManager.currentUser.goalMiles }

    private var statsInput: RunStatsInput {
        let user = userManager.currentUser
        return RunStatsInput(
            distance: healthManager.todaysDistance,
            paceSecondsPerMile: nil,
            durationSeconds: nil,
            streak: user.streak,
            workoutId: nil,
            dateText: Self.todayText()
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: MADTheme.Spacing.md) {
                StoriesRailView(
                    groups: stories,
                    currentUserId: currentUserId,
                    myName: userManager.currentUser.username ?? userManager.currentUser.name,
                    myImageURL: userManager.currentUser.profileImageUrl,
                    canPost: canPost,
                    onTapAdd: handleCompose,
                    onTapGroup: { viewerGroup = $0 }
                )

                Divider().overlay(Color.white.opacity(0.08))

                if isLoading && feed.isEmpty {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                        .padding(.top, MADTheme.Spacing.xxl)
                } else if feed.isEmpty {
                    emptyState
                } else {
                    ForEach(feed) { post in
                        PostCardView(
                            post: post,
                            isHyping: hypingPostIds.contains(post.post_id),
                            onHype: { Task { await hype(post) } },
                            onReport: { reportingPost = post },
                            onBlock: { Task { await block(post) } },
                            onDelete: { Task { await deletePost(post) } }
                        )
                        .onAppear { if post.id == feed.last?.id { Task { await loadMore() } } }
                        .padding(.horizontal, MADTheme.Spacing.md)
                    }
                    if isLoadingMore {
                        ProgressView().tint(.white).padding(.vertical, MADTheme.Spacing.md)
                    }
                }
            }
            .padding(.vertical, MADTheme.Spacing.sm)
            .padding(.bottom, MADTheme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .refreshable { await refresh() }
        .overlay(alignment: .bottomTrailing) { composeButton }
        .task { if !loadedOnce { await refresh(); await loadTermsStatus() } }
        .fullScreenCover(item: $viewerGroup) { group in
            StoryViewerView(group: group, currentUserId: currentUserId) { changed in
                viewerGroup = nil
                if changed { Task { await refresh() } }
            }
        }
        .sheet(isPresented: $presentingComposer) {
            PostComposerView(stats: statsInput) { success in
                if success { Task { await refresh() } }
            }
        }
        .sheet(item: $reportingPost) { post in
            ReportPostSheet(postId: post.post_id) { reportingPost = nil }
        }
        .sheet(isPresented: $showTermsGate) {
            PostTermsGateView {
                termsAccepted = true
                presentingComposer = true
            }
        }
        .alert("Finish today's mile first", isPresented: $showMileHint) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Complete your daily mile to share a post or story today. Keep going — you've got this! 🏃")
        }
    }

    private var composeButton: some View {
        Button(action: handleCompose) {
            Image(systemName: canPost ? "plus" : "lock.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(canPost ? AnyShapeStyle(MADTheme.Colors.redGradient) : AnyShapeStyle(Color.gray.opacity(0.6)))
                )
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .padding(.trailing, MADTheme.Spacing.lg)
        .padding(.bottom, MADTheme.Spacing.lg)
    }

    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
            Text("No posts yet")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Finish your mile, then share a photo of today's walk or run.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.top, MADTheme.Spacing.xxl)
        .padding(.horizontal, MADTheme.Spacing.xl)
    }

    // MARK: - Compose flow

    private func handleCompose() {
        guard canPost else { showMileHint = true; return }
        if termsAccepted == true {
            presentingComposer = true
        } else {
            showTermsGate = true
        }
    }

    private func loadTermsStatus() async {
        if let status = try? await PostService.termsStatus() {
            await MainActor.run { termsAccepted = status.accepted }
        }
    }

    // MARK: - Data

    private func refresh() async {
        await MainActor.run { isLoading = feed.isEmpty }
        let feedResponse = try? await PostService.fetchFeed(before: nil)
        let storyGroups = try? await PostService.fetchStoriesRail()
        await MainActor.run {
            if let feedResponse {
                feed = feedResponse.items
                nextBefore = feedResponse.next_before
            }
            if let storyGroups { stories = storyGroups }
            isLoading = false
            loadedOnce = true
        }
    }

    private func loadMore() async {
        guard let before = nextBefore, !isLoadingMore else { return }
        await MainActor.run { isLoadingMore = true }
        let response = try? await PostService.fetchFeed(before: before)
        await MainActor.run {
            if let response {
                let existing = Set(feed.map(\.post_id))
                feed.append(contentsOf: response.items.filter { !existing.contains($0.post_id) })
                nextBefore = response.next_before
            }
            isLoadingMore = false
        }
    }

    // MARK: - Actions

    private func hype(_ post: PostItem) async {
        guard !post.is_self, !post.is_hyped, !hypingPostIds.contains(post.post_id) else { return }
        await MainActor.run { _ = hypingPostIds.insert(post.post_id) }
        defer { Task { @MainActor in hypingPostIds.remove(post.post_id) } }
        do {
            _ = try await HypeService.sendHype(
                targetUserId: post.user_id,
                context: HypeContext(
                    contextType: "post",
                    contextId: post.post_id,
                    contextLabel: post.caption ?? post.displayName
                )
            )
            await MainActor.run { updatePost(post.post_id) { $0.is_hyped = true; $0.hype_count = ($0.hype_count ?? 0) + 1 } }
        } catch {
            // conflict / rate-limited — leave as-is.
        }
    }

    private func block(_ post: PostItem) async {
        do {
            try await BlockService.block(userId: post.user_id)
            await MainActor.run { feed.removeAll { $0.user_id == post.user_id } }
            await refresh()
        } catch {}
    }

    private func deletePost(_ post: PostItem) async {
        do {
            try await PostService.deletePost(postId: post.post_id)
            await MainActor.run { feed.removeAll { $0.post_id == post.post_id } }
        } catch {}
    }

    private func updatePost(_ id: String, _ mutate: (inout PostItem) -> Void) {
        guard let idx = feed.firstIndex(where: { $0.post_id == id }) else { return }
        mutate(&feed[idx])
    }

    private static func todayText() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: Date())
    }
}
