import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @State private var prefs = NotificationPreferences.load()
    @ObservedObject private var notificationService = MADNotificationService.shared
    @StateObject private var friendService = FriendService()

    // Friend-specific settings
    @State private var friendSettings: [FriendNotificationSetting] = []
    @State private var isLoadingFriendSettings = false
    @State private var showFriendSettings = false
    @State private var savedFeedback = false

    // Convert stored hour into Date for DatePicker and vice-versa
    private var reminderTimeBinding: Binding<Date> {
        Binding {
            var comps = DateComponents()
            comps.hour = prefs.dailyReminderHour
            comps.minute = 0
            return Calendar.current.date(from: comps) ?? Date()
        } set: { date in
            let hour = Calendar.current.component(.hour, from: date)
            prefs.dailyReminderHour = hour
        }
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    // Daily Reminder Section
                    settingsSection(title: "DAILY REMINDER", icon: "alarm.fill", iconColor: .orange) {
                        Toggle("Enable Daily Reminder", isOn: $prefs.dailyReminderEnabled)
                            .font(MADTheme.Typography.body)
                            .tint(MADTheme.Colors.madRed)

                        if prefs.dailyReminderEnabled {
                            Divider().overlay(Color.white.opacity(0.06))

                            DatePicker("Reminder Time", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                                .font(MADTheme.Typography.body)
                                .datePickerStyle(.compact)
                                .tint(MADTheme.Colors.madRed)
                        }
                    }

                    // Activity Notifications
                    settingsSection(title: "ACTIVITY", icon: "figure.run", iconColor: .green) {
                        settingsToggle("When I complete a mile", isOn: $prefs.mileCompletedEnabled)
                        settingsDivider
                        settingsToggle("When a friend completes a mile", isOn: $prefs.friendCompletedEnabled)
                    }

                    // Social Notifications
                    settingsSection(title: "SOCIAL", icon: "person.2.fill", iconColor: .blue) {
                        settingsToggle("Friend requests", isOn: $prefs.friendRequestReceivedEnabled)
                        settingsDivider
                        settingsToggle("Friend request accepted", isOn: $prefs.friendRequestAcceptedEnabled)
                        settingsDivider
                        settingsToggle("Friend nudges", isOn: $prefs.friendNudgeEnabled)
                    }

                    // Competition Notifications
                    settingsSection(title: "COMPETITIONS", icon: "trophy.fill", iconColor: .yellow) {
                        settingsToggle("Competition invites", isOn: $prefs.competitionInviteEnabled)
                        settingsDivider
                        settingsToggle("Invite accepted", isOn: $prefs.competitionAcceptedEnabled)
                        settingsDivider
                        settingsToggle("Competition started", isOn: $prefs.competitionStartEnabled)
                        settingsDivider
                        settingsToggle("Competition finished", isOn: $prefs.competitionFinishEnabled)
                        settingsDivider
                        settingsToggle("Competition nudges", isOn: $prefs.competitionNudgeEnabled)
                        settingsDivider
                        settingsToggle("Flex notifications", isOn: $prefs.competitionFlexEnabled)
                        settingsDivider
                        settingsToggle("Milestones & updates", isOn: $prefs.competitionMilestonesEnabled,
                            description: "Halfway marks, one point from winning, and more")
                    }

                    // Friend-Specific Settings
                    settingsSection(title: "FRIEND-SPECIFIC", icon: "person.crop.circle.badge.minus", iconColor: .purple) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showFriendSettings.toggle()
                            }
                            if showFriendSettings && friendSettings.isEmpty {
                                loadFriendSettings()
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Manage friend notifications")
                                        .font(MADTheme.Typography.body)
                                        .foregroundColor(.white)
                                    Text("Mute specific friends or notification types")
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                Spacer()
                                Image(systemName: showFriendSettings ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        }
                        .buttonStyle(.plain)

                        if showFriendSettings {
                            settingsDivider

                            if isLoadingFriendSettings {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(MADTheme.Colors.madRed)
                                    Text("Loading...")
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                .padding(.vertical, MADTheme.Spacing.sm)
                            } else if friendService.friends.isEmpty {
                                Text("No friends to configure")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundColor(.white.opacity(0.4))
                                    .padding(.vertical, MADTheme.Spacing.sm)
                            } else {
                                friendNotificationList
                            }
                        }
                    }

                    Spacer(minLength: MADTheme.Spacing.xxl)
                }
                .padding(MADTheme.Spacing.md)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveAndApply()
                }
                .foregroundColor(MADTheme.Colors.madRed)
                .fontWeight(.semibold)
            }
        }
        .overlay(alignment: .bottom) {
            if savedFeedback {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                    Text("Settings saved")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.15))
                        .overlay(Capsule().stroke(Color.green.opacity(0.2), lineWidth: 1))
                )
                .padding(.bottom, MADTheme.Spacing.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            await friendService.refreshAllData()
        }
    }

    // MARK: - Settings Section
    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(iconColor)

                Text(title)
                    .font(MADTheme.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.5)
            }

            content()
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    // MARK: - Settings Toggle
    private func settingsToggle(_ label: String, isOn: Binding<Bool>, description: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(label, isOn: isOn)
                .font(MADTheme.Typography.body)
                .tint(MADTheme.Colors.madRed)

            if let description = description {
                Text(description)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.leading, 2)
            }
        }
    }

    private var settingsDivider: some View {
        Divider().overlay(Color.white.opacity(0.06))
    }

    // MARK: - Friend Notification List
    private var friendNotificationList: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ForEach(friendService.friends) { friend in
                friendNotificationRow(friend: friend)
            }
        }
    }

    private func friendNotificationRow(friend: BackendUser) -> some View {
        let setting = friendSettings.first(where: { $0.friend_id == friend.user_id })
        let isMuted = setting?.muted ?? false
        let nudgesMuted = setting?.nudges_muted ?? false
        let activityMuted = setting?.activity_muted ?? false

        return VStack(spacing: MADTheme.Spacing.sm) {
            HStack(spacing: MADTheme.Spacing.sm) {
                AvatarView(name: friend.displayName, imageURL: friend.profile_image_url, size: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(friend.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    if let username = friend.username {
                        Text("@\(username)")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }

                Spacer()

                // Mute all toggle
                Button {
                    toggleFriendMute(friendId: friend.user_id, currentlyMuted: isMuted)
                } label: {
                    Image(systemName: isMuted ? "bell.slash.fill" : "bell.fill")
                        .font(.system(size: 12))
                        .foregroundColor(isMuted ? .red.opacity(0.6) : .white.opacity(0.4))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(isMuted ? Color.red.opacity(0.1) : Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }

            if !isMuted {
                HStack(spacing: MADTheme.Spacing.sm) {
                    muteChip(
                        label: "Nudges",
                        icon: "bell.badge",
                        isMuted: nudgesMuted,
                        action: { toggleFriendNudgesMute(friendId: friend.user_id, currentlyMuted: nudgesMuted) }
                    )

                    muteChip(
                        label: "Activity",
                        icon: "figure.run",
                        isMuted: activityMuted,
                        action: { toggleFriendActivityMute(friendId: friend.user_id, currentlyMuted: activityMuted) }
                    )

                    Spacer()
                }
            }
        }
        .padding(MADTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                .fill(Color.white.opacity(0.03))
        )
    }

    private func muteChip(label: String, icon: String, isMuted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isMuted ? "slash.circle" : icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .foregroundColor(isMuted ? .red.opacity(0.7) : .white.opacity(0.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isMuted ? Color.red.opacity(0.08) : Color.white.opacity(0.04))
                    .overlay(
                        Capsule()
                            .stroke(isMuted ? Color.red.opacity(0.15) : Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Actions

    private func saveAndApply() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        prefs.save()
        if prefs.dailyReminderEnabled {
            let widgetData = WidgetDataStore.load()
            notificationService.updateDailyReminder(
                isCompleted: widgetData.miles >= widgetData.goal,
                currentMiles: widgetData.miles,
                goalMiles: widgetData.goal,
                at: prefs.dailyReminderHour
            )
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [MADNotificationService.Identifier.dailyReminder])
        }

        // Show feedback
        withAnimation(.easeInOut(duration: 0.2)) { savedFeedback = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) { savedFeedback = false }
        }
    }

    private func loadFriendSettings() {
        isLoadingFriendSettings = true
        Task {
            do {
                let settings = try await friendService.getFriendNotificationSettings()
                await MainActor.run {
                    friendSettings = settings
                    isLoadingFriendSettings = false
                }
            } catch {
                await MainActor.run {
                    isLoadingFriendSettings = false
                }
            }
        }
    }

    private func toggleFriendMute(friendId: String, currentlyMuted: Bool) {
        Task {
            do {
                let updated = try await friendService.updateFriendNotificationSettings(
                    friendId: friendId,
                    muted: !currentlyMuted
                )
                await MainActor.run {
                    updateLocalFriendSetting(updated)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } catch {
                // Silently fail
            }
        }
    }

    private func toggleFriendNudgesMute(friendId: String, currentlyMuted: Bool) {
        Task {
            do {
                let updated = try await friendService.updateFriendNotificationSettings(
                    friendId: friendId,
                    nudgesMuted: !currentlyMuted
                )
                await MainActor.run {
                    updateLocalFriendSetting(updated)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } catch { }
        }
    }

    private func toggleFriendActivityMute(friendId: String, currentlyMuted: Bool) {
        Task {
            do {
                let updated = try await friendService.updateFriendNotificationSettings(
                    friendId: friendId,
                    activityMuted: !currentlyMuted
                )
                await MainActor.run {
                    updateLocalFriendSetting(updated)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } catch { }
        }
    }

    private func updateLocalFriendSetting(_ setting: FriendNotificationSetting) {
        if let index = friendSettings.firstIndex(where: { $0.friend_id == setting.friend_id }) {
            friendSettings[index] = setting
        } else {
            friendSettings.append(setting)
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
