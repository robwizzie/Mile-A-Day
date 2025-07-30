import SwiftUI

struct ProfileView: View {
    @Environment(\.appStateManager) var appStateManager
    @ObservedObject var userManager: UserManager
    @ObservedObject var healthManager: HealthKitManager
    
    @State private var isEditingName = false
    @State private var newName = ""
    @State private var showingMostMilesDetail = false
    @State private var showingFastestPaceDetail = false
    @State private var showingLogoutConfirmation = false
    
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
        }
        .background(MADTheme.Colors.secondaryBackground)
        .preferredColorScheme(nil) // Allow system to control color scheme
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingMostMilesDetail) {
            MostMilesDetailView(miles: userManager.currentUser.mostMilesInOneDay, healthManager: healthManager)
        }
        .sheet(isPresented: $showingFastestPaceDetail) {
            FastestPaceDetailView(pace: healthManager.fastestMilePace)
        }
        .alert("Sign Out", isPresented: $showingLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                appStateManager.signOut()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }
    
    private var profileHeader: some View {
        VStack(spacing: MADTheme.Spacing.lg) {
            // Profile Image
            ZStack {
                Circle()
                    .fill(MADTheme.Colors.redGradient)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "person.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(.white)
            }
            .shadow(
                color: MADTheme.Shadow.medium.color,
                radius: MADTheme.Shadow.medium.radius,
                x: MADTheme.Shadow.medium.x,
                y: MADTheme.Shadow.medium.y
            )
            
            // Name Section
            VStack(spacing: MADTheme.Spacing.sm) {
                if isEditingName {
                    TextField("Your name", text: $newName)
                        .font(MADTheme.Typography.title2)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !newName.isEmpty {
                                userManager.currentUser.name = newName
                                userManager.saveUserData()
                            }
                            isEditingName = false
                        }
                } else {
                    Text(userManager.currentUser.name)
                        .font(MADTheme.Typography.title2)
                        .fontWeight(.bold)
                        .foregroundColor(MADTheme.Colors.primaryText)
                        .onTapGesture {
                            newName = userManager.currentUser.name
                            isEditingName = true
                        }
                }
                
                Text("MAD Member")
                    .font(MADTheme.Typography.callout)
                    .foregroundColor(MADTheme.Colors.madRed)
                    .fontWeight(.medium)
            }
        }
        .padding(MADTheme.Spacing.xl)
        .madCard()
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
                        value: formatPace(healthManager.fastestMilePace),
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
                
                MADSettingsRow(
                    icon: "heart.fill",
                    title: "Health Data",
                    subtitle: "HealthKit integration",
                    iconColor: Color.red
                )
                
                Divider()
                
                MADSettingsRow(
                    icon: "person.2.fill",
                    title: "Friends & Leaderboard",
                    subtitle: "Social features",
                    iconColor: Color.blue
                )
                
                Divider()
                
                MADSettingsRow(
                    icon: "questionmark.circle.fill",
                    title: "Help & Support",
                    subtitle: "FAQ and contact",
                    iconColor: Color.orange
                )
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
    private func formatPace(_ pace: TimeInterval) -> String {
        guard pace > 0 else { return "Not set" }
        
        let totalMinutes = pace
        let minutes = Int(totalMinutes)
        let seconds = Int((totalMinutes - Double(minutes)) * 60)
        
        return String(format: "%d:%02d /mi", minutes, seconds)
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