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

    private var dndStartBinding: Binding<Date> {
        Binding {
            var comps = DateComponents()
            comps.hour = prefs.dndStartHour
            comps.minute = 0
            return Calendar.current.date(from: comps) ?? Date()
        } set: { date in
            prefs.dndStartHour = Calendar.current.component(.hour, from: date)
        }
    }

    private var dndEndBinding: Binding<Date> {
        Binding {
            var comps = DateComponents()
            comps.hour = prefs.dndEndHour
            comps.minute = 0
            return Calendar.current.date(from: comps) ?? Date()
        } set: { date in
            prefs.dndEndHour = Calendar.current.component(.hour, from: date)
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

                    // Do Not Disturb Schedule
                    settingsSection(title: "DO NOT DISTURB", icon: "moon.fill", iconColor: .indigo) {
                        settingsToggle("Enable DND Schedule", isOn: $prefs.dndEnabled,
                            description: "Silence all notifications during scheduled hours")

                        if prefs.dndEnabled {
                            settingsDivider

                            DatePicker("Start", selection: dndStartBinding, displayedComponents: .hourAndMinute)
                                .font(MADTheme.Typography.body)
                                .datePickerStyle(.compact)
                                .tint(MADTheme.Colors.madRed)

                            DatePicker("End", selection: dndEndBinding, displayedComponents: .hourAndMinute)
                                .font(MADTheme.Typography.body)
                                .datePickerStyle(.compact)
                                .tint(MADTheme.Colors.madRed)

                            Text("Notifications received during DND will appear in your inbox")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.white.opacity(0.35))
                                .padding(.top, 2)
                        }
                    }

                    // Reset to Defaults
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            prefs = .default
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack(spacing: MADTheme.Spacing.sm) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Reset to Defaults")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MADTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                .fill(Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)

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
                    HStack(spacing: 4) {
                        Image(systemName: isMuted ? "bell.slash.fill" : "bell.fill")
                            .font(.system(size: 12))
                        Text(isMuted ? "Muted" : "On")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(isMuted ? .red.opacity(0.7) : .green.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(isMuted ? Color.red.opacity(0.1) : Color.green.opacity(0.08))
                            .overlay(
                                Capsule()
                                    .stroke(isMuted ? Color.red.opacity(0.2) : Color.green.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }

            if !isMuted {
                HStack(spacing: MADTheme.Spacing.sm) {
                    Text("Tap to toggle:")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.white.opacity(0.25))

                    notificationToggleChip(
                        label: "Nudges",
                        icon: "bell.badge",
                        isEnabled: !nudgesMuted,
                        action: { toggleFriendNudgesMute(friendId: friend.user_id, currentlyMuted: nudgesMuted) }
                    )

                    notificationToggleChip(
                        label: "Activity",
                        icon: "figure.run",
                        isEnabled: !activityMuted,
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

    private func notificationToggleChip(label: String, icon: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isEnabled ? icon : "slash.circle")
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .foregroundColor(isEnabled ? .green.opacity(0.8) : .red.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isEnabled ? Color.green.opacity(0.06) : Color.red.opacity(0.08))
                    .overlay(
                        Capsule()
                            .stroke(isEnabled ? Color.green.opacity(0.12) : Color.red.opacity(0.15), lineWidth: 1)
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
                // Load friends list if not already loaded
                if friendService.friends.isEmpty {
                    try await friendService.loadFriends()
                }
                let settings = try await friendService.getFriendNotificationSettings()
                await MainActor.run {
                    friendSettings = settings
                    isLoadingFriendSettings = false
                }
            } catch {
                print("[NotifSettings] ❌ loadFriendSettings failed: \(error)")
                await MainActor.run {
                    isLoadingFriendSettings = false
                }
            }
        }
    }

    private func toggleFriendMute(friendId: String, currentlyMuted: Bool) {
        // Optimistic update
        let existing = friendSettings.first(where: { $0.friend_id == friendId })
        let optimistic = FriendNotificationSetting(
            friend_id: friendId,
            username: existing?.username,
            muted: !currentlyMuted,
            nudges_muted: existing?.nudges_muted ?? false,
            activity_muted: existing?.activity_muted ?? false
        )
        updateLocalFriendSetting(optimistic)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            do {
                let updated = try await friendService.updateFriendNotificationSettings(
                    friendId: friendId,
                    muted: !currentlyMuted
                )
                await MainActor.run { updateLocalFriendSetting(updated) }
            } catch {
                print("[NotifSettings] ❌ toggleFriendMute failed: \(error)")
                await MainActor.run {
                    let reverted = FriendNotificationSetting(
                        friend_id: friendId,
                        username: existing?.username,
                        muted: currentlyMuted,
                        nudges_muted: existing?.nudges_muted ?? false,
                        activity_muted: existing?.activity_muted ?? false
                    )
                    updateLocalFriendSetting(reverted)
                }
            }
        }
    }

    private func toggleFriendNudgesMute(friendId: String, currentlyMuted: Bool) {
        let existing = friendSettings.first(where: { $0.friend_id == friendId })
        let optimistic = FriendNotificationSetting(
            friend_id: friendId,
            username: existing?.username,
            muted: existing?.muted ?? false,
            nudges_muted: !currentlyMuted,
            activity_muted: existing?.activity_muted ?? false
        )
        updateLocalFriendSetting(optimistic)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            do {
                let updated = try await friendService.updateFriendNotificationSettings(
                    friendId: friendId,
                    nudgesMuted: !currentlyMuted
                )
                await MainActor.run { updateLocalFriendSetting(updated) }
            } catch {
                print("[NotifSettings] ❌ toggleFriendNudgesMute failed: \(error)")
                await MainActor.run {
                    let reverted = FriendNotificationSetting(
                        friend_id: friendId,
                        username: existing?.username,
                        muted: existing?.muted ?? false,
                        nudges_muted: currentlyMuted,
                        activity_muted: existing?.activity_muted ?? false
                    )
                    updateLocalFriendSetting(reverted)
                }
            }
        }
    }

    private func toggleFriendActivityMute(friendId: String, currentlyMuted: Bool) {
        let existing = friendSettings.first(where: { $0.friend_id == friendId })
        let optimistic = FriendNotificationSetting(
            friend_id: friendId,
            username: existing?.username,
            muted: existing?.muted ?? false,
            nudges_muted: existing?.nudges_muted ?? false,
            activity_muted: !currentlyMuted
        )
        updateLocalFriendSetting(optimistic)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            do {
                let updated = try await friendService.updateFriendNotificationSettings(
                    friendId: friendId,
                    activityMuted: !currentlyMuted
                )
                await MainActor.run { updateLocalFriendSetting(updated) }
            } catch {
                print("[NotifSettings] ❌ toggleFriendActivityMute failed: \(error)")
                await MainActor.run {
                    let reverted = FriendNotificationSetting(
                        friend_id: friendId,
                        username: existing?.username,
                        muted: existing?.muted ?? false,
                        nudges_muted: existing?.nudges_muted ?? false,
                        activity_muted: currentlyMuted
                    )
                    updateLocalFriendSetting(reverted)
                }
            }
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
