import SwiftUI

struct NotificationInboxView: View {
    var onUnreadCountChanged: ((Int) -> Void)?

    @StateObject private var friendService = FriendService()
    @State private var notifications: [InAppNotification] = []
    @State private var unreadCount = 0
    @State private var isLoading = true
    @State private var hasMore = true

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
    }

    // MARK: - Notification Row

    private func notificationRow(_ notification: InAppNotification) -> some View {
        Button {
            if !notification.is_read {
                markRead(notification)
            }
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
                        created_at: n.created_at
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
                        created_at: n.created_at
                    )
                }
                unreadCount = 0
            }
        }
    }
}

#Preview {
    NavigationStack {
        NotificationInboxView()
    }
}
