import SwiftUI
import Combine
import HealthKit
import UserNotifications

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
        case healthAccess
        /// Flamey asks before the system notification prompt (only while
        /// permission is undecided).
        case notifications
        /// Mile A Day+ offer, once, after setup. Skippable; never a gate.
        case plusOffer
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
    private let personalizationPendingKey = "MAD_PersonalizationPending"
    
    // MARK: - Initialization
    init() {
        loadAppState()
        #if DEBUG
        if let step = Self.previewStep {
            currentState = step
            return
        }
        #endif
        if splashLeadsToMain {
            // Returning user: the app builds UNDER the splash (RootView draws
            // `SplashView` over `.main` while `splashOverlay` is set), so the
            // splash can wait for the real home screen and dissolve into it.
            NotificationPrePrompt.release()
            currentState = .main
            splashOverlay = true
            // Build the home screen only once the splash is on screen
            // (`SplashView` calls `mountMain()`): building it first held the
            // launch on black for ~1.5s.
            mainMounted = false
            startSplashOverlayFallback()
        } else {
            startSplashTimer()
        }
    }

    #if DEBUG
    /// `-MADOnboardingStep auth` opens one setup screen, for simulator reviews.
    private static var previewStep: AppState? {
        switch UserDefaults.standard.string(forKey: "MADOnboardingStep") {
        case "intro": return .onboarding
        case "auth": return .authentication
        case "username": return .usernameSetup
        case "about": return .personalization
        case "health": return .healthAccess
        case "notifications": return .notifications
        case "plus": return .plusOffer
        default: return nil
        }
    }
    #endif

    // MARK: - Public Methods

    /// Set while the splash is drawn over the already-running app (returning
    /// users). `SplashView` clears it via `finishSplashOverlay()` once it has
    /// dissolved into the real dashboard.
    @Published var splashOverlay = false

    /// False only while a cold launch's splash is getting on screen; then
    /// `mountMain()` lets RootView build `MainTabView` under it.
    @Published var mainMounted = true

    func mountMain() {
        DispatchQueue.main.async {
            if !self.mainMounted { self.mainMounted = true }
        }
    }

    /// Whether the splash hands off straight into the app (the same test
    /// `completeSplash` routes on).
    var splashLeadsToMain: Bool {
        !isFirstLaunch && isAuthenticated && userDefaults.bool(forKey: hasCompletedFullSetupKey)
    }

    /// The splash has dissolved into the app; stop drawing it.
    func finishSplashOverlay() {
        DispatchQueue.main.async { self.splashOverlay = false }
    }

    /// Never leave the overlay up: `SplashView` reveals by ~6s at the latest
    /// even if the dashboard never reports ready; this is the backstop for a
    /// splash that never appeared at all.
    private func startSplashOverlayFallback() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            self.mainMounted = true
            self.splashOverlay = false
        }
    }

    /// Complete the splash screen and move to next appropriate state

    func completeSplash() {
        DispatchQueue.main.async {
            // SplashView hands off when its animation ends; the timer below is
            // only a fallback. Whichever comes second must not re-route.
            guard self.currentState == .splash else { return }
            withAnimation(MADTheme.Animation.standard) {
                if self.isFirstLaunch {
                    self.currentState = .onboarding
                } else if !self.isAuthenticated {
                    self.currentState = .authentication
                } else if self.userDefaults.bool(forKey: self.hasCompletedFullSetupKey) {
                    // Quit on the pre-prompt? The app asks the system way now.
                    NotificationPrePrompt.release()
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

        // Heading into setup: hold the system notification prompt for
        // Flamey's pre-prompt (the request below then only reads status).
        // A returning user going straight to the app is asked as before.
        if !(userManager.currentUser.hasUsername && isHealthKitAuthorized()) {
            NotificationPrePrompt.hold()
        }

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

        // Mile A Day+ entitlement for the account that just signed in. The
        // historical import below waits for it: it decides how far back this
        // account reads Apple Health (`HistoryWindow`).
        let plusReady = Task { @MainActor in await PlusStore.shared.refresh() }

        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                if userManager.currentUser.hasUsername {
                    if self.isHealthKitAuthorized() {
                        // Returning user with everything set up
                        self.userDefaults.set(true, forKey: self.hasCompletedFullSetupKey)
                        NotificationPrePrompt.release()
                        self.currentState = .main
                        // Initial sync (if needed) runs in the background — user can
                        // continue using the app while workouts upload. After the
                        // Plus status lands, so the history window is known.
                        Task { @MainActor in
                            await plusReady.value
                            WorkoutSyncService.shared.startInitialSyncIfNeeded()
                        }
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
        // Only a brand-new account sets a username: a "What's New" sheet on
        // its first dashboard would announce the whole app as an update.
        // Existing users who update never pass through here, so they still
        // get it.
        WhatsNewManager.markSeen()
        userDefaults.set(true, forKey: personalizationPendingKey)
        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                self.currentState = .personalization
            }
        }
    }

    /// Complete the personalization step and move straight to health access.
    /// (A "You're all set" screen sat between them once — it repeated the
    /// welcome tour the user had just finished.) Asked of new accounts only:
    /// `personalizationPendingKey` is what brings someone back here if they
    /// quit, and existing users never have it set.
    func completePersonalization() {
        userDefaults.set(false, forKey: personalizationPendingKey)
        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                self.currentState = .healthAccess
            }
        }
    }

    /// Complete health access, then offer Mile A Day+ once before the app.
    /// Setup is already COMPLETE here (the flag is set first), so quitting on
    /// the offer resumes straight to the main app — it is never shown again.
    /// A Founding Runner (already Plus) skips it.
    func completeHealthAccess() {
        userDefaults.set(true, forKey: hasCompletedFullSetupKey)

        // A MainActor task (not DispatchQueue.main) because PlusStore is
        // main-actor isolated.
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            withAnimation(MADTheme.Animation.standard) {
                if settings.authorizationStatus == .notDetermined {
                    self.currentState = .notifications
                } else {
                    NotificationPrePrompt.release()
                    self.routeToPlusOfferOrMain()
                }
            }
        }
    }

    /// Flamey's notification pre-prompt was answered (either way).
    func completeNotifications() {
        NotificationPrePrompt.release()
        Task { @MainActor in
            withAnimation(MADTheme.Animation.standard) {
                self.routeToPlusOfferOrMain()
            }
        }
    }

    /// A Founding Runner (already Plus) skips the offer.
    @MainActor private func routeToPlusOfferOrMain() {
        if PlusStore.shared.isPlus {
            enterMain()
        } else {
            currentState = .plusOffer
        }
    }

    /// The onboarding Mile A Day+ offer was bought or skipped.
    func completePlusOffer() {
        DispatchQueue.main.async {
            withAnimation(MADTheme.Animation.standard) {
                self.enterMain()
            }
        }
    }

    @MainActor private func enterMain() {
        NotificationPrePrompt.release()
        currentState = .main
        // Initial sync runs in the background — non-blocking.
        WorkoutSyncService.shared.startInitialSyncIfNeeded()
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
        } else if userDefaults.bool(forKey: personalizationPendingKey) {
            self.currentState = .personalization
        } else if !isHealthKitAuthorized() {
            self.currentState = .healthAccess
        } else {
            // Everything is actually complete — set the flag and go to main
            self.userDefaults.set(true, forKey: hasCompletedFullSetupKey)
            NotificationPrePrompt.release()
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
        
        // `MAD_IsAuthenticated` is a plain bool stamped at sign-in — it says
        // nothing about whether we still hold credentials. Without the token
        // check, an install whose Keychain no longer has tokens (restore from
        // another device's backup, a wiped Keychain, a half-completed sign-in)
        // boots straight into the main app and every request fails. Requiring
        // real tokens sends those users to the auth screen instead.
        //
        // Deliberately NOT persisted: tokens are stored
        // kSecAttrAccessibleAfterFirstUnlock, so a background launch before the
        // first unlock reads nil even though the session is fine. Keeping this
        // in-memory means such a false negative costs at most one auth-screen
        // launch and heals itself, instead of permanently clearing the flag.
        if savedAuthState && !TokenStore.hasTokens {
            print("[AppStateManager] ⚠️ Marked authenticated but no tokens readable — routing to sign-in")
            isAuthenticated = false
        } else {
            isAuthenticated = savedAuthState
        }
    }
    
    /// Fallback exit from the splash. `SplashView` normally hands off itself
    /// (`SplashView.handoffDelay`) once it has actually been on screen; this
    /// only fires if the view never appeared, so it sits well after that.
    private func startSplashTimer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
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