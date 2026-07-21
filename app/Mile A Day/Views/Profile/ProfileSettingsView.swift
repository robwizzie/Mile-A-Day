import SwiftUI

/// Standalone settings page pushed from the Profile header's gear icon.
/// Keeps all account-management rows in one place without crowding the
/// profile tab picker.
struct ProfileSettingsView: View {
    @ObservedObject var userManager: UserManager
    @ObservedObject var friendService: FriendService
    @Environment(\.appStateManager) var appStateManager

    let onLogout: () -> Void
    let onDeleteAccount: () -> Void
    let onRecalibrateStreak: () -> Void
    let isRecalibratingStreak: Bool
    let onPrivacySettings: () -> Void

    /// What's New sheet — reopenable here anytime (auto-presents once per
    /// release from the Dashboard).
    @State private var showWhatsNew = false

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

            Button(action: onPrivacySettings) {
                MADSettingsRow(
                    icon: "lock.shield.fill",
                    title: "Privacy Settings",
                    subtitle: "Control what others can see",
                    iconColor: MADTheme.Colors.madRed
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            Button {
                showWhatsNew = true
            } label: {
                MADSettingsRow(
                    icon: "sparkles",
                    title: "What's New",
                    subtitle: "Latest features and updates",
                    iconColor: Color.yellow
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showWhatsNew) {
                WhatsNewView()
            }

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

            Button(action: onLogout) {
                MADSettingsRow(
                    icon: "arrow.right.square.fill",
                    title: "Sign Out",
                    subtitle: "Sign out and return to login",
                    iconColor: MADTheme.Colors.madRed
                )
            }
            .buttonStyle(.plain)

            settingsDivider

            Button(action: onDeleteAccount) {
                MADSettingsRow(
                    icon: "trash.fill",
                    title: "Delete Account",
                    subtitle: "Permanently remove your account and data",
                    iconColor: .red
                )
            }
            .buttonStyle(.plain)
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
