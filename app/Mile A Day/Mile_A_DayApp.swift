//
//  Mile_A_DayApp.swift
//  Mile A Day
//
//  Created by Robert Wiscount on 6/7/25.
//

import SwiftUI
import UIKit
import BackgroundTasks

@main
struct Mile_A_DayApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Register background tasks when app launches
        MADBackgroundService.shared.registerBackgroundTasks()
        // Start HealthKit-driven daily steps sync (observer + background delivery).
        DailyStepsSyncService.shared.start()
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .task {
                    await verifyAppleCredentialIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // Schedule background refresh when app enters background
                    MADBackgroundService.shared.appDidEnterBackground()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Handle app returning to foreground
                    MADBackgroundService.shared.appWillEnterForeground()
                    // Re-check Apple Sign In credential — if the user revoked
                    // access while the app was backgrounded, sign them out.
                    Task { await verifyAppleCredentialIfNeeded() }
                    // Register for push notifications (handles first-time + token rotation)
                    if AppStateManager.shared.isAuthenticated {
                        Task {
                            await MADNotificationService.shared.requestAuthorization()
                            MADNotificationService.shared.registerForRemoteNotifications()
                            await MADNotificationService.shared.syncDailyReminderPrefsToBackend()
                            await DailyStepsSyncService.shared.syncNow(force: true)
                        }
                    }
                }
                .onOpenURL { url in
                    // Handle deep links from Live Activities / widgets
                    if url.scheme == "mileaday", url.host == "workout" {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_OpenWorkoutFromLiveActivity"),
                            object: nil
                        )
                    }
                }
        }
    }

    /// Apple requires Sign in with Apple apps to detect when the user has
    /// revoked their credential (Settings → Apple ID → Password & Security
    /// → Apps Using Apple ID → Mile A Day → Stop Using). If revoked, sign
    /// them out so they're returned to the auth screen on next launch.
    private func verifyAppleCredentialIfNeeded() async {
        guard AppStateManager.shared.isAuthenticated,
              let appleId = UserManager.shared.currentUser.appleId,
              !appleId.isEmpty
        else { return }

        let isValid = await AppleSignInManager.isCredentialValid(forUserID: appleId)
        if !isValid {
            await MainActor.run {
                AppStateManager.shared.signOut()
            }
        }
    }
}
