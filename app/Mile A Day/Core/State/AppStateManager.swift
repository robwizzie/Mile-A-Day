import SwiftUI
import Combine

/// App State Manager
/// Manages the overall app flow: Splash -> Onboarding -> Auth -> Main App
class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    
    // MARK: - App States
    enum AppState {
        case splash
        case onboarding
        case authentication
        case usernameSetup
        case workoutSync
        case main
    }
    
    // MARK: - Published Properties
    @Published var currentState: AppState = .splash
    @Published var isFirstLaunch: Bool = true
    @Published var isAuthenticated: Bool = false
    @Published var showOnboarding: Bool = false
    
    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    private let hasLaunchedKey = "MAD_HasLaunchedBefore"
    private let hasCompletedOnboardingKey = "MAD_HasCompletedOnboarding"
    private let isAuthenticatedKey = "MAD_IsAuthenticated"
    
    // MARK: - Initialization
    init() {
        loadAppState()
        startSplashTimer()
    }
    
    // MARK: - Public Methods
    
    /// Complete the splash screen and move to next appropriate state
    func completeSplash() {
        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                if self.isFirstLaunch {
                    self.currentState = .onboarding
                } else if !self.isAuthenticated {
                    self.currentState = .authentication
                } else {
                    self.currentState = .main
                }
            }
        }
    }
    
    /// Complete onboarding and move to authentication
    func completeOnboarding() {
        userDefaults.set(true, forKey: hasCompletedOnboardingKey)
        userDefaults.set(false, forKey: hasLaunchedKey)
        isFirstLaunch = false
        
        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                self.currentState = .authentication
            }
        }
    }
    
    /// Complete authentication and check if username setup is needed
    func completeAuthentication() {
        userDefaults.set(true, forKey: isAuthenticatedKey)
        isAuthenticated = true
        
        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                // Check if user needs to set up username
                // This will be determined by the UserManager
                self.currentState = .usernameSetup
            }
        }
    }
    
    /// Complete authentication with username check
    func completeAuthentication(userManager: UserManager) {
        userDefaults.set(true, forKey: isAuthenticatedKey)
        isAuthenticated = true

        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                // Check if user already has a username
                if userManager.currentUser.hasUsername {
                    // Check if first-time workout sync is needed
                    if WorkoutSyncService.shared.isFirstTimeSync() {
                        self.currentState = .workoutSync
                    } else {
                        self.currentState = .main
                    }
                } else {
                    self.currentState = .usernameSetup
                }
            }
        }
    }
    
    /// Complete username setup and check if workout sync is needed
    func completeUsernameSetup() {
        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                // Check if first-time workout sync is needed
                if WorkoutSyncService.shared.isFirstTimeSync() {
                    self.currentState = .workoutSync
                } else {
                    self.currentState = .main
                }
            }
        }
    }

    /// Complete workout sync and move to main app
    func completeWorkoutSync() {
        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                self.currentState = .main
            }
        }
    }
    
    /// Sign out user (for testing purposes)
    func signOut() {
        userDefaults.set(false, forKey: isAuthenticatedKey)
        isAuthenticated = false
        
        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                self.currentState = .authentication
            }
        }
    }
    
    /// Reset app state (for testing purposes)
    func resetAppState() {
        userDefaults.removeObject(forKey: hasLaunchedKey)
        userDefaults.removeObject(forKey: hasCompletedOnboardingKey)
        userDefaults.removeObject(forKey: isAuthenticatedKey)
        
        isFirstLaunch = true
        isAuthenticated = false
        
        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                self.currentState = .splash
                self.startSplashTimer()
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Load the current app state from UserDefaults
    private func loadAppState() {
        let hasLaunched = userDefaults.bool(forKey: hasLaunchedKey)
        let hasCompletedOnboarding = userDefaults.bool(forKey: hasCompletedOnboardingKey)
        let savedAuthState = userDefaults.bool(forKey: isAuthenticatedKey)
        
        // Determine if this is the first launch
        if !hasLaunched && !hasCompletedOnboarding {
            isFirstLaunch = true
            userDefaults.set(true, forKey: hasLaunchedKey)
        } else {
            isFirstLaunch = false
        }
        
        isAuthenticated = savedAuthState
    }
    
    /// Start the splash screen timer
    private func startSplashTimer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.completeSplash()
        }
    }
}

/// Environment key for AppStateManager
struct AppStateManagerKey: EnvironmentKey {
    static let defaultValue = AppStateManager()
}

extension EnvironmentValues {
    var appStateManager: AppStateManager {
        get { self[AppStateManagerKey.self] }
        set { self[AppStateManagerKey.self] = newValue }
    }
}