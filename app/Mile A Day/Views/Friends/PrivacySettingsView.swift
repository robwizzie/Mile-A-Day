import SwiftUI

/// View for managing user privacy settings
struct PrivacySettingsView: View {
    @State private var privacySettings = PrivacySettings.default
    @State private var isLoading = false
    @State private var showingSuccessMessage = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: MADTheme.Spacing.lg) {
                    // Header
                    headerSection
                    
                    // Privacy Options
                    privacyOptionsSection
                    
                    // Save Button
                    saveButton
                }
                .padding(MADTheme.Spacing.md)
            }
            .navigationTitle("Privacy Settings")
            .navigationBarTitleDisplayMode(.large)
            .alert("Settings Saved", isPresented: $showingSuccessMessage) {
                Button("OK") { }
            } message: {
                Text("Your privacy settings have been updated successfully.")
            }
            .onAppear {
                loadCurrentSettings()
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(MADTheme.Colors.madRed)
            
            Text("Control Your Privacy")
                .font(MADTheme.Typography.title2)
                .foregroundColor(MADTheme.Colors.primaryText)
            
            Text("Choose what information other users can see about you. You can always change these settings later.")
                .font(MADTheme.Typography.body)
                .foregroundColor(MADTheme.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(MADTheme.Spacing.lg)
        .madCard()
    }
    
    // MARK: - Privacy Options Section
    private var privacyOptionsSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            // Public/Private Toggle
            privacyToggle
            
            if privacySettings.isPublic {
                // Public Settings
                publicSettingsSection
            } else {
                // Private Settings Info
                privateSettingsInfo
            }
        }
        .madCard()
    }
    
    // MARK: - Privacy Toggle
    private var privacyToggle: some View {
        VStack(spacing: MADTheme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                    Text("Account Visibility")
                        .font(MADTheme.Typography.headline)
                        .foregroundColor(MADTheme.Colors.primaryText)
                    
                    Text(privacySettings.isPublic ? "Your profile is visible to other users" : "Your profile is private")
                        .font(MADTheme.Typography.caption)
                        .foregroundColor(MADTheme.Colors.secondaryText)
                }
                
                Spacer()
                
                Toggle("", isOn: $privacySettings.isPublic)
                    .toggleStyle(SwitchToggleStyle(tint: MADTheme.Colors.madRed))
            }
        }
        .padding(MADTheme.Spacing.md)
    }
    
    // MARK: - Public Settings Section
    private var publicSettingsSection: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Divider()
            
            Text("What others can see:")
                .font(MADTheme.Typography.subheadline)
                .foregroundColor(MADTheme.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: MADTheme.Spacing.sm) {
                // Always visible (username and profile picture)
                HStack {
                    Image(systemName: "person.circle")
                        .foregroundColor(MADTheme.Colors.madRed)
                        .frame(width: 24)
                    
                    Text("Username and Profile Picture")
                        .font(MADTheme.Typography.body)
                        .foregroundColor(MADTheme.Colors.primaryText)
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .padding(.horizontal, MADTheme.Spacing.md)
                .padding(.vertical, MADTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                        .fill(MADTheme.Colors.secondaryBackground)
                )
                
                // Configurable settings
                VStack(spacing: MADTheme.Spacing.sm) {
                    PrivacyToggleRow(
                        title: "Running Stats",
                        description: "Total miles, streak, best pace",
                        icon: "chart.line.uptrend.xyaxis",
                        isOn: $privacySettings.showStats
                    )
                    
                    PrivacyToggleRow(
                        title: "Achievement Badges",
                        description: "Your earned badges and milestones",
                        icon: "medal.fill",
                        isOn: $privacySettings.showBadges
                    )
                    
                    PrivacyToggleRow(
                        title: "Current Streak",
                        description: "Your current running streak",
                        icon: "flame.fill",
                        isOn: $privacySettings.showStreak
                    )
                }
            }
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.bottom, MADTheme.Spacing.md)
    }
    
    // MARK: - Private Settings Info
    private var privateSettingsInfo: some View {
        VStack(spacing: MADTheme.Spacing.md) {
            Divider()
            
            VStack(spacing: MADTheme.Spacing.sm) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 32))
                    .foregroundColor(MADTheme.Colors.secondaryText)
                
                Text("Private Account")
                    .font(MADTheme.Typography.headline)
                    .foregroundColor(MADTheme.Colors.primaryText)
                
                Text("When your account is private, only your username and profile picture are visible to other users. All other information is hidden.")
                    .font(MADTheme.Typography.body)
                    .foregroundColor(MADTheme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(MADTheme.Spacing.lg)
        }
    }
    
    // MARK: - Save Button
    private var saveButton: some View {
        Button(action: saveSettings) {
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save Settings")
                }
            }
        }
        .madPrimaryButton(fullWidth: true)
        .disabled(isLoading)
    }
    
    // MARK: - Helper Methods
    private func loadCurrentSettings() {
        // Load current privacy settings from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "privacySettings"),
           let settings = try? JSONDecoder().decode(PrivacySettings.self, from: data) {
            privacySettings = settings
        }
    }
    
    private func saveSettings() {
        isLoading = true
        
        // Save to UserDefaults (in a real app, this would be sent to the backend)
        if let data = try? JSONEncoder().encode(privacySettings) {
            UserDefaults.standard.set(data, forKey: "privacySettings")
        }
        
        // Simulate API call delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isLoading = false
            showingSuccessMessage = true
        }
    }
}

// MARK: - Privacy Toggle Row Component
struct PrivacyToggleRow: View {
    let title: String
    let description: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: MADTheme.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(MADTheme.Colors.madRed)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: MADTheme.Spacing.xs) {
                Text(title)
                    .font(MADTheme.Typography.body)
                    .foregroundColor(MADTheme.Colors.primaryText)
                
                Text(description)
                    .font(MADTheme.Typography.caption)
                    .foregroundColor(MADTheme.Colors.secondaryText)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: MADTheme.Colors.madRed))
        }
        .padding(.horizontal, MADTheme.Spacing.md)
        .padding(.vertical, MADTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MADTheme.CornerRadius.small)
                .fill(MADTheme.Colors.secondaryBackground)
        )
    }
}

// MARK: - Preview
struct PrivacySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        PrivacySettingsView()
    }
}
