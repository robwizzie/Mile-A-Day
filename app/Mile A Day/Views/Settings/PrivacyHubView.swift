import SwiftUI

/// Every "who sees what" control, one page.
///
/// These used to be three separate Settings rows — Stealth Mode, Privacy
/// Settings, and the sharing half of "Notifications & Sharing" — so the answer
/// to "who can see my walks?" depended on which row you happened to open. This
/// page SAVES NOTHING of its own (bar the local route-map default it took
/// over, and hide-start-&-end, which lives only here and owns its one write):
/// every other row opens the screen that already owns that setting, so
/// there's still exactly one owner per server write. Stealth Mode especially:
/// `StealthModeView` is the only thing that PUTs it.
struct PrivacyHubView: View {
    @ObservedObject var friendService: FriendService

    @AppStorage(RouteSharingDefault.key) private var routeDefaultRaw = RouteSharingDefault.ask.rawValue

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
                whoSeesSection
                routesSection
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
    }

    // MARK: - Sections

    private var whoSeesSection: some View {
        section("WHO SEES YOUR ACTIVITY", icon: "eye.fill", iconColor: .purple) {
            // The audience, feed sharing, flyovers, live presence and tagged
            // posts all live on the notification page and save with it — so
            // this is a door to it, not a second copy of its toggles.
            NavigationLink(destination: NotificationSettingsView()) {
                MADSettingsRow(
                    icon: "person.2.fill",
                    title: "Workouts & Posts",
                    subtitle: "Who sees your workouts, flyovers and tagged posts",
                    iconColor: .purple
                )
            }

            divider

            Button { activeSheet = .accountVisibility } label: {
                MADSettingsRow(
                    icon: "lock.shield.fill",
                    title: "Account Visibility",
                    subtitle: "Public or private, and what your profile shows",
                    iconColor: MADTheme.Colors.madRed
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var routesSection: some View {
        section("ROUTES", icon: "map.fill", iconColor: .teal) {
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
                Text("New posts only. Missing maps entirely? Check Health Access and Apple's Route switch.")
                    .madFont(size: 11, design: .rounded)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, MADTheme.Spacing.xs)

            divider

            // Hide start & end: server-enforced on every route friends are
            // served, so — unlike the local default above — this row owns a
            // server write of its own (`route_privacy_meters`).
            RoutePrivacySettingRow(friendService: friendService)
                .padding(.bottom, MADTheme.Spacing.xs)

            divider

            Button { activeSheet = .stealth } label: {
                MADSettingsRow(
                    icon: "eye.slash.fill",
                    title: "Stealth Mode",
                    subtitle: StealthModeStore.shared.isOn
                        ? "On — routes are hidden from friends"
                        : "Hide where you walk, for good",
                    iconColor: .gray
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var peopleSection: some View {
        section("PEOPLE", icon: "person.crop.circle", iconColor: .green) {
            NavigationLink(destination: CloseFriendsListView(friendService: friendService)) {
                MADSettingsRow(
                    icon: "star.circle.fill",
                    title: "Close Friends",
                    subtitle: "Your private list — they're never told",
                    iconColor: .green
                )
            }

            divider

            NavigationLink(destination: BlockedUsersView()) {
                MADSettingsRow(
                    icon: "hand.raised.fill",
                    title: "Blocked Accounts",
                    subtitle: "See who you've blocked, or unblock",
                    iconColor: .red
                )
            }
        }
    }

    // MARK: - Chrome (same card as MADSettingsView)

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
                    .accessibilityHidden(true)
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

    private var currentRouteDefault: RouteSharingDefault {
        RouteSharingDefault(rawValue: routeDefaultRaw) ?? .ask
    }
}
