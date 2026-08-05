import SwiftUI

/// Standalone settings page pushed from the Profile header's gear icon.
/// Keeps all account-management rows in one place without crowding the
/// profile tab picker.
struct ProfileSettingsView: View {
    @ObservedObject var userManager: UserManager
    @ObservedObject var friendService: FriendService
    @Environment(\.appStateManager) var appStateManager

    /// The confirmations for these rows are presented HERE, not by ProfileView.
    /// A modal attached to ProfileView never appears while this page is pushed
    /// on top of it — tapping Sign Out looked like a no-op until you hit Back.
    /// Same rule as the sheet/toast gotcha: whoever owns the button renders the
    /// feedback. ProfileView still owns the state so it can run the actions.
    @Binding var showingLogoutConfirmation: Bool
    @Binding var showingDeleteAccountConfirmation: Bool
    @Binding var deleteAccountErrorMessage: String?
    @Binding var recalibrateResultMessage: String?

    let onConfirmLogout: () -> Void
    let onConfirmDeleteAccount: () -> Void
    let onRecalibrateStreak: () -> Void
    let isRecalibratingStreak: Bool
    let isDeletingAccount: Bool

    @State private var showingPrivacySettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.lg) {
                settingsSection
                #if DEBUG
                if showsDevelopmentSection {
                    developmentSection
                }
                #endif
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.vertical, MADTheme.Spacing.md)
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingPrivacySettings) {
            PrivacySettingsView()
        }
        .alert("Sign Out", isPresented: $showingLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive, action: onConfirmLogout)
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Delete Account?", isPresented: $showingDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive, action: onConfirmDeleteAccount)
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

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: NotificationSettingsView()) {
                MADSettingsRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    subtitle: "Daily reminders and alerts",
                    iconColor: MADTheme.Colors.madRed
                )
            }

            settingsDivider

            Button {
                if let url = URL(string: "x-apple-health://") {
                    UIApplication.shared.open(url)
                }
            } label: {
                MADSettingsRow(
                    icon: "heart.fill",
                    title: "Health Data",
                    subtitle: "HealthKit integration",
                    iconColor: Color.red
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            NavigationLink(destination: FitnessConnectionsView(userManager: userManager)) {
                MADSettingsRow(
                    icon: "link.circle.fill",
                    title: "Connected Apps",
                    subtitle: "Strava, Garmin, WHOOP, Oura and more",
                    iconColor: Color.teal
                )
            }

            settingsDivider

            Button(action: onRecalibrateStreak) {
                MADSettingsRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Recalibrate Streak",
                    subtitle: isRecalibratingStreak
                        ? "Re-syncing your workouts…"
                        : "Fix a streak that looks too low",
                    iconColor: Color.green
                )
            }
            .buttonStyle(.plain)
            .disabled(isRecalibratingStreak)

            settingsDivider

            NavigationLink(destination: FriendsListView(friendService: friendService)) {
                MADSettingsRow(
                    icon: "person.2.fill",
                    title: "Friends & Leaderboard",
                    subtitle: "Social features",
                    iconColor: Color.blue
                )
            }

            settingsDivider

            NavigationLink(destination: DailyChallengeSettingsView(friendService: friendService)) {
                MADSettingsRow(
                    icon: "flag.2.crossed.fill",
                    title: "Daily Challenges",
                    subtitle: "Head-to-Head matchup preferences",
                    iconColor: Color.purple
                )
            }

            settingsDivider

            Button { showingPrivacySettings = true } label: {
                MADSettingsRow(
                    icon: "lock.shield.fill",
                    title: "Privacy Settings",
                    subtitle: "Control what others can see",
                    iconColor: MADTheme.Colors.madRed
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            NavigationLink(destination: HelpAndSupportView()) {
                MADSettingsRow(
                    icon: "questionmark.circle.fill",
                    title: "Help & Support",
                    subtitle: "FAQ and contact",
                    iconColor: Color.orange
                )
            }

            settingsDivider

            Button { showingLogoutConfirmation = true } label: {
                MADSettingsRow(
                    icon: "arrow.right.square.fill",
                    title: "Sign Out",
                    subtitle: "Sign out and return to login",
                    iconColor: MADTheme.Colors.madRed
                )
            }
            .buttonStyle(.plain)

            settingsDivider

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
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    private var settingsDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.06))
            .padding(.vertical, MADTheme.Spacing.xs)
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

                settingsDivider

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
