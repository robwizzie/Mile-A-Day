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
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // Schedule background refresh when app enters background
                    MADBackgroundService.shared.appDidEnterBackground()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Handle app returning to foreground
                    MADBackgroundService.shared.appWillEnterForeground()
                    // Register for push notifications (handles first-time + token rotation)
                    if AppStateManager.shared.isAuthenticated {
                        Task {
                            // Proactively refresh the access token if it's within
                            // 1 day of expiry. This avoids first-request races on
                            // cold start (where the token check passes but the
                            // server has the token marked stale).
                            await refreshTokenIfNeededOnForeground()
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
}

/// On foreground, refresh the access token if it's within 1 day of expiry.
/// 30-day access tokens mean this rarely fires, but it ensures the first
/// post-foreground API call doesn't race a stale token against the server.
@MainActor
private func refreshTokenIfNeededOnForeground() async {
    guard let access = TokenStore.accessToken else { return }
    // 86_400s = 1 day buffer — refresh if expiring within this window.
    guard TokenUtils.isTokenExpired(access, bufferSeconds: 86_400) else { return }
    guard let refresh = TokenStore.refreshToken else { return }
    do {
        let (newAccess, newRefresh) = try await TokenRefreshService.refreshAccessToken(refreshToken: refresh)
        UserManager.shared.setTokens(accessToken: newAccess, refreshToken: newRefresh)
        MADWatchBridge.shared.pushSnapshotIfReady()
        print("[Mile_A_DayApp] ✅ Foreground token refresh succeeded")
    } catch {
        print("[Mile_A_DayApp] ⚠️ Foreground token refresh failed: \(error). Will rely on next request to retry/sign out.")
    }
}
