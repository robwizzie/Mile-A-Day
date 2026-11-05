import SwiftUI
import UserNotifications

/// Alerts only: what Mile A Day tells you about, and when.
///
/// This page used to hold the privacy controls too (who can see my workouts,
/// feed sharing, route maps, flyovers, Stealth Mode, the profile grid), and
/// Privacy linked here for them, so the same settings had two doors. Those now
/// live on `PrivacyHubView` and save from there; this page sends only the
/// alert keys (`NotificationPreferences.alertPayload`).
struct NotificationSettingsView: View {
    @State private var prefs = NotificationPreferences.load()
    /// At-risk streak Live Activity master switch (default on; the activity
    /// only appears when the streak is genuinely about to die).
    @State private var streakRiskActivityEnabled = StreakRiskActivityManager.isEnabled

    /// Persists the switch and retires any activity already on the lock
    /// screen the moment it's turned off. (A didSet on @State never fires
    /// through a Toggle's binding — the custom Binding is the reliable hook.)
    private var streakRiskBinding: Binding<Bool> {
        Binding(
            get: { streakRiskActivityEnabled },
            set: { newValue in
                streakRiskActivityEnabled = newValue
                StreakRiskActivityManager.isEnabled = newValue
                if !newValue {
                    StreakRiskActivityManager.sync(
                        isAtRisk: false, isCompleted: false, streak: 0,
                        goalMiles: 1, currentMiles: 0
                    )
                }
            }
        )
    }
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

    // True when any of the 8 competition alerts is on — drives the collapsed
    // master toggle and whether the "Customize" drill-in is shown.
    private var anyCompetitionEnabled: Bool {
        prefs.competitionInviteEnabled || prefs.competitionAcceptedEnabled
            || prefs.competitionStartEnabled || prefs.competitionFinishEnabled
            || prefs.competitionNudgeEnabled || prefs.competitionFlexEnabled
            || prefs.hypeEnabled || prefs.competitionMilestonesEnabled
    }

    // Master toggle: reading is "any on"; turning it off silences all eight,
    // turning it on enables all eight. Granular control lives on the drill-in.
    private var competitionsMasterBinding: Binding<Bool> {
        Binding {
            anyCompetitionEnabled
        } set: { newValue in
            prefs.competitionInviteEnabled = newValue
            prefs.competitionAcceptedEnabled = newValue
            prefs.competitionStartEnabled = newValue
            prefs.competitionFinishEnabled = newValue
            prefs.competitionNudgeEnabled = newValue
            prefs.competitionFlexEnabled = newValue
            prefs.hypeEnabled = newValue
            prefs.competitionMilestonesEnabled = newValue
        }
    }

    var body: some View {
        ZStack {
            MADTheme.Colors.appBackgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    SettingsSection("Your activity") {
                        settingsToggle("When I complete a mile", isOn: $prefs.mileCompletedEnabled)
                        settingsDivider
                        settingsToggle("Step goal", isOn: $prefs.stepGoalEnabled,
                            description: "When you reach 10,000 steps in a day")
                    }

                    friendsSection

                    SettingsSection("Recaps & challenges") {
                        settingsToggle("Weekly recap", isOn: $prefs.weeklyRecapEnabled,
                            description: "A Sunday summary of your week, ready to share")
                        settingsDivider
                        settingsToggle("Weekly challenge", isOn: $prefs.weeklyChallengeEnabled,
                            description: "The new challenge, a nudge before it ends, and when you finish")
                        settingsDivider
                        // Competition alerts collapse behind a master toggle;
                        // the 8 individual alerts live on a drill-in screen.
                        settingsToggle("Competitions", isOn: competitionsMasterBinding,
                            description: "Invites, status, cheers and milestones")

                        if anyCompetitionEnabled {
                            settingsDivider

                            NavigationLink(destination: CompetitionNotificationSettingsView(prefs: $prefs, onSave: saveAndApply)) {
                                SettingsRow(
                                    icon: "slider.horizontal.3",
                                    title: "Choose competition alerts"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    muteFriendsSection

                    scheduleSection

                    // Resets the alerts only: the privacy half of the stored
                    // prefs belongs to Privacy and is carried over untouched.
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            var reset = NotificationPreferences.default
                            reset.takeSharing(from: prefs)
                            reset.routePrivacyMeters = prefs.routePrivacyMeters
                            prefs = reset
                        }
                        MADHaptics.action()
                    } label: {
                        Text("Reset to defaults")
                            .madFont(size: 14, weight: .medium, design: .rounded)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, MADTheme.Spacing.sm)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: MADTheme.Spacing.xl)
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
                .background(Capsule().fill(Color.green.opacity(0.15)))
                .padding(.bottom, MADTheme.Spacing.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            await friendService.refreshAllData()
            await loadFriendSettingsAsync()
            await loadServerSettings()
        }
    }

    // MARK: - Sections

    private var friendsSection: some View {
        SettingsSection("Friends") {
            // Audience controls for who hears about your activity (and whose
            // you hear about).
            NavigationLink(destination: FriendActivitySettingsView()) {
                SettingsRow(
                    icon: "person.2.wave.2.fill",
                    title: "Friend activity",
                    subtitle: "Who hears about your runs, walks and PBs",
                    tint: MADTheme.Colors.madRed
                )
            }
            .buttonStyle(.plain)
            settingsDivider
            settingsToggle("When a friend completes a mile", isOn: $prefs.friendCompletedEnabled)
            settingsDivider
            settingsToggle("When a friend hits a personal best", isOn: $prefs.friendPersonalBestEnabled,
                description: "Fastest mile or most miles in a day")
            settingsDivider
            settingsToggle("New posts from friends", isOn: $prefs.friendPostsEnabled)
            settingsDivider
            settingsToggle("Friend requests", isOn: $prefs.friendRequestReceivedEnabled)
            settingsDivider
            settingsToggle("Friend request reminders", isOn: $prefs.friendRequestReminderEnabled,
                description: "A nudge about requests you haven't answered")
            settingsDivider
            settingsToggle("Friend request accepted", isOn: $prefs.friendRequestAcceptedEnabled)
            settingsDivider
            settingsToggle("Friend nudges", isOn: $prefs.friendNudgeEnabled)
            settingsDivider
            settingsToggle("Buddy walks & runs", isOn: $prefs.buddyInvitesEnabled,
                description: "Off stops invites and takes you out of friends' pickers")
        }
    }

    private var muteFriendsSection: some View {
        SettingsSection("Mute friends") {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showFriendSettings.toggle()
                }
            } label: {
                HStack {
                    Text("Mute a friend's alerts")
                        .madFont(size: 16, weight: .medium, design: .rounded)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .madFont(size: 12, weight: .semibold, maxScale: 1.5)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(showFriendSettings ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
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
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, MADTheme.Spacing.sm)
                } else if friendService.friends.isEmpty {
                    Text("No friends yet")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.vertical, MADTheme.Spacing.sm)
                } else {
                    friendNotificationList
                        .padding(.top, MADTheme.Spacing.sm)
                }
            }
        }
    }

    /// Daily reminder + Do Not Disturb together: both are time-based and the
    /// least often changed.
    private var scheduleSection: some View {
        SettingsSection("Schedule") {
            settingsToggle("Daily reminder", isOn: $prefs.dailyReminderEnabled,
                description: "A nudge to get your mile in")

            if prefs.dailyReminderEnabled {
                DatePicker("Reminder time", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                    .font(MADTheme.Typography.body)
                    .datePickerStyle(.compact)
                    .tint(MADTheme.Colors.madRed)
                    .padding(.bottom, 6)
            }

            settingsDivider

            settingsToggle("Streak countdown on Lock Screen", isOn: streakRiskBinding,
                description: "Time left when your streak is at risk in the evening")

            settingsDivider

            settingsToggle("Do Not Disturb", isOn: $prefs.dndEnabled,
                description: "Silence alerts during set hours. They wait in your inbox")

            if prefs.dndEnabled {
                DatePicker("Start", selection: dndStartBinding, displayedComponents: .hourAndMinute)
                    .font(MADTheme.Typography.body)
                    .datePickerStyle(.compact)
                    .tint(MADTheme.Colors.madRed)

                DatePicker("End", selection: dndEndBinding, displayedComponents: .hourAndMinute)
                    .font(MADTheme.Typography.body)
                    .datePickerStyle(.compact)
                    .tint(MADTheme.Colors.madRed)
                    .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Rows

    private func settingsToggle(_ label: String, isOn: Binding<Bool>, description: String? = nil) -> some View {
        SettingsToggleRow(title: label, subtitle: description, isOn: isOn)
    }

    private var settingsDivider: some View {
        SettingsDivider(inset: 0)
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
        MADHaptics.action()
        prefs.saveAlerts()
        // Daily reminder is now backend-driven (server cron + APNs push). Clear
        // any legacy local-notification still pending from older app versions —
        // the backend respects `daily_reminder_enabled` and `daily_reminder_hour`
        // which are synced below as part of the prefs payload.
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [MADNotificationService.Identifier.dailyReminder])

        // Sync the ALERT keys to the backend so push filtering works. The
        // privacy keys are Privacy's to send (`sharingPayload`).
        let saved = prefs
        Task {
            do {
                _ = try await friendService.updateNotificationSettings(saved.alertPayload)
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

    /// Pull the settings the SERVER enforces (buddy invites gate a SQL query,
    /// so the server's value wins over whatever this install last wrote), and
    /// keep the stored privacy half honest while we have the response.
    private func loadServerSettings() async {
        guard let settings = try? await friendService.getNotificationSettings()
        else { return }
        // Free hydration point for the Stealth window log (server wins).
        StealthModeStore.shared.apply(settings)
        // …and for hide-start-&-end's local mirror (share cards, own maps).
        RoutePrivacySync.adopt(settings)
        await MainActor.run {
            if prefs.adoptServerValues(settings) {
                // Keep the stored copy honest too, so a later Save can't push
                // a stale value back over the server's.
                var stored = NotificationPreferences.load()
                stored.adoptServerValues(settings)
                stored.save()
            }
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
