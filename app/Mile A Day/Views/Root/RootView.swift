import SwiftUI

struct RootView: View {
    @StateObject private var appStateManager = AppStateManager()
    @StateObject private var healthManager = HealthKitManager()
    @StateObject private var userManager = UserManager()
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
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                
            case .main:
                MainTabView()
                    .environmentObject(healthManager)
                    .environmentObject(userManager)
                    .environmentObject(notificationService)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .environment(\.appStateManager, appStateManager)
        .animation(MADTheme.Animation.standard, value: appStateManager.currentState)
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
        // Configure navigation bar appearance to match MAD theme
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(MADTheme.Colors.primaryBackground)
        navBarAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(MADTheme.Colors.primaryText),
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold)
        ]
        navBarAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(MADTheme.Colors.primaryText),
            .font: UIFont.systemFont(ofSize: 32, weight: .bold)
        ]
        
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        
        // Configure tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(MADTheme.Colors.primaryBackground)
        
        // Normal state
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(MADTheme.Colors.secondaryText)
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(MADTheme.Colors.secondaryText)
        ]
        
        // Selected state
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(MADTheme.Colors.madRed)
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(MADTheme.Colors.madRed)
        ]
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }
    
    private func requestHealthPermissions() {
        // This will be handled by HealthKitManager when the main app loads
        healthManager.requestPermissions()
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