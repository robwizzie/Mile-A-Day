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
    @Environment(\.duoSpread) private var duoSpread
    @ObservedObject var friendService: FriendService
    @StateObject private var healthManager = HealthKitManager.shared
    /// Live presence for the "Out right now" section. Shared singleton, so the
    /// dashboard's prefetch has usually already populated it by the time this
    /// tab is opened.
    @ObservedObject private var buddy = BuddySessionService.shared
    @StateObject private var userManager = UserManager.shared
    @State private var topMode: FriendsTabMode = .friends
    @State private var showingSearch = false
    @State private var showingRequestsSheet = false
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

    // Shared namespace so a friend row can slide smoothly between
    // "Cheer Them On" and "Done Today" when their status flips.
    @Namespace private var friendRowNamespace

    // Streak Assist: rescuable friends + per-row send state (server-gated;
    // the rescuable list is empty until streak features are live). The CTA
    // lives ON the friend's row, in the nudge/action slot.
    @ObservedObject private var tokensState = StreakTokensState.shared
    /// Friends saved in this session — the row keeps its confirmation chip
    /// instead of snapping back to a nudge the moment the status refreshes.
    @State private var savedFriendIds: Set<String> = []

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                friendsHeader
                    .tourAnchor("friends.header")
                if usesTwoPages {
                    DuoTwoPages(leftTitle: "Today", rightTitle: "Leaderboard") {
                        friendsHome
                    } right: {
                        leaderboard
                    }
                } else {
                    modePicker

                    switch topMode {
                    case .leaderboard:
                        leaderboard
                    case .friends:
                        friendsHome
                    }
                }
            }

            // Toast floats above all content. zIndex keeps it on top, and the
            // safe-area padding lets it sit cleanly below the status bar
            // instead of overlapping the custom header.
            if let feedback = nudgeFeedback {
                NudgeToast(feedback: feedback)
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }

        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .madTypeCap(.madCardCap)
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
        .task {
            // Parked intents first: they're synchronous state reads, so there
            // is no reason to make a deep-linked sheet wait behind the network
            // work below.
            if MADNotificationService.shared.pendingNotificationType == "friend_request" {
                showingRequestsSheet = true
                MADNotificationService.shared.pendingNotificationType = nil
            }
            // Cold path for in-app entry points (Dashboard attention row,
            // notification-inbox row): the flag was parked before this view
            // existed. The onReceive below covers the already-mounted case.
            if DeepLinkRouter.shared.pendingOpenFriendRequests {
                showingRequestsSheet = true
                DeepLinkRouter.shared.pendingOpenFriendRequests = false
            }
            // Cold-launch profile link: the username was parked before this
            // view existed. (Warm launches arrive via the onReceive below.)
            if let pending = DeepLinkRouter.shared.pendingProfileUsername {
                openProfileFromDeepLink(username: pending)
            }
            await refreshAll(force: false)
        }
        .onReceive(DeepLinkRouter.shared.$pendingProfileUsername) { username in
            guard let username else { return }
            openProfileFromDeepLink(username: username)
        }
        // Warm path for the parked open-requests intent (see .task above).
        .onReceive(DeepLinkRouter.shared.$pendingOpenFriendRequests) { shouldOpen in
            guard shouldOpen else { return }
            showingRequestsSheet = true
            DeepLinkRouter.shared.pendingOpenFriendRequests = false
        }
        .refreshable {
            await refreshAll(force: true)
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

    // MARK: - Refresh

    /// Everything this tab renders, in one place.
    ///
    /// `.task` and `.refreshable` had drifted into two different subsets: the
    /// pull re-fetched the friend graph and nothing else, so the hero card's own
    /// miles/streak and every Streak Assist CTA stayed frozen until the user
    /// happened to visit the Dashboard (whose onAppear refreshes HealthKit and
    /// the backend stats) and come back — which is why a tab round-trip looked
    /// like a better refresh than the refresh gesture. One function, both
    /// callers; add new page data here and both paths get it.
    ///
    /// `force` is the pull: it re-fetches the friend graph and the activity feed
    /// unconditionally, where opening the tab keeps the existing "only if we
    /// have nothing yet" guards so a tab switch doesn't re-run what the
    /// Dashboard just loaded.
    private func refreshAll(force: Bool) async {
        // The hero card is the top of this page and shows the VIEWER's own
        // numbers — today's miles straight off HealthKit, the streak off the
        // backend. Nothing else on this tab fetches either.
        healthManager.fetchTodaysDistance()

        // The groups below share no inputs, so they run side by side — run
        // one after another, the page waited on six round-trips in a row.
        // Only stats → tokens keeps its order (see below).

        // Presence is the one thing on this screen that is only true for the
        // next few minutes, so it is always re-pulled rather than trusted from
        // whenever the dashboard last looked.
        async let presence: Void = buddy.refreshFriendsOutNow()

        async let graph: Void = refreshFriendGraph(force: force)

        async let selfStats: Void = {
            // Streak (raise-only) + fastest pace + the gated tokens payload.
            await SelfStatsRefresher.refreshBackendStats(userManager: userManager)
            // Rescuable friends + meters (no-op {active:false} until the server
            // enables streak features for this user). Runs after the stats call so
            // the fuller of the two payloads is the one that lands last.
            await tokensState.refreshStatus()
        }()
        _ = await (presence, graph, selfStats)
    }

    private func refreshFriendGraph(force: Bool) async {
        if force || (friendService.friends.isEmpty && friendService.friendRequests.isEmpty && friendService.sentRequests.isEmpty) {
            // refreshAllData re-fetches nudge statuses internally.
            await friendService.refreshAllData()
        } else {
            // Friend rows still need fresh today-miles/completion even when the
            // list itself is already loaded.
            await loadNudgeStatuses()
        }
    }

    // MARK: - Streak Assist (in-row rescue)

    /// The donation for this friend, if one is open: they're holding an Assist
    /// with a day in play, and I haven't already offered them a mile.
    ///
    /// Shaped into the same payload the profile CTA fetches per friend, so both
    /// surfaces render one component with one confirmation. This list already
    /// has every candidate from the single status call — handing it down keeps
    /// a long friends list at zero extra requests.
    ///
    /// The list is no longer gated on ME holding a token (the friend's token is
    /// what pays now), so it's gated on my spare miles instead: with none left
    /// the row still renders, locked, saying how much further to run.
    private func assistRescue(for friend: BackendUser) -> FriendRescueStatus? {
        guard !savedFriendIds.contains(friend.user_id) else { return nil }
        guard let rescue = tokensState.assistableFriends.first(where: { $0.user_id == friend.user_id })
        else { return nil }
        let budget = tokensState.donationBudget
        let outOfMiles = (budget?.remaining ?? 0) < 1
        return FriendRescueStatus(
            available: !rescue.alreadyOffered && !outOfMiles,
            target_date: rescue.target_date,
            target_kind: rescue.target_kind,
            prior_streak: rescue.prior_streak,
            restored_streak: rescue.restored_streak,
            self_recovery: nil,
            friend_holds_assist: true,
            viewer_budget: budget,
            offer_status: rescue.offer_status,
            offer_id: rescue.offer_id,
            reason: rescue.alreadyOffered ? nil : (outOfMiles ? "no_miles" : nil)
        )
    }

    /// Post-offer confirmation chip in the same slot. "Offered", not "Saved" —
    /// the friend still has to spend their token to take the mile.
    private var savedChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "paperplane.fill")
                .madFont(size: 11, weight: .bold, maxScale: 1.5)
            Text("Mile offered")
                .madFont(size: 11, weight: .heavy, design: .rounded)
        }
        .foregroundColor(.green)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.green.opacity(0.14)))
    }

    // MARK: - Custom header (title + search + requests-with-badge)

    private var friendsHeader: some View {
        // Matches MADTabHeader: center-aligned with a 26pt title so the icon
        // buttons sit level with the text on every tab.
        HStack(alignment: .center) {
            Text("Friends")
                .madFont(size: 26, weight: .heavy, design: .rounded)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Spacer(minLength: MADTheme.Spacing.sm)

            NavigationLink(destination: ReferralsView()) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .accessibilityLabel("Invite friends and rewards")
            }
            .buttonStyle(.plain)

            // ONE labelled action. Three unlabelled rimmed circles (search /
            // close friends / requests) used to sit here: requests are now a
            // row at the top of the list when there are any, and Close
            // Friends lives in Settings › Privacy and on each friend's •••.
            Button {
                MADHaptics.tap()
                showingSearch = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "person.badge.plus")
                        .madFont(size: 13, weight: .bold, maxScale: 1.5)
                        .accessibilityHidden(true)
                    Text("Add friends")
                        .madFont(size: 14, weight: .bold, design: .rounded)
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.top, MADTheme.Spacing.sm)
        .padding(.bottom, 4)
    }

    // MARK: - Pending requests row

    /// "2 friend requests" at the top of the list, only while there is
    /// something pending. Incoming requests lead (they need an answer);
    /// with none, requests you sent show quietly so they stay reachable.
    @ViewBuilder
    private var pendingRequestsRow: some View {
        let incoming = friendService.friendRequests.count
        let sent = friendService.sentRequests.count
        if incoming > 0 || sent > 0 {
            Button {
                MADHaptics.tap()
                showingRequestsSheet = true
            } label: {
                HStack(spacing: 10) {
                    Text(incoming > 0
                         ? (incoming == 1 ? "1 friend request" : "\(incoming) friend requests")
                         : (sent == 1 ? "1 request sent" : "\(sent) requests sent"))
                        .madFont(size: 15, weight: .bold, design: .rounded)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if incoming > 0 {
                        Text("Review")
                            .madFont(size: 13, weight: .bold, design: .rounded)
                            .foregroundColor(MADTheme.Colors.madRed)
                    }
                    Image(systemName: "chevron.right")
                        .madFont(size: 12, weight: .bold, maxScale: 1.5)
                        .foregroundColor(.white.opacity(0.35))
                        .accessibilityHidden(true)
                }
                .padding(DashboardCardSurface.padding)
                .background(DashboardCardSurface(style: .fun))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Mode Picker (Friends vs Leaderboard)
    // Uses the shared MADPillPicker so this picker, the Compete sub-tabs,
    // and the Requests sheet picker all read with the same visual grammar.
    /// With no friends yet there is only one thing to say: find some.
    private var usesTwoPages: Bool { duoSpread && !friendService.friends.isEmpty }

    private var leaderboard: some View {
        LeaderboardSection(
            friendService: friendService,
            onAddFriends: { showingSearch = true }
        )
    }

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

    // MARK: - Friends Mode Body — split sections

    private var friendsHome: some View {
        ScrollView {
            // Lazy so the Done Today section (and its rows' avatars/rings) isn't
            // built until it nears the screen. The rows themselves stay grouped
            // in each section's card, which is what draws its background.
            // No "your day" hero up top: the Dashboard owns your own day and
            // the Leaderboard mode owns rank — this list is about friends.
            LazyVStack(spacing: MADTheme.Spacing.lg) {
                // First, and only while something is pending — including for
                // someone with no friends yet, whose first friend may be
                // waiting right here.
                pendingRequestsRow
                if friendService.isLoading && friendService.friends.isEmpty {
                    friendsSkeletonList
                } else if friendService.friends.isEmpty {
                    FriendsEmptyFlamey(
                        username: userManager.currentUser.username,
                        onAddFriends: { showingSearch = true }
                    )
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
            .lockedToScrollWidth()
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Out right now

    /// Friends who are walking or running THIS MINUTE.
    ///
    /// This lived only inside `WorkoutTrackingView`, which meant you could only
    /// discover that a friend was out if you were already out yourself — useless
    /// as a "should I go with them" signal, which is the entire point of knowing.
    /// The friends list is where someone looks to see what their friends are
    /// doing, so it belongs here.
    ///
    /// `BuddyJoinFriendCard` is reused verbatim rather than reimplemented: it
    /// already reads live presence (so a friend out on their OWN appears, not
    /// just one inside a buddy room) and already picks the right action —
    /// **Join** when there's a room, **Ask to walk** when there isn't. Renders
    /// nothing when nobody is out, so it never holds space speculatively.
    @ViewBuilder
    private var outRightNowSection: some View {
        if !buddy.friendsOutNow.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                BuddyJoinFriendCard(
                    // Always false here: this list is not a workout screen, and
                    // gating on a live workout would hide the section exactly
                    // when a friend is most worth joining.
                    hasActiveWorkout: false,
                    onJoined: openJoinedLobby
                )
            }
        }
    }

    /// Hand the joined session to the Dashboard, which owns the lobby
    /// presentation (`BuddyFlowModifier`). Parking the id on `DeepLinkRouter`
    /// is the same path a buddy push takes, so there is one way in rather than
    /// two that can drift.
    private func openJoinedLobby() {
        guard let sessionId = buddy.session?.id else { return }
        DeepLinkRouter.shared.requestOpenBuddySession(sessionId: sessionId)
        NotificationCenter.default.post(
            name: NSNotification.Name("MAD_SwitchTab"), object: nil, userInfo: ["tab": 0]
        )
    }

    // MARK: Split sections

    // Both sections sort by today's miles, descending. The miles are read once
    // per friend before sorting — the comparator used to hit the published
    // dictionary twice per comparison, every body pass.
    private func friendsByMilesDescending(completed: Bool) -> [BackendUser] {
        let statuses = nudgeStatuses
        return friendService.friends
            .compactMap { friend -> (BackendUser, Double)? in
                let status = statuses[friend.user_id]
                guard (status?.has_completed_mile ?? false) == completed else { return nil }
                return (friend, status?.today_miles ?? 0)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private var incompleteFriends: [BackendUser] {
        // Sort by progress descending so the closest-to-done friends bubble
        // to the top — they're the most satisfying to nudge.
        friendsByMilesDescending(completed: false)
    }

    private var completedFriends: [BackendUser] {
        // Highest miles first — rewards the day's top performers with
        // visibility at the top of the section.
        friendsByMilesDescending(completed: true)
    }

    @ViewBuilder
    private var cheerThemOnSection: some View {
        let incomplete = incompleteFriends
        let liveIds = Set(buddy.friendsOutNow.map(\.userId))
        if !incomplete.isEmpty || !liveIds.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                sectionHeader(
                    title: "Cheer them on",
                    trailing: ""
                )

                // Anyone OUT RIGHT NOW comes first, with how far they've got.
                // They're the friends where cheering actually reaches someone
                // mid-effort rather than after the fact, and they were
                // previously visible only from inside your own workout.
                if !liveIds.isEmpty {
                    outRightNowSection
                        .padding(.bottom, 2)
                }

                VStack(spacing: 6) {
                    // Live friends are rendered above with their real progress;
                    // a second static row for the same person would contradict
                    // the first the moment they moved.
                    ForEach(incomplete.filter { !liveIds.contains($0.id) }) { friend in
                        friendRowCompact(friend: friend, isCompleted: false)
                    }
                }
                .padding(.vertical, 4)
                .background(DashboardCardSurface(style: .fun))
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
        HStack(spacing: 12) {
            Image(systemName: "party.popper.fill")
                .madFont(size: 20, weight: .bold, maxScale: 1.5)
                .foregroundColor(.green)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Everyone's crushed it today")
                    .madFont(size: 14, weight: .bold, design: .rounded)
                    .foregroundColor(.white)
                Text("All \(friendService.friends.count) friends hit their goal.")
                    .madFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(DashboardCardSurface.padding)
        .background(DashboardCardSurface(style: .fun))
    }

    @ViewBuilder
    private var doneTodaySection: some View {
        let complete = completedFriends
        if !complete.isEmpty {
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                sectionHeader(
                    title: "Done today",
                    trailing: "\(complete.count) of \(friendService.friends.count)"
                )
                VStack(spacing: 6) {
                    ForEach(complete) { friend in
                        friendRowCompact(friend: friend, isCompleted: true)
                    }
                }
                .padding(.vertical, 4)
                .background(DashboardCardSurface(style: .fun))
            }
        }
    }

    private func sectionHeader(title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .madFont(size: 15, weight: .bold, design: .rounded)
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            Text(trailing)
                .madFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundColor(.white.opacity(0.45))
                .monospacedDigit()
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
        // A token holding their day. Suppressed once the miles are actually
        // in — the server refunds the coverage on that upload, so a finished
        // day is a green day, not a saved one.
        let savedToday = isCompleted ? nil : status?.today_covered
        // A covered day fills the ring: the streak is safe, and a 0% arc
        // beside a streak a friend's mile just rescued reads as the rescue
        // having failed.
        let progress = savedToday != nil ? 1.0 : min(todayMiles / goalMiles, 1.0)

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
                    progress: progress,
                    savedToday: savedToday
                )
            }
            .buttonStyle(.plain)

            // Action slot (where hype used to live). A rescuable broken streak
            // and today's unrun mile are different problems, so when a friend
            // has both, both show — Donate a Mile leads (restoring yesterday is
            // the time-boxed one) and the nudge shrinks to its bell.
            HStack(spacing: 6) {
                if let rescue = assistRescue(for: friend) {
                    SaveFriendStreakView(
                        friendId: friend.user_id,
                        friendName: friend.username ?? friend.displayName,
                        style: .compact,
                        preloaded: rescue,
                        onSaved: { _ in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                _ = savedFriendIds.insert(friend.user_id)
                            }
                            Task { await loadNudgeStatuses() }
                        }
                    )
                    // Capped, or this pill starves the name beside it. Its
                    // second line ("2.00 mi further today") is what makes its
                    // ideal width large, and an HStack splits slack in
                    // proportion to ideal widths — so the pill took ~40% of
                    // the row and the name column was left rendering "Aar…".
                    // The pill's own lines already truncate and scale down, so
                    // a ceiling costs it nothing it wasn't already spending.
                    .frame(maxWidth: 150)
                    if !isCompleted {
                        nudgeButton(
                            friend: friend,
                            alreadyNudged: alreadyNudged,
                            canRenudge: canRenudge,
                            iconOnly: true
                        )
                    }
                } else if savedFriendIds.contains(friend.user_id) {
                    savedChip
                } else if !isCompleted {
                    nudgeButton(friend: friend, alreadyNudged: alreadyNudged, canRenudge: canRenudge)
                }
            }
            .padding(.trailing, MADTheme.Spacing.md)
        }
        // Shared identity across sections so a friend moving from Cheer →
        // Done (or vice versa) slides instead of fade-popping.
        .matchedGeometryEffect(id: friend.user_id, in: friendRowNamespace)
    }

    /// Just the visual content of a friend row — avatar + name + subtitle +
    /// chevron-when-completed. Nudge button is rendered separately as a
    /// sibling so it doesn't compete with the row's open-profile tap.
    @ViewBuilder
    private func tappableRowContent(friend: BackendUser, isCompleted: Bool, status: NudgeStatusResponse?, todayMiles: Double, goalMiles: Double, progress: Double, savedToday: CoveredDate? = nil) -> some View {
        HStack(spacing: MADTheme.Spacing.md) {
            AvatarWithRing(
                name: friend.displayName,
                imageURL: friend.profile_image_url,
                progress: progress,
                size: 52,
                ringWidth: 3,
                accent: savedToday != nil ? SavedDayStyle.tint : .orange,
                badge: isCompleted ? .check : (savedToday != nil ? .saved : nil)
            )

            VStack(alignment: .leading, spacing: 2) {
                MADInlineStack {
                    Text(friend.username ?? friend.displayName)
                        .madFont(size: 14, weight: .bold, design: .rounded)
                        .foregroundColor(.white)
                        .madNameLines()
                    if let streak = status?.current_streak {
                        StreakFlameChip(streak: streak)
                    }
                }

                Text(rowSubtitle(
                    isCompleted: isCompleted,
                    todayMiles: todayMiles,
                    goal: goalMiles,
                    savedToday: savedToday
                ))
                .madFont(size: 11, weight: .medium, design: .rounded)
                .foregroundColor(savedToday != nil ? SavedDayStyle.tint : .white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 4)

            if isCompleted {
                Image(systemName: "chevron.right")
                    .madFont(size: 12, weight: .bold, maxScale: 1.5)
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

    private func rowSubtitle(
        isCompleted: Bool,
        todayMiles: Double,
        goal: Double,
        savedToday: CoveredDate? = nil
    ) -> String {
        // ONE number: today's distance. The ring beside it already shows
        // progress and done (green + check), and the section header says
        // "Done today", so "Goal complete · …" and "0.42 / 1 mi · 42%" were
        // the same fact said a second and third time.
        //
        // A covered day leads with WHO is holding it, not with how far short
        // the miles are: on this screen the reader is often the person who
        // paid for it.
        if !isCompleted, let savedToday {
            return SavedDayStyle.credit(for: savedToday)
        }
        return todayMiles.distanceFormatted
    }

    // MARK: - Nudge Button (only shown when friend hasn't completed goal)
    /// `canRenudge` (unlimited-nudge roles): an already-nudged friend shows an
    /// ENABLED "Nudge again" pill — visibly different from the fresh "Nudge",
    /// so the sender knows one already went out today before sending another.
    ///
    /// `iconOnly` drops the labels for the case where a Save Streak pill is
    /// already in the row's action slot: both actions stay reachable without
    /// two full-width pills fighting over the same ~120pt.
    private func nudgeButton(
        friend: BackendUser,
        alreadyNudged: Bool,
        canRenudge: Bool = false,
        iconOnly: Bool = false
    ) -> some View {
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
                                // Reads for the icon-only variant; hidden
                                // beside the text so it isn't said twice.
                                .accessibilityLabel("Nudge again")
                                .accessibilityHidden(!iconOnly)
                                .madFont(size: 10, weight: .semibold)
                            if !iconOnly {
                                Text("Nudge again")
                                    .madFont(size: 11, weight: .semibold, design: .rounded)
                            }
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
                        .madFont(size: 10, maxScale: 1.5)
                    if !iconOnly {
                        Text("Nudged")
                            .madFont(size: 11, weight: .medium, design: .rounded)
                    }
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
                                .madFont(size: 10, weight: .semibold, maxScale: 1.5)
                                .modifier(BellShakeModifier(isShaking: bellShakeIds.contains(friend.user_id)))
                            if !iconOnly {
                                Text("Nudge")
                                    .madFont(size: 11, weight: .semibold, design: .rounded)
                            }
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

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: MADTheme.Colors.madRed))

            Text("Loading...")
                .madFont(size: 17, design: .rounded)
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
            .background(DashboardCardSurface(style: .fun))
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
                    // `nudgeFriend` already marked the shared store (every
                    // surface flips together); nothing to patch here.
                    MADHaptics.success()
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

    // The request handlers are async and return an error message (nil on
    // success) rather than swallowing failures. They're called from INSIDE
    // FriendRequestsSheet, which covers this view — so the sheet renders the
    // resulting toast itself. Posting it here would put it behind the sheet,
    // where nobody would ever see it.
    //
    // FriendService mutates its published arrays only after the request
    // succeeds, so a failure leaves the row correctly in place; the only thing
    // missing was telling the user it failed.

    private func handleAcceptRequest(_ user: BackendUser) async -> String? {
        do {
            try await friendService.acceptFriendRequest(from: user)
            return nil
        } catch {
            return "Couldn't accept \(user.displayName)'s request. Try again."
        }
    }

    private func handleDeclineRequest(_ user: BackendUser) async -> String? {
        do {
            try await friendService.declineFriendRequest(from: user)
            return nil
        } catch {
            return "Couldn't decline that request. Try again."
        }
    }

    private func handleCancelRequest(_ user: BackendUser) async -> String? {
        do {
            try await friendService.cancelFriendRequest(to: user)
            return nil
        } catch {
            return "Couldn't cancel that request. Try again."
        }
    }

    private func handleUnfriend(_ user: BackendUser) {
        Task {
            do {
                try await friendService.removeFriend(user)
            } catch {
                // Called from the list itself, not the sheet, so this toast is
                // visible where it's posted.
                showNudgeFeedback(
                    NudgeFeedback(
                        icon: "xmark.circle",
                        message: "Couldn't remove \(user.displayName). Try again.",
                        isError: true
                    )
                )
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

// MARK: - Nudge Toast
/// The ONE floating confirmation for a nudge (Friends tab and a friend's
/// profile). Flat: the state colour is on the glyph, the card is a solid dark
/// plate so it stays readable over any content. No stripe, icon disc, rim,
/// material or shadow.
struct NudgeToast: View {
    let feedback: NudgeFeedback

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: feedback.icon)
                .madFont(size: 15, weight: .bold, maxScale: 1.5)
                .foregroundColor(feedback.isError ? .red : .green)
                .accessibilityHidden(true)
            Text(feedback.message)
                .madFont(size: 14, weight: .semibold, design: .rounded)
                .foregroundColor(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DashboardCardSurface.padding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DashboardCardSurface.radius, style: .continuous)
                .fill(Color(white: 0.14))
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty state
/// No friends yet: Flamey and two plain ways to fix it, sized to its content.
private struct FriendsEmptyFlamey: View {
    let username: String?
    let onAddFriends: () -> Void

    private var inviteURL: URL? {
        guard let username, !username.isEmpty else { return nil }
        return URL(string: "https://mileaday.run/u/\(username)")
    }

    var body: some View {
        VStack(spacing: 12) {
            // Room above him for whatever he's wearing; nothing clips his glow.
            FlameBuddyView(health: .healthy, size: 96, showsMoodBubble: false)
                .frame(width: 96, height: 96)
                .padding(.top, 24)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("Walks are better with friends")
                    .madFont(size: 18, weight: .heavy, design: .rounded)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("Add someone you walk with, or send them your link.")
                    .madFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button {
                    MADHaptics.tap()
                    onAddFriends()
                } label: {
                    Text("Add friends")
                        .madFont(size: 15, weight: .bold, design: .rounded)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                }
                .buttonStyle(.plain)
                if let inviteURL {
                    ShareLink(
                        item: inviteURL,
                        // The same link and words as Share Profile.
                        message: Text("Add me on Mile A Day and let's keep our streaks going!")
                    ) {
                        Text("Invite")
                            .madFont(size: 15, weight: .bold, design: .rounded)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .padding(DashboardCardSurface.padding)
        .frame(maxWidth: .infinity)
    }
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
