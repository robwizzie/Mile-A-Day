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
    /// Same key the tracking screen's speaker button and the Ghost Race sheet
    /// write, so all three are one switch.
    @AppStorage(GhostCoach.enabledKey) private var coachEnabled = true
    // Absent = follow the device, so the picker shows the device's unit until
    // the user picks one; picking writes the key (see DistanceUnits).
    @AppStorage(DistanceUnits.key) private var distanceUnitRaw = DisplayDistanceUnit.systemDefault.rawValue

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
    @State private var isBackfillingRoutes = false
    @State private var routeBackfillProgress: String?
    /// Troubleshooting opens IN PLACE rather than as a pushed page: its two
    /// actions report through this page's alert, and an alert on a view under
    /// a pushed page can't present.
    @State private var troubleshootingExpanded = false

    /// The modals this page presents, so a single `.sheet(item:)` drives all of
    /// them. Two `.sheet`s on the same node compete and one silently never
    /// presents — the settings row then reads as a dead button.
    enum SettingsSheet: String, Identifiable {
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
                notificationsAndPrivacySection
                healthAndDataSection
                // No FRIENDS section: its one row pushed the Friends tab's own
                // screen (FriendsListView) a second time, so it configured
                // nothing the tab doesn't already own.
                helpSection
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
            // Dynamic Type: a list of text, so it grows as far as a list
            // holds. Inside the ScrollView, i.e. below every sheet this page
            // presents, so none of them inherits the cap.
            .madTypeCap(.madListCap)
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $healthAccessLinkActive) {
            HealthAccessSettingsView()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
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
                    subtitle: "\(userManager.currentUser.goalMiles.distanceFormatted1) per day",
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

            // Flamey lives on the Fun dashboard only, so his Closet does too.
            if selectedStyle == .fun {
                divider

                Button {
                    MADHaptics.tap()
                    FlameyClosetLink.shared.open()
                } label: {
                    MADSettingsRow(
                        icon: "hanger",
                        title: "\(FlameyNameRules.possessive(FlameyFacts.displayName)) Closet",
                        subtitle: "Dress \(FlameyFacts.displayName) in what you've earned",
                        iconColor: .orange
                    )
                }
                .buttonStyle(.plain)
            }

            divider

            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                MADSettingsRow(
                    icon: "ruler",
                    title: "Units",
                    subtitle: DistanceUnits.isChosen
                        ? "Shown in \(DistanceUnits.current.plural)"
                        : "Following your device (\(DisplayDistanceUnit.systemDefault.plural))",
                    iconColor: .teal
                )
                Picker("Units", selection: $distanceUnitRaw) {
                    ForEach(DisplayDistanceUnit.allCases) { unit in
                        Text(unit.title).tag(unit.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: distanceUnitRaw) { _, newValue in
                    // Storage stays miles everywhere; this only moves the
                    // formatter. Widgets keep miles until their next data write.
                    DistanceUnits.current = DisplayDistanceUnit(rawValue: newValue) ?? .systemDefault
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

            divider

            // The coach speaks on every workout, so its switch belongs on the
            // page everyone opens — not only inside the Ghost Race sheet,
            // which is where it used to live and which you never see on an
            // ordinary walk.
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                // Deliberately NOT a MADSettingsRow: that row ends in a
                // disclosure chevron, and a chevron beside a switch promises a
                // page that isn't there. Same metrics, different ending.
                HStack(spacing: MADTheme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(MADTheme.Colors.walkBlue.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: coachEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .madFont(size: 15, weight: .medium, maxScale: 1.3)
                            .foregroundColor(MADTheme.Colors.walkBlue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voice Coach")
                            .madFont(size: 17, weight: .medium, design: .rounded)
                            .foregroundColor(.primary)
                        Text(coachEnabled ? "Calls out splits and your goal" : "Off — lines still show on screen")
                        .madFont(size: 12, weight: .regular, design: .rounded)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    }

                    Spacer()

                    Toggle("", isOn: $coachEnabled)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: MADTheme.Colors.madRed))
                }
                .padding(.vertical, MADTheme.Spacing.xs)
                .onChange(of: coachEnabled) { _, on in
                    MADHaptics.tap()
                    if !on { GhostCoach.shared.silenceCurrentLine() }
                }

                // An OFFER, not a defect notice. The coach picks a modern
                // preinstalled voice now, so it sounds fine out of the box;
                // enhanced voices are a ~100MB download only the user can
                // start, and the copy must not imply the feature is waiting
                // on it.
                if coachEnabled, GhostCoach.usingBasicVoice {
                    Text("Richer voices: iOS Settings → Accessibility → Spoken Content → Voices.")
                        .madFont(size: 11, design: .rounded)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, MADTheme.Spacing.xs)
        }
    }

    // MARK: - Notifications & privacy

    /// Two rows where there were four. Stealth Mode, Privacy Settings and the
    /// "who sees your workouts" half of the notification page all answer one
    /// question, so they sit behind ONE Privacy page; each of its rows opens
    /// the screen that already owns (and saves) that setting.
    private var notificationsAndPrivacySection: some View {
        section("NOTIFICATIONS & PRIVACY", icon: "bell.badge.fill", iconColor: MADTheme.Colors.madRed) {
            // The page still holds the feed/sharing toggles too (they save
            // together); Privacy links to the same page for those.
            NavigationLink(destination: NotificationSettingsView()) {
                MADSettingsRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    subtitle: "Alerts, quiet hours and feed sharing",
                    iconColor: MADTheme.Colors.madRed
                )
            }

            divider

            NavigationLink(destination: PrivacyHubView(friendService: friendService)) {
                MADSettingsRow(
                    icon: "lock.shield.fill",
                    title: "Privacy",
                    subtitle: StealthModeStore.shared.isOn
                        ? "Stealth Mode on · who sees your walks"
                        : "Who sees your walks, routes and profile",
                    iconColor: .purple
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

            // Repair tools, not settings: most people never need them, so
            // they fold away instead of sitting between real choices.
            Button {
                MADHaptics.tap()
                withAnimation(.easeInOut(duration: 0.2)) {
                    troubleshootingExpanded.toggle()
                }
            } label: {
                HStack(spacing: MADTheme.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "wrench.adjustable.fill")
                            .madFont(size: 15, weight: .medium, maxScale: 1.3)
                            .foregroundColor(.gray)
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Troubleshooting")
                            .madFont(size: 17, weight: .medium, design: .rounded)
                            .foregroundColor(.primary)
                        Text("Fix a low streak or missing maps")
                            .madFont(size: 12, weight: .regular, design: .rounded)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .madFont(size: 13, weight: .semibold, maxScale: 1.3)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(troubleshootingExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, MADTheme.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(troubleshootingExpanded ? "Hides the repair tools" : "Shows the repair tools")

            if troubleshootingExpanded {
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

                divider

                // The automatic sweep heals ~75 workouts a session, two years
                // back, only after a quiet sync — so an old post's map (and its
                // Flyover) could take weeks of launches to appear. This runs the
                // same pipeline to the end, now, and says what it found.
                Button { Task { await backfillRoutes() } } label: {
                    MADSettingsRow(
                        icon: "map.fill",
                        title: "Add Maps to Past Workouts",
                        subtitle: routeBackfillProgress
                            ?? "Send routes from Apple Health so older posts get a map and Flyover",
                        iconColor: .teal
                    )
                }
                .buttonStyle(.plain)
                .disabled(isBackfillingRoutes)
            }
        }
    }

    /// "Español · change in iOS Settings" — the language the app is
    /// currently running in, named in that language.
    private var languageSubtitle: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let name = Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? "English"
        return "\(name) · \(String(localized: "change in iOS Settings"))"
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

    // MARK: - Help

    private var helpSection: some View {
        section("HELP", icon: "questionmark.circle.fill", iconColor: .orange) {
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

            NavigationLink(destination: HelpAndSupportView()) {
                MADSettingsRow(
                    icon: "questionmark.circle.fill",
                    title: "Help & Support",
                    subtitle: "FAQ and contact",
                    iconColor: .orange
                )
            }

            divider

            // What's New and Language are reference, not settings — they
            // sit at the bottom of Help rather than in a group of their own.
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

            // The app follows the device language; iOS lets a user pick a
            // different one PER APP once the app ships more than one
            // localization, and that switch lives on the app's own page in
            // Settings — the one place we can send them.
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                MADSettingsRow(
                    icon: "globe",
                    title: "Language",
                    subtitle: languageSubtitle,
                    iconColor: .blue
                )
            }
            .buttonStyle(.plain)
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
                    .madFont(size: 12, weight: .semibold)
                    .foregroundColor(iconColor)
                Text(LocalizedStringKey(title))
                    .madFont(size: 11, weight: .heavy, design: .rounded)
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

    private var versionFooter: some View {
        Text(versionString)
            .madFont(size: 11, weight: .medium, design: .rounded)
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
            await RecalibrateMedals.refresh(userManager: userManager, newBadgeIds: outcome.newBadgeIds)

            let dayWord = outcome.streak == 1 ? "day" : "days"
            let workoutWord = outcome.workoutsPushed == 1 ? "workout" : "workouts"
            var message =
                "Your streak is now \(outcome.streak) \(dayWord). We re-checked \(outcome.workoutsPushed) recent \(workoutWord) and made sure they're all saved to your account."
            if let medals = RecalibrateMedals.sentence(for: outcome.newBadgeIds) {
                message += " " + medals
            }
            recalibrateResultMessage = message
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

    /// Every past workout with a route in HealthKit but no map on the server,
    /// pushed to the end — see `WorkoutSyncService.backfillAllRoutes`. The
    /// result lands in the same alert Recalibrate uses; both are "we went
    /// through your history and here is what changed".
    private func backfillRoutes() async {
        guard !isBackfillingRoutes else { return }
        isBackfillingRoutes = true
        routeBackfillProgress = "Checking your workouts…"
        defer {
            isBackfillingRoutes = false
            routeBackfillProgress = nil
        }

        let summary = await WorkoutSyncService.shared.backfillAllRoutes { progress in
            if progress.pushed > 0 {
                routeBackfillProgress = "Sent \(progress.pushed) so far…"
            } else if progress.total > 0 {
                routeBackfillProgress = "Checked \(progress.probed) of \(progress.total)…"
            }
        }

        if summary.busy {
            recalibrateResultMessage =
                "A sync is already running. Give it a moment and try again."
            return
        }
        let pushedWord = summary.pushed == 1 ? "workout" : "workouts"
        var lines: [String] = []
        if summary.pushed > 0 {
            lines.append("Added maps to \(summary.pushed) past \(pushedWord). Their posts will show the route and Flyover from now on.")
        } else {
            lines.append("Every workout that has a route in Apple Health already has its map.")
        }
        if summary.noRoute > 0 {
            let word = summary.noRoute == 1 ? "workout has" : "workouts have"
            lines.append("\(summary.noRoute) \(word) no GPS route in Apple Health — treadmill, no Watch, or route sharing was off when it was recorded — so there's nothing to send for those.")
        }
        if summary.failed {
            lines.append("We couldn't finish — check your connection and run this again; it picks up where it stopped.")
        }
        recalibrateResultMessage = lines.joined(separator: " ")
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
