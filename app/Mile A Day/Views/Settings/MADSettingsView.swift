import SwiftUI

/// THE settings screen. One gear, everything behind it.
///
/// There used to be two: a "Dashboard Settings" page behind the Dashboard's
/// gear (goal, dashboard style, tour) and a "Settings" page behind the
/// Profile's gear (everything else). Neither mentioned the other, so half the
/// app's settings were only reachable from a tab you might not have opened,
/// and "where do I change my goal?" had a different answer from "where do I
/// change my notifications?". Both gears now push this, so wherever a user
/// starts looking, they find all of it.
///
/// This page owns its own confirmations and its own account actions rather
/// than taking them as bindings from a host. That's the sheet/alert rule: a
/// modal attached to the view that PUSHED this one can't present while this
/// one is on top, which is how Sign Out came to look like a no-op until you
/// hit Back. Whoever owns the button renders the feedback.
struct MADSettingsView: View {
    @ObservedObject var userManager: UserManager
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var friendService: FriendService
    @ObservedObject private var injuryPause = InjuryPauseState.shared
    @Environment(\.appStateManager) var appStateManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage(DashboardStylePreference.key) private var dashboardStyleRaw = DashboardStyle.modern.rawValue
    @AppStorage(RouteSharingDefault.key) private var routeDefaultRaw = RouteSharingDefault.ask.rawValue

    @State private var activeSheet: SettingsSheet?
    @State private var showWhatsNew = false
    @State private var showGoalSheet = false
    /// Pushed from two places — the banner at the top and the row in the
    /// Health section — so it's one destination flag rather than two links.
    @State private var healthAccessLinkActive = false

    @State private var showingLogoutConfirmation = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?
    @State private var isRecalibratingStreak = false
    @State private var recalibrateResultMessage: String?

    /// The modals this page presents, so a single `.sheet(item:)` drives all of
    /// them. Two `.sheet`s on the same node compete and one silently never
    /// presents — the settings row then reads as a dead button.
    enum SettingsSheet: String, Identifiable {
        case privacy
        case importHistory
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.lg) {
                // The one thing on this page that can be BROKEN rather than
                // merely unset, so it leads.
                HealthAccessBanner {
                    healthAccessLinkActive = true
                }
                yourDaySection
                feedAndProfileSection
                healthAndDataSection
                socialSection
                learnSection
                accountSection
                #if DEBUG
                if showsDevelopmentSection {
                    developmentSection
                }
                #endif
                versionFooter
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.md)
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $healthAccessLinkActive) {
            HealthAccessSettingsView()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .privacy:
                PrivacySettingsView()
            case .importHistory:
                ImportHistoryView(userManager: userManager)
            }
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView()
        }
        .sheet(isPresented: $showGoalSheet) {
            GoalSettingSheet(
                currentGoal: userManager.currentUser.goalMiles,
                onSave: { newGoal in
                    userManager.setDailyGoal(miles: newGoal)
                    // The widgets show progress against the goal, so a goal
                    // changed here has to reach the App Group or the home
                    // screen keeps scoring today against the old number.
                    WidgetDataStore.save(
                        todayMiles: healthManager.todaysDistance,
                        goal: newGoal
                    )
                }
            )
            .presentationDetents([.height(300)])
        }
        .alert("Sign Out", isPresented: $showingLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                userManager.signOut()
                appStateManager.signOut()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Delete Account?", isPresented: $showingDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { Task { await performDeleteAccount() } }
        } message: {
            Text("This permanently deletes your account, workouts, streak history, friendships, and competition data. This cannot be undone.")
        }
        .alert(
            "Couldn't Delete Account",
            isPresented: Binding(
                get: { deleteAccountErrorMessage != nil },
                set: { if !$0 { deleteAccountErrorMessage = nil } }
            )
        ) {
            Button("OK") { deleteAccountErrorMessage = nil }
        } message: {
            Text(deleteAccountErrorMessage ?? "")
        }
        .alert(
            "Streak Recalibrated",
            isPresented: Binding(
                get: { recalibrateResultMessage != nil },
                set: { if !$0 { recalibrateResultMessage = nil } }
            )
        ) {
            Button("OK") { recalibrateResultMessage = nil }
        } message: {
            Text(recalibrateResultMessage ?? "")
        }
    }

    // MARK: - Your day

    private var yourDaySection: some View {
        section("YOUR DAY", icon: "sun.max.fill", iconColor: .yellow) {
            Button { showGoalSheet = true } label: {
                MADSettingsRow(
                    icon: "target",
                    title: "Daily Goal",
                    subtitle: "\(String(format: "%.1f", userManager.currentUser.goalMiles)) miles per day",
                    iconColor: .green
                )
            }
            .buttonStyle(.plain)

            divider

            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                MADSettingsRow(
                    icon: "paintbrush.pointed.fill",
                    title: "Dashboard Style",
                    subtitle: selectedStyle.subtitle,
                    iconColor: .orange
                )
                Picker("Dashboard Style", selection: $dashboardStyleRaw) {
                    ForEach(DashboardStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: dashboardStyleRaw) { _, newValue in
                    DashboardStylePreference.current = DashboardStyle(rawValue: newValue) ?? .modern
                    DashboardStylePreference.markChosen()
                    MADHaptics.tap()
                }
            }
            .padding(.bottom, MADTheme.Spacing.xs)

            divider

            NavigationLink(destination: DailyChallengeSettingsView(friendService: friendService)) {
                MADSettingsRow(
                    icon: "flag.2.crossed.fill",
                    title: "Daily Challenges",
                    subtitle: "Head-to-Head matchup preferences",
                    iconColor: .purple
                )
            }

            divider

            NavigationLink(destination: RecoveryModeView()) {
                MADSettingsRow(
                    icon: "cross.case.fill",
                    title: "Recovery Mode",
                    subtitle: injuryPause.isPaused
                        ? "Streak paused for injury"
                        : "Pause your streak while injured",
                    iconColor: MADTheme.Colors.warning
                )
            }
        }
    }

    // MARK: - Feed & profile

    private var feedAndProfileSection: some View {
        section("FEED & PROFILE", icon: "square.grid.2x2.fill", iconColor: MADTheme.Colors.madRed) {
            // The route is the one part of a post you can only decide BEFORE
            // sharing, and the person it matters most to — whose walks all
            // start at their front door — was re-making the same decision
            // every single day and only had to forget once.
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                MADSettingsRow(
                    icon: "map.fill",
                    title: "Route Maps on New Posts",
                    subtitle: currentRouteDefault.subtitle,
                    iconColor: .teal
                )
                Picker("Route maps", selection: $routeDefaultRaw) {
                    ForEach(RouteSharingDefault.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: routeDefaultRaw) { _, _ in MADHaptics.tap() }
                Text("You can still turn the map on or off for any individual post, before or after you share it.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, MADTheme.Spacing.xs)

            divider

            Button { activeSheet = .privacy } label: {
                MADSettingsRow(
                    icon: "lock.shield.fill",
                    title: "Privacy Settings",
                    subtitle: "Control what others can see",
                    iconColor: MADTheme.Colors.madRed
                )
            }
            .buttonStyle(.plain)

            divider

            // Named for what it actually holds. It's called "Notifications"
            // in the code and always has been, but the page is also where
            // "who can see my workouts", route sharing and tagged-post
            // curation live — so a user hunting for those was looking for a
            // page that, by its title, had nothing to do with them.
            NavigationLink(destination: NotificationSettingsView()) {
                MADSettingsRow(
                    icon: "bell.fill",
                    title: "Notifications & Sharing",
                    subtitle: "Alerts, who sees your workouts, tagged posts",
                    iconColor: MADTheme.Colors.madRed
                )
            }
        }
    }

    // MARK: - Health & data

    private var healthAndDataSection: some View {
        section("HEALTH & DATA", icon: "heart.fill", iconColor: .red) {
            Button { healthAccessLinkActive = true } label: {
                MADSettingsRow(
                    icon: "heart.fill",
                    title: "Health Access",
                    subtitle: healthAccessSubtitle,
                    iconColor: .red
                )
            }
            .buttonStyle(.plain)

            divider

            NavigationLink(destination: FitnessConnectionsView(userManager: userManager)) {
                MADSettingsRow(
                    icon: "link.circle.fill",
                    title: "Connected Apps",
                    subtitle: "Strava, Garmin, WHOOP, Oura and more",
                    iconColor: .teal
                )
            }

            divider

            // A sheet, not a NavigationLink: ImportHistoryView owns its own
            // NavigationStack and Cancel/Done button, which a pushed
            // destination would nest inside this one.
            Button { activeSheet = .importHistory } label: {
                MADSettingsRow(
                    icon: "clock.arrow.circlepath",
                    title: "Import Past Workouts",
                    subtitle: "Bring in history from a Strava or Garmin export",
                    iconColor: .indigo
                )
            }
            .buttonStyle(.plain)

            divider

            Button { Task { await recalibrateStreak() } } label: {
                MADSettingsRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Recalibrate Streak",
                    subtitle: isRecalibratingStreak
                        ? "Re-syncing your workouts…"
                        : "Fix a streak that looks too low",
                    iconColor: .green
                )
            }
            .buttonStyle(.plain)
            .disabled(isRecalibratingStreak)
        }
    }

    /// The row says what's wrong before you tap it, so a broken permission is
    /// visible from the settings list itself and not one screen deeper.
    private var healthAccessSubtitle: String {
        switch HealthAccessMonitor.shared.state {
        case .someWritesDenied: return "Some access is turned off — tap to fix"
        case .needsRequest: return "Some access hasn't been granted yet"
        case .unavailable: return "Not available on this device"
        case .granted: return "What Mile A Day reads from Apple Health"
        }
    }

    // MARK: - Social

    private var socialSection: some View {
        section("FRIENDS", icon: "person.2.fill", iconColor: .blue) {
            NavigationLink(destination: FriendsListView(friendService: friendService)) {
                MADSettingsRow(
                    icon: "person.2.fill",
                    title: "Friends & Leaderboard",
                    subtitle: "Requests, blocked accounts, close friends",
                    iconColor: .blue
                )
            }
        }
    }

    // MARK: - Learn

    private var learnSection: some View {
        section("GETTING AROUND", icon: "questionmark.circle.fill", iconColor: .orange) {
            Button {
                // Pop back to the tab first, then start the tour overlay on
                // MainTabView after a beat so the navigation stack settles.
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("MAD_StartGuidedTour"),
                        object: nil
                    )
                }
            } label: {
                MADSettingsRow(
                    icon: "map.fill",
                    title: "App Tour",
                    subtitle: "Take a guided walkthrough of the app",
                    iconColor: MADTheme.Colors.madRed
                )
            }
            .buttonStyle(.plain)

            divider

            Button { showWhatsNew = true } label: {
                MADSettingsRow(
                    icon: "sparkles",
                    title: "What's New",
                    subtitle: "See what changed in the latest update",
                    iconColor: .orange
                )
            }
            .buttonStyle(.plain)

            divider

            NavigationLink(destination: HelpAndSupportView()) {
                MADSettingsRow(
                    icon: "questionmark.circle.fill",
                    title: "Help & Support",
                    subtitle: "FAQ and contact",
                    iconColor: .orange
                )
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        section("ACCOUNT", icon: "person.crop.circle", iconColor: .gray) {
            Button { showingLogoutConfirmation = true } label: {
                MADSettingsRow(
                    icon: "arrow.right.square.fill",
                    title: "Sign Out",
                    subtitle: "Sign out and return to login",
                    iconColor: MADTheme.Colors.madRed
                )
            }
            .buttonStyle(.plain)

            divider

            Button { showingDeleteAccountConfirmation = true } label: {
                MADSettingsRow(
                    icon: "trash.fill",
                    title: "Delete Account",
                    subtitle: isDeletingAccount
                        ? "Deleting your account…"
                        : "Permanently remove your account and data",
                    iconColor: .red
                )
            }
            .buttonStyle(.plain)
            .disabled(isDeletingAccount)
        }
    }

    // MARK: - Chrome

    /// A labelled card. The old pages were one long undivided list, which is
    /// fine at eight rows and unreadable at twenty — and twenty is what one
    /// page's worth of settings actually is once both gears lead here.
    private func section<Content: View>(
        _ title: String,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, MADTheme.Spacing.xs)

            VStack(spacing: 0) { content() }
                .padding(MADTheme.Spacing.md)
                .madLiquidGlass()
        }
    }

    private var divider: some View {
        Divider()
            .overlay(Color.white.opacity(0.06))
            .padding(.vertical, MADTheme.Spacing.xs)
    }

    private var selectedStyle: DashboardStyle {
        DashboardStyle(rawValue: dashboardStyleRaw) ?? .modern
    }

    private var currentRouteDefault: RouteSharingDefault {
        RouteSharingDefault(rawValue: routeDefaultRaw) ?? .ask
    }

    private var versionFooter: some View {
        Text(versionString)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(.secondary.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.top, MADTheme.Spacing.sm)
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Mile A Day \(version) (\(build))"
    }

    // MARK: - Account actions

    private func performDeleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await userManager.deleteAccount()
            appStateManager.signOut()
        } catch {
            deleteAccountErrorMessage = error.localizedDescription
        }
    }

    /// Re-push the phone's local workouts to the server and recompute the
    /// streak. Recovers a streak that reads too low because a manual/backdated
    /// workout never reached the backend. Local HealthKit is the source of
    /// truth, so this only ever fills server gaps — it can't shorten a
    /// legitimately broken streak.
    private func recalibrateStreak() async {
        guard !isRecalibratingStreak else { return }
        isRecalibratingStreak = true
        defer { isRecalibratingStreak = false }

        do {
            let outcome = try await WorkoutSyncService.shared.recalibrateStreak(
                localStreakDays: healthManager.retroactiveStreak
            )
            userManager.updateStreakFromBackend(outcome.streak)

            let dayWord = outcome.streak == 1 ? "day" : "days"
            let workoutWord = outcome.workoutsPushed == 1 ? "workout" : "workouts"
            recalibrateResultMessage =
                "Your streak is now \(outcome.streak) \(dayWord). We re-checked \(outcome.workoutsPushed) recent \(workoutWord) and made sure they're all saved to your account."
        } catch {
            recalibrateResultMessage =
                "We couldn't finish recalibrating right now. Please check your connection and try again."
        }

        // Steps live in a separate daily_steps table that only ever finalizes
        // today (and yesterday once at rollover), so a day left partial by a
        // late Watch sync is never revisited. Re-post the recent window; the
        // backend keeps the GREATEST, so this back-corrects a stale day and
        // never lowers a good one. Best-effort and independent of the result.
        await DailyStepsSyncService.shared.backfillRecentDays(30)
    }

    // MARK: - Development

    // DEBUG builds only — compiled out of Release so no dev tooling ships.
    #if DEBUG
    private var showsDevelopmentSection: Bool {
        // TEMPORARY (local testing): admin-role check dropped so dev tools show
        // on any DEBUG build without promoting the account server-side.
        // Restore before committing:
        //   AppEnvironment.isDevelopment && userManager.currentUser.role == "admin"
        AppEnvironment.isDevelopment
    }

    private var developmentSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("Development")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
                Spacer()
            }

            VStack(spacing: 0) {
                NavigationLink(destination: DeveloperSettingsView()) {
                    MADSettingsRow(
                        icon: "hammer.fill",
                        title: "Developer Settings",
                        subtitle: "Debug tools and sync management",
                        iconColor: MADTheme.Colors.madRed
                    )
                }

                divider

                Button {
                    appStateManager.resetAppState()
                } label: {
                    MADSettingsRow(
                        icon: "arrow.counterclockwise.circle.fill",
                        title: "Reset Onboarding",
                        subtitle: "Return to initial setup flow",
                        iconColor: .orange
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(MADTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                .fill(MADTheme.Colors.madRed.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.large)
                        .stroke(MADTheme.Colors.madRed.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
    #endif
}
