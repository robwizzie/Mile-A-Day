import SwiftUI

/// The single social surface inside the Friends tab: a stories rail, an optional
/// "On this day" memories card, then one unified, infinitely-scrollable feed of
/// photo posts AND raw walk/run activity. Posting and viewing friends' stories
/// are both gated on completing today's mile (the server re-verifies posting).
struct SocialFeedView: View {
    @StateObject private var healthManager = HealthKitManager.shared
    @StateObject private var userManager = UserManager.shared
    /// One stable service for profiles opened from the feed. Creating a fresh
    /// FriendService inside the sheet closure re-instantiated it on every feed
    /// state change, wiping the loaded friends list mid-view.
    @StateObject private var profileFriendService = FriendService()

    @State private var feed: [FeedEntry] = []
    @State private var stories: [StoryGroup] = []
    @State private var memories: [MemoryItem] = []
    @State private var nextBefore: String?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    /// A load-more request failed (offline, server error). Shows a tappable
    /// retry row — the stalled last card never re-fires onAppear on its own.
    @State private var loadMoreFailed = false
    @State private var loadedOnce = false

    @State private var hypingIds: Set<String> = []
    @State private var termsAccepted: Bool?
    /// Transient "out of hypes" banner — the only hype failure worth surfacing.
    @State private var showHypeLimitBanner = false

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
    @State private var showAlreadySharedHint = false
    @State private var showMemories = false
    @State private var showWeeklyRecap = false
    @State private var profileUser: BackendUser?
    /// Tapped hype tally — presents the "who hyped this" sheet.
    @State private var hypersContext: HypersListContext?
    /// Profile tapped INSIDE the hypers sheet — presented after that sheet
    /// fully dismisses (sheet-over-sheet races drop the second presentation).
    @State private var pendingProfileUser: BackendUser?

    private var currentUserId: String? { UserDefaults.standard.string(forKey: "backendUserId") }
    /// Completing the daily mile unlocks posting AND viewing friends' stories.
    private var mileDone: Bool {
        ProgressCalculator.isGoalCompleted(
            current: healthManager.todaysDistance,
            goal: userManager.currentUser.goalMiles
        )
    }

    /// Workout ids of the user's own stories (fetched when the rail shows an
    /// own-story group) — a story share counts as that workout's one share.
    @State private var myStoryWorkoutIds: Set<String> = []

    /// Workout ids of today's walks/runs that already carry the user's
    /// DELIBERATE share — a photo post on the feed or a story. The auto
    /// route/stats card doesn't count (a photo can still replace it).
    private var mySharedWorkoutIds: Set<String> {
        var ids = Set(feed.compactMap { entry -> String? in
            guard entry.is_self, entry.isPost, entry.is_auto != true else { return nil }
            return entry.workout_id
        })
        ids.formUnion(myStoryWorkoutIds)
        return ids
    }

    /// The workout the composer should attach to: the LATEST of today's
    /// walks/runs without a deliberate share yet. One share per walk/run is
    /// the reward — every new workout unlocks another photo.
    private var nextShareableWorkoutId: String? {
        let shared = mySharedWorkoutIds
        return healthManager.todaysWorkouts
            .sorted { $0.startDate > $1.startDate }
            .first { !shared.contains($0.uuid.uuidString) }?
            .uuid.uuidString
    }

    /// True when there's nothing left to share right now: every one of today's
    /// walks/runs already has its photo post or story. Compose affordances
    /// hide until the user deletes a share or finishes another workout.
    private var alreadySharedWorkout: Bool {
        guard let uid = currentUserId else { return false }
        if healthManager.todaysWorkouts.isEmpty {
            // Mile met via non-workout distance — no per-workout key to dedupe
            // on, so keep the legacy one-share-per-day rule.
            let hasStoryToday = stories.contains { $0.user_id == uid && Self.isToday($0.latest_at) }
            let hasFeedPostToday = feed.contains {
                $0.is_self && $0.isPost && $0.is_auto != true && Self.isToday($0.sort_ts)
            }
            return hasStoryToday || hasFeedPostToday
        }
        return nextShareableWorkoutId == nil
    }

    private static func isToday(_ iso: String) -> Bool {
        guard let d = RelativeTime.date(from: iso) else { return false }
        return Calendar.current.isDateInToday(d)
    }

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
            // Link to the newest not-yet-shared workout so this post upserts
            // into that run's feed item — one post per run, and every new
            // walk/run in the day unlocks another photo.
            workoutId: mileDone ? (nextShareableWorkoutId ?? RunPostService.dailyMileWorkoutId()) : nil,
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
                        hasSharedWorkout: alreadySharedWorkout,
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
                                // Prefetch a few cards early (not just on the
                                // very last row) so the next page is usually
                                // there before the user reaches the bottom.
                                .onAppear {
                                    if feed.suffix(3).contains(where: { $0.id == entry.id }) {
                                        Task { await loadMore() }
                                    }
                                }
                                .padding(.horizontal, MADTheme.Spacing.md)
                        }
                        if isLoadingMore {
                            ProgressView().tint(.white).padding(.vertical, MADTheme.Spacing.md)
                        } else if loadMoreFailed, nextBefore != nil {
                            loadMoreRetryRow
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
        .overlay(alignment: .top) {
            if showHypeLimitBanner {
                hypeLimitBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
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
                UserProfileDetailView(user: user, friendService: profileFriendService)
            }
        }
        .sheet(item: $hypersContext, onDismiss: {
            if let pending = pendingProfileUser {
                pendingProfileUser = nil
                profileUser = pending
            }
        }) { context in
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
        .alert("Finish today's mile first", isPresented: $showMileHint) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Complete your daily mile to post and to see your friends' stories today. Keep going — you've got this! 🏃")
        }
        .alert("You've already shared this one", isPresented: $showAlreadySharedHint) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("One post per walk or run — that's the reward. Do another walk or run to share again, or delete a post or story to swap the shot.")
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
        let openHypers = {
            hypersContext = HypersListContext(
                contextType: entry.isPost ? "post" : "mile",
                contextId: entry.entryId,
                targetUserId: entry.user_id
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
                onTapAuthor: openProfile,
                onTapHypeCount: openHypers
            )
        } else {
            ActivityCardView(
                entry: entry,
                isHyping: hypingIds.contains(entry.id),
                onHype: { Task { await hype(entry) } },
                onTapAuthor: openProfile,
                onTapHypeCount: openHypers
            )
        }
    }

    /// The compose FAB. Hidden entirely once the mile is done AND already
    /// shared — one post per walk/run, so there's nothing to add. Still shows
    /// the lock state before the mile is finished.
    @ViewBuilder
    private var composeButton: some View {
        if !(mileDone && alreadySharedWorkout) {
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
        // Reachable from the rail's own-story cell even after the FAB hides —
        // enforce one-share-per-workout at the entry point too.
        guard !alreadySharedWorkout else { showAlreadySharedHint = true; return }
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
        // Own active stories carry their workout ids — needed to know which
        // of today's workouts are already "spent" on a story share.
        var storyWorkoutIds: Set<String> = []
        if let uid = currentUserId,
           storyGroups?.contains(where: { $0.user_id == uid }) == true,
           let ownStories = try? await PostService.fetchUserStories(userId: uid) {
            storyWorkoutIds = Set(ownStories.compactMap(\.workout_id))
        }
        await MainActor.run {
            if let feedResponse {
                feed = feedResponse.items
                nextBefore = feedResponse.next_before
                loadMoreFailed = false
            }
            if let storyGroups {
                stories = storyGroups
                myStoryWorkoutIds = storyWorkoutIds
            }
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

    /// Instagram-style infinite scroll: pages keep coming until the server
    /// says there's nothing older (`next_before == nil`). A page whose rows
    /// ALL dedupe away (fresh posts shifted the keyset boundary between
    /// requests) advances the cursor and immediately fetches again — an
    /// unchanged last row never re-fires onAppear, so stopping there would
    /// stall the feed with history still unloaded. A failed request surfaces
    /// the retry row instead of dying silently.
    private func loadMore() async {
        guard nextBefore != nil, !isLoadingMore else { return }
        await MainActor.run {
            isLoadingMore = true
            loadMoreFailed = false
        }
        while let before = nextBefore {
            guard let response = try? await PostService.fetchUnifiedFeed(before: before) else {
                await MainActor.run {
                    loadMoreFailed = true
                    isLoadingMore = false
                }
                return
            }
            let gotFresh: Bool = await MainActor.run {
                let existing = Set(feed.map(\.id))
                let fresh = response.items.filter { !existing.contains($0.id) }
                feed.append(contentsOf: fresh)
                nextBefore = response.next_before
                return !fresh.isEmpty
            }
            if gotFresh || nextBefore == nil { break }
        }
        await MainActor.run { isLoadingMore = false }
    }

    private var loadMoreRetryRow: some View {
        Button {
            Task { await loadMore() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .bold))
                Text("Couldn't load more — tap to retry")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white.opacity(0.7))
            .padding(.vertical, MADTheme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        } catch APIError.rateLimited {
            // Out of hypes for today — say so instead of silently doing
            // nothing after the double-tap burst played.
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showHypeLimitBanner = true
                }
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) { showHypeLimitBanner = false }
            }
        } catch {
            // conflict (already hyped) — leave as-is.
        }
    }

    private var hypeLimitBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hands.clap.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.orange)
            Text("You're out of hypes for today")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule()
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                .overlay(Capsule().strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        )
        .padding(.top, 8)
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
