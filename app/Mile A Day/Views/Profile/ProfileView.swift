import SwiftUI

struct ProfileView: View {
    @Environment(\.appStateManager) var appStateManager
    @ObservedObject var userManager: UserManager
    @ObservedObject var healthManager: HealthKitManager
    
    @State private var showingMostMilesDetail = false
    @State private var showingFastestPaceDetail = false
    @State private var showingLogoutConfirmation = false
    @State private var showingUsernameSetup = false
    @State private var showingBioEditor = false
    @State private var showingUsernameEditor = false
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
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
        }
        .background(MADTheme.Colors.secondaryBackground)
        .preferredColorScheme(nil) // Allow system to control color scheme
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
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
                showingImagePicker = true
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
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(.white)
                            .transition(.scale.combined(with: .opacity))
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
                                .scaleEffect(0.9)
                                .animation(.easeInOut(duration: 0.2), value: currentProfileImage)
                        }
                    }
                    .frame(width: 100, height: 100)
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(currentProfileImage != nil ? 1.0 : 0.95)
            .animation(.easeInOut(duration: 0.3), value: currentProfileImage)
            .shadow(
                color: MADTheme.Shadow.medium.color,
                radius: MADTheme.Shadow.medium.radius,
                x: MADTheme.Shadow.medium.x,
                y: MADTheme.Shadow.medium.y
            )
            
            // Username Section (main name under profile picture)
            VStack(spacing: MADTheme.Spacing.sm) {
                // Username as main name
                if let username = userManager.currentUser.username {
                    Text("@\(username)")
                        .font(MADTheme.Typography.title2)
                        .fontWeight(.bold)
                        .foregroundColor(MADTheme.Colors.primaryText)
                } else {
                    Text("Set Username")
                        .font(MADTheme.Typography.title2)
                        .fontWeight(.bold)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                }
                
                // Edit Username Button
                if userManager.currentUser.username != nil {
                    Button("Edit Username") {
                        showingUsernameEditor = true
                    }
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(MADTheme.Colors.madRed)
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.vertical, MADTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                            .fill(MADTheme.Colors.madRed.opacity(0.1))
                    )
                } else {
                    Button("Set Username") {
                        showingUsernameSetup = true
                    }
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(MADTheme.Colors.madRed)
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.vertical, MADTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                            .fill(MADTheme.Colors.madRed.opacity(0.1))
                    )
                }
                
                
                Text("MAD Member")
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(MADTheme.Colors.secondaryText)
            }
            
            // Bio Section
            VStack(spacing: MADTheme.Spacing.sm) {
                if let bio = userManager.currentUser.bio, !bio.isEmpty {
                    VStack(spacing: MADTheme.Spacing.sm) {
                        Text(bio)
                            .font(MADTheme.Typography.body)
                            .foregroundColor(MADTheme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                        
                        Button("Edit Bio") {
                            showingBioEditor = true
                        }
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(MADTheme.Colors.madRed)
                        .padding(.horizontal, MADTheme.Spacing.sm)
                        .padding(.vertical, MADTheme.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                                .fill(MADTheme.Colors.madRed.opacity(0.1))
                        )
                    }
                } else {
                    Button("Create Bio") {
                        showingBioEditor = true
                    }
                    .font(MADTheme.Typography.body)
                    .foregroundColor(MADTheme.Colors.madRed)
                    .fontWeight(.medium)
                    .padding(.horizontal, MADTheme.Spacing.md)
                    .padding(.vertical, MADTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                            .fill(MADTheme.Colors.madRed.opacity(0.1))
                    )
                }
            }
        }
        .padding(MADTheme.Spacing.xl)
        .madCard()
        .sheet(isPresented: $showingUsernameSetup) {
            UsernameSetupView()
                .environmentObject(userManager)
        }
        .sheet(isPresented: $showingBioEditor) {
            BioEditorView(
                bio: userManager.currentUser.bio ?? "",
                onSave: { newBio in
                    // Update local data immediately
                    userManager.currentUser.bio = newBio.isEmpty ? nil : newBio
                    userManager.saveUserData()
                    
                    // Sync to backend
                    syncBioToBackend(newBio)
                    
                    showingBioEditor = false
                },
                onCancel: {
                    showingBioEditor = false
                }
            )
        }
        .sheet(isPresented: $showingUsernameEditor) {
            UsernameEditorView(
                currentUsername: userManager.currentUser.username ?? "",
                onSave: { newUsername in
                    updateUsername(newUsername)
                    showingUsernameEditor = false
                },
                onCancel: {
                    showingUsernameEditor = false
                }
            )
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
                .onDisappear {
                    // Reset selected image when picker is dismissed
                    selectedImage = nil
                }
        }
        .sheet(isPresented: $showingPrivacySettings) {
            PrivacySettingsView()
        }
        .onChange(of: selectedImage) { oldImage, newImage in
            if let image = newImage {
                // Update UI immediately with animation
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentProfileImage = image
                }
                // Save to storage
                saveCustomProfileImage(image)
            }
        }
        .onAppear {
            // Load current profile image on appear
            currentProfileImage = getCustomProfileImage() ?? getAppleProfileImage()
            
            // Log user data when profile view appears
            logUserData()
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
                    // Log user data for testing
                    logUserData()
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
        print("[ProfileView] formatPace called with value: \(pace)")
        
        guard pace > 0 else { 
            print("[ProfileView] Returning 'Not yet recorded'")
            return "Not yet recorded" 
        }
        
        let totalMinutes = pace
        let minutes = Int(totalMinutes)
        let seconds = Int((totalMinutes - Double(minutes)) * 60)
        let formatted = String(format: "%d:%02d /mi", minutes, seconds)
        print("[ProfileView] Formatted pace: \(formatted)")
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
    
    // Helper function to save custom profile image
    private func saveCustomProfileImage(_ image: UIImage) {
        if let data = image.jpegData(compressionQuality: 0.8) {
            UserDefaults.standard.set(data, forKey: "customProfileImage")
        }
    }
    
    // Helper function to log user data
    private func logUserData() {
        print("🔍 Current User Data:")
        print("  - Name: \(userManager.currentUser.name)")
        print("  - Username: \(userManager.currentUser.username ?? "nil")")
        print("  - Bio: \(userManager.currentUser.bio ?? "nil")")
        print("  - Email: \(userManager.currentUser.email ?? "nil")")
        print("  - Apple ID: \(userManager.currentUser.appleId ?? "nil")")
        print("  - Backend User ID: \(userManager.currentUser.backendUserId ?? "nil")")
        print("  - Auth Token: \(userManager.authToken ?? "nil")")
        print("  - Streak: \(userManager.currentUser.streak)")
        print("  - Total Miles: \(userManager.currentUser.totalMiles)")
        print("  - Auth Provider: \(userManager.currentUser.authProvider)")
        print("  - Has Username: \(userManager.currentUser.hasUsername)")
        print("  - Custom Profile Image: \(getCustomProfileImage() != nil ? "Yes" : "No")")
        print("  - Apple Profile Image: \(getAppleProfileImage() != nil ? "Yes" : "No")")
    }
    
    // Helper function to update username
    private func updateUsername(_ username: String) {
        Task {
            do {
                // Update username in backend
                if let authToken = userManager.authToken,
                   let backendUserId = userManager.currentUser.backendUserId {
                    try await UsernameService.updateUsername(username, userId: backendUserId, authToken: authToken)
                }
                
                // Update local user
                await MainActor.run {
                    userManager.currentUser.username = username
                    userManager.saveUserData()
                }
            } catch {
                await MainActor.run {
                    // Handle error - could show an alert
                    print("Failed to update username: \(error)")
                }
            }
        }
    }
    
    // Helper function to sync bio to backend
    private func syncBioToBackend(_ bio: String) {
        Task {
            do {
                if let authToken = userManager.authToken,
                   let backendUserId = userManager.currentUser.backendUserId {
                    try await BioService.updateBio(bio, userId: backendUserId, authToken: authToken)
                    print("✅ Bio synced to backend successfully")
                }
            } catch {
                print("❌ Failed to sync bio to backend: \(error)")
            }
        }
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