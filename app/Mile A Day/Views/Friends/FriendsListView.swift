import SwiftUI

/// Top-level mode for the Friends tab: either the existing friends/requests
/// management UI, or the new global/friends leaderboard.
private enum FriendsTabMode: String, CaseIterable, Identifiable {
    case friends, leaderboard
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .friends: return "Friends"
        case .leaderboard: return "Leaderboard"
        }
    }
}

/// Main view for managing friends list
struct FriendsListView: View {
    @ObservedObject var friendService: FriendService
    @StateObject private var healthManager = HealthKitManager.shared
    @StateObject private var userManager = UserManager.shared
    @State private var topMode: FriendsTabMode = .friends
    @State private var showingSearch = false
    @State private var showingRequestsSheet = false
    @State private var showingCloseFriends = false
    @State private var selectedUser: BackendUser?
    // Profile to open once the requests sheet finishes dismissing. Presenting
    // from the sheet's onDismiss (instead of a fixed asyncAfter delay) avoids
    // the race where the new sheet is silently dropped because the old one is
    // still animating out.
    @State private var pendingProfileUser: BackendUser?
    @State private var showingUnfriendAlert = false
    @State private var userToUnfriend: BackendUser?

    // Nudge state. Statuses live on FriendService (published) so every refresh
    // path — including app-foreground and tab-switch refreshes that don't go
    // through this view — keeps the rows current.
    private var nudgeStatuses: [String: NudgeStatusResponse] { friendService.nudgeStatuses }
    @State private var nudgingFriendId: String?
    @State private var nudgeFeedback: NudgeFeedback?
    @State private var bellShakeIds: Set<String> = []
    @State private var bellAnimatedIds: Set<String> = []

    // Personal rank — fetched on appear so the hero card can show "#4 of 8 this week"
    // without coupling to the leaderboard view's state.
    @State private var myRankEntry: LeaderboardEntry?
    @State private var myRankTotal: Int = 0

    // "Today" tab — rolling-48h workout feed + inline hype state.
    @State private var feedItems: [FeedWorkoutItem] = []
    @State private var isLoadingFeed = false
    @State private var hasLoadedFeed = false
    @State private var hypesRemaining: Int?
    /// Admin/founder roles bypass the daily hype cap — pill shows ∞.
    @State private var hypesUnlimited = false
    @State private var hypingWorkoutIds: Set<String> = []
    // Rows the user has tapped open to reveal the duration/pace/calories/steps strip.
    @State private var expandedWorkoutIds: Set<String> = []
    // Double-tap-to-hype, mirroring the feed cards: per-row clap-burst trigger
    // plus a shared debounce so triple-taps don't fire two bursts.
    @State private var rowHypeBursts: [String: Int] = [:]
    @State private var lastDoubleTapAt = Date.distantPast

    // Shared namespace so a friend row can slide smoothly between
    // "Cheer Them On" and "Done Today" when their status flips.
    @Namespace private var friendRowNamespace

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                friendsHeader
                modePicker

                switch topMode {
                case .leaderboard:
                    LeaderboardSection(
                        friendService: friendService,
                        onAddFriends: { showingSearch = true }
                    )
                case .friends:
                    friendsHome
                }
            }

            // Toast floats above all content. zIndex keeps it on top, and the
            // safe-area padding lets it sit cleanly below the status bar
            // instead of overlapping the custom header.
            if let feedback = nudgeFeedback {
                nudgeFeedbackBanner(feedback)
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .toolbar(.hidden, for: .navigationBar)
        // Pushed, not presented as a sheet — keeps Find Friends inside the
        // tab's NavigationStack so there's no slide-down gesture involved
        // (the tab bar's stack is set up in MainTabView).
        .navigationDestination(isPresented: $showingSearch) {
            FriendSearchView(friendService: friendService)
        }
        .sheet(isPresented: $showingRequestsSheet, onDismiss: {
            if let user = pendingProfileUser {
                pendingProfileUser = nil
                selectedUser = user
            }
        }) {
            NavigationStack {
                FriendRequestsSheet(
                    friendService: friendService,
                    onSelectUser: { user in
                        pendingProfileUser = user
                        showingRequestsSheet = false
                    },
                    onAccept: handleAcceptRequest,
                    onDecline: handleDeclineRequest,
                    onCancel: handleCancelRequest
                )
            }
        }
        .sheet(item: $selectedUser) { user in
            NavigationStack {
                UserProfileDetailView(user: user, friendService: friendService)
            }
        }
        .sheet(isPresented: $showingCloseFriends) {
            NavigationStack {
                CloseFriendsListView(friendService: friendService)
            }
        }
        .task {
            if friendService.friends.isEmpty && friendService.friendRequests.isEmpty && friendService.sentRequests.isEmpty {
                await friendService.refreshAllData()
            }
            if MADNotificationService.shared.pendingNotificationType == "friend_request" {
                showingRequestsSheet = true
                MADNotificationService.shared.pendingNotificationType = nil
            }
            // Cold-launch profile link: the username was parked before this
            // view existed. (Warm launches arrive via the onReceive below.)
            if let pending = DeepLinkRouter.shared.pendingProfileUsername {
                openProfileFromDeepLink(username: pending)
            }
            await loadNudgeStatuses()
            await loadMyRank()
            await loadFeed()
        }
        .onReceive(DeepLinkRouter.shared.$pendingProfileUsername) { username in
            guard let username else { return }
            openProfileFromDeepLink(username: username)
        }
        .refreshable {
            // refreshAllData re-fetches nudge statuses internally.
            await friendService.refreshAllData()
            await loadMyRank()
            await loadFeed(force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .didTapPushNotification)) { notification in
            guard let type = notification.userInfo?["type"] as? String else { return }
            if type == "friend_request" {
                showingRequestsSheet = true
            }
        }
        .alert("Unfriend \(userToUnfriend?.displayName ?? "User")?", isPresented: $showingUnfriendAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Unfriend", role: .destructive) {
                if let user = userToUnfriend {
                    handleUnfriend(user)
                }
            }
        } message: {
            Text("You will no longer be friends with this person.")
        }
    }

    // MARK: - Custom header (title + search + requests-with-badge)

    private var friendsHeader: some View {
        // Matches MADTabHeader: center-aligned with a 26pt title so the icon
        // buttons sit level with the text on every tab.
        HStack(alignment: .center) {
            Text("Friends")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Spacer(minLength: MADTheme.Spacing.sm)

            HStack(spacing: 8) {
                headerCircleButton(systemImage: "magnifyingglass") {
                    showingSearch = true
                }
                headerCircleButton(systemImage: "star") {
                    showingCloseFriends = true
                }
                // Badge counts only incoming requests — sent ones aren't a
                // notification, they're just pending state the user already
                // knows about. Surfacing the sent count would over-alert.
                headerCircleButton(
                    systemImage: "person.crop.circle.badge.plus",
                    badgeCount: friendService.friendRequests.count
                ) {
                    showingRequestsSheet = true
                }
            }
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.top, MADTheme.Spacing.sm)
        .padding(.bottom, 4)
    }

    private func headerCircleButton(systemImage: String, badgeCount: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    )

                if badgeCount > 0 {
                    Text("\(min(badgeCount, 99))")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                        .overlay(Capsule().strokeBorder(Color.black, lineWidth: 1.5))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mode Picker (Friends vs Leaderboard)
    // Uses the shared MADPillPicker so this picker, the Compete sub-tabs,
    // and the Requests sheet picker all read with the same visual grammar.
    private var modePicker: some View {
        MADPillPicker(
            selection: $topMode,
            options: [
                .init(id: .friends, title: "Friends", systemImage: "person.2.fill"),
                .init(id: .leaderboard, title: "Leaderboard", systemImage: "trophy.fill")
            ]
        )
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.top, MADTheme.Spacing.sm)
        .padding(.bottom, MADTheme.Spacing.xs)
    }

    // MARK: - Friends Mode Body — hero card + split sections

    private var friendsHome: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.lg) {
                personalHeroCard

                if friendService.isLoading && friendService.friends.isEmpty {
                    friendsSkeletonList
                } else if friendService.friends.isEmpty {
                    FriendEmptyStateView(
                        title: "No Friends Yet",
                        message: "Start building your running community by adding friends!",
                        systemImage: "person.2",
                        actionTitle: "Add Friends",
                        action: { showingSearch = true }
                    )
                    .padding(.top, MADTheme.Spacing.lg)
                } else {
                    cheerThemOnSection
                    doneTodaySection
                }
            }
            // Spring animation triggers whenever nudge statuses or friend
            // count change — friends slide between Cheer/Done sections via
            // matchedGeometryEffect on each row.
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: nudgeStatuses)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: friendService.friends.count)
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.top, MADTheme.Spacing.md)
            .padding(.bottom, MADTheme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Today (rolling-48h workout feed + hypes)

    private var feedView: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.md) {
                if isLoadingFeed && feedItems.isEmpty {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))
                        .padding(.top, MADTheme.Spacing.xxl)
                } else if feedItems.isEmpty {
                    FriendEmptyStateView(
                        title: "No Activity Yet",
                        message: "When you and your friends log workouts, they'll show up here — give each other some hype 👏.",
                        systemImage: "hands.clap",
                        actionTitle: "Add Friends",
                        action: { showingSearch = true }
                    )
                    .padding(.top, MADTheme.Spacing.lg)
                } else {
                    hypesRemainingChip
                    ForEach(groupedFeed(), id: \.title) { group in
                        feedSectionHeader(group.title)
                        ForEach(group.items) { feedRow($0) }
                    }
                }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.top, MADTheme.Spacing.md)
            .padding(.bottom, MADTheme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    private var hypesRemainingChip: some View {
        HStack {
            Spacer()
            HypePill(remaining: hypesRemaining ?? HypeService.dailyLimit, unlimited: hypesUnlimited)
            Spacer()
        }
        .padding(.top, 2)
    }

    private func feedSectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.4))
            Spacer()
        }
        .padding(.top, MADTheme.Spacing.sm)
        .padding(.horizontal, 4)
    }

    private func feedRow(_ item: FeedWorkoutItem) -> some View {
        let expanded = expandedWorkoutIds.contains(item.workout_id)
        let completedMile = item.distance >= ProgressCalculator.dailyGoalTolerance

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Avatar opens the friend's profile.
                Button {
                    selectedUser = makeBackendUser(from: item)
                } label: {
                    AvatarView(name: item.displayName, imageURL: item.profile_image_url, size: 44)
                }
                .buttonStyle(.plain)

                // Tapping the body expands the row to reveal workout details.
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        if expanded { expandedWorkoutIds.remove(item.workout_id) }
                        else { expandedWorkoutIds.insert(item.workout_id) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(item.displayName)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if completedMile {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.green)
                            }
                        }
                        HStack(spacing: 5) {
                            Image(systemName: workoutIcon(item.workout_type))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(workoutColor(item.workout_type))
                            Text("\(workoutVerb(item.workout_type)) \(String(format: "%.2f", item.distance)) mi")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.8))
                            Text("· \(relativeTime(item.completed_at))")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.45))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.3))
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Trailing: social-proof tally + the hype action.
                HStack(spacing: 8) {
                    if let count = item.hype_count, count > 0 {
                        HypeTally(count: count)
                    }
                    if !item.is_self {
                        HypeButton(
                            isHyped: item.is_hyped,
                            isBusy: hypingWorkoutIds.contains(item.workout_id),
                            isOutOfHypes: !hypesUnlimited
                                && (hypesRemaining ?? HypeService.dailyLimit) <= 0
                                && !item.is_hyped
                        ) {
                            // Same clap burst as double-tapping the row — the
                            // button and the gesture feel identical (and match
                            // the feed cards' behavior).
                            rowHypeBursts[item.workout_id, default: 0] += 1
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            Task { await sendHype(for: item) }
                        }
                    }
                }
            }
            .padding(12)

            if expanded {
                workoutDetailStrip(item)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(completedMile ? Color.green.opacity(0.06) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(completedMile ? Color.green.opacity(0.18) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        // Double-tap anywhere on the row hypes, same as double-tapping a feed
        // card. simultaneousGesture so the avatar/expand buttons keep working.
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { doubleTapHype(item) }
        )
        .overlay(
            HypeBurstView(trigger: rowHypeBursts[item.workout_id] ?? 0)
                .scaleEffect(0.55) // full-size burst overwhelms a compact row
        )
    }

    /// Inline stats revealed when a feed row is tapped open: time, pace,
    /// calories, and (when present) steps. Pulled straight from the feed
    /// payload so there's no extra fetch.
    private func workoutDetailStrip(_ item: FeedWorkoutItem) -> some View {
        HStack(spacing: 8) {
            detailStat(icon: "clock.fill", value: item.durationText, label: "Time")
            detailStat(icon: "speedometer", value: item.paceText, label: "Min/Mi")
            detailStat(icon: "flame.fill", value: item.caloriesText, label: "Cal")
            if let steps = item.stepsText {
                detailStat(icon: "shoeprints.fill", value: steps, label: "Steps")
            }
        }
    }

    private func detailStat(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(0.65))
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func makeBackendUser(from item: FeedWorkoutItem) -> BackendUser {
        BackendUser(
            user_id: item.user_id,
            username: item.username,
            email: nil,
            first_name: item.first_name,
            last_name: item.last_name,
            bio: nil,
            profile_image_url: item.profile_image_url,
            apple_id: nil,
            auth_provider: nil,
            role: nil
        )
    }

    // MARK: Feed helpers

    private struct FeedGroup { let title: String; let items: [FeedWorkoutItem] }

    private func groupedFeed() -> [FeedGroup] {
        let cal = Calendar.current
        var today: [FeedWorkoutItem] = []
        var yesterday: [FeedWorkoutItem] = []
        var earlier: [FeedWorkoutItem] = []
        for item in feedItems {
            guard let date = parseFeedDate(item.completed_at) else { earlier.append(item); continue }
            if cal.isDateInToday(date) { today.append(item) }
            else if cal.isDateInYesterday(date) { yesterday.append(item) }
            else { earlier.append(item) }
        }
        var groups: [FeedGroup] = []
        if !today.isEmpty { groups.append(FeedGroup(title: "TODAY", items: today)) }
        if !yesterday.isEmpty { groups.append(FeedGroup(title: "YESTERDAY", items: yesterday)) }
        if !earlier.isEmpty { groups.append(FeedGroup(title: "EARLIER", items: earlier)) }
        return groups
    }

    private func parseFeedDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        if let d = f.date(from: s) { return d }
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f.date(from: s)
    }

    private func relativeTime(_ s: String) -> String {
        guard let date = parseFeedDate(s) else { return "" }
        let secs = Date().timeIntervalSince(date)
        if secs < 60 { return "just now" }
        if secs < 3600 { return "\(Int(secs / 60))m ago" }
        if secs < 6 * 3600 { return "\(Int(secs / 3600))h ago" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private func workoutVerb(_ type: String) -> String {
        switch type.lowercased() {
        case "running": return "ran"
        case "walking": return "walked"
        case "cycling": return "biked"
        case "hiking": return "hiked"
        default: return "logged"
        }
    }

    private func workoutIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "cycling": return "figure.outdoor.cycle"
        case "hiking": return "figure.hiking"
        default: return "figure.run"
        }
    }

    private func workoutColor(_ type: String) -> Color {
        MADTheme.workoutColor(type)
    }

    /// Double-tap on a row = hype, mirroring the feed cards: clap burst +
    /// haptic play every time (celebration is free), the hype itself only
    /// fires when the row isn't already hyped.
    private func doubleTapHype(_ item: FeedWorkoutItem) {
        guard !item.is_self else { return }
        let now = Date()
        guard now.timeIntervalSince(lastDoubleTapAt) > 0.35 else { return }
        lastDoubleTapAt = now

        rowHypeBursts[item.workout_id, default: 0] += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if !item.is_hyped {
            Task { await sendHype(for: item) }
        }
    }

    private func sendHype(for item: FeedWorkoutItem) async {
        guard !item.is_hyped, !hypingWorkoutIds.contains(item.workout_id) else { return }
        hypingWorkoutIds.insert(item.workout_id)
        defer { hypingWorkoutIds.remove(item.workout_id) }

        // Optimistic, like the feed cards: flip the row + bump the tally
        // immediately so double-tap feels instant, reconcile on failure.
        setHyped(item.workout_id, hyped: true, countDelta: 1)

        let label = "\(workoutVerb(item.workout_type)) \(String(format: "%.2f", item.distance)) mi"
        let context = HypeContext(contextType: "mile", contextId: item.workout_id, contextLabel: label)
        do {
            let response = try await HypeService.sendHype(targetUserId: item.user_id, context: context)
            hypesRemaining = response.hypes_remaining
            hypesUnlimited = response.unlimited ?? hypesUnlimited
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch let error as APIError {
            switch error {
            case .conflict:
                // Already hyped this workout server-side — keep the hyped
                // state but undo the optimistic bump (the server's count
                // already includes this one).
                setHyped(item.workout_id, hyped: true, countDelta: -1)
            case .rateLimited:
                setHyped(item.workout_id, hyped: false, countDelta: -1)
                hypesRemaining = 0
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            default:
                setHyped(item.workout_id, hyped: false, countDelta: -1)
                print("[FriendsListView] hype failed: \(error)")
            }
        } catch {
            setHyped(item.workout_id, hyped: false, countDelta: -1)
            print("[FriendsListView] hype failed: \(error)")
        }
    }

    private func setHyped(_ workoutId: String, hyped: Bool, countDelta: Int) {
        guard let idx = feedItems.firstIndex(where: { $0.workout_id == workoutId }) else { return }
        feedItems[idx].is_hyped = hyped
        feedItems[idx].hype_count = max((feedItems[idx].hype_count ?? 0) + countDelta, 0)
    }

    private func loadFeed(force: Bool = false) async {
        if hasLoadedFeed && !force { return }
        isLoadingFeed = true
        do {
            feedItems = try await friendService.fetchFriendsFeed()
        } catch {
            print("[FriendsListView] feed load failed: \(error)")
        }
        if let status = try? await HypeService.status() {
            hypesRemaining = status.hypes_remaining
            hypesUnlimited = status.unlimited ?? false
        }
        isLoadingFeed = false
        hasLoadedFeed = true
    }

    // MARK: Personal hero card

    /// Top card showing the user's own progress + streak + rank. Tapping it
    /// jumps to the Leaderboard mode so they can see the full standings.
    private var personalHeroCard: some View {
        let goal = max(userManager.currentUser.goalMiles, 0.01)
        let today = healthManager.todaysDistance
        let progress = min(today / goal, 1.0)
        let isComplete = today >= goal
        let streak = userManager.currentUser.streak
        // Streak-saver: active streak + not done + past 9pm = visual escalation.
        // Pulls the card toward red to signal genuine risk of losing the streak.
        let hour = Calendar.current.component(.hour, from: Date())
        let streakInDanger = streak > 0 && !isComplete && hour >= 21

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                topMode = .leaderboard
            }
        } label: {
            HStack(spacing: MADTheme.Spacing.md) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 5)
                        .frame(width: 78, height: 78)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            isComplete ? Color.green : MADTheme.Colors.madRed,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 78, height: 78)
                    VStack(spacing: 0) {
                        Text(String(format: today >= 10 ? "%.1f" : "%.2f", today))
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("mi today")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(heroHeadline(isComplete: isComplete))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(heroHeadlineColor(isComplete: isComplete))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if streak > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.orange)
                                Text("\(streak)")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    Text(heroSubtitle(isComplete: isComplete))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(streakInDanger ? MADTheme.Colors.madRed.opacity(0.10) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .strokeBorder(
                                streakInDanger ? MADTheme.Colors.madRed.opacity(0.5) : Color.white.opacity(0.08),
                                lineWidth: streakInDanger ? 1.5 : 1
                            )
                    )
                    .shadow(color: streakInDanger ? MADTheme.Colors.madRed.opacity(0.25) : .clear, radius: 12, y: 4)
            )
            .overlay(alignment: .topTrailing) {
                if streakInDanger {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("STREAK AT RISK")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(MADTheme.Colors.madRed))
                    .offset(x: -10, y: -8)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Time-aware headline. Communicates urgency as the day winds down so
    /// users get a gentle reminder before midnight risks the streak.
    private func heroHeadline(isComplete: Bool) -> String {
        if isComplete { return "You're on a roll" }
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Halfway through"
        case 17..<20: return "Strong finish"
        default: return "Time's running short"   // 20:00–04:59 — late or pre-dawn
        }
    }

    /// Red headline when the day is nearly over and the mile isn't done —
    /// reinforces the urgency in the copy.
    private func heroHeadlineColor(isComplete: Bool) -> Color {
        if isComplete { return .white }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 20 ? .orange : .white
    }

    private func heroSubtitle(isComplete: Bool) -> String {
        if let entry = myRankEntry {
            let prefix = isComplete ? "Goal complete" : "Keep going"
            return "\(prefix) · Ranked #\(entry.rank) this week"
        }
        return isComplete ? "Goal complete · Tap to see the leaderboard" : "Tap to see the leaderboard"
    }

    // MARK: Split sections

    private var incompleteFriends: [BackendUser] {
        friendService.friends
            .filter { friend in
                !(nudgeStatuses[friend.user_id]?.has_completed_mile ?? false)
            }
            // Sort by progress descending so the closest-to-done friends bubble
            // to the top — they're the most satisfying to nudge.
            .sorted { lhs, rhs in
                let lhsMi = nudgeStatuses[lhs.user_id]?.today_miles ?? 0
                let rhsMi = nudgeStatuses[rhs.user_id]?.today_miles ?? 0
                return lhsMi > rhsMi
            }
    }

    private var completedFriends: [BackendUser] {
        friendService.friends
            .filter { friend in
                nudgeStatuses[friend.user_id]?.has_completed_mile ?? false
            }
            // Highest miles first — rewards the day's top performers with
            // visibility at the top of the section.
            .sorted { lhs, rhs in
                let lhsMi = nudgeStatuses[lhs.user_id]?.today_miles ?? 0
                let rhsMi = nudgeStatuses[rhs.user_id]?.today_miles ?? 0
                return lhsMi > rhsMi
            }
    }

    @ViewBuilder
    private var cheerThemOnSection: some View {
        let incomplete = incompleteFriends
        if !incomplete.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                sectionHeader(
                    title: "CHEER THEM ON",
                    trailing: ""
                )
                VStack(spacing: 6) {
                    ForEach(incomplete) { friend in
                        friendRowCompact(friend: friend, isCompleted: false)
                    }
                }
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                        )
                )
            }
        } else if !friendService.friends.isEmpty {
            // Celebratory state — everyone in the friend group has crushed
            // their mile today. Shown only after data has loaded (`friends`
            // non-empty) so it doesn't flicker before the nudge statuses arrive.
            allDoneCelebration
        }
    }

    /// Friendly empty state for "Cheer Them On" when every friend has hit
    /// their goal — rewards the user with a moment of group accomplishment
    /// rather than an empty section.
    private var allDoneCelebration: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.green)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.green.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Everyone's crushed it today")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("All \(friendService.friends.count) friends hit their goal.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(Color.green.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var doneTodaySection: some View {
        let complete = completedFriends
        if !complete.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                sectionHeader(
                    title: "DONE TODAY",
                    trailing: "\(complete.count) of \(friendService.friends.count)"
                )
                VStack(spacing: 6) {
                    ForEach(complete) { friend in
                        friendRowCompact(friend: friend, isCompleted: true)
                    }
                }
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                        )
                )
            }
        }
    }

    private func sectionHeader(title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.4))
            Spacer()
            Text(trailing)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 4)
    }

    // MARK: Compact friend row (ring avatar)

    /// One unified row used in both sections — appearance and trailing action
    /// flip based on `isCompleted`. The progress ring color also adapts:
    /// green when done, accent when in-progress.
    private func friendRowCompact(friend: BackendUser, isCompleted: Bool) -> some View {
        let status = nudgeStatuses[friend.user_id]
        let alreadyNudged = status?.nudgedToday ?? false
        let canRenudge = status?.unlimitedNudges ?? false
        let todayMiles = status?.today_miles ?? 0
        let goalMiles: Double = 1.0
        let progress = min(todayMiles / goalMiles, 1.0)

        // Two sibling buttons in a single HStack — NOT nested. Previously
        // the Nudge button lived inside the row's outer Button label, which
        // caused SwiftUI's gesture system to ambiguously route the first
        // tap between them. Splitting them as siblings means each has its
        // own discrete hit area; first tap on the row opens the profile,
        // first tap on the nudge button sends the nudge.
        return HStack(spacing: 0) {
            Button {
                selectedUser = friend
            } label: {
                tappableRowContent(
                    friend: friend,
                    isCompleted: isCompleted,
                    status: status,
                    todayMiles: todayMiles,
                    goalMiles: goalMiles,
                    progress: progress
                )
            }
            .buttonStyle(.plain)

            if !isCompleted {
                nudgeButton(friend: friend, alreadyNudged: alreadyNudged, canRenudge: canRenudge)
                    .padding(.trailing, MADTheme.Spacing.md)
            }
        }
        // Shared identity across sections so a friend moving from Cheer →
        // Done (or vice versa) slides instead of fade-popping.
        .matchedGeometryEffect(id: friend.user_id, in: friendRowNamespace)
    }

    /// Just the visual content of a friend row — avatar + name + subtitle +
    /// chevron-when-completed. Nudge button is rendered separately as a
    /// sibling so it doesn't compete with the row's open-profile tap.
    @ViewBuilder
    private func tappableRowContent(friend: BackendUser, isCompleted: Bool, status: NudgeStatusResponse?, todayMiles: Double, goalMiles: Double, progress: Double) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            AvatarWithRing(
                name: friend.displayName,
                imageURL: friend.profile_image_url,
                progress: progress,
                size: 52,
                ringWidth: 3,
                accent: .orange,
                badge: isCompleted ? .check : nil
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(friend.username ?? friend.displayName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let streak = status?.current_streak, streak > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(streak)")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                        }
                        .foregroundColor(.orange)
                    }
                    // Shared "friend streak" — days you BOTH completed in a row.
                    // A bordered pill in a distinct pink-red so it never reads as
                    // the friend's own (orange) streak next to it.
                    if let shared = friendService.sharedStreaks[friend.user_id], shared > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(shared)")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.5, blue: 0.7), MADTheme.Colors.madRed],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                    }
                }

                Text(rowSubtitle(isCompleted: isCompleted, todayMiles: todayMiles, goal: goalMiles))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isCompleted {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.trailing, 4)
            }
        }
        .padding(.leading, MADTheme.Spacing.md)
        .padding(.trailing, MADTheme.Spacing.sm)
        .padding(.vertical, 10)
        // Claim the whole padded area as the tap target — without this,
        // gaps between the avatar/name/spacer can swallow taps.
        .contentShape(Rectangle())
    }

    private func rowSubtitle(isCompleted: Bool, todayMiles: Double, goal: Double) -> String {
        if isCompleted {
            return String(format: "Goal complete · %.2f mi today", todayMiles)
        }
        let percent = Int((min(todayMiles / goal, 1.0)) * 100)
        return String(format: "%.2f / %.0f mi · %d%%", todayMiles, goal, percent)
    }

    // MARK: Personal rank fetch

    /// Reads the viewer's rank within their friend group for THIS week.
    /// Used by the hero card subtitle. Silently no-ops on failure — the card
    /// just falls back to a generic subtitle.
    private func loadMyRank() async {
        do {
            let page = try await LeaderboardService.fetch(
                metric: .milesRan,
                period: .week,
                limit: 1,
                offset: 0
            )
            await MainActor.run {
                self.myRankEntry = page.current_user_entry
                self.myRankTotal = page.total_count
            }
        } catch {
            // Hero card subtitle silently falls back — no UI noise required.
            print("[FriendsList] loadMyRank failed: \(error)")
        }
    }

    // MARK: - Nudge Button (only shown when friend hasn't completed goal)
    /// `canRenudge` (unlimited-nudge roles): an already-nudged friend shows an
    /// ENABLED "Nudge again" pill — visibly different from the fresh "Nudge",
    /// so the sender knows one already went out today before sending another.
    private func nudgeButton(friend: BackendUser, alreadyNudged: Bool, canRenudge: Bool = false) -> some View {
        Group {
            if alreadyNudged && canRenudge {
                Button {
                    handleNudge(friend)
                } label: {
                    HStack(spacing: 4) {
                        if nudgingFriendId == friend.user_id {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.orange)
                        } else {
                            Image(systemName: "bell.and.waves.left.and.right.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Nudge again")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                    }
                    .foregroundColor(.orange.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.orange.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                            )
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(nudgingFriendId != nil)
            } else if alreadyNudged {
                HStack(spacing: 4) {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 10))
                    Text("Nudged")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.25))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.04))
                )
            } else {
                Button {
                    handleNudge(friend)
                } label: {
                    HStack(spacing: 4) {
                        if nudgingFriendId == friend.user_id {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.orange)
                        } else {
                            Image(systemName: "bell.badge")
                                .font(.system(size: 10, weight: .semibold))
                                .modifier(BellShakeModifier(isShaking: bellShakeIds.contains(friend.user_id)))
                            Text("Nudge")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(nudgingFriendId != nil)
                .onAppear {
                    guard !bellAnimatedIds.contains(friend.user_id) else { return }
                    bellAnimatedIds.insert(friend.user_id)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        _ = withAnimation(.easeInOut(duration: 0.6)) {
                            bellShakeIds.insert(friend.user_id)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            bellShakeIds.remove(friend.user_id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Nudge Feedback Banner
    /// Substantial floating card so it's clearly visible even when stacked
    /// over other tab content. Uses a colored leading stripe + ultraThinMaterial
    /// backdrop so it reads as a system toast rather than blending into the
    /// scroll content.
    private func nudgeFeedbackBanner(_ feedback: NudgeFeedback) -> some View {
        let accent: Color = feedback.isError ? .red : .green

        return HStack(spacing: MADTheme.Spacing.sm) {
            // Constrain stripe height — `Rectangle()` is greedy and will
            // grow to fill the parent's available height (which was the
            // entire screen when this lived in an .overlay). Locking
            // height to 28pt matches the icon disc next to it.
            Rectangle()
                .fill(accent)
                .frame(width: 4, height: 28)
                .cornerRadius(2)

            Image(systemName: feedback.icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(accent.opacity(0.18)))

            Text(feedback.message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(2)

            Spacer(minLength: 4)
        }
        .padding(.leading, 6)
        .padding(.trailing, MADTheme.Spacing.md)
        .padding(.vertical, MADTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        )
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))

            Text("Loading...")
                .font(MADTheme.Typography.body)
                .foregroundColor(MADTheme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Skeleton Loader
    /// Placeholder rows shown while friend data is loading. Perceived
    /// performance > spinner-on-blank-screen — users see the eventual layout
    /// shape immediately, which makes the wait feel shorter.
    private var friendsSkeletonList: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            VStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in skeletonRow() }
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                            .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
        }
    }

    private func skeletonRow() -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 52, height: 52)
                .shimmer()

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 110, height: 12)
                    .shimmer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 160, height: 10)
                    .shimmer()
            }

            Spacer(minLength: 4)

            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(width: 64, height: 26)
                .shimmer()
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, 10)
    }

    // MARK: - Deep Link Profile Open

    /// Resolves a username from a mileaday.run/u/<username> link to a
    /// BackendUser and presents their profile (which carries the Add Friend
    /// button). Clears the pending value first so the onReceive re-fire
    /// with nil is a no-op and repeat links still work.
    private func openProfileFromDeepLink(username: String) {
        DeepLinkRouter.shared.pendingProfileUsername = nil
        Task {
            do {
                let matches = try await friendService.searchUsers(byUsername: username)
                // The search endpoint is a substring match — prefer the exact
                // username, fall back to the first hit.
                let user = matches.first(where: { $0.username?.lowercased() == username.lowercased() })
                    ?? matches.first
                if let user {
                    await MainActor.run {
                        selectedUser = user
                    }
                }
            } catch {
                print("[FriendsList] ❌ Deep link profile lookup failed for '\(username)': \(error)")
            }
        }
    }

    // MARK: - Nudge Methods
    private func loadNudgeStatuses() async {
        await friendService.refreshNudgeStatuses()
    }

    private func handleNudge(_ friend: BackendUser) {
        nudgingFriendId = friend.user_id
        Task {
            do {
                try await friendService.nudgeFriend(friend.user_id)
                await MainActor.run {
                    nudgingFriendId = nil
                    FlexNudgeTracker.markFriendNudgeSent(friendId: friend.user_id)
                    // Optimistic update on the shared service state — preserve existing miles/completion.
                    // Unlimited nudgers keep can_nudge so "Nudge again" stays available.
                    let existing = friendService.nudgeStatuses[friend.user_id]
                    let unlimited = existing?.unlimitedNudges ?? false
                    friendService.nudgeStatuses[friend.user_id] = NudgeStatusResponse(
                        can_nudge: unlimited,
                        has_completed_mile: existing?.has_completed_mile ?? false,
                        already_nudged_today: !unlimited,
                        today_miles: existing?.today_miles,
                        current_streak: existing?.current_streak,
                        has_nudged_today: true,
                        unlimited_nudges: existing?.unlimited_nudges
                    )
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showNudgeFeedback(NudgeFeedback(
                        icon: "bell.badge.fill",
                        message: "Nudge sent to \(friend.displayName)!",
                        isError: false
                    ))
                }
            } catch {
                print("[FriendsList] ❌ Nudge failed: \(error)")
                await MainActor.run {
                    nudgingFriendId = nil
                    showNudgeFeedback(NudgeFeedback(
                        icon: "xmark.circle",
                        message: error.localizedDescription,
                        isError: true
                    ))
                }
            }
        }
    }

    private func showNudgeFeedback(_ feedback: NudgeFeedback) {
        withAnimation(.easeInOut(duration: 0.2)) { nudgeFeedback = feedback }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.2)) { nudgeFeedback = nil }
        }
    }

    // MARK: - Helper Methods
    private func handleAcceptRequest(_ user: BackendUser) {
        Task {
            do {
                try await friendService.acceptFriendRequest(from: user)
            } catch {
                // Handle error
            }
        }
    }

    private func handleDeclineRequest(_ user: BackendUser) {
        Task {
            do {
                try await friendService.declineFriendRequest(from: user)
            } catch {
                // Handle error
            }
        }
    }

    private func handleCancelRequest(_ user: BackendUser) {
        Task {
            do {
                try await friendService.cancelFriendRequest(to: user)
            } catch {
                // Handle error
            }
        }
    }

    private func handleUnfriend(_ user: BackendUser) {
        Task {
            do {
                try await friendService.removeFriend(user)
            } catch {
                // Handle error
            }
        }
    }

}

// MARK: - Nudge Feedback Model
// Internal (not `private`) because UserProfileDetailView uses the same
// type for its nudge confirmation toast — both surfaces share visual treatment.
struct NudgeFeedback: Equatable {
    let icon: String
    let message: String
    let isError: Bool
}

// MARK: - Bell Shake Animation Modifier
struct BellShakeModifier: ViewModifier {
    var isShaking: Bool

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isShaking ? -15 : 0), anchor: .top)
            .animation(
                isShaking
                    ? .easeInOut(duration: 0.1).repeatCount(5, autoreverses: true)
                    : .default,
                value: isShaking
            )
    }
}

// MARK: - Preview
struct FriendsListView_Previews: PreviewProvider {
    static var previews: some View {
        FriendsListView(friendService: FriendService())
    }
}
