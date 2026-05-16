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
                VStack(spacing: MADTheme.Spacing.md) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.15))
                    Text("No notifications yet")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                    Text("Your activity feed will appear here")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.white.opacity(0.25))
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: MADTheme.Spacing.sm) {
                        ForEach(notifications) { notification in
                            notificationRow(notification)
                                .onAppear {
                                    if notification.id == notifications.last?.id && hasMore {
                                        loadMore()
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
                    .padding(MADTheme.Spacing.md)
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if unreadCount > 0 {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Read All") {
                        markAllRead()
                    }
                    .foregroundColor(MADTheme.Colors.madRed)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
            }
        }
        .task {
            await loadNotifications()
        }
        .refreshable {
            await loadNotifications()
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

    private func showHypeToast(_ message: String) {
        hypeToast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { hypeToast = nil }
        }
    }

    /// Derive hype affordance directly from the notification's type + data payload.
    /// Independent of server enrichment so the button works against any backend version.
    /// Returns nil for non-celebratory rows (streak broken, friend requests, competition
    /// notifications, etc.).
    private func hypeAffordance(for notification: InAppNotification) -> HypeContext? {
        let data = notification.data ?? [:]

        switch notification.type {
        case "friend_activity":
            // Skip the streak-broken variant — that's sympathetic, not celebratory.
            if data["kind"] == "streak_broken" { return nil }
            if notification.title.hasPrefix("Streak broken") { return nil }
            guard let targetId = data["user_id"] else { return nil }
            // user_id:YYYY-MM-DD as the dedupe key (one mile per day per user).
            let dateKey = String(notification.created_at.prefix(10))
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
        hypeAffordance(for: notification) != nil
    }

    /// True when this row has already been hyped (server-side flag or local optimistic).
    private func isAlreadyHyped(_ notification: InAppNotification) -> Bool {
        notification.is_hyped == true || hypedRowIds.contains(notification.id)
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
                _ = try await HypeService.sendHype(targetUserId: targetId, context: context)
                // Success — stay greyed out.
            } catch APIError.conflict {
                // Already hyped server-side; stay greyed out, no toast.
            } catch APIError.rateLimited(let msg) {
                await MainActor.run {
                    hypedRowIds.remove(notification.id)
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
            _ = try await HypeService.sendHype(targetUserId: targetId)
            // Stay greyed out.
        } catch APIError.rateLimited(let msg) {
            await MainActor.run {
                hypedRowIds.remove(notification.id)
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
                userInfo: ["tab": 2]
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
                userInfo: ["tab": 3]
            )
        default:
            break
        }
    }

    private func notificationRow(_ notification: InAppNotification) -> some View {
        Button {
            handleNotificationTap(notification)
        } label: {
            HStack(alignment: .top, spacing: MADTheme.Spacing.md) {
                // Type icon
                notificationIcon(for: notification.type)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(notificationColor(for: notification.type).opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(notification.title)
                        .font(.system(size: 13, weight: notification.is_read ? .medium : .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(notification.body)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)

                    Text(relativeTime(notification.created_at))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.top, 1)
                }

                Spacer()

                if canShowHypeButton(notification) {
                    let hyped = isAlreadyHyped(notification)
                    Button {
                        if !hyped { performHype(notification) }
                    } label: {
                        HStack(spacing: 4) {
                            Text("🔥")
                                .font(.system(size: 13))
                                .opacity(hyped ? 0.4 : 1)
                            Text(hyped ? "Hyped" : "Hype")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(hyped ? .white.opacity(0.35) : .orange)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                hyped ? Color.white.opacity(0.06) : Color.orange.opacity(0.18)
                            )
                        )
                    }
                    .buttonStyle(.borderless)
                    .disabled(hyped)
                }

                if !notification.is_read {
                    Circle()
                        .fill(MADTheme.Colors.madRed)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(MADTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(notification.is_read ? Color.white.opacity(0.03) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .stroke(Color.white.opacity(notification.is_read ? 0.04 : 0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
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

    private func loadNotifications() async {
        isLoading = true
        do {
            let response = try await friendService.getInboxNotifications()
            await MainActor.run {
                notifications = response.notifications
                unreadCount = response.unread_count
                hasMore = response.notifications.count >= 50
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
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
                    // Create updated notification with is_read = true
                    let n = notifications[idx]
                    notifications[idx] = InAppNotification(
                        id: n.id, title: n.title, body: n.body,
                        type: n.type, data: n.data, is_read: true,
                        created_at: n.created_at,
                        hype_target_user_id: n.hype_target_user_id,
                        hype_context_type: n.hype_context_type,
                        hype_context_id: n.hype_context_id,
                        hype_context_label: n.hype_context_label,
                        is_hyped: n.is_hyped
                    )
                    unreadCount = max(0, unreadCount - 1)
                }
            }
        }
    }

    private func markAllRead() {
        Task {
            try? await friendService.markAllNotificationsRead()
            await MainActor.run {
                notifications = notifications.map { n in
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
                unreadCount = 0
            }
        }
    }
}

#Preview {
    NavigationStack {
        NotificationInboxView(competitionService: CompetitionService())
    }
}
