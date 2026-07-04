import SwiftUI

struct NotificationInboxView: View {
    @ObservedObject var competitionService: CompetitionService
    var onUnreadCountChanged: ((Int) -> Void)?

    @StateObject private var friendService = FriendService()
    @State private var notifications: [InAppNotification] = []
    @State private var unreadCount = 0
    @State private var isLoading = true
    @State private var hasMore = true
    @State private var selectedCompetition: Competition?
    @State private var hypedRowIds: Set<String> = []
    @State private var hypeToast: String?
    @State private var hypesRemaining: Int?
    /// Admin/founder roles bypass the daily hype cap — pill shows ∞.
    @State private var hypesUnlimited = false

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
                return type.hasPrefix("friend_")
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
        .toolbar {
            if let remaining = hypesRemaining {
                // iOS 26 wraps toolbar items in a shared glass capsule; hiding it
                // stops the orange pill from rendering inside a second system pill.
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .navigationBarLeading) {
                        HypePill(remaining: remaining, compact: true, unlimited: hypesUnlimited)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .navigationBarLeading) {
                        HypePill(remaining: remaining, compact: true, unlimited: hypesUnlimited)
                    }
                }
            }
            // "Read All" button removed — opening the inbox now auto-marks
            // everything read (see loadNotifications).
        }
        .task {
            await loadNotifications()
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
            if let msg = hypeToast {
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
        .animation(.spring(response: 0.3), value: hypeToast)
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

    private func showHypeToast(_ message: String) {
        hypeToast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { hypeToast = nil }
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
                    showHypeToast(msg.isEmpty ? "You're out of hypes today" : msg)
                }
            } catch APIError.badRequest(let msg) {
                // Older backend that doesn't accept context fields will reject — fall back
                // to context-less hype call so the feature still works pre-deploy.
                if msg.contains("context_type") || msg.contains("context_id") {
                    await fallbackHype(notification, targetId: targetId)
                } else {
                    await MainActor.run {
                        hypedRowIds.remove(notification.id)
                        showHypeToast(msg)
                    }
                }
            } catch {
                await MainActor.run {
                    hypedRowIds.remove(notification.id)
                    showHypeToast("Couldn't send hype")
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
                showHypeToast(msg.isEmpty ? "You're out of hypes today" : msg)
            }
        } catch {
            await MainActor.run {
                hypedRowIds.remove(notification.id)
                showHypeToast("Couldn't send hype")
            }
        }
    }

    // MARK: - Notification Row

    private func handleNotificationTap(_ notification: InAppNotification) {
        if !notification.is_read {
            markRead(notification)
        }

        let type = notification.type
        switch type {
        case "friend_request", "friend_request_accepted", "friend_nudge", "friend_activity":
            NotificationCenter.default.post(
                name: NSNotification.Name("MAD_SwitchTab"),
                object: nil,
                userInfo: ["tab": 3]
            )
        case "competition_invite", "competition_accepted", "competition_started",
             "competition_finished", "competition_nudge", "competition_flex",
             "competition_milestone", "lead_change", "clash_tie":
            if let compId = notification.data?["competition_id"],
               let comp = competitionService.competitions.first(where: { $0.competition_id == compId })
                       ?? competitionService.invites.first(where: { $0.competition_id == compId }) {
                selectedCompetition = comp
            } else {
                NotificationCenter.default.post(
                    name: NSNotification.Name("MAD_SwitchTab"),
                    object: nil,
                    userInfo: ["tab": 1]
                )
            }
        case "personal_best":
            NotificationCenter.default.post(
                name: NSNotification.Name("MAD_SwitchTab"),
                object: nil,
                userInfo: ["tab": 4]
            )
        default:
            break
        }
    }

    private func notificationRow(_ notification: InAppNotification) -> some View {
        let accent = notificationColor(for: notification.type)
        let isUnread = !notification.is_read

        return Button {
            handleNotificationTap(notification)
        } label: {
            HStack(alignment: .top, spacing: MADTheme.Spacing.md) {
                // Larger type icon with colored gradient disc — reads as a
                // "feed event avatar" rather than a small system glyph.
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

                    Text(notification.title)
                        .font(.system(size: 14, weight: isUnread ? .heavy : .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)

                    Text(notification.body)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

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

                if isUnread {
                    Circle()
                        .fill(MADTheme.Colors.madRed)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
            }
            .padding(MADTheme.Spacing.md)
            .background(
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(isUnread ? Color.white.opacity(0.06) : Color.white.opacity(0.03))

                    // Colored leading stripe — quick visual identifier for
                    // the notification type. Plain rectangle clipped by the
                    // outer rounded shape so it hugs the card's curve
                    // instead of overflowing past the rounded corners.
                    Rectangle()
                        .fill(accent.opacity(isUnread ? 0.85 : 0.35))
                        .frame(width: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large, style: .continuous)
                        .strokeBorder(Color.white.opacity(isUnread ? 0.10 : 0.05), lineWidth: 1)
                )
            )
        }
        .buttonStyle(.plain)
    }

    /// Friendly category label paired with each row's icon. Matches the
    /// `iconForType` casing so users see "FRIEND · 5m ago" at a glance.
    private func typeLabel(for type: String) -> String {
        switch type {
        case "friend_request": return "FRIEND REQUEST"
        case "friend_request_accepted": return "FRIEND"
        case "friend_nudge": return "NUDGE"
        case "friend_activity": return "FRIEND"
        case "friend_badge_earned": return "FRIEND BADGE"
        case "friend_personal_best": return "FRIEND PR"
        case "friend_challenge_completed": return "FRIEND CHALLENGE"
        case "competition_invite": return "COMP INVITE"
        case "competition_accepted": return "COMP JOINED"
        case "competition_started": return "COMP STARTED"
        case "competition_finished": return "COMP FINISHED"
        case "competition_nudge": return "COMP NUDGE"
        case "competition_flex": return "FLEX"
        case "competition_milestone": return "MILESTONE"
        case "streak_broken": return "STREAK"
        case "personal_best": return "PERSONAL BEST"
        case "badge_earned": return "BADGE"
        case "lead_change": return "LEAD CHANGE"
        case "clash_tie": return "CLASH TIE"
        default: return "UPDATE"
        }
    }

    // MARK: - Helpers

    private func notificationIcon(for type: String) -> some View {
        let (icon, color) = iconForType(type)
        return Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(color)
    }

    private func iconForType(_ type: String) -> (String, Color) {
        switch type {
        case "friend_request": return ("person.badge.plus", .blue)
        case "friend_request_accepted": return ("person.2.fill", .green)
        case "friend_nudge": return ("bell.badge", .orange)
        case "friend_activity": return ("figure.run", .green)
        case "competition_invite": return ("envelope.fill", .purple)
        case "competition_accepted": return ("checkmark.circle", .green)
        case "competition_started": return ("flag.fill", .blue)
        case "competition_finished": return ("trophy.fill", .yellow)
        case "competition_nudge": return ("bell.badge", .orange)
        case "competition_flex": return ("flame.fill", .red)
        case "competition_milestone": return ("star.fill", .yellow)
        case "streak_broken": return ("flame.fill", .red)
        case "personal_best": return ("medal.fill", .yellow)
        case "lead_change": return ("arrow.up.right", .green)
        case "clash_tie": return ("equal.circle.fill", .purple)
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
            is_hyped: n.is_hyped
        )
    }

}

#Preview {
    NavigationStack {
        NotificationInboxView(competitionService: CompetitionService())
    }
}
