import SwiftUI

struct ProfileView: View {
    @Environment(\.appStateManager) var appStateManager
    @ObservedObject var userManager: UserManager
    @ObservedObject var healthManager: HealthKitManager

    @State private var showingMostMilesDetail = false
    @State private var showingFastestPaceDetail = false
    @State private var showingLogoutConfirmation = false
    @State private var showingUsernameSetup = false
    @State private var showingEditProfile = false
    @State private var currentProfileImage: UIImage?
    @State private var showingPrivacySettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: MADTheme.Spacing.lg) {
                // Profile Header (matches friend profile style)
                profileHeader

                // Streak & Goal Row
                streakAndGoalRow

                // Performance Stats
                performanceSection

                // Settings & Actions
                settingsSection

                // Development Section (admin or debug only)
                if isAdminOrDebug {
                    developmentSection
                }
            }
            .padding(.horizontal, MADTheme.Spacing.md)
            .padding(.top, MADTheme.Spacing.sm)
            .padding(.bottom, 100)
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .scrollContentBackground(.hidden)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingMostMilesDetail) {
            MostMilesDetailView(miles: userManager.currentUser.mostMilesInOneDay, healthManager: healthManager)
        }
        .sheet(isPresented: $showingFastestPaceDetail) {
            FastestPaceDetailView(healthManager: healthManager)
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView(userManager: userManager) {
                showingEditProfile = false
                currentProfileImage = getCustomProfileImage() ?? getAppleProfileImage()
            }
        }
        .sheet(isPresented: $showingUsernameSetup) {
            UsernameSetupView()
                .environmentObject(userManager)
        }
        .sheet(isPresented: $showingPrivacySettings) {
            PrivacySettingsView()
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
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Red gradient banner
                LinearGradient(
                    gradient: Gradient(colors: [
                        MADTheme.Colors.madRed.opacity(0.3),
                        Color.clear
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)

                VStack(spacing: MADTheme.Spacing.lg) {
                    // Profile Image with edit overlay
                    Button {
                        showingEditProfile = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 128, height: 128)

                            if let image = currentProfileImage ?? getCustomProfileImage() ?? getAppleProfileImage() {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                            } else {
                                AvatarView(name: userManager.currentUser.name, imageURL: userManager.currentUser.profileImageUrl, size: 120)
                            }

                            // Camera edit badge
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Circle()
                                        .fill(MADTheme.Colors.madRed)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.white)
                                        )
                                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                                }
                            }
                            .frame(width: 120, height: 120)
                        }
                    }
                    .buttonStyle(.plain)
                    .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 5)
                    .padding(.top, 40)

                    // User Info
                    VStack(spacing: MADTheme.Spacing.sm) {
                        // Username (primary, large)
                        if let username = userManager.currentUser.username {
                            Text("@\(username)")
                                .font(MADTheme.Typography.title1)
                                .foregroundColor(MADTheme.Colors.primaryText)
                        }

                        // Display name
                        if let firstName = userManager.currentUser.firstName, !firstName.isEmpty {
                            let displayName = [firstName, userManager.currentUser.lastName].compactMap { $0 }.joined(separator: " ")
                            Text(displayName)
                                .font(MADTheme.Typography.body)
                                .foregroundColor(MADTheme.Colors.secondaryText)
                        }

                        // Bio with quote-style accent
                        if let bio = userManager.currentUser.bio, !bio.isEmpty {
                            HStack(alignment: .top, spacing: MADTheme.Spacing.sm) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(MADTheme.Colors.madRed.opacity(0.5))
                                    .frame(width: 2)

                                Text(bio)
                                    .font(MADTheme.Typography.body)
                                    .foregroundColor(MADTheme.Colors.secondaryText)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.horizontal, MADTheme.Spacing.lg)
                            .padding(.top, MADTheme.Spacing.xs)
                        }
                    }

                    // Edit Profile Button
                    Button {
                        showingEditProfile = true
                    } label: {
                        HStack(spacing: MADTheme.Spacing.sm) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Edit Profile")
                                .font(MADTheme.Typography.headline)
                        }
                        .foregroundColor(MADTheme.Colors.madRed)
                        .padding(.horizontal, MADTheme.Spacing.xl)
                        .padding(.vertical, MADTheme.Spacing.sm + 2)
                        .background(
                            Capsule()
                                .fill(MADTheme.Colors.madRed.opacity(0.15))
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.horizontal, MADTheme.Spacing.lg)
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.bottom, MADTheme.Spacing.lg)
            }
        }
        .madLiquidGlass()
        .onAppear {
            loadProfileImage()
        }
    }

    // MARK: - Streak & Goal Row

    private var streakAndGoalRow: some View {
        let hasCompletedToday = userManager.currentUser.isStreakActiveToday
        let streak = userManager.currentUser.streak
        let goalMiles = userManager.currentUser.goalMiles

        return HStack(spacing: MADTheme.Spacing.md) {
            // Streak Card
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                Text("STREAK")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(hasCompletedToday ? .green : .orange)
                    .tracking(1.5)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(streak)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("days")
                        .font(MADTheme.Typography.small)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 18))
                        .foregroundColor(hasCompletedToday ? .green : .orange)
                    Spacer()
                    if hasCompletedToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(MADTheme.Spacing.md)
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(
                        LinearGradient(
                            colors: hasCompletedToday
                                ? [Color.green.opacity(0.15), Color.green.opacity(0.05)]
                                : [Color.orange.opacity(0.15), Color.orange.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                            .stroke(
                                hasCompletedToday ? Color.green.opacity(0.2) : Color.orange.opacity(0.2),
                                lineWidth: 1
                            )
                    )
            )

            // Daily Goal Card
            VStack(alignment: .leading, spacing: MADTheme.Spacing.sm) {
                Text("DAILY GOAL")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .tracking(1.5)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", goalMiles))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("mi")
                        .font(MADTheme.Typography.small)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack {
                    Image(systemName: hasCompletedToday ? "checkmark.circle.fill" : "target")
                        .font(.system(size: 18))
                        .foregroundColor(hasCompletedToday ? .green : MADTheme.Colors.madRed)
                    Spacer()
                }
            }
            .padding(MADTheme.Spacing.md)
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .madLiquidGlass()
        }
    }

    // MARK: - Performance Stats

    private var performanceSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("Performance")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MADTheme.Spacing.md) {
                MADStatCard(
                    title: "Total Miles",
                    value: userManager.currentUser.totalMiles.milesFormatted,
                    icon: "map.fill",
                    iconColor: .blue,
                    backgroundColor: .blue.opacity(0.1)
                )

                Button {
                    showingFastestPaceDetail = true
                } label: {
                    MADStatCard(
                        title: "Best Pace",
                        value: formatPace(bestFastestMilePace),
                        icon: "timer",
                        iconColor: MADTheme.Colors.madRed,
                        backgroundColor: MADTheme.Colors.madRed.opacity(0.1)
                    )
                }
                .buttonStyle(ScaleButtonStyle())

                Button {
                    showingMostMilesDetail = true
                } label: {
                    MADStatCard(
                        title: "Best Day",
                        value: userManager.currentUser.mostMilesInOneDay.milesFormatted,
                        icon: "calendar",
                        iconColor: .green,
                        backgroundColor: .green.opacity(0.1)
                    )
                }
                .buttonStyle(ScaleButtonStyle())

                MADStatCard(
                    title: "Avg/Day",
                    value: String(format: "%.1f mi", userManager.currentUser.streak > 0 ? userManager.currentUser.totalMiles / Double(userManager.currentUser.streak) : 0),
                    icon: "chart.bar.fill",
                    iconColor: .purple,
                    backgroundColor: .purple.opacity(0.1)
                )
            }
        }
        .padding(MADTheme.Spacing.md)
        .madLiquidGlass()
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            HStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MADTheme.Colors.redGradient)
                Text("Settings")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(.primary)
                Spacer()
            }

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

                NavigationLink(destination: AppSettingsView(healthManager: healthManager)) {
                    MADSettingsRow(
                        icon: "gear.circle.fill",
                        title: "App Settings",
                        subtitle: "Timezone and tracking preferences",
                        iconColor: Color.gray
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

                NavigationLink(destination: FriendsListView(friendService: FriendService())) {
                    MADSettingsRow(
                        icon: "person.2.fill",
                        title: "Friends & Leaderboard",
                        subtitle: "Social features",
                        iconColor: Color.blue
                    )
                }

                settingsDivider

                NavigationLink(destination: BlockedUsersView(friendService: FriendService())) {
                    MADSettingsRow(
                        icon: "hand.raised.fill",
                        title: "Blocked Users",
                        subtitle: "Manage blocked accounts",
                        iconColor: Color.orange
                    )
                }

                settingsDivider

                Button(action: { showingPrivacySettings = true }) {
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

                Button {
                    showingLogoutConfirmation = true
                } label: {
                    MADSettingsRow(
                        icon: "arrow.right.square.fill",
                        title: "Sign Out",
                        subtitle: "Sign out and return to login",
                        iconColor: MADTheme.Colors.madRed
                    )
                }
                .buttonStyle(.plain)
            }
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

    private var isAdminOrDebug: Bool {
        #if DEBUG
        return true
        #else
        return userManager.currentUser.role == "admin"
        #endif
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

    // MARK: - Helpers

    private var bestFastestMilePace: TimeInterval {
        let userPace = userManager.currentUser.fastestMilePace
        let hkPace = healthManager.fastestMilePace
        if userPace > 0 && hkPace > 0 {
            return min(userPace, hkPace)
        }
        return userPace > 0 ? userPace : hkPace
    }

    private func formatPace(_ pace: TimeInterval) -> String {
        guard pace > 0 else {
            return "N/A"
        }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func loadProfileImage() {
        if let urlPath = userManager.currentUser.profileImageUrl,
           let url = ProfileImageService.fullImageURL(for: urlPath) {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    await MainActor.run { currentProfileImage = image }
                } else {
                    await MainActor.run {
                        currentProfileImage = getCustomProfileImage() ?? getAppleProfileImage()
                    }
                }
            }
        } else {
            currentProfileImage = getCustomProfileImage() ?? getAppleProfileImage()
        }
    }

    private func getCustomProfileImage() -> UIImage? {
        if let data = UserDefaults.standard.data(forKey: "customProfileImage"),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }

    private func getAppleProfileImage() -> UIImage? {
        return userManager.getAppleProfileImage()
    }
}

// MARK: - Stat Card

struct MADStatCard: View {
    let title: String
    let value: String
    let icon: String
    let iconColor: Color
    let backgroundColor: Color

    var body: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
            }

            VStack(spacing: MADTheme.Spacing.xs) {
                Text(value)
                    .font(MADTheme.Typography.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(title)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.md)
        .background(Color.white.opacity(0.05))
        .cornerRadius(MADTheme.CornerRadius.medium)
    }
}

// MARK: - Settings Row

struct MADSettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MADTheme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, MADTheme.Spacing.xs)
    }
}

#Preview {
    NavigationStack {
        ProfileView(
            userManager: UserManager(),
            healthManager: HealthKitManager()
        )
    }
    .environmentObject(AppStateManager())
}
