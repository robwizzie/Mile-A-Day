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
                        settingsDivider
                        settingsToggle("When a friend hits a personal best", isOn: $prefs.friendPersonalBestEnabled,
                            description: "Fastest mile or most miles in a day")
                        settingsDivider
                        settingsToggle("Step goal", isOn: $prefs.stepGoalEnabled,
                            description: "When you reach 10,000 steps in a day")
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
                        settingsToggle("Hype reactions", isOn: $prefs.hypeEnabled,
                            description: "When a friend or competitor cheers on your completed mile")
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
            await loadFriendSettingsAsync()
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
                FriendNotificationRowView(
                    friend: friend,
                    settings: $friendSettings,
                    friendService: friendService
                )
            }
        }
    }

    // MARK: - Actions

    private func saveAndApply() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        prefs.save()
        // Daily reminder is now backend-driven (server cron + APNs push). Clear
        // any legacy local-notification still pending from older app versions —
        // the backend respects `daily_reminder_enabled` and `daily_reminder_hour`
        // which are synced below as part of the prefs payload.
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [MADNotificationService.Identifier.dailyReminder])

        // Sync preferences to the backend so push notification filtering works
        Task {
            do {
                let backendSettings: [String: Any] = [
                    "nudges_enabled": prefs.friendNudgeEnabled && prefs.competitionNudgeEnabled,
                    "flexes_enabled": prefs.competitionFlexEnabled,
                    "hypes_enabled": prefs.hypeEnabled,
                    "step_goal_enabled": prefs.stepGoalEnabled,
                    "friend_activity_enabled": prefs.friendCompletedEnabled,
                    "friend_personal_best_enabled": prefs.friendPersonalBestEnabled,
                    "competition_invites_enabled": prefs.competitionInviteEnabled,
                    "competition_updates_enabled": prefs.competitionAcceptedEnabled && prefs.competitionStartEnabled && prefs.competitionFinishEnabled,
                    "competition_milestones_enabled": prefs.competitionMilestonesEnabled,
                    "quiet_hours_start": prefs.dndEnabled ? prefs.dndStartHour : NSNull(),
                    "quiet_hours_end": prefs.dndEnabled ? prefs.dndEndHour : NSNull(),
                    "daily_reminder_enabled": prefs.dailyReminderEnabled,
                    "daily_reminder_hour": prefs.dailyReminderHour,
                    "timezone_offset_minutes": TimeZone.current.secondsFromGMT() / 60,
                ]
                _ = try await friendService.updateNotificationSettings(backendSettings)
            } catch {
                print("[NotifSettings] ❌ Failed to sync preferences to backend: \(error)")
            }
        }

        // Show feedback
        withAnimation(.easeInOut(duration: 0.2)) { savedFeedback = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) { savedFeedback = false }
        }
    }

    private func loadFriendSettingsAsync() async {
        await MainActor.run { isLoadingFriendSettings = true }
        do {
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
            await MainActor.run { isLoadingFriendSettings = false }
        }
    }

}

// MARK: - Friend Notification Row

struct FriendNotificationRowView: View {
    let friend: BackendUser
    @Binding var settings: [FriendNotificationSetting]
    let friendService: FriendService

    private var isMuted: Bool {
        settings.first(where: { $0.friend_id == friend.user_id })?.muted ?? false
    }
    private var isNudgesMuted: Bool {
        settings.first(where: { $0.friend_id == friend.user_id })?.nudges_muted ?? false
    }
    private var isActivityMuted: Bool {
        settings.first(where: { $0.friend_id == friend.user_id })?.activity_muted ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Friend header + mute all toggle
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

                Toggle("", isOn: Binding(
                    get: { !isMuted },
                    set: { newEnabled in
                        syncToBackend(muted: !newEnabled)
                    }
                ))
                .labelsHidden()
                .tint(MADTheme.Colors.madRed)
            }

            if !isMuted {
                Divider().overlay(Color.white.opacity(0.06)).padding(.vertical, 8)

                // Sub-toggles
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                            .frame(width: 20)
                        Text("Nudges")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !isNudgesMuted },
                            set: { newEnabled in
                                syncToBackend(nudgesMuted: !newEnabled)
                            }
                        ))
                        .labelsHidden()
                        .tint(MADTheme.Colors.madRed)
                        .scaleEffect(0.85)
                    }

                    HStack {
                        Image(systemName: "figure.run")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                            .frame(width: 20)
                        Text("Activity")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !isActivityMuted },
                            set: { newEnabled in
                                syncToBackend(activityMuted: !newEnabled)
                            }
                        ))
                        .labelsHidden()
                        .tint(MADTheme.Colors.madRed)
                        .scaleEffect(0.85)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                .fill(Color.white.opacity(0.03))
        )
    }

    private func syncToBackend(muted: Bool? = nil, nudgesMuted: Bool? = nil, activityMuted: Bool? = nil) {
        let updated = FriendNotificationSetting(
            friend_id: friend.user_id,
            username: friend.username,
            muted: muted ?? isMuted,
            nudges_muted: nudgesMuted ?? isNudgesMuted,
            activity_muted: activityMuted ?? isActivityMuted
        )
        if let index = settings.firstIndex(where: { $0.friend_id == friend.user_id }) {
            settings[index] = updated
        } else {
            settings.append(updated)
        }

        Task {
            do {
                _ = try await friendService.updateFriendNotificationSettings(
                    friendId: friend.user_id,
                    muted: muted,
                    nudgesMuted: nudgesMuted,
                    activityMuted: activityMuted
                )
            } catch {
                print("[NotifSettings] ❌ sync failed: \(error)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
