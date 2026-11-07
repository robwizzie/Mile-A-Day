import SwiftUI

/// Every "who sees what" control, one page, and the only home of each.
///
/// These used to be spread across three places: Stealth Mode, Privacy
/// Settings, and the sharing half of the Notifications page (which this page
/// then linked back to as "Workouts & Posts"), so "Share route maps" and the
/// audience picker had two doors. They all live here now.
///
/// What saves where:
/// - The sharing toggles, audience and flyover choice are the privacy half of
///   `NotificationPreferences`. They save as you change them (debounced), and
///   send ONLY `sharingPayload`'s keys, so this page can't touch an alert.
/// - Hide start & end owns its own write (`RoutePrivacySettingRow`).
/// - Stealth Mode: `StealthModeView` is the only thing that PUTs it.
/// - Map on new posts and the photo prompt are local (`@AppStorage`).
struct PrivacyHubView: View {
    @ObservedObject var friendService: FriendService

    @AppStorage(RouteSharingDefault.key) private var routeDefaultRaw = RouteSharingDefault.ask.rawValue
    /// Local master switch for the post-run photo prompt + auto-sharing the mile.
    @AppStorage("autoShareRunsToFeed") private var autoShareRunsToFeed = true

    @State private var prefs = NotificationPreferences.load()
    /// What the server was last told (or told us). A change only saves when it
    /// differs, so adopting the server's values never echoes them back.
    @State private var lastSaved = NotificationPreferences.load().sharingSnapshot
    @State private var saveTask: Task<Void, Never>?
    @State private var saveFailed = false

    @State private var activeSheet: PrivacySheet?

    /// One `.sheet(item:)` for both modals — two `.sheet`s on one node compete
    /// and one silently never presents.
    enum PrivacySheet: String, Identifiable {
        case stealth
        case accountVisibility
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.lg) {
                if saveFailed {
                    Text("Couldn't save your last change. Check your connection and try again.")
                        .madFont(size: 13, weight: .semibold, design: .rounded)
                        .foregroundColor(MADTheme.Colors.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MADTheme.Spacing.xs)
                }
                audienceSection
                feedSection
                routesSection
                profileSection
                peopleSection
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.md)
            .madTypeCap(.madListCap)
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .stealth:
                StealthModeView()
            case .accountVisibility:
                PrivacySettingsView()
            }
        }
        .onChange(of: prefs.sharingSnapshot) { _, new in
            scheduleSave(new)
        }
        .task { await loadServerSettings() }
        // Leaving (or opening Close Friends) sends a change still waiting on
        // the debounce rather than dropping it.
        .onDisappear { flushPendingSave() }
    }

    // MARK: - Sections

    private var audienceSection: some View {
        SettingsSection(
            "Who can see my workouts",
            footer: "Covers your routes, photos and posts. People you block never see them."
        ) {
            ForEach(Array(WorkoutVisibility.allCases.enumerated()), id: \.element.id) { index, option in
                if index > 0 { SettingsDivider() }
                visibilityOption(option)
            }
        }
    }

    private var feedSection: some View {
        SettingsSection("Feed") {
            SettingsToggleRow(
                title: "Share my walks & runs",
                subtitle: "Friends see them in the feed",
                isOn: $prefs.shareWorkoutsToFeed
            )
            SettingsDivider(inset: 0)
            SettingsToggleRow(
                title: "Photo prompt after a run",
                subtitle: "Off and nothing is posted for you",
                isOn: $autoShareRunsToFeed
            )
            SettingsDivider(inset: 0)
            SettingsToggleRow(
                title: "Post my route when I skip",
                subtitle: "Skipping the photo still posts your route and stats",
                isOn: $prefs.autoPostWithoutPhoto
            )
            SettingsDivider(inset: 0)
            SettingsToggleRow(
                title: "Show when I'm out",
                subtitle: "Friends see you're out, never where you are",
                isOn: $prefs.shareLivePresence
            )
        }
    }

    private var routesSection: some View {
        SettingsSection(
            "Routes",
            footer: "A walk with no map at all? Check Health access and Apple's Route switch."
        ) {
            SettingsToggleRow(
                title: "Show route maps",
                subtitle: prefs.shareRouteMaps
                    ? "Friends see the map on your posts"
                    : "Friends see your posts without the map",
                isOn: $prefs.shareRouteMaps
            )

            // The route is the one part of a post you can only decide BEFORE
            // sharing; someone whose walks all start at their front door
            // shouldn't have to make that call every day.
            if prefs.shareRouteMaps {
                SettingsDivider(inset: 0)
                VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                    Text("Map on new posts")
                        .madFont(size: 16, weight: .medium, design: .rounded)
                        .foregroundColor(.primary)
                    Picker("Map on new posts", selection: $routeDefaultRaw) {
                        ForEach(RouteSharingDefault.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: routeDefaultRaw) { _, _ in MADHaptics.tap() }
                    Text(currentRouteDefault.subtitle)
                        .madFont(size: 12, design: .rounded)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            SettingsDivider(inset: 0)

            // Server-enforced on every route friends are served; owns its
            // own write (`route_privacy_meters`).
            RoutePrivacySettingRow(friendService: friendService)
                .padding(.vertical, 8)

            SettingsDivider(inset: 0)

            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                Text("Route flyovers")
                    .madFont(size: 16, weight: .medium, design: .rounded)
                    .foregroundColor(.primary)
                Picker("Route flyovers", selection: $prefs.flyoverVisibility) {
                    ForEach(FlyoverVisibility.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Text(prefs.flyoverVisibility.subtitle)
                    .madFont(size: 12, design: .rounded)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)

            SettingsDivider(inset: 0)

            // A launcher, not a toggle: enabling asks "also hide routes
            // from…", and `StealthModeView` is the one owner of that write.
            Button { activeSheet = .stealth } label: {
                SettingsRow(
                    icon: "eye.slash.fill",
                    title: "Stealth Mode",
                    subtitle: StealthModeStore.shared.isOn
                        ? "On. Routes you record now never leave your phone"
                        : "Routes recorded while it's on are never shared",
                    tint: StealthModeStore.shared.isOn ? MADTheme.Colors.madRed : .secondary
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var profileSection: some View {
        SettingsSection("Profile") {
            Button { activeSheet = .accountVisibility } label: {
                SettingsRow(
                    icon: "lock.fill",
                    title: "Account visibility",
                    subtitle: "Public or private, and what your profile shows",
                    tint: .purple
                )
            }
            .buttonStyle(.plain)
            SettingsDivider(inset: 0)
            SettingsToggleRow(
                title: "Only show routes with photos",
                subtitle: "On your Posts grid. Friends' feeds can still show them",
                isOn: photoOnlyProfileGridBinding
            )
            SettingsDivider(inset: 0)
            SettingsToggleRow(
                title: "Tagged posts on my grid",
                subtitle: "Off keeps them in your Tagged tab only",
                isOn: $prefs.taggedPostsOnProfile
            )
        }
    }

    private var peopleSection: some View {
        SettingsSection("People") {
            NavigationLink(destination: CloseFriendsListView(friendService: friendService)) {
                SettingsRow(
                    icon: "star.fill",
                    title: "Close Friends",
                    subtitle: "Your private list. They're never told",
                    tint: .green
                )
            }
            .buttonStyle(.plain)

            SettingsDivider()

            NavigationLink(destination: BlockedUsersView()) {
                SettingsRow(
                    icon: "hand.raised.fill",
                    title: "Blocked accounts",
                    tint: .red
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Visibility picker

    /// Green reads "open", red reads "shut": the glyph carries the state.
    private func visibilityTint(_ option: WorkoutVisibility) -> Color {
        switch option {
        case .public: return .green
        case .friends: return .blue
        case .private: return MADTheme.Colors.madRed
        }
    }

    /// One choice. A row rather than a segmented control because each option
    /// needs a sentence to be honest about what it does.
    private func visibilityOption(_ option: WorkoutVisibility) -> some View {
        let selected = prefs.workoutVisibility == option
        let tint = visibilityTint(option)
        return Button {
            guard !selected else { return }
            MADHaptics.tap()
            withAnimation(.easeInOut(duration: 0.15)) {
                prefs.workoutVisibility = option
            }
        } label: {
            HStack(spacing: 12) {
                SettingsGlyph(icon: option.icon, tint: selected ? tint : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .madFont(size: 16, weight: .medium, design: .rounded)
                        .foregroundColor(.primary)
                    Text(option.subtitle)
                        .madFont(size: 12, design: .rounded)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: MADTheme.Spacing.sm)
                Image(systemName: "checkmark")
                    .madFont(size: 14, weight: .bold, maxScale: 1.3)
                    .foregroundColor(tint)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Bindings

    private var photoOnlyProfileGridBinding: Binding<Bool> {
        Binding(
            get: { !prefs.autoPostsOnProfile },
            set: { prefs.autoPostsOnProfile = !$0 }
        )
    }

    private var currentRouteDefault: RouteSharingDefault {
        RouteSharingDefault(rawValue: routeDefaultRaw) ?? .ask
    }

    // MARK: - Saving

    /// Stores locally at once, sends to the server after a short pause so a
    /// run of taps is one request.
    private func scheduleSave(_ snapshot: NotificationPreferences.SharingSnapshot) {
        prefs.saveSharing()
        // Already what the server has (e.g. just adopted from it): nothing
        // new to send. A send already waiting still goes, with current values.
        guard snapshot != lastSaved else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await pushSharing()
        }
    }

    private func flushPendingSave() {
        guard prefs.sharingSnapshot != lastSaved else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in await pushSharing() }
    }

    @MainActor
    private func pushSharing() async {
        let snapshot = prefs.sharingSnapshot
        do {
            _ = try await friendService.updateNotificationSettings(prefs.sharingPayload)
            lastSaved = snapshot
            saveFailed = false
            // The profile grid is server-built, so it can't notice this on
            // its own. Told only after the server has taken the change, or
            // the reload would re-fetch the old grid.
            NotificationCenter.default.post(
                name: NSNotification.Name("MAD_ProfileGridSettingsChanged"),
                object: nil
            )
        } catch {
            saveFailed = true
        }
    }

    /// The server's values win for everything it enforces (showing "Friends
    /// only" to someone the server has as "Everyone" would be a lie).
    @MainActor
    private func loadServerSettings() async {
        guard let settings = try? await friendService.getNotificationSettings() else { return }
        StealthModeStore.shared.apply(settings)
        RoutePrivacySync.adopt(settings)
        var adopted = prefs
        guard adopted.adoptServerValues(settings) else { return }
        // Mark it saved BEFORE it lands, so the change handler doesn't send
        // the server its own values back.
        lastSaved = adopted.sharingSnapshot
        prefs = adopted
        var stored = NotificationPreferences.load()
        stored.adoptServerValues(settings)
        stored.save()
    }
}
