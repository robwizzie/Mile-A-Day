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
            VStack(spacing: MADTheme.Spacing.xl) {
                // Profile Header
                profileHeader
                
                // Stats Summary
                statsSection
                
                // Settings & Actions
                settingsSection
                
                // Development Section (for testing)
                #if DEBUG
                developmentSection
                #endif
            }
            .padding(MADTheme.Spacing.lg)
            .padding(.bottom, 100) // Extra padding for tab bar
        }
        .background(MADTheme.Colors.appBackgroundGradient)
        .scrollContentBackground(.hidden)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        // iOS 26: Liquid Glass is automatic - no toolbar modifiers needed
        .sheet(isPresented: $showingMostMilesDetail) {
            MostMilesDetailView(miles: userManager.currentUser.mostMilesInOneDay, healthManager: healthManager)
        }
        .sheet(isPresented: $showingFastestPaceDetail) {
            FastestPaceDetailView(healthManager: healthManager)
        }
        .alert("Sign Out", isPresented: $showingLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                // Sign out immediately
                userManager.signOut()
                appStateManager.signOut()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }
    
    private var profileHeader: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            // Profile Image
            Button(action: {
                showingEditProfile = true
            }) {
                ZStack {
                    Circle()
                        .fill(MADTheme.Colors.redGradient)
                        .frame(width: 100, height: 100)
                    
                    // Use current profile image state, with fallback to stored images
                    if let image = currentProfileImage ?? getCustomProfileImage() ?? getAppleProfileImage() {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    // Edit overlay with animation
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.black.opacity(0.7))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .frame(width: 100, height: 100)
                }
            }
            .buttonStyle(.plain)
            .shadow(
                color: MADTheme.Shadow.medium.color,
                radius: MADTheme.Shadow.medium.radius,
                x: MADTheme.Shadow.medium.x,
                y: MADTheme.Shadow.medium.y
            )
            
            // Name & Username Section
            VStack(spacing: MADTheme.Spacing.sm) {
                // Display name (first + last)
                if let firstName = userManager.currentUser.firstName, !firstName.isEmpty {
                    let displayName = [firstName, userManager.currentUser.lastName].compactMap { $0 }.joined(separator: " ")
                    Text(displayName)
                        .font(MADTheme.Typography.title2)
                        .fontWeight(.bold)
                        .foregroundColor(MADTheme.Colors.primaryText)
                }

                // Username
                if let username = userManager.currentUser.username {
                    Text("@\(username)")
                        .font(MADTheme.Typography.body)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                }

                Text("MAD Member")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(MADTheme.Colors.secondaryText)
            }

            // Bio
            if let bio = userManager.currentUser.bio, !bio.isEmpty {
                Text(bio)
                    .font(MADTheme.Typography.body)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            // Edit Profile Button
            Button("Edit Profile") {
                showingEditProfile = true
            }
            .font(MADTheme.Typography.headline)
            .fontWeight(.medium)
            .foregroundColor(MADTheme.Colors.madRed)
            .padding(.horizontal, MADTheme.Spacing.lg)
            .padding(.vertical, MADTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MADTheme.CornerRadius.medium)
                    .fill(MADTheme.Colors.madRed.opacity(0.1))
            )
        }
        .padding(MADTheme.Spacing.xl)
        .madCard()
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView(userManager: userManager) {
                showingEditProfile = false
                // Reload profile image after edit
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
        .onAppear {
            // Load profile image: try server URL first, then local cache
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
    }
    
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: MADTheme.Spacing.lg) {
            Text("Your Stats")
                .font(MADTheme.Typography.title3)
                .fontWeight(.bold)
                .foregroundColor(MADTheme.Colors.primaryText)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: MADTheme.Spacing.md) {
                MADStatCard(
                    title: "Current Streak",
                    value: "\(userManager.currentUser.streak)",
                    icon: "flame.fill",
                    iconColor: MADTheme.Colors.warning,
                    backgroundColor: MADTheme.Colors.warning.opacity(0.1)
                )
                
                MADStatCard(
                    title: "Total Miles",
                    value: userManager.currentUser.totalMiles.milesFormatted,
                    icon: "map.fill",
                    iconColor: MADTheme.Colors.madRed,
                    backgroundColor: MADTheme.Colors.madRed.opacity(0.1)
                )
                
                Button {
                    showingFastestPaceDetail = true
                } label: {
                    MADStatCard(
                        title: "Fastest Mile",
                        value: formatPace(bestFastestMilePace),
                        icon: "hare.fill",
                        iconColor: MADTheme.Colors.success,
                        backgroundColor: MADTheme.Colors.success.opacity(0.1)
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    showingMostMilesDetail = true
                } label: {
                    MADStatCard(
                        title: "Best Day",
                        value: userManager.currentUser.mostMilesInOneDay.milesFormatted,
                        icon: "calendar.badge.exclamationmark",
                        iconColor: Color.purple,
                        backgroundColor: Color.purple.opacity(0.1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(MADTheme.Spacing.lg)
        .madCard()
    }
    
    private var settingsSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Text("Settings")
                .font(MADTheme.Typography.title3)
                .fontWeight(.bold)
                .foregroundColor(MADTheme.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: MADTheme.Spacing.sm) {
                NavigationLink(destination: NotificationSettingsView()) {
                    MADSettingsRow(
                        icon: "bell.fill",
                        title: "Notifications",
                        subtitle: "Daily reminders and alerts",
                        iconColor: MADTheme.Colors.madRed
                    )
                }
                
                Divider()
                
                NavigationLink(destination: AppSettingsView(healthManager: healthManager)) {
                    MADSettingsRow(
                        icon: "gear.circle.fill",
                        title: "App Settings",
                        subtitle: "Timezone and tracking preferences",
                        iconColor: Color.gray
                    )
                }
                
                Divider()
                
                MADSettingsRow(
                    icon: "heart.fill",
                    title: "Health Data",
                    subtitle: "HealthKit integration",
                    iconColor: Color.red
                )
                
                Divider()
                
                NavigationLink(destination: FriendsListView()) {
                    MADSettingsRow(
                        icon: "person.2.fill",
                        title: "Friends & Leaderboard",
                        subtitle: "Social features",
                        iconColor: Color.blue
                    )
                }

                Divider()

                NavigationLink(destination: BlockedUsersView(friendService: FriendService())) {
                    MADSettingsRow(
                        icon: "hand.raised.fill",
                        title: "Blocked Users",
                        subtitle: "Manage blocked accounts",
                        iconColor: Color.orange
                    )
                }

                Divider()
                
                Button(action: { showingPrivacySettings = true }) {
                    MADSettingsRow(
                        icon: "lock.shield.fill",
                        title: "Privacy Settings",
                        subtitle: "Control what others can see",
                        iconColor: MADTheme.Colors.madRed
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Divider()
                
                MADSettingsRow(
                    icon: "questionmark.circle.fill",
                    title: "Help & Support",
                    subtitle: "FAQ and contact",
                    iconColor: Color.orange
                )
                
                Divider()
                
                Button(action: {

                    showingLogoutConfirmation = true
                }) {
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
        .padding(MADTheme.Spacing.lg)
        .madCard()
    }
    
    #if DEBUG
    private var developmentSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Text("Development")
                .font(MADTheme.Typography.title3)
                .fontWeight(.bold)
                .foregroundColor(MADTheme.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: MADTheme.Spacing.sm) {
                NavigationLink(destination: DeveloperSettingsView()) {
                    HStack {
                        Image(systemName: "wrench.and.screwdriver")
                            .foregroundColor(MADTheme.Colors.madRed)
                        Text("Developer Settings")
                            .foregroundColor(MADTheme.Colors.primaryText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(MADTheme.Colors.secondaryText)
                    }
                    .padding()
                    .background(MADTheme.Colors.primaryBackground)
                    .cornerRadius(MADTheme.CornerRadius.medium)
                }

                Button("Reset Onboarding") {
                    appStateManager.resetAppState()
                }
                .madSecondaryButton(fullWidth: true)

                Button("Sign Out") {
                    showingLogoutConfirmation = true
                }
                .madPrimaryButton(fullWidth: true)
            }
        }
        .padding(MADTheme.Spacing.lg)
        .madCard(backgroundColor: MADTheme.Colors.madRed.opacity(0.05))
    }
    #endif
    
    // Helper function for pace formatting
    /// Best fastest pace from all sources (user stored + HealthKit live)
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
            return "Not yet recorded" 
        }
        
        let totalMinutes = pace
        let minutes = Int(totalMinutes)
        let seconds = Int((totalMinutes - Double(minutes)) * 60)
        let formatted = String(format: "%d:%02d /mi", minutes, seconds)
        return formatted
    }
    
    // Helper function to get custom profile image
    private func getCustomProfileImage() -> UIImage? {
        // Load custom profile image from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "customProfileImage"),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }
    
    // Helper function to get Apple profile image
    private func getAppleProfileImage() -> UIImage? {
        return userManager.getAppleProfileImage()
    }
    
}

/// MAD-themed stat card component
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
                    .foregroundColor(MADTheme.Colors.primaryText)
                
                Text(title)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(MADTheme.Spacing.md)
        .madCard()
    }
}

/// MAD-themed settings row component
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
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                Text(title)
                    .font(MADTheme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(MADTheme.Colors.primaryText)
                
                Text(subtitle)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(MADTheme.Colors.secondaryText)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(MADTheme.Colors.secondaryText)
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