//
//  Mile_A_DayApp.swift
//  Mile A Day
//
//  Created by Robert Wiscount on 6/7/25.
//

import SwiftUI
import UIKit

@main
struct Mile_A_DayApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
                    // In-app profile links (mileaday://u/<username>) park their
                    // username on DeepLinkRouter so the Friends tab can resolve
                    // it whenever it's ready — covers cold launches where the
                    // tab UI doesn't exist yet.
                    if DeepLinkRouter.shared.handleProfileLink(url) {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_SwitchTab"),
                            object: nil,
                            userInfo: ["tab": 3]
                        )
                        return
                    }

                    // Handle deep links from Live Activities / widgets
                    guard url.scheme == "mileaday" else { return }
                    switch url.host {
                    case "workout":
                        // Covers mileaday://workout (Live Activity tap) and
                        // mileaday://workout/start (widget Start Mile button)
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_OpenWorkoutFromLiveActivity"),
                            object: nil
                        )
                    case "compete":
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_SwitchTab"),
                            object: nil,
                            userInfo: ["tab": 1]
                        )
                    case "friends":
                        // mileaday://friends — Daily Leaderboard widget tap
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_SwitchTab"),
                            object: nil,
                            userInfo: ["tab": 3]
                        )
                    case "competition":
                        // mileaday://competition/<id> — land on that comp's detail
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MAD_SwitchTab"),
                            object: nil,
                            userInfo: ["tab": 1]
                        )
                        let id = url.lastPathComponent
                        if !id.isEmpty, id != "competition" {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("MAD_OpenCompetition"),
                                object: nil,
                                userInfo: ["competitionId": id]
                            )
                        }
                    default:
                        break
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
