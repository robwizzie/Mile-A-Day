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
///
/// Built from `SettingsChrome`: sentence-case headers, rows with a small
/// tinted glyph, one flat surface per group. Each setting has one row in the
/// whole Settings tree (see docs/conventions/ios.md § Settings).
struct MADSettingsView: View {
    @ObservedObject var userManager: UserManager
    @ObservedObject var healthManager: HealthKitManager
    @ObservedObject var friendService: FriendService
    @ObservedObject private var injuryPause = InjuryPauseState.shared
    @ObservedObject private var plusStore = PlusStore.shared
    /// The Health row says what's wrong before you tap it, so it watches the
    /// monitor itself (the Dashboard carries the banner; this page doesn't
    /// repeat it above the row).
    @ObservedObject private var healthAccess = HealthAccessMonitor.shared
    @Environment(\.appStateManager) var appStateManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage(DashboardStylePreference.key) private var dashboardStyleRaw = DashboardStylePreference.defaultStyle.rawValue
    /// Same key the tracking screen's speaker button and the Ghost Race sheet
    /// write, so all three are one switch.
    @AppStorage(GhostCoach.enabledKey) private var coachEnabled = true
    // Absent = follow the device, so the picker shows the device's unit until
    // the user picks one; picking writes the key (see DistanceUnits).
    @AppStorage(DistanceUnits.key) private var distanceUnitRaw = DisplayDistanceUnit.systemDefault.rawValue

    @State private var activeSheet: SettingsSheet?
    @State private var showWhatsNew = false
    @State private var showGoalSheet = false

    @State private var showingLogoutConfirmation = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?
    @State private var showingDeleteWithoutAppleConfirmation = false
    /// Recalibrate's live state. The service owns it, so leaving this page
    /// and coming back mid-run still shows it running.
    @ObservedObject private var syncService = WorkoutSyncService.shared
    /// What a repair tool found, shown in one alert for both tools.
    @State private var repairResult: RepairResult?
    @State private var isBackfillingRoutes = false
    @State private var routeBackfillProgress: String?
    /// Troubleshooting opens IN PLACE rather than as a pushed page: its two
    /// actions report through this page's alert, and an alert on a view under
    /// a pushed page can't present.
    @State private var troubleshootingExpanded = false

    struct RepairResult {
        let title: String
        let message: String
    }

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
                plusSection
                goalSection
                workoutsSection
                challengesSection
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
        .task { healthAccess.refresh() }
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
            Text("This permanently deletes your account, workouts, streak history, friendships, and competition data. This cannot be undone. Apple may ask you to confirm with Sign in with Apple.")
        }
        .alert("Delete Without Apple Confirmation?", isPresented: $showingDeleteWithoutAppleConfirmation) {
            Button("Keep Account", role: .cancel) { }
            Button("Delete Anyway", role: .destructive) {
                Task { await performDeleteAccount(skippingAppleConfirmation: true) }
            }
        } message: {
            Text("Your Mile A Day account will still be permanently deleted. Mile A Day may stay listed under Sign in with Apple in your Apple Account settings, where you can remove it yourself.")
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
            repairResult?.title ?? "",
            isPresented: Binding(
                get: { repairResult != nil },
                set: { if !$0 { repairResult = nil } }
            )
        ) {
            Button("OK") { repairResult = nil }
        } message: {
            Text(repairResult?.message ?? "")
        }
    }

    // MARK: - Mile A Day+

    /// No header: one highlighted row says it. Flamey's Closet rides here
    /// because his looks are what Plus mostly adds to.
    private var plusSection: some View {
        SettingsSection {
            NavigationLink(destination: PlusSettingsView()) {
                SettingsRow(
                    icon: plusStore.isPlus ? "checkmark.seal.fill" : "sparkles",
                    title: "Mile A Day+",
                    subtitle: plusSubtitle,
                    tint: .orange,
                    titleColor: .orange
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()
            NavigationLink(destination: ReferralsView()) {
                SettingsRow(
                    icon: "gift.fill",
                    title: "Invite friends",
                    subtitle: "Referral rewards, up to free Plus",
                    tint: MADTheme.Colors.madRed
                )
            }
            .buttonStyle(.plain)

            // Flamey lives on the Fun dashboard only, so his Closet does too.
            if selectedStyle == .fun {
                SettingsDivider()
                Button {
                    MADHaptics.tap()
                    FlameyClosetLink.shared.open()
                } label: {
                    SettingsRow(
                        icon: "hanger",
                        title: "\(FlameyNameRules.possessive(FlameyFacts.displayName)) Closet",
                        tint: .orange
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var plusSubtitle: String {
        guard let status = plusStore.status, status.is_plus else {
            return HistoryWindow.isCapped ? "Your full workout history, faster streak tokens" : "Faster streak tokens, Flamey looks, gifting"
        }
        if status.isFoundingRunner && status.source == "founding" { return "Founding Runner — free for life" }
        return "Active — manage, gift or restore"
    }

    // MARK: - Goal & units

    private var goalSection: some View {
        SettingsSection("Goal & units") {
            Button { showGoalSheet = true } label: {
                SettingsRow(
                    icon: "target",
                    title: "Daily goal",
                    subtitle: "\(userManager.currentUser.goalMiles.distanceFormatted1) per day",
                    tint: .green
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                SettingsRow(
                    icon: "ruler",
                    title: "Units",
                    subtitle: DistanceUnits.isChosen ? nil : "Following your device",
                    tint: .teal,
                    accessory: .none
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
            .padding(.bottom, MADTheme.Spacing.sm)

            // One style for now, so nothing to pick (`DashboardStylePreference.offered`).
            if DashboardStylePreference.offersChoice {
                SettingsDivider()

                VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                    SettingsRow(
                        icon: "paintbrush.pointed.fill",
                        title: "Dashboard style",
                        subtitle: selectedStyle.subtitle,
                        tint: .orange,
                        accessory: .none
                    )
                    Picker("Dashboard style", selection: $dashboardStyleRaw) {
                        ForEach(DashboardStylePreference.offered) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: dashboardStyleRaw) { _, newValue in
                        DashboardStylePreference.current = DashboardStyle(rawValue: newValue) ?? DashboardStylePreference.defaultStyle
                        DashboardStylePreference.markChosen()
                        MADHaptics.tap()
                    }
                }
                .padding(.bottom, MADTheme.Spacing.sm)
            }
        }
    }

    // MARK: - Workouts

    private var workoutsSection: some View {
        SettingsSection("Workouts") {
            // The coach speaks on every workout, so its switch belongs on the
            // page everyone opens — not only inside the Ghost Race sheet.
            VStack(alignment: .leading, spacing: 0) {
                SettingsToggleRow(
                    icon: coachEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    title: "Voice coach",
                    subtitle: coachEnabled ? "Calls out splits and your goal" : "Off. Lines still show on screen",
                    tint: MADTheme.Colors.walkBlue,
                    isOn: $coachEnabled
                )
                .onChange(of: coachEnabled) { _, on in
                    MADHaptics.tap()
                    if !on { GhostCoach.shared.silenceCurrentLine() }
                }

                // An OFFER, not a defect notice: the coach already picks a
                // modern preinstalled voice; enhanced ones are a download
                // only the user can start. One short line.
                if coachEnabled, GhostCoach.usingBasicVoice {
                    Text("Richer voices: iOS Settings › Accessibility › Spoken Content")
                        .madFont(size: 11, design: .rounded)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.leading, 36)
                        .padding(.bottom, 6)
                }
            }

            SettingsDivider()

            NavigationLink(destination: ShoesListView()) {
                SettingsRow(
                    icon: ShoeSymbol.filled,
                    title: "Shoes",
                    subtitle: "Mileage on each pair. Only you see it",
                    tint: .orange
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            NavigationLink(destination: RecoveryModeView()) {
                SettingsRow(
                    icon: "cross.case.fill",
                    title: "Recovery Mode",
                    subtitle: injuryPause.isPaused
                        ? "On. Your streak is paused"
                        : "Pause your streak while injured",
                    tint: MADTheme.Colors.warning
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Challenges

    private var challengesSection: some View {
        SettingsSection("Challenges") {
            NavigationLink(destination: DailyChallengeSettingsView(friendService: friendService)) {
                SettingsRow(
                    icon: "flag.2.crossed.fill",
                    title: "Daily challenges",
                    subtitle: "Who you're matched with head to head",
                    tint: .purple
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Notifications & privacy

    /// Two rows, two jobs: Notifications is alerts only, Privacy holds every
    /// "who sees what" control. No setting appears on both.
    private var notificationsAndPrivacySection: some View {
        SettingsSection("Notifications & privacy") {
            NavigationLink(destination: NotificationSettingsView()) {
                SettingsRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    subtitle: "Alerts, reminders and quiet hours",
                    tint: MADTheme.Colors.madRed
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            NavigationLink(destination: PrivacyHubView(friendService: friendService)) {
                SettingsRow(
                    icon: "lock.shield.fill",
                    title: "Privacy",
                    subtitle: StealthModeStore.shared.isOn
                        ? "Stealth Mode on"
                        : "Who sees your walks, routes and profile",
                    tint: .purple
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Health & data

    private var healthAndDataSection: some View {
        SettingsSection("Health & data") {
            NavigationLink(destination: HealthAccessSettingsView()) {
                SettingsRow(
                    icon: healthAccess.state.needsAttention ? "heart.slash.fill" : "heart.fill",
                    title: "Health access",
                    subtitle: healthAccessSubtitle,
                    tint: healthAccessTint
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            NavigationLink(destination: FitnessConnectionsView(userManager: userManager)) {
                SettingsRow(
                    icon: "link",
                    title: "Connected apps",
                    subtitle: "Strava, Garmin, WHOOP, Oura and more",
                    tint: .teal
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            // A sheet, not a NavigationLink: ImportHistoryView owns its own
            // NavigationStack and Cancel/Done button, which a pushed
            // destination would nest inside this one.
            Button { activeSheet = .importHistory } label: {
                SettingsRow(
                    icon: "clock.arrow.circlepath",
                    title: "Import past workouts",
                    subtitle: "From a Strava or Garmin export",
                    tint: .indigo
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            // Repair tools, not settings: most people never need them, so
            // they fold away instead of sitting between real choices.
            Button {
                MADHaptics.tap()
                withAnimation(.easeInOut(duration: 0.2)) {
                    troubleshootingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    SettingsGlyph(icon: "wrench.adjustable.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Troubleshooting")
                            .madFont(size: 16, weight: .medium, design: .rounded)
                            .foregroundColor(.primary)
                        Text("Streak too low or maps missing")
                            .madFont(size: 12, design: .rounded)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .madFont(size: 12, weight: .semibold, maxScale: 1.5)
                        .foregroundColor(.secondary.opacity(0.7))
                        .rotationEffect(.degrees(troubleshootingExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(troubleshootingExpanded ? "Hides the repair tools" : "Shows the repair tools")

            if troubleshootingExpanded {
                SettingsDivider()

                Button { Task { await recalibrateStreak() } } label: {
                    SettingsRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Fix my streak",
                        subtitle: recalibrateSubtitle,
                        tint: .green,
                        accessory: .none
                    )
                }
                .buttonStyle(.plain)
                .disabled(syncService.isRecalibrating)

                SettingsDivider()

                // The automatic sweep heals ~75 workouts a session, two years
                // back, only after a quiet sync — so an old post's map (and its
                // Flyover) could take weeks of launches to appear. This runs the
                // same pipeline to the end, now, and says what it found.
                Button { Task { await backfillRoutes() } } label: {
                    SettingsRow(
                        icon: "map.fill",
                        title: "Add maps to old walks",
                        subtitle: routeBackfillProgress ?? "For older posts missing their map",
                        tint: .teal,
                        accessory: .none
                    )
                }
                .buttonStyle(.plain)
                .disabled(isBackfillingRoutes)
            }
        }
    }

    /// The streak repair row's subtitle, counting along while it runs (the
    /// banner at the bottom says the same thing everywhere else).
    private var recalibrateSubtitle: String {
        guard let progress = syncService.recalibration, progress.isRunning else {
            return "For a streak that looks too low"
        }
        switch progress.stage {
        case .uploading where progress.total > 0:
            return "Checked \(progress.checked) of \(progress.total) walks…"
        case .recomputing:
            return "Recounting your streak…"
        default:
            return "Syncing your walks…"
        }
    }

    /// The row says what's wrong before you tap it, so a broken permission is
    /// visible from the settings list itself and not one screen deeper.
    private var healthAccessSubtitle: String {
        switch healthAccess.state {
        case .someWritesDenied: return "Some access is off. Tap to fix"
        case .needsRequest: return "Some access hasn't been granted yet"
        case .unavailable: return "Not available on this device"
        case .granted: return "What Mile A Day reads from Apple Health"
        }
    }

    private var healthAccessTint: Color {
        switch healthAccess.state {
        case .someWritesDenied: return MADTheme.Colors.madRed
        case .needsRequest: return .orange
        case .unavailable: return .secondary
        case .granted: return .red
        }
    }

    /// "Español · change in iOS Settings" — the language the app is
    /// currently running in, named in that language.
    private var languageSubtitle: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let name = Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? "English"
        return "\(name) · \(String(localized: "change in iOS Settings"))"
    }

    // MARK: - Help

    private var helpSection: some View {
        SettingsSection("Help") {
            // The tour's one door (Help & Support used to have a second).
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
                SettingsRow(
                    icon: "map",
                    title: "Take the tour",
                    subtitle: "Streaks, syncing, competitions and medals",
                    tint: MADTheme.Colors.madRed,
                    accessory: .none
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            NavigationLink(destination: HelpAndSupportView()) {
                SettingsRow(
                    icon: "questionmark.circle",
                    title: "Help & support",
                    subtitle: "FAQ, contact, privacy and terms",
                    tint: .orange
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            // What's New and Language are reference, not settings — they
            // sit at the bottom of Help rather than in a group of their own.
            Button { showWhatsNew = true } label: {
                SettingsRow(
                    icon: "sparkles",
                    title: "What's new",
                    tint: .orange
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            // The app follows the device language; iOS lets a user pick a
            // different one PER APP once the app ships more than one
            // localization, and that switch lives on the app's own page in
            // Settings — the one place we can send them.
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                SettingsRow(
                    icon: "globe",
                    title: "Language",
                    subtitle: languageSubtitle,
                    tint: .blue,
                    accessory: .external
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        SettingsSection("Account") {
            Button { showingLogoutConfirmation = true } label: {
                SettingsRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "Sign Out",
                    tint: .secondary,
                    accessory: .none
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button { showingDeleteAccountConfirmation = true } label: {
                SettingsRow(
                    icon: "trash",
                    title: "Delete Account",
                    subtitle: isDeletingAccount
                        ? "Deleting your account…"
                        : "Removes your account and data for good",
                    tint: .red,
                    titleColor: .red,
                    accessory: .none
                )
            }
            .buttonStyle(.plain)
            .disabled(isDeletingAccount)
        }
    }

    // MARK: - Chrome

    private var selectedStyle: DashboardStyle {
        DashboardStyle(rawValue: dashboardStyleRaw) ?? DashboardStylePreference.defaultStyle
    }

    /// The app version's one place in Settings.
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

    private func performDeleteAccount(skippingAppleConfirmation: Bool = false) async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await userManager.deleteAccount(skippingAppleConfirmation: skippingAppleConfirmation)
            appStateManager.signOut()
        } catch AppleSignInManager.AppleSignInError.cancelled {
            showingDeleteWithoutAppleConfirmation = true
        } catch {
            deleteAccountErrorMessage = error.localizedDescription
        }
    }

    /// "Fix my streak": re-push the phone's local workouts to the server and
    /// recompute the streak. Recovers a streak that reads too low because a
    /// manual/backdated workout never reached the backend. Local HealthKit is
    /// the source of truth, so this only ever fills server gaps — it can't
    /// shorten a legitimately broken streak.
    private func recalibrateStreak() async {
        guard !syncService.isRecalibrating else { return }

        do {
            let outcome = try await WorkoutSyncService.shared.recalibrateStreak(
                localStreakDays: healthManager.retroactiveStreak
            )
            userManager.updateStreakFromBackend(outcome.streak)
            await RecalibrateMedals.refresh(userManager: userManager, newBadgeIds: outcome.newBadgeIds)

            let dayWord = outcome.streak == 1 ? "day" : "days"
            var message = "Your streak is \(outcome.streak) \(dayWord), and your recent walks are all saved."
            if let medals = RecalibrateMedals.sentence(for: outcome.newBadgeIds) {
                message += " " + medals
            }
            repairResult = RepairResult(title: "Streak checked", message: message)
        } catch SyncError.alreadyRunning {
            return
        } catch {
            repairResult = RepairResult(
                title: "Couldn't fix your streak",
                message: "Check your connection and try again."
            )
        }
    }

    /// "Add maps to old walks": every past workout with a route in HealthKit
    /// but no map on the server, pushed to the end — see
    /// `WorkoutSyncService.backfillAllRoutes`.
    private func backfillRoutes() async {
        guard !isBackfillingRoutes else { return }
        isBackfillingRoutes = true
        routeBackfillProgress = "Checking your walks…"
        defer {
            isBackfillingRoutes = false
            routeBackfillProgress = nil
        }

        let summary = await WorkoutSyncService.shared.backfillAllRoutes { progress in
            if progress.pushed > 0 {
                routeBackfillProgress = "Added \(progress.pushed) so far…"
            } else if progress.total > 0 {
                routeBackfillProgress = "Checked \(progress.probed) of \(progress.total)…"
            }
        }

        let title = "Add maps to old walks"
        if summary.busy {
            repairResult = RepairResult(title: title, message: "A sync is running. Try again in a moment.")
            return
        }
        let walks = summary.pushed == 1 ? "1 old walk" : "\(summary.pushed) old walks"
        if summary.failed {
            repairResult = RepairResult(
                title: title,
                message: summary.pushed > 0
                    ? "Added maps to \(walks), then lost connection. Run it again to finish."
                    : "Couldn't finish. Check your connection and run it again."
            )
            return
        }
        var message = summary.pushed > 0
            ? "Added maps to \(walks)."
            : "Every walk with a route in Apple Health already has its map."
        if summary.noRoute > 0 {
            let others = summary.noRoute == 1 ? "1 walk has" : "\(summary.noRoute) walks have"
            message += " \(others) no route in Apple Health, so there's no map to add."
        }
        repairResult = RepairResult(title: title, message: message)
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
        SettingsSection("Development") {
            NavigationLink(destination: DeveloperSettingsView()) {
                SettingsRow(
                    icon: "hammer.fill",
                    title: "Developer settings",
                    subtitle: "Debug tools and sync management",
                    tint: MADTheme.Colors.madRed
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            Button {
                appStateManager.resetAppState()
            } label: {
                SettingsRow(
                    icon: "arrow.counterclockwise",
                    title: "Reset onboarding",
                    subtitle: "Return to initial setup flow",
                    tint: .orange,
                    accessory: .none
                )
            }
            .buttonStyle(.plain)
        }
    }
    #endif
}
