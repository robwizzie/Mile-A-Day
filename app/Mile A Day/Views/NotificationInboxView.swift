import SwiftUI
import UIKit

struct NotificationInboxView: View {
    @ObservedObject var competitionService: CompetitionService
    /// The app-wide FriendService (MainTabView's instance) — inline request
    /// accepts must mutate the SAME instance the Friends tab badge and
    /// requests sheet read, or an accepted request keeps showing as pending
    /// everywhere else until the next full refresh.
    @ObservedObject var friendService: FriendService
    var onUnreadCountChanged: ((Int) -> Void)?

    /// Rows that open a post close the inbox first — the post presents from
    /// MainTabView, and stacking it under a sheet that's still up would either
    /// drop the presentation or bury it.
    @Environment(\.dismiss) private var dismiss

    @State private var notifications: [InAppNotification] = []
    @State private var unreadCount = 0
    @State private var isLoading = true
    @State private var hasMore = true
    @State private var selectedCompetition: Competition?
    @State private var hypedRowIds: Set<String> = []
    @State private var toast: String?
    @State private var hypesRemaining: Int?
    /// Admin/founder roles bypass the daily hype cap — pill shows ∞.
    @State private var hypesUnlimited = false
    /// Friend requests accepted inline this visit — keeps the row's "Friends ✓"
    /// confirmation up after the request leaves `friendService.friendRequests`.
    @State private var acceptedRequestIds: Set<String> = []

    /// Active category filter. `all` shows everything; the others narrow
    /// the feed to a related cluster of notification types so users can
    /// focus (e.g., "just show me what's happening in my competitions").
    @State private var filter: NotificationFilter = .all

    enum NotificationFilter: Hashable, CaseIterable {
        case all, friends, comps, achievements

        var title: String {
            switch self {
            case .all: return "All"
            case .friends: return "Friends"
            case .comps: return "Comps"
            case .achievements: return "Awards"
            }
        }

        var icon: String {
            switch self {
            case .all: return "tray.full.fill"
            case .friends: return "person.2.fill"
            case .comps: return "trophy.fill"
            case .achievements: return "medal.fill"
            }
        }

        /// Notification types that belong to this category. `all` returns
        /// nil — caller skips the filter step entirely.
        func matches(_ type: String) -> Bool {
            switch self {
            case .all:
                return true
            case .friends:
                // Streak rescues are friend activity too — without these two
                // they'd only ever surface under All (nothing else matches
                // the streak_ prefix).
                return type.hasPrefix("friend_")
                    || type == "streak_assist_opportunity"
                    || type == "streak_assisted"
            case .comps:
                return type.hasPrefix("competition_") || type == "lead_change" || type == "clash_tie"
            case .achievements:
                return type == "badge_earned" || type == "personal_best" || type == "streak_broken"
            }
        }
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            if isLoading && notifications.isEmpty {
                VStack(spacing: MADTheme.Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(MADTheme.Colors.madRed)
                    Text("Loading notifications...")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                }
            } else if notifications.isEmpty {
                emptyState
            } else {
                feedScrollView
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await loadNotifications()
            // Refresh pending requests so friend_request rows can offer the
            // inline Accept — usually already warm from MainTabView's refresh.
            try? await friendService.loadFriendRequests()
        }
        .refreshable {
            // Pull-to-refresh also settles the unread state in place, so the
            // user doesn't have to leave and return to see the dots clear.
            await loadNotifications(markVisibleRead: true)
        }
        .onChange(of: unreadCount) { _, newCount in
            onUnreadCountChanged?(newCount)
        }
        .sheet(item: $selectedCompetition) { competition in
            NavigationStack {
                CompetitionDetailView(competition: competition, competitionService: competitionService)
            }
        }
        .overlay(alignment: .top) {
            if let msg = toast {
                Text(msg)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .padding(.top, MADTheme.Spacing.md)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: toast)
    }

    // MARK: - Feed shell

    /// Friendly empty state — same visual grammar as Friends/Compete empty
    /// states elsewhere in the app (centered icon disc + title + subtitle).
    private var emptyState: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.white.opacity(0.06)))

            VStack(spacing: 4) {
                Text("No notifications yet")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                Text("Friend activity, competition updates, and badge wins will land here")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MADTheme.Spacing.xl)
            }
        }
    }

    /// Feed grouped by time bucket — Today / Yesterday / Earlier — so the
    /// list reads chronologically the way a social feed does instead of an
    /// undifferentiated stream. Filter chips sit inline at the top of the
    /// feed (scroll away with content — not sticky).
    private var feedScrollView: some View {
        ScrollView {
            LazyVStack(spacing: MADTheme.Spacing.lg) {
                filterChipsBar

                let groups = groupedNotifications
                if groups.isEmpty {
                    filteredEmptyState
                        .padding(.top, 60)
                } else {
                    ForEach(groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            feedSectionHeader(group.title)
                            VStack(spacing: 6) {
                                ForEach(group.items) { notification in
                                    notificationRow(notification)
                                        .onAppear {
                                            if notification.id == notifications.last?.id && hasMore {
                                                loadMore()
                                            }
                                        }
                                }
                            }
                        }
                    }
                }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(MADTheme.Colors.madRed)
                        .padding()
                }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.top, MADTheme.Spacing.sm)
            .padding(.bottom, MADTheme.Spacing.lg)
        }
    }

    /// Filter chip row at the top of the feed. Horizontal scroll lets each
    /// chip claim its natural width (icon + label + count badge) without
    /// fighting the others for space — the row never gets scrunched even
    /// when counts get into the double digits. Scrolls away with the feed.
    private var filterChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotificationFilter.allCases, id: \.self) { f in
                    filterChip(f)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func filterChip(_ f: NotificationFilter) -> some View {
        let count = countFor(filter: f)
        let isSelected = filter == f
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                filter = f
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: f.icon)
                    .font(.system(size: 11, weight: .bold))
                Text(f.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.55))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.10))
                        )
                }
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isSelected ? MADTheme.Colors.madRed : Color.white.opacity(0.06))
                    .overlay(
                        Capsule().strokeBorder(
                            isSelected ? Color.clear : Color.white.opacity(0.10),
                            lineWidth: 1
                        )
                    )
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
    }

    private func countFor(filter f: NotificationFilter) -> Int {
        notifications.filter { f.matches($0.type) }.count
    }

    /// Empty state shown when the active filter excludes every notification
    /// (e.g., user picks "Comps" but has no competition notifications).
    /// Different copy than the universal empty state so users know to try
    /// "All" if they're not sure where their stuff is.
    private var filteredEmptyState: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            Image(systemName: filter.icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.white.opacity(0.04)))
            Text("No \(filter.title.lowercased()) notifications")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            Button("Show all") { filter = .all }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(MADTheme.Colors.madRed)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    /// Inline section divider — small uppercase label on the left + a
    /// fading line to the right. Quieter than the old sticky uppercase
    /// banner; doesn't overlap scrolling content on stutter.
    private func feedSectionHeader(_ title: String) -> some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.4))
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
    }

    /// Groups notifications into Today / Yesterday / Earlier this week /
    /// Older buckets, after applying the active category filter. Buckets
    /// with zero items don't render.
    private var groupedNotifications: [(title: String, items: [InAppNotification])] {
        let cal = Calendar.current
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func bucket(for n: InAppNotification) -> Int {
            // Parse created_at with or without fractional seconds.
            var date: Date? = formatter.date(from: n.created_at)
            if date == nil {
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: n.created_at)
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            }
            guard let d = date else { return 3 }
            if cal.isDateInToday(d) { return 0 }
            if cal.isDateInYesterday(d) { return 1 }
            let days = cal.dateComponents([.day], from: d, to: now).day ?? 0
            return days < 7 ? 2 : 3
        }

        // Apply category filter before bucketing — if the filter excludes
        // everything, the caller renders `filteredEmptyState`.
        let filtered = notifications.filter { filter.matches($0.type) }

        var buckets: [Int: [InAppNotification]] = [:]
        for n in filtered {
            buckets[bucket(for: n), default: []].append(n)
        }

        let titles = ["Today", "Yesterday", "Earlier this week", "Older"]
        return titles.enumerated().compactMap { (idx, title) in
            guard let items = buckets[idx], !items.isEmpty else { return nil }
            return (title: title, items: items)
        }
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { toast = nil }
        }
    }

    /// Hype affordance for a notification row. Prefers the server-enriched
    /// context fields — those use the canonical keys shared with the feed, so a
    /// hype sent here and one sent from the feed dedupe as the same hype — and
    /// falls back to local derivation for older backends. Returns nil for
    /// non-celebratory rows (streak broken, friend requests, competition
    /// notifications, etc.).
    private func hypeAffordance(for notification: InAppNotification) -> HypeContext? {
        if let type = notification.hype_context_type, !type.isEmpty,
           let contextId = notification.hype_context_id, !contextId.isEmpty,
           let label = notification.hype_context_label,
           notification.hype_target_user_id?.isEmpty == false {
            return HypeContext(contextType: type, contextId: contextId, contextLabel: label)
        }

        let data = notification.data ?? [:]

        switch notification.type {
        case "friend_activity":
            // Skip the streak-broken variant — that's sympathetic, not celebratory.
            if data["kind"] == "streak_broken" { return nil }
            if notification.title.hasPrefix("Streak broken") { return nil }
            guard let targetId = data["user_id"] else { return nil }
            // user_id:YYYY-MM-DD as the dedupe key (one mile per day per user).
            // Prefer the runner's local_date from the payload — the created_at
            // fallback is the UTC date, which is off-by-one for evening miles
            // (e.g. 11pm ET) and collides with the next day's mile.
            let dateKey = data["local_date"] ?? String(notification.created_at.prefix(10))
            return HypeContext(
                contextType: "mile",
                contextId: "\(targetId):\(dateKey)",
                contextLabel: "today's mile"
            )

        case "friend_badge_earned":
            guard let targetId = data["sender_id"], let badgeId = data["badge_id"] else { return nil }
            _ = targetId
            return HypeContext(
                contextType: "badge",
                contextId: badgeId,
                contextLabel: data["badge_name"] ?? "a medal"
            )

        case "friend_personal_best":
            guard
                let targetId = data["sender_id"],
                let prType = data["pr_type"],
                let workoutId = data["workout_id"]
            else { return nil }
            _ = targetId
            return HypeContext(
                contextType: "pr",
                contextId: "\(prType):\(workoutId)",
                contextLabel: data["pr_label"] ?? "personal best"
            )

        case "friend_challenge_completed":
            guard let targetId = data["sender_id"] else { return nil }
            // local_date is in the payload; fall back to the row's creation date.
            // The fallback uses the UTC created_at and can be off-by-one for
            // legacy rows completed near local midnight — new pushes carry local_date.
            let localDate = data["local_date"] ?? String(notification.created_at.prefix(10))
            return HypeContext(
                contextType: "challenge",
                contextId: "\(targetId):\(localDate)",
                contextLabel: data["challenge_title"] ?? notification.body
            )

        default:
            return nil
        }
    }

    /// The user_id of the friend we'd hype for this notification (or nil if not hype-able).
    private func hypeTargetUserId(for notification: InAppNotification) -> String? {
        if let target = notification.hype_target_user_id, !target.isEmpty {
            return target
        }
        let data = notification.data ?? [:]
        switch notification.type {
        case "friend_activity":
            if data["kind"] == "streak_broken" { return nil }
            if notification.title.hasPrefix("Streak broken") { return nil }
            return data["user_id"]
        case "friend_badge_earned", "friend_personal_best", "friend_challenge_completed":
            return data["sender_id"]
        default:
            return nil
        }
    }

    private func canShowHypeButton(_ notification: InAppNotification) -> Bool {
        guard hypeAffordance(for: notification) != nil else { return false }
        return isFromTodayOrYesterday(notification.created_at)
    }

    /// Hype affordance is restricted to events from today or yesterday by
    /// local calendar date — not a rolling 48-hour window. Matches the
    /// "Today" / "Yesterday" buckets users already see in the feed.
    private func isFromTodayOrYesterday(_ dateString: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: dateString)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: dateString)
        }
        guard let d = date else { return false }
        let cal = Calendar.current
        return cal.isDateInToday(d) || cal.isDateInYesterday(d)
    }

    /// True when this row has already been hyped (server-side flag or local optimistic).
    private func isAlreadyHyped(_ notification: InAppNotification) -> Bool {
        notification.is_hyped == true || hypedRowIds.contains(notification.id)
    }

    /// The event's total hype count for display: the server figure (computed
    /// with the same canonical context keys as the feed) plus one while the
    /// viewer's own optimistic hype is in flight but not yet reflected.
    private func displayedHypeCount(_ notification: InAppNotification) -> Int {
        let base = notification.hype_count ?? 0
        let optimisticBump = hypedRowIds.contains(notification.id) && notification.is_hyped != true
        return base + (optimisticBump ? 1 : 0)
    }

    private func performHype(_ notification: InAppNotification) {
        guard
            let targetId = hypeTargetUserId(for: notification),
            let context = hypeAffordance(for: notification)
        else { return }

        // Optimistic grey-out.
        hypedRowIds.insert(notification.id)

        Task {
            do {
                let response = try await HypeService.sendHype(targetUserId: targetId, context: context)
                await MainActor.run {
                    hypesRemaining = response.hypes_remaining
                    hypesUnlimited = response.unlimited ?? hypesUnlimited
                }
            } catch APIError.conflict {
                // Already hyped server-side; stay greyed out, no toast.
            } catch APIError.rateLimited(let msg) {
                await MainActor.run {
                    hypedRowIds.remove(notification.id)
                    hypesRemaining = 0
                    showToast(msg.isEmpty ? "You're out of hypes today" : msg)
                }
            } catch APIError.badRequest(let msg) {
                // Older backend that doesn't accept context fields will reject — fall back
                // to context-less hype call so the feature still works pre-deploy.
                if msg.contains("context_type") || msg.contains("context_id") {
                    await fallbackHype(notification, targetId: targetId)
                } else {
                    await MainActor.run {
                        hypedRowIds.remove(notification.id)
                        showToast(msg)
                    }
                }
            } catch {
                await MainActor.run {
                    hypedRowIds.remove(notification.id)
                    showToast("Couldn't send hype")
                }
            }
        }
    }

    /// Retry against an older backend that hasn't deployed the context-aware hype yet.
    private func fallbackHype(_ notification: InAppNotification, targetId: String) async {
        do {
            let response = try await HypeService.sendHype(targetUserId: targetId)
            await MainActor.run {
                hypesRemaining = response.hypes_remaining
                hypesUnlimited = response.unlimited ?? hypesUnlimited
            }
        } catch APIError.rateLimited(let msg) {
            await MainActor.run {
                hypedRowIds.remove(notification.id)
                hypesRemaining = 0
                showToast(msg.isEmpty ? "You're out of hypes today" : msg)
            }
        } catch {
            await MainActor.run {
                hypedRowIds.remove(notification.id)
                showToast("Couldn't send hype")
            }
        }
    }

    // MARK: - Notification Row

    private func switchTab(_ tab: Int) {
        NotificationCenter.default.post(
            name: NSNotification.Name("MAD_SwitchTab"),
            object: nil,
            userInfo: ["tab": tab]
        )
    }

    /// Lands on the actor's profile — parked on DeepLinkRouter for
    /// FriendsListView to resolve and present (it may not be mounted yet).
    /// Falls back to the Friends tab when the username is unknown.
    private func openActorProfileOrFriends(_ notification: InAppNotification) {
        if let username = notification.actor?.username, !username.isEmpty {
            DeepLinkRouter.shared.pendingProfileUsername = username.lowercased()
        }
        switchTab(3)
    }

    private func handleNotificationTap(_ notification: InAppNotification) {
        if !notification.is_read {
            markRead(notification)
        }

        let type = notification.type
        switch type {
        case "friend_post":
            // A friend's photo post or story — land on the thing itself:
            // posts scroll the feed to the entry, stories open the viewer
            // (which still respects the day-scoped viewing gate).
            let kind = notification.data?["kind"]
            if kind != "story", let postId = notification.data?["post_id"], !postId.isEmpty {
                dismiss()
                PostDeepLink.shared.openAfterDismiss(postId)
                return
            }
            FeedDeepLink.pending = FeedDeepLink.Target(
                userId: notification.data?["user_id"],
                storyUserId: kind == "story" ? notification.data?["user_id"] : nil
            )
            switchTab(2)
            NotificationCenter.default.post(name: FeedDeepLink.poke, object: nil)
        case "story_reaction":
            // Someone reacted to MY story — replay my own story.
            FeedDeepLink.pending = FeedDeepLink.Target(
                storyUserId: UserDefaults.standard.string(forKey: "backendUserId")
            )
            switchTab(2)
            NotificationCenter.default.post(name: FeedDeepLink.poke, object: nil)
        case "coauthor_invite", "coauthor_accepted", "mention", "post_comment":
            // Collab invites/accepts, @mentions, and comment activity all live
            // on one specific feed item. A post opens DIRECTLY — scrolling the
            // feed to it only ever worked while the post was still on the
            // loaded page, which an inbox row read days later rarely is.
            if let postId = notification.data?["post_id"], !postId.isEmpty {
                dismiss()
                PostDeepLink.shared.openAfterDismiss(postId)
                return
            }
            // Raw workout comments have no permalink — the feed entry is the
            // only place they live.
            FeedDeepLink.pending = FeedDeepLink.Target(
                workoutId: notification.data?["workout_id"],
                userId: notification.data?["user_id"]
            )
            switchTab(2)
            NotificationCenter.default.post(name: FeedDeepLink.poke, object: nil)
        case "hype_received":
            // A hype on a post opens the post itself — newer rows carry the
            // post uuid in context_id, and the server-resolved preview covers
            // rows where the post is still visible. Mile/badge/PR hypes have
            // no permalink; the hyped thing lives on the feed.
            let postId = notification.post_preview?.post_id
                ?? (notification.data?["context_type"] == "post" ? notification.data?["context_id"] : nil)
            if let postId, !postId.isEmpty {
                dismiss()
                PostDeepLink.shared.openAfterDismiss(postId)
                return
            }
            switchTab(2)
        case "friend_activity" where isWorkoutActivity(notification):
            // A merged mile+photo push (upgraded in the 10-min window) carries
            // a post id — open that post DIRECTLY, same as mention/comment
            // rows (scrolling the feed to it only works while the post is
            // still on the loaded page, which an inbox row read later isn't).
            if let postId = notification.data?["post_id"], !postId.isEmpty {
                dismiss()
                PostDeepLink.shared.openAfterDismiss(postId)
                return
            }
            // A raw walk/run has no permalink — its feed entry is the target.
            // Parked statically because the Feed tab may not be mounted yet;
            // the poke wakes it when it is.
            FeedDeepLink.pending = FeedDeepLink.Target(
                workoutId: notification.data?["workout_id"],
                userId: notification.data?["user_id"],
                localDate: notification.data?["local_date"]
            )
            switchTab(2)
            NotificationCenter.default.post(name: FeedDeepLink.poke, object: nil)
        case "friend_request", "friend_request_reminder":
            // Ask the Friends tab to open the requests sheet. Switching tabs
            // alone dropped the user on the friends list with the sheet closed
            // and no hint where the request went — the row looked broken.
            DeepLinkRouter.shared.requestOpenFriendRequests()
            switchTab(3)
        case "friend_request_accepted", "friend_activity":
            // A new friendship / a friend's streak news — land on the person,
            // not just the friends list.
            openActorProfileOrFriends(notification)
        case "friend_nudge":
            switchTab(3)
        case "friend_badge_earned", "friend_challenge_completed":
            // The medal case / their challenge run lives on their profile.
            openActorProfileOrFriends(notification)
        case "friend_personal_best":
            // The PR is a concrete workout — land on its feed entry.
            FeedDeepLink.pending = FeedDeepLink.Target(
                workoutId: notification.data?["workout_id"],
                userId: notification.data?["sender_id"]
            )
            switchTab(2)
            NotificationCenter.default.post(name: FeedDeepLink.poke, object: nil)
        case "competition_invite", "competition_accepted", "competition_started",
             "competition_finished", "competition_updates", "competition_nudge",
             "competition_flex", "competition_milestone", "lead_change", "clash_tie":
            // A Head-to-Head lead change reuses `lead_change` (every shipped
            // build routes it; a new type would tap to nothing on all of
            // them). It has no competition, so send it to the Dashboard where
            // the duel card lives rather than the Compete tab.
            if notification.data?["challenge_key"] == "head_to_head" {
                switchTab(0)
                return
            }
            if let compId = notification.data?["competition_id"],
               let comp = competitionService.competitions.first(where: { $0.competition_id == compId })
                       ?? competitionService.invites.first(where: { $0.competition_id == compId }) {
                selectedCompetition = comp
            } else {
                switchTab(1)
            }
        case "challenge_won":
            // The overnight Head-to-Head verdict — the duel card lives on the
            // Dashboard.
            switchTab(0)
        case "badge_earned", "personal_best":
            // Your own award — the trophy case is on your profile.
            switchTab(4)
        case "streak_assist_opportunity":
            // The push copy says "save it from their profile" — land on the
            // broken friend's profile, where SaveFriendStreakView fetches a
            // fresh rescue status. (The Friends-tab row button also works but
            // depends on a tokensState refresh that a tab switch alone
            // doesn't guarantee.) Legacy rows without an actor fall back to
            // the Friends tab.
            openActorProfileOrFriends(notification)
        default:
            // Streak token outcomes, reminders, recaps, and any future type:
            // land on the Dashboard rather than dead-ending the tap.
            switchTab(0)
        }
    }

    /// friend_activity kinds that correspond to a concrete walk/run the feed
    /// can show (streak_broken etc. keep the Friends-tab destination).
    private func isWorkoutActivity(_ notification: InAppNotification) -> Bool {
        switch notification.data?["kind"] {
        case "mile_completed", "workout", "extra_workout": return true
        default: return false
        }
    }

    private func notificationRow(_ notification: InAppNotification) -> some View {
        let accent = notificationColor(for: notification.type)
        let isUnread = !notification.is_read

        return Button {
            handleNotificationTap(notification)
        } label: {
            HStack(alignment: .top, spacing: MADTheme.Spacing.md) {
                leadingIdentity(for: notification, accent: accent)

                VStack(alignment: .leading, spacing: 4) {
                    // Type label + time — small caption row that makes
                    // "what kind of event is this" instantly readable.
                    HStack(spacing: 6) {
                        Text(typeLabel(for: notification.type))
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(0.6)
                            .foregroundColor(accent)
                        Text("·")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.25))
                        Text(relativeTime(notification.created_at))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.45))
                    }

                    Text(emphasized(notification.title, name: notification.actor?.displayName))
                        .font(.system(size: 14, weight: isUnread ? .heavy : .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)

                    Text(emphasized(notification.body, name: notification.actor?.displayName))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    friendRequestActions(notification)

                    if canShowHypeButton(notification) {
                        let hyped = isAlreadyHyped(notification)
                        HStack(spacing: 10) {
                            HypeButton(isHyped: hyped) {
                                performHype(notification)
                            }
                            // Same tally the feed shows for this event — the
                            // server computes both from the same canonical
                            // hype context, so the numbers always agree.
                            let count = displayedHypeCount(notification)
                            if count > 0 {
                                HypeTally(count: count)
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                Spacer(minLength: 4)

                // Instagram-style trailing thumbnail of the post the row is
                // about — instantly answers "which post?" and reinforces that
                // tapping lands on it. Today's photos stay LOCKED until the
                // viewer runs, exactly like the feed — same gate, same look.
                if notification.post_preview?.photo_locked == true {
                    NotificationPostThumb(url: nil, locked: true)
                } else if let thumbURL = thumbnailURL(for: notification) {
                    NotificationPostThumb(url: thumbURL)
                }

                if isUnread {
                    Circle()
                        .fill(MADTheme.Colors.madRed)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
            }
            .padding(MADTheme.Spacing.md)
            .background(
                // Flat card — the type's color signal lives in the avatar
                // badge and label, so no accent stripe.
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                    .fill(isUnread ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                            .strokeBorder(Color.white.opacity(isUnread ? 0.10 : 0.05), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Row identity, Instagram-style: WHO it's about (their avatar) with a
    /// small type badge for the "what kind of event" color signal the old
    /// icon disc carried. Rows with no actor — reminders, competition
    /// lifecycle, streak tokens — keep the type-icon disc.
    @ViewBuilder
    private func leadingIdentity(for notification: InAppNotification, accent: Color) -> some View {
        if let actor = notification.actor {
            AvatarView(name: actor.initialsName, imageURL: actor.profile_image_url, size: 44)
                // Badge lives INSIDE the 44pt bounds (overlay alignment, no
                // .offset) so the row measures exactly what it draws.
                .overlay(alignment: .bottomTrailing) {
                    ZStack {
                        Circle()
                            .fill(accent)
                            .frame(width: 17, height: 17)
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1.5))
                        notificationIcon(for: notification.type)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.30), accent.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(accent.opacity(0.35), lineWidth: 1))
                notificationIcon(for: notification.type)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(accent)
            }
        }
    }

    /// Bolds the actor's name inside the server-baked copy ("dave hyped your
    /// post" → "**dave** hyped your post") — Instagram's pattern, without
    /// changing any server strings. No-op when the name isn't in the text.
    private func emphasized(_ text: String, name: String?) -> AttributedString {
        var attributed = AttributedString(text)
        if let name, !name.isEmpty,
           let range = attributed.range(of: name, options: [.caseInsensitive]) {
            attributed[range].inlinePresentationIntent = .stronglyEmphasized
            attributed[range].foregroundColor = .white
        }
        return attributed
    }

    /// Trailing post thumbnail — the server only sends `post_preview` for
    /// posts this viewer may still see (feed visibility rules), signed the
    /// same way feed media is.
    private func thumbnailURL(for notification: InAppNotification) -> URL? {
        guard let media = notification.post_preview?.media_url, !media.isEmpty else { return nil }
        return ProfileImageService.fullImageURL(for: media)
    }

    /// Inline Accept for a still-pending friend request — Instagram's "Follow
    /// back" pattern. The row tap keeps opening the requests sheet (where
    /// decline lives); this is the fast path. Nothing renders once the
    /// request is no longer pending, except the "Friends ✓" confirmation for
    /// accepts made right here.
    @ViewBuilder
    private func friendRequestActions(_ notification: InAppNotification) -> some View {
        if notification.type == "friend_request" || notification.type == "friend_request_reminder",
           let actor = notification.actor {
            if acceptedRequestIds.contains(actor.user_id) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                    Text("Friends")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.green.opacity(0.15)))
                .padding(.top, 4)
            } else if friendService.friendRequests.contains(where: { $0.user_id == actor.user_id }) {
                Button {
                    acceptRequest(notification)
                } label: {
                    Text("Accept")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    private func acceptRequest(_ notification: InAppNotification) {
        guard
            let actor = notification.actor,
            let requester = friendService.friendRequests.first(where: { $0.user_id == actor.user_id })
        else { return }

        // Optimistic — flip to "Friends ✓" immediately; roll back on failure.
        acceptedRequestIds.insert(actor.user_id)

        Task {
            do {
                try await friendService.acceptFriendRequest(from: requester)
                await MainActor.run {
                    showToast("You're now friends with \(actor.displayName) 🎉")
                }
            } catch {
                await MainActor.run {
                    acceptedRequestIds.remove(actor.user_id)
                    showToast("Couldn't accept the request — try again")
                }
            }
        }
    }

    /// Friendly category label paired with each row's icon. Matches the
    /// `iconForType` casing so users see "FRIEND · 5m ago" at a glance.
    private func typeLabel(for type: String) -> String {
        switch type {
        case "friend_request", "friend_request_reminder": return "FRIEND REQUEST"
        case "friend_request_accepted": return "FRIEND"
        case "friend_nudge": return "NUDGE"
        case "friend_activity": return "FRIEND"
        case "friend_post": return "NEW POST"
        case "story_reaction": return "STORY"
        case "friend_badge_earned": return "FRIEND BADGE"
        case "friend_personal_best": return "FRIEND PR"
        case "friend_challenge_completed": return "FRIEND CHALLENGE"
        case "challenge_won": return "CHALLENGE WON"
        case "competition_invite": return "COMP INVITE"
        case "competition_accepted": return "COMP JOINED"
        case "competition_started": return "COMP STARTED"
        case "competition_finished": return "COMP FINISHED"
        case "competition_nudge": return "COMP NUDGE"
        case "competition_flex": return "FLEX"
        case "competition_milestone": return "MILESTONE"
        case "streak_broken": return "STREAK"
        case "goal_reached": return "GOAL DONE"
        case "personal_best": return "PERSONAL BEST"
        case "badge_earned": return "BADGE"
        case "lead_change": return "LEAD CHANGE"
        case "clash_tie": return "CLASH TIE"
        default: return "UPDATE"
        }
    }

    // MARK: - Helpers

    /// Bare glyph for the type — callers pick size/color (big disc vs the
    /// small avatar badge).
    private func notificationIcon(for type: String) -> Image {
        Image(systemName: iconForType(type).0)
    }

    private func iconForType(_ type: String) -> (String, Color) {
        switch type {
        case "friend_request", "friend_request_reminder": return ("person.badge.plus", .blue)
        case "friend_request_accepted": return ("person.2.fill", .green)
        case "friend_nudge": return ("bell.badge", .orange)
        case "friend_activity": return ("figure.run", .green)
        case "friend_post": return ("photo.fill", .orange)
        case "story_reaction": return ("heart.circle.fill", .pink)
        case "competition_invite": return ("envelope.fill", .purple)
        case "competition_accepted": return ("checkmark.circle", .green)
        case "competition_started": return ("flag.fill", .blue)
        case "competition_finished": return ("trophy.fill", .yellow)
        case "competition_nudge": return ("bell.badge", .orange)
        case "competition_flex": return ("flame.fill", .red)
        case "competition_milestone": return ("star.fill", .yellow)
        case "streak_broken": return ("flame.fill", .red)
        case "goal_reached": return ("checkmark.seal.fill", .green)
        case "personal_best": return ("medal.fill", .yellow)
        case "lead_change": return ("arrow.up.right", .green)
        case "clash_tie": return ("equal.circle.fill", .purple)
        case "challenge_won": return ("flag.2.crossed.fill", .yellow)
        default: return ("bell.fill", .white.opacity(0.5))
        }
    }

    private func notificationColor(for type: String) -> Color {
        iconForType(type).1
    }

    private func relativeTime(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateString) else { return dateString }
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Data Loading

    /// Loads the inbox and auto-reads everything on the server.
    ///
    /// On open (`.task`) the freshly-fetched rows still carry `is_read=false`,
    /// so the unread dots stay visible for this visit and settle when the view
    /// reappears. Pull-to-refresh passes `markVisibleRead: true` to also clear
    /// those dots in place — everything is read server-side at that point, so
    /// flipping the displayed rows just mirrors the reappear behavior without
    /// requiring the user to leave and come back.
    private func loadNotifications(markVisibleRead: Bool = false) async {
        isLoading = true
        do {
            let response = try await friendService.getInboxNotifications()
            await MainActor.run {
                notifications = response.notifications
                unreadCount = response.unread_count
                hasMore = response.notifications.count >= 50
                isLoading = false
            }
            // Zeroing unreadCount clears the bell badge via onUnreadCountChanged.
            if response.unread_count > 0 {
                try? await friendService.markAllNotificationsRead()
                await MainActor.run { unreadCount = 0 }
            }
            if markVisibleRead {
                await MainActor.run {
                    notifications = notifications.map { $0.is_read ? $0 : readCopy($0) }
                }
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
        await loadHypeStatus()
    }

    private func loadHypeStatus() async {
        do {
            let status = try await HypeService.status()
            await MainActor.run {
                hypesRemaining = status.hypes_remaining
                hypesUnlimited = status.unlimited ?? false
            }
        } catch {
            // Non-fatal — pill just stays hidden.
        }
    }

    private func loadMore() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            do {
                let response = try await friendService.getInboxNotifications(offset: notifications.count)
                await MainActor.run {
                    notifications.append(contentsOf: response.notifications)
                    hasMore = response.notifications.count >= 50
                    isLoading = false
                }
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }

    private func markRead(_ notification: InAppNotification) {
        Task {
            try? await friendService.markNotificationRead(id: notification.id)
            await MainActor.run {
                if let idx = notifications.firstIndex(where: { $0.id == notification.id }) {
                    notifications[idx] = readCopy(notifications[idx])
                    unreadCount = max(0, unreadCount - 1)
                }
            }
        }
    }

    /// Returns a copy of the notification with `is_read = true`. The model's
    /// fields are immutable `let`s, so the row is rebuilt rather than mutated.
    private func readCopy(_ n: InAppNotification) -> InAppNotification {
        InAppNotification(
            id: n.id, title: n.title, body: n.body,
            type: n.type, data: n.data, is_read: true,
            created_at: n.created_at,
            hype_target_user_id: n.hype_target_user_id,
            hype_context_type: n.hype_context_type,
            hype_context_id: n.hype_context_id,
            hype_context_label: n.hype_context_label,
            is_hyped: n.is_hyped,
            // Dropping this defaulted the tally to nil — marking an unread
            // hypeable row read wiped its displayed count until next reload.
            hype_count: n.hype_count,
            // Same trap as hype_count: these default to nil in the memberwise
            // init, and dropping them would strip the avatar + thumbnail off
            // a row the moment it was marked read.
            actor: n.actor,
            post_preview: n.post_preview
        )
    }

}

/// Small trailing thumbnail of the post a notification is about. Uses the
/// feed's image cache (keyed by URL path) so a photo already seen in the feed
/// never re-downloads here — and signed-URL query rotation doesn't bust it.
/// `locked` renders the feed's "run to see today's photos" state: a lock
/// tile, no image request (the server withholds the bytes anyway).
private struct NotificationPostThumb: View {
    let url: URL?
    var locked: Bool = false

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if locked {
                Color.white.opacity(0.06)
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.06)
                if failed {
                    Image(systemName: "photo")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .task(id: url) { await load() }
    }

    private func load() async {
        guard !locked, let url else { return }
        if let cached = FeedImageCache.image(for: url) {
            image = cached
            return
        }
        // Recycled row with a new url: drop the previous photo instead of
        // showing someone else's post while the right one downloads.
        image = nil
        failed = false
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let loaded = UIImage(data: data) else {
                failed = true
                return
            }
            FeedImageCache.store(loaded, for: url)
            image = loaded
        } catch {
            failed = true
        }
    }
}

#Preview {
    NavigationStack {
        NotificationInboxView(
            competitionService: CompetitionService(),
            friendService: FriendService()
        )
    }
}
