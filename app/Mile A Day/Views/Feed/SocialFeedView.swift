import SwiftUI

/// The single social surface inside the Friends tab: a stories rail, an optional
/// "On this day" memories card, then one unified, infinitely-scrollable feed of
/// photo posts AND raw walk/run activity. Posting and viewing friends' stories
/// are both gated on completing today's mile (the server re-verifies posting).
struct SocialFeedView: View {
    @StateObject private var healthManager = HealthKitManager.shared
    @StateObject private var userManager = UserManager.shared

    @State private var feed: [FeedEntry] = []
    @State private var stories: [StoryGroup] = []
    @State private var memories: [MemoryItem] = []
    @State private var nextBefore: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var loadedOnce = false

    @State private var hypingIds: Set<String> = []
    @State private var termsAccepted: Bool?

    // Presentation
    @State private var presentingComposer = false
    @State private var viewerGroup: StoryGroup?
    @State private var reportingPost: PostItem?
    @State private var showTermsGate = false
    /// Compose was requested but blocked on the terms gate — open the composer
    /// AFTER the gate sheet dismisses (presenting both at once is a SwiftUI
    /// sheet-over-sheet race that can drop the composer entirely).
    @State private var pendingCompose = false
    @State private var showMileHint = false
    @State private var showMemories = false
    @State private var showWeeklyRecap = false
    @State private var profileUser: BackendUser?

    private var currentUserId: String? { UserDefaults.standard.string(forKey: "backendUserId") }
    /// Completing the daily mile unlocks posting AND viewing friends' stories.
    private var mileDone: Bool { healthManager.todaysDistance >= userManager.currentUser.goalMiles }

    private var statsInput: RunStatsInput {
        let user = userManager.currentUser
        let duration = healthManager.todaysTotalDuration
        // todaysAveragePace is MINUTES per mile; sticker/snapshot use SECONDS.
        let paceSecPerMile = healthManager.todaysAveragePace.map { $0 * 60 }
        let calories = healthManager.todaysTotalCalories
        let steps = healthManager.todaysSteps
        return RunStatsInput(
            distance: healthManager.todaysDistance,
            paceSecondsPerMile: (paceSecPerMile ?? 0) > 0 ? paceSecPerMile : nil,
            durationSeconds: duration > 0 ? duration : nil,
            streak: user.streak,
            calories: calories > 0 ? calories : nil,
            steps: steps > 0 ? steps : nil,
            // Link to the daily-mile workout so this post upserts into the same
            // feed item as the auto route/stats post — one post per run.
            workoutId: mileDone ? RunPostService.dailyMileWorkoutId() : nil,
            dateText: Self.todayText()
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            MADTabHeader(title: "Feed")

            ScrollView {
                LazyVStack(spacing: MADTheme.Spacing.md) {
                    StoriesRailView(
                        groups: stories,
                        currentUserId: currentUserId,
                        myName: userManager.currentUser.username ?? userManager.currentUser.name,
                        myImageURL: userManager.currentUser.profileImageUrl,
                        canPost: mileDone,
                        canViewStories: mileDone,
                        onTapAdd: handleCompose,
                        onTapGroup: { viewerGroup = $0 },
                        onLockedStoryTap: { showMileHint = true }
                    )

                    if !memories.isEmpty {
                        MemoriesCardView(memories: memories) { showMemories = true }
                            .padding(.horizontal, MADTheme.Spacing.md)
                    }

                    if isWeeklyRecapDay {
                        weeklyRecapTeaserCard
                            .padding(.horizontal, MADTheme.Spacing.md)
                    }

                    Divider().overlay(Color.white.opacity(0.08))

                    if isLoading && feed.isEmpty {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                            .padding(.top, MADTheme.Spacing.xxl)
                    } else if feed.isEmpty {
                        emptyState
                    } else {
                        ForEach(feed) { entry in
                            feedCard(entry)
                                .onAppear { if entry.id == feed.last?.id { Task { await loadMore() } } }
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
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottomTrailing) { composeButton }
        .task { if !loadedOnce { await refresh(); await loadTermsStatus(); loadMemories() } }
        .fullScreenCover(item: $viewerGroup) { group in
            StoryViewerView(group: group, currentUserId: currentUserId) { changed in
                viewerGroup = nil
                if changed {
                    Task { await refresh() }
                } else {
                    // Even a plain watch-through changes rail state (viewed
                    // rings) — refresh just the rail so rings gray out.
                    Task { await refreshRail() }
                }
            }
        }
        .sheet(isPresented: $presentingComposer) {
            PostComposerView(stats: statsInput, destination: .feed) { outcome in
                if case .published = outcome { Task { await refresh() } }
            }
        }
        .sheet(item: $reportingPost) { post in
            ReportPostSheet(postId: post.post_id) { reportingPost = nil }
        }
        .sheet(isPresented: $showTermsGate, onDismiss: {
            // Present the composer only after the gate sheet is fully gone.
            if pendingCompose && termsAccepted == true {
                presentingComposer = true
            }
            pendingCompose = false
        }) {
            PostTermsGateView {
                termsAccepted = true
            }
        }
        .sheet(isPresented: $showMemories) {
            MemoriesDetailView(memories: memories)
        }
        .sheet(isPresented: $showWeeklyRecap) {
            WeeklyRecapView()
        }
        .sheet(item: $profileUser) { user in
            NavigationStack {
                UserProfileDetailView(user: user, friendService: FriendService())
            }
        }
        .alert("Finish today's mile first", isPresented: $showMileHint) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Complete your daily mile to post and to see your friends' stories today. Keep going — you've got this! 🏃")
        }
    }

    // MARK: - Weekly Recap teaser

    /// The recap teaser only surfaces at the week boundary (Sunday/Monday),
    /// and respects the "Weekly recap" preference toggle.
    private var isWeeklyRecapDay: Bool {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return (weekday == 1 || weekday == 2) && NotificationPreferences.load().weeklyRecapEnabled
    }

    /// Compact "Your week in miles" card — styled like MemoriesCardView.
    private var weeklyRecapTeaserCard: some View {
        Button { showWeeklyRecap = true } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(MADTheme.Colors.redGradient))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly recap")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.6))
                    Text("Your week in miles is ready")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(MADTheme.Colors.madRed.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func feedCard(_ entry: FeedEntry) -> some View {
        let openProfile = {
            guard !entry.is_self else { return }
            profileUser = BackendUser(
                user_id: entry.user_id,
                username: entry.username,
                email: nil,
                first_name: entry.first_name,
                last_name: entry.last_name,
                bio: nil,
                profile_image_url: entry.profile_image_url,
                apple_id: nil,
                auth_provider: nil,
                role: nil
            )
        }
        if entry.isPost, let post = entry.asPostItem() {
            PostCardView(
                post: post,
                storyPhotoURL: entry.storyPhotoURL,
                isHyping: hypingIds.contains(entry.id),
                onHype: { Task { await hype(entry) } },
                onReport: { reportingPost = post },
                onBlock: { Task { await block(entry) } },
                onDelete: { Task { await deletePost(entry) } },
                onTapAuthor: openProfile
            )
        } else {
            ActivityCardView(
                entry: entry,
                isHyping: hypingIds.contains(entry.id),
                onHype: { Task { await hype(entry) } },
                onTapAuthor: openProfile
            )
        }
    }

    private var composeButton: some View {
        Button(action: handleCompose) {
            Image(systemName: mileDone ? "plus" : "lock.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(mileDone ? AnyShapeStyle(MADTheme.Colors.redGradient) : AnyShapeStyle(Color.gray.opacity(0.6)))
                )
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .padding(.trailing, MADTheme.Spacing.lg)
        .padding(.bottom, MADTheme.Spacing.lg)
    }

    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
            Text("No activity yet")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Walks, runs, and photos from you and your friends show up here. Add friends and get moving!")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.top, MADTheme.Spacing.xxl)
        .padding(.horizontal, MADTheme.Spacing.xl)
    }

    // MARK: - Compose flow

    private func handleCompose() {
        guard mileDone else { showMileHint = true; return }
        if termsAccepted == true {
            presentingComposer = true
        } else {
            pendingCompose = true
            showTermsGate = true
        }
    }

    private func loadTermsStatus() async {
        if let status = try? await PostService.termsStatus() {
            await MainActor.run { termsAccepted = status.accepted }
        }
    }

    private func loadMemories() {
        // Local HealthKit memories show instantly; past post photos (this day
        // in past years, a week ago, a month ago) blend in when they arrive.
        memories = MemoriesService.onThisDay(using: healthManager)
        Task {
            if let posts = try? await PostService.fetchPostMemories(), !posts.isEmpty {
                await MainActor.run {
                    memories = MemoriesService.mergingPostMemories(posts, into: memories)
                }
            }
        }
    }

    // MARK: - Data

    private func refresh() async {
        await MainActor.run { isLoading = feed.isEmpty }
        let feedResponse = try? await PostService.fetchUnifiedFeed(before: nil)
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

    /// Reload just the stories rail (viewed rings, expired groups) without the
    /// heavier full feed refresh.
    private func refreshRail() async {
        if let groups = try? await PostService.fetchStoriesRail() {
            await MainActor.run { stories = groups }
        }
    }

    private func loadMore() async {
        guard let before = nextBefore, !isLoadingMore else { return }
        await MainActor.run { isLoadingMore = true }
        let response = try? await PostService.fetchUnifiedFeed(before: before)
        await MainActor.run {
            if let response {
                let existing = Set(feed.map(\.id))
                feed.append(contentsOf: response.items.filter { !existing.contains($0.id) })
                nextBefore = response.next_before
            }
            isLoadingMore = false
        }
    }

    // MARK: - Actions

    private func hype(_ entry: FeedEntry) async {
        guard !entry.is_self, !entry.is_hyped, !hypingIds.contains(entry.id) else { return }
        await MainActor.run { _ = hypingIds.insert(entry.id) }
        defer { Task { @MainActor in hypingIds.remove(entry.id) } }
        let ctxType = entry.isPost ? "post" : "mile"
        let label = entry.isPost
            ? (entry.caption ?? entry.displayName)
            : "\(ActivityCardView.verb(entry.workout_type)) \(String(format: "%.2f", entry.distance ?? 0)) mi"
        do {
            _ = try await HypeService.sendHype(
                targetUserId: entry.user_id,
                context: HypeContext(contextType: ctxType, contextId: entry.entryId, contextLabel: label)
            )
            await MainActor.run {
                updateEntry(entry.id) { e in
                    // A refresh may have landed mid-request and already carry
                    // this hype — don't count it twice.
                    guard !e.is_hyped else { return }
                    e.is_hyped = true
                    e.hype_count = (e.hype_count ?? 0) + 1
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            // conflict (already hyped) / rate-limited — leave as-is.
        }
    }

    private func block(_ entry: FeedEntry) async {
        do {
            try await BlockService.block(userId: entry.user_id)
            await MainActor.run { feed.removeAll { $0.user_id == entry.user_id } }
            await refresh()
        } catch {}
    }

    private func deletePost(_ entry: FeedEntry) async {
        do {
            try await PostService.deletePost(postId: entry.entryId)
            await MainActor.run { feed.removeAll { $0.id == entry.id } }
        } catch {}
    }

    private func updateEntry(_ id: String, _ mutate: (inout FeedEntry) -> Void) {
        guard let idx = feed.firstIndex(where: { $0.id == id }) else { return }
        mutate(&feed[idx])
    }

    private static func todayText() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: Date())
    }
}
