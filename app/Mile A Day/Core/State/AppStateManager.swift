import SwiftUI
import Combine
import HealthKit

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
        case personalization
        case welcome
        case healthAccess
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
    private let hasCompletedFullSetupKey = "MAD_HasCompletedFullSetup"
    
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
                } else if self.userDefaults.bool(forKey: self.hasCompletedFullSetupKey) {
                    self.currentState = .main
                } else {
                    self.routeToIncompleteSetupStep()
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
    
    /// Complete authentication and route to appropriate setup step
    func completeAuthentication(userManager: UserManager) {
        userDefaults.set(true, forKey: isAuthenticatedKey)
        isAuthenticated = true

        // Now that user is authenticated, enable HealthKit background delivery
        MADBackgroundService.shared.enableBackgroundDeliveryAfterAuth()

        // Register for push notifications
        Task {
            await MADNotificationService.shared.requestAuthorization()
            MADNotificationService.shared.registerForRemoteNotifications()
            await MADNotificationService.shared.syncDailyReminderPrefsToBackend()
        }

        // Stamp this install as a streak-tokens-capable build (idempotent,
        // fire-and-forget). The server still shows nothing until its env
        // switch flips — this only marks that the UI exists here.
        StreakFeatureService.enrollIfNeeded()

        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                if userManager.currentUser.hasUsername {
                    if self.isHealthKitAuthorized() {
                        // Returning user with everything set up
                        self.userDefaults.set(true, forKey: self.hasCompletedFullSetupKey)
                        self.currentState = .main
                        // Initial sync (if needed) runs in the background — user can
                        // continue using the app while workouts upload.
                        WorkoutSyncService.shared.startInitialSyncIfNeeded()
                    } else {
                        self.currentState = .healthAccess
                    }
                } else {
                    self.currentState = .usernameSetup
                }
            }
        }
    }
    
    /// Complete username setup and move to the personalization ("about you") step
    func completeUsernameSetup() {
        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                self.currentState = .personalization
            }
        }
    }

    /// Complete the optional personalization step and move to the welcome screen.
    /// This step is optional (data-collection only) so it is intentionally NOT
    /// part of the `hasCompletedFullSetup` gate — a user who quits here still
    /// resumes straight to the main app on next launch.
    func completePersonalization() {
        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                self.currentState = .welcome
            }
        }
    }

    /// Complete welcome screen and move to health access
    func completeWelcome() {
        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                self.currentState = .healthAccess
            }
        }
    }

    /// Complete health access and check if workout sync is needed
    func completeHealthAccess() {
        userDefaults.set(true, forKey: hasCompletedFullSetupKey)

        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                self.currentState = .main
                // Initial sync runs in the background — non-blocking.
                WorkoutSyncService.shared.startInitialSyncIfNeeded()
            }
        }
    }

    /// Sign out user (for testing purposes)
    func signOut() {
        // Unregister device token before signing out
        Task {
            await MADNotificationService.shared.unregisterDeviceToken()
            // Clear the friend-request badge — otherwise the previous account's
            // count sits on the icon through sign-in as the next user.
            await MADNotificationService.shared.setAppBadge(0)
        }

        userDefaults.set(false, forKey: isAuthenticatedKey)
        userDefaults.set(false, forKey: hasCompletedFullSetupKey)
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
        userDefaults.removeObject(forKey: hasCompletedFullSetupKey)
        
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

    /// Check if HealthKit write authorization has been granted
    private func isHealthKitAuthorized() -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let status = HKHealthStore().authorizationStatus(for: HKObjectType.workoutType())
        return status == .sharingAuthorized
    }

    /// Route to the first incomplete setup step for an authenticated user
    private func routeToIncompleteSetupStep() {
        let user = UserManager.shared.currentUser

        if !user.hasUsername {
            self.currentState = .usernameSetup
        } else if !isHealthKitAuthorized() {
            self.currentState = .healthAccess
        } else {
            // Everything is actually complete — set the flag and go to main
            self.userDefaults.set(true, forKey: hasCompletedFullSetupKey)
            self.currentState = .main
        }
    }

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