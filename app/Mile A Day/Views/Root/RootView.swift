import SwiftUI

struct RootView: View {
    @StateObject private var appStateManager = AppStateManager.shared
    @StateObject private var healthManager = HealthKitManager()
    @StateObject private var userManager = UserManager.shared
    @StateObject private var notificationService = MADNotificationService.shared
    
    var body: some View {
        ZStack {
            switch appStateManager.currentState {
            case .splash:
                SplashView()
                    .transition(.opacity)
                
            case .onboarding:
                OnboardingView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                
            case .authentication:
                AuthenticationView()
                    .environmentObject(userManager)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                
            case .usernameSetup:
                UsernameSetupView()
                    .environmentObject(userManager)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

            case .workoutSync:
                SyncProgressView(onComplete: {
                    appStateManager.completeWorkoutSync()
                })
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .opacity
                ))

            case .main:
                MainTabView()
                    .environmentObject(healthManager)
                    .environmentObject(userManager)
                    .environmentObject(notificationService)
                    .environment(\.appStateManager, appStateManager)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .environment(\.appStateManager, appStateManager)
        .animation(MADTheme.Animation.standard, value: appStateManager.currentState)
        // Force dark mode app-wide - the app is designed with a dark theme
        .preferredColorScheme(.dark)
        .onAppear {
            setupApp()
        }
    }
    
    private func setupApp() {
        // Apply theme to navigation bar
        configureNavigationAppearance()
        
        // Request health permissions early if needed
        if appStateManager.currentState == .main {
            requestHealthPermissions()
        }
    }
    
    private func configureNavigationAppearance() {
        // iOS 26: Liquid Glass is 100% automatic for both navigation bars AND tab bars
        // Do NOT configure any UIAppearance - it breaks the native glass effect
        if #available(iOS 26.0, *) {
            // Only set tint colors - let system handle all glass effects
            UINavigationBar.appearance().tintColor = UIColor(MADTheme.Colors.madRed)
            UITabBar.appearance().tintColor = UIColor(MADTheme.Colors.madRed)
        } else {
            // iOS 18 and earlier: Custom styling
            let navAppearance = UINavigationBarAppearance()
            navAppearance.configureWithTransparentBackground()
            navAppearance.backgroundColor = .clear
            navAppearance.shadowColor = .clear
            navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
            
            UINavigationBar.appearance().standardAppearance = navAppearance
            UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
            UINavigationBar.appearance().compactAppearance = navAppearance
            UINavigationBar.appearance().tintColor = UIColor(MADTheme.Colors.madRed)
            UINavigationBar.appearance().isTranslucent = true
            
            // Tab bar for older iOS
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithTransparentBackground()
            tabBarAppearance.backgroundColor = .clear
            
            tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(MADTheme.Colors.secondaryText)
            tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor(MADTheme.Colors.secondaryText)
            ]
            tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(MADTheme.Colors.madRed)
            tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor(MADTheme.Colors.madRed)
            ]
            
            UITabBar.appearance().standardAppearance = tabBarAppearance
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        }
    }
    
    private func requestHealthPermissions() {
        // This will be handled by HealthKitManager when the main app loads
        healthManager.requestAuthorization { success in
            if success {
                healthManager.fetchAllWorkoutData()
            }
        }
    }
}

/// Development helper view with reset button for testing flows
struct DevelopmentRootView: View {
    @StateObject private var appStateManager = AppStateManager()
    @State private var showResetConfirmation = false
    
    var body: some View {
        ZStack {
            RootView()
                .environment(\.appStateManager, appStateManager)
            
            // Development controls (only visible in debug builds)
            #if DEBUG
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        showResetConfirmation = true
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                Circle()
                                    .fill(MADTheme.Colors.madRed.opacity(0.8))
                            )
                    }
                    .padding(.trailing, MADTheme.Spacing.md)
                    .padding(.top, MADTheme.Spacing.md)
                }
                Spacer()
            }
            .alert("Reset App State", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    appStateManager.resetAppState()
                }
            } message: {
                Text("This will reset the app to the splash screen and clear all onboarding progress.")
            }
            #endif
        }
    }
}

#Preview("Production") {
    RootView()
}

#Preview("Development") {
    DevelopmentRootView()
}